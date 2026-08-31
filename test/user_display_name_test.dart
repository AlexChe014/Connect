import 'package:connect/utils/user_display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('userDisplayName', () {
    test('joins surname and name', () {
      expect(
        userDisplayName(surname: 'Иванов', name: 'Иван'),
        'Иванов Иван',
      );
    });

    test('trims whitespace around parts', () {
      expect(
        userDisplayName(surname: '  Иванов  ', name: '  Иван '),
        'Иванов Иван',
      );
    });

    test('falls back to whichever of surname/name is present', () {
      expect(userDisplayName(surname: 'Иванов'), 'Иванов');
      expect(userDisplayName(name: 'Иван'), 'Иван');
    });

    test('falls back to email when no name is set', () {
      expect(
        userDisplayName(email: 'user@example.com'),
        'user@example.com',
      );
    });

    test('falls back to a placeholder when nothing is set', () {
      expect(userDisplayName(), 'Пользователь');
      expect(userDisplayName(surname: '  ', name: '  ', email: '  '), 'Пользователь');
    });
  });

  group('userDisplayNameFromJson', () {
    test('reads surname/name/email out of a raw user map', () {
      expect(
        userDisplayNameFromJson({
          'surname': 'Петров',
          'name': 'Пётр',
          'email': 'petrov@example.com',
        }),
        'Петров Пётр',
      );
    });

    test('handles a map missing every name field', () {
      expect(userDisplayNameFromJson({'id': 1}), 'Пользователь');
    });
  });

  group('userInitials', () {
    test('takes the first letter of each of the first two words', () {
      expect(userInitials('Иванов Иван'), 'ИИ');
    });

    test('extra words beyond the first two are ignored', () {
      expect(userInitials('Иванов Иван Иванович'), 'ИИ');
    });

    test('a single multi-letter word uses its first two letters', () {
      expect(userInitials('Иван'), 'ИВ');
    });

    test('a single one-letter word uses just that letter', () {
      expect(userInitials('A'), 'A');
    });

    test('blank input falls back to a placeholder', () {
      expect(userInitials(''), '?');
      expect(userInitials('   '), '?');
    });
  });
}
