import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/config/routes/auth_routes.dart';
import 'package:connect/config/routes/user_routes.dart';
import 'package:connect/services/network_errors.dart';
import 'package:connect/services/session_auth_guard.dart';
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
  AuthService._() {
    _sessionGuard = SessionAuthGuard(
      isAuthenticated: () => isAuthenticated,
      sessionGeneration: () => sessionGeneration,
      verifySession: _probeSession,
      onExpired: _expireSession,
    );
  }
  static final AuthService instance = AuthService._();

  late final SessionAuthGuard _sessionGuard;

  String? _token;
  int _sessionGeneration = 0;
  bool _handlingExpiry = false;

  /// Вызывается после принудительного разлогина из-за мёртвой сессии.
  void Function()? onSessionExpired;

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  int get sessionGeneration => _sessionGeneration;

  void noteRequestSucceeded({required int sessionGeneration}) {
    _sessionGuard.noteSuccess(generation: sessionGeneration);
  }

  void noteAuthenticationFailed({required int sessionGeneration}) {
    _sessionGuard.noteAuthFailure(generation: sessionGeneration);
  }

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
    _sessionGeneration++;
    _sessionGuard.reset();
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user));
    }
  }

  Future<void> logout() async {
    _sessionGeneration++;
    _sessionGuard.reset();
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  /// `true` — бэкенд отверг токен, `false` — сессия жива, `null` — неизвестно.
  Future<bool?> _probeSession() async {
    final token = _token;
    if (token == null || token.isEmpty) return true;

    try {
      final response = await http
          .get(
            Uri.parse(UserRoutes.getProfileUrl),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

      if (response.statusCode == 401) return true;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return false;
      }
      return null;
    } catch (e, st) {
      AppLogger.e(
        'Session probe failed',
        name: 'auth.session',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _expireSession() async {
    if (_handlingExpiry || !isAuthenticated) return;
    _handlingExpiry = true;
    try {
      AppLogger.e(
        'Session expired: backend requests returned authentication errors',
        name: 'auth.session',
      );
      await logout();
      onSessionExpired?.call();
    } finally {
      _handlingExpiry = false;
    }
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
