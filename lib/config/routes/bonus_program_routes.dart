import '../api_config.dart';

/// URL-ы `/bonus-program/*` — бонусная программа (баллы, магазин, рулетка, форма достижений).
class BonusProgramRoutes {
  BonusProgramRoutes._();

  static const String _prefix = '/bonus-program';

  static String get balanceUrl => '${ApiConfig.baseUrl}$_prefix/points/balance';

  static String get historyUrl => '${ApiConfig.baseUrl}$_prefix/points/history';

  static String get transferUrl => '${ApiConfig.baseUrl}$_prefix/points/transfers';

  static String get transferConfigUrl => '${ApiConfig.baseUrl}$_prefix/points/transfer-config';

  static String get shopUrl => '${ApiConfig.baseUrl}$_prefix/shop';

  static String get shopRequestUrl => '${ApiConfig.baseUrl}$_prefix/shop/request';

  static String get rouletteConfigUrl => '${ApiConfig.baseUrl}$_prefix/roulette/config';

  static String get roulettePrizesUrl => '${ApiConfig.baseUrl}$_prefix/roulette/prizes';

  static String get rouletteSpinUrl => '${ApiConfig.baseUrl}$_prefix/roulette/spin';

  static String get achievementTypesUrl => '${ApiConfig.baseUrl}$_prefix/achievement-types';

  static String get formConfigUrl => '${ApiConfig.baseUrl}$_prefix/form-submissions/config';

  static String get formSubmissionsUrl => '${ApiConfig.baseUrl}$_prefix/form-submissions';
}
