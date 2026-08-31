import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/settings_repository.dart';
import '../utils/app_logger.dart';

/// Кэш и загрузка логотипа компании (`connect.light_logo`).
class BrandingService extends ChangeNotifier {
  BrandingService._();
  static final BrandingService instance = BrandingService._();

  static const _logoUrlKey = 'branding_light_logo_url';

  String? _logoUrl;
  String? get logoUrl => _logoUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_logoUrlKey)?.trim();
    if (cached != null && cached.isNotEmpty) {
      _logoUrl = cached;
    }
    unawaited(refresh());
  }

  /// Тянет `light_logo` с текущего (или переданного) хоста.
  Future<void> refresh({String? host}) async {
    try {
      final url = await SettingsRepository.instance.getConnectLightLogo(
        host: host,
      );
      if (url == null || url.isEmpty) return;
      if (url == _logoUrl) return;
      _logoUrl = url;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_logoUrlKey, url);
    } catch (e, st) {
      AppLogger.d(
        'Branding logo refresh failed',
        name: 'branding',
        error: e,
        stackTrace: st,
      );
    }
  }
}
