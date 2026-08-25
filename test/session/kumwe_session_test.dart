import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

final class ScriptedProvider implements KumweAuthorizationProvider {
  ScriptedProvider(this._tokens);

  final List<KumweAccessToken Function(KumweTokenRequest)> _tokens;
  final List<KumweTokenRequest> requests = [];
  final List<KumweCredentialReference> invalidated = [];
  int pendingCalls = 0;

  @override
  Future<KumweAccessToken> tokenFor(KumweTokenRequest request) async {
    requests.add(request);
    pendingCalls += 1;
    await Future<void>.delayed(Duration.zero);
    pendingCalls -= 1;
    if (_tokens.isEmpty) {
      throw StateError('No scripted token remains.');
    }
    return _tokens.removeAt(0)(request);
  }

  @override
  Future<void> invalidate(KumweCredentialReference credential) async {
    invalidated.add(credential);
  }
}

KumweAccessToken issued(
  String suffix, {
  DateTime? expiresAt,
  Map<String, String> generations = const {},
  String site = 'corporate',
}) {
  return KumweAccessToken(
    token: BearerToken('bearer-token-00000000000000000000$suffix'),
    credential: KumweCredentialReference('credential-$suffix'),
    boundSite: site,
    expiresAt: expiresAt,
    refreshEligible: true,
    authorityGenerations: generations,
  );
}

void main() {
  final origin = Uri.parse('https://cms.example.invalid');
  final selection = KumweContextSelection(site: 'corporate');

  KumweSession session(
    ScriptedProvider provider, {
    DateTime Function()? clock,
  }) {
    return KumweSession(
      origin: origin,
      selection: selection,
      provider: provider,
      clock: clock ?? () => DateTime.utc(2026, 8, 25, 12),
    );
  }

  group('acquisition', () {
    test('the first use asks for an initial token and holds it', () async {
      final provider = ScriptedProvider([(_) => issued('0001')]);
      final subject = session(provider);
      final token = await subject.token();
      expect(token?.value, endsWith('0001'));
      expect(provider.requests.single.reason, KumweTokenRequestReason.initial);
      expect(subject.state, KumweSessionState.active);
      // A second use spends the held token without a provider call.
      await subject.token();
      expect(provider.requests, hasLength(1));
    });

    test('concurrent first uses share one provider call', () async {
      final provider = ScriptedProvider([(_) => issued('0001')]);
      final subject = session(provider);
      final results = await Future.wait([
        subject.token(),
        subject.token(),
        subject.token(),
      ]);
      expect(provider.requests, hasLength(1));
      expect(
        results.every((token) => token?.value == results.first?.value),
        isTrue,
      );
    });

    test('a token inside its expiry margin is refreshed before use', () async {
      final provider = ScriptedProvider([
        (_) => issued('0001', expiresAt: DateTime.utc(2026, 8, 25, 12, 0, 20)),
      ]);
      final subject = session(provider);
      await expectLater(
        subject.token(),
        throwsA(isA<Object>()),
        reason: 'the provider returned an already-expiring token',
      );
    });

    test('an expired held token triggers a refresh request', () async {
      var now = DateTime.utc(2026, 8, 25, 12);
      final provider = ScriptedProvider([
        (_) => issued('0001', expiresAt: DateTime.utc(2026, 8, 25, 13)),
        (_) => issued('0002', expiresAt: DateTime.utc(2026, 8, 25, 15)),
      ]);
      final subject = session(provider, clock: () => now);
      await subject.token();
      now = DateTime.utc(2026, 8, 25, 14);
      final refreshed = await subject.token();
      expect(refreshed?.value, endsWith('0002'));
      expect(provider.requests[1].reason, KumweTokenRequestReason.refresh);
      expect(provider.requests[1].previousCredential?.value, 'credential-0001');
    });

    test('a token bound to a different site is refused', () async {
      final provider = ScriptedProvider([(_) => issued('0001', site: 'other')]);
      await expectLater(
        session(provider).token(),
        throwsA(isA<KumweAuthenticationException>()),
      );
    });
  });

  group('the 401-once discipline', () {
    test('one rejection invalidates, refreshes and recovers', () async {
      final provider = ScriptedProvider([
        (_) => issued('0001'),
        (_) => issued('0002'),
      ]);
      final subject = session(provider);
      await subject.token();
      final replacement = await subject.handleAuthenticationFailure();
      expect(replacement?.credential.value, 'credential-0002');
      expect(provider.invalidated.single.value, 'credential-0001');
      expect(subject.state, KumweSessionState.active);
    });

    test('a rejected refresh escalates instead of looping', () async {
      final provider = ScriptedProvider([
        (_) => issued('0001'),
        (_) => issued('0002'),
      ]);
      final subject = session(provider);
      await subject.token();
      await subject.handleAuthenticationFailure();
      // The refreshed credential is rejected too.
      final second = await subject.handleAuthenticationFailure();
      expect(second, isNull);
      expect(subject.state, KumweSessionState.reauthenticationRequired);
      expect(provider.invalidated.map((credential) => credential.value), [
        'credential-0001',
        'credential-0002',
      ]);
      // No silent token is handed out any more.
      expect(await subject.token(), isNull);
      expect(
        provider.requests,
        hasLength(2),
        reason: 'no hidden third provider call',
      );
    });

    test('interactive re-authentication restores the session', () async {
      final provider = ScriptedProvider([
        (_) => issued('0001'),
        (_) => issued('0002'),
        (_) => issued('0003'),
      ]);
      final subject = session(provider);
      await subject.token();
      await subject.handleAuthenticationFailure();
      await subject.handleAuthenticationFailure();
      expect(subject.state, KumweSessionState.reauthenticationRequired);
      final restored = await subject.reauthenticate();
      expect(restored.credential.value, 'credential-0003');
      expect(
        provider.requests.last.reason,
        KumweTokenRequestReason.reauthentication,
      );
      expect(subject.state, KumweSessionState.active);
      expect((await subject.token())?.value, endsWith('0003'));
    });

    test('a failing silent refresh escalates and surfaces the error', () async {
      final provider = ScriptedProvider([(_) => issued('0001')]);
      final subject = session(provider);
      await subject.token();
      await expectLater(
        subject.handleAuthenticationFailure(),
        throwsStateError,
      );
      expect(subject.state, KumweSessionState.reauthenticationRequired);
    });
  });

  group('sign-out', () {
    test('invalidates the credential and stays signed out', () async {
      final provider = ScriptedProvider([(_) => issued('0001')]);
      final subject = session(provider);
      await subject.token();
      await subject.signOut();
      expect(subject.state, KumweSessionState.signedOut);
      expect(provider.invalidated.single.value, 'credential-0001');
      expect(await subject.token(), isNull);
      expect(
        provider.requests,
        hasLength(1),
        reason: 'a signed-out session never asks for tokens',
      );
      await expectLater(subject.reauthenticate(), throwsStateError);
    });
  });

  group('authority generations', () {
    test('the held generations follow the held token', () async {
      final provider = ScriptedProvider([
        (_) => issued('0001', generations: {'policy_generation': '7'}),
      ]);
      final subject = session(provider);
      expect(subject.authorityGenerations, isEmpty);
      await subject.token();
      expect(subject.authorityGenerations, {'policy_generation': '7'});
    });
  });
}
