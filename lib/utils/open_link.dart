import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _inAppBrowserChannel = MethodChannel('connect/in_app_browser');

/// Открывает ссылку как Telegram/«Почта»: веб-страницы — во встроенном
/// системном браузере поверх приложения (на iOS — Safari-шторка с зазором
/// сверху, см. AppDelegate.presentInAppBrowser; на Android — Custom Tabs),
/// всё остальное (tel:, mailto:, ссылки на App Store и т.п.) — в
/// соответствующем внешнем приложении.
Future<bool> openLink(Uri uri) async {
  final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
  if (isWeb) {
    if (Platform.isIOS) {
      try {
        final opened = await _inAppBrowserChannel.invokeMethod<bool>(
          'open',
          uri.toString(),
        );
        if (opened ?? false) return true;
      } catch (_) {
        // Фоллбэк на url_launcher ниже.
      }
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
        return true;
      }
    } catch (_) {
      // Фоллбэк на внешний браузер ниже.
    }
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
