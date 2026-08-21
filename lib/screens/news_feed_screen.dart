import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/app_theme.dart';
import '../config/api_config.dart';
import '../models/news_item.dart';
import '../repositories/news_repository.dart';
import '../services/paginated.dart';
import '../utils/app_feedback.dart';
import '../utils/html_text_utils.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_network_image.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/news_people_sheet.dart';
import 'news_create_screen.dart';
import 'news_detail_screen.dart';

class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({super.key, this.showAppBar = true, this.openNewsId});

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      AppFeedback.showSnackBar(
        context,
        e,
        fallback: 'Не удалось загрузить новости',
      );
    }
  }

  Future<void> _loadMore() async {
    final url = _normalizeNextPageUrl(_nextPageUrl);
    if (url == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final Paginated<NewsItem> page = await NewsRepository.instance.getPage(
        url: url,
      );
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
      CupertinoPageRoute(builder: (_) => NewsDetailScreen(news: current)),
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
    final created = await Navigator.of(
      context,
    ).push<bool>(CupertinoPageRoute(builder: (_) => const NewsCreateScreen()));
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
          (n) => n.copyWith(isLiked: true, likesCount: n.likesCount + 1),
        );
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      _showCupertinoSnack(
        wasLiked ? 'Не удалось убрать лайк' : 'Не удалось поставить лайк',
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _likeInFlight.remove(id));
      }
    }
  }

  void _showCupertinoSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
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
        (n) => n.copyWith(viewsCount: n.viewsCount + 1, isViewed: true),
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

  Widget _buildSliverBody() {
    if (_isInitialLoading) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        sliver: SliverList.builder(
          itemCount: 3,
          itemBuilder: (context, index) => const _NewsCardSkeleton(),
        ),
      );
    }

    if (_news.isEmpty) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.news,
        message: 'Пока нет новостей',
        onRetry: _loadFirstPage,
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      sliver: SliverList.separated(
        itemCount: _news.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.lg),
        itemBuilder: (context, index) {
          if (index >= _news.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CupertinoActivityIndicator()),
            );
          }

          final news = _news[index];
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
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadFirstPage,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Лента'),
                backgroundColor: CupertinoColors.systemGroupedBackground
                    .withValues(alpha: 0.9),
                border: null,
                trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _openCreate,
                  child: const Icon(CupertinoIcons.square_pencil, size: 26),
                ),
              ),
              _buildSliverBody(),
            ],
          ),
        ),
      ),
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

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        decoration: TextDecoration.none,
        color: CupertinoColors.label.resolveFrom(context),
        fontSize: 15,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: CupertinoColors.systemBackground.resolveFrom(context),
          boxShadow: AppColors.cardPhotoShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTap: onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Фото целиком (contain) + блюр-копия того же снимка по краям —
              // портретные фото не обрезаются, но карточка остаётся 16:9.
              if (hasImage)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: AppNetworkImage(
                          url: news.imageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
                      AppNetworkImage(
                        url: news.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
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
                        Icon(
                          CupertinoIcons.calendar,
                          size: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      news.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (news.contentHtml.trim().isNotEmpty ||
                        news.content.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _ExpandableSummary(
                        text: news.contentHtml.trim().isNotEmpty
                            ? news.contentHtml
                            : news.content,
                        fontSize: 15,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatChip(
                          icon: CupertinoIcons.eye,
                          label: '${news.viewsCount}',
                          onTap: onShowViewers,
                        ),
                        const Spacer(),
                        _StatChip(
                          icon: CupertinoIcons.chat_bubble,
                          onTap: onOpen,
                        ),
                        const SizedBox(width: 16),
                        _LikeButton(
                          count: news.likesCount,
                          isLiked: news.isLiked,
                          isLoading: isLikeInFlight,
                          onPressed: onLike,
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
      ),
    );
  }
}

/// Превью текста новости в 3 строки — если текст в них не помещается,
/// показывает под ним подпись «Читать полностью» (сам тап обрабатывает
/// карточка целиком, у подписи нет своего onTap).
class _ExpandableSummary extends StatelessWidget {
  const _ExpandableSummary({
    required this.text,
    required this.fontSize,
    required this.color,
  });

  final String text;
  final double fontSize;
  final Color color;

  static const _maxLines = 3;

  @override
  Widget build(BuildContext context) {
    final plain = HtmlTextUtils.looksLikeHtml(text)
        ? HtmlTextUtils.toPlainText(text)
        : text;
    final style = TextStyle(color: color, fontSize: fontSize, height: 1.35);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: plain, style: style),
          maxLines: _maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final isTruncated = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plain,
              maxLines: _maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (isTruncated) ...[
              const SizedBox(height: 4),
              Text(
                'Читать полностью',
                style: TextStyle(
                  fontSize: fontSize - 2,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Заготовка карточки новости на время первой загрузки ленты.
class _NewsCardSkeleton extends StatelessWidget {
  const _NewsCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: CupertinoColors.systemBackground.resolveFrom(context),
        boxShadow: AppColors.cardPhotoShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: 16 / 9,
            child: AppSkeletonBox(borderRadius: 0),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(width: 160, height: 12, borderRadius: 6),
                const SizedBox(height: AppSpacing.md),
                const AppSkeletonBox(height: 16, borderRadius: 6),
                const SizedBox(height: AppSpacing.sm),
                AppSkeletonBox(
                  width: MediaQuery.sizeOf(context).width * 0.6,
                  height: 16,
                  borderRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, this.label, this.onTap});

  final IconData icon;
  final String? label;
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
          if (label != null) ...[
            const SizedBox(width: 6),
            Text(label!, style: TextStyle(fontSize: 13, color: color)),
          ],
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
  final Future<bool> Function() onPressed;
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
                    width: 16,
                    height: 16,
                    child: CupertinoActivityIndicator(radius: 8),
                  )
                : ScaleTransition(
                    scale: _scale,
                    child: Icon(
                      widget.isLiked
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      size: 20,
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
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MemberAvatar(displayName: authorName, avatarUrl: avatarUrl, radius: 10),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }
}
