import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('credential references are bounded opaque identifiers', () {
    expect(
      KumweCredentialReference(' credential-0001 ').value,
      'credential-0001',
    );
    for (final value in ['', 'has space', '-lead', 'a' * 192]) {
      expect(
        () => KumweCredentialReference(value),
        throwsArgumentError,
        reason: value,
      );
    }
  });

  test('token requests bind an HTTPS origin and name replaced credentials', () {
    final request = KumweTokenRequest(
      origin: Uri.https('cms.example.invalid'),
      selection: KumweContextSelection(site: 'corporate'),
      reason: KumweTokenRequestReason.initial,
    );
    expect(request.previousCredential, isNull);
    expect(
      () => KumweTokenRequest(
        origin: Uri.http('cms.example.invalid'),
        selection: KumweContextSelection(site: 'corporate'),
        reason: KumweTokenRequestReason.initial,
      ),
      throwsArgumentError,
    );
    expect(
      () => KumweTokenRequest(
        origin: Uri.https('cms.example.invalid'),
        selection: KumweContextSelection(site: 'corporate'),
        reason: KumweTokenRequestReason.refresh,
      ),
      throwsArgumentError,
    );
  });

  test('access tokens carry redacted secrets beside bounded metadata', () {
    final token = KumweAccessToken(
      token: BearerToken('example-access-token-0001'),
      credential: KumweCredentialReference('credential-0001'),
      boundSite: 'corporate',
      expiresAt: DateTime.utc(2026, 9, 1),
      refreshEligible: true,
      purpose: 'api',
      audience: 'kumwe-http',
      authorityGenerations: {'policy_generation': '7'},
    );
    expect(token.toString(), isNot(contains('example-access-token-0001')));
    expect(token.toString(), contains('credential-0001'));
    expect(
      () => token.authorityGenerations['security_epoch'] = '2',
      throwsUnsupportedError,
    );
    expect(
      () => KumweAccessToken(
        token: BearerToken('example-access-token-0002'),
        credential: KumweCredentialReference('credential-0002'),
        boundSite: 'corporate',
        authorityGenerations: {
          for (var index = 0; index < 17; index++) 'key$index': '$index',
        },
      ),
      throwsArgumentError,
    );
  });

  test('credential store keys bind the exact origin and credential', () {
    final key = KumweCredentialStoreKey(
      origin: Uri.https('cms.example.invalid'),
      credential: KumweCredentialReference('credential-0001'),
    );
    expect(
      key,
      KumweCredentialStoreKey(
        origin: Uri.https('cms.example.invalid'),
        credential: KumweCredentialReference('credential-0001'),
      ),
    );
    expect(
      key,
      isNot(
        KumweCredentialStoreKey(
          origin: Uri.https('other.example.invalid'),
          credential: KumweCredentialReference('credential-0001'),
        ),
      ),
    );
    expect(
      () => KumweCredentialStoreKey(
        origin: Uri.http('cms.example.invalid'),
        credential: KumweCredentialReference('credential-0001'),
      ),
      throwsArgumentError,
    );
  });

  test('the in-memory store reads, replaces, and removes secrets', () async {
    final store = InMemoryCredentialStore();
    final key = KumweCredentialStoreKey(
      origin: Uri.https('cms.example.invalid'),
      credential: KumweCredentialReference('credential-0001'),
    );
    expect(await store.read(key), isNull);
    await store.write(key, 'example-secret-0001');
    expect(await store.read(key), 'example-secret-0001');
    await store.write(key, 'example-secret-0002');
    expect(await store.read(key), 'example-secret-0002');
    await store.remove(key);
    expect(await store.read(key), isNull);
    await store.remove(key);
    expect(() => store.write(key, ''), throwsArgumentError);
    expect(store.toString(), isNot(contains('example-secret')));
  });
}
