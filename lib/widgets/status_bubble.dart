import 'package:flutter/cupertino.dart';

/// Облачко рабочего статуса с хвостиком-указателем сверху — используется
/// под аватаркой в профиле и в карточке сотрудника, хвостик визуально
/// «привязывает» статус к аватару, стоящему над ним.
class StatusBubble extends StatelessWidget {
  const StatusBubble({
    super.key,
    required this.text,
    this.color = CupertinoColors.activeBlue,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = color.withValues(alpha: 0.12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(size: const Size(14, 6), painter: _BubbleTailPainter(fill)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2 - 6, size.height)
      ..lineTo(size.width / 2 + 6, size.height)
      ..lineTo(size.width / 2, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
