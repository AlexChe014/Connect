import 'dart:convert';

import 'package:connect/config/api_config.dart';
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
    if (ApiConfig.useMockApi) {
      if (email.isEmpty || password.isEmpty) {
        throw AuthException('Введите email и пароль');
      }
      const mockToken = 'mock_bearer_token_12345';
      final user = {'email': email, 'name': email.split('@').first};
      await _saveSession(mockToken, user);
      return AuthResult(token: mockToken, user: user);
    }

    final response = await http.post(
      Uri.parse(ApiConfig.authLoginUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ).timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String? ?? data['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw AuthException('Токен не получен от сервера');
      }
      final user = data['user'] as Map<String, dynamic>?;
      await _saveSession(token, user);
      return AuthResult(token: token, user: user);
    } else {
      final body = response.body;
      String message = 'Ошибка авторизации';
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        message = json['message'] as String? ?? json['error'] as String? ?? message;
      } catch (_) {}
      throw AuthException(message);
    }
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
