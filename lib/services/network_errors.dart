import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class NetworkException implements Exception {
  final String message;

  NetworkException(this.message);

  @override
  String toString() => message;
}

/// Преобразует системные сетевые ошибки в [NetworkException] с понятным текстом.
Object mapNetworkError(Object e) {
  if (e is NetworkException) return e;
  if (e is TimeoutException) {
    return NetworkException(
      'Превышено время ожидания ответа сервера. Проверьте интернет и попробуйте снова.',
    );
  }
  if (e is SocketException) {
    return NetworkException(
      'Нет подключения к интернету. Проверьте сеть и попробуйте снова.',
    );
  }
  if (e is http.ClientException) {
    return NetworkException(
      'Не удалось связаться с сервером. Проверьте интернет и попробуйте снова.',
    );
  }
  final text = e.toString();
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection refused')) {
    return NetworkException(
      'Нет подключения к интернету. Проверьте сеть и попробуйте снова.',
    );
  }
  if (text.contains('TimeoutException') || text.contains('timed out')) {
    return NetworkException(
      'Превышено время ожидания ответа сервера. Попробуйте снова.',
    );
  }
  return NetworkException('Произошла ошибка сети. Попробуйте снова.');
}
