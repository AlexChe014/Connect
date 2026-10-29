import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/branding_service.dart';

/// Пути к PNG в [assets/branding/]. После замены файлов выполните
/// `dart run flutter_launcher_icons` для обновления иконки ярлыка.
abstract final class BrandingAssets {
  BrandingAssets._();

  /// Исходник для `flutter_launcher_icons` — иконка на рабочем столе / в лончере.
  static const String appIconPng = 'assets/branding/app_icon.png';

  /// Запасной логотип, пока сеть не отдала `connect.light_logo` из настроек.
  static const String loginLogoPng = 'assets/branding/login_logo.png';

  /// Тот же логотип с белыми буквами — для тёмной темы. Тот же холст и
  /// поля, что у [loginLogoPng]: при смене темы логотип не прыгает.
  static const String loginLogoDarkPng = 'assets/branding/login_logo_dark.png';
}

/// Главный логотип компании: `GET /settings/get?module=connect` → `light_logo`,
/// с локальным ассетом, если URL ещё нет или картинка не загрузилась.
/// В тёмной теме — всегда локальный [BrandingAssets.loginLogoDarkPng]:
/// у `light_logo` чёрные буквы, а тёмного варианта сервер не отдаёт.
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
    return ListenableBuilder(
      listenable: BrandingService.instance,
      builder: (context, _) {
        final url = BrandingService.instance.logoUrl?.trim();
        final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
        if (dark || url == null || url.isEmpty) {
          return _AssetLogo(height: height, fit: fit);
        }
        return CachedNetworkImage(
          imageUrl: url,
          height: height,
          fit: fit,
          placeholder: (context, _) => _AssetLogo(height: height, fit: fit),
          errorWidget: (context, _, error) =>
              _AssetLogo(height: height, fit: fit),
        );
      },
    );
  }
}

class _AssetLogo extends StatelessWidget {
  const _AssetLogo({required this.height, required this.fit});

  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Image.asset(
      dark ? BrandingAssets.loginLogoDarkPng : BrandingAssets.loginLogoPng,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) =>
          Icon(CupertinoIcons.news, size: height * 0.85, color: scheme.primary),
    );
  }
}
