import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/users_repository.dart';
import '../widgets/mail_glass.dart';

/// ФИО для адресов без имени. Письма из приложения уходят с голыми адресами,
/// поэтому в «Отправленных» имени нет ни в заголовке, ни на сервере; ищем
/// его в справочнике сотрудников. Внешние адреса так и остаются адресами.
///
/// [displayName] сразу отвечает тем, что известно, а поиск идёт в фоне:
/// когда имя найдено, срабатывают слушатели.
class MailNameResolver extends ChangeNotifier {
  MailNameResolver({Future<String?> Function(String email)? lookup})
    : _lookup = lookup ?? _lookupInDirectory;

  static final MailNameResolver instance = MailNameResolver();

  static const _maxConcurrent = 4;
  static const _retryDelay = Duration(minutes: 1);

  final Future<String?> Function(String email) _lookup;

  /// Адрес в нижнем регистре → ФИО; пустая строка — такого сотрудника нет.
  final Map<String, String> _names = {};
  final Map<String, DateTime> _failedAt = {};
  final Set<String> _pending = {};
  final List<String> _queue = [];
  int _active = 0;

  /// Меняется при выходе из аккаунта: ответы старых запросов не сохраняем.
  int _generation = 0;

  String displayName(String address) {
    final shown = mailDisplayName(address);
    final email = mailEmailOnly(address);
    if (shown != email || !email.contains('@')) return shown;

    final key = email.toLowerCase();
    final name = _names[key];
    if (name != null) return name.isEmpty ? shown : name;
    _enqueue(key);
    return shown;
  }

  void clear() {
    _generation++;
    _names.clear();
    _failedAt.clear();
    _pending.clear();
    _queue.clear();
  }

  void _enqueue(String key) {
    if (_pending.contains(key)) return;
    final failedAt = _failedAt[key];
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryDelay) {
      return;
    }
    _pending.add(key);
    _queue.add(key);
    // Вызывается из build: запросы и уведомления — уже после него.
    scheduleMicrotask(_drain);
  }

  void _drain() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      _active++;
      unawaited(_resolve(_queue.removeAt(0)));
    }
  }

  Future<void> _resolve(String key) async {
    final generation = _generation;
    String? name;
    var failed = false;
    try {
      name = await _lookup(key);
    } catch (_) {
      failed = true;
    }
    _active--;
    if (generation == _generation) {
      _pending.remove(key);
      if (failed) {
        _failedAt[key] = DateTime.now();
      } else {
        _failedAt.remove(key);
        _names[key] = name?.trim() ?? '';
        if (_names[key]!.isNotEmpty) notifyListeners();
      }
    }
    _drain();
  }

  static Future<String?> _lookupInDirectory(String email) async {
    final page = await UsersRepository.instance.getPage(q: email);
    return page.data
        .where((u) => (u.email ?? '').trim().toLowerCase() == email)
        .firstOrNull
        ?.fullName;
  }
}
