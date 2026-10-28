import 'package:connect/utils/ru_plural.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ruPlural picks the Russian form by number', () {
    String f(int n) => ruPlural(n, 'участник', 'участника', 'участников');
    expect(f(1), 'участник');
    expect(f(21), 'участник');
    expect(f(2), 'участника');
    expect(f(24), 'участника');
    expect(f(5), 'участников');
    expect(f(11), 'участников');
    expect(f(12), 'участников');
    expect(f(111), 'участников');
  });
}
