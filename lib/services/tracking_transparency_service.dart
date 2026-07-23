import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/foundation.dart';

/// Запрос App Tracking Transparency (iOS 14+).
class TrackingTransparencyService {
  TrackingTransparencyService._();
  static final TrackingTransparencyService instance =
      TrackingTransparencyService._();

  bool _requested = false;

  Future<void> requestIfNeeded() async {
    if (_requested) return;
    if (kIsWeb || !Platform.isIOS) return;

    try {
      // Даём UI успеть отрисоваться — Apple рекомендует не показывать
      // диалог ATT в момент холодного старта без контекста.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
      _requested = true;
    } catch (e, st) {
      AppLogger.e(
        'ATT request failed',
        name: 'privacy.att',
        error: e,
        stackTrace: st,
      );
    }
  }
}
