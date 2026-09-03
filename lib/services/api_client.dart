import 'dart:async';
import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/network_errors.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:http/http.dart' as http;

export 'network_errors.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...authHeaders,
    };
    return headers;
  }

  /// Заголовок авторизации без `Content-Type` — для скачивания файлов
  /// и картинок через [CachedNetworkImage].
  Map<String, String> get authHeaders {
    final token = AuthService.instance.token;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? queryParameters,
  }) async {
    var uri = Uri.parse(url);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          ...queryParameters,
        },
      );
    }
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'GET',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP GET failed: $uri', e, st);
    }
  }

  /// POST с телом `application/x-www-form-urlencoded` (как form-data в Postman).
  Future<Map<String, dynamic>> postForm(
    String url, {
    required List<MapEntry<String, String>> fields,
  }) async {
    final uri = Uri.parse(url);
    final body = fields
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final headers = Map<String, String>.from(_headers);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    final sessionGeneration = AuthService.instance.sessionGeneration;

    try {
      final response = await http
          .post(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'POST',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP POST form failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> post(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'POST',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP POST failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> patch(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .patch(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'PATCH',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP PATCH failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> put(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .put(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'PUT',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP PUT failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> delete(String url) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .delete(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'DELETE',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP DELETE failed: $uri', e, st);
    }
  }

  /// POST `multipart/form-data` (как form-data в Postman).
  Future<Map<String, dynamic>> postMultipart(
    String url, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
  }) async {
    final uri = Uri.parse(url);
    final request = http.MultipartRequest('POST', uri);
    final headers = Map<String, String>.from(_headers);
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.fields.addAll(fields);
    request.files.addAll(files);
    final sessionGeneration = AuthService.instance.sessionGeneration;

    try {
      final streamed = await request.send().timeout(
        Duration(seconds: ApiConfig.timeoutSeconds),
      );
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(
        response,
        uri: uri,
        method: 'POST multipart',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP POST multipart failed: $uri', e, st);
    }
  }

  Future<List<int>> downloadBytes(String url) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        AuthService.instance.noteRequestSucceeded(
          sessionGeneration: sessionGeneration,
        );
        return response.bodyBytes;
      }
      _noteResponseAuthOutcome(
        statusCode: response.statusCode,
        sessionGeneration: sessionGeneration,
      );
      throw ApiException(response.statusCode, 'Не удалось скачать файл');
    } catch (e, st) {
      throw _mapAndLog('HTTP download failed: $uri', e, st);
    }
  }

  Never _mapAndLog(String label, Object e, StackTrace st) {
    AppLogger.e(label, name: 'network.http', error: e, stackTrace: st);
    if (e is ApiException) throw e;
    throw mapNetworkError(e);
  }

  Map<String, dynamic> _handleResponse(
    http.Response response, {
    required Uri uri,
    required String method,
    required int sessionGeneration,
  }) {
    final body = response.body.isEmpty ? '{}' : response.body;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      AuthService.instance.noteRequestSucceeded(
        sessionGeneration: sessionGeneration,
      );
      if (decoded is Map<String, dynamic>) return decoded;
      AppLogger.e(
        'HTTP $method $uri: unexpected success body (not a JSON object)\n'
        'status: ${response.statusCode}\n'
        'body: ${AppLogger.truncate(body)}',
        name: 'network.http',
      );
      throw ApiException(response.statusCode, 'Некорректный ответ сервера');
    }

    AppLogger.e(
      'HTTP $method $uri failed\n'
      'status: ${response.statusCode}\n'
      'headers: ${AppLogger.prettyJson(response.headers)}\n'
      'body: ${AppLogger.truncate(body)}',
      name: 'network.http',
    );

    String message = 'Ошибка запроса (${response.statusCode})';
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      final nestedError = data is Map ? data['error']?.toString() : null;
      message =
          decoded['message'] as String? ??
          decoded['error'] as String? ??
          (decoded['errors'] as List?)?.join(', ') ??
          nestedError ??
          message;
    }

    _noteResponseAuthOutcome(
      statusCode: response.statusCode,
      sessionGeneration: sessionGeneration,
      message: message,
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        response.statusCode,
        message.isNotEmpty && message != 'Ошибка запроса (${response.statusCode})'
            ? message
            : 'Ошибка авторизации. Войдите в аккаунт снова.',
      );
    }

    throw ApiException(response.statusCode, message);
  }

  void _noteResponseAuthOutcome({
    required int statusCode,
    required int sessionGeneration,
    String? message,
  }) {
    if (_isAuthenticationFailure(statusCode, message)) {
      AuthService.instance.noteAuthenticationFailed(
        sessionGeneration: sessionGeneration,
      );
    }
  }

  bool _isAuthenticationFailure(int statusCode, String? message) {
    if (statusCode == 401) return true;
    final normalized = message?.toLowerCase() ?? '';
    return normalized.contains('unauthenticated');
  }
}
