import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:http/http.dart' as http;

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
    };
    final token = AuthService.instance.token;
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
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
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(response, uri: uri, method: 'GET');
    } catch (e, st) {
      AppLogger.e('HTTP GET failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
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

    try {
      final response = await http
          .post(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(response, uri: uri, method: 'POST');
    } catch (e, st) {
      AppLogger.e('HTTP POST form failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> post(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    try {
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(response, uri: uri, method: 'POST');
    } catch (e, st) {
      AppLogger.e('HTTP POST failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> patch(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    try {
      final response = await http
          .patch(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(response, uri: uri, method: 'PATCH');
    } catch (e, st) {
      AppLogger.e('HTTP PATCH failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> put(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    try {
      final response = await http
          .put(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(response, uri: uri, method: 'PUT');
    } catch (e, st) {
      AppLogger.e('HTTP PUT failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> delete(String url) async {
    final uri = Uri.parse(url);
    try {
      final response = await http
          .delete(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(response, uri: uri, method: 'DELETE');
    } catch (e, st) {
      AppLogger.e('HTTP DELETE failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
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

    try {
      final streamed = await request.send().timeout(
        Duration(seconds: ApiConfig.timeoutSeconds),
      );
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response, uri: uri, method: 'POST multipart');
    } catch (e, st) {
      AppLogger.e(
        'HTTP POST multipart failed: $uri',
        name: 'network.http',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<List<int>> downloadBytes(String url) async {
    final uri = Uri.parse(url);
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      throw ApiException(response.statusCode, 'Не удалось скачать файл');
    } catch (e, st) {
      AppLogger.e('HTTP download failed: $uri', name: 'network.http', error: e, stackTrace: st);
      rethrow;
    }
  }

  Map<String, dynamic> _handleResponse(
    http.Response response, {
    required Uri uri,
    required String method,
  }) {
    final body = response.body.isEmpty ? '{}' : response.body;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
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
      message =
          decoded['message'] as String? ??
          decoded['error'] as String? ??
          (decoded['errors'] as List?)?.join(', ') ??
          message;
    }
    throw ApiException(response.statusCode, message);
  }
}
