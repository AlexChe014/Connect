import '../api_config.dart';

class MailRoutes {
  MailRoutes._();

  static const String _mailPrefix = '/mail';
  static const String _connectionPrefix = '$_mailPrefix/connection';

  static String getByUserUrl(int userId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/user/$userId';

  static String getByServiceUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/service/$connectionId';

  static String getByFolderUrl(int connectionId, int folderId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/folder/$connectionId/$folderId';

  static String getMailboxesUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/mailboxes/$connectionId';

  static String getMessageUrl(int connectionId, int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/message/$connectionId/$messageId';

  static String moveMessageUrl(int connectionId, int messageId, int folderId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/move/$connectionId/$messageId/$folderId';

  static String deleteMessageUrl(int connectionId, int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/delete/$connectionId/$messageId';

  static String attachmentUrl(int connectionId, int attachmentId, String filename) {
    final encoded = Uri.encodeComponent(filename);
    return '${ApiConfig.baseUrl}$_mailPrefix/attachments/$connectionId/$attachmentId/$encoded';
  }

  static String get smtpSendUrl => '${ApiConfig.baseUrl}$_mailPrefix/smtp/send';

  static String get smtpAttachmentUrl =>
      '${ApiConfig.baseUrl}$_mailPrefix/smtp/attachment';

  static String connectionsByUserUrl(int userId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/get/user/$userId';

  static String connectionByIdUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/get/$connectionId';

  static String updateConnectionUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/update/$connectionId';

  static String get createConnectionUrl =>
      '${ApiConfig.baseUrl}$_connectionPrefix/create';
}
