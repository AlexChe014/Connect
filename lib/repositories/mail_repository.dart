import 'dart:typed_data';

import '../models/mail/mail_payload_utils.dart';
import 'package:connect/config/routes/mail_routes.dart';
import 'package:connect/models/mail/mail_connection.dart';
import 'package:connect/models/mail/mail_folder.dart';
import 'package:connect/models/mail/mail_message.dart';
import 'package:connect/services/api_client.dart';
import 'package:http/http.dart' as http;

class CreateMailConnectionRequest {
  final String service;
  final String email;
  final String username;
  final String password;
  final String? name;
  final String? customImapHost;
  final int? customImapPort;
  final String? customImapEncryption;

  const CreateMailConnectionRequest({
    required this.service,
    required this.email,
    required this.username,
    required this.password,
    this.name,
    this.customImapHost,
    this.customImapPort,
    this.customImapEncryption,
  });

  List<MapEntry<String, String>> toFormFields() {
    final fields = <MapEntry<String, String>>[
      MapEntry('service', service),
      MapEntry('email', email),
      MapEntry('username', username),
      MapEntry('password', password),
    ];
    final n = name?.trim();
    if (n != null && n.isNotEmpty) fields.add(MapEntry('name', n));
    final host = customImapHost?.trim();
    if (host != null && host.isNotEmpty) {
      fields.add(MapEntry('custom_imap_host', host));
    }
    if (customImapPort != null) {
      fields.add(MapEntry('custom_imap_port', customImapPort.toString()));
    }
    final enc = customImapEncryption?.trim();
    if (enc != null && enc.isNotEmpty) {
      fields.add(MapEntry('custom_imap_encryption', enc));
    }
    return fields;
  }
}

class SendMailRequest {
  final int connectionId;
  final String to;
  final String subject;
  final String? body;
  final List<http.MultipartFile> attachments;

  const SendMailRequest({
    required this.connectionId,
    required this.to,
    required this.subject,
    this.body,
    this.attachments = const [],
  });
}

class MailRepository {
  MailRepository._();
  static final MailRepository instance = MailRepository._();

  Future<List<MailConnection>> getConnectionsByUser(int userId) async {
    final decoded = await ApiClient.instance.get(MailRoutes.connectionsByUserUrl(userId));
    final items = _unwrapMailList(decoded, 'Не удалось получить почтовые подключения');
    return items.map(MailConnection.fromJson).where((c) => c.id > 0).toList();
  }

  Future<MailConnection> getConnection(int connectionId) async {
    final decoded = await ApiClient.instance.get(MailRoutes.connectionByIdUrl(connectionId));
    final data = _unwrapMailDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить подключение',
    );
    return MailConnection.fromJson(data);
  }

  Future<MailConnection> createConnection(CreateMailConnectionRequest request) async {
    final decoded = await ApiClient.instance.postForm(
      MailRoutes.createConnectionUrl,
      fields: request.toFormFields(),
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

  Future<void> updateConnectionPassword({
    required int connectionId,
    required String password,
  }) async {
    await ApiClient.instance.postForm(
      MailRoutes.updateConnectionUrl(connectionId),
      fields: [MapEntry('password', password)],
    );
  }

  Future<List<MailFolder>> getMailboxes(int connectionId) async {
    final decoded = await ApiClient.instance.get(MailRoutes.getMailboxesUrl(connectionId));
    return _parseFolderList(decoded, 'Не удалось получить папки');
  }

  Future<List<MailMessage>> getMessagesByUser(int userId) async {
    final decoded = await ApiClient.instance.get(MailRoutes.getByUserUrl(userId));
    return _parseMessageList(decoded, 'Не удалось получить письма');
  }

  Future<List<MailMessage>> getMessagesByService(int connectionId) async {
    final decoded = await ApiClient.instance.get(MailRoutes.getByServiceUrl(connectionId));
    return _parseMessageList(decoded, 'Не удалось получить письма');
  }

  Future<List<MailMessage>> getMessagesByFolder({
    required int connectionId,
    required int folderId,
  }) async {
    final decoded = await ApiClient.instance.get(
      MailRoutes.getByFolderUrl(connectionId, folderId),
    );
    return _parseMessageList(decoded, 'Не удалось получить письма');
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

  Future<void> moveMessage({
    required int connectionId,
    required int messageId,
    required int folderId,
  }) async {
    await ApiClient.instance.get(
      MailRoutes.moveMessageUrl(connectionId, messageId, folderId),
    );
  }

  Future<void> deleteMessage({
    required int connectionId,
    required int messageId,
  }) async {
    await ApiClient.instance.get(
      MailRoutes.deleteMessageUrl(connectionId, messageId),
    );
  }

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
      fields: {'filename': filename},
      files: [file],
    );
  }

  Future<void> sendMail(SendMailRequest request) async {
    final fields = <String, String>{
      'service': request.connectionId.toString(),
      'connection_id': request.connectionId.toString(),
      'to': request.to,
      'subject': request.subject,
    };
    final body = request.body?.trim();
    if (body != null && body.isNotEmpty) {
      fields['body'] = body;
      fields['message'] = body;
    }
    await ApiClient.instance.postMultipart(
      MailRoutes.smtpSendUrl,
      fields: fields,
      files: request.attachments,
    );
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
    if (success == false || success == 0 || success == '0' || success == 'false') {
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
      return data
          .map(_asJsonMap)
          .whereType<Map<String, dynamic>>()
          .toList();
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

    throw ApiException(200, 'Некорректный формат data (ожидался объект или список)');
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
    final raw = map['id'] ?? map['uid'] ?? map['message_id'] ?? map['msg_id'] ?? map['msgno'];
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
