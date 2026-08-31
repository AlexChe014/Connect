import 'package:connect/utils/media_url_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaUrlUtils.firstUrl', () {
    test('null and blank input yield null', () {
      expect(MediaUrlUtils.firstUrl(null), isNull);
      expect(MediaUrlUtils.firstUrl('   '), isNull);
    });

    test('a plain string is returned trimmed', () {
      expect(MediaUrlUtils.firstUrl('  http://x/a.png  '), 'http://x/a.png');
    });

    test('picks the first known URL key from a map', () {
      expect(MediaUrlUtils.firstUrl({'url': 'http://x/a.png'}), 'http://x/a.png');
    });

    test('preview_url takes priority over url', () {
      expect(
        MediaUrlUtils.firstUrl({
          'preview_url': 'http://x/preview.png',
          'url': 'http://x/full.png',
        }),
        'http://x/preview.png',
      );
    });

    test('a map with no known key yields null', () {
      expect(MediaUrlUtils.firstUrl({'id': 1}), isNull);
    });

    test('returns the first non-empty URL from a list', () {
      expect(
        MediaUrlUtils.firstUrl([
          {'id': 1},
          {'url': 'http://x/a.png'},
          {'url': 'http://x/b.png'},
        ]),
        'http://x/a.png',
      );
    });

    test('skips null entries inside a list', () {
      expect(
        MediaUrlUtils.firstUrl([null, {'url': 'http://x/b.png'}]),
        'http://x/b.png',
      );
    });
  });

  group('MediaUrlUtils.normalizeFirstUrl', () {
    test('rebases a relative media path onto the public files host', () {
      expect(
        MediaUrlUtils.normalizeFirstUrl({'url': '/storage/avatar.png'}),
        'https://data.xondev.ru/storage/avatar.png',
      );
    });

    test('null media yields null', () {
      expect(MediaUrlUtils.normalizeFirstUrl(null), isNull);
    });
  });
}
