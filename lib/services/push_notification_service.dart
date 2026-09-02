import 'dart:async';
import 'dart:io';

import 'package:connect/firebase_options.dart';
import 'package:connect/repositories/device_token_repository.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/chat_preferences_service.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/services/incoming_call_service.dart';
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

  /// После успешного логина: разрешение → FCM-токен в БД → топики.
  Future<void> registerAfterLogin() async {
    await requestPermissions();
    await registerCurrentDevice();
  }

  Future<void> registerCurrentDevice() async {
    if (kIsWeb) return;
    if (!_initialized) {
      await init();
    }
    if (!_initialized) {
      AppLogger.d(
        'Skip FCM register: Firebase is not initialized',
        name: 'push',
      );
      return;
    }
    if (!AuthService.instance.isAuthenticated) {
      AppLogger.d('Skip FCM register: user is not authenticated', name: 'push');
      return;
    }

    try {
      final token = await _resolveFcmToken();
      if (token == null || token.isEmpty) {
        AppLogger.d(
          'Skip FCM register: empty FCM token (APNs/Google Play not ready?)',
          name: 'push',
        );
        return;
      }

      _currentToken = token;
      await DeviceTokenRepository.instance.registerToken(
        token: token,
        platform: _platformName(),
      );
      AppLogger.d(
        'FCM token registered on backend (${_platformName()})',
        name: 'push',
      );
      await IncomingCallService.instance.refreshVoipRegistration();
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

  /// iOS отдаёт FCM-токен только после APNs. Без ожидания `getToken()`
  /// часто возвращает null или кидает `apns-token-not-set`.
  Future<String?> _resolveFcmToken() async {
    if (Platform.isIOS) {
      await _waitForApnsToken();
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) return token;
      } catch (e) {
        AppLogger.d(
          'FCM getToken attempt ${attempt + 1} failed: $e',
          name: 'push',
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      if (Platform.isIOS) {
        await _waitForApnsToken();
      }
    }
    return null;
  }

  Future<void> _waitForApnsToken() async {
    for (var i = 0; i < 6; i++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null && apns.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
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

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (IncomingCallPayload.isChatCall(message.data)) {
      await IncomingCallService.instance.handlePushData(message.data);
      return;
    }

    var isMutedChat = false;
    if (message.data['type'] == 'chat_message') {
      final chatId = message.data['chat_id'] as String?;
      if (chatId != null && chatId.isNotEmpty) {
        // Обновляем список чатов (счётчик непрочитанных, превью последнего
        // сообщения), чтобы бейдж на экране чатов появился сразу, а не
        // только после ручного pull-to-refresh или перезапуска приложения.
        unawaited(ChatService.instance.refreshChats());

        await ChatPreferencesService.instance.ensureLoaded();
        // Мьют — чисто локальная настройка (см. ChatPreferencesService):
        // сервер уже отправил пуш всем устройствам пользователя, здесь мы
        // только не показываем баннер/звук на этом устройстве.
        isMutedChat = ChatPreferencesService.instance.isMuted(chatId);
      }
    }

    final notification = message.notification;
    if (notification == null) return;
    if (!Platform.isAndroid) return;
    if (isMutedChat) return;

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
    final data = message.data;
    switch (data['type']) {
      case 'chat_message':
        final chatId = data['chat_id'];
        if (chatId != null && chatId.isNotEmpty) {
          AppNavigationService.storePendingChat(chatId);
        }
      case 'news':
        final newsId = data['news_id'];
        if (newsId != null && newsId.isNotEmpty) {
          AppNavigationService.storePendingNews(newsId);
        }
      case 'document':
        final serviceId = data['service_id'];
        if (serviceId != null && serviceId.isNotEmpty) {
          AppNavigationService.storePendingDocument(serviceId);
        }
      case 'mail':
        final connectionId = data['connection_id'];
        if (connectionId != null && connectionId.isNotEmpty) {
          AppNavigationService.storePendingMail(
            connectionId,
            data['message_id'],
          );
        }
      case 'meeting_invite':
      case 'meeting_reminder':
        final bookingId = data['booking_id'];
        if (bookingId != null && bookingId.isNotEmpty) {
          AppNavigationService.storePendingBooking(bookingId);
        }
      case 'chat_call':
        final chatId = data['chat_id'];
        if (chatId != null && chatId.toString().isNotEmpty) {
          AppNavigationService.storePendingChat(chatId.toString());
        }
    }
  }

  void _navigateFromData(Map<String, dynamic> data) {
    if (IncomingCallPayload.isChatCall(data)) {
      unawaited(IncomingCallService.instance.handlePushData(data));
      return;
    }
    AppNavigationService.openFromData(data);
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
