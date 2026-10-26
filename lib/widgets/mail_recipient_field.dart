import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../models/mail/mail_message.dart';
import '../models/staff_user.dart';
import '../repositories/users_repository.dart';
import '../services/mail_contacts_service.dart';
import 'mail_glass.dart';

/// Получатель письма: адрес и, если известно, ФИО — как в Outlook/«Почте»
/// iOS в поле показывается имя, а адрес — по нажатию.
class MailRecipient {
  const MailRecipient({required this.email, this.name = '', this.userId});

  factory MailRecipient.fromStaff(StaffUser user) => MailRecipient(
    email: user.email!.trim(),
    name: user.fullName,
    userId: user.id,
  );

  /// Из `Имя <a@x>` или просто `a@x`.
  factory MailRecipient.parse(String address) {
    final email = mailEmailOnly(address);
    final name = mailDisplayName(address);
    return MailRecipient(email: email, name: name == email ? '' : name);
  }

  final String email;
  final String name;

  /// id сотрудника портала — чтобы шторка выбора показала его отмеченным.
  final String? userId;

  String get displayName => name.isNotEmpty ? name : email;

  String get key => email.toLowerCase();

  bool get isValidEmail =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}

/// Список получателей одного поля («Кому», «Копия», «Скрытая») и строка
/// ввода для нового адреса.
class MailRecipientController extends ChangeNotifier {
  MailRecipientController([Iterable<MailRecipient> initial = const []]) {
    for (final r in initial) {
      if (_add(r) && r.name.isEmpty) _resolveName(r);
    }
  }

  final List<MailRecipient> _recipients = [];
  final input = TextEditingController();

  List<MailRecipient> get recipients => List.unmodifiable(_recipients);

  Set<String> get userIds =>
      _recipients.map((r) => r.userId).whereType<String>().toSet();

  /// Голые адреса — так их принимает сервер.
  List<String> get emails => _recipients.map((r) => r.email).toList();

  bool contains(String email) =>
      _recipients.any((r) => r.key == email.trim().toLowerCase());

  bool get isEmpty => _recipients.isEmpty && input.text.trim().isEmpty;

  /// Отпечаток содержимого — для проверки «есть ли что терять».
  String get snapshot => [...emails, input.text.trim()].join(',');

  void add(MailRecipient recipient) {
    if (_add(recipient)) notifyListeners();
  }

  bool _add(MailRecipient recipient) {
    if (recipient.email.isEmpty || contains(recipient.email)) return false;
    _recipients.add(recipient);
    return true;
  }

  void remove(MailRecipient recipient) {
    _recipients.removeWhere((r) => r.key == recipient.key);
    notifyListeners();
  }

  void removeUser(String userId) {
    _recipients.removeWhere((r) => r.userId == userId);
    notifyListeners();
  }

  void _replace(MailRecipient old, MailRecipient updated) {
    if (_disposed) return;
    final index = _recipients.indexWhere((r) => r.key == old.key);
    if (index < 0) return;
    _recipients[index] = updated;
    notifyListeners();
  }

  /// Переносит набранные адреса из строки ввода в список. Возвращает то,
  /// что не похоже на e-mail, — оно остаётся в строке ввода.
  List<String> commitInput() {
    // Без `Имя <…>` пробел тоже разделяет адреса: «a@x b@y».
    final text = input.text.contains('<')
        ? input.text
        : input.text.replaceAll(RegExp(r'\s+'), ',');
    final parts = MailMessage.splitAddresses(text);
    if (parts.isEmpty) return const [];
    final invalid = <String>[];
    final added = <MailRecipient>[];
    for (final part in parts) {
      final recipient = MailRecipient.parse(part);
      if (!recipient.isValidEmail) {
        invalid.add(part);
      } else if (_add(recipient)) {
        added.add(recipient);
      }
    }
    input.text = invalid.join(', ');
    notifyListeners();
    for (final r in added) {
      if (r.name.isEmpty) _resolveName(r);
    }
    return invalid;
  }

