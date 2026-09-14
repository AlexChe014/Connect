import 'dart:async';
import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/config/reverb_config.dart';
import 'package:connect/repositories/settings_repository.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:connect/utils/chat_realtime_payload.dart';
import 'package:http/http.dart' as http;
import 'package:laravel_reverb/laravel_reverb.dart';

/// Клиент Laravel Reverb: живые события чатов → [ChatService].
class ChatRealtimeService {
  ChatRealtimeService._();
  static final ChatRealtimeService instance = ChatRealtimeService._();

  static const _logName = 'chat.reverb';

  Reverb? _client;
  bool _started = false;
  bool _connecting = false;
  ReverbConfig? _config;
  String? _workingAuthUrl;
  int? _subscribedUserId;
  final List<Subscription> _userSubs = [];
  final Map<String, Subscription> _chatSubs = {};

  bool get isStarted => _started;
  bool get isConnected => _client != null;

  Future<void> start() async {
    if (!AuthService.instance.isAuthenticated) return;
    if (!_started) {
      _started = true;
      ChatService.instance.addListener(_onChatsChanged);
    }
    await _ensureConnected();
    _syncSubscriptions();
  }

  Future<void> stop() async {
    _started = false;
    ChatService.instance.removeListener(_onChatsChanged);
    _clearSubscriptions();
    _workingAuthUrl = null;
    _config = null;
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.disconnect(forget: true);
      } catch (_) {}
      client.dispose();
    }
  }

  void _onChatsChanged() {
    if (!_started) return;
    if (_client == null) {
      unawaited(_ensureConnected().then((_) => _syncSubscriptions()));
      return;
    }
    _syncSubscriptions();
  }

  Future<void> _ensureConnected() async {
    if (_client != null || _connecting) return;
    _connecting = true;
    try {
      final config = await _resolveConfig();
      _config = config;
      if (!config.isConfigured) {
        AppLogger.e(
          'Reverb: нет app key. Задайте настройки module=reverb '
          '(app_key) или --dart-define=REVERB_APP_KEY=...',
          name: _logName,
        );
        return;
      }

      final client = Reverb(
        host: config.host,
        port: config.port,
        appKey: config.appKey,
        useTls: config.useTls,
        path: config.path,
        pingInterval: const Duration(seconds: 20),
        watchdogTimeout: const Duration(seconds: 40),
        authorizer: _authorize,
        onError: (error, stack) {
          AppLogger.e(
            'Reverb error: $error',
            name: _logName,
            error: error,
            stackTrace: stack,
          );
        },
        onLog: (message) => AppLogger.d(message, name: _logName),
      );
      client.onReconnected(() {
        unawaited(ChatService.instance.refreshChats(showLoading: false));
        unawaited(ChatService.instance.reloadCachedMessages());
      });
      _client = client;
      await client.connect();
      AppLogger.d(
        'Reverb connected ${config.host}:${config.port} key=${config.appKey}',
        name: _logName,
      );
    } catch (e, st) {
      AppLogger.e(
        'Reverb connect failed',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      _client?.dispose();
      _client = null;
    } finally {
      _connecting = false;
    }
  }

  Future<ReverbConfig> _resolveConfig() async {
    var config = ReverbConfig.fromEnvironment();
    for (final module in [
      SettingsRepository.reverbModule,
      SettingsRepository.broadcastingModule,
      SettingsRepository.connectModule,
    ]) {
      try {
        final settings = await SettingsRepository.instance.getModuleSettings(
          module,
        );
        config = ReverbConfig.fromSettings(settings, fallback: config);
        if (config.appKey.isNotEmpty) break;
      } catch (_) {}
    }
    return config.forDevice();
  }

  Future<ReverbAuth> _authorize(String channelName, String socketId) async {
    final token = AuthService.instance.token;
    if (token == null || token.isEmpty) {
      throw StateError('Reverb auth: нет токена');
    }

    final urls = <String>[
      if (_workingAuthUrl != null) _workingAuthUrl!,
      ...?_config?.authCandidateUrls(),
    ];
    final seen = <String>{};
    Object? lastError;

    for (final url in urls) {
      if (!seen.add(url)) continue;
      try {
        final auth = await _postAuth(
          url,
          channelName: channelName,
          socketId: socketId,
          token: token,
        );
        _workingAuthUrl = url;
        return auth;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('Reverb auth failed');
  }

  Future<ReverbAuth> _postAuth(
    String url, {
    required String channelName,
    required String socketId,
    required String token,
  }) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Authorization': 'Bearer $token',
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: 'socket_id=${Uri.encodeQueryComponent(socketId)}'
              '&channel_name=${Uri.encodeQueryComponent(channelName)}',
        )
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Reverb auth ${response.statusCode} $url ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final map = ChatRealtimePayload.asJsonMap(decoded);
    if (map == null) {
      throw StateError('Reverb auth: не JSON-объект');
    }
    final data = ChatRealtimePayload.asJsonMap(map['data']) ?? map;
    final auth = data['auth']?.toString();
    if (auth == null || auth.isEmpty) {
      throw StateError('Reverb auth: нет поля auth');
    }
    final channelData = data['channel_data']?.toString();
    return ReverbAuth(auth: auth, channelData: channelData);
  }

  void _syncSubscriptions() {
    final client = _client;
    if (client == null || !_started) return;

    final userId = ChatService.instance.selfUserId;
    if (userId != _subscribedUserId) {
      for (final sub in _userSubs) {
        sub.cancel();
      }
      _userSubs.clear();
      _subscribedUserId = userId;
      if (userId != null) {
        for (final name in ['App.Models.User.$userId', 'user.$userId']) {
          _userSubs.add(_listen(client.private(name), name));
        }
      }
    }

    final ids = ChatService.instance.chats.map((c) => c.id).toSet();
    final stale = _chatSubs.keys.where((id) => !ids.contains(id)).toList();
    for (final id in stale) {
      _chatSubs.remove(id)?.cancel();
    }
    for (final id in ids) {
      if (_chatSubs.containsKey(id)) continue;
      _chatSubs[id] = _listen(client.private('chat.$id'), 'chat.$id');
    }
  }

  Subscription _listen(PrivateChannel channel, String name) {
    return channel.listenAll((event, data) {
      if (ChatRealtimePayload.isProtocolEvent(event)) return;
      ChatService.instance.applyRealtimeEvent(
        eventName: event,
        data: data,
        channelName: name,
      );
    });
  }

  void _clearSubscriptions() {
    for (final sub in _userSubs) {
      sub.cancel();
    }
    _userSubs.clear();
    for (final sub in _chatSubs.values) {
      sub.cancel();
    }
    _chatSubs.clear();
    _subscribedUserId = null;
  }
}
