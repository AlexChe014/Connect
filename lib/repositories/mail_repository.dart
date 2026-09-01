import 'dart:typed_data';

import '../models/mail/mail_payload_utils.dart';
import 'package:connect/config/routes/mail_routes.dart';
import 'package:connect/models/mail/mail_connection.dart';
import 'package:connect/models/mail/mail_folder.dart';
import 'package:connect/models/mail/mail_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:http/http.dart' as http;

class MailMessagePage {
  const MailMessagePage({
    required this.messages,
    required this.hasMore,
    required this.nextPage,
  });

  final List<MailMessage> messages;
  final bool hasMore;
  final int nextPage;
}

class CreateMailConnectionRequest {
  final String service;
  final String email;
  final String password;
  final String? username;
  final String? customImapHost;
  final int? customImapPort;
  final String? customImapEncryption;
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpEncryption;
  final bool? canSend;

  const CreateMailConnectionRequest({
    required this.service,
    required this.email,
    required this.password,
    this.username,
    this.customImapHost,
    this.customImapPort,
    this.customImapEncryption,
    this.smtpHost,
    this.smtpPort,
    this.smtpEncryption,
    this.canSend,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'service': service,
      'email': email,
      'password': password,
    };
    if (username != null) map['username'] = username;
    if (customImapHost != null) map['custom_imap_host'] = customImapHost;
    if (customImapPort != null) map['custom_imap_port'] = customImapPort;
    if (customImapEncryption != null) {
      map['custom_imap_encryption'] = customImapEncryption;
    }
    if (smtpHost != null) map['smtp_host'] = smtpHost;
    if (smtpPort != null) map['smtp_port'] = smtpPort;
    if (smtpEncryption != null) map['smtp_encryption'] = smtpEncryption;
    if (canSend != null) map['can_send'] = canSend;
    return map;
  }
}

class UpdateMailConnectionRequest {
  final String? service;
  final String? email;
  final String? password;
  final String? username;
  final String? customImapHost;
  final int? customImapPort;
  final String? customImapEncryption;
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpEncryption;
  final bool? canSend;

  const UpdateMailConnectionRequest({
    this.service,
    this.email,
    this.password,
    this.username,
    this.customImapHost,
    this.customImapPort,
    this.customImapEncryption,
    this.smtpHost,
    this.smtpPort,
    this.smtpEncryption,
    this.canSend,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (service != null) map['service'] = service;
    if (email != null) map['email'] = email;
    if (password != null) map['password'] = password;
    if (username != null) map['username'] = username;
    if (customImapHost != null) map['custom_imap_host'] = customImapHost;
    if (customImapPort != null) map['custom_imap_port'] = customImapPort;
    if (customImapEncryption != null) {
      map['custom_imap_encryption'] = customImapEncryption;
    }
    if (smtpHost != null) map['smtp_host'] = smtpHost;
    if (smtpPort != null) map['smtp_port'] = smtpPort;
    if (smtpEncryption != null) map['smtp_encryption'] = smtpEncryption;
    if (canSend != null) map['can_send'] = canSend;
    return map;
  }
}

class SendMailRequest {
  final String to;
  final String subject;
  final String? body;
  final List<http.MultipartFile> attachments;

  const SendMailRequest({
    required this.to,
    required this.subject,
    this.body,
    this.attachments = const [],
  });
}

class ReplyMailRequest {
  final int messageId;
  final String to;
  final String subject;
  final String? body;

  const ReplyMailRequest({
    required this.messageId,
    required this.to,
    required this.subject,
    this.body,
  });
}

class ForwardMailRequest {
  final int messageId;
  final String to;
  final String subject;
  final String? body;

  const ForwardMailRequest({
    required this.messageId,
    required this.to,
    required this.subject,
    this.body,
  });
}

class MailRepository {
  MailRepository._();
  static final MailRepository instance = MailRepository._();

  // --- Connections ---

