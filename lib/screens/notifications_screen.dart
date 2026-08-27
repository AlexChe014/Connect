import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;
import 'package:intl/intl.dart';

import '../config/notification_topics.dart';
import '../models/notification_item.dart';
import '../repositories/notifications_repository.dart';
import '../services/app_navigation_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
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
    });

    try {
      final page = await NotificationsRepository.instance.getPage();
      if (!mounted) return;
      setState(() {
        _items = page.data;
        _nextPageUrl = page.nextPageUrl;
        _isInitialLoading = false;
      });
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
    if (_isMarkingAll || _items.every((i) => i.isRead)) return;

    setState(() => _isMarkingAll = true);
    try {
      await NotificationsRepository.instance.markAllAsRead();
      if (!mounted) return;
      setState(() {
        _items = _items.map((i) => i.copyWith(isRead: true)).toList();
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
    if (!item.isRead) {
      setState(() {
        _items = [
          for (final i in _items)
            i.id == item.id ? i.copyWith(isRead: true) : i,
        ];
      });
      NotificationsRepository.instance.markAsRead(item.id).catchError((_) {});
    }

    await AppNavigationService.openFromData({'type': item.type, ...item.data});
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
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList.separated(
            itemCount: 6,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => const AppSkeletonCardTile(),
          ),
        ),
      ];
    }

    if (_items.isEmpty) {
      return [
        SliverFillRemaining(
          child: AppEmptyState(
            icon: CupertinoIcons.bell,
            message: 'Пока нет уведомлений',
            onRetry: _loadFirstPage,
          ),
        ),
      ];
    }

    final dateFormat = DateFormat('d MMM, HH:mm', 'ru_RU');

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: _items.length + (_isLoadingMore ? 1 : 0),
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CupertinoActivityIndicator()),
              );
            }

            final item = _items[index];
            return _NotificationTile(
              item: item,
              dateFormat: dateFormat,
              onTap: () => _openItem(item),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _loadFirstPage,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                CupertinoSliverNavigationBar(
                  largeTitle: const Text('Уведомления'),
                  backgroundColor: CupertinoColors.systemGroupedBackground
                      .withValues(alpha: 0.9),
                  border: null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: _openSettings,
                        child: const Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 24,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 14),
                        minimumSize: Size.zero,
                        onPressed: _isMarkingAll ? null : _markAllRead,
                        child: _isMarkingAll
                            ? const CupertinoActivityIndicator()
                            : const Icon(
                                CupertinoIcons.check_mark_circled,
                                size: 24,
                              ),
                      ),
                    ],
                  ),
                ),
                ..._buildContentSlivers(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.dateFormat,
    required this.onTap,
  });

  final NotificationItem item;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final topic = NotificationTopics.byType(item.type);
    final icon = topic?.icon ?? CupertinoIcons.bell_fill;
    final color = topic?.color ?? CupertinoColors.systemGrey;
    final isUnread = !item.isRead;

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: CupertinoColors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8, top: 4),
                            decoration: const BoxDecoration(
                              color: CupertinoColors.activeBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                    if (item.createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dateFormat.format(item.createdAt!.toLocal()),
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.tertiaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