  /// Адрес, набранный вручную, ищем в справочнике сотрудников — чтобы и
  /// у него показывалось ФИО.
  Future<void> _resolveName(MailRecipient recipient) async {
    try {
      final page = await UsersRepository.instance.getPage(q: recipient.email);
      final user = page.data
          .where((u) => (u.email ?? '').trim().toLowerCase() == recipient.key)
          .firstOrNull;
      if (user == null) return;
      _replace(recipient, MailRecipient.fromStaff(user));
    } catch (_) {
      // Без имени тоже можно отправить — покажем адрес.
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    input.dispose();
    super.dispose();
  }
}

/// Поле получателей: подпись слева, получатели друг под другом (без
/// горизонтальной прокрутки), строка ввода и кнопка справочника.
class MailRecipientField extends StatefulWidget {
  const MailRecipientField({
    super.key,
    required this.label,
    required this.controller,
    required this.onPickEmployees,
    this.labelWidth = 72,
    this.placeholder,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final MailRecipientController controller;
  final VoidCallback onPickEmployees;
  final double labelWidth;
  final String? placeholder;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  State<MailRecipientField> createState() => _MailRecipientFieldState();
}

class _MailRecipientFieldState extends State<MailRecipientField> {
  final _focusNode = FocusNode();

  /// Получатели, у которых раскрыт адрес.
  final Set<String> _expanded = {};

  /// Подсказки под строкой ввода: сначала те, с кем уже переписывались,
  /// затем сотрудники из справочника.
  List<MailRecipient> _suggestions = const [];
  int _suggestVersion = 0;
  Timer? _staffSearch;

  static const _maxSuggestions = 6;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.controller.commitInput();
        _clearSuggestions();
      }
    });
  }

  @override
  void dispose() {
    _staffSearch?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _clearSuggestions() {
    _suggestVersion++;
    _staffSearch?.cancel();
    if (_suggestions.isNotEmpty && mounted) {
      setState(() => _suggestions = const []);
    }
  }

  Future<void> _updateSuggestions() async {
    final query = widget.controller.input.text.trim();
    if (query.isEmpty || !_focusNode.hasFocus) {
      _clearSuggestions();
      return;
    }
    final version = ++_suggestVersion;
    _staffSearch?.cancel();
    final taken = widget.controller.recipients.map((r) => r.key).toSet();
    final recent = await MailContactsService.instance.suggest(
      query,
      exclude: taken,
    );
    if (!mounted || version != _suggestVersion) return;
    setState(() => _suggestions = recent);
    if (query.length < 2 || recent.length >= _maxSuggestions) return;
    _staffSearch = Timer(const Duration(milliseconds: 300), () async {
      try {
        final page = await UsersRepository.instance.getPage(q: query);
        if (!mounted || version != _suggestVersion) return;
        final seen = {...taken, ...recent.map((r) => r.key)};
        final staff = page.data
            .where((u) => (u.email ?? '').trim().isNotEmpty)
            .map(MailRecipient.fromStaff)
            .where((r) => seen.add(r.key));
        setState(
          () => _suggestions = [
            ...recent,
            ...staff,
          ].take(_maxSuggestions).toList(),
        );
      } catch (_) {
        // Без справочника остаются подсказки из переписки.
      }
    });
  }

  void _pickSuggestion(MailRecipient recipient) {
    widget.controller.input.clear();
    widget.controller.add(recipient);
    _clearSuggestions();
    widget.onChanged?.call();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onInputChanged(String text) {
    // Запятая, «;» или пробел после адреса — адрес готов.
    if (RegExp(r'[,;]|@\S+\s').hasMatch(text)) {
      widget.controller.commitInput();
    }
    _updateSuggestions();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final recipients = widget.controller.recipients;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: widget.labelWidth,
              child: Text(
                widget.label,
                style: TextStyle(fontSize: 15, color: secondary),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in recipients) _recipientRow(context, r),
                CupertinoTextField(
                  controller: widget.controller.input,
                  focusNode: _focusNode,
                  placeholder: recipients.isEmpty ? widget.placeholder : null,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enabled: widget.enabled,
                  decoration: const BoxDecoration(),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  style: TextStyle(fontSize: 15, color: label),
                  onChanged: _onInputChanged,
                  onSubmitted: (_) {
                    widget.controller.commitInput();
                    _clearSuggestions();
                  },
                ),
                // Нажатие на подсказку — «внутри» поля: фокус и набранный
                // текст не теряются до выбора.
                if (_suggestions.isNotEmpty)
                  TextFieldTapRegion(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final r in _suggestions)
                          _suggestionRow(context, r),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 40),
            onPressed: widget.enabled ? widget.onPickEmployees : null,
            child: Icon(
              CupertinoIcons.person_crop_circle_badge_plus,
              size: 24,
              color: label,
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow(BuildContext context, MailRecipient r) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickSuggestion(r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            if (r.name.isNotEmpty)
              Text(
                r.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recipientRow(BuildContext context, MailRecipient r) {
    final hasName = r.name.isNotEmpty;
    final expanded = hasName && _expanded.contains(r.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasName
          ? () => setState(() {
              if (!_expanded.remove(r.key)) _expanded.add(r.key);
            })
          : null,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.systemBlue.resolveFrom(context),
                    ),
                  ),
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        r.email,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8),
              minimumSize: const Size(28, 20),
              onPressed: widget.enabled
                  ? () {
                      _expanded.remove(r.key);
                      widget.controller.remove(r);
                      widget.onChanged?.call();
                    }
                  : null,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 18,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
