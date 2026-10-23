import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../screens/chat_conversation_screen.dart';
import '../services/chat_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/employee_row.dart';
import 'employee_detail_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

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
      if (_isInitialLoading || _isLoadingMore || !_hasMore) return;
      if (_scrollController.position.maxScrollExtent <= 80) {
        _loadMore();
      }
    });
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
    if (!_hasMore) return;

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
        _isInitialLoading = false;
      });
      _scheduleFillViewport();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить сотрудников')),
      );
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final url = _nextPageUrl;

    setState(() => _isLoadingMore = true);
    try {
      final page = url != null
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
      return AppGlassSliverList(
        itemCount: 8,
        itemBuilder: (context, index) => const AppSkeletonListTile(),
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

    return SliverMainAxisGroup(
      slivers: [
        AppGlassSliverList(
          separatorIndent: EmployeeRow.separatorIndent,
          padding: EdgeInsets.fromLTRB(16, 4, 16, _isLoadingMore ? 0 : 24),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final user = _items[index];
            return EmployeeRow(
              user: user,
              onTap: () => _openDetail(user),
              trailing: EmployeeRowButton(
                icon: CupertinoIcons.bubble_left,
                onPressed: () => _openChat(user),
              ),
            );
          },
        ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: () async {
                    _debounce?.cancel();
                    _appliedQ = _qController.text.trim();
                    await _loadFirstPage();
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      AppSliverTitleBar(
                        title: const Text('Сотрудники'),
                        leading: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.pop(context),
                          child: Icon(
                            CupertinoIcons.back,
                            size: AppSliverTitleBar.iconSize,
                            color: label,
                          ),
                        ),
                        blur: blur,
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: AppGlass(
                            borderRadius: BorderRadius.circular(12),
                            shadows: AppGlass.controlShadow,
                            child: CupertinoSearchTextField(
                              controller: _qController,
                              backgroundColor: const Color(0x00000000),
                              placeholder: 'Фамилия, имя, отчество или почта',
                              onSubmitted: (_) {
                                _debounce?.cancel();
                                _appliedQ = _qController.text.trim();
                                _loadFirstPage();
                              },
                            ),
                          ),
                        ),
                      ),
                      _buildResultsSliver(),
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
