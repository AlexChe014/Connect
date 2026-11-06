import 'package:connect/services/api_client.dart';
import 'package:connect/services/api_envelope.dart';

class DocumentBulkFailure {
  const DocumentBulkFailure({required this.guid, this.error});

  final String guid;
  final String? error;
}

/// Итог `POST accept/documents/{service}`: бэкенд проводит документы по одному
/// и не останавливается на ошибке, поэтому часть может пройти, а часть нет.
class DocumentBulkResult {
  const DocumentBulkResult({required this.succeeded, required this.failed});

  final List<String> succeeded;
  final List<DocumentBulkFailure> failed;

  int get total => succeeded.length + failed.length;
  bool get allSucceeded => failed.isEmpty;

  /// Ответы бэкенда:
  /// - часть прошла: `{success: true, data: [{guid, success, error?}]}`;
  /// - ни один не прошёл: `{success: false, data: {error, error_data: [...]}}`;
  /// - общая ошибка (нет прав, нет guid'ов): `{success: false, data: {error}}`
  ///   — без результата по документам, бросается [ApiException];
  /// - прежняя версия бэкенда: `{success: true, data: [ответы 1С]}` — ошибка
  ///   там приходила как `success: false`, значит все документы прошли.
  factory DocumentBulkResult.fromResponse(
    Map<String, dynamic> decoded, {
    required List<String> requestedGuids,
  }) {
    final isSuccess = ApiEnvelope.isSuccess(decoded['success']);
    final data = decoded['data'];
    final rawItems = isSuccess
        ? data
        : (data is Map ? data['error_data'] : null);
    final itemsByGuid = _itemsByGuid(rawItems);

    if (itemsByGuid.isEmpty) {
      if (!isSuccess) {
        ApiEnvelope.unwrapData(
          decoded,
          defaultErrorMessage: 'Не удалось согласовать документы',
        );
        throw ApiException(200, 'Не удалось согласовать документы');
      }
      return DocumentBulkResult(
        succeeded: List.of(requestedGuids),
        failed: const [],
      );
    }

    final succeeded = <String>[];
    final failed = <DocumentBulkFailure>[];
    for (final guid in requestedGuids) {
      final item = itemsByGuid[guid.trim()];
      if (item != null && ApiEnvelope.isSuccess(item['success'])) {
        succeeded.add(guid);
      } else {
        // Документа нет в ответе — считать его подписанным нельзя.
        final error = item?['error']?.toString().trim();
        failed.add(
          DocumentBulkFailure(
            guid: guid,
            error: error == null || error.isEmpty ? null : error,
          ),
        );
      }
    }
    return DocumentBulkResult(succeeded: succeeded, failed: failed);
  }

  /// Текст для диалога: «№ 123: причина» построчно, длинный список обрезается.
  String describeFailures(Map<String, String> labelsByGuid, {int limit = 5}) {
    final lines = <String>[
      for (final failure in failed.take(limit))
        '${labelsByGuid[failure.guid] ?? 'Документ'}: '
            '${failure.error ?? 'нет ответа сервера'}',
    ];
    final rest = failed.length - limit;
    if (rest > 0) lines.add('и ещё $rest');
    return lines.join('\n');
  }

  static Map<String, Map> _itemsByGuid(Object? raw) {
    if (raw is! List) return const {};
    return {
      for (final item in raw)
        if (item is Map && item['guid'] != null && item.containsKey('success'))
          item['guid'].toString().trim(): item,
    };
  }
}
