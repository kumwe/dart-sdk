import 'dart:async';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

final class _ControlledProvider implements KumweAuthorizationProvider {
  final requests = <KumweTokenRequest>[];
  final tokens = <Completer<KumweAccessToken>>[];
  final invalidated = <KumweCredentialReference>[];
  final invalidationGates = <Completer<void>>[];

  @override
  Future<KumweAccessToken> tokenFor(KumweTokenRequest request) {
    requests.add(request);
    final pending = Completer<KumweAccessToken>();
    tokens.add(pending);
    return pending.future;
  }

  @override
  Future<void> invalidate(KumweCredentialReference credential) async {
    invalidated.add(credential);
    if (invalidationGates.isNotEmpty) {
      await invalidationGates.removeAt(0).future;
    }
  }
}

KumweAccessToken _issued(String identity, {String? credential}) =>
    KumweAccessToken(
      token: BearerToken('synthetic-bearer-token-$identity'),
      credential: KumweCredentialReference(
        credential ?? 'credential-$identity',
      ),
      boundSite: 'corporate',
      refreshEligible: true,
    );

KumweSession _session(_ControlledProvider provider) => KumweSession(
  origin: Uri.parse('https://cms.example.invalid'),
  selection: KumweContextSelection(site: 'corporate'),
  provider: provider,
);

