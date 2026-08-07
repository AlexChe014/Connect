import 'package:flutter/material.dart';

// Не импортируем package:phosphor_flutter/phosphor_flutter.dart — его классы
// (`PhosphorIconData extends IconData`) не компилируются на новых версиях
// Dart, где `IconData` стал `final class` и больше не наследуется. Пакет
// нужен здесь только как источник самого файла шрифта (объявлен в его
// pubspec.yaml и подхватывается Flutter автоматически), а `IconData`
// собираем сами напрямую по кодпоинтам.
const String _kRegular = 'PhosphorRegular';
const String _kFill = 'PhosphorFill';
const String _kPhosphorPackage = 'phosphor_flutter';

IconData _regular(int codePoint) => IconData(
  codePoint,
  fontFamily: _kRegular,
  fontPackage: _kPhosphorPackage,
  matchTextDirection: true,
);

IconData _fill(int codePoint) => IconData(
  codePoint,
  fontFamily: _kFill,
  fontPackage: _kPhosphorPackage,
  matchTextDirection: true,
);

/// Семантические иконки приложения на базе набора Phosphor
/// (стиль Regular — единая толщина линий, современный SaaS-вид).
abstract final class AppIcons {
  AppIcons._();

  // 01 — главное меню / навигация
  static final IconData dashboard = _regular(0xe344); // newspaper
  static final IconData bookings = _regular(0xe712); // calendarCheck
  static final IconData news = _regular(0xe2ca); // image
  static final IconData documents = _regular(0xe23a); // fileText
  static final IconData calendar = _regular(0xe10a); // calendarBlank
  static final IconData user = _regular(0xe4c4); // userCircle
  static final IconData mailAt = _regular(0xe218); // envelopeSimple
  static final IconData chat = _regular(0xe168); // chatCircle
  static final IconData settings = _regular(0xe270); // gear
  static final IconData mapPin = _regular(0xe316); // mapPin
  static final IconData users = _regular(0xe68e); // usersThree
  static final IconData settingsFilled = _fill(0xe270); // gear

  // 03 — избранное / поиск
  static final IconData search = _regular(0xe30c); // magnifyingGlass
  static final IconData favorite = _regular(0xe2a8); // heart
  static final IconData starOutline = _regular(0xe46a); // star
  static final IconData starFilled = _fill(0xe46a); // star

  // 04 — сотрудники
  static final IconData birthdayCake = _regular(0xe780); // cake
  static final IconData phone = _regular(0xe3b8); // phone
  static final IconData staffMail = _regular(0xe218); // envelopeSimple
  static final IconData staffMessage = _regular(0xe16e); // chatCircleText
  static final IconData fieldTime = _regular(0xed2c); // clockCountdown
  static final IconData home = _regular(0xe2c6); // houseSimple
  static final IconData car = _regular(0xe114); // carSimple

  // 05 — чат
  static final IconData attachment = _regular(0xe39a); // paperclip
  static final IconData close = _regular(0xe4f6); // x
  static final IconData download = _regular(0xe20c); // downloadSimple
  static final IconData smile = _regular(0xe436); // smiley
  static final IconData thumbtack = _regular(0xe3e2); // pushPin

  // 06 — действия в чате
  static final IconData copy = _regular(0xe1ca); // copy
  static final IconData reply = _regular(0xe024); // arrowBendUpLeft
  static final IconData share = _regular(0xe408); // shareNetwork

  // 07 — календарь
  static final IconData date = _regular(0xe7b4); // calendarDots
  static final IconData locationPin = _regular(0xe316); // mapPin
  static final IconData attendees = _regular(0xe68e); // usersThree
  static final IconData calendarList = _regular(0xe2f2); // listBullets

  // 08 — профиль
  static final IconData logout = _regular(0xe42a); // signOut
  static final IconData profileMail = _regular(0xe218); // envelopeSimple
  static final IconData profileAdd = _regular(0xe3d6); // plusCircle
  static final IconData profileSettings = _regular(0xe272); // gearSix

  // 09 — лента
  static final IconData eye = _regular(0xe220); // eye
  static final IconData like = _regular(0xe48e); // thumbsUp
  static final IconData send = _regular(0xe398); // paperPlaneTilt
  static final IconData feedSearch = _regular(0xe30c); // magnifyingGlass
  static final IconData feedList = _regular(0xe2f2); // listBullets

  // 10 — бронирование
  static final IconData bookingMap = _regular(0xe31a); // mapTrifold
  static final IconData sliders = _regular(0xe434); // slidersHorizontal
  static final IconData bookingClose = _regular(0xe4f8); // xCircle
  static final IconData bookingAttendees = _regular(0xe68c); // usersFour

  // 12 — безопасность
  static final IconData info = _regular(0xe2ce); // info

  // 13 — почта
  static final IconData mailAdd = _regular(0xe3d6); // plusCircle
  static final IconData compose = _regular(0xebc6); // pencilSimpleLine
  static final IconData refresh = _regular(0xe094); // arrowsClockwise

  // 14 — коннектор
  static final IconData cameraOn = _regular(0xe10e); // camera
  static final IconData videoMeeting = _regular(0xe4da); // videoCamera
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
