import 'dart:async';
import 'dart:convert';

import 'package:connect/config/home_tabs.dart';
import 'package:connect/config/notification_topics.dart';
import 'package:connect/models/documents/document_service.dart';
import 'package:connect/models/mail/mail_connection.dart';
import 'package:connect/models/surveys/survey_invitation.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/repositories/documents_repository.dart';
import 'package:connect/repositories/mail_repository.dart';
import 'package:connect/repositories/news_repository.dart';
import 'package:connect/screens/bonus_history_screen.dart';
import 'package:connect/screens/bonus_program_screen.dart';
import 'package:connect/screens/bonus_roulette_screen.dart';
import 'package:connect/screens/bonus_shop_screen.dart';
import 'package:connect/screens/booking_detail_sheet.dart';
import 'package:connect/screens/calendar_screen.dart';
import 'package:connect/screens/chat_conversation_screen.dart';
import 'package:connect/screens/documents_list_screen.dart';
import 'package:connect/screens/documents_signing_screen.dart';
import 'package:connect/screens/mail_inbox_screen.dart';
import 'package:connect/screens/mail_message_screen.dart';
import 'package:connect/screens/mail_screen.dart';
import 'package:connect/screens/news_detail_screen.dart';
import 'package:connect/screens/survey_form_screen.dart';
import 'package:connect/screens/surveys_screen.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/survey_pending_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class _PendingMail {
  const _PendingMail(this.connectionId, this.messageId);
  final String connectionId;
  final String? messageId;
}

