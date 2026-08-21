import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// Иконки из набора Tabler Icons — единая толщина линий, самый большой
/// открытый набор (MIT), технический/линейный стиль.
abstract final class AppIcons {
  AppIcons._();

  // 01 — главное меню / навигация
  static const IconData dashboard = TablerIcons.news;
  static const IconData bookings = TablerIcons.calendar_check;
  static const IconData news = TablerIcons.photo;
  static const IconData documents = TablerIcons.file_text;
  static const IconData calendar = TablerIcons.calendar;
  static const IconData user = TablerIcons.user_circle;
  static const IconData mailAt = TablerIcons.mail;
  static const IconData chat = TablerIcons.message_circle;
  static const IconData settings = TablerIcons.settings;
  static const IconData mapPin = TablerIcons.map_pin;
  static const IconData users = TablerIcons.users;
  static const IconData settingsFilled = TablerIcons.settings_filled;

  // 03 — избранное / поиск
  static const IconData search = TablerIcons.search;
  static const IconData favorite = TablerIcons.heart;
  static const IconData starOutline = TablerIcons.star;
  static const IconData starFilled = TablerIcons.star_filled;

  // 04 — сотрудники
  static const IconData birthdayCake = TablerIcons.cake;
  static const IconData phone = TablerIcons.phone;
  static const IconData staffMail = TablerIcons.mail;
  static const IconData staffMessage = TablerIcons.message;
  static const IconData fieldTime = TablerIcons.clock;
  static const IconData home = TablerIcons.home;
  static const IconData car = TablerIcons.car;

  // 05 — чат
  static const IconData attachment = TablerIcons.paperclip;
  static const IconData close = TablerIcons.x;
  static const IconData download = TablerIcons.download;
  static const IconData smile = TablerIcons.mood_smile;
  static const IconData thumbtack = TablerIcons.pin;

  // 06 — действия в чате
  static const IconData copy = TablerIcons.copy;
  static const IconData reply = TablerIcons.corner_up_left;
  static const IconData share = TablerIcons.share;

  // 07 — календарь
  static const IconData date = TablerIcons.calendar;
  static const IconData locationPin = TablerIcons.map_pin;
  static const IconData attendees = TablerIcons.users;
  static const IconData calendarList = TablerIcons.list;

  // 08 — профиль
  static const IconData logout = TablerIcons.logout;
  static const IconData profileMail = TablerIcons.mail;
  static const IconData profileAdd = TablerIcons.circle_plus;
  static const IconData profileSettings = TablerIcons.settings;

  // 09 — лента
  static const IconData eye = TablerIcons.eye;
  static const IconData like = TablerIcons.thumb_up;
  static const IconData send = TablerIcons.send;
  static const IconData feedSearch = TablerIcons.search;
  static const IconData feedList = TablerIcons.list;

  // 10 — бронирование
  static const IconData bookingMap = TablerIcons.map_pin;
  static const IconData sliders = TablerIcons.adjustments;
  static const IconData bookingClose = TablerIcons.x;
  static const IconData bookingAttendees = TablerIcons.users;

  // 12 — безопасность
  static const IconData info = TablerIcons.info_circle;

  // 13 — почта
  static const IconData mailAdd = TablerIcons.circle_plus;
  static const IconData compose = TablerIcons.edit;
  static const IconData refresh = TablerIcons.refresh;

  // 14 — коннектор
  static const IconData cameraOn = TablerIcons.camera;
  static const IconData videoMeeting = TablerIcons.video;
  static const IconData scheduleMeeting = TablerIcons.calendar_plus;
}

/// Иконка из [AppIcons] с поддержкой размера и цвета из [IconTheme].
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    return Icon(
      icon,
      size: size ?? iconTheme.size,
      color: color ?? iconTheme.color,
    );
  }
}
