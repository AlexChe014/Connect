import 'package:connect/services/session_auth_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> flushDebounce() =>
      Future<void>.delayed(const Duration(milliseconds: 1));

  SessionAuthGuard buildGuard({
    required Future<bool?> Function() verifySession,
    required Future<void> Function() onExpired,
    bool authenticated = true,
    int generation = 1,
  }) {
    return SessionAuthGuard(
      debounce: Duration.zero,
      probeCooldown: const Duration(seconds: 30),
      isAuthenticated: () => authenticated,
      sessionGeneration: () => generation,
      verifySession: verifySession,
      onExpired: onExpired,
    );
  }

  test('does not expire when a later request succeeds', () async {
    var expired = false;
    var probes = 0;
    final guard = buildGuard(
      verifySession: () async {
        probes++;
        return true;
      },
      onExpired: () async => expired = true,
    );

    guard.noteAuthFailure(generation: 1);
    guard.noteSuccess(generation: 1);
    await flushDebounce();

    expect(expired, isFalse);
    expect(probes, 0);
  });

  test('expires when all requests fail auth and the probe is 401', () async {
    var expired = false;
    final guard = buildGuard(
      verifySession: () async => true,
      onExpired: () async => expired = true,
    );

    guard.noteAuthFailure(generation: 1);
    guard.noteAuthFailure(generation: 1);
    await flushDebounce();

    expect(expired, isTrue);
  });

  test('does not expire when the probe shows the session is still valid', () async {
    var expired = false;
    final guard = buildGuard(
      verifySession: () async => false,
      onExpired: () async => expired = true,
    );

    guard.noteAuthFailure(generation: 1);
    await flushDebounce();

    expect(expired, isFalse);
  });

  test('does not expire when the probe is inconclusive', () async {
    var expired = false;
    final guard = buildGuard(
      verifySession: () async => null,
      onExpired: () async => expired = true,
    );

    guard.noteAuthFailure(generation: 1);
    await flushDebounce();

    expect(expired, isFalse);
  });

  test('ignores auth failures from a previous session generation', () async {
    var expired = false;
    final guard = buildGuard(
      verifySession: () async => true,
      onExpired: () async => expired = true,
    );

    guard.noteAuthFailure(generation: 0);
    await flushDebounce();

    expect(expired, isFalse);
  });

  test('does not probe while logged out', () async {
    var probes = 0;
    var expired = false;
    final guard = buildGuard(
      authenticated: false,
      verifySession: () async {
        probes++;
        return true;
      },
      onExpired: () async => expired = true,
    );

    guard.noteAuthFailure(generation: 1);
    await flushDebounce();

    expect(probes, 0);
    expect(expired, isFalse);
  });
}
