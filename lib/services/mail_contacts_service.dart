import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/mail_recipient_field.dart';
import 'auth_service.dart';

/// Адресаты, с которыми идёт переписка: кому писали из приложения и чьи
/// письма открывали. Из них — подсказки в поле «Кому» по мере ввода.
///
/// Хранится только на телефоне, отдельно для каждого пользователя;
/// удаляется при выходе из аккаунта.
class MailContactsService {
  MailContactsService._();
  static final MailContactsService instance = MailContactsService._();

  static const _maxContacts = 300;

  /// Рассылки и автоответчики в подсказках не нужны.
  static final _robot = RegExp(
    r'no-?reply|do-?not-?reply|mailer-daemon|postmaster|notifications?@',
    caseSensitive: false,
  );

  String? _loadedFor;
  final Map<String, _Contact> _contacts = {};

  Future<String?> _prefsKey() async {
    final user = await AuthService.instance.getStoredUser();
    final id = user?['id']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return 'mail_contacts_u$id';
  }

  Future<String?> _ensureLoaded() async {
    final key = await _prefsKey();
    if (key == null || key == _loadedFor) return key;
    _contacts.clear();
    _loadedFor = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null) {
        for (final item in jsonDecode(raw) as List) {
          final contact = _Contact.fromJson(item as Map<String, dynamic>);
          if (contact.email.isNotEmpty) _contacts[contact.key] = contact;
        }
      }
    } catch (_) {
      // Испорченная запись — начнём список заново.
    }
    return key;
  }

  Future<void> _save(String key) async {
    final sorted = _contacts.values.toList()
      ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
    if (sorted.length > _maxContacts) {
      for (final old in sorted.skip(_maxContacts)) {
        _contacts.remove(old.key);
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(sorted.take(_maxContacts).map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Письмо отправлено этим людям.
  Future<void> rememberSent(Iterable<MailRecipient> recipients) =>
      _remember(recipients, sent: true);

  /// Открыто письмо от этого человека.
  Future<void> rememberReceived(MailRecipient sender) =>
      _remember([sender], sent: false);

  Future<void> _remember(
    Iterable<MailRecipient> recipients, {
    required bool sent,
  }) async {
    final key = await _ensureLoaded();
    if (key == null) return;
    final now = DateTime.now();
    var changed = false;
    for (final r in recipients) {
      if (!r.isValidEmail || _robot.hasMatch(r.email)) continue;
      final contact = _contacts.putIfAbsent(
        r.key,
        () => _Contact(email: r.email),
      );
      if (r.name.isNotEmpty) contact.name = r.name;
      if (sent) {
        contact.sent++;
      } else {
        contact.received++;
      }
      contact.lastAt = now;
      changed = true;
    }
    if (changed) await _save(key);
  }

  /// Подходящие под набранный текст — по началу слова в ФИО или адресе;
  /// сначала те, с кем переписка чаще и свежее.
  Future<List<MailRecipient>> suggest(
    String query, {
    Set<String> exclude = const {},
    int limit = 4,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    await _ensureLoaded();
    final now = DateTime.now();
    final matches =
        _contacts.values
            .where((c) => !exclude.contains(c.key) && c.matches(q))
            .toList()
          ..sort((a, b) => b.score(now).compareTo(a.score(now)));
    return [
      for (final c in matches.take(limit))
        MailRecipient(email: c.email, name: c.name),
    ];
  }

  Future<void> clear() async {
    final key = await _prefsKey();
    _contacts.clear();
    _loadedFor = null;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}

class _Contact {
  _Contact({
    required this.email,
    this.name = '',
    this.sent = 0,
    this.received = 0,
    DateTime? lastAt,
  }) : lastAt = lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory _Contact.fromJson(Map<String, dynamic> json) => _Contact(
    email: (json['e'] ?? '').toString(),
    name: (json['n'] ?? '').toString(),
    sent: (json['s'] as num?)?.toInt() ?? 0,
    received: (json['r'] as num?)?.toInt() ?? 0,
    lastAt: DateTime.fromMillisecondsSinceEpoch(
      (json['t'] as num?)?.toInt() ?? 0,
    ),
  );

  final String email;
  String name;
  int sent;
  int received;
  DateTime lastAt;

  String get key => email.toLowerCase();

  Map<String, dynamic> toJson() => {
    'e': email,
    if (name.isNotEmpty) 'n': name,
    's': sent,
    'r': received,
    't': lastAt.millisecondsSinceEpoch,
  };

  bool matches(String q) {
    if (key.startsWith(q)) return true;
    final words = name.toLowerCase().split(RegExp(r'\s+'));
    if (words.any((w) => w.startsWith(q))) return true;
    // «ив пе» — Иванов Пётр.
    final parts = q.split(RegExp(r'\s+'));
    return parts.length > 1 &&
        parts.every((p) => words.any((w) => w.startsWith(p)));
  }

  /// Написать самому весомее, чем получить; давняя переписка тускнеет.
  double score(DateTime now) {
    final days = now.difference(lastAt).inDays;
    return (sent * 3 + received) / (1 + days / 30);
  }
}
