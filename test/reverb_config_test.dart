import 'package:connect/config/api_config.dart';
import 'package:connect/config/reverb_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReverbConfig.forDevice', () {
    test('rewrites docker hostname reverb to the public backend host', () {
      const raw = ReverbConfig(
        appKey: 'test-key',
        host: 'reverb',
        port: 8081,
        useTls: false,
      );
      final resolved = raw.forDevice();
      final backend = Uri.parse(ApiConfig.backendHost);

      expect(resolved.appKey, 'test-key');
      expect(resolved.host, backend.host);
      expect(resolved.useTls, backend.scheme != 'http');
      expect(resolved.port, backend.hasPort ? backend.port : 443);
    });

    test('keeps a public websocket host unchanged', () {
      const raw = ReverbConfig(
        appKey: 'test-key',
        host: 'connect.xondev.ru',
        port: 443,
        useTls: true,
        path: '/ws',
      );
      final resolved = raw.forDevice();
      expect(resolved.host, 'connect.xondev.ru');
      expect(resolved.port, 443);
      expect(resolved.useTls, isTrue);
      expect(resolved.path, '/ws');
    });

    test('fromSettings prefers public_host over docker host', () {
      const fallback = ReverbConfig(
        appKey: '',
        host: 'example.com',
        port: 443,
        useTls: true,
      );
      final config = ReverbConfig.fromSettings(
        {
          'app_key': 'k',
          'public_host': 'connect.xondev.ru',
          'host': 'reverb',
          'port': '8081',
          'scheme': 'http',
        },
        fallback: fallback,
      );
      expect(config.appKey, 'k');
      expect(config.host, 'connect.xondev.ru');
    });
  });
}
