import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:intl/intl.dart';

import '../models/bonus_program/point_operation.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';

/// История операций по баллам текущего сотрудника.
class BonusHistoryScreen extends StatefulWidget {
  const BonusHistoryScreen({super.key});

  @override
  State<BonusHistoryScreen> createState() => _BonusHistoryScreenState();
}

class _BonusHistoryScreenState extends State<BonusHistoryScreen> {
  final _scrollController = ScrollController();

  List<PointOperation> _items = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String? _nextPageUrl;
  int? _lastPage;
  int _currentPage = 1;

  bool get _hasMore {
    if (_nextPageUrl != null) return true;
    if (_lastPage != null) return _currentPage < _lastPage!;
    return false;
  }

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
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
      _nextPageUrl = null;
      _lastPage = null;
      _currentPage = 1;
    });

    try {
      final page = await BonusProgramRepository.instance.getHistory();
      if (!mounted) return;
      setState(() {
        _items = page.data;
        _nextPageUrl = page.nextPageUrl;
        _lastPage = page.lastPage;
        _currentPage = page.currentPage;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось получить историю операций';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = _nextPageUrl != null
          ? await BonusProgramRepository.instance.getHistory(url: _nextPageUrl)
          : await BonusProgramRepository.instance.getHistory(
              page: _currentPage + 1,
            );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.data];
        _nextPageUrl = page.nextPageUrl;
        _lastPage = page.lastPage;
        _currentPage = page.currentPage;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('История баллов'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: CupertinoColors.label.resolveFrom(context),
          decoration: TextDecoration.none,
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) return const AppSkeletonList(count: 10);

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _loadFirstPage,
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: const AppEmptyState(
          icon: CupertinoIcons.time,
          message: 'Операций пока нет',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CupertinoActivityIndicator()),
            );
          }
          return _OperationTile(operation: _items[index]);
        },
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({required this.operation});

  final PointOperation operation;

  @override
  Widget build(BuildContext context) {
    final isCredit = operation.isCredit;
    final color = isCredit
        ? CupertinoColors.systemGreen
        : CupertinoColors.systemRed;
    final date = operation.createdAt;
    final title =
        operation.operationTypeName ?? operation.description ?? 'Операция';

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit
                  ? CupertinoIcons.arrow_down_left
                  : CupertinoIcons.arrow_up_right,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (operation.description != null &&
                    operation.description != title) ...[
                  const SizedBox(height: 2),
                  Text(
                    operation.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
                if (date != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat(
                      'd MMM yyyy, HH:mm',
                      'ru_RU',
                    ).format(date.toLocal()),
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.tertiaryLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isCredit ? '+' : ''}${operation.pointsDelta}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
