import 'package:connect/config/notification_topics.dart';
import 'package:connect/services/push_notification_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальные настройки push-категорий пользователя. Хранит выбор
/// вкл/выкл на устройстве и синхронизирует его с подписками на топики
/// FCM — сам факт согласия/отказа никогда не покидает устройство и не
/// требует бэкенд-эндпоинта: сервер просто шлёт push в топик, когда
/// происходит событие (см. [NotificationTopics]).
class NotificationPreferencesService {
  NotificationPreferencesService._();
  static final NotificationPreferencesService instance =
      NotificationPreferencesService._();

  static const _prefKeyPrefix = 'notif_topic_';

  Future<bool> isEnabled(String topicId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefKeyPrefix$topicId') ?? true;
  }

  Future<void> setEnabled(String topicId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefKeyPrefix$topicId', enabled);
    await _applyTopic(topicId, enabled);
  }

  /// Приводит подписки FCM в соответствие с сохранёнными настройками —
  /// вызывается один раз после выдачи разрешения на push, так как до
  /// этого подписка на топик ни на что не влияет.
  Future<void> syncAll() async {
    if (kIsWeb || !PushNotificationService.instance.isAvailable) return;

    final prefs = await SharedPreferences.getInstance();
    for (final topic in NotificationTopics.all) {
      final enabled = prefs.getBool('$_prefKeyPrefix${topic.id}') ?? true;
      await _applyTopic(topic.id, enabled);
    }
  }

  Future<void> _applyTopic(String topicId, bool enabled) async {
    if (kIsWeb || !PushNotificationService.instance.isAvailable) return;
    try {
      if (enabled) {
        await FirebaseMessaging.instance.subscribeToTopic(topicId);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topicId);
      }
    } catch (e, st) {
      AppLogger.e(
        'Failed to ${enabled ? 'subscribe to' : 'unsubscribe from'} topic $topicId',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    }
  }
}
