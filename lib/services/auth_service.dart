import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/config/routes/auth_routes.dart';
import 'package:connect/services/network_errors.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _tokenKey = 'auth_bearer_token';
const _userKey = 'auth_user_data';

class AuthResult {
  final String token;
  final Map<String, dynamic>? user;

  AuthResult({required this.token, this.user});
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<AuthResult> login(String email, String password) async {
    final uri = Uri.parse(AuthRoutes.loginUrl);
    final requestBody = {'email': email, 'password': password};

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
    } catch (e, st) {
      AppLogger.e('Auth login request failed: POST $uri', name: 'network.auth', error: e, stackTrace: st);
      final mapped = mapNetworkError(e);
      if (mapped is NetworkException) {
        throw AuthException(mapped.message);
      }
      throw AuthException('Не удалось выполнить вход. Проверьте интернет и попробуйте снова.');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (e, st) {
        AppLogger.e(
          'Auth login: invalid JSON response\n'
          'status: ${response.statusCode}\n'
          'url: $uri\n'
          'body: ${AppLogger.truncate(response.body)}',
          name: 'network.auth',
          error: e,
          stackTrace: st,
        );
        throw AuthException('Некорректный ответ сервера');
      }

      if (decoded is! Map<String, dynamic>) {
        AppLogger.e(
          'Auth login: unexpected success body (not a JSON object)\n'
          'status: ${response.statusCode}\n'
          'url: $uri\n'
          'body: ${AppLogger.truncate(response.body)}',
          name: 'network.auth',
        );
        throw AuthException('Некорректный ответ сервера');
      }

      final success = decoded['success'];
      final payload = decoded['data'];
      if (success != true || payload is! Map<String, dynamic>) {
        final message =
            decoded['message'] as String? ?? decoded['error'] as String? ?? 'Ошибка авторизации';
        AppLogger.e(
          'Auth login: success=false or invalid data\n'
          'status: ${response.statusCode}\n'
          'url: $uri\n'
          'decoded: ${AppLogger.prettyJson(decoded)}',
          name: 'network.auth',
        );
        throw AuthException(message);
      }

      final token = _extractToken(payload);
      if (token == null || token.isEmpty) {
        AppLogger.e(
          'Auth login: access_token missing\n'
          'status: ${response.statusCode}\n'
          'url: $uri\n'
          'data: ${AppLogger.prettyJson(payload)}',
          name: 'network.auth',
        );
        throw AuthException('Токен не получен от сервера');
      }
      final user = payload['user'] as Map<String, dynamic>?;
      final profile = user ?? payload;
      await _saveSession(token, profile);
      return AuthResult(token: token, user: profile);
    } else {
      final body = response.body;
      String message = 'Ошибка авторизации';
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        message = json['message'] as String? ?? json['error'] as String? ?? message;
      } catch (_) {}

      AppLogger.e(
        'Auth login failed\n'
        'status: ${response.statusCode}\n'
        'url: $uri\n'
        'body: ${AppLogger.truncate(body)}',
        name: 'network.auth',
      );
      throw AuthException(message);
    }
  }

  String? _extractToken(Map<String, dynamic> data) {
    final t = data['access_token'];
    return t is String ? t : null;
  }

  Future<void> _saveSession(String token, Map<String, dynamic>? user) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user));
    }
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<Map<String, dynamic>?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_userKey);
    if (json == null) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}
