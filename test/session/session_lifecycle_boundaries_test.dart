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

KumweAccessToken _issued(String identity) => KumweAccessToken(
  token: BearerToken('synthetic-bearer-token-$identity'),
  credential: KumweCredentialReference('credential-$identity'),
  boundSite: 'corporate',
  refreshEligible: true,
);

KumweSession _session(_ControlledProvider provider) => KumweSession(
  origin: Uri.parse('https://cms.example.invalid'),
  selection: KumweContextSelection(site: 'corporate'),
  provider: provider,
);

void main() {
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
