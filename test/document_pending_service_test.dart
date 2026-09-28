import 'dart:async';
import 'package:connect/models/documents/document_service.dart';
import 'package:connect/services/document_pending_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = DocumentService(id: 1, name: 'First', title: 'First');
  const second = DocumentService(id: 2, name: 'Second', title: 'Second');

  test(
    'counts pending documents per service, excluding finished items',
    () async {
      final service = DocumentPendingService(
        load: (id) async => id == 1
            ? [
                {'status': 'pending'},
                {'guidlist': 'legacy'},
                {'status': 'approved'},
              ]
            : [
                {'Status': 'Подписан'},
              ],
      );
      await service.refresh([first, second]);
      expect(service.counts, {1: 2, 2: 0});
      expect(service.errors, isEmpty);
      service.dispose();
    },
  );

  test(
    'failure is distinguishable from zero and does not block other services',
    () async {
      var fail = false;
      final service = DocumentPendingService(
        load: (id) async {
          if (fail && id == 1) throw Exception('Offline');
          return [
            {'status': 'pending'},
          ];
        },
      );
      await service.refresh([first, second]);
      fail = true;
      await service.refresh([first, second]);
      expect(service.errors, {1});
      expect(service.counts, {1: 1, 2: 1});
      expect(service.loading, isEmpty);
      service.dispose();
    },
  );

  test('late response cannot restore counts after logout', () async {
    final response = Completer<List<Map<String, dynamic>>>();
    final service = DocumentPendingService(load: (_) => response.future);
    final refresh = service.refresh([first]);
    service.reset();
    response.complete([
      {'status': 'pending'},
    ]);
    await refresh;
    expect(service.counts, isEmpty);
    expect(service.loading, isEmpty);
    service.dispose();
  });
}
