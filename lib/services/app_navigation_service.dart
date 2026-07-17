import 'package:connect/repositories/chat_repository.dart';
import 'package:connect/screens/chat_conversation_screen.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/material.dart';

class AppNavigationService {
  AppNavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static String? _pendingChatId;
  static String? _pendingNewsId;

  static void storePendingChat(String chatId) => _pendingChatId = chatId;

  static void storePendingNews(String newsId) => _pendingNewsId = newsId;

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
      if (!navigator.mounted) return;
      await navigator.pushNamed(
        '/home',
        arguments: {'initialIndex': 2},
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
      arguments: {
        'initialIndex': 0,
        'homeSection': 'news',
        'openNewsId': newsId,
      },
    );
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
