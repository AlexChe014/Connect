import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/app_theme.dart';
import '../config/home_tabs.dart';
import '../models/news_item.dart';
import '../repositories/news_repository.dart';
import '../services/paginated.dart';
import '../utils/app_feedback.dart';
import '../utils/html_text_utils.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/news_glass.dart';
import '../widgets/news_people_sheet.dart';
import '../widgets/news_reactions.dart';
import 'news_create_screen.dart';
import 'news_detail_screen.dart';
import '../services/haptics_service.dart';

class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({
    super.key,
    this.showAppBar = true,
    this.openNewsId,
    this.title = 'Лента',
    this.trailing,
    this.headerSlivers = const [],
    this.onRefresh,
    this.homeTab,
  });

  final bool showAppBar;
  final String? openNewsId;
  final String title;

  /// Кнопки шапки; без них — «написать пост».
  final Widget? trailing;

  /// Блоки над лентой (экран «Сегодня»). Если они есть, «написать пост»
  /// переезжает в подпись «Лента» над постами.
  final List<Widget> headerSlivers;

  /// Что ещё обновить жестом «потянуть вниз», кроме самой ленты.
  final Future<void> Function()? onRefresh;

  /// Вкладка нижнего меню, в которой лежит лента: повторный тап по ней
  /// прокручивает в начало.
  final int? homeTab;

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  List<NewsItem> _news = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _viewInFlight = <String>{};
  final Set<String> _reactionInFlight = <String>{};

  /// Id новостей, которые сейчас полностью видны (чтобы отметить просмотр
  /// снова после ухода с экрана и повторного появления).
  final Set<String> _fullyVisibleIds = <String>{};
  bool _openedNewsFromPush = false;

  /// Кнопка «наверх» — когда ушли от начала дальше пары экранов.
  bool _showScrollToTop = false;
  StreamSubscription<int>? _reselectSub;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
    final tab = widget.homeTab;
    if (tab != null) {
      _reselectSub = HomeTabs.reselected
          .where((index) => index == tab)
          .listen((_) => _scrollToTop());
    }
  }

  /// Лента с прошлого раза — сразу, свежая подменяет её, когда придёт.
  Future<void> _loadInitial() async {
    final fresh = _loadFirstPage(quiet: true);
    final cached = await NewsRepository.instance.cachedFirstPage();
    if (cached != null && mounted && _news.isEmpty && cached.data.isNotEmpty) {
      setState(() {
        _news = cached.data;
        // Подгрузка следующих страниц — только от свежей первой.
        _nextPageUrl = null;
        _isInitialLoading = false;
      });
    }
    await fresh;
  }

  @override
  void dispose() {
    _reselectSub?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final show = pos.pixels > pos.viewportDimension * 2;
    if (show != _showScrollToTop) setState(() => _showScrollToTop = show);

    if (_isInitialLoading || _isLoadingMore) return;
    if (_nextPageUrl == null) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  /// Плавно в начало. Издалека — сначала прыжок поближе: анимация через
  /// десятки постов шла бы долго и подгружала бы все картинки по пути.
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 0) return;
    final near = pos.viewportDimension * 1.5;
    if (pos.pixels > near) _scrollController.jumpTo(near);
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  /// [quiet] — без снекбара об ошибке, если на экране уже есть лента
  /// (из кэша при открытии): без сети работаем с ней молча.
  Future<void> _loadFirstPage({bool quiet = false}) async {
    // Лента на экране (обновление, кэш) остаётся до ответа — без скелетона.
    setState(() {
      _isInitialLoading = _news.isEmpty;
      _isLoadingMore = false;
    });

    try {
      final page = await NewsRepository.instance.getPage();
      if (!mounted) return;
      setState(() {
        _news = page.data;
        _nextPageUrl = page.nextPageUrl;
        _isInitialLoading = false;
        _fullyVisibleIds.clear();
      });
      await _maybeOpenNewsFromPush();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      if (quiet && _news.isNotEmpty) return;
      AppFeedback.showSnackBar(
        context,
        e,
        fallback: 'Не удалось загрузить новости',
      );
    }
  }

  Future<void> _loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final Paginated<NewsItem> page = await NewsRepository.instance.getPage(
        url: url,
      );
      if (!mounted) return;
      setState(() {
        _news = [..._news, ...page.data];
        _nextPageUrl = page.nextPageUrl;
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
        var nextUrl = _nextPageUrl;
        while (item == null && nextUrl != null) {
          try {
            final page = await NewsRepository.instance.getPage(url: nextUrl);
            for (final news in page.data) {
              if (news.id == id) {
                item = news;
                break;
              }
            }
            nextUrl = page.nextPageUrl;
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

    final deleted = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => NewsDetailScreen(news: current)),
    );
    if (!mounted) return;
    if (deleted == true) {
      setState(() {
        _news = _news.where((n) => n.id != current.id).toList();
      });
      return;
    }
    // Обновляем карточку после возврата (реакции / просмотры могли измениться).
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

  void _updateItem(String newsId, NewsItem Function(NewsItem item) mutate) {
    final idx = _news.indexWhere((n) => n.id == newsId);
    if (idx < 0) return;
    setState(() {
      final updated = mutate(_news[idx]);
      _news = [..._news]..[idx] = updated;
    });
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

  Future<void> _toggleReaction(NewsItem item, String emoji) async {
    final id = item.id;
    if (id.isEmpty || _reactionInFlight.contains(id)) return;
    setState(() => _reactionInFlight.add(id));
    try {
      await toggleNewsReaction(
        item,
        emoji,
        onUpdate: (news) {
          if (mounted) _updateItem(id, (_) => news);
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showSnackBar(
        context,
        e,
        fallback: 'Не удалось поставить реакцию',
      );
    } finally {
      if (mounted) setState(() => _reactionInFlight.remove(id));
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        sliver: SliverList.builder(
          itemCount: 3,
          itemBuilder: (context, index) => const _NewsCardSkeleton(),
        ),
      );
    }

    if (_news.isEmpty) {
      // Под блоками «Сегодня» пустая лента — просто ничего.
      if (widget.headerSlivers.isNotEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      return SliverAppEmptyState(
        icon: CupertinoIcons.news,
        message: 'Пока нет новостей',
        onRetry: _loadFirstPage,
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      sliver: SliverList.separated(
        itemCount: _news.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 14),
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
              onOpen: () => _openDetail(news),
              reactionInFlight: _reactionInFlight.contains(news.id),
              onToggleReaction: (emoji) => _toggleReaction(news, emoji),
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

  Future<void> _refresh() async {
    final extra = widget.onRefresh;
    await Future.wait([_loadFirstPage(), if (extra != null) extra()]);
  }

  Widget _createButton(Color color) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: _openCreate,
      child: Icon(
        CupertinoIcons.square_pencil,
        size: AppSliverTitleBar.iconSize,
        color: color,
      ),
    );
  }

  /// Подпись «ЛЕНТА» с карандашом справа — над постами под блоками.
  Widget _feedLabel() {
    return SliverToBoxAdapter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(child: AppGlassSectionLabel('Лента')),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 20, 2),
            child: _createButton(AppColors.primary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final hasHeader = widget.headerSlivers.isNotEmpty;
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 15,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: AppHaptics.onRefresh(_refresh),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      AppSliverTitleBar(
                        title: Text(widget.title),
                        blur: blur,
                        trailing:
                            widget.trailing ??
                            (hasHeader ? null : _createButton(label)),
                      ),
                      ...widget.headerSlivers,
                      if (hasHeader) _feedLabel(),
                      _buildSliverBody(),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 16,
                // Над плавающим нижним меню: его высота уже в padding.bottom.
                bottom: MediaQuery.paddingOf(context).bottom + 12,
                child: _ScrollToTopButton(
                  visible: _showScrollToTop,
                  onTap: () {
                    AppHaptics.selection();
                    _scrollToTop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая стеклянная кнопка со стрелкой вверх; появляется и прячется
/// с лёгким масштабом.
class _ScrollToTopButton extends StatelessWidget {
  const _ScrollToTopButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: AnimatedScale(
          scale: visible ? 1 : 0.8,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Semantics(
            button: true,
            label: 'Наверх',
            child: AppGlass(
              borderRadius: BorderRadius.circular(22),
              shadows: AppGlass.controlShadow,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: onTap,
                child: Icon(
                  CupertinoIcons.arrow_up,
                  size: 20,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Пост в ленте: автор и дата, заголовок, начало текста, фото, файлы,
/// внизу реакции и счётчики. Тап по верхней части открывает пост.
class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.news,
    required this.onOpen,
    required this.reactionInFlight,
    required this.onToggleReaction,
    required this.onShowViewers,
  });

  final NewsItem news;
  final VoidCallback onOpen;
  final bool reactionInFlight;
  final void Function(String emoji) onToggleReaction;
  final VoidCallback onShowViewers;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final summary = HtmlTextUtils.toParagraphText(
      news.contentHtml.trim().isNotEmpty ? news.contentHtml : news.content,
    );
    final imageUrl = news.imageUrl?.trim() ?? '';

    return AppFlatGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NewsAuthorLine(news: news),
                  const SizedBox(height: 12),
                  Text(
                    news.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _ExpandableSummary(text: summary),
                  ],
                  if (imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    NewsCoverImage(
                      url: imageUrl,
                      moreCount: news.imageUrls.length - 1,
                    ),
                  ],
                  if (news.documents.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.paperclip,
                          size: 15,
                          color: secondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            news.documents.length == 1
                                ? news.documents.first.name
                                : '${news.documents.first.name} '
                                      'и ещё ${news.documents.length - 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: secondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: NewsReactionsBar(
                    news: news,
                    isLoading: reactionInFlight,
                    onToggle: onToggleReaction,
                  ),
                ),
                const SizedBox(width: 8),
                NewsStatChip(icon: CupertinoIcons.chat_bubble, onTap: onOpen),
                NewsStatChip(
                  icon: CupertinoIcons.eye,
                  label: '${news.viewsCount}',
                  onTap: onShowViewers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Превью текста новости в 3 строки — если текст в них не помещается,
/// показывает под ним подпись «Читать полностью» (сам тап обрабатывает
/// карточка целиком, у подписи нет своего onTap).
class _ExpandableSummary extends StatelessWidget {
  const _ExpandableSummary({required this.text});

  final String text;

  static const _maxLines = 3;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: CupertinoColors.label.resolveFrom(context),
      fontSize: 15,
      height: 1.35,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: _maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final isTruncated = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              maxLines: _maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (isTruncated) ...[
              const SizedBox(height: 4),
              Text(
                'Читать полностью',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppFlatGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                AppSkeletonBox(width: 36, height: 36, borderRadius: 18),
                SizedBox(width: 10),
                AppSkeletonBox(width: 140, height: 12, borderRadius: 6),
              ],
            ),
            const SizedBox(height: 14),
            const AppSkeletonBox(height: 16, borderRadius: 6),
            const SizedBox(height: 8),
            AppSkeletonBox(
              width: MediaQuery.sizeOf(context).width * 0.6,
              height: 16,
              borderRadius: 6,
            ),
            const SizedBox(height: 14),
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: AppSkeletonBox(borderRadius: 16),
            ),
          ],
        ),
      ),
    );
  }
}
