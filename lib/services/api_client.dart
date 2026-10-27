import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connect/config/api_config.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/network_errors.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:http/http.dart' as http;

export 'network_errors.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Пользователь сам остановил скачивание — это не ошибка, сообщать о ней
/// не нужно.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'DownloadCancelledException';
}

/// Позволяет оборвать [ApiClient.downloadToFile] на любом этапе: закрывает
/// HTTP-клиент, и ожидание ответа или очередного куска сразу прерывается.
class DownloadCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...authHeaders,
    };
    return headers;
  }

  /// Заголовок авторизации без `Content-Type` — для скачивания файлов
  /// и картинок через [CachedNetworkImage].
  Map<String, String> get authHeaders {
    final token = AuthService.instance.token;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? queryParameters,
  }) async {
    var uri = Uri.parse(url);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {...uri.queryParameters, ...queryParameters},
      );
    }
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'GET',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP GET failed: $uri', e, st);
    }
  }

  /// POST с телом `application/x-www-form-urlencoded` (как form-data в Postman).
  Future<Map<String, dynamic>> postForm(
    String url, {
    required List<MapEntry<String, String>> fields,
  }) async {
    final uri = Uri.parse(url);
    final body = fields
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final headers = Map<String, String>.from(_headers);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    final sessionGeneration = AuthService.instance.sessionGeneration;

    try {
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'POST',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP POST form failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> post(
    String url, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'POST',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP POST failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> patch(
    String url, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .patch(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'PATCH',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP PATCH failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> put(
    String url, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .put(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'PUT',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP PUT failed: $uri', e, st);
    }
  }

  Future<Map<String, dynamic>> delete(String url) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .delete(uri, headers: _headers)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      return _handleResponse(
        response,
        uri: uri,
        method: 'DELETE',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP DELETE failed: $uri', e, st);
    }
  }

  /// POST `multipart/form-data` (как form-data в Postman).
  Future<Map<String, dynamic>> postMultipart(
    String url, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
    Duration? timeout,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final request = onProgress == null
        ? http.MultipartRequest('POST', uri)
        : _ProgressMultipartRequest('POST', uri, onProgress);
    final headers = Map<String, String>.from(_headers);
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.fields.addAll(fields);
    request.files.addAll(files);
    final sessionGeneration = AuthService.instance.sessionGeneration;

    try {
      // Тайм-аут считается до ответа сервера, то есть вместе с отправкой
      // всего тела: крупному файлу нужен свой, иначе он не успеет уйти.
      final streamed = await request.send().timeout(
        timeout ?? Duration(seconds: ApiConfig.timeoutSeconds),
      );
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(
        response,
        uri: uri,
        method: 'POST multipart',
        sessionGeneration: sessionGeneration,
      );
    } catch (e, st) {
      throw _mapAndLog('HTTP POST multipart failed: $uri', e, st);
    }
  }

  Future<List<int>> downloadBytes(String url) async {
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    try {
      final response = await http
          .get(uri, headers: authHeaders)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        AuthService.instance.noteRequestSucceeded(
          sessionGeneration: sessionGeneration,
        );
        final bytes = response.bodyBytes;
        final preview = bytes
            .take(16)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        AppLogger.d(
          'download OK: $uri content-type=${response.headers['content-type']} '
          'content-encoding=${response.headers['content-encoding']} '
          'len=${bytes.length} first-bytes=$preview',
          name: 'network.http.download',
        );
        _throwIfJsonError(response);
        return bytes;
      }
      _noteResponseAuthOutcome(
        statusCode: response.statusCode,
        sessionGeneration: sessionGeneration,
      );
      throw ApiException(response.statusCode, 'Не удалось скачать файл');
    } catch (e, st) {
      throw _mapAndLog('HTTP download failed: $uri', e, st);
    }
  }

  /// Скачивает файл потоком прямо на диск, не держа его целиком в памяти.
  /// Пишет во временный `.part` и переименовывает только после успеха, чтобы
  /// оборванная загрузка не осталась на месте готового файла.
  Future<void> downloadToFile(
    String url,
    File target, {
    void Function(int received, int? total)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw const DownloadCancelledException();
    }
    final uri = Uri.parse(url);
    final sessionGeneration = AuthService.instance.sessionGeneration;
    final client = http.Client();
    cancelToken?._onCancel = client.close;
    final part = File('${target.path}.part');
    try {
      final request = http.Request('GET', uri)..headers.addAll(authHeaders);
      final response = await client
          .send(request)
          .timeout(Duration(seconds: ApiConfig.timeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _noteResponseAuthOutcome(
          statusCode: response.statusCode,
          sessionGeneration: sessionGeneration,
        );
        throw ApiException(response.statusCode, 'Не удалось скачать файл');
      }
      AuthService.instance.noteRequestSucceeded(
        sessionGeneration: sessionGeneration,
      );

      await part.parent.create(recursive: true);
      final sink = part.openWrite();
      var received = 0;
      try {
        // Тайм-аут на паузу между кусками, а не на весь файл: большой файл
        // на медленной сети качается долго, но не должен «висеть» молча.
        await for (final chunk in response.stream.timeout(
          Duration(seconds: ApiConfig.timeoutSeconds),
        )) {
          if (cancelToken?.isCancelled ?? false) break;
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, response.contentLength);
        }
      } finally {
        await sink.close();
      }
      if (cancelToken?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      await part.rename(target.path);
    } catch (e, st) {
      if (await part.exists()) await part.delete();
      // Закрытый клиент бросает ClientException — при отмене это ожидаемо.
      if (cancelToken?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      throw _mapAndLog('HTTP download to file failed: $uri', e, st);
    } finally {
      cancelToken?._onCancel = null;
      client.close();
    }
  }

  /// Laravel отдаёт ошибку кодом 200 с `{"success": false, "data": {"error"}}`
  /// — без проверки такой JSON сохранялся бы как скачанный файл. Настоящий
  /// .json-файл не трогаем: ошибкой считается только `success: false`.
  void _throwIfJsonError(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('json')) return;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return;
    }
    if (decoded is! Map || decoded['success'] != false) return;
    final data = decoded['data'];
    final error = data is Map ? data['error'] : null;
    throw ApiException(
      response.statusCode,
      error is String && error.trim().isNotEmpty
          ? error
          : 'Не удалось скачать файл',
    );
  }

  Never _mapAndLog(String label, Object e, StackTrace st) {
    AppLogger.e(label, name: 'network.http', error: e, stackTrace: st);
    if (e is ApiException) throw e;
    throw mapNetworkError(e);
  }

  Map<String, dynamic> _handleResponse(
    http.Response response, {
    required Uri uri,
    required String method,
    required int sessionGeneration,
  }) {
    final body = response.body.isEmpty ? '{}' : response.body;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      AuthService.instance.noteRequestSucceeded(
        sessionGeneration: sessionGeneration,
      );
      if (decoded is Map<String, dynamic>) return decoded;
      AppLogger.e(
        'HTTP $method $uri: unexpected success body (not a JSON object)\n'
        'status: ${response.statusCode}\n'
        'body: ${AppLogger.truncate(body)}',
        name: 'network.http',
      );
      throw ApiException(response.statusCode, 'Некорректный ответ сервера');
    }

    AppLogger.e(
      'HTTP $method $uri failed\n'
      'status: ${response.statusCode}\n'
      'headers: ${AppLogger.prettyJson(response.headers)}\n'
      'body: ${AppLogger.truncate(body)}',
      name: 'network.http',
    );

    String message = 'Ошибка запроса (${response.statusCode})';
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      final nestedError = data is Map ? data['error']?.toString() : null;
      message =
          decoded['message'] as String? ??
          decoded['error'] as String? ??
          (decoded['errors'] as List?)?.join(', ') ??
          nestedError ??
          message;
    }

    _noteResponseAuthOutcome(
      statusCode: response.statusCode,
      sessionGeneration: sessionGeneration,
      message: message,
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        response.statusCode,
        message.isNotEmpty &&
                message != 'Ошибка запроса (${response.statusCode})'
            ? message
            : 'Ошибка авторизации. Войдите в аккаунт снова.',
      );
    }

    throw ApiException(response.statusCode, message);
  }

  void _noteResponseAuthOutcome({
    required int statusCode,
    required int sessionGeneration,
    String? message,
  }) {
    if (_isAuthenticationFailure(statusCode, message)) {
      AuthService.instance.noteAuthenticationFailed(
        sessionGeneration: sessionGeneration,
      );
    }
  }

  bool _isAuthenticationFailure(int statusCode, String? message) {
    if (statusCode == 401) return true;
    final normalized = message?.toLowerCase() ?? '';
    return normalized.contains('unauthenticated');
  }
}

/// [http.MultipartRequest], который сообщает, сколько байт тела уже ушло.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, this.onProgress);

  final void Function(int sent, int total) onProgress;

  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      stream.map((chunk) {
        sent += chunk.length;
        onProgress(sent, total);
        return chunk;
      }),
    );
  }
}
