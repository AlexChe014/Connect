import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:connect/config/app_theme.dart';
import 'package:connect/config/call_config.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_call_status.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/widgets/call_glass.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Результат экрана «Звоним…».
enum OutgoingCallOutcome {
  /// Собеседник ответил — входим в комнату.
  proceed,

  /// Пользователь нажал «Отменить».
  cancelled,

  /// Истёк таймер дозвона.
  timeout,

  /// Звонок завершён другой стороной/сервером (отклонён, занято, пропущен)
  /// или не создан — серверу сообщать ничего не нужно.
  failed,
}

/// Полноэкранный экран «Звоним {имя}…» для исходящего звонка из личного чата.
///
/// Показывается после успешного создания встречи и `ring`-запроса, перед
/// входом в Jitsi. Статус приходит в [ChatCallService.applySignal] из push,
/// Reverb и опроса `GET /chat/call/{id}`. Закрывается сам, когда:
/// - собеседник принял звонок (на телефоне или в вебе) — сразу входим;
/// - собеседник отклонил звонок, занят, или сервер завершил его по таймауту;
/// - истекло локальное время ожидания — «Нет ответа», в Jitsi не заходим;
/// - пользователь нажал «Отменить».
class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
    super.key,
    required this.chat,
    this.callId,
    this.initialFailure,
  });

  final Chat chat;

  /// `null`, если сервер не создал звонок — тогда задан [initialFailure].
  final String? callId;

  /// Звонок не состоялся ещё на этапе `ring` (занято, ошибка) —
  /// показываем причину и закрываемся.
  final ChatCallStatus? initialFailure;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  final AudioPlayer _ringbackPlayer = AudioPlayer();
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  String? _statusOverride;
  bool _ringing = false;
  bool _resolved = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    final failure = widget.initialFailure;
    final callId = widget.callId;
    if (callId != null && ChatCallService.instance.isAccepted(callId)) {
      // Встречный вызов: сервер сразу соединил — гудки не нужны.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resolve(OutgoingCallOutcome.proceed),
      );
      return;
    }
    if (failure != null || callId == null) {
      _statusOverride = _statusLabel(failure ?? ChatCallStatus.failed);
      _closing = true;
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        _resolve(OutgoingCallOutcome.failed);
      });
      return;
    }

    unawaited(_playRingback());
    ChatCallService.instance.addListener(_onCallServiceChanged);
    // Статус мог смениться, пока экран открывался.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onCallServiceChanged(),
    );

    _pollTimer = Timer.periodic(CallConfig.outgoingStatusPollInterval, (_) {
      if (_resolved || _closing) return;
      unawaited(ChatCallService.instance.pollCallStatus(callId));
    });

    _timeoutTimer = Timer(CallConfig.outgoingRingTimeout, () {
      if (_resolved || _closing) return;
      _closeWith('Нет ответа', OutgoingCallOutcome.timeout);
    });
  }

  Future<void> _playRingback() async {
    try {
      await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer.play(AssetSource('sounds/ringback_tone.wav'));
    } catch (_) {
      // Гудок — приятное дополнение, не критично, если не заиграл.
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    ChatCallService.instance.removeListener(_onCallServiceChanged);
    _pulseController.dispose();
    unawaited(_ringbackPlayer.stop());
    unawaited(_ringbackPlayer.dispose());
    super.dispose();
  }

  void _onCallServiceChanged() {
    final callId = widget.callId;
    if (callId == null || _resolved || _closing || !mounted) return;
    final service = ChatCallService.instance;

    if (service.isAccepted(callId)) {
      _resolve(OutgoingCallOutcome.proceed);
      return;
    }

    final status = service.endedStatusFor(callId);
    if (status != null) {
      _closeWith(_statusLabel(status), OutgoingCallOutcome.failed);
      return;
    }

    if (!_ringing && service.isRinging(callId)) {
      setState(() => _ringing = true);
    }
  }

  String _statusLabel(ChatCallStatus status) {
    return switch (status) {
      ChatCallStatus.declined ||
      ChatCallStatus.declinedElsewhere => 'Звонок отклонён',
      ChatCallStatus.missed => 'Нет ответа',
      ChatCallStatus.busy => 'Абонент занят',
      ChatCallStatus.failed => 'Не удалось дозвониться',
      _ => 'Звонок завершён',
    };
  }

  /// Показать причину ~1 с и закрыть экран.
  void _closeWith(String label, OutgoingCallOutcome outcome) {
    if (_closing || _resolved || !mounted) return;
    _closing = true;
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    unawaited(_ringbackPlayer.stop());
    setState(() => _statusOverride = label);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      _resolve(outcome);
    });
  }

  void _resolve(OutgoingCallOutcome outcome) {
    if (_resolved || !mounted) return;
    _resolved = true;
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    Navigator.of(context).pop(outcome);
  }

  void _cancel() {
    if (_closing) return;
    _resolve(OutgoingCallOutcome.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: CupertinoPageScaffold(
          backgroundColor: AppCallColors.backgroundBottom,
          // Тот же фон и кнопки, что у экрана разговора (CallOverlayHost):
          // после ответа экран не «перескакивает» в другой стиль.
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CallBackground(),
              SafeArea(
                // SafeArea/CupertinoPageScaffold дают этому экрану loose-
                // констрейнты по ширине, поэтому Column без принудительной
                // ширины схлопывается по самому широкому ребёнку (обычно по
                // имени), и «центрированные» элементы уезжают влево.
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1 + _pulseController.value * 0.08;
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppCallColors.glowBlue.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 52,
                              ),
                            ],
                          ),
                          child: ChatAvatar(chat: chat, radius: 64),
                        ),
                      ),
                      const SizedBox(height: 44),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          chat.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppCallColors.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusOverride ??
                            (_ringing ? 'Идут гудки…' : 'Вызов…'),
                        style: const TextStyle(
                          color: AppCallColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(flex: 3),
                      CallRoundButton(
                        icon: CupertinoIcons.phone_down_fill,
                        label: 'Отменить',
                        destructive: true,
                        size: 72,
                        onPressed: _statusOverride == null ? _cancel : null,
                      ),
                      const SizedBox(height: 40),
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
