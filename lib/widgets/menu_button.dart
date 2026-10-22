import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/notification_unread_service.dart';
import '../services/survey_pending_service.dart';

/// Кнопка-бургер для `leading:` навбара корневых экранов нижнего меню —
/// открывает боковой `Drawer`, объявленный в `MainNavigationScreen`.
/// Красная точка — в меню есть непройденные опросы или новые уведомления.
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => Scaffold.of(context).openDrawer(),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          SurveyPendingService.instance,
          NotificationUnreadService.instance,
        ]),
        builder: (context, child) => Badge(
          isLabelVisible:
              SurveyPendingService.instance.pendingCount > 0 ||
              NotificationUnreadService.instance.unreadCount > 0,
          smallSize: 8,
          backgroundColor: CupertinoColors.systemRed,
          child: child,
        ),
        child: Icon(
          CupertinoIcons.line_horizontal_3,
          size: 26,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    );
  }
}
