import 'api_config.dart';

/// Параметры Laravel Reverb (публичный app key, хост, порт).
///
/// Ключ не секретный — тот же `REVERB_APP_KEY`, что у веб-Echo.
/// Приоритет: настройки API (`module=reverb` / `broadcasting`) →
/// `--dart-define=REVERB_APP_KEY=...` → хост текущего бэкенда.
class ReverbConfig {
  const ReverbConfig({
    required this.appKey,
    required this.host,
    required this.port,
    required this.useTls,
    this.path = '',
  });

  final String appKey;
  final String host;
  final int port;
  final bool useTls;

  /// Префикс пути, если Reverb за прокси на subpath (`/ws`). Пусто — стандартный `/app/{key}`.
  final String path;

  bool get isConfigured => appKey.isNotEmpty && host.isNotEmpty;

  static ReverbConfig fromEnvironment() {
    final backend = Uri.parse(ApiConfig.backendHost);
    final tlsDefine = const String.fromEnvironment('REVERB_SCHEME');
    final useTls = tlsDefine.isEmpty
        ? backend.scheme != 'http'
        : tlsDefine.toLowerCase() != 'http';
    final portRaw = const String.fromEnvironment('REVERB_PORT');
    final port = int.tryParse(portRaw) ??
        (backend.hasPort ? backend.port : (useTls ? 443 : 80));
    final hostDefine = const String.fromEnvironment('REVERB_HOST');
    return ReverbConfig(
      appKey: const String.fromEnvironment('REVERB_APP_KEY').trim(),
      host: hostDefine.trim().isEmpty ? backend.host : hostDefine.trim(),
      port: port,
      useTls: useTls,
      path: const String.fromEnvironment('REVERB_PATH').trim(),
    );
  }

  static ReverbConfig fromSettings(
    Map<String, dynamic> settings, {
    required ReverbConfig fallback,
  }) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final raw = settings[key];
        if (raw == null) continue;
        final text = raw.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return null;
    }

    final appKey = pick(const [
          'app_key',
          'reverb_app_key',
          'key',
          'REVERB_APP_KEY',
          'pusher_key',
        ]) ??
        fallback.appKey;

    var host = pick(const [
          'host',
          'reverb_host',
          'ws_host',
          'REVERB_HOST',
        ]) ??
        fallback.host;
    final hostUri = Uri.tryParse(host);
    if (hostUri != null && hostUri.host.isNotEmpty) {
      host = hostUri.host;
    }

    final scheme = pick(const ['scheme', 'reverb_scheme', 'REVERB_SCHEME']);
    final useTls = scheme == null
        ? fallback.useTls
        : scheme.toLowerCase() != 'http';

    final portRaw = pick(const ['port', 'reverb_port', 'ws_port', 'REVERB_PORT']);
    final port = int.tryParse(portRaw ?? '') ?? fallback.port;

    final path = pick(const ['path', 'reverb_path', 'server_path', 'REVERB_PATH']) ??
        fallback.path;

    return ReverbConfig(
      appKey: appKey,
      host: host,
      port: port,
      useTls: useTls,
      path: path,
    );
  }

  List<String> authCandidateUrls() {
    final backend = ApiConfig.backendHost.replaceAll(RegExp(r'/+$'), '');
    return [
      '${ApiConfig.baseUrl}/broadcasting/auth',
      '$backend/broadcasting/auth',
      '$backend/api/broadcasting/auth',
    ];
  }
}
