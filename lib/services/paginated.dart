import '../config/api_config.dart';
import 'api_client.dart';
import 'api_envelope.dart';

/// Пагинированный ответ внутри `data` у конверта `{ success, data }`.
///
/// Поддерживаются оба формата Laravel:
/// - LengthAwarePaginator: `{ data, current_page, next_page_url, last_page, ... }`
/// - API Resource: `{ data, links: { next }, meta: { current_page, last_page } }`
class Paginated<T> {
  final List<T> data;
  final int currentPage;
  final int? lastPage;
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
    this.lastPage,
  });

  bool get hasMore {
    final next = nextPageUrl?.trim();
    if (next != null && next.isNotEmpty) return true;
    if (lastPage != null) return currentPage < lastPage!;
    return false;
  }
}

class ApiPaginatedEnvelope {
  ApiPaginatedEnvelope._();

  static int? parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static Paginated<T> unwrapPaginated<T>(
    Map<String, dynamic> decoded, {
    required T Function(Map<String, dynamic>) mapItem,
    String defaultErrorMessage = 'Ошибка запроса',
  }) {
    final dataMap = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: defaultErrorMessage,
    );

    final meta = _asMap(dataMap['meta']) ?? dataMap;
    final links = _asMap(dataMap['links']);
    final rawList = dataMap['data'];

    if (rawList is! List) {
      throw ApiException(200, 'Некорректный формат data (ожидался список)');
    }

    final items = rawList
        .whereType<Map>()
        .map((e) => mapItem(Map<String, dynamic>.from(e)))
        .toList(growable: false);

    final currentPage =
        parseInt(meta['current_page']) ?? parseInt(dataMap['current_page']) ?? 1;
    final lastPage = parseInt(meta['last_page']) ?? parseInt(dataMap['last_page']);

    var nextPageUrl =
        _asString(dataMap['next_page_url']) ?? _asString(meta['next_page_url']);
    nextPageUrl ??= _asString(links?['next']);

    if (nextPageUrl == null && lastPage != null && currentPage < lastPage) {
      final path = _asString(meta['path']) ?? _asString(dataMap['path']);
      if (path != null) {
        final pathUri = Uri.parse(path);
        nextPageUrl = pathUri.replace(
          queryParameters: {
            ...pathUri.queryParameters,
            'page': '${currentPage + 1}',
          },
        ).toString();
      }
    }

    return Paginated<T>(
      data: items,
      currentPage: currentPage,
      lastPage: lastPage,
      nextPageUrl: ApiConfig.normalizeNextPageUrl(nextPageUrl),
      prevPageUrl: _asString(dataMap['prev_page_url']) ??
          _asString(meta['prev_page_url']) ??
          _asString(links?['prev']),
      path: _asString(meta['path']) ?? _asString(dataMap['path']),
      perPage: parseInt(meta['per_page']) ?? parseInt(dataMap['per_page']),
      to: parseInt(meta['to']) ?? parseInt(dataMap['to']),
      total: parseInt(meta['total']) ?? parseInt(dataMap['total']),
    );
  }
}
