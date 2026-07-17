import '../api_config.dart';

class ChatRoutes {
  ChatRoutes._();

  static const String _prefix = '/chat';

  static String get listUrl => '${ApiConfig.baseUrl}$_prefix';

  static String chatUrl(int chatId) => '${ApiConfig.baseUrl}$_prefix/$chatId';

  static String messagesUrl(int chatId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/messages';

  static String membersUrl(int chatId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/members';

  static String memberUrl(int chatId, int userId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/members/$userId';

  static String messageUrl(int chatId, int messageId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/messages/$messageId';

  static String memberDeleteUrl(int chatId, int userId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/members/$userId/delete';

  static String messageDeleteUrl(int chatId, int messageId) =>
      '${ApiConfig.baseUrl}$_prefix/$chatId/messages/$messageId/delete';
}