class AppNavigationService {
  AppNavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Сбрасывает стек и открывает форму входа. Безопасно вызывать из
  /// HTTP-колбэков: навигация откладывается на следующий кадр.
  static void goToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null || !nav.mounted) return;
      if (ModalRoute.of(nav.context)?.settings.name == '/login') return;
      nav.pushNamedAndRemoveUntil('/login', (route) => false);
    });
  }

  /// Регистрируется в `MaterialApp.navigatorObservers`. Экраны, которые
  /// остаются смонтированными "под" запушенными поверх них route (например,
  /// вкладки нижней навигации, не пересоздающиеся при `Navigator.push`),
  /// используют его через `RouteAware`/`didPopNext`, чтобы перечитать данные
  /// при возврате, а не только в `initState`.
  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

  static String? _pendingChatId;
  static String? _pendingNewsId;
  static String? _pendingDocumentServiceId;
  static _PendingMail? _pendingMail;
  static String? _pendingBookingId;

  /// Тап по пушу об опросе до готовности навигатора: `''` — открыть
  /// список опросов, иначе токен получателя.
  static String? _pendingSurveyToken;

  /// Чат, который сейчас открывается через [openChatById]. Дублирующая
  /// доставка push (обычное дело для FCM — например, эхо системного
  /// сообщения о завершённом звонке тому же устройству) иначе запускает
  /// второй параллельный вызов, который пушит ещё один экземпляр
  /// `ChatConversationScreen` поверх уже открытого: стек ветвится, и кнопка
  /// «на главный экран» (`HomeShortcutButton`) залипает видимой, потому что
  /// её счётчик глубины стека считает и этот лишний route.
  static String? _openingChatId;

  static void storePendingChat(String chatId) => _pendingChatId = chatId;

  static void storePendingNews(String newsId) => _pendingNewsId = newsId;

  static void storePendingDocument(String serviceId) =>
      _pendingDocumentServiceId = serviceId;

  static void storePendingMail(String connectionId, String? messageId) =>
      _pendingMail = _PendingMail(connectionId, messageId);

  static void storePendingBooking(String bookingId) =>
      _pendingBookingId = bookingId;

  static void storePendingSurvey(String? token) =>
      _pendingSurveyToken = token ?? '';

  static String? takePendingChatId() {
    final id = _pendingChatId;
    _pendingChatId = null;
    return id;
  }

  static String? takePendingNewsId() {
    final id = _pendingNewsId;
    _pendingNewsId = null;
    return id;
  }

  static Future<void> openChatById(String chatId) async {
    if (!AuthService.instance.isAuthenticated) {
      storePendingChat(chatId);
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      storePendingChat(chatId);
      return;
    }

    if (_openingChatId == chatId) return;
    _openingChatId = chatId;

    try {
      final userId = await _currentUserId();
      if (userId == null) {
        storePendingChat(chatId);
        return;
      }

      // Без await: `/home` — корневой route, его Future завершится, только
      // когда его закроют, и код ниже не выполнился бы.
      unawaited(
        navigator.pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
          arguments: {'initialIndex': HomeTabs.chats},
        ),
      );

      if (!navigator.mounted) return;
      final chat = await ChatRepository.instance.getChat(
        int.parse(chatId),
        currentUserId: userId,
      );
      if (!navigator.mounted) return;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (context) => ChatConversationScreen(chat: chat),
        ),
      );
    } catch (e, st) {
      AppLogger.e(
        'Failed to open chat from push: $chatId',
        name: 'push.navigation',
        error: e,
        stackTrace: st,
      );
    } finally {
      _openingChatId = null;
    }
  }

  static Future<void> openNewsById(String newsId) async {
    if (!AuthService.instance.isAuthenticated) {
      storePendingNews(newsId);
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      storePendingNews(newsId);
      return;
    }

    if (!navigator.mounted) return;
    // Без await: Future корневого `/home` завершится, только когда его
    // закроют, — вызывающий код (openFromData) завис бы.
    unawaited(
      navigator.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: {'initialIndex': HomeTabs.today, 'openNewsId': newsId},
      ),
    );
  }

  /// Открывает раздел «Согласование» и, если сервис с [serviceId] найден
  /// среди активных, сразу переходит в список его документов.
  static Future<void> openDocumentService(String serviceId) async {
    if (!AuthService.instance.isAuthenticated) {
      storePendingDocument(serviceId);
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      storePendingDocument(serviceId);
      return;
    }

    // Не await: `push*` завершается только когда route закроют, а `/home` —
    // корневой, так что дальше код бы не пошёл и раздел не открылся.
    unawaited(
      navigator.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: {'initialIndex': HomeTabs.more},
      ),
    );
    unawaited(
      navigator.push<void>(
        CupertinoPageRoute<void>(
          builder: (context) => const DocumentsSigningScreen(),
        ),
      ),
    );

    final id = int.tryParse(serviceId);
    if (id == null) return;
    try {
      final services = await DocumentsRepository.instance.getActiveServices();
      DocumentService? service;
      for (final s in services) {
        if (s.id == id) {
          service = s;
          break;
        }
      }
      if (service == null || !navigator.mounted) return;
      unawaited(
        navigator.push<void>(
          CupertinoPageRoute<void>(
            builder: (context) => DocumentsListScreen(service: service!),
          ),
        ),
      );
    } catch (e, st) {
      AppLogger.e(
        'Failed to open document service from push: $serviceId',
        name: 'push.navigation',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Открывает раздел «Почта» и, если ящик с [connectionId] найден,
  /// сразу переходит в него (и в письмо, если передан [messageId]).
  static Future<void> openMailConnection(
    String connectionId, {
    String? messageId,
  }) async {
    if (!AuthService.instance.isAuthenticated) {
      storePendingMail(connectionId, messageId);
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      storePendingMail(connectionId, messageId);
      return;
    }

    // Без await: `/home` — корневой route, его Future завершится, только
    // когда его закроют, и код ниже не выполнился бы.
    unawaited(
      navigator.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: {'initialIndex': HomeTabs.mail},
      ),
    );
    if (!navigator.mounted) return;

    // Экраны открываем без await: Future от push завершается, когда экран
    // ЗАКРЫВАЮТ. Раньше тут открывался список ящиков и код ждал его
    // закрытия — до входящих и самого письма дело не доходило.
    // Сама вкладка «Почта» уже показывает основной ящик — дальше открываем
    // только то, чего в ней нет.
    final id = int.tryParse(connectionId);
    final userId = await _currentUserId();
    if (id == null || userId == null) return;
    try {
      final connections = await MailRepository.instance.getConnectionsByUser(
        userId,
      );
      if (!navigator.mounted) return;
      final connection = connections.where((c) => c.id == id).firstOrNull;
      if (connection == null) return;
      final tabConnection = connections.firstWhere(
        (c) => c.isDefault,
        orElse: () => connections.first,
      );
      if (connection.id != tabConnection.id) {
        unawaited(
          navigator.push<void>(
            CupertinoPageRoute<void>(
              builder: (context) => MailInboxScreen(
                connection: connection,
                connections: connections,
              ),
            ),
          ),
        );
      }

      final msgId = int.tryParse(messageId ?? '');
      if (msgId == null) return;
      unawaited(
        navigator.push<void>(
          CupertinoPageRoute<void>(
            builder: (context) =>
                MailMessageScreen(connection: connection, messageId: msgId),
          ),
        ),
      );
    } catch (e, st) {
      AppLogger.e(
        'Failed to open mail connection from push: $connectionId',
        name: 'push.navigation',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Открывает Календарь и показывает карточку брони [bookingId] —
  /// используется и для приглашения, и для напоминания о встрече.
  static Future<void> openBookingById(String bookingId) async {
    if (!AuthService.instance.isAuthenticated) {
      storePendingBooking(bookingId);
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      storePendingBooking(bookingId);
      return;
    }

    final id = int.tryParse(bookingId);
    if (id == null) return;

    // Без await: `/home` — корневой route, его Future завершится, только
    // когда его закроют, и код ниже не выполнился бы.
    unawaited(
      navigator.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: {'initialIndex': HomeTabs.more},
      ),
    );
    // Календаря больше нет в нижнем меню — открываем его поверх «Ещё».
    unawaited(
      navigator.push<void>(
        CupertinoPageRoute<void>(builder: (_) => const CalendarScreen()),
      ),
    );

    if (!navigator.mounted) return;
    try {
      await BookingDetailSheet.show(navigator.context, bookingId: id);
    } catch (e, st) {
      AppLogger.e(
        'Failed to open booking from push: $bookingId',
        name: 'push.navigation',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Токен получателя из уведомления об опросе: поле `token` или ссылка
  /// вида `{frontend_url}/survey/{token}`.
  static String? resolveSurveyToken(Map<String, dynamic> data) {
    final token = resolveDataField(data, ['token', 'survey_token']);
    if (token != null) return token;
    final link = resolveDataField(data, ['link', 'url']);
    if (link == null) return null;
    final segments = Uri.tryParse(link)?.pathSegments ?? const [];
    final i = segments.indexOf('survey');
    if (i < 0 || i + 1 >= segments.length) return null;
    final fromLink = segments[i + 1].trim();
    return fromLink.isEmpty ? null : fromLink;
  }

  /// Открывает «Опросы» и, если известен [token], сразу форму опроса.
  static Future<void> openSurvey(String? token) async {
    final navigator = navigatorKey.currentState;
    if (!AuthService.instance.isAuthenticated || navigator == null) {
      storePendingSurvey(token);
      return;
    }

    // Не await: `/home` — корневой route, его future не завершится.
    unawaited(
      navigator.pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: {'initialIndex': HomeTabs.more},
      ),
    );
    unawaited(
      navigator.push<void>(
        CupertinoPageRoute<void>(builder: (context) => const SurveysScreen()),
      ),
    );
    if (token == null || token.isEmpty) return;

    // Id получателя нужен для отметки portal-open — берём из списка.
    final pending = SurveyPendingService.instance;
    await pending.refreshQuietly();
    if (!navigator.mounted) return;
    SurveyInvitation? invitation;
    for (final i in pending.invitations) {
      if (i.token == token) {
        invitation = i;
        break;
      }
    }
    if (invitation != null) {
      unawaited(SurveysScreen.openInvitation(navigator.context, invitation));
    } else {
      unawaited(
        navigator.push<void>(
          CupertinoPageRoute<void>(
            builder: (context) => SurveyFormScreen(token: token),
          ),
        ),
      );
    }
  }

  /// Общая точка входа для навигации по `type`/`data` — используется и для
  /// тапа по push (см. `PushNotificationService`), и для тапа по элементу
  /// ленты уведомлений (`NotificationsScreen`), чтобы не дублировать логику.
  ///
  /// `type` здесь — значение как оно есть в БД бэкенда (`news_created`,
  /// `new_documents`, ...), без переименования на стороне бэкенда.
  static Future<void> openFromData(Map<String, dynamic> data) async {
    if (NotificationTopics.isSurveyType(
      data['type']?.toString(),
      data['module']?.toString(),
    )) {
      await openSurvey(resolveSurveyToken(data));
      return;
    }
    switch (NotificationTopics.canonicalType(data['type']?.toString())) {
      case 'chat_message':
        final chatId = data['chat_id']?.toString();
        if (chatId != null && chatId.isNotEmpty) {
          await openChatById(chatId);
        }
      case 'news_created':
        final newsId = resolveDataField(data, ['news_id', 'id']);
        if (newsId != null) {
          await openNewsById(newsId);
        }
      case 'new_documents':
        final serviceId = resolveDataField(data, ['service_id']);
        if (serviceId != null) {
          await openDocumentService(serviceId);
        }
      case 'mail':
        final connectionId = data['connection_id']?.toString();
        if (connectionId != null && connectionId.isNotEmpty) {
          await openMailConnection(
            connectionId,
            messageId: data['message_id']?.toString(),
          );
        }
      case 'booking_created':
      case 'meeting_invite':
      case 'meeting_reminder':
        final bookingId = resolveBookingId(data);
        if (bookingId != null) {
          await openBookingById(bookingId);
        }
      default:
        if (data['module']?.toString() == 'calendar') {
          final bookingId = resolveBookingId(data);
          if (bookingId != null) {
            await openBookingById(bookingId);
          }
        } else if (NotificationTopics.isBonusType(data['type']?.toString()) ||
            data['type'] == 'document_changes') {
          // Без отложенного перехода: такие пуши редки и не срочны.
          final navigator = navigatorKey.currentState;
          if (!AuthService.instance.isAuthenticated || navigator == null) {
            return;
          }
          unawaited(
            navigator.pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
              arguments: {'initialIndex': HomeTabs.today},
            ),
          );
          await openNotificationInPlace(data);
        }
    }
  }

  /// Тап по уведомлению в ленте (`NotificationsScreen`): в отличие от
  /// [openFromData] не сбрасывает стек до `/home`, а открывает объект
  /// поверх ленты — «Назад» возвращает к уведомлениям. `false` — для типа
  /// нет экрана в приложении.
  static Future<bool> openNotificationInPlace(Map<String, dynamic> data) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;
    final type = NotificationTopics.canonicalType(data['type']?.toString());
    final module = data['module']?.toString();

    void push(Widget screen) => unawaited(
      navigator.push<void>(CupertinoPageRoute<void>(builder: (_) => screen)),
    );

    try {
      if (NotificationTopics.isSurveyType(type, module)) {
        await _openSurveyInPlace(navigator, resolveSurveyToken(data));
        return true;
      }
      if (NotificationTopics.isBookingType(type) || module == 'calendar') {
        final id = int.tryParse(resolveBookingId(data) ?? '');
        if (id == null) return false;
        unawaited(BookingDetailSheet.show(navigator.context, bookingId: id));
        return true;
      }
      if (NotificationTopics.isBonusType(type)) {
        push(switch (type) {
          'bonus_program_point_transfer_received' ||
          'bonus_program_point_transfer_hr' => const BonusHistoryScreen(),
          'bonus_program_shop_request_moderated' => const BonusShopScreen(),
          'bonus_program_roulette_prize_request_moderated' =>
            const BonusRouletteScreen(),
          // Заявки для ответственных модерируются только на портале.
          _ => const BonusProgramScreen(),
        });
        return true;
      }
      switch (type) {
        case 'news_created':
          final newsId = resolveDataField(data, ['news_id', 'id']);
          if (newsId == null) return false;
          final news = await NewsRepository.instance.getById(newsId);
          if (!navigator.mounted) return true;
          push(NewsDetailScreen(news: news));
          return true;
        case 'new_documents':
          final service = await _findDocumentService(
            resolveDataField(data, ['service_id']),
          );
          if (!navigator.mounted) return true;
          push(
            service != null
                ? DocumentsListScreen(service: service)
                : const DocumentsSigningScreen(),
          );
          return true;
        case 'document_changes':
          push(const DocumentsSigningScreen());
          return true;
        case 'mail':
          final connection = await _findMailConnection(
            resolveDataField(data, ['connection_id']),
          );
          if (!navigator.mounted) return true;
          if (connection == null) {
            push(const MailScreen(autoOpenInbox: false));
            return true;
          }
          final messageId = int.tryParse(
            resolveDataField(data, ['email_id', 'message_id']) ?? '',
          );
          // Одно уведомление на пачку писем — открываем ящик, а письмо
          // сразу только если оно одно.
          final count = int.tryParse(resolveDataField(data, ['count']) ?? '');
          if (messageId != null && (count == null || count <= 1)) {
            push(
              MailMessageScreen(connection: connection, messageId: messageId),
            );
          } else {
            push(MailInboxScreen(connection: connection));
          }
          return true;
        case 'chat_message':
          final chatId = data['chat_id']?.toString();
          if (chatId == null || chatId.isEmpty) return false;
          await openChatById(chatId);
          return true;
      }
    } catch (e, st) {
      AppLogger.e(
        'Failed to open notification: $type',
        name: 'notifications.navigation',
        error: e,
        stackTrace: st,
      );
      return false;
    }
    return false;
  }

  static Future<void> _openSurveyInPlace(
    NavigatorState navigator,
    String? token,
  ) async {
    if (token == null || token.isEmpty) {
      unawaited(
        navigator.push<void>(
          CupertinoPageRoute<void>(builder: (_) => const SurveysScreen()),
        ),
      );
      return;
    }
    final pending = SurveyPendingService.instance;
    await pending.refreshQuietly();
    if (!navigator.mounted) return;
    for (final i in pending.invitations) {
      if (i.token == token) {
        unawaited(SurveysScreen.openInvitation(navigator.context, i));
        return;
      }
    }
    unawaited(
      navigator.push<void>(
        CupertinoPageRoute<void>(
          builder: (_) => SurveyFormScreen(token: token),
        ),
      ),
    );
  }

  static Future<DocumentService?> _findDocumentService(String? rawId) async {
    final id = int.tryParse(rawId ?? '');
    if (id == null) return null;
    final services = await DocumentsRepository.instance.getActiveServices();
    for (final s in services) {
      if (s.id == id) return s;
    }
    return null;
  }

  static Future<MailConnection?> _findMailConnection(String? rawId) async {
    final id = int.tryParse(rawId ?? '');
    final userId = await _currentUserId();
    if (id == null || userId == null) return null;
    final connections = await MailRepository.instance.getConnectionsByUser(
      userId,
    );
    for (final c in connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Id брони: `booking_id` наверху или во вложенном `data`, иначе `id`
  /// только во вложенном объекте. Верхний `id` — id уведомления, не брони.
  static String? resolveBookingId(Map<String, dynamic> data) {
    final bookingId = data['booking_id'];
    if (bookingId != null && bookingId.toString().isNotEmpty) {
      return bookingId.toString();
    }

    final nested = _nestedDataMap(data);
    if (nested == null) return null;

    final nestedBookingId = nested['booking_id'];
    if (nestedBookingId != null && nestedBookingId.toString().isNotEmpty) {
      return nestedBookingId.toString();
    }

    final nestedId = nested['id'];
    if (nestedId != null && nestedId.toString().isNotEmpty) {
      return nestedId.toString();
    }
    return null;
  }

  /// Достаёт первое непустое значение из [keys] в data-payload: сначала на
  /// верхнем уровне, а если там нет — из вложенного объекта под ключом
  /// `data` (бэкенд для части типов уведомлений кладёт оригинальные поля
  /// только туда, JSON-строкой в push и вложенной картой в ленте
  /// уведомлений, не дублируя их наверх).
  static String? resolveDataField(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }

    final nestedMap = _nestedDataMap(data);
    if (nestedMap != null) {
      for (final key in keys) {
        final value = nestedMap[key];
        if (value != null && value.toString().isNotEmpty) {
          return value.toString();
        }
      }
    }

    return null;
  }

  static Map<dynamic, dynamic>? _nestedDataMap(Map<String, dynamic> data) {
    final nested = data['data'];
    if (nested is String && nested.isNotEmpty) {
      try {
        final decoded = jsonDecode(nested);
        if (decoded is Map) return decoded;
      } catch (_) {
        return null;
      }
    }
    if (nested is Map) return nested;
    return null;
  }

  static Future<void> processPendingNavigation() async {
    final chatId = takePendingChatId();
    if (chatId != null) {
      await openChatById(chatId);
      return;
    }

    final newsId = takePendingNewsId();
    if (newsId != null) {
      await openNewsById(newsId);
      return;
    }

    final serviceId = _pendingDocumentServiceId;
    if (serviceId != null) {
      _pendingDocumentServiceId = null;
      await openDocumentService(serviceId);
      return;
    }

    final mail = _pendingMail;
    if (mail != null) {
      _pendingMail = null;
      await openMailConnection(mail.connectionId, messageId: mail.messageId);
      return;
    }

    final bookingId = _pendingBookingId;
    if (bookingId != null) {
      _pendingBookingId = null;
      await openBookingById(bookingId);
      return;
    }

    final surveyToken = _pendingSurveyToken;
    if (surveyToken != null) {
      _pendingSurveyToken = null;
      await openSurvey(surveyToken.isEmpty ? null : surveyToken);
    }
  }

  static Future<int?> _currentUserId() =>
      AuthService.instance.getStoredUserId();
}
