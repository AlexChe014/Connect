import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/app_icons.dart';
import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../screens/chat_conversation_screen.dart';
import '../services/chat_service.dart';
import 'employee_detail_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _scrollController = ScrollController();
  final _qController = TextEditingController();

  List<StaffUser> _items = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  String? _nextPageUrl;

  String _appliedQ = '';

  Timer? _debounce;

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _qController.addListener(_scheduleSearch);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _qController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = _qController.text.trim();
      if (q == _appliedQ) return;
      _appliedQ = q;
      _loadFirstPage();
    });
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
        _isInitialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить сотрудников')),
      );
    }
  }

  Future<void> _loadMore() async {
    final url = _nextPageUrl;
    if (url == null || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await UsersRepository.instance.getPage(url: url);
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

  Future<void> _openChat(StaffUser user) async {
    final peerId = user.idAsInt;
    if (peerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось определить пользователя')),
      );
      return;
    }

    final chat = await ChatService.instance.createDirect(
      fullName: user.fullName,
      peerUserId: peerId,
      peerAvatarUrl: user.avatarUrl,
    );
    if (!mounted) return;
    if (chat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть чат')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: chat),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return TextField(
      controller: _qController,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Фамилия, имя, отчество или почта',
        prefixIcon: AppIcon(AppIcons.search, size: 20),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onSubmitted: (_) {
        _debounce?.cancel();
        _appliedQ = _qController.text.trim();
        _loadFirstPage();
      },
    );
  }

  Widget _buildListContent({required bool showInlineTitle}) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final headerCount = (showInlineTitle ? 1 : 0) + 1;
    final itemCount = headerCount + _items.length + 1;

    return RefreshIndicator(
      onRefresh: () async {
        _debounce?.cancel();
        _appliedQ = _qController.text.trim();
        await _loadFirstPage();
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(16, showInlineTitle ? 0 : 8, 16, 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (showInlineTitle && index == 0) {
            final theme = Theme.of(context);
            final appBarTheme = theme.appBarTheme;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              color: appBarTheme.backgroundColor ?? theme.colorScheme.surface,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Center(
                    child: Text(
                      'Сотрудники',
                      style: appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            );
          }

          final base = showInlineTitle ? 1 : 0;
          final afterHeader = index - base;

          if (afterHeader == 0) {
            return Padding(
              padding: EdgeInsets.only(bottom: widget.showAppBar ? 0 : 12),
              child: _buildSearchBar(context),
            );
          }

          final listIndex = afterHeader - 1;
          if (listIndex < _items.length) {
            final user = _items[listIndex];
            return _EmployeeTile(
              user: user,
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => EmployeeDetailScreen(user: user),
                  ),
                );
              },
              onChat: () => _openChat(user),
            );
          }

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
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) {
      return _buildListContent(showInlineTitle: true);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сотрудники'),
        centerTitle: true,
      ),
      body: _buildListContent(showInlineTitle: false),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({
    required this.user,
    required this.onTap,
    required this.onChat,
  });

  final StaffUser user;
  final VoidCallback onTap;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: hasAvatar
                        ? ClipOval(
                            child: Image.network(
                              user.avatarUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Text(
                                user.initials,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            user.initials,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: user.isOnline ? const Color(0xFF34C759) : theme.colorScheme.outline,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.cardColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  user.fullName,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Написать',
                onPressed: onChat,
                icon: const AppIcon(AppIcons.chat, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
