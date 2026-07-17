import 'package:connect/config/routes/documents_routes.dart';
import 'package:connect/models/documents/document_service.dart';
import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class DocumentsRepository {
  DocumentsRepository._();
  static final DocumentsRepository instance = DocumentsRepository._();

  Future<List<DocumentService>> getActiveServices() async {
    final decoded = await ApiClient.instance.get(DocumentsRoutes.activeServicesUrl);
    return _parseServiceList(
      decoded,
      defaultErrorMessage: 'Не удалось получить список сервисов 1С',
    );
  }

  Future<List<DocumentService>> getAllServices() async {
    final decoded = await ApiClient.instance.get(DocumentsRoutes.allServicesUrl);
    return _parseServiceList(
      decoded,
      defaultErrorMessage: 'Не удалось получить полный список сервисов 1С',
    );
  }

  Future<DocumentService> getService(int serviceId) async {
    final decoded = await ApiClient.instance.get(
      DocumentsRoutes.serviceByIdUrl(serviceId),
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить сервис 1С',
    );
    return DocumentService.fromJson(data);
  }

  Future<List<DocumentService>> authenticate(String code) async {
    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.authUrl,
      fields: [MapEntry('code', code.trim())],
    );
    return _parseServiceList(
      decoded,
      defaultErrorMessage: 'Не удалось авторизоваться в сервисах 1С',
    );
  }

  Future<Map<String, dynamic>> authenticateService({
    required int serviceId,
    required String code,
  }) async {
    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.authServiceUrl(serviceId),
      fields: [MapEntry('code', code.trim())],
    );
    return ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось авторизоваться в сервисе 1С',
    );
  }

  Future<int> logout() async {
    final decoded = await ApiClient.instance.get(DocumentsRoutes.logoutUrl);
    return ApiEnvelope.unwrapDataInt(
      decoded,
      defaultErrorMessage: 'Не удалось выйти из сервисов 1С',
    );
  }

  Future<int> logoutService(int serviceId) async {
    final decoded = await ApiClient.instance.get(
      DocumentsRoutes.logoutServiceUrl(serviceId),
    );
    return ApiEnvelope.unwrapDataInt(
      decoded,
      defaultErrorMessage: 'Не удалось выйти из сервиса 1С',
    );
  }

  Future<String> sendVerificationCode({bool regenerate = false}) async {
    final fields = <MapEntry<String, String>>[];
    if (regenerate) {
      fields.add(const MapEntry('regenerate', '1'));
    }
    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.sendCodeUrl,
      fields: fields,
    );
    return ApiEnvelope.unwrapDataString(
      decoded,
      defaultErrorMessage: 'Не удалось отправить код подтверждения',
    );
  }

  Future<bool> verifyCode(String code) async {
    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.verifyCodeUrl,
      fields: [MapEntry('code', code.trim())],
    );
    return ApiEnvelope.unwrapDataBool(
      decoded,
      defaultErrorMessage: 'Не удалось проверить код подтверждения',
    );
  }

  Future<List<Map<String, dynamic>>> getAllDocuments(int serviceId) async {
    final decoded = await ApiClient.instance.get(
      DocumentsRoutes.allDocumentsUrl(serviceId),
    );

    final success = decoded['success'];
    if (!ApiEnvelope.isSuccess(success)) {
      final data = decoded['data'];
      final error = data is Map
          ? (data['error']?.toString() ?? data['message']?.toString() ?? '')
          : (decoded['error']?.toString() ?? decoded['message']?.toString() ?? '');
      final normalized = error.trim().toLowerCase();
      if (normalized.contains('нет информации') ||
          normalized.contains('нет документов') ||
          normalized.contains('empty')) {
        return const [];
      }
      throw ApiException(
        200,
        error.trim().isEmpty ? 'Не удалось получить список документов' : error.trim(),
      );
    }

    return _parseJsonObjectList(decoded['data']);
  }

  Future<Map<String, dynamic>> getDocument({
    required int serviceId,
    required String guid,
  }) async {
    final decoded = await ApiClient.instance.get(
      DocumentsRoutes.documentUrl(serviceId),
      queryParameters: {'guid': guid.trim()},
    );
    return _parseJsonObject(
      ApiEnvelope.unwrapData(
        decoded,
        defaultErrorMessage: 'Не удалось получить документ',
      ),
    );
  }

  Future<Map<String, dynamic>> getDocumentFile({
    required int serviceId,
    required String guid,
  }) async {
    final decoded = await ApiClient.instance.get(
      DocumentsRoutes.fileUrl(serviceId),
      queryParameters: {'guid': guid.trim()},
    );
    return _parseJsonObject(
      ApiEnvelope.unwrapData(
        decoded,
        defaultErrorMessage: 'Не удалось получить файл документа',
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getAcceptors({
    required int serviceId,
    required String guid,
  }) async {
    final decoded = await ApiClient.instance.get(
      DocumentsRoutes.acceptorsUrl(serviceId),
      queryParameters: {'guid': guid.trim()},
    );
    return _parseJsonObjectList(
      ApiEnvelope.unwrapData(
        decoded,
        defaultErrorMessage: 'Не удалось получить список согласующих',
      ),
    );
  }

  Future<Map<String, dynamic>> acceptDocument({
    required int serviceId,
    required String guid,
    String? comment,
    String? number,
  }) async {
    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.acceptDocumentUrl(serviceId),
      fields: _documentActionFields(
        guid: guid,
        comment: comment,
        number: number,
        guidRequired: true,
      ),
    );
    return _parseOneCResponse(
      decoded,
      defaultErrorMessage: 'Не удалось согласовать документ',
    );
  }

  Future<Map<String, dynamic>> rejectDocument({
    required int serviceId,
    String? guid,
    String? comment,
    String? number,
  }) async {
    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.rejectDocumentUrl(serviceId),
      fields: _documentActionFields(
        guid: guid,
        comment: comment,
        number: number,
      ),
    );
    return _parseOneCResponse(
      decoded,
      defaultErrorMessage: 'Не удалось отклонить документ',
    );
  }

  Future<List<Map<String, dynamic>>> acceptDocuments({
    required int serviceId,
    required List<String> guids,
    String? comment,
    List<String>? numbers,
  }) async {
    if (guids.isEmpty) {
      throw ApiException(400, 'Не указаны документы для согласования');
    }

    final fields = <MapEntry<String, String>>[
      for (final guid in guids) MapEntry('guids[]', guid.trim()),
    ];
    final c = comment?.trim();
    if (c != null && c.isNotEmpty) {
      fields.add(MapEntry('comment', c));
    }
    if (numbers != null) {
      for (final number in numbers) {
        final n = number.trim();
        if (n.isNotEmpty) {
          fields.add(MapEntry('numbers[]', n));
        }
      }
    }

    final decoded = await ApiClient.instance.postForm(
      DocumentsRoutes.acceptDocumentsUrl(serviceId),
      fields: fields,
    );
    return _parseJsonObjectList(
      ApiEnvelope.unwrapData(
        decoded,
        defaultErrorMessage: 'Не удалось согласовать документы',
      ),
    );
  }

  List<DocumentService> _parseServiceList(
    Map<String, dynamic> decoded, {
    required String defaultErrorMessage,
  }) {
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );
    return list
        .whereType<Map>()
        .map((item) => DocumentService.fromJson(item.cast<String, dynamic>()))
        .where((service) => service.id > 0)
        .toList();
  }

  List<MapEntry<String, String>> _documentActionFields({
    String? guid,
    String? comment,
    String? number,
    bool guidRequired = false,
  }) {
    final fields = <MapEntry<String, String>>[];
    final g = guid?.trim();
    if (g != null && g.isNotEmpty) {
      fields.add(MapEntry('guid', g));
    } else if (guidRequired) {
      throw ApiException(400, 'Не указан guid документа');
    }

    final c = comment?.trim();
    if (c != null && c.isNotEmpty) {
      fields.add(MapEntry('comment', c));
    }

    final n = number?.trim();
    if (n != null && n.isNotEmpty) {
      fields.add(MapEntry('number', n));
    }

    return fields;
  }

  Map<String, dynamic> _parseOneCResponse(
    Map<String, dynamic> decoded, {
    required String defaultErrorMessage,
  }) {
    final data = ApiEnvelope.unwrapData(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List) {
      return {'results': _parseJsonObjectList(data)};
    }
    return {'value': data};
  }

  List<Map<String, dynamic>> _parseJsonObjectList(Object? data) {
    if (data == null) return const [];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (data is Map) {
      return [Map<String, dynamic>.from(data)];
    }
    throw ApiException(200, 'Некорректный формат data (ожидался объект или список)');
  }

  Map<String, dynamic> _parseJsonObject(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException(200, 'Некорректный формат data (ожидался объект)');
  }
}
