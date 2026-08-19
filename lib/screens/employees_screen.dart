import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../screens/chat_conversation_screen.dart';
import '../services/chat_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/chat_avatar.dart';
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
      return;
    }
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: chat),
      ),
    );
  }

  void _openDetail(StaffUser user) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => EmployeeDetailScreen(user: user),
      ),
    );
  }

  Widget _buildResultsSliver() {
    if (_isInitialLoading) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => const _EmployeeTileSkeleton(),
        ),
      );
    }

    if (_items.isEmpty) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.person_2,
        message: _appliedQ.isEmpty
            ? 'Пока нет сотрудников'
            : 'Никого не нашлось по запросу «$_appliedQ»',
      );
    }

    return SliverPadding(
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

          final user = _items[index];
          return _EmployeeTile(
            user: user,
            onTap: () => _openDetail(user),
            onChat: () => _openChat(user),
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
          onRefresh: () async {
            _debounce?.cancel();
            _appliedQ = _qController.text.trim();
            await _loadFirstPage();
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              const CupertinoSliverNavigationBar(
                largeTitle: Text('Сотрудники'),
                backgroundColor: CupertinoColors.systemGroupedBackground,
                border: null,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: CupertinoSearchTextField(
                    controller: _qController,
                    placeholder: 'Фамилия, имя, отчество или почта',
                    onSubmitted: (_) {
                      _debounce?.cancel();
                      _appliedQ = _qController.text.trim();
                      _loadFirstPage();
                    },
                  ),
                ),
              ),
              _buildResultsSliver(),
            ],
          ),
        ),
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  MemberAvatar(
                    displayName: user.fullName,
                    avatarUrl: user.avatarUrl,
                    radius: 24,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: user.isOnline
                            ? const Color(0xFF34C759)
                            : AppColors.outlineStrong,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: CupertinoColors.secondarySystemGroupedBackground
                              .resolveFrom(context),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  if (user.isBirthdayToday)
                    Positioned(
                      left: -4,
                      bottom: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CupertinoColors.secondarySystemGroupedBackground
                              .resolveFrom(context),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('🎂', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  user.fullName,
                  style: TextStyle(
                    fontFamily: '.SF Pro Text',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onChat,
                child: const Icon(
                  CupertinoIcons.bubble_left,
                  size: 22,
                  color: CupertinoColors.systemBlue,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeTileSkeleton extends StatelessWidget {
  const _EmployeeTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
