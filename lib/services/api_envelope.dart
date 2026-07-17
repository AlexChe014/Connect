import 'api_client.dart';

/// Обёртка ответа бэкенда формата `{ success: bool, data: any }`.
class ApiEnvelope {
  ApiEnvelope._();

  static bool isSuccess(Object? value) {
    if (value == true) return true;
    if (value is num && value == 1) return true;
    if (value is String && value.toLowerCase() == 'true') return true;
    return false;
  }

  static Object? unwrapData(
    Map<String, dynamic> decoded, {
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final success = decoded['success'];
    if (isSuccess(success)) {
      return decoded['data'];
    }

    final data = decoded['data'];
    String? nestedError;
    if (data is Map) {
      nestedError = data['error']?.toString() ?? data['message']?.toString();
    }

    final message =
        decoded['message'] as String? ??
        decoded['error'] as String? ??
        nestedError ??
        defaultErrorMessage;
    throw ApiException(200, message);
  }

  static Map<String, dynamic> unwrapDataMap(
    Map<String, dynamic> decoded, {
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final data = unwrapData(decoded, defaultErrorMessage: defaultErrorMessage);
    if (data == null) return <String, dynamic>{};
    if (data is Map && data.isEmpty) return <String, dynamic>{};
    if (data is Map<String, dynamic>) return data;
    throw ApiException(200, 'Некорректный формат data (ожидался объект)');
  }

  static List unwrapDataList(
    Map<String, dynamic> decoded, {
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final data = unwrapData(decoded, defaultErrorMessage: defaultErrorMessage);
    if (data == null) return const [];
    if (data is Map && data.isEmpty) return const [];
    if (data is List) return data;
    throw ApiException(200, 'Некорректный формат data (ожидался список)');
  }

  static bool unwrapDataBool(
    Map<String, dynamic> decoded, {
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final data = unwrapData(decoded, defaultErrorMessage: defaultErrorMessage);
    if (data is bool) return data;
    if (data is num) return data != 0;
    if (data is String) {
      final s = data.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    throw ApiException(200, 'Некорректный формат data (ожидалось логическое значение)');
  }

  static int unwrapDataInt(
    Map<String, dynamic> decoded, {
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final data = unwrapData(decoded, defaultErrorMessage: defaultErrorMessage);
    if (data is int) return data;
    if (data is num) return data.toInt();
    if (data is String) {
      final parsed = int.tryParse(data.trim());
      if (parsed != null) return parsed;
    }
    throw ApiException(200, 'Некорректный формат data (ожидалось число)');
  }

  static String unwrapDataString(
    Map<String, dynamic> decoded, {
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final data = unwrapData(decoded, defaultErrorMessage: defaultErrorMessage);
    if (data == null) return '';
    if (data is String) return data;
    return data.toString();
  }
}

