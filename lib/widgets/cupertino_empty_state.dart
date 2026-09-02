import 'package:flutter/cupertino.dart';

/// Простой пустой экран в стиле Cupertino — для разделов вроде «Медиа»,
/// «Файлы», «Ссылки» в деталях чата, где Material-версия [AppEmptyState] не
/// подходит по стилю.
class CupertinoEmptyState extends StatelessWidget {
  const CupertinoEmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
