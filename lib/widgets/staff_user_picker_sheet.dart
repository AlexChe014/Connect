import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;

import '../config/app_theme.dart';
import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../services/paginated.dart';
import 'app_glass.dart';
import 'app_loading.dart';
import 'chat_avatar.dart';

/// Поиск и выбор сотрудника (`/user/filter`) с debounce и пагинацией.
class StaffUserPickerSheet extends StatefulWidget {
  const StaffUserPickerSheet({
    super.key,
    required this.selectedIds,
    required this.onUserSelected,
    this.validateUser,
    this.onUserDeselected,
    this.title = 'Участники',
  });

  final Set<String> selectedIds;
  final ValueChanged<StaffUser> onUserSelected;

  /// Если задан, повторное нажатие на отмеченного сотрудника снимает
  /// отметку; без него отмеченные строки не нажимаются.
  final ValueChanged<StaffUser>? onUserDeselected;
  final String title;

  /// Доп. проверка перед выбором: вернуть текст ошибки, чтобы показать его
  /// поверх списка и не отмечать сотрудника (например, нет e-mail).
  final String? Function(StaffUser user)? validateUser;

  static Future<void> show(
    BuildContext context, {
    required Set<String> selectedIds,
    required ValueChanged<StaffUser> onUserSelected,
    String? Function(StaffUser user)? validateUser,
    ValueChanged<StaffUser>? onUserDeselected,
    String title = 'Участники',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.groupedBackground.resolveFrom(context),
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
            validateUser: validateUser,
            onUserDeselected: onUserDeselected,
            title: title,
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
    final onDeselected = widget.onUserDeselected;
    if (_selectedIds.contains(user.id) && onDeselected != null) {
      setState(() => _selectedIds.remove(user.id));
      onDeselected(user);
      return;
    }
    if (_selectedIds.contains(user.id)) {
      _showError('Участник уже добавлен');
      return;
    }
    if (user.idAsInt == null) {
      _showError('Некорректный id пользователя');
      return;
    }
    final error = widget.validateUser?.call(user);
    if (error != null) {
      _showError(error);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
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
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
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
                          canDeselect: widget.onUserDeselected != null,
                          onTap: () => _onUserTap(user),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Готово',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
    this.canDeselect = false,
  });

  final StaffUser user;
  final bool isSelected;
  final bool canDeselect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Заливка и кромка как у AppGlass, но без размытия: строк в списке
    // много, а BackdropFilter под каждой дорог.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? CupertinoColors.tertiarySystemFill.resolveFrom(context)
            : AppColors.glassFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder.resolveFrom(context)),
        boxShadow: isSelected ? null : AppGlass.controlShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isSelected && !canDeselect ? null : onTap,
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((user.email ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((user.department ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.department!,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
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
                  color: AppColors.primary,
                )
              else
                Icon(
                  CupertinoIcons.plus_circle,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
