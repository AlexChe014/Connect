import 'dart:async';

import 'package:connect/config/app_theme.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/app_glass.dart';
import 'package:connect/widgets/app_loading.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/app_title_bar.dart';

class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  /// Выбранные участники в порядке выбора (для ленты над поиском).
  final _selected = <int, ChatContact>{};
  bool _creating = false;
  String? _nameError;
  String _search = '';
  List<ChatContact> _searchResults = const [];
  bool _searching = false;
  int _searchToken = 0;
  Timer? _searchDebounce;
  final _chat = ChatService.instance;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChat);
    // После кадра: loadContacts сразу уведомляет слушателей, а initState
    // идёт посреди построения дерева.
    WidgetsBinding.instance.addPostFrameCallback((_) => _chat.loadContacts());
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    _searchDebounce?.cancel();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim();
    setState(() {
      _search = query.toLowerCase();
      if (query.isEmpty) {
        _searchResults = const [];
        _searching = false;
      }
    });

    _searchDebounce?.cancel();
    if (query.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    setState(() => _searching = true);
    try {
      final results = await _chat.searchContacts(query);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() => _searching = false);
    }
  }

  void _onChat() {
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Введите название группы' : null;
    });
    if (_nameError != null) return;

    if (_selected.isEmpty) {
      _showMessage('Выберите хотя бы одного участника');
      return;
    }

    setState(() => _creating = true);
    Chat? c;
    String? errorMessage;
    try {
      c = await ChatService.instance.createGroup(
        title: name,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        userIds: _selected.keys.toList(),
      );
    } catch (e) {
      errorMessage = e is ApiException
          ? e.message
          : 'Не удалось создать группу';
    }
    if (!mounted) return;
    setState(() => _creating = false);

    if (c == null) {
      _showMessage(errorMessage ?? 'Не удалось создать группу');
      return;
    }
    Navigator.of(context).pop<Chat>(c);
  }

  void _showMessage(String message) {
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

  void _toggle(ChatContact c) {
    setState(() {
      if (_selected.remove(c.userId) == null) _selected[c.userId] = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allContacts = _chat.contacts.where((c) => c.userId > 0).toList();
    List<ChatContact> contacts;
    if (_search.isEmpty) {
      contacts = allContacts;
    } else {
      final byId = <int, ChatContact>{
        for (final c in allContacts)
          if (c.fullName.toLowerCase().contains(_search)) c.userId: c,
      };
      for (final c in _searchResults) {
        byId[c.userId] = c;
      }
      contacts = byId.values.toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
    }
    final contactsLoading = _chat.isContactsLoading && allContacts.isEmpty;
    final groupedBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );

    return CupertinoPageScaffold(
      backgroundColor: groupedBg,
      navigationBar: AppTitleBar(
        title: const Text('Новая группа'),
        // Полупрозрачная — содержимое уходит под размытую шапку.
        backgroundColor: groupedBg.withValues(alpha: 0.7),
        blur: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: AppTitleBar.iconSize),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _creating ? null : _create,
          child: _creating
              ? const CupertinoActivityIndicator()
              : const Text(
                  'Создать',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: Stack(
          children: [
            // То же мягкое пятно, что за шапкой настроек чата.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 420,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.22),
                      AppColors.primary.withValues(alpha: 0.08),
                      groupedBg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Builder(
              // Свой context — под скаффолдом, где в MediaQuery уже учтена
              // высота полупрозрачной шапки.
              builder: (context) => CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + 20,
                    ),
                    sliver: SliverToBoxAdapter(child: _buildHeader(context)),
                  ),
                  SliverToBoxAdapter(
                    child: _sectionLabel(
                      context,
                      _selected.isEmpty
                          ? 'УЧАСТНИКИ'
                          : 'УЧАСТНИКИ • ${_selected.length}',
                      top: 24,
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    SliverToBoxAdapter(child: _buildSelectedStrip(context)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: CupertinoSearchTextField(
                        controller: _searchCtrl,
                        placeholder: 'Поиск',
                      ),
                    ),
                  ),
                  ..._buildContactSlivers(
                    context,
                    contacts: contacts,
                    loading: contactsLoading,
                    noContacts: allContacts.isEmpty && _search.isEmpty,
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Монограмма группы + название и описание. Поля переносят текст на
  /// новые строки, поэтому длинное название не обрезается и не уезжает
  /// в узкую полоску, как было с подписью «Название» слева.
  Widget _buildHeader(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Column(
      children: [
        ListenableBuilder(
          listenable: _nameCtrl,
          builder: (context, _) {
            final name = _nameCtrl.text.trim();
            if (name.isNotEmpty) {
              return MemberAvatar(displayName: name, radius: 44);
            }
            return Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppColors.avatarPlaceholderGradient,
                ),
              ),
              child: const Icon(
                CupertinoIcons.person_3_fill,
                size: 40,
                color: CupertinoColors.white,
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppGlass(
            borderRadius: BorderRadius.circular(22),
            shadows: AppGlass.controlShadow,
            child: Column(
              children: [
                CupertinoTextField(
                  controller: _nameCtrl,
                  placeholder: 'Название группы',
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
                CupertinoTextField(
                  controller: _descCtrl,
                  placeholder: 'Описание (необязательно)',
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
              ],
            ),
          ),
        ),
        if (_nameError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              _nameError!,
              style: const TextStyle(
                color: CupertinoColors.systemRed,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  /// Выбранные участники чипами с переносом по строкам: сразу видно
  /// всех, кого добавил, и любого можно убрать тапом, не листая список.
  Widget _buildSelectedStrip(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in _selected.values)
            GestureDetector(
              onTap: () => _toggle(c),
              child: AppGlass(
                borderRadius: BorderRadius.circular(15),
                shadows: null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MemberAvatar(
                        displayName: c.fullName,
                        avatarUrl: c.avatarUrl,
                        radius: 12,
                      ),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          c.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(CupertinoIcons.xmark, size: 11, color: secondary),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildContactSlivers(
    BuildContext context, {
    required List<ChatContact> contacts,
    required bool loading,
    required bool noContacts,
  }) {
    if (loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: 6,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => const AppSkeletonCardTile(),
          ),
        ),
      ];
    }
    if (contacts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _searching
                ? const Center(child: CupertinoActivityIndicator())
                : Text(
                    noContacts
                        ? 'Нет доступных контактов'
                        : 'Ничего не найдено',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
          ),
        ),
      ];
    }
    // Список строится лениво (контактов бывают сотни), поэтому вместо
    // AppGlass с размытием — та же заливка, кромка и тень без фильтра:
    // под этой частью экрана размывать всё равно нечего.
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: AppColors.glassFill.resolveFrom(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.glassBorder.resolveFrom(context),
            ),
            boxShadow: AppGlass.controlShadow,
          ),
          sliver: SliverList.separated(
            itemCount: contacts.length,
            separatorBuilder: (context, index) => Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 64),
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            itemBuilder: (context, index) {
              final c = contacts[index];
              final checked = _selected.containsKey(c.userId);
              return CupertinoListTile(
                leading: MemberAvatar(
                  displayName: c.fullName,
                  avatarUrl: c.avatarUrl,
                  radius: 18,
                ),
                title: Text(c.fullName),
                trailing: checked
                    ? const Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: AppColors.primary,
                      )
                    : Icon(
                        CupertinoIcons.circle,
                        color: CupertinoColors.systemGrey3.resolveFrom(context),
                      ),
                onTap: () => _toggle(c),
              );
            },
          ),
        ),
      ),
    ];
  }

  Widget _sectionLabel(BuildContext context, String text, {double top = 0}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