void main() {
  for (final sharedReference in [false, true]) {
    test('newer interactive result survives stale completion '
        '(shared reference: $sharedReference)', () async {
      final provider = _ControlledProvider();
      final session = _session(provider);
      final old = session.reauthenticate();
      final refused = expectLater(
        old,
        throwsA(isA<KumweAuthenticationException>()),
      );
      final newest = session.reauthenticate();
      provider.tokens[1].complete(_issued('newest'));
      await newest;
      provider.tokens[0].complete(
        _issued(
          'old',
          credential: sharedReference ? 'credential-newest' : null,
        ),
      );
      await refused;

      expect((await session.token())?.value, 'synthetic-bearer-token-newest');
      expect(session.state, KumweSessionState.active);
      expect(provider.requests, hasLength(2));
      expect(
        provider.invalidated.map((value) => value.value),
        sharedReference ? isEmpty : ['credential-old'],
      );
    });
  }

  test('obsolete cleanup cannot clear a pending newer acquisition', () async {
    final provider = _ControlledProvider();
    final session = _session(provider);
    final old = session.token();
    final refused = expectLater(old, throwsStateError);
    final newest = session.reauthenticate();
    provider.tokens[0].completeError(StateError('Synthetic obsolete failure.'));
    await refused;
    final joining = session.token();
    await Future<void>.delayed(Duration.zero);
    expect(provider.requests, hasLength(2));
    provider.tokens[1].complete(_issued('newest'));
    await newest;
    expect((await joining)?.value, 'synthetic-bearer-token-newest');
    expect(provider.requests, hasLength(2));
  });

  for (final sharedReference in [false, true]) {
    test('discard waits for pending acquisition before releasing its reference '
        '(shared reference: $sharedReference)', () async {
      final provider = _ControlledProvider();
      final session = _session(provider);
      final old = session.reauthenticate();
      final refused = expectLater(
        old,
        throwsA(isA<KumweAuthenticationException>()),
      );
      final newest = session.reauthenticate();
      provider.tokens[0].complete(_issued('old'));
      await Future<void>.delayed(Duration.zero);
      expect(
        provider.invalidated,
        isEmpty,
        reason: 'a pending provider result may reuse the discarded reference',
      );
      final joining = session.token();
      expect(provider.requests, hasLength(2));
      provider.tokens[1].complete(
        _issued(
          'newest',
          credential: sharedReference ? 'credential-old' : null,
        ),
      );
      await newest;
      await refused;
      expect((await joining)?.value, 'synthetic-bearer-token-newest');
      expect((await session.token())?.value, 'synthetic-bearer-token-newest');
      expect(
        provider.invalidated.map((value) => value.value),
        sharedReference ? isEmpty : ['credential-old'],
      );
    });
  }

  test(
    'sign-out releases deferred credentials without waiting for newer work',
    () async {
      final provider = _ControlledProvider();
      final session = _session(provider);
      final old = session.reauthenticate();
      final oldRefused = expectLater(
        old,
        throwsA(isA<KumweAuthenticationException>()),
      );
      final newest = session.reauthenticate();
      final newestRefused = expectLater(
        newest,
        throwsA(isA<KumweAuthenticationException>()),
      );
      provider.tokens[0].complete(_issued('old'));
      await Future<void>.delayed(Duration.zero);
      expect(provider.invalidated, isEmpty);
      await session.signOut();
      await oldRefused;
      expect(provider.tokens[1].isCompleted, isFalse);
      expect(provider.invalidated.map((value) => value.value), [
        'credential-old',
      ]);
      provider.tokens[1].complete(_issued('newest'));
      await newestRefused;
      expect(provider.invalidated.map((value) => value.value), [
        'credential-old',
        'credential-newest',
      ]);
      expect(session.state, KumweSessionState.signedOut);
      expect(await session.token(), isNull);
    },
  );

  test(
    'stale refresh failure cannot close a newer interactive session',
    () async {
      final provider = _ControlledProvider();
      final session = _session(provider);
      final initial = session.token();
      provider.tokens.single.complete(_issued('initial'));
      await initial;
      final refreshing = session.handleAuthenticationFailure(
        KumweCredentialReference('credential-initial'),
      );
      final failed = expectLater(refreshing, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final newest = session.reauthenticate();
      provider.tokens[2].complete(_issued('newest'));
      await newest;
      provider.tokens[1].completeError(
        StateError('Synthetic refresh refusal.'),
      );
      await failed;

      expect(session.state, KumweSessionState.active);
      expect((await session.token())?.value, 'synthetic-bearer-token-newest');
      expect(provider.requests, hasLength(3));
    },
  );

  test(
    'interactive authentication completing after sign-out dies unused',
    () async {
      final provider = _ControlledProvider();
      final session = _session(provider);
      final pending = session.reauthenticate();
      final refused = expectLater(
        pending,
        throwsA(isA<KumweAuthenticationException>()),
      );
      await session.signOut();
      provider.tokens.single.complete(_issued('late-interactive'));
      await refused;

      expect(session.state, KumweSessionState.signedOut);
      expect(session.accessToken, isNull);
      expect(await session.token(), isNull);
      expect(
        provider.invalidated.map((value) => value.value),
        ['credential-late-interactive'],
        reason:
            'interactive requests obey the same post-sign-out ownership rule',
      );
    },
  );

  test('delayed duplicate invalidation preserves a newer replacement', () async {
    final provider = _ControlledProvider();
    final session = _session(provider);
    final initial = session.token();
    provider.tokens.single.complete(_issued('initial'));
    await initial;

    final firstGate = Completer<void>();
    final delayedGate = Completer<void>();
    provider.invalidationGates.addAll([firstGate, delayedGate]);
    final first = session.handleAuthenticationFailure(
      KumweCredentialReference('credential-initial'),
    );
    final delayed = session.handleAuthenticationFailure(
      KumweCredentialReference('credential-initial'),
    );
    firstGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(provider.requests, hasLength(2));
    provider.tokens.last.complete(_issued('replacement'));
    expect((await first)?.credential.value, 'credential-replacement');

    delayedGate.complete();
    await Future<void>.delayed(Duration.zero);
    // Settle an erroneous extra acquisition so a regression fails immediately.
    if (provider.tokens.length > 2) {
      provider.tokens.last.complete(_issued('unexpected-extra'));
    }
    final answered = await delayed;
    expect(
      provider.requests,
      hasLength(2),
      reason: 'a late rejection cannot rotate the recovered token',
    );
    expect(answered?.credential.value, 'credential-replacement');
    expect(session.accessToken?.credential.value, 'credential-replacement');
    expect(session.state, KumweSessionState.active);
  });
}
