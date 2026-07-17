import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/app_icons.dart';
import '../config/app_theme.dart';
import '../config/api_config.dart';
import '../models/news_item.dart';
import '../repositories/news_repository.dart';
import '../services/paginated.dart';
import '../widgets/news_people_sheet.dart';
import 'news_create_screen.dart';
import 'news_detail_screen.dart';

class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({
    super.key,
    this.showAppBar = true,
    this.openNewsId,
  });

  final bool showAppBar;
  final String? openNewsId;

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  List<NewsItem> _news = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _likeInFlight = <String>{};
  final Set<String> _viewInFlight = <String>{};
  /// Id новостей, которые сейчас полностью видны (чтобы отметить просмотр
  /// снова после ухода с экрана и повторного появления).
  final Set<String> _fullyVisibleIds = <String>{};
  bool _openedNewsFromPush = false;

  String? _normalizeNextPageUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final nextUri = Uri.tryParse(trimmed);
    if (nextUri == null) return null;

    final baseUri = Uri.parse(ApiConfig.baseUrl);

    final normalized = nextUri.replace(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
    );
    return normalized.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isInitialLoading || _isLoadingMore) return;
    if (_nextPageUrl == null) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isInitialLoading = true;
      _isLoadingMore = false;
      _nextPageUrl = null;
      _news = [];
      _fullyVisibleIds.clear();
    });

    try {
      final page = await NewsRepository.instance.getPage();
      if (!mounted) return;
      setState(() {
        _news = page.data;
        _nextPageUrl = _normalizeNextPageUrl(page.nextPageUrl);
        _isInitialLoading = false;
      });
      await _maybeOpenNewsFromPush();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить новости')),
      );
    }
  }

  Future<void> _loadMore() async {
    final url = _normalizeNextPageUrl(_nextPageUrl);
    if (url == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final Paginated<NewsItem> page =
          await NewsRepository.instance.getPage(url: url);
      if (!mounted) return;
      setState(() {
        _news = [..._news, ...page.data];
        _nextPageUrl = _normalizeNextPageUrl(page.nextPageUrl);
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _maybeOpenNewsFromPush() async {
    final id = widget.openNewsId;
    if (id == null || id.isEmpty || _openedNewsFromPush) return;
    _openedNewsFromPush = true;
    await _openNewsById(id);
  }

  Future<void> _openNewsById(String id) async {
    NewsItem? item;
    for (final news in _news) {
      if (news.id == id) {
        item = news;
        break;
      }
    }

    if (item == null) {
      try {
        item = await NewsRepository.instance.getById(id);
      } catch (_) {
        var nextUrl = _normalizeNextPageUrl(_nextPageUrl);
        while (item == null && nextUrl != null) {
          try {
            final page = await NewsRepository.instance.getPage(url: nextUrl);
            for (final news in page.data) {
              if (news.id == id) {
                item = news;
                break;
              }
            }
            nextUrl = _normalizeNextPageUrl(page.nextPageUrl);
          } catch (_) {
            break;
          }
        }
      }
    }

    if (!mounted || item == null) return;
    await _openDetail(item);
  }

  Future<void> _openDetail(NewsItem item) async {
    final index = _news.indexWhere((n) => n.id == item.id);
    final current = index >= 0 ? _news[index] : item;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewsDetailScreen(news: current),
      ),
    );
    if (!mounted) return;
    // Обновляем карточку после возврата (лайки / просмотры могли измениться).
    try {
      final fresh = await NewsRepository.instance.getById(current.id);
      if (!mounted) return;
      _updateItem(fresh.id, (_) => fresh);
    } catch (_) {}
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewsCreateScreen()),
    );
    if (created == true && mounted) {
      await _loadFirstPage();
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat("d MMMM y 'г.'", 'ru_RU').format(date);
  }

  void _updateItem(String newsId, NewsItem Function(NewsItem item) mutate) {
    final idx = _news.indexWhere((n) => n.id == newsId);
    if (idx < 0) return;
    setState(() {
      final updated = mutate(_news[idx]);
      _news = [..._news]..[idx] = updated;
    });
  }

  Future<bool> _toggleLike(NewsItem item) async {
    final id = item.id;
    if (id.isEmpty) return false;
    if (_likeInFlight.contains(id)) return false;

    setState(() => _likeInFlight.add(id));
    final wasLiked = item.isLiked;
    try {
      if (wasLiked) {
        await NewsRepository.instance.removeLike(id);
        if (!mounted) return false;
        _updateItem(
          id,
          (n) => n.copyWith(
            isLiked: false,
            likesCount: (n.likesCount - 1).clamp(0, 1 << 30),
          ),
        );
      } else {
        await NewsRepository.instance.addLike(id);
        if (!mounted) return false;
        _updateItem(
          id,
          (n) => n.copyWith(
            isLiked: true,
            likesCount: n.likesCount + 1,
          ),
        );
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasLiked ? 'Не удалось убрать лайк' : 'Не удалось поставить лайк',
          ),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _likeInFlight.remove(id));
      }
    }
  }

  Future<void> _addView(NewsItem item) async {
    final id = item.id;
    if (id.isEmpty) return;
    if (_viewInFlight.contains(id)) return;

    setState(() => _viewInFlight.add(id));
    try {
      await NewsRepository.instance.addView(id);
      if (!mounted) return;
      _updateItem(
        id,
        (n) => n.copyWith(
          viewsCount: n.viewsCount + 1,
          isViewed: true,
        ),
      );
    } catch (_) {
      // Просмотр — тихо игнорируем ошибки.
    } finally {
      if (mounted) {
        setState(() => _viewInFlight.remove(id));
      }
    }
  }

  void _onCardVisibilityChanged(NewsItem news, VisibilityInfo info) {
    final id = news.id;
    if (id.isEmpty) return;

    final fullyVisible = info.visibleFraction >= 1.0;
    if (fullyVisible) {
      if (_fullyVisibleIds.add(id)) {
        _addView(news);
      }
    } else {
      _fullyVisibleIds.remove(id);
    }
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final showInlineTitle = !widget.showAppBar;

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(16, showInlineTitle ? 0 : 16, 16, 88),
        itemCount: _news.length + 1 + (showInlineTitle ? 1 : 0),
        itemBuilder: (context, index) {
          if (showInlineTitle && index == 0) {
            final theme = Theme.of(context);
            final appBarTheme = theme.appBarTheme;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: appBarTheme.backgroundColor ?? AppColors.surfaceElevated,
                border: const Border(bottom: BorderSide(color: AppColors.outline)),
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Center(
                    child: Text(
                      'Новости',
                      style:
                          appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            );
          }

          final realIndex = index - (showInlineTitle ? 1 : 0);

          if (realIndex >= _news.length) {
            if (!_isLoadingMore) return const SizedBox(height: 24);
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final news = _news[realIndex];
          return VisibilityDetector(
            key: Key('news-card-${news.id}'),
            onVisibilityChanged: (info) => _onCardVisibilityChanged(news, info),
            child: _NewsCard(
              news: news,
              dateLabel: _formatDate(news.date),
              isLikeInFlight: _likeInFlight.contains(news.id),
              onLike: () => _toggleLike(news),
              onOpen: () => _openDetail(news),
              onShowLikers: () => NewsPeopleSheet.show(
                context,
                newsId: news.id,
                kind: NewsPeopleKind.likers,
              ),
              onShowViewers: () => NewsPeopleSheet.show(
                context,
                newsId: news.id,
                kind: NewsPeopleKind.viewers,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fab = FloatingActionButton(
      onPressed: _openCreate,
      child: const AppIcon(AppIcons.profileAdd, size: 22),
    );

    if (!widget.showAppBar) {
      return Scaffold(
        body: _buildBody(),
        floatingActionButton: fab,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новости'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _buildBody(),
      floatingActionButton: fab,
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsItem news;
  final String dateLabel;
  final Future<bool> Function() onLike;
  final VoidCallback onOpen;
  final VoidCallback onShowLikers;
  final VoidCallback onShowViewers;
  final bool isLikeInFlight;

  const _NewsCard({
    required this.news,
    required this.dateLabel,
    required this.onLike,
    required this.onOpen,
    required this.onShowLikers,
    required this.onShowViewers,
    required this.isLikeInFlight,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = news.imageUrl != null && news.imageUrl!.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              Image.network(
                news.imageUrl!,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (news.author != null) ...[
                        _AuthorChip(
                          authorName: news.author!.fullName,
                          avatarUrl: news.author!.avatarUrl,
                        ),
                        const SizedBox(width: 10),
                      ],
                      AppIcon(
                        AppIcons.date,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    news.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    news.content,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatChip(
                        iconAsset: AppIcons.eye,
                        label: '${news.viewsCount}',
                        onTap: onShowViewers,
                      ),
                      const SizedBox(width: 10),
                      _LikeButton(
                        count: news.likesCount,
                        isLiked: news.isLiked,
                        isLoading: isLikeInFlight,
                        onPressed: () async {
                          await onLike();
                        },
                        onCountTap: onShowLikers,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.iconAsset,
    required this.label,
    this.onTap,
  });

  final String iconAsset;
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
          AppIcon(iconAsset, size: 14, color: cs.onSurfaceVariant),
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

class _AuthorChip extends StatelessWidget {
  const _AuthorChip({required this.authorName, required this.avatarUrl});

  final String authorName;
  final String? avatarUrl;

  String _initials(String s) {
    final parts =
        s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    String firstChar(String p) => p.isEmpty ? '' : p.substring(0, 1);
    final first = firstChar(parts.first);
    final second = parts.length > 1 ? firstChar(parts[1]) : '';
    return (first + second).toUpperCase().trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
          child: hasAvatar
              ? null
              : Text(
                  _initials(authorName),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
