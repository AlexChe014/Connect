import 'package:connect/models/documents/document_bulk_result.dart';
import 'package:connect/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guids = ['a', 'b', 'c'];

  DocumentBulkResult parse(Map<String, dynamic> decoded) =>
      DocumentBulkResult.fromResponse(decoded, requestedGuids: guids);

  test('partial success keeps failed documents with reasons', () {
    final result = parse({
      'success': true,
      'data': [
        {'guid': 'a', 'success': true},
        {'guid': 'b', 'success': false, 'error': 'Нет прав'},
        {'guid': 'c', 'success': true},
      ],
    });

    expect(result.allSucceeded, isFalse);
    expect(result.succeeded, ['a', 'c']);
    expect(result.total, 3);
    expect(result.failed.single.guid, 'b');
    expect(result.failed.single.error, 'Нет прав');
  });

  test('all failed comes as success:false with error_data', () {
    final result = parse({
      'success': false,
      'data': {
        'error': 'Не удалось обработать ни один документ',
        'error_data': [
          {'guid': 'a', 'success': false, 'error': 'x'},
          {'guid': 'b', 'success': false, 'error': 'y'},
          {'guid': 'c', 'success': false, 'error': 'z'},
        ],
      },
    });

    expect(result.succeeded, isEmpty);
    expect(result.failed.map((f) => f.error), ['x', 'y', 'z']);
  });

  test('general error without per-document data throws its message', () {
    expect(
      () => parse({
        'success': false,
        'data': {'error': 'Unauthenticated'},
      }),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Unauthenticated',
        ),
      ),
    );
  });

  test('old backend response of raw 1C answers means everything passed', () {
    final result = parse({
      'success': true,
      'data': [
        {'number': '1'},
        {'number': '2'},
        {'number': '3'},
      ],
    });

    expect(result.allSucceeded, isTrue);
    expect(result.succeeded, guids);
  });

  test('document missing from the per-document answer is not a success', () {
    final result = parse({
      'success': true,
      'data': [
        {'guid': 'a', 'success': true},
        {'guid': 'b', 'success': true},
      ],
    });

    expect(result.failed.single.guid, 'c');
    expect(result.failed.single.error, isNull);
  });

  test('describeFailures labels documents and truncates the list', () {
    const result = DocumentBulkResult(
      succeeded: ['ok'],
      failed: [
        DocumentBulkFailure(guid: 'a', error: 'Нет прав'),
        DocumentBulkFailure(guid: 'b'),
        DocumentBulkFailure(guid: 'c', error: 'x'),
      ],
    );

    expect(
      result.describeFailures({'a': '№ 1', 'b': 'Договор'}, limit: 2),
      '№ 1: Нет прав\nДоговор: нет ответа сервера\nи ещё 1',
    );
  });
}
