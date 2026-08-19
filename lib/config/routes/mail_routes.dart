import '../api_config.dart';

class MailRoutes {
  MailRoutes._();

  static const String _mailPrefix = '/mail';
  static const String _connectionPrefix = '$_mailPrefix/connection';

  // --- Connections ---

  static String connectionsByUserUrl(int userId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/get/user/$userId';

  static String connectionByIdUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/get/$connectionId';

  static String get connectionConfigsUrl =>
      '${ApiConfig.baseUrl}$_connectionPrefix/configs';

  static String get checkConnectionUrl =>
      '${ApiConfig.baseUrl}$_connectionPrefix/check';

  static String get createConnectionUrl =>
      '${ApiConfig.baseUrl}$_connectionPrefix/create';

  static String updateConnectionUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/update/$connectionId';

  static String deleteConnectionUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_connectionPrefix/delete/$connectionId';

  // --- Messages ---

  static String getByUserUrl(int userId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/user/$userId';

  static String getByServiceUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/service/$connectionId';

  static String getByFolderUrl(int connectionId, String folder) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/folder/$connectionId/${Uri.encodeComponent(folder)}';

  static String getMailboxesUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/mailboxes/$connectionId';

  static String getMessageUrl(int connectionId, int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/get/message/$connectionId/$messageId';

  static String fetchMailUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/fetch/$connectionId';

  // --- Mark read/unread ---

  static String markReadUrl(int connectionId, int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/mark/read/$connectionId/$messageId';

  static String markUnreadUrl(int connectionId, int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/mark/unread/$connectionId/$messageId';

  static String markFewReadUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/mark/few/read/$connectionId';

  // --- Delete ---

  static String deleteMessageUrl(int connectionId, int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/delete/$connectionId/$messageId';

  static String deleteFewUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/delete/few/$connectionId';

  // --- Move ---

  static String moveMessageUrl(int connectionId, int messageId, String folder) =>
      '${ApiConfig.baseUrl}$_mailPrefix/move/$connectionId/$messageId/${Uri.encodeComponent(folder)}';

  // --- Attachments ---

  static String attachmentUrl(int connectionId, int attachmentId, String filename) {
    final encoded = Uri.encodeComponent(filename);
    return '${ApiConfig.baseUrl}$_mailPrefix/attachments/$connectionId/$attachmentId/$encoded';
  }

  // --- SMTP ---

  static String get smtpSendableUrl =>
      '${ApiConfig.baseUrl}$_mailPrefix/smtp/get/sendable';

  static String smtpSetDefaultUrl(int connectionId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/smtp/set/$connectionId';

  static String get smtpSendUrl => '${ApiConfig.baseUrl}$_mailPrefix/smtp/send';

  static String smtpReplyUrl(int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/smtp/reply/$messageId';

  static String smtpForwardUrl(int messageId) =>
      '${ApiConfig.baseUrl}$_mailPrefix/smtp/forward/$messageId';

  static String get smtpAttachmentUrl =>
      '${ApiConfig.baseUrl}$_mailPrefix/smtp/attachment';
}
