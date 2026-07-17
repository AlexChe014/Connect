import 'api_client.dart';
import 'api_envelope.dart';

/// Пагинированный ответ внутри `data` у конверта `{ success, data }`.
///
/// Ожидаемый формат `data`:
/// `{ data: [], current_page, next_page_url, path, per_page, prev_page_url, to, total }`
class Paginated<T> {
  final List<T> data;
  final int currentPage;
  final String? nextPageUrl;
  final String? prevPageUrl;
  final String? path;
  final int? perPage;
  final int? to;
  final int? total;

  const Paginated({
    required this.data,
    required this.currentPage,
    required this.nextPageUrl,
    required this.prevPageUrl,
    required this.path,
    required this.perPage,
    required this.to,
    required this.total,
  });
}

class ApiPaginatedEnvelope {
  ApiPaginatedEnvelope._();

  static Paginated<T> unwrapPaginated<T>(
    Map<String, dynamic> decoded, {
    required T Function(Map<String, dynamic>) mapItem,
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final dataMap = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );

    final rawList = dataMap['data'];

    if (rawList is! List) {
      throw ApiException(200, 'Некорректный формат data (ожидался список)');
    }

    final items = rawList
        .map((e) => mapItem(e as Map<String, dynamic>))
        .toList(growable: false);

    final currentPage = (dataMap['current_page'] as num?)?.toInt();
    
    if (currentPage == null) {
      throw ApiException(200, 'Некорректный формат current_page (ожидался int)');
    }

    return Paginated<T>(
      data: items,
      currentPage: currentPage,
      nextPageUrl: dataMap['next_page_url'] as String?,
      prevPageUrl: dataMap['prev_page_url'] as String?,
      path: dataMap['path'] as String?,
      perPage: (dataMap['per_page'] as num?)?.toInt(),
      to: (dataMap['to'] as num?)?.toInt(),
      total: (dataMap['total'] as num?)?.toInt(),
    );
  }
}

