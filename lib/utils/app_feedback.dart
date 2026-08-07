import 'dart:async';
import 'dart:io';

import 'package:connect/services/api_client.dart';
import 'package:connect/services/auth_service.dart';
import 'package:flutter/material.dart';

/// Единая точка показа ошибок сети/авторизации пользователю.
class AppFeedback {
  AppFeedback._();

  static String messageOf(Object error, {String? fallback}) {
    if (error is String && error.trim().isNotEmpty) return error;
    if (error is AuthException) return error.message;
    if (error is ApiException) return error.message;
    if (error is NetworkException) return error.message;
    if (error is TimeoutException) {
      return 'Превышено время ожидания ответа сервера. Проверьте интернет и попробуйте снова.';
    }
    if (error is SocketException) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Network is unreachable')) {
      return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
    }
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return 'Превышено время ожидания ответа сервера. Попробуйте снова.';
    }
    return fallback ?? 'Произошла ошибка. Попробуйте снова.';
  }

  static void showSnackBar(
    BuildContext context,
    Object error, {
    String? fallback,
  }) {
    if (!context.mounted) return;
    final message = messageOf(error, fallback: fallback);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> showAlert(
    BuildContext context,
    Object error, {
    String title = 'Ошибка',
    String? fallback,
  }) async {
    if (!context.mounted) return;
    final message = messageOf(error, fallback: fallback);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
