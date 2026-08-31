import '../api_config.dart';

/// URL-ы `/nextcloud/*` — файловое хранилище («Диск»).
class DiskRoutes {
  DiskRoutes._();

  static const String _prefix = '/nextcloud';

  static String get filesListUrl => '${ApiConfig.baseUrl}$_prefix/files/list';

  static String get uploadUrl => '${ApiConfig.baseUrl}$_prefix/files/upload';

  static String get deleteFileUrl => '${ApiConfig.baseUrl}$_prefix/files/delete';

  static String get downloadUrl => '${ApiConfig.baseUrl}$_prefix/files/download';

  static String get createFolderUrl => '${ApiConfig.baseUrl}$_prefix/folders/create';

  static String get deleteFolderUrl => '${ApiConfig.baseUrl}$_prefix/folders/delete';

  static String get createPublicShareUrl => '${ApiConfig.baseUrl}$_prefix/shares/public';

  static String get shareWithUserUrl => '${ApiConfig.baseUrl}$_prefix/shares/user';

  static String get listSharesUrl => '${ApiConfig.baseUrl}$_prefix/shares/get';

  static String get deleteShareUrl => '${ApiConfig.baseUrl}$_prefix/shares/delete';
}
