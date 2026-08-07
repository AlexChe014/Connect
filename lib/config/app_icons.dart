import 'package:flutter/material.dart';

import 'connect_icons.dart';

/// Иконки из шрифта [ConnectIcons], сгруппированные по разделам приложения.
abstract final class AppIcons {
  AppIcons._();

  // 01 — главное меню / навигация
  static const IconData dashboard = ConnectIcons.icon011Dashboard;
  static const IconData bookings = ConnectIcons.icon012CalendarCheck;
  static const IconData news = ConnectIcons.icon014FileText;
  static const IconData documents = ConnectIcons.icon017FileCheck;
  static const IconData calendar = ConnectIcons.icon018CalendarGrid;
  static const IconData user = ConnectIcons.icon019User;
  static const IconData mailAt = ConnectIcons.icon016AtSign;
  static const IconData chat = ConnectIcons.icon0111MessageCircle;
  static const IconData settings = ConnectIcons.icon0117Settings;
  static const IconData mapPin = ConnectIcons.icon0118MapPin;
  static const IconData users = ConnectIcons.icon0119Users;
  static const IconData settingsFilled = ConnectIcons.icon01SettingsFilled;

  // 03 — избранное / поиск
  static const IconData search = ConnectIcons.icon03Search;
  static const IconData favorite = ConnectIcons.icon03Favorite;
  static const IconData starOutline = ConnectIcons.icon03StarOutline;
  static const IconData starFilled = ConnectIcons.icon03StarFilled;

  // 04 — сотрудники
  static const IconData birthdayCake = ConnectIcons.icon04BirthdayCake;
  static const IconData phone = ConnectIcons.icon04Phone;
  static const IconData staffMail = ConnectIcons.icon04Mail;
  static const IconData staffMessage = ConnectIcons.icon04Message;
  static const IconData fieldTime = ConnectIcons.icon04FieldTime;
  static const IconData home = ConnectIcons.icon04Home;
  static const IconData car = ConnectIcons.icon04Car;

  // 05 — чат
  static const IconData attachment = ConnectIcons.icon05Attachment;
  static const IconData close = ConnectIcons.icon05Close;
  static const IconData download = ConnectIcons.icon05Download;
  static const IconData smile = ConnectIcons.icon05Smile;
  static const IconData thumbtack = ConnectIcons.icon05Thumbtack;

  // 06 — действия в чате
  static const IconData copy = ConnectIcons.icon06Copy;
  static const IconData reply = ConnectIcons.icon06Reply;
  static const IconData share = ConnectIcons.icon06Share;

  // 07 — календарь
  static const IconData date = ConnectIcons.icon07Date;
  static const IconData locationPin = ConnectIcons.icon07LocationPin;
  static const IconData attendees = ConnectIcons.icon07Attendees;
  static const IconData calendarList = ConnectIcons.icon07List;

  // 08 — профиль
  static const IconData logout = ConnectIcons.icon08Logout;
  static const IconData profileMail = ConnectIcons.icon08Mail;
  static const IconData profileAdd = ConnectIcons.icon08Add;
  static const IconData profileSettings = ConnectIcons.icon08Settings;

  // 09 — лента
  static const IconData eye = ConnectIcons.icon09Eye;
  static const IconData like = ConnectIcons.icon09Like;
  static const IconData send = ConnectIcons.icon09Send;
  static const IconData feedSearch = ConnectIcons.icon09Search;
  static const IconData feedList = ConnectIcons.icon09List;

  // 10 — бронирование
  static const IconData bookingMap = ConnectIcons.icon10Map;
  static const IconData sliders = ConnectIcons.icon10Sliders;
  static const IconData bookingClose = ConnectIcons.icon10Close;
  static const IconData bookingAttendees = ConnectIcons.icon10Attendees;

  // 12 — безопасность
  static const IconData info = ConnectIcons.icon12Info;

  // 13 — почта
  static const IconData mailAdd = ConnectIcons.icon13Add;
  static const IconData compose = ConnectIcons.icon13Compose;
  static const IconData refresh = ConnectIcons.icon13Refresh;

  // 14 — коннектор
  static const IconData cameraOn = ConnectIcons.icon14CameraOn;
  static const IconData videoMeeting = ConnectIcons.icon14VideoMeeting;
}

/// Иконка из [AppIcons] с поддержкой размера и цвета из [IconTheme].
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
  });

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
