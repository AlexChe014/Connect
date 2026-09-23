import 'package:flutter/cupertino.dart';

/// Индикатор доставки/прочтения исходящего сообщения:
/// одна галочка — доставлено, две синие — прочитано получателем.
///
/// Используется и в диалоге чата, и в списке чатов — единая реализация,
/// чтобы вид галочек не расходился между экранами.
class ReadReceipt extends StatelessWidget {
  const ReadReceipt({super.key, required this.read, this.size = 12});

  final bool read;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = read
        ? CupertinoColors.activeBlue
        : CupertinoColors.tertiaryLabel.resolveFrom(context);

    if (!read) {
      return Icon(CupertinoIcons.checkmark, size: size, color: color);
    }

    // В Cupertino-наборе иконок нет готовой "двойной галочки" —
    // рисуем её как две перекрывающиеся одинарные (как в WhatsApp/Telegram).
    return SizedBox(
      width: size + size / 3,
      height: size,
      child: Stack(
        children: [
          Icon(CupertinoIcons.checkmark, size: size, color: color),
          Positioned(
            left: size / 3,
            child: Icon(CupertinoIcons.checkmark, size: size, color: color),
          ),
        ],
      ),
    );
  }
}
