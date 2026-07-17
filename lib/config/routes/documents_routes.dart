import '../api_config.dart';

class DocumentsRoutes {
  DocumentsRoutes._();

  static const String _prefix = '/documents';
  static const String _servicePrefix = '$_prefix/service';

  static String get notificationsUrl => '${ApiConfig.baseUrl}$_prefix/notifications';

  static String get activeServicesUrl => '${ApiConfig.baseUrl}$_servicePrefix/get';

  static String get allServicesUrl => '${ApiConfig.baseUrl}$_servicePrefix/all';

  static String serviceByIdUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_servicePrefix/get/$serviceId';

  static String get authUrl => '${ApiConfig.baseUrl}$_prefix/auth';

  static String authServiceUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/auth/$serviceId';

  static String get logoutUrl => '${ApiConfig.baseUrl}$_prefix/logout';

  static String logoutServiceUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/logout/$serviceId';

  static String get sendCodeUrl => '${ApiConfig.baseUrl}$_prefix/code/send';

  static String get verifyCodeUrl => '${ApiConfig.baseUrl}$_prefix/code/verify';

  static String allDocumentsUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/get/all/$serviceId';

  static String documentUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/get/document/$serviceId';

  static String fileUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/get/file/$serviceId';

  static String acceptorsUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/get/acceptors/$serviceId';

  static String acceptDocumentUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/accept/document/$serviceId';

  static String rejectDocumentUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/reject/document/$serviceId';

  static String acceptDocumentsUrl(int serviceId) =>
      '${ApiConfig.baseUrl}$_prefix/accept/documents/$serviceId';
}
