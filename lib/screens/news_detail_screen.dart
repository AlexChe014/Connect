import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/api_config.dart';
import '../config/app_icons.dart';
import '../models/news_comment.dart';
import '../models/news_item.dart';
import '../repositories/comments_repository.dart';
import '../repositories/news_repository.dart';
import '../services/paginated.dart';
import '../widgets/news_people_sheet.dart';

class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({
    super.key,
    required this.news,
  });

  final NewsItem news;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  late NewsItem _news;
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();

  List<NewsComment> _comments = [];
  bool _commentsLoading = true;
  bool _commentsLoadingMore = false;
  String? _commentsNextUrl;
  bool _sendingComment = false;
  bool _likeInFlight = false;
  bool _viewRecordedForOpen = false;

  @override
  void initState() {
    super.initState();
    _news = widget.news;
    _scrollController.addListener(_onScroll);
    _loadComments();
    _refreshNews();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _commentController.dispose();
    super.dispose();
  }

  String? _normalizeNextPageUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final nextUri = Uri.tryParse(trimmed);
    if (nextUri == null) return null;
    final baseUri = Uri.parse(ApiConfig.baseUrl);
    return nextUri
        .replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null,
        )
        .toString();
  }

  String _formatDate(DateTime date) {
    return DateFormat("d MMMM y 'г.'", 'ru_RU').format(date);
  }

  Future<void> _refreshNews() async {
    try {
      final fresh = await NewsRepository.instance.getById(
        _news.id,
        includePeople: true,
      );
      if (!mounted) return;
      setState(() => _news = fresh);
    } catch (_) {
      // оставляем данные из списка
    }
  }

  Future<void> _recordView() async {
    if (_news.id.isEmpty) return;
    try {
      await NewsRepository.instance.addView(_news.id);
      if (!mounted) return;
      setState(() {
        _news = _news.copyWith(
          viewsCount: _news.viewsCount + 1,
          isViewed: true,
        );
      });
    } catch (_) {}
  }

  void _onNewsFullyVisible(VisibilityInfo info) {
    if (info.visibleFraction < 1.0) return;
    if (_viewRecordedForOpen) return;
    _viewRecordedForOpen = true;
    _recordView();
  }

  Future<void> _toggleLike() async {
    if (_likeInFlight || _news.id.isEmpty) return;
    setState(() => _likeInFlight = true);
    final wasLiked = _news.isLiked;
    try {
      if (wasLiked) {
        await NewsRepository.instance.removeLike(_news.id);
        if (!mounted) return;
        setState(() {
          _news = _news.copyWith(
            isLiked: false,
            likesCount: (_news.likesCount - 1).clamp(0, 1 << 30),
          );
        });
      } else {
        await NewsRepository.instance.addLike(_news.id);
        if (!mounted) return;
        setState(() {
          _news = _news.copyWith(
            isLiked: true,
            likesCount: _news.likesCount + 1,
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasLiked ? 'Не удалось убрать лайк' : 'Не удалось поставить лайк',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _likeInFlight = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_commentsLoading || _commentsLoadingMore) return;
    if (_commentsNextUrl == null) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMoreComments();
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsNextUrl = null;
      _comments = [];
    });
    try {
      final page = await CommentsRepository.instance.getByNewsPage(
        newsId: _news.id,
      );
      if (!mounted) return;
      setState(() {
        _comments = page.data;
        _commentsNextUrl = _normalizeNextPageUrl(page.nextPageUrl);
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить комментарии')),
      );
    }
  }

  Future<void> _loadMoreComments() async {
    final url = _normalizeNextPageUrl(_commentsNextUrl);
    if (url == null) return;
    setState(() => _commentsLoadingMore = true);
    try {
      final Paginated<NewsComment> page =
          await CommentsRepository.instance.getByNewsPage(
        newsId: _news.id,
        url: url,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.data];
        _commentsNextUrl = _normalizeNextPageUrl(page.nextPageUrl);
        _commentsLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsLoadingMore = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      await CommentsRepository.instance.create(newsId: _news.id, text: text);
      if (!mounted) return;
      _commentController.clear();
      await _loadComments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить комментарий')),
      );
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage =
        _news.imageUrl != null && _news.imageUrl!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новость'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.wait([_refreshNews(), _loadComments()]);
              },
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  VisibilityDetector(
                    key: Key('news-detail-${_news.id}'),
                    onVisibilityChanged: _onNewsFullyVisible,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_news.author != null) ...[
                          _AuthorHeader(
                            authorName: _news.author!.fullName,
                            avatarUrl: _news.author!.avatarUrl,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          _formatDate(_news.date),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _news.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        if (hasImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              _news.imageUrl!,
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          _news.content,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _StatChip(
                              icon: AppIcons.eye,
                              label: '${_news.viewsCount}',
                              onTap: () => NewsPeopleSheet.show(
                                context,
                                newsId: _news.id,
                                kind: NewsPeopleKind.viewers,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _LikeButton(
                              count: _news.likesCount,
                              isLiked: _news.isLiked,
                              isLoading: _likeInFlight,
                              onPressed: _toggleLike,
                              onCountTap: () => NewsPeopleSheet.show(
                                context,
                                newsId: _news.id,
                                kind: NewsPeopleKind.likers,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Комментарии',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_commentsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Пока нет комментариев',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    )
                  else
                    ..._comments.map(
                      (c) => _CommentTile(
                        comment: c,
                        dateLabel: _formatDate(c.date),
                      ),
                    ),
                  if (_commentsLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Написать комментарий…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      enabled: !_sendingComment,
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendingComment ? null : _sendComment,
                    icon: _sendingComment
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const AppIcon(AppIcons.send, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.dateLabel});

  final NewsComment comment;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final author = comment.author;
    final avatarUrl = author?.avatarUrl?.trim();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
            child: hasAvatar
                ? null
                : AppIcon(AppIcons.user, size: 16, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        author?.fullName ?? 'Пользователь',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment.text, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: child,
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.count,
    required this.isLiked,
    required this.isLoading,
    required this.onPressed,
    this.onCountTap,
  });

  final int count;
  final bool isLiked;
  final bool isLoading;
  final Future<void> Function() onPressed;
  final VoidCallback? onCountTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isLiked ? cs.primary : cs.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLoading
              ? null
              : () async {
                  await onPressed();
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
            child: isLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : AppIcon(AppIcons.like, size: 14, color: iconColor),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onCountTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 4, 4),
            child: Text(
              '$count',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthorHeader extends StatelessWidget {
  const _AuthorHeader({required this.authorName, required this.avatarUrl});

  final String authorName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
          child: hasAvatar
              ? null
              : AppIcon(
                  AppIcons.user,
                  size: 18,
                  color: cs.onPrimaryContainer,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            authorName,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
