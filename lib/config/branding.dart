import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/branding_service.dart';
import 'app_icons.dart';

/// Пути к PNG в [assets/branding/]. После замены файлов выполните
/// `dart run flutter_launcher_icons` для обновления иконки ярлыка.
abstract final class BrandingAssets {
  BrandingAssets._();

  /// Исходник для `flutter_launcher_icons` — иконка на рабочем столе / в лончере.
  static const String appIconPng = 'assets/branding/app_icon.png';

  /// Запасной логотип, пока сеть не отдала `connect.light_logo`.
  static const String loginLogoPng = 'assets/branding/login_logo.jpg';
}

/// Логотип компании: `GET /settings/get?module=connect&key=light_logo`,
/// с локальным ассетом, если URL ещё нет или картинка не загрузилась.
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
        if (url == null || url.isEmpty) {
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
