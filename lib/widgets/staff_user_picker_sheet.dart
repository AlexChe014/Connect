import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/app_icons.dart';
import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../services/paginated.dart';

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
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: StaffUserPickerSheet(
          selectedIds: selectedIds,
          onUserSelected: onUserSelected,
        ),
      ),
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
  String _appliedQ = '';
  Timer? _debounce;

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

  String? _normalizeNextPageUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final nextUri = Uri.tryParse(trimmed);
    if (nextUri == null) return null;
    final baseUri = Uri.parse(ApiConfig.baseUrl);
    return nextUri
        .replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null,
        )
        .toString();
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
    if (_nextPageUrl == null) return;
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
      _items = [];
    });

    try {
      final page = await UsersRepository.instance.getPage(
        q: _appliedQ.isEmpty ? null : _appliedQ,
      );
      if (!mounted) return;
      setState(() {
        _items = page.data;
        _nextPageUrl = _normalizeNextPageUrl(page.nextPageUrl);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _loadMore() async {
    final url = _normalizeNextPageUrl(_nextPageUrl);
    if (url == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final Paginated<StaffUser> page = await UsersRepository.instance.getPage(url: url);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.data];
        _nextPageUrl = _normalizeNextPageUrl(page.nextPageUrl);
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onUserTap(StaffUser user) {
    if (_selectedIds.contains(user.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Участник уже добавлен')),
      );
      return;
    }
    if (user.idAsInt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректный id пользователя')),
      );
      return;
    }
    setState(() => _selectedIds.add(user.id));
    widget.onUserSelected(user);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Участники',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Фамилия, имя или email',
                prefixIcon: const AppIcon(AppIcons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
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
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          _appliedQ.isEmpty
                              ? 'Сотрудники не найдены'
                              : 'Никого не найдено по запросу',
                          style: Theme.of(context).textTheme.bodyMedium,
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
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
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
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Готово'),
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final hasAvatar = (user.avatarUrl ?? '').trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: isSelected
          ? theme.colorScheme.surfaceContainerHighest
          : null,
      child: InkWell(
        onTap: isSelected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: hasAvatar
                    ? ClipOval(
                        child: Image.network(
                          user.avatarUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Text(user.initials),
                        ),
                      )
                    : Text(
                        user.initials,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((user.email ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((user.department ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.department!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary)
              else
                AppIcon(AppIcons.profileAdd, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
