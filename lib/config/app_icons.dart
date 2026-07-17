import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SVG из [assets/icons/], подобранные по разделам приложения.
abstract final class AppIcons {
  AppIcons._();

  static const String _base = 'assets/icons';

  // 01 — главное меню / навигация
  static const String dashboard = '$_base/01-1-dashboard.svg';
  static const String bookings = '$_base/01-2-calendar-check.svg';
  static const String news = '$_base/01-4-file-text.svg';
  static const String documents = '$_base/01-7-file-check.svg';
  static const String calendar = '$_base/01-8-calendar-grid.svg';
  static const String user = '$_base/01-9-user.svg';
  static const String mailAt = '$_base/01-6-at-sign.svg';
  static const String chat = '$_base/01-11-message-circle.svg';
  static const String settings = '$_base/01-17-settings.svg';
  static const String mapPin = '$_base/01-18-map-pin.svg';
  static const String users = '$_base/01-19-users.svg';
  static const String settingsFilled = '$_base/01-settings-filled.svg';

  // 03 — избранное / поиск
  static const String search = '$_base/03-search.svg';
  static const String favorite = '$_base/03-favorite.svg';
  static const String starOutline = '$_base/03-star-outline.svg';
  static const String starFilled = '$_base/03-star-filled.svg';

  // 04 — сотрудники
  static const String birthdayCake = '$_base/04-birthday-cake.svg';
  static const String phone = '$_base/04-phone.svg';
  static const String staffMail = '$_base/04-mail.svg';
  static const String staffMessage = '$_base/04-message.svg';
  static const String fieldTime = '$_base/04-field-time.svg';
  static const String home = '$_base/04-home.svg';
  static const String car = '$_base/04-car.svg';

  // 05 — чат
  static const String attachment = '$_base/05-attachment.svg';
  static const String close = '$_base/05-close.svg';
  static const String download = '$_base/05-download.svg';
  static const String smile = '$_base/05-smile.svg';
  static const String thumbtack = '$_base/05-thumbtack.svg';

  // 06 — действия в чате
  static const String copy = '$_base/06-copy.svg';
  static const String reply = '$_base/06-reply.svg';
  static const String share = '$_base/06-share.svg';

  // 07 — календарь
  static const String date = '$_base/07-date.svg';
  static const String locationPin = '$_base/07-location-pin.svg';
  static const String attendees = '$_base/07-attendees.svg';
  static const String calendarList = '$_base/07-list.svg';

  // 08 — профиль
  static const String logout = '$_base/08-logout.svg';
  static const String profileMail = '$_base/08-mail.svg';
  static const String profileAdd = '$_base/08-add.svg';
  static const String profileSettings = '$_base/08-settings.svg';

  // 09 — лента
  static const String eye = '$_base/09-eye.svg';
  static const String like = '$_base/09-like.svg';
  static const String send = '$_base/09-send.svg';
  static const String feedSearch = '$_base/09-search.svg';
  static const String feedList = '$_base/09-list.svg';

  // 10 — бронирование
  static const String bookingMap = '$_base/10-map.svg';
  static const String sliders = '$_base/10-sliders.svg';
  static const String bookingClose = '$_base/10-close.svg';
  static const String bookingAttendees = '$_base/10-attendees.svg';

  // 12 — безопасность
  static const String info = '$_base/12-info.svg';

  // 13 — почта
  static const String mailAdd = '$_base/13-add.svg';
  static const String compose = '$_base/13-compose.svg';
  static const String refresh = '$_base/13-refresh.svg';

  // 14 — коннектор
  static const String cameraOn = '$_base/14-camera-on.svg';
  static const String videoMeeting = '$_base/14-video-meeting.svg';
}

/// Виджет SVG-иконки с окраской через [ColorFilter].
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.asset, {
    super.key,
    this.size,
    this.color,
  });

  final String asset;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolved =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: resolvedSize,
      height: resolvedSize,
      child: SvgPicture.asset(
        asset,
        width: resolvedSize,
        height: resolvedSize,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
      ),
    );
  }
}
