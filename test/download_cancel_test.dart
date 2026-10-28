import 'dart:io';

import 'package:connect/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('download_cancel_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // 10 кусков по 1 КБ с паузой — медленный файл, который успеем оборвать.
    server.listen((request) async {
      request.response.contentLength = 10 * 1024;
      for (var i = 0; i < 10; i++) {
        request.response.add(List.filled(1024, 7));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  String url() => 'http://127.0.0.1:${server.port}/file';

  test('downloadToFile reports progress and finishes', () async {
    final target = File('${dir.path}/a.bin');
    int? lastTotal;
    var lastReceived = 0;
    await ApiClient.instance.downloadToFile(
      url(),
      target,
      onProgress: (received, total) {
        lastReceived = received;
        lastTotal = total;
      },
    );
    expect(await target.length(), 10 * 1024);
    expect(lastReceived, 10 * 1024);
    expect(lastTotal, 10 * 1024);
  });

  test('cancel stops download and leaves no files', () async {
    final target = File('${dir.path}/b.bin');
    final token = DownloadCancelToken();
    final future = ApiClient.instance.downloadToFile(
      url(),
      target,
      cancelToken: token,
      onProgress: (received, _) {
        if (received >= 3 * 1024) token.cancel();
      },
    );
    await expectLater(future, throwsA(isA<DownloadCancelledException>()));
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.part').exists(), isFalse);
  });

  test('cancelled token fails immediately', () async {
    final token = DownloadCancelToken()..cancel();
    await expectLater(
      ApiClient.instance.downloadToFile(
        url(),
        File('${dir.path}/c.bin'),
        cancelToken: token,
      ),
      throwsA(isA<DownloadCancelledException>()),
    );
  });
}
