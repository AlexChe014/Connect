import 'package:connect/models/documents/document_service.dart';
import 'package:connect/models/mail/mail_connection.dart';
import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/repositories/documents_repository.dart';
import 'package:connect/repositories/mail_repository.dart';
import 'package:connect/screens/booking_detail_sheet.dart';
import 'package:connect/screens/chat_conversation_screen.dart';
import 'package:connect/screens/documents_list_screen.dart';
import 'package:connect/screens/documents_signing_screen.dart';
import 'package:connect/screens/mail_inbox_screen.dart';
import 'package:connect/screens/mail_message_screen.dart';
import 'package:connect/screens/mail_screen.dart';
import 'package:connect/services/auth_service.dart';
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

  static void storePendingChat(String chatId) => _pendingChatId = chatId;

  static void storePendingNews(String newsId) => _pendingNewsId = newsId;

  static void storePendingDocument(String serviceId) =>
      _pendingDocumentServiceId = serviceId;

  static void storePendingMail(String connectionId, String? messageId) =>
      _pendingMail = _PendingMail(connectionId, messageId);

  static void storePendingBooking(String bookingId) =>
      _pendingBookingId = bookingId;

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

    final userId = await _currentUserId();
    if (userId == null) {
      storePendingChat(chatId);
      return;
    }

    await navigator.pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'initialIndex': 2},
    );

    if (!navigator.mounted) return;
    try {
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
    await navigator.pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'initialIndex': 0, 'openNewsId': newsId},
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

    await navigator.pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'initialIndex': 0},
    );

    if (!navigator.mounted) return;
    await navigator.push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const DocumentsSigningScreen(),
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
      await navigator.push<void>(
        CupertinoPageRoute<void>(
          builder: (context) => DocumentsListScreen(service: service!),
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

    await navigator.pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'initialIndex': 0},
    );

    if (!navigator.mounted) return;
    await navigator.push<void>(
      CupertinoPageRoute<void>(builder: (context) => const MailScreen()),
    );

    final id = int.tryParse(connectionId);
    final userId = await _currentUserId();
    if (id == null || userId == null) return;
    try {
      final connections = await MailRepository.instance.getConnectionsByUser(
        userId,
      );
      MailConnection? connection;
      for (final c in connections) {
        if (c.id == id) {
          connection = c;
          break;
        }
      }
      if (connection == null || !navigator.mounted) return;
      await navigator.push<void>(
        CupertinoPageRoute<void>(
          builder: (context) => MailInboxScreen(connection: connection!),
        ),
      );

      final msgId = int.tryParse(messageId ?? '');
      if (msgId == null || !navigator.mounted) return;
      await navigator.push<void>(
        CupertinoPageRoute<void>(
          builder: (context) =>
              MailMessageScreen(connection: connection!, messageId: msgId),
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

    await navigator.pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'initialIndex': 1},
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

  /// Общая точка входа для навигации по `type`/`data` — используется и для
  /// тапа по push (см. `PushNotificationService`), и для тапа по элементу
  /// ленты уведомлений (`NotificationsScreen`), чтобы не дублировать логику.
  static Future<void> openFromData(Map<String, dynamic> data) async {
    switch (data['type']) {
      case 'chat_message':
        final chatId = data['chat_id']?.toString();
        if (chatId != null && chatId.isNotEmpty) {
          await openChatById(chatId);
        }
      case 'news':
        final newsId = data['news_id']?.toString();
        if (newsId != null && newsId.isNotEmpty) {
          await openNewsById(newsId);
        }
      case 'document':
        final serviceId = data['service_id']?.toString();
        if (serviceId != null && serviceId.isNotEmpty) {
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
      case 'meeting_invite':
      case 'meeting_reminder':
        final bookingId = data['booking_id']?.toString();
        if (bookingId != null && bookingId.isNotEmpty) {
          await openBookingById(bookingId);
        }
    }
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
    }
  }

  static Future<int?> _currentUserId() async {
    final user = await AuthService.instance.getStoredUser();
    if (user == null) return null;

    final rawId = user['id'];
    if (rawId is int) return rawId;
    return int.tryParse(rawId?.toString() ?? '');
  }
}
