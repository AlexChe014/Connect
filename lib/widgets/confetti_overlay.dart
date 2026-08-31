import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';

const List<Color> kConfettiColors = [
  AppColors.primary,
  Color(0xFFFFC542),
  Color(0xFF0B2545),
  CupertinoColors.white,
];

class _ConfettiParticle {
  _ConfettiParticle(Random random, List<Color> colors)
    : angle = random.nextDouble() * 2 * pi,
      speed = 90 + random.nextDouble() * 130,
      size = 4 + random.nextDouble() * 6,
      spin = (random.nextDouble() * 2 - 1) * 8,
      color = colors[random.nextInt(colors.length)];

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
}

/// Разлетающиеся конфетти поверх карточки результата — используется в
/// диалогах "поздравляем" (выигрыш в колесе, успешная покупка в магазине).
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, this.colors = kConfettiColors});

  final List<Color> colors;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    final random = Random();
    _particles = List.generate(
      28,
      (_) => _ConfettiParticle(random, widget.colors),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _ConfettiPainter(_particles, _controller.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);

  final List<_ConfettiParticle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final opacity = (1 - t).clamp(0.0, 1.0);
    for (final p in particles) {
      final distance = p.speed * t;
      final dx = cos(p.angle) * distance;
      final dy = sin(p.angle) * distance + 260 * t * t;
      final offset = center + Offset(dx, dy);
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(p.spin * t * pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 1.6),
        Paint()..color = p.color.withValues(alpha: opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
