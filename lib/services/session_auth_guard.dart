import 'dart:async';

/// Следит за ошибками аутентификации API и решает, мертва ли сессия.
///
/// Один 401 ещё не повод разлогинивать: часть эндпоинтов (например, 1С)
/// отвечает Unauthenticated при живом токене приложения. Разлогин только если
/// в окне debounce не было успешных запросов **и** проверочный запрос к бэку
/// тоже вернул ошибку аутентификации.
class SessionAuthGuard {
  SessionAuthGuard({
    required this.isAuthenticated,
    required this.sessionGeneration,
    required this.verifySession,
    required this.onExpired,
    this.debounce = const Duration(milliseconds: 400),
    this.probeCooldown = const Duration(seconds: 30),
  });

  final bool Function() isAuthenticated;
  final int Function() sessionGeneration;

  /// `true` — бэкенд ответил 401, `false` — сессия жива, `null` — неизвестно
  /// (сеть, 5xx): в этом случае пользователя не выкидываем.
  final Future<bool?> Function() verifySession;
  final Future<void> Function() onExpired;

  final Duration debounce;
  final Duration probeCooldown;

  Timer? _debounce;
  int _authFailures = 0;
  int _successes = 0;
  bool _checking = false;
  DateTime? _lastValidProbeAt;

  void noteSuccess({required int generation}) {
    if (generation != sessionGeneration()) return;
    _successes++;
    _authFailures = 0;
    _debounce?.cancel();
    _debounce = null;
  }

  void noteAuthFailure({required int generation}) {
    if (!isAuthenticated()) return;
    if (generation != sessionGeneration()) return;
    if (_checking) return;
    if (_inProbeCooldown) return;

    _authFailures++;
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      unawaited(_evaluate(generation));
    });
  }

  void reset() {
    _debounce?.cancel();
    _debounce = null;
    _authFailures = 0;
    _successes = 0;
    _checking = false;
    _lastValidProbeAt = null;
  }

  bool get _inProbeCooldown {
    final at = _lastValidProbeAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < probeCooldown;
  }

  Future<void> _evaluate(int generation) async {
    _debounce = null;
    if (_checking) return;
    if (!isAuthenticated()) return;
    if (generation != sessionGeneration()) return;

    if (_successes > 0 || _authFailures == 0) {
      _authFailures = 0;
      _successes = 0;
      return;
    }

    _checking = true;
    try {
      final unauthenticated = await verifySession();
      if (generation != sessionGeneration()) return;
      if (!isAuthenticated()) return;

      if (unauthenticated == true) {
        await onExpired();
      } else if (unauthenticated == false) {
        _lastValidProbeAt = DateTime.now();
        _authFailures = 0;
        _successes = 0;
      } else {
        _authFailures = 0;
        _successes = 0;
      }
    } finally {
      _checking = false;
    }
  }
}
