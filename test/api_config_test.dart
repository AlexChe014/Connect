import 'package:connect/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConfig.baseUrl', () {
    test('defaults to production host with /mobile/api suffix', () {
      expect(ApiConfig.baseUrl, 'https://connect.xondev.ru/mobile/api');
    });
  });

  group('ApiConfig.isBackendHostValid', () {
    test('accepts a plain https host', () {
      expect(ApiConfig.isBackendHostValid('https://example.com'), isTrue);
    });

    test('rejects null, empty and blank input', () {
      expect(ApiConfig.isBackendHostValid(null), isFalse);
      expect(ApiConfig.isBackendHostValid(''), isFalse);
      expect(ApiConfig.isBackendHostValid('   '), isFalse);
    });

    test('rejects a host without a scheme', () {
      expect(ApiConfig.isBackendHostValid('example.com'), isFalse);
    });

    test('rejects non-http(s) schemes', () {
      expect(ApiConfig.isBackendHostValid('ftp://example.com'), isFalse);
    });
  });

  group('ApiConfig.normalizeFileUrl', () {
    test('null and empty input stay null', () {
      expect(ApiConfig.normalizeFileUrl(null), isNull);
      expect(ApiConfig.normalizeFileUrl(''), isNull);
      expect(ApiConfig.normalizeFileUrl('   '), isNull);
    });

    test('relative path is rebased onto the public files host', () {
      expect(
        ApiConfig.normalizeFileUrl('/storage/avatars/1.png'),
        'https://data.xondev.ru/storage/avatars/1.png',
      );
    });

    test('relative path without a leading slash gets one added', () {
      expect(
        ApiConfig.normalizeFileUrl('storage/avatars/1.png'),
        'https://data.xondev.ru/storage/avatars/1.png',
      );
    });

    test('localhost URLs are rewritten to the public files host', () {
      expect(
        ApiConfig.normalizeFileUrl('http://localhost:8000/storage/x.png'),
        'https://data.xondev.ru/storage/x.png',
      );
    });

    test('current backend host URLs are rewritten to the public files host', () {
      expect(
        ApiConfig.normalizeFileUrl(
          'https://connect.xondev.ru/storage/avatar.png',
        ),
        'https://data.xondev.ru/storage/avatar.png',
      );
    });

    test('URLs already on an unrelated host are left untouched', () {
      expect(
        ApiConfig.normalizeFileUrl('https://cdn.other.com/image.png'),
        'https://cdn.other.com/image.png',
      );
    });

    test('URLs already on the public files host are left untouched', () {
      expect(
        ApiConfig.normalizeFileUrl('https://data.xondev.ru/x.png'),
        'https://data.xondev.ru/x.png',
      );
    });
  });

  group('ApiConfig.normalizeNextPageUrl', () {
    test('null and empty input stay null', () {
      expect(ApiConfig.normalizeNextPageUrl(null), isNull);
      expect(ApiConfig.normalizeNextPageUrl(''), isNull);
    });

    test('rebases host/scheme onto baseUrl when path already matches it', () {
      expect(
        ApiConfig.normalizeNextPageUrl(
          'http://localhost:8000/mobile/api/chat?page=2',
        ),
        'https://connect.xondev.ru/mobile/api/chat?page=2',
      );
    });

    test('drops a stray port from the backend and keeps ours', () {
      // Regression: Uri.replace(port: null) does not clear the port, so a
      // naive implementation would leak backend-internal ports like :8000
      // into the URL the app actually calls.
      final result = ApiConfig.normalizeNextPageUrl(
        'http://backend-internal:8000/mobile/api/chat?page=2',
      )!;
      expect(Uri.parse(result).hasPort, isFalse);
      expect(result, 'https://connect.xondev.ru/mobile/api/chat?page=2');
    });

    test('an empty or root next-page path falls back to baseUrl path', () {
      expect(
        ApiConfig.normalizeNextPageUrl('https://backend-internal?page=3'),
        'https://connect.xondev.ru/mobile/api?page=3',
      );
    });

    test(
      'prefixes a reverse-proxy-unaware path with the missing baseUrl segment',
      () {
        // Regression: backend builds next_page_url from its own internal
        // route (/api/user/filter) without knowing about the /mobile
        // reverse-proxy prefix. Naively prepending basePath would produce
        // /mobile/api/api/user/filter (404) instead of /mobile/api/user/filter.
        expect(
          ApiConfig.normalizeNextPageUrl(
            'http://backend-internal/api/user/filter?page=2',
          ),
          'https://connect.xondev.ru/mobile/api/user/filter?page=2',
        );
      },
    );

    test('leaves query string untouched when absent', () {
      expect(
        ApiConfig.normalizeNextPageUrl('http://backend-internal/mobile/api/chat'),
        'https://connect.xondev.ru/mobile/api/chat',
      );
    });
  });
}
