import 'package:flutter/material.dart';

import 'app_icons.dart';

/// Пути к PNG в [assets/branding/]. После замены файлов выполните
/// `dart run flutter_launcher_icons` для обновления иконки ярлыка.
abstract final class BrandingAssets {
  BrandingAssets._();

  /// Исходник для `flutter_launcher_icons` — иконка на рабочем столе / в лончере.
  static const String appIconPng = 'assets/branding/app_icon.jpg';

  /// Логотип на экране входа и в панели навигации.
  static const String loginLogoPng = 'assets/branding/login_logo.jpg';
}

/// Логотип из [BrandingAssets.loginLogoPng] с запасным вариантом, если ассета ещё нет.
class BrandingLoginLogo extends StatelessWidget {
  const BrandingLoginLogo({
    super.key,
    this.height = 96,
    this.fit = BoxFit.contain,
  });

  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.asset(
      BrandingAssets.loginLogoPng,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => AppIcon(
        AppIcons.dashboard,
        size: height * 0.85,
        color: scheme.primary,
      ),
    );
  }
}
