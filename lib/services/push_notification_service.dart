import 'dart:io';

import 'package:connect/firebase_options.dart';
import 'package:connect/repositories/device_token_repository.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/push_background_handler.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const _androidChannelId = 'connect_high_importance';
  static const _androidChannelName = 'Connect уведомления';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentToken;

  bool get isAvailable => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (!DefaultFirebaseOptions.isConfigured) {
      AppLogger.d(
        'Push notifications disabled: run `flutterfire configure` and add google-services.json',
        name: 'push',
      );
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      if (Platform.isAndroid) {
        await _initAndroidNotifications();
        final androidPlugin =
            _localNotifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      await requestPermissions();

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageNavigation);
      messaging.onTokenRefresh.listen(_onTokenRefresh);

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _storeNavigationFromMessage(initialMessage);
      }

      _initialized = true;

      if (AuthService.instance.isAuthenticated) {
        await registerCurrentDevice();
      }
    } catch (e, st) {
      AppLogger.e(
        'Push notifications init failed',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Программный запрос разрешения на push-уведомления (iOS / Android 13+).
  Future<NotificationSettings?> requestPermissions() async {
    if (kIsWeb) return null;
    if (!DefaultFirebaseOptions.isConfigured && !_initialized) return null;

    try {
      if (Platform.isAndroid) {
        final androidPlugin =
            _localNotifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      }

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      AppLogger.d(
        'Notification permission: ${settings.authorizationStatus}',
        name: 'push',
      );
      return settings;
    } catch (e, st) {
      AppLogger.e(
        'Notification permission request failed',
        name: 'push',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _initAndroidNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _handlePayloadNavigation(payload);
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        importance: Importance.high,
      ),
    );
  }

  Future<void> registerCurrentDevice() async {
    if (!_initialized) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      _currentToken = token;
      await DeviceTokenRepository.instance.registerToken(
        token: token,
        platform: _platformName(),
      );
      await AppNavigationService.processPendingNavigation();
    } catch (e, st) {
      AppLogger.e(
        'Failed to register FCM token',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> unregisterCurrentDevice() async {
    if (!_initialized) return;

    final token = _currentToken ?? await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    try {
      await DeviceTokenRepository.instance.unregisterToken(token: token);
    } catch (e, st) {
      AppLogger.e(
        'Failed to unregister FCM token',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    } finally {
      _currentToken = null;
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    if (!AuthService.instance.isAuthenticated) return;
    _currentToken = token;
    try {
      await DeviceTokenRepository.instance.registerToken(
        token: token,
        platform: _platformName(),
      );
    } catch (e, st) {
      AppLogger.e(
        'Failed to refresh FCM token on backend',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    if (!Platform.isAndroid) return;

    final payload = _encodePayload(message.data);
    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  void _handleMessageNavigation(RemoteMessage message) {
    _navigateFromData(message.data);
  }

  void _handlePayloadNavigation(String payload) {
    final data = _decodePayload(payload);
    if (data.isEmpty) return;
    _navigateFromData(data);
  }

  void _storeNavigationFromMessage(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'chat_message') {
      final chatId = message.data['chat_id'];
      if (chatId != null && chatId.isNotEmpty) {
        AppNavigationService.storePendingChat(chatId);
      }
      return;
    }
    if (type == 'news') {
      final newsId = message.data['news_id'];
      if (newsId != null && newsId.isNotEmpty) {
        AppNavigationService.storePendingNews(newsId);
      }
    }
  }

  void _navigateFromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat_message') {
      final chatId = data['chat_id']?.toString();
      if (chatId != null && chatId.isNotEmpty) {
        AppNavigationService.openChatById(chatId);
      }
      return;
    }
    if (type == 'news') {
      final newsId = data['news_id']?.toString();
      if (newsId != null && newsId.isNotEmpty) {
        AppNavigationService.openNewsById(newsId);
      }
    }
  }

  String _encodePayload(Map<String, dynamic> data) {
    return data.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
        .join('&');
  }

  Map<String, dynamic> _decodePayload(String payload) {
    final result = <String, dynamic>{};
    for (final part in payload.split('&')) {
      if (part.isEmpty) continue;
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final key = part.substring(0, idx);
      final value = Uri.decodeComponent(part.substring(idx + 1));
      result[key] = value;
    }
    return result;
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return defaultTargetPlatform.name;
  }
}
