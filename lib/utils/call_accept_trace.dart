import 'package:connect/services/crash_reporting_service.dart';

/// Временная диагностика "тормозов" между Accept входящего звонка (в т.ч.
/// когда приложение было полностью убито) и реальным входом в Jitsi.
///
/// Собирает тайминги ключевых шагов cold start (main.dart) и последующего
/// _onAccept (IncomingCallService), но отправляет их в Crashlytics только
/// если по факту нашёлся принятый звонок — иначе трасса не интересна и
/// просто шумит на каждом обычном открытии приложения.
///
/// Убрать после того, как найдём и устраним причину задержек.
class CallAcceptTrace {
  CallAcceptTrace._();

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static final List<String> _marks = [];
  static bool _flushed = false;

  static void mark(String stage) {
    _marks.add('$stage=${_stopwatch.elapsedMilliseconds}ms');
  }

  /// Отправить накопленную трассу как нефатальное событие. Идемпотентно —
  /// повторные вызовы после первого ничего не делают, чтобы не плодить
  /// дубли, если _onAccept вызывается несколько раз за один cold start.
  static void flush({required String reason}) {
    if (_flushed || _marks.isEmpty) return;
    _flushed = true;
    CrashReportingService.recordNonFatal(
      Exception('call_accept_trace: ${_marks.join(' | ')}'),
      StackTrace.empty,
      reason: reason,
    );
  }
}
