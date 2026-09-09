import 'package:connect/config/routes/settings_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/media_url_utils.dart';

class SettingsRepository {
  SettingsRepository._();
  static final SettingsRepository instance = SettingsRepository._();

  static const String connectModule = 'connect';
  static const String bonusProgramModule = 'bonus_program';
  static const String reverbModule = 'reverb';
  static const String broadcastingModule = 'broadcasting';
  static const String lightLogoKey = 'light_logo';

  /// `GET /settings/get?module=...` — карта ключей модуля.
  ///
  /// Бэкенд отдаёт настройки сразу в `data` (`light_logo`, `transfer_min_points`
  /// и т.д.), без вложенного `settings`.
  Future<Map<String, dynamic>> getModuleSettings(
    String module, {
    String? host,
    String? key,
  }) async {
    final url = host == null
        ? SettingsRoutes.getUrl
        : SettingsRoutes.getUrlForHost(host);
    final decoded = await ApiClient.instance.get(
      url,
      queryParameters: {
        'module': module,
        'key': ?key,
      },
    );
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось получить настройки',
    );
    return _asSettingsMap(data);
  }

  /// Главный логотип: `GET /settings/get?module=connect` → `light_logo`.
  Future<String?> getConnectLightLogo({String? host}) async {
    try {
      final settings = await getModuleSettings(connectModule, host: host);
      return _extractLightLogo(settings);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _asSettingsMap(Object? data) {
    if (data is! Map) return const {};
    final map = Map<String, dynamic>.from(data);
    final nested = map['settings'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return map;
  }

  static String? _extractLightLogo(Map<String, dynamic> settings) {
    for (final key in [lightLogoKey, 'lightLogo', 'logo', 'dark_logo']) {
      final raw = settings[key];
      final url =
          MediaUrlUtils.normalizeFirstOriginalUrl(raw) ??
          MediaUrlUtils.normalizeFirstUrl(raw);
      if (url != null && url.isNotEmpty) return url;
    }
    return MediaUrlUtils.normalizeFirstOriginalUrl(settings) ??
        MediaUrlUtils.normalizeFirstUrl(settings);
  }
}
