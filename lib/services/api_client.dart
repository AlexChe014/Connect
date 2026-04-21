import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/services/auth_service.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);
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

  Future<Map<String, dynamic>> get(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> post(String url, {Map<String, dynamic>? body}) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = response.body.isEmpty ? '{}' : response.body;
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data ?? {};
    }

    String message = 'Ошибка запроса (${response.statusCode})';
    if (data != null) {
      message = data['message'] as String? ??
          data['error'] as String? ??
          (data['errors'] as List?)?.join(', ') ??
          message;
    }
    throw ApiException(response.statusCode, message);
  }
}
