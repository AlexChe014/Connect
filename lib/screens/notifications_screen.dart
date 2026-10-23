import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../config/app_theme.dart';
import '../config/notification_topics.dart';
import '../models/notification_item.dart';
import '../repositories/notifications_repository.dart';
import '../services/app_navigation_service.dart';
import '../services/notification_unread_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/news_glass.dart' show formatNewsDate;
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _scrollController = ScrollController();

  List<NotificationItem> _items = [];
  String? _nextPageUrl;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _isMarkingAll = false;

  /// Были непрочитанными при открытии экрана: уже отмечены на сервере, но
  /// до ухода с экрана остаются выделенными, чтобы было видно, что нового.
  final Set<int> _freshIds = {};

  /// Попали на экран и ждут отправки `read/{id}` — копим, чтобы при
  /// прокрутке не слать запрос на каждый кадр.
  final Set<int> _pendingReadIds = {};
  Timer? _readFlushTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _readFlushTimer?.cancel();
    _flushRead();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Уведомление хотя бы раз показалось на экране — считаем прочитанным.
  void _markSeen(NotificationItem item) {
    if (_freshIds.contains(item.id)) return;
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index < 0 || _items[index].isRead) return;
    _items[index] = _items[index].copyWith(isRead: true);
    _freshIds.add(item.id);
    _pendingReadIds.add(item.id);
    _readFlushTimer?.cancel();
    _readFlushTimer = Timer(const Duration(milliseconds: 400), _flushRead);
  }

  void _flushRead() {
    if (_pendingReadIds.isEmpty) return;
    final ids = _pendingReadIds.toList();
    _pendingReadIds.clear();
    NotificationUnreadService.instance.markRead(ids.length);
    for (final id in ids) {
      NotificationsRepository.instance.markAsRead(id).catchError((_) {});
    }
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
    });

    try {
      final page = await NotificationsRepository.instance.getPage();
      if (!mounted) return;
      setState(() {
        _items = List.of(page.data);
        _nextPageUrl = page.nextPageUrl;
        _isInitialLoading = false;
      });
      unawaited(NotificationUnreadService.instance.refresh());
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await NotificationsRepository.instance.getPage(url: url);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.data];
        _nextPageUrl = page.nextPageUrl;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_isMarkingAll) return;
    // Непрочитанные могут быть и на ещё не загруженных страницах.
    if (NotificationUnreadService.instance.unreadCount == 0 &&
        _items.every((i) => i.isRead)) {
      return;
    }

    setState(() => _isMarkingAll = true);
    try {
      await NotificationsRepository.instance.markAllAsRead();
      if (!mounted) return;
      NotificationUnreadService.instance.markAllRead();
      setState(() {
        _items = _items.map((i) => i.copyWith(isRead: true)).toList();
        _freshIds.clear();
        _pendingReadIds.clear();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось отметить всё прочитанным')),
      );
    } finally {
      if (mounted) setState(() => _isMarkingAll = false);
    }
  }

  Future<void> _openItem(NotificationItem item) async {
    // Тап по только что подгруженной карточке мог опередить отметку
    // по показу — отправляем её сразу.
    _markSeen(item);
    _readFlushTimer?.cancel();
    _flushRead();

    final opened = await AppNavigationService.openNotificationInPlace(
      item.toNavigationData(),
    );
    if (opened || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Этот раздел пока доступен только на портале'),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const NotificationSettingsScreen(),
      ),
    );
  }

  List<Widget> _buildContentSlivers() {
    if (_isInitialLoading) {
      return [
        AppGlassSliverList(
          itemCount: 6,
          itemBuilder: (context, index) => const AppSkeletonListTile(),
        ),
      ];
    }

    if (_items.isEmpty) {
      return [
        SliverAppEmptyState(
          icon: CupertinoIcons.bell,
          message: 'Пока нет уведомлений',
          onRetry: _loadFirstPage,
        ),
      ];
    }

    // Группы по дням, как в Центре уведомлений: «Сегодня», «Вчера», дата.
    // Без даты — в группу предыдущего уведомления, список отсортирован
    // сервером.
    final groups = <(String, List<NotificationItem>)>[];
    for (final item in _items) {
      final createdAt = item.createdAt;
      final label = createdAt == null
          ? (groups.isEmpty ? 'Ранее' : groups.last.$1)
          : formatNewsDate(createdAt);
      if (groups.isEmpty || groups.last.$1 != label) {
        groups.add((label, [item]));
      } else {
        groups.last.$2.add(item);
      }
    }

    final timeFormat = DateFormat('HH:mm', 'ru_RU');

    return [
      for (final (index, (label, items)) in groups.indexed) ...[
        SliverToBoxAdapter(
          child: index == 0
              ? _buildFirstGroupHeader(label)
              : AppGlassSectionLabel(label),
        ),
        AppGlassSliverList(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          separatorIndent: _NotificationTile.separatorIndent,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return VisibilityDetector(
              key: Key('notification-${item.id}'),
              onVisibilityChanged: (info) {
                if (info.visibleFraction >= 0.5) _markSeen(item);
              },
              child: _NotificationTile(
                item: item,
                isHighlighted: !item.isRead || _freshIds.contains(item.id),
                timeFormat: timeFormat,
                onTap: () => _openItem(item),
              ),
            );
          },
        ),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: _isLoadingMore
              ? const Center(child: CupertinoActivityIndicator())
              : const SizedBox(height: 8),
        ),
      ),
    ];
  }

  /// Заголовок первой группы и справа «Прочитать все» — как «Очистить»
  /// в Центре уведомлений. Видна, пока на сервере есть непрочитанные,
  /// в том числе на ещё не загруженных страницах.
  Widget _buildFirstGroupHeader(String label) {
    return ListenableBuilder(
      listenable: NotificationUnreadService.instance,
      builder: (context, _) {
        final hasUnread =
            NotificationUnreadService.instance.unreadCount > 0 ||
            _pendingReadIds.isNotEmpty ||
            _items.any((i) => !i.isRead);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: AppGlassSectionLabel(label)),
            if (hasUnread || _isMarkingAll)
              Padding(
                padding: const EdgeInsets.only(right: 20, bottom: 2),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  minimumSize: Size.zero,
                  onPressed: _isMarkingAll ? null : _markAllRead,
                  child: _isMarkingAll
                      ? const CupertinoActivityIndicator(radius: 8)
                      : const Text(
                          'Прочитать все',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.primary,
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _navButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.only(left: 14),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Icon(
        icon,
        size: AppSliverTitleBar.iconSize,
        color: CupertinoColors.label.resolveFrom(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: _loadFirstPage,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      AppSliverTitleBar(
                        title: const Text('Уведомления'),
                        leading: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.maybePop(context),
                          child: Icon(
                            CupertinoIcons.back,
                            size: AppSliverTitleBar.iconSize,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                        blur: blur,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _navButton(
                              icon: CupertinoIcons.slider_horizontal_3,
                              onPressed: _openSettings,
                            ),
                          ],
                        ),
                      ),
                      ..._buildContentSlivers(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка уведомления: значок темы на мягкой подложке, заголовок и текст,
/// справа время; у нового — синяя точка.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.isHighlighted,
    required this.timeFormat,
    required this.onTap,
  });

  /// Отступ разделителя — под текст, мимо значка.
  static const separatorIndent = 68.0;

  final NotificationItem item;

  /// Новое: не прочитано или стало прочитанным за этот показ экрана.
  final bool isHighlighted;
  final DateFormat timeFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final topic =
        NotificationTopics.byType(item.type) ??
        (NotificationTopics.isSurveyType(item.type, item.module)
            ? NotificationTopics.survey
            : null);
    final icon = topic?.icon ?? CupertinoIcons.bell_fill;
    final tint = CupertinoDynamicColor.resolve(
      topic?.color ?? CupertinoColors.systemGrey.resolveFrom(context),
      context,
    );
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final isUnread = isHighlighted;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Мягкая подложка, как у AppIconBadge: на тёмном 15% не видно.
                color: tint.withValues(alpha: isDark ? 0.24 : 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: isUnread
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
                      if (item.createdAt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 1),
                          child: Text(
                            timeFormat.format(item.createdAt!.toLocal()),
                            style: TextStyle(fontSize: 13, color: secondary),
                          ),
                        ),
                      if (isUnread)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(left: 8, top: 5),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
