import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/call_conference.dart';
import 'chat_avatar.dart';

/// Фон экрана звонка: тёмный градиент и медленно плывущие пятна света.
class CallBackground extends StatefulWidget {
  const CallBackground({super.key});

  @override
  State<CallBackground> createState() => _CallBackgroundState();
}

class _CallBackgroundState extends State<CallBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppCallColors.backgroundTop,
              AppCallColors.backgroundBottom,
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _drift,
          builder: (context, _) {
            final t = _drift.value * 2 * math.pi;
            return Stack(
              fit: StackFit.expand,
              children: [
                _Glow(
                  color: AppCallColors.glowBlue,
                  alignment: Alignment(
                    -0.7 + 0.25 * math.sin(t),
                    -0.55 + 0.1 * math.cos(t),
                  ),
                  size: 420,
                  opacity: 0.55,
                ),
                _Glow(
                  color: AppCallColors.glowViolet,
                  alignment: Alignment(
                    0.8 + 0.2 * math.cos(t),
                    -0.1 + 0.15 * math.sin(t),
                  ),
                  size: 360,
                  opacity: 0.4,
                ),
                _Glow(
                  color: AppCallColors.glowCyan,
                  alignment: Alignment(-0.2 + 0.3 * math.sin(t + 2), 0.75),
                  size: 320,
                  opacity: 0.22,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.color,
    required this.alignment,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final Alignment alignment;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка экрана звонка с подписью.
///
/// Без BackdropFilter: под кнопками может оказаться видео Jitsi (platform
/// view), а размытие поверх нативного вида — лишняя нагрузка и артефакты.
/// Стекло изображают полупрозрачная заливка, блик сверху и светлая кромка.
class CallRoundButton extends StatefulWidget {
  const CallRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.destructive = false,
    this.size = 64,
    this.badge = 0,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;

  /// Светлая кнопка с тёмной иконкой: функция включена.
  final bool active;

  /// Красная кнопка «Завершить».
  final bool destructive;
  final double size;

  /// Счётчик (непрочитанные в чате встречи).
  final int badge;

  @override
  State<CallRoundButton> createState() => _CallRoundButtonState();
}

class _CallRoundButtonState extends State<CallRoundButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final Color fill;
    final Color iconColor;
    if (widget.destructive) {
      fill = AppCallColors.hangUp;
      iconColor = AppCallColors.textPrimary;
    } else if (widget.active) {
      fill = AppCallColors.buttonActiveFill;
      iconColor = AppCallColors.buttonActiveIcon;
    } else {
      fill = AppCallColors.buttonFill;
      iconColor = AppCallColors.textPrimary;
    }

    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.destructive || widget.active ? fill : null,
        border: widget.destructive || widget.active
            ? null
            : Border.all(color: AppCallColors.buttonBorder, width: 0.8),
        gradient: widget.destructive || widget.active
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppCallColors.buttonFill.withValues(alpha: 0.32),
                  AppCallColors.buttonFill.withValues(alpha: 0.14),
                ],
              ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween(begin: 0.7, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          widget.icon,
          key: ValueKey(widget.icon),
          size: widget.size * 0.42,
          color: iconColor,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: enabled
            ? () {
                if (widget.destructive) {
                  HapticFeedback.mediumImpact();
                } else {
                  HapticFeedback.selectionClick();
                }
                widget.onPressed!();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 120),
                scale: _pressed ? 0.9 : 1,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    circle,
                    if (widget.badge > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: _CountBadge(count: widget.badge),
                      ),
                  ],
                ),
              ),
              if (widget.label != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppCallColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppCallColors.mutedBadge,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppCallColors.backgroundBottom, width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: AppCallColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Маленькая стеклянная кнопка-иконка (свернуть, перевернуть камеру).
class CallIconButton extends StatelessWidget {
  const CallIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.square(size),
        onPressed: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed!();
              },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppCallColors.buttonFill,
            border: Border.all(color: AppCallColors.buttonBorder, width: 0.8),
          ),
          child: Icon(
            icon,
            size: size * 0.48,
            color: AppCallColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Капсула со значком и текстом (число участников, «микрофон выключен»).
class CallPill extends StatelessWidget {
  const CallPill({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor = AppCallColors.textPrimary,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppCallColors.buttonFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppCallColors.buttonBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppCallColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: pill,
    );
  }
}

/// «Соединение…», «00:42», «Звонок завершён» — тикает сам раз в секунду.
class CallStatusText extends StatefulWidget {
  const CallStatusText({
    super.key,
    required this.conference,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final CallConference conference;
  final TextStyle? style;
  final TextAlign textAlign;

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  State<CallStatusText> createState() => _CallStatusTextState();
}

class _CallStatusTextState extends State<CallStatusText> {
  Timer? _ticker;

  /// Длительность на момент завершения — дальше не тикает.
  Duration? _frozen;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _text() {
    final c = widget.conference;
    final started = c.startedAt;
    switch (c.phase) {
      case CallPhase.connecting:
        return 'Соединение…';
      case CallPhase.waiting:
        return c.isDirect ? 'Ожидание собеседника…' : 'Вы в звонке одни';
      case CallPhase.reconnecting:
        return 'Переподключение…';
      case CallPhase.ending:
        if (started == null) return 'Звонок завершён';
        _frozen ??= DateTime.now().difference(started);
        return 'Звонок завершён · ${CallStatusText.formatDuration(_frozen!)}';
      case CallPhase.active:
        if (started == null) return 'Соединение…';
        return CallStatusText.formatDuration(
          DateTime.now().difference(started),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text(),
      textAlign: widget.textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          widget.style ??
          const TextStyle(
            color: AppCallColors.textSecondary,
            fontSize: 15,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
    );
  }
}

/// 1:1 без видео: крупный аватар собеседника на фоне звонка — вместо
/// чёрного кадра Jitsi с кружком.
class CallAudioStage extends StatefulWidget {
  const CallAudioStage({
    super.key,
    required this.conference,
    this.compact = false,
  });

  final CallConference conference;

  /// Свёрнутое окошко: только аватар.
  final bool compact;

  @override
  State<CallAudioStage> createState() => _CallAudioStageState();
}

class _CallAudioStageState extends State<CallAudioStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conference;
    final name = c.title.isNotEmpty ? c.title : (c.peer?.name ?? '');
    final radius = widget.compact ? 30.0 : 64.0;
    // Пульсирует, пока ждём соединения или собеседника; в разговоре —
    // спокойное «дыхание».
    final waiting = c.phase != CallPhase.active;

    final avatar = AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return CustomPaint(
          painter: _RingsPainter(
            progress: _pulse.value,
            radius: radius,
            strength: waiting ? 1 : 0.45,
          ),
          child: child,
        );
      },
      child: Padding(
        padding: EdgeInsets.all(radius * 0.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppCallColors.glowBlue.withValues(alpha: 0.45),
                blurRadius: radius * 0.8,
              ),
            ],
          ),
          child: MemberAvatar(
            displayName: name.isEmpty ? '?' : name,
            avatarUrl: c.avatarUrl,
            radius: radius,
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        const CallBackground(),
        if (widget.compact)
          Center(child: avatar)
        else
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                avatar,
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    name,
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
                CallStatusText(conference: c),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: c.peer?.audioOn == false && c.phase == CallPhase.active
                      ? const CallPill(
                          key: ValueKey('peer-muted'),
                          icon: CupertinoIcons.mic_slash_fill,
                          iconColor: AppCallColors.mutedBadge,
                          text: 'Микрофон собеседника выключен',
                        )
                      : const SizedBox(key: ValueKey('none'), height: 32),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
      ],
    );
  }
}

/// Расходящиеся кольца вокруг аватара.
class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.progress,
    required this.radius,
    required this.strength,
  });

  final double progress;
  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final r = radius * (1.0 + 0.5 * t);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppCallColors.textPrimary.withValues(
          alpha: (1 - t) * 0.35 * strength,
        );
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.progress != progress || old.strength != strength;
}
