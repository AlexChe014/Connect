import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/app_theme.dart';
import '../models/news_comment.dart';
import '../models/news_item.dart';
import '../repositories/comments_repository.dart';
import '../repositories/news_repository.dart';
import '../services/paginated.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_network_image.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_message_text.dart';
import '../widgets/news_people_sheet.dart';

class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, required this.news});

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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
        _commentsNextUrl = page.nextPageUrl;
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsLoading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить комментарии')),
      );
    }
  }

  Future<void> _loadMoreComments() async {
    final url = _commentsNextUrl;
    if (url == null || _commentsLoadingMore) return;
    setState(() => _commentsLoadingMore = true);
    try {
      final Paginated<NewsComment> page = await CommentsRepository.instance
          .getByNewsPage(newsId: _news.id, url: url);
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.data];
        _commentsNextUrl = page.nextPageUrl;
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось отправить комментарий')),
      );
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage =
        _news.imageUrl != null && _news.imageUrl!.trim().isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Новость'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await Future.wait([_refreshNews(), _loadComments()]);
                  },
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      VisibilityDetector(
                        key: Key('news-detail-${_news.id}'),
                        onVisibilityChanged: _onNewsFullyVisible,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBackground
                                .resolveFrom(context),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: AppColors.cardPhotoShadow,
                          ),
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
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _news.title,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (hasImage) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    // Фото целиком (contain) + блюр-копия того же
                                    // снимка по краям — портретные фото не
                                    // обрезаются, но карточка остаётся 16:9.
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                            sigmaX: 24,
                                            sigmaY: 24,
                                          ),
                                          child: AppNetworkImage(
                                            url: _news.imageUrl,
                                            width: double.infinity,
                                            height: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        ColoredBox(
                                          color: Colors.black.withValues(
                                            alpha: 0.18,
                                          ),
                                        ),
                                        AppNetworkImage(
                                          url: _news.imageUrl,
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_news.contentHtml.trim().isNotEmpty ||
                                  _news.content.trim().isNotEmpty)
                                ChatMessageText(
                                  text: _news.contentHtml.trim().isNotEmpty
                                      ? _news.contentHtml
                                      : _news.content,
                                  fontSize: 16,
                                  color:
                                      CupertinoColors.label.resolveFrom(context),
                                ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  _StatChip(
                                    icon: CupertinoIcons.eye,
                                    label: '${_news.viewsCount}',
                                    onTap: () => NewsPeopleSheet.show(
                                      context,
                                      newsId: _news.id,
                                      kind: NewsPeopleKind.viewers,
                                    ),
                                  ),
                                  const Spacer(),
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
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Комментарии',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_commentsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: AppLoadingIndicator(),
                        )
                      else if (_comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: AppEmptyState(message: 'Пока нет комментариев'),
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
                          child: AppLoadingIndicator(size: 20),
                        ),
                    ],
                  ),
                ),
              ),
              _CommentInputBar(
                controller: _commentController,
                isSending: _sendingComment,
                onSend: _sendComment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentInputBar extends StatelessWidget {
  const _CommentInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: CupertinoTextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  placeholder: 'Написать комментарий…',
                  enabled: !isSending,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: isSending ? null : onSend,
              child: isSending
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CupertinoActivityIndicator(),
                    )
                  : const Icon(
                      CupertinoIcons.arrow_up_circle_fill,
                      size: 30,
                    ),
            ),
          ],
        ),
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
    final author = comment.author;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberAvatar(
            displayName: author?.fullName ?? 'Пользователь',
            avatarUrl: author?.avatarUrl,
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground
                    .resolveFrom(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          author?.fullName ?? 'Пользователь',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(comment.text, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.secondaryLabel.resolveFrom(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );

    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

/// Кнопка лайка в стиле iOS: сердце с bounce-анимацией и haptic-откликом.
class _LikeButton extends StatefulWidget {
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
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.isLoading) return;
    HapticFeedback.lightImpact();
    unawaited(_controller.forward(from: 0));
    await widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isLiked
        ? CupertinoColors.systemRed
        : CupertinoColors.secondaryLabel.resolveFrom(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
            child: widget.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CupertinoActivityIndicator(radius: 9),
                  )
                : ScaleTransition(
                    scale: _scale,
                    child: Icon(
                      widget.isLiked
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      size: 22,
                      color: color,
                    ),
                  ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onCountTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 4, 4),
            child: Text(
              '${widget.count}',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
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
    return Row(
      children: [
        MemberAvatar(displayName: authorName, avatarUrl: avatarUrl, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            authorName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
