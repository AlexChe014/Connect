import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:connect/widgets/home_shortcut_button.dart';
import 'package:flutter/cupertino.dart';

/// Результат экрана «Звоним…»: продолжить (войти в комнату) или отменить.
enum OutgoingCallOutcome { proceed, cancelled }

/// Сколько ждём ответа собеседника, прежде чем считать звонок пропущенным —
/// как реальный дозвон (4-5 гудков по ~5 сек).
const outgoingCallRingTimeout = Duration(seconds: 25);

/// Полноэкранный экран «Звоним {имя}…» для исходящего звонка из личного чата.
///
/// Показывается после успешного создания встречи и `ring`-запроса, перед
/// входом в Jitsi. Закрывается сам, когда:
/// - собеседник принял звонок (push `chat_call_accepted`) — сразу входим;
/// - собеседник отклонил звонок (push `chat_call_ended`, см. [ChatCallService]);
/// - истекло время ожидания без ответа — «Нет ответа», в Jitsi не заходим;
/// - пользователь нажал «Отменить».
class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({super.key, required this.chat, this.callId});

  final Chat chat;

  /// `null`, если сервер не вернул `call_id` (например, ring-запрос не удался) —
  /// экран всё равно отработает по таймеру, просто без сигнала об отклонении.
  final String? callId;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  final AudioPlayer _ringbackPlayer = AudioPlayer();
  Timer? _timeoutTimer;
  String? _statusOverride;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    unawaited(_playRingback());
    HomeShortcutButton.suppressed.value = true;

    final callId = widget.callId;
    if (callId != null) {
      ChatCallService.instance.addListener(_onCallServiceChanged);
    }

    _timeoutTimer = Timer(outgoingCallRingTimeout, () {
      if (_resolved) return;
      setState(() => _statusOverride = 'Нет ответа');
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        _resolve(OutgoingCallOutcome.cancelled);
      });
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
    HomeShortcutButton.suppressed.value = false;
    _timeoutTimer?.cancel();
    ChatCallService.instance.removeListener(_onCallServiceChanged);
    _pulseController.dispose();
    unawaited(_ringbackPlayer.stop());
    unawaited(_ringbackPlayer.dispose());
    super.dispose();
  }

  void _onCallServiceChanged() {
    final callId = widget.callId;
    if (callId == null || _resolved) return;

    if (ChatCallService.instance.isAccepted(callId)) {
      _resolve(OutgoingCallOutcome.proceed);
      return;
    }

    final status = ChatCallService.instance.endedStatusFor(callId);
    if (status == null) return;

    setState(() => _statusOverride = _statusLabel(status));

    // Даём пользователю секунду увидеть причину, прежде чем закрыть экран.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      _resolve(OutgoingCallOutcome.cancelled);
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'declined':
        return 'Звонок отклонён';
      case 'missed':
        return 'Нет ответа';
      default:
        return 'Звонок завершён';
    }
  }

  void _resolve(OutgoingCallOutcome outcome) {
    if (_resolved || !mounted) return;
    _resolved = true;
    _timeoutTimer?.cancel();
    Navigator.of(context).pop(outcome);
  }

  void _cancel() => _resolve(OutgoingCallOutcome.cancelled);

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        child: SafeArea(
          // SafeArea/CupertinoPageScaffold дают этому экрану loose-констрейнты
          // по ширине (в отличие от ListView/CustomScrollView на других экранах),
          // поэтому Column без принудительной ширины схлопывается по самому
          // широкому ребёнку (обычно по имени) вместо всей ширины экрана —
          // и все «центрированные» элементы визуально уезжают влево.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                const Spacer(flex: 2),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1 + _pulseController.value * 0.12;
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: ChatAvatar(chat: chat, radius: 56),
                ),
                const SizedBox(height: 24),
                Text(
                  chat.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _statusOverride ?? 'Звоним…',
                  style: TextStyle(
                    color: CupertinoColors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
                const Spacer(flex: 3),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _statusOverride == null ? _cancel : null,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: CupertinoColors.destructiveRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.phone_down_fill,
                      color: CupertinoColors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Отменить',
                  style: TextStyle(color: CupertinoColors.white, fontSize: 14),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
