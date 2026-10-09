import 'dart:async';
import 'package:connect/models/documents/document_service.dart';
import 'package:connect/services/document_pending_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = DocumentService(id: 1, name: 'First', title: 'First');
  const second = DocumentService(id: 2, name: 'Second', title: 'Second');
  const signing = DocumentService(
    id: 3,
    name: 'Sign',
    title: 'Sign',
    type: 'sign',
  );

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

  test(
    'signing service is loaded only while e-mail code access is fresh',
    () async {
      var now = DateTime(2026, 10, 1, 12);
      final loaded = <int>[];
      final service = DocumentPendingService(
        now: () => now,
        load: (id) async {
          loaded.add(id);
          return [
            {'status': 'pending'},
          ];
        },
      );
      await service.refresh([first, signing]);
      expect(loaded, [1]);
      expect(service.counts, {1: 1});

      service.markSigningAccessGranted();
      loaded.clear();
      await service.refresh([first, signing]);
      expect(loaded, [1, 3]);
      expect(service.counts, {1: 1, 3: 1});

      now = now.add(const Duration(minutes: 20));
      loaded.clear();
      await service.refresh([first, signing]);
      expect(loaded, [1]);
      expect(service.counts, {1: 1});
      service.dispose();
    },
  );
}
