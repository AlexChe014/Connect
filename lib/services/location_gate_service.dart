import 'dart:io';
import 'dart:math' as math;

import 'package:connect/config/app_store_review.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Настройки офисной геозоны.
///
/// Пока координаты не заданы ([officeLatitude]/[officeLongitude] == null),
/// проверка геопозиции для обычных сотрудников пропускается.
/// Для аккаунтов из [AppStoreReviewConfig] проверка всегда успешна.
class LocationGateConfig {
  LocationGateConfig._();

  /// Широта офиса (WGS84). Задайте реальные координаты перед включением.
  static const double? officeLatitude = null;

  /// Долгота офиса (WGS84).
  static const double? officeLongitude = null;

  /// Допустимый радиус вокруг офиса, метры.
  static const double radiusMeters = 1000;

  static bool get isGeofenceConfigured =>
      officeLatitude != null && officeLongitude != null;
}

class LocationGateResult {
  const LocationGateResult._({
    required this.allowed,
    required this.reason,
    this.message,
  });

  final bool allowed;
  final String reason;
  final String? message;

  factory LocationGateResult.allowed({required String reason}) =>
      LocationGateResult._(allowed: true, reason: reason);

  factory LocationGateResult.denied(String message, {required String reason}) =>
      LocationGateResult._(allowed: false, reason: reason, message: message);
}

/// Проверка геопозиции для функций, связанных с присутствием на рабочем месте.
class LocationGateService {
  LocationGateService._();
  static final LocationGateService instance = LocationGateService._();

  Future<LocationGateResult> verifyForCurrentUser() async {
    final user = await AuthService.instance.getStoredUser();
    final email = _extractEmail(user);
    return verifyForEmail(email);
  }

  Future<LocationGateResult> verifyForEmail(String? email) async {
    if (AppStoreReviewConfig.isReviewAccount(email)) {
      AppLogger.d(
        'Location gate skipped for App Store review account: $email',
        name: 'location.gate',
      );
      return LocationGateResult.allowed(reason: 'review_account');
    }

    if (!LocationGateConfig.isGeofenceConfigured) {
      return LocationGateResult.allowed(reason: 'geofence_disabled');
    }

    if (kIsWeb) {
      return LocationGateResult.allowed(reason: 'web_unsupported');
    }

    if (!(Platform.isIOS || Platform.isAndroid)) {
      return LocationGateResult.allowed(reason: 'desktop_skip');
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationGateResult.denied(
          'Включите службы геолокации, чтобы подтвердить присутствие в офисе.',
          reason: 'service_disabled',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationGateResult.denied(
          'Нужен доступ к геопозиции для подтверждения присутствия на территории компании.',
          reason: 'permission_denied',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final distance = _distanceMeters(
        position.latitude,
        position.longitude,
        LocationGateConfig.officeLatitude!,
        LocationGateConfig.officeLongitude!,
      );

      if (distance <= LocationGateConfig.radiusMeters) {
        return LocationGateResult.allowed(reason: 'inside_geofence');
      }

      return LocationGateResult.denied(
        'Вы находитесь вне территории компании. Подойдите ближе к офису и попробуйте снова.',
        reason: 'outside_geofence',
      );
    } catch (e, st) {
      AppLogger.e(
        'Location gate failed',
        name: 'location.gate',
        error: e,
        stackTrace: st,
      );
      return LocationGateResult.denied(
        'Не удалось определить геопозицию. Проверьте настройки и попробуйте снова.',
        reason: 'error',
      );
    }
  }

  String? _extractEmail(Map<String, dynamic>? user) {
    if (user == null) return null;
    for (final key in ['email', 'Email', 'mail', 'login']) {
      final value = user[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double deg) => deg * math.pi / 180.0;
}