  Future<List<MailConnection>> getConnectionsByUser(int userId) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.connectionsByUserUrl(userId),
    );
    final items = _unwrapMailList(
      decoded,
      'Не удалось получить почтовые подключения',
    );
    return items.map(MailConnection.fromJson).where((c) => c.id > 0).toList();
  }

  Future<MailConnection> getConnection(int connectionId) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.connectionByIdUrl(connectionId),
    );
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить подключение',
    );
    return MailConnection.fromJson(data);
  }

  Future<List<MailConnection>> getConnectionConfigs() async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.connectionConfigsUrl,
    );
    final items = _unwrapMailList(
      decoded,
      'Не удалось получить конфиги подключений',
    );
    return items.map(MailConnection.fromJson).where((c) => c.id > 0).toList();
  }

  Future<bool> checkConnection(CreateMailConnectionRequest request) async {
    final decoded = await ApiClient.instance.post(
      MailRoutes.checkConnectionUrl,
      body: request.toJson(),
    );
    final data = _unwrapMailData(decoded, 'Не удалось проверить подключение');
    if (data is bool) return data;
    return decoded['success'] == true || decoded['success'] == 1;
  }

  Future<MailConnection> createConnection(
    CreateMailConnectionRequest request,
  ) async {
    final decoded = await ApiClient.instance.post(
      MailRoutes.createConnectionUrl,
      body: request.toJson(),
    );
    final data = _unwrapMailData(decoded, 'Не удалось создать подключение');
    if (data is Map<String, dynamic>) {
      return MailConnection.fromJson(data);
    }
    if (data is Map) {
      return MailConnection.fromJson(data.cast<String, dynamic>());
    }
    throw ApiException(200, 'Некорректный ответ при создании подключения');
  }

  Future<MailConnection> updateConnection({
    required int connectionId,
    required UpdateMailConnectionRequest request,
  }) async {
    final decoded = await ApiClient.instance.post(
      MailRoutes.updateConnectionUrl(connectionId),
      body: request.toJson(),
    );
    final data = _unwrapMailData(decoded, 'Не удалось обновить подключение');
    if (data is Map<String, dynamic>) {
      return MailConnection.fromJson(data);
    }
    if (data is Map) {
      return MailConnection.fromJson(data.cast<String, dynamic>());
    }
    throw ApiException(200, 'Некорректный ответ при обновлении подключения');
  }

  Future<void> deleteConnection(int connectionId) async {
    await ApiClient.instance.get(MailRoutes.deleteConnectionUrl(connectionId));
  }

  // --- Mailboxes (folders) ---

  Future<List<MailFolder>> getMailboxes(int connectionId) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.getMailboxesUrl(connectionId),
    );
    return _parseMailboxList(decoded, 'Не удалось получить папки');
  }

  // --- Messages ---

  Future<List<MailMessage>> getMessagesByUser(int userId) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.getByUserUrl(userId),
    );
    return _parseMessageList(decoded, 'Не удалось получить письма');
  }

  Future<MailMessagePage> getMessagesByService(
    int connectionId, {
    int page = 1,
  }) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.getByServiceUrl(connectionId),
      queryParameters: {'page': '$page'},
    );
    return _parseMessagePage(decoded, 'Не удалось получить письма');
  }

  Future<MailMessagePage> getMessagesByFolder({
    required int connectionId,
    required int folderId,
    int page = 1,
  }) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.getByFolderUrl(connectionId, folderId),
      queryParameters: {'page': '$page'},
    );
    return _parseMessagePage(decoded, 'Не удалось получить письма');
  }

  Future<MailMessage> getMessage({
    required int connectionId,
    required int messageId,
  }) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.getMessageUrl(connectionId, messageId),
    );
    final data = _unwrapMailMessagePayload(
      decoded,
      messageId: messageId,
      defaultErrorMessage: 'Не удалось получить письмо',
    );
    if (MailPayloadUtils.isConnection(data)) {
      throw ApiException(
        200,
        'Сервер вернул почтовое подключение вместо письма',
      );
    }
    return MailMessage.fromJson(data);
  }

  Future<List<MailMessage>> fetchMessages(int connectionId) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.fetchMailUrl(connectionId),
    );
    return _parseMessageList(decoded, 'Не удалось получить письма с сервера');
  }

  // --- Mark read/unread ---

  Future<MailMessage> markRead({
    required int connectionId,
    required int messageId,
  }) async {
    final decoded = await ApiClient.instance.post(
      MailRoutes.markReadUrl(connectionId, messageId),
      body: {'is_read': true},
    );
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось отметить письмо прочитанным',
    );
    return MailMessage.fromJson(data);
  }

  Future<MailMessage> markUnread({
    required int connectionId,
    required int messageId,
  }) async {
    final decoded = await ApiClient.instance.post(
      MailRoutes.markUnreadUrl(connectionId, messageId),
      body: {'is_read': false},
    );
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось отметить письмо непрочитанным',
    );
    return MailMessage.fromJson(data);
  }

  Future<void> markFewRead({
    required int connectionId,
    required List<int> ids,
  }) async {
    await ApiClient.instance.post(
      MailRoutes.markFewReadUrl(connectionId),
      body: {'ids': ids},
    );
  }

  // --- Delete ---

  Future<void> deleteMessage({
    required int connectionId,
    required int messageId,
  }) async {
    await ApiClient.instance.get(
      MailRoutes.deleteMessageUrl(connectionId, messageId),
    );
  }

  Future<void> deleteFewMessages({required int connectionId}) async {
    await ApiClient.instance.get(MailRoutes.deleteFewUrl(connectionId));
  }

  // --- Move ---

  Future<void> moveMessage({
    required int connectionId,
    required int messageId,
    required int folderId,
  }) async {
    await ApiClient.instance.get(
      MailRoutes.moveMessageUrl(connectionId, messageId, folderId),
    );
  }

  // --- Attachments ---

  Future<Uint8List> downloadAttachment({
    required int connectionId,
    required int attachmentId,
    required String filename,
  }) async {
    final bytes = await ApiClient.instance.downloadBytes(
      MailRoutes.attachmentUrl(connectionId, attachmentId, filename),
    );
    return Uint8List.fromList(bytes);
  }

  Future<Map<String, dynamic>> uploadSmtpAttachment({
    required List<int> bytes,
    required String filename,
  }) async {
    final file = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    );
    return ApiClient.instance.postMultipart(
      MailRoutes.smtpAttachmentUrl,
      fields: {},
      files: [file],
    );
  }

  // --- SMTP ---

  Future<List<MailConnection>> getSendableConnections() async {
    final decoded = await ApiClient.instance.get(MailRoutes.smtpSendableUrl);
    final items = _unwrapMailList(
      decoded,
      'Не удалось получить ящики для отправки',
    );
    return items.map(MailConnection.fromJson).where((c) => c.id > 0).toList();
  }

  Future<MailConnection> setDefaultConnection(int connectionId) async {
    final decoded = await ApiClient.instance.post(
      MailRoutes.smtpSetDefaultUrl(connectionId),
      body: {'is_default': true},
    );
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось установить ящик по умолчанию',
    );
    return MailConnection.fromJson(data);
  }

  Future<void> sendMail(SendMailRequest request) async {
    final fields = <String, String>{
      'to': request.to,
      'subject': request.subject,
    };
    final body = request.body?.trim();
    if (body != null && body.isNotEmpty) {
      fields['body_text'] = body;
    }
    final decoded = await ApiClient.instance.postMultipart(
      MailRoutes.smtpSendUrl,
      fields: fields,
      files: request.attachments,
    );
    // Live API returns {success: true, data: true} on success (not an Email
    // object, despite api-docs.json), so only the success flag can be checked.
    _unwrapMailData(decoded, 'Не удалось отправить письмо');
  }

  Future<MailMessage> replyMail(ReplyMailRequest request) async {
    final body = <String, dynamic>{
      'to': request.to,
      'subject': request.subject,
    };
    if (request.body != null && request.body!.trim().isNotEmpty) {
      body['body'] = request.body;
    }
    final decoded = await ApiClient.instance.post(
      MailRoutes.smtpReplyUrl(request.messageId),
      body: body,
    );
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось ответить на письмо',
    );
    return MailMessage.fromJson(data);
  }

  Future<MailMessage> forwardMail(ForwardMailRequest request) async {
    final body = <String, dynamic>{
      'to': request.to,
      'subject': request.subject,
    };
    if (request.body != null && request.body!.trim().isNotEmpty) {
      body['body'] = request.body;
    }
    final decoded = await ApiClient.instance.post(
      MailRoutes.smtpForwardUrl(request.messageId),
      body: body,
    );
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось переслать письмо',
    );
    return MailMessage.fromJson(data);
  }

  // --- Internal helpers ---

  List<MailFolder> _parseMailboxList(
    Map<String, dynamic> decoded,
    String errorMessage,
  ) {
    final data = _unwrapMailData(decoded, errorMessage);
    // Live API: array of EmailFolder objects (id, original_name, custom_name, children).
    // Spec/docs may still describe plain strings — support both.
    if (data is List) {
      final folders = <MailFolder>[];
      for (final item in data) {
        _collectMailFolders(item, folders);
      }
      return folders.where((f) => f.id > 0 || f.name.isNotEmpty).toList();
    }
    return _parseFolderList(decoded, errorMessage);
  }

  void _collectMailFolders(Object? item, List<MailFolder> out) {
    if (item is String) {
      final name = item.trim();
      if (name.isNotEmpty) out.add(MailFolder(id: 0, name: name));
      return;
    }
    final map = _asJsonMap(item);
    if (map == null) return;
    final folder = MailFolder.fromJson(map);
    if (folder.id > 0 || folder.name.isNotEmpty) {
      out.add(folder);
    }
    final children = map['children'];
    if (children is List) {
      for (final child in children) {
        _collectMailFolders(child, out);
      }
    }
  }

  List<MailFolder> _parseFolderList(
    Map<String, dynamic> decoded,
    String errorMessage,
  ) {
    final data = _unwrapMailData(decoded, errorMessage);
    return _mapJsonList(data, MailFolder.fromJson);
  }

  List<MailMessage> _parseMessageList(
    Map<String, dynamic> decoded,
    String errorMessage,
  ) {
    final items = _unwrapMailList(decoded, errorMessage);
    return items
        .where((item) => MailPayloadUtils.isMessage(item))
        .map(MailMessage.fromJson)
        .where((m) => m.id > 0 || m.subject != '(без темы)')
        .toList();
  }

  MailMessagePage _parseMessagePage(
    Map<String, dynamic> decoded,
    String errorMessage,
  ) {
    final messages = _parseMessageList(decoded, errorMessage);
    final data = _unwrapMailData(decoded, errorMessage);
    if (data is Map) {
      final currentPage = _parseIntValue(data['current_page']);
      final lastPage = _parseIntValue(data['last_page']);
      if (currentPage != null && lastPage != null) {
        return MailMessagePage(
          messages: messages,
          hasMore: currentPage < lastPage,
          nextPage: currentPage + 1,
        );
      }
      final nextPageUrl = data['next_page_url'];
      if (nextPageUrl != null) {
        return MailMessagePage(
          messages: messages,
          hasMore: true,
          nextPage: (_parseIntValue(data['current_page']) ?? 1) + 1,
        );
      }
    }
    return MailMessagePage(messages: messages, hasMore: false, nextPage: 1);
  }

  int? _parseIntValue(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  Object? _unwrapMailData(Map<String, dynamic> decoded, String errorMessage) {
    final success = decoded['success'];
    if (success == true ||
        success == 1 ||
        success == '1' ||
        success == 'true' ||
        success == 'success') {
      return decoded['data'];
    }
    if (decoded.containsKey('data') && success == null) {
      return decoded['data'];
    }
    if (success == false ||
        success == 0 ||
        success == '0' ||
        success == 'false') {
      final message =
          decoded['message'] as String? ??
          decoded['error'] as String? ??
          errorMessage;
      throw ApiException(200, message);
    }
    return decoded['data'] ?? decoded;
  }

  List<Map<String, dynamic>> _unwrapMailList(
    Map<String, dynamic> decoded,
    String errorMessage,
  ) {
    final data = _unwrapMailData(decoded, errorMessage);
    if (data is List) {
      return data.map(_asJsonMap).whereType<Map<String, dynamic>>().toList();
    }
    return _extractJsonMaps(data);
  }

  Map<String, dynamic>? _asJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic> _unwrapMailDataMap(
    Map<String, dynamic> decoded, {
    required String defaultErrorMessage,
  }) {
    final data = _unwrapMailData(decoded, defaultErrorMessage);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    throw ApiException(200, 'Некорректный формат data (ожидался объект)');
  }

  Map<String, dynamic> _unwrapMessageMap(Map<String, dynamic> data) {
    for (final key in ['message', 'mail', 'email', 'item']) {
      final nested = data[key];
      if (nested is Map) {
        return Map<String, dynamic>.from(nested);
      }
    }
    return data;
  }

  Map<String, dynamic> _unwrapMailMessagePayload(
    Map<String, dynamic> decoded, {
    required int messageId,
    required String defaultErrorMessage,
  }) {
    final data = _unwrapMailData(decoded, defaultErrorMessage);

    if (data is List) {
      return _pickMessageFromList(data, messageId);
    }

    if (data is Map) {
      final map = _unwrapMessageMap(Map<String, dynamic>.from(data));
      for (final key in ['messages', 'items', 'data']) {
        final nested = map[key];
        if (nested is List) {
          return _pickMessageFromList(nested, messageId);
        }
      }
      return map;
    }

    throw ApiException(
      200,
      'Некорректный формат data (ожидался объект или список)',
    );
  }

  Map<String, dynamic> _pickMessageFromList(List data, int messageId) {
    final items = data
        .map(_asJsonMap)
        .whereType<Map<String, dynamic>>()
        .where(MailPayloadUtils.isMessage)
        .toList();
    if (items.isEmpty) {
      throw ApiException(200, 'Письмо не найдено');
    }

    for (final item in items) {
      if (_messageIdFromMap(item) == messageId) return item;
    }

    if (items.length == 1) return items.first;
    throw ApiException(200, 'Письмо не найдено');
  }

  int? _messageIdFromMap(Map<String, dynamic> map) {
    final raw =
        map['id'] ??
        map['uid'] ??
        map['message_id'] ??
        map['msg_id'] ??
        map['msgno'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  List<T> _mapJsonList<T>(
    Object? data,
    T Function(Map<String, dynamic>) mapItem, {
    bool isConnection = false,
  }) {
    final rawItems = _extractJsonMaps(data);
    return rawItems
        .map(mapItem)
        .where((item) => _isValidMailItem(item, isConnection: isConnection))
        .toList();
  }

  bool _isValidMailItem<T>(T item, {bool isConnection = false}) {
    if (item is MailConnection) {
      return item.id > 0 || (isConnection && item.email.isNotEmpty);
    }
    if (item is MailFolder) return item.id > 0 || item.name.isNotEmpty;
    if (item is MailMessage) return item.id > 0 || item.subject.isNotEmpty;
    return true;
  }

  List<Map<String, dynamic>> _extractJsonMaps(Object? data) {
    if (data == null) return const [];

    if (data is List) {
      return data.map(_asJsonMap).whereType<Map<String, dynamic>>().toList();
    }

    if (data is Map<String, dynamic>) {
      final paginated = data['data'];
      if (paginated is List) {
        return paginated
            .map(_asJsonMap)
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      for (final key in [
        'items',
        'messages',
        'folders',
        'mailboxes',
        'connections',
        'services',
        'mail_connections',
        'list',
        'result',
      ]) {
        final nested = data[key];
        if (nested is List) {
          return nested
              .map(_asJsonMap)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }

      final fromEntries = <Map<String, dynamic>>[];
      for (final entry in data.entries) {
        if (entry.value is Map) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          final parsedId = int.tryParse(entry.key);
          if (parsedId != null && item['id'] == null) {
            item['id'] = parsedId;
          }
          fromEntries.add(item);
        }
      }
      if (fromEntries.isNotEmpty) return fromEntries;

      if (data.isNotEmpty && data.containsKey('id')) {
        return [data];
      }
    }

    return const [];
  }
}
