import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;

import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../services/paginated.dart';
import 'app_loading.dart';
import 'chat_avatar.dart';

/// Поиск и выбор сотрудника (`/user/filter`) с debounce и пагинацией.
class StaffUserPickerSheet extends StatefulWidget {
  const StaffUserPickerSheet({
    super.key,
    required this.selectedIds,
    required this.onUserSelected,
  });

  final Set<String> selectedIds;
  final ValueChanged<StaffUser> onUserSelected;

  static Future<void> show(
    BuildContext context, {
    required Set<String> selectedIds,
    required ValueChanged<StaffUser> onUserSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        // Клавиатура (автофокус в поиске снят, но пользователь может открыть
        // её сам) не должна выталкивать шторку за пределы экрана — иначе
        // список и кнопка «Готово» уезжают за клавиатуру и выглядят так,
        // будто скролл не работает.
        final maxHeight =
            (mediaQuery.size.height -
                    mediaQuery.padding.top -
                    mediaQuery.viewInsets.bottom -
                    24)
                .clamp(200.0, mediaQuery.size.height);
        final height = (mediaQuery.size.height * 0.75).clamp(0.0, maxHeight);
        return SizedBox(
          height: height,
          child: StaffUserPickerSheet(
            selectedIds: selectedIds,
            onUserSelected: onUserSelected,
          ),
        );
      },
    );
  }

  @override
  State<StaffUserPickerSheet> createState() => _StaffUserPickerSheetState();
}

class _StaffUserPickerSheetState extends State<StaffUserPickerSheet> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// Локальная копия: bottom sheet не перестраивается при setState родителя.
  late Set<String> _selectedIds;

  List<StaffUser> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  int _currentPage = 1;
  int? _lastPage;
  String _appliedQ = '';
  Timer? _debounce;

  bool get _hasMore {
    if (_nextPageUrl != null) return true;
    if (_lastPage != null) return _currentPage < _lastPage!;
    return false;
  }

  List<StaffUser> _appendUnique(
    List<StaffUser> current,
    List<StaffUser> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final seen = current.map((u) => u.id).toSet();
    final extra = incoming
        .where((u) => u.id.isNotEmpty && seen.add(u.id))
        .toList(growable: false);
    if (extra.isEmpty) return current;
    return [...current, ...extra];
  }

  void _scheduleFillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_isLoading || _isLoadingMore || !_hasMore) return;
      if (_scrollController.position.maxScrollExtent <= 80) {
        _loadMore();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_scheduleSearch);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = _searchController.text.trim();
      if (q == _appliedQ) return;
      _appliedQ = q;
      _loadFirstPage();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore) return;
    if (!_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _nextPageUrl = null;
      _currentPage = 1;
      _lastPage = null;
      _items = [];
    });

    try {
      final page = await UsersRepository.instance.getPage(
        q: _appliedQ.isEmpty ? null : _appliedQ,
      );
      if (!mounted) return;
      setState(() {
        _items = page.data;
        _nextPageUrl = page.nextPageUrl;
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _isLoading = false;
      });
      _scheduleFillViewport();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final url = _nextPageUrl;

    setState(() => _isLoadingMore = true);
    try {
      final Paginated<StaffUser> page = url != null
          ? await UsersRepository.instance.getPage(url: url)
          : await UsersRepository.instance.getPage(
              q: _appliedQ.isEmpty ? null : _appliedQ,
              page: _currentPage + 1,
            );
      if (!mounted) return;
      final previousLength = _items.length;
      final merged = _appendUnique(_items, page.data);
      setState(() {
        _items = merged;
        _nextPageUrl = page.nextPageUrl;
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _isLoadingMore = false;
        if (merged.length == previousLength || page.data.isEmpty) {
          _nextPageUrl = null;
          _lastPage = _currentPage;
        }
      });
      _scheduleFillViewport();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  void _onUserTap(StaffUser user) {
    if (_selectedIds.contains(user.id)) {
      _showError('Участник уже добавлен');
      return;
    }
    if (user.idAsInt == null) {
      _showError('Некорректный id пользователя');
      return;
    }
    setState(() => _selectedIds.add(user.id));
    widget.onUserSelected(user);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        decoration: TextDecoration.none,
        color: CupertinoColors.label.resolveFrom(context),
        fontSize: 16,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Участники',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Фамилия, имя или email',
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _appliedQ = _searchController.text.trim();
                  _loadFirstPage();
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: 8,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          const AppSkeletonCardTile(),
                    )
                  : _items.isEmpty
                  ? Center(
                      child: Text(
                        _appliedQ.isEmpty
                            ? 'Сотрудники не найдены'
                            : 'Никого не найдено по запросу',
                        style: const TextStyle(
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final user = _items[index];
                        final isSelected = _selectedIds.contains(user.id);
                        return _PickerUserTile(
                          user: user,
                          isSelected: isSelected,
                          onTap: () => _onUserTap(user),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Готово'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerUserTile extends StatelessWidget {
  const _PickerUserTile({
    required this.user,
    required this.isSelected,
    required this.onTap,
  });

  final StaffUser user;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                context,
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isSelected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              MemberAvatar(
                displayName: user.fullName,
                avatarUrl: user.avatarUrl,
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((user.email ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((user.department ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.department!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: CupertinoColors.activeBlue,
                )
              else
                const Icon(
                  CupertinoIcons.plus_circle,
                  color: CupertinoColors.systemGrey,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
