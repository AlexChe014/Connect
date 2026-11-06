import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../models/bonus_program/reward_request.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../services/haptics_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/bonus_glass.dart';

/// Заявки сотрудника на товары магазина и призы колеса: что одобрено,
/// отклонено или ещё ждёт решения.
class BonusRequestsScreen extends StatefulWidget {
  const BonusRequestsScreen({super.key});

  @override
  State<BonusRequestsScreen> createState() => _BonusRequestsScreenState();
}

class _BonusRequestsScreenState extends State<BonusRequestsScreen> {
  final _scrollController = ScrollController();

  List<RewardRequest> _items = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String? _nextPageUrl;

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
    if (_isInitialLoading || _isLoadingMore || _nextPageUrl == null) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) _loadMore();
  }

  /// Страница короче экрана: прокручивать нечего, и без этого следующая
  /// страница никогда бы не загрузилась.
  void _loadMoreIfListIsShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
      _nextPageUrl = null;
    });

    try {
      final page = await BonusProgramRepository.instance.getMyRewardRequests();
      if (!mounted) return;
      setState(() {
        _items = page.data;
        _nextPageUrl = page.nextPageUrl;
        _isInitialLoading = false;
      });
      _loadMoreIfListIsShort();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось получить заявки';
      });
    }
  }

  Future<void> _loadMore() async {
    final url = _nextPageUrl;
    if (_isLoadingMore || url == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await BonusProgramRepository.instance.getMyRewardRequests(
        url: url,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.data];
        _nextPageUrl = page.nextPageUrl;
        _isLoadingMore = false;
      });
      _loadMoreIfListIsShort();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BonusGlassScaffold(
      title: 'Мои заявки',
      controller: _scrollController,
      onRefresh: AppHaptics.onRefresh(_loadFirstPage),
      slivers: _buildSlivers(),
    );
  }

  List<Widget> _buildSlivers() {
    if (_isInitialLoading) {
      return [
        AppGlassSliverList(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 8,
          itemBuilder: (context, index) => const AppSkeletonListTile(),
        ),
      ];
    }

    if (_errorMessage != null) {
      return [
        SliverAppEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: _errorMessage!,
          onRetry: _loadFirstPage,
        ),
      ];
    }

    if (_items.isEmpty) {
      return const [
        SliverAppEmptyState(
          icon: CupertinoIcons.doc_text,
          message: 'Заявок пока нет',
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Text(
            'После одобрения HR свяжется с вами, чтобы передать товар или приз.',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ),
      AppGlassSliverList(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        separatorIndent: 16,
        itemCount: _items.length,
        itemBuilder: (context, index) => _RequestRow(request: _items[index]),
      ),
      if (_isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
    ];
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final RewardRequest request;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final date = request.createdAt;
    final comment = request.hrComment?.trim();
    final details = [
      request.typeLabel,
      if (date != null)
        DateFormat('d MMM yyyy, HH:mm', 'ru_RU').format(date.toLocal()),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  request.itemName ?? request.typeLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(request: request),
            ],
          ),
          const SizedBox(height: 2),
          Text(details, style: TextStyle(fontSize: 12, color: secondary)),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: TextStyle(fontSize: 13, color: secondary)),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.request});

  final RewardRequest request;

  @override
  Widget build(BuildContext context) {
    final tint =
        (request.isApproved
                ? CupertinoColors.systemGreen
                : request.isRejected
                ? CupertinoColors.systemRed
                : CupertinoColors.systemOrange)
            .resolveFrom(context);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: isDark ? 0.24 : 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        request.statusLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: tint,
        ),
      ),
    );
  }
}
