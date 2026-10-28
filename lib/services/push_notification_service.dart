import 'dart:async';
import 'dart:io';

import 'package:connect/config/notification_topics.dart';
import 'package:connect/firebase_options.dart';
import 'package:connect/repositories/device_token_repository.dart';
import 'package:connect/services/app_navigation_service.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/chat_call_service.dart';
import 'package:connect/services/chat_preferences_service.dart';
import 'package:connect/services/chat_quick_reply.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/services/home_widget_service.dart';
import 'package:connect/services/mail_unread_service.dart';
import 'package:connect/services/notification_unread_service.dart';
import 'package:connect/services/document_pending_service.dart';
import 'package:connect/services/survey_pending_service.dart';
import 'package:connect/models/chat/chat_call_record.dart';
import 'package:connect/models/chat/chat_call_status.dart';
import 'package:connect/models/chat/chat_sticker.dart';
import 'package:connect/models/incoming_call_payload.dart';
import 'package:connect/services/incoming_call_service.dart';
import 'package:connect/services/push_background_handler.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/chat_mapper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const _androidChannelId = 'connect_high_importance';
  static const _androidChannelName = 'Connect уведомления';
  static const _backendTimeout = Duration(seconds: 5);

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
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
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
      if (Platform.isAndroid) {
        final launch = await _localNotifications
            .getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true && payload != null) {
          _storeNavigationFromMessage(
            RemoteMessage(data: decodeNotificationPayload(payload)),
          );
        }
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
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
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
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_stat_notify',
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          chatNotificationBackgroundResponse,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        importance: Importance.high,
      ),
    );
  }

  Future<void> _onLocalNotificationResponse(
    NotificationResponse response,
  ) async {
    if (ChatQuickReply.isQuickAction(response.actionId)) {
      final chatId = await ChatQuickReply.handle(
        response.actionId,
        response.input,
        decodeNotificationPayload(response.payload),
      );
      if (chatId != null) {
        unawaited(ChatService.instance.applyPushForChat(chatId.toString()));
      }
      return;
    }
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _handlePayloadNavigation(payload);
  }

  static const _defaultDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Сообщение чата — с кнопками «Ответить» и «Прочитано».
  static const _chatDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      actions: ChatQuickReply.androidActions,
    ),
  );

  /// После успешного логина: разрешение → FCM-токен в БД → топики.
  Future<void> registerAfterLogin() async {
    unawaited(HomeWidgetService.instance.refresh(force: true));
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
      // VoIP (PushKit) не зависит от Firebase — всё равно пробуем.
      await IncomingCallService.instance.refreshVoipRegistration(force: true);
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
      } else {
        _currentToken = token;
        await DeviceTokenRepository.instance.registerToken(
          token: token,
          platform: _platformName(),
        );
        AppLogger.d(
          'FCM token registered on backend (${_platformName()})',
          name: 'push',
        );
      }
      await AppNavigationService.processPendingNavigation();
    } catch (e, st) {
      AppLogger.e(
        'Failed to register FCM token',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    } finally {
      // Важно: не привязывать VoIP к успеху FCM — иначе iOS теряет
      // PushKit-токен, если APNs/FCM ещё не готов.
      await IncomingCallService.instance.refreshVoipRegistration(force: true);
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

  /// Выход из аккаунта, пока сессия ещё жива: отвязать FCM- и VoIP-токены
  /// на бэкенде. Ошибки не блокируют выход — локально токены всё равно
  /// гасятся в [disableLocally].
  Future<void> unregisterOnBackend() async {
    // Иначе собеседник останется в комнате с «зависшим» звонком.
    try {
      await ChatCallService.instance.endLiveCallForLogout().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
    await IncomingCallService.instance.unregisterVoipOnBackend();
    if (!_initialized) return;

    String? token = _currentToken;
    if (token == null || token.isEmpty) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    if (token == null || token.isEmpty) return;

    try {
      await DeviceTokenRepository.instance
          .unregisterToken(token: token)
          .timeout(_backendTimeout);
    } catch (e, st) {
      AppLogger.e(
        'Failed to unregister FCM token',
        name: 'push',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Вызывать после очистки сессии: инвалидирует FCM-токен в Firebase и
  /// отключает VoIP, чтобы пуши не приходили, даже если бэкенд не отвязал
  /// токены. После очистки сессии — иначе `onTokenRefresh` успеет
  /// зарегистрировать новый токен на старого пользователя.
  Future<void> disableLocally() async {
    await HomeWidgetService.instance.clear();
    await IncomingCallService.instance.disableLocally();
    if (!_initialized) return;

    _currentToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
      AppLogger.d('FCM token deleted locally', name: 'push');
    } catch (e, st) {
      AppLogger.e(
        'Failed to delete FCM token',
        name: 'push',
        error: e,
        stackTrace: st,
      );
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
    final type = NotificationTopics.canonicalType(message.data['type']);
    if (type == 'mail') {
      MailUnreadService.instance.invalidate();
    }
    // Пуш по записи `user_notifications` — запись уже создана, обновляем
    // счётчик. Чаты и звонки в эту таблицу не попадают.
    if (type.isNotEmpty &&
        type != 'chat_message' &&
        !type.startsWith('chat_call')) {
      unawaited(NotificationUnreadService.instance.refresh());
    }
    if (type == 'new_documents') {
      unawaited(DocumentPendingService.instance.refreshKnownServices());
    }
    if (_isSurveyMessage(message.data)) {
      unawaited(SurveyPendingService.instance.refreshQuietly());
    }
    if (IncomingCallPayload.isChatCall(message.data)) {
      await IncomingCallService.instance.handlePushData(message.data);
      return;
    }

    if (ChatCallSignal.isCallSignal(message.data)) {
      final signal = ChatCallSignal.tryParse(message.data);
      if (signal != null) ChatCallService.instance.applySignal(signal);
      return;
    }

    var isMutedChat = false;
    if (message.data['type'] == 'chat_message') {
      final chatId = message.data['chat_id']?.toString();
      if (chatId != null && chatId.isNotEmpty) {
        // Список чатов (бейдж, превью) и открытую переписку — иначе при
        // открытом чате новое сообщение не появится, пока сокет молчит.
        unawaited(ChatService.instance.applyPushForChat(chatId));

        await ChatPreferencesService.instance.ensureLoaded();
        // Мьют — чисто локальная настройка (см. ChatPreferencesService):
        // сервер уже отправил пуш всем устройствам пользователя, здесь мы
        // только не показываем баннер/звук на этом устройстве.
        isMutedChat = ChatPreferencesService.instance.isMuted(chatId);
      }
    }

    final notification = message.notification;
    final isMail = message.data['type'] == 'mail';
    if (notification == null && !isMail) return;
    if (!Platform.isAndroid) return;
    if (isMutedChat) return;

    // `message_type` нового сообщения чата: у звонка свой пуш, а код стикера
    // показывать пользователю бессмысленно.
    final chatMessageType = message.data['type'] == 'chat_message'
        ? message.data['message_type']?.toString().trim().toUpperCase()
        : null;
    if (chatMessageType == ChatCallRecord.messageType) return;
    final bodyOverride = chatMessageType == ChatStickers.messageType
        ? ChatMapper.stickerSnippet
        : null;

    final payload = encodeNotificationPayload(message.data);
    _localNotifications.show(
      id: message.messageId.hashCode ^ message.data.hashCode,
      title:
          notification?.title ??
          message.data['title']?.toString() ??
          (isMail ? 'Новое письмо' : null),
      body:
          bodyOverride ??
          notification?.body ??
          message.data['body']?.toString() ??
          message.data['subject']?.toString(),
      notificationDetails: chatMessageType != null
          ? _chatDetails
          : _defaultDetails,
      payload: payload,
    );
  }

  /// Android: data-only пуш о сообщении чата, пока приложение в фоне или
  /// убито. Системный баннер (пуш с `notification`) не умеет кнопок, поэтому
  /// такие пуши рисуем сами — с «Ответить» / «Прочитано».
  Future<void> showBackgroundChat(RemoteMessage message) async {
    final data = message.data;
    if (!Platform.isAndroid ||
        message.notification != null ||
        data['type'] != 'chat_message') {
      return;
    }
    final chatId = data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    await ChatPreferencesService.instance.ensureLoaded();
    if (ChatPreferencesService.instance.isMuted(chatId)) return;

    final messageType = data['message_type']?.toString().trim().toUpperCase();
    if (messageType == ChatCallRecord.messageType) return;

    await _initAndroidNotifications();
    await _localNotifications.show(
      id: (message.messageId ?? '$chatId:${data['message_id']}').hashCode,
      title: data['title']?.toString() ?? 'Новое сообщение',
      body: messageType == ChatStickers.messageType
          ? ChatMapper.stickerSnippet
          : data['body']?.toString(),
      notificationDetails: _chatDetails,
      payload: encodeNotificationPayload(data),
    );
  }

  /// Notification payloads are displayed by the OS in the background.
  /// Android data-only mail pushes require an explicit local notification.
  Future<void> showBackgroundMail(RemoteMessage message) async {
    if (!Platform.isAndroid ||
        message.notification != null ||
        message.data['type'] != 'mail') {
      return;
    }
    await _initAndroidNotifications();
    await _localNotifications.show(
      id:
          (message.messageId ??
                  '${message.data['connection_id']}:${message.data['message_id']}')
              .hashCode,
      title: message.data['title']?.toString() ?? 'Новое письмо',
      body:
          message.data['body']?.toString() ??
          message.data['subject']?.toString(),
      notificationDetails: _defaultDetails,
      payload: encodeNotificationPayload(message.data),
    );
  }

  void _handleMessageNavigation(RemoteMessage message) {
    _navigateFromData(message.data);
  }

  void _handlePayloadNavigation(String payload) {
    final data = decodeNotificationPayload(payload);
    if (data.isEmpty) return;
    _navigateFromData(data);
  }

  static bool _isSurveyMessage(Map<String, dynamic> data) =>
      NotificationTopics.isSurveyType(
        data['type']?.toString(),
        data['module']?.toString(),
      );

  void _storeNavigationFromMessage(RemoteMessage message) {
    final data = message.data;
    if (_isSurveyMessage(data)) {
      AppNavigationService.storePendingSurvey(
        AppNavigationService.resolveSurveyToken(data),
      );
      return;
    }
    switch (NotificationTopics.canonicalType(data['type'])) {
      case 'chat_message':
        final chatId = data['chat_id'];
        if (chatId != null && chatId.isNotEmpty) {
          AppNavigationService.storePendingChat(chatId);
        }
      case 'news_created':
        final newsId = AppNavigationService.resolveDataField(data, [
          'news_id',
          'id',
        ]);
        if (newsId != null) {
          AppNavigationService.storePendingNews(newsId);
        }
      case 'new_documents':
        final serviceId = AppNavigationService.resolveDataField(data, [
          'service_id',
        ]);
        if (serviceId != null) {
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
      case 'booking_created':
      case 'meeting_invite':
      case 'meeting_reminder':
        final bookingId = AppNavigationService.resolveBookingId(data);
        if (bookingId != null) {
          AppNavigationService.storePendingBooking(bookingId);
        }
      case 'chat_call':
        // Приложение было полностью убито, и Flutter поднялся из-за тапа
        // по пушу (getInitialMessage) — раньше здесь просто запоминался
        // чат для перехода, из-за чего разблокировка вела в переписку
        // вместо экрана звонка. Ведём туда же, куда и живой _navigateFromData.
        unawaited(IncomingCallService.instance.handlePushData(data));
      default:
        if (data['module']?.toString() == 'calendar') {
          final bookingId = AppNavigationService.resolveBookingId(data);
          if (bookingId != null) {
            AppNavigationService.storePendingBooking(bookingId);
          }
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

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return defaultTargetPlatform.name;
  }
}
