import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../models/staff_user.dart';
import 'chat_avatar.dart';

/// Аватар сотрудника: зелёная точка, когда он в сети (серой для «не в
/// сети» нет — в длинном списке она только шумит), и тортик в день
/// рождения. Значки сидят на окружности, а не в углу квадрата, поэтому
/// одинаково смотрятся на любом размере.
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({super.key, required this.user, this.radius = 22});

  final StaffUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ring = AppColors.screenBackground.resolveFrom(context);
    final dot = (radius * 0.6).clamp(12.0, 18.0);
    final cake = dot * 1.5;
    // Точка на окружности под 45°: от края квадрата r·(1 − 1/√2).
    final edge = radius * 0.2929;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        MemberAvatar(
          displayName: user.fullName,
          avatarUrl: user.avatarUrl,
          radius: radius,
        ),
        if (user.isOnline)
          Positioned(
            right: edge - dot / 2,
            bottom: edge - dot / 2,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGreen.resolveFrom(context),
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: dot / 6),
              ),
            ),
          ),
        if (user.isBirthdayToday)
          Positioned(
            left: edge - cake / 2,
            bottom: edge - cake / 2,
            child: Container(
              width: cake,
              height: cake,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: Text('🎂', style: TextStyle(fontSize: cake * 0.62)),
            ),
          ),
      ],
    );
  }
}

/// Строка сотрудника в списках «Сотрудники» и «Избранное»: аватар,
/// ФИО и должность (или отдел), справа — необязательная кнопка.
class EmployeeRow extends StatelessWidget {
  const EmployeeRow({
    super.key,
    required this.user,
    required this.onTap,
    this.trailing,
  });

  /// Отступ разделителя: поле 16 + аватар 44 + зазор 12.
  static const double separatorIndent = 72;

  final StaffUser user;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final position = (user.position ?? '').trim();
    final subtitle = position.isNotEmpty
        ? position
        : (user.department ?? '').trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            EmployeeAvatar(user: user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Круглая кнопка справа в строке списка (написать, убрать из избранного).
class EmployeeRowButton extends StatelessWidget {
  const EmployeeRowButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 17,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    );
  }
}
