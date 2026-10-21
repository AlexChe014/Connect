import 'package:flutter/foundation.dart';

import '../models/surveys/survey_invitation.dart';
import '../repositories/surveys_repository.dart';
import 'auth_service.dart';

/// Приглашения в опросы текущего пользователя — источник бейджа «Опросы»
/// в боковом меню и точки на кнопке меню.
class SurveyPendingService extends ChangeNotifier {
  SurveyPendingService({
    Future<List<SurveyInvitation>> Function()? load,
    DateTime Function()? now,
  }) : _load = load ?? SurveysRepository.instance.getMyInvitations,
       _now = now ?? DateTime.now;
  static final instance = SurveyPendingService();

  final Future<List<SurveyInvitation>> Function() _load;
  final DateTime Function() _now;

  List<SurveyInvitation> _invitations = const [];
  List<SurveyInvitation> get invitations => _invitations;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  bool _isRefreshing = false;
  bool _refreshAgain = false;
  int _generation = 0;

  int get pendingCount => _invitations.where((i) => i.isPending(_now())).length;

  Future<void> refresh() async {
    if (_isRefreshing) {
      _refreshAgain = true;
      return;
    }
    _isRefreshing = true;
    final generation = _generation;
    final session = AuthService.instance.sessionGeneration;
    try {
      final invitations = await _load();
      if (generation != _generation ||
          session != AuthService.instance.sessionGeneration) {
        return;
      }
      _invitations = List.unmodifiable(invitations);
      _loaded = true;
      notifyListeners();
    } finally {
      _isRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        await _refreshQuietly();
      }
    }
  }

  /// Фоновое обновление бейджа: при ошибке сети остаётся последнее значение.
  Future<void> refreshQuietly() => _refreshQuietly();

  Future<void> _refreshQuietly() async {
    try {
      await refresh();
    } catch (_) {}
  }

  /// Локально снимает маркер «Новый», не дожидаясь перезагрузки.
  void markOpened(String token) => _update(
    token,
    (i) => SurveyRecipientStatus.unopened.contains(i.status)
        ? i.copyWith(status: SurveyRecipientStatus.opened)
        : i,
  );

  /// Локально помечает приглашение пройденным, не дожидаясь перезагрузки.
  void markCompleted(String token) => _update(
    token,
    (i) => i.isCompleted
        ? i
        : i.copyWith(
            status: SurveyRecipientStatus.completed,
            completedAt: _now(),
          ),
  );

  void _update(
    String token,
    SurveyInvitation Function(SurveyInvitation) change,
  ) {
    var changed = false;
    _invitations = List.unmodifiable(
      _invitations.map((i) {
        if (i.token != token) return i;
        final next = change(i);
        if (!identical(next, i)) changed = true;
        return next;
      }),
    );
    if (changed) notifyListeners();
  }

  void reset() {
    _generation++;
    _refreshAgain = false;
    _loaded = false;
    _invitations = const [];
    notifyListeners();
  }
}
