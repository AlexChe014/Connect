import 'package:connect/config/routes/settings_routes.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';
import 'package:connect/utils/media_url_utils.dart';

class SettingsRepository {
  SettingsRepository._();
  static final SettingsRepository instance = SettingsRepository._();

  static const String connectModule = 'connect';
  static const String lightLogoKey = 'light_logo';

  /// Логотип светлой темы: `GET /settings/get?module=connect&key=light_logo`.
  Future<String?> getConnectLightLogo({String? host}) async {
    final url = host == null
        ? SettingsRoutes.getUrl
        : SettingsRoutes.getUrlForHost(host);
    try {
      final withKey = await _fetchLogo(url, includeKey: true);
      if (withKey != null) return withKey;
    } catch (_) {}
    return _fetchLogo(url, includeKey: false);
  }

  Future<String?> _fetchLogo(String url, {required bool includeKey}) async {
    final decoded = await ApiClient.instance.get(
      url,
      queryParameters: {
        'module': connectModule,
        if (includeKey) 'key': lightLogoKey,
      },
    );
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: 'Не удалось получить настройки',
    );
    return _extractLightLogo(data);
  }

  static String? _extractLightLogo(Object? data) {
    if (data == null) return null;

    final fromMedia = MediaUrlUtils.normalizeFirstUrl(data);
    if (fromMedia != null && fromMedia.isNotEmpty) return fromMedia;

    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);

    final settingsRaw = map['settings'];
    final settings = settingsRaw is Map
        ? Map<String, dynamic>.from(settingsRaw)
        : map;

    for (final key in [lightLogoKey, 'lightLogo', 'logo']) {
      final url = MediaUrlUtils.normalizeFirstUrl(settings[key] ?? map[key]);
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }
}
