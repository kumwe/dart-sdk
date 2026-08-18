import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  final origin = Uri.parse('https://cms.example.invalid');
  final otherOrigin = Uri.parse('https://kumwe.other.invalid');

  KumweAccountKey key({
    Uri? accountOrigin,
    KumweLoginArea area = KumweLoginArea.portal,
    String credential = 'credential-example-0001',
  }) => KumweAccountKey(
    origin: accountOrigin ?? origin,
    area: area,
    credential: KumweCredentialReference(credential),
  );

  test('keys separate origins, areas and credentials', () {
    expect(key(), key());
    expect(key().hashCode, key().hashCode);
    expect(key(), isNot(key(accountOrigin: otherOrigin)));
    expect(key(), isNot(key(area: KumweLoginArea.administrator)));
    expect(key(), isNot(key(credential: 'credential-example-0002')));
    expect(
      key().identity,
      'https://cms.example.invalid|portal|credential-example-0001',
    );
  });

  test('records validate their bounded display fields', () {
    final record = KumweAccountRecord(
      key: key(),
      state: KumweAccountState.pending,
      emailAddress: 'user@example.invalid',
      installationDisplayName: ' Example Kumwe Installation ',
    );
    expect(record.installationDisplayName, 'Example Kumwe Installation');
    expect(
      () => KumweAccountRecord(
        key: key(),
        state: KumweAccountState.active,
        emailAddress: 'with space@example.invalid',
      ),
      throwsArgumentError,
    );
    expect(
      () => KumweAccountRecord(
        key: key(),
        state: KumweAccountState.active,
        installationDisplayName: 'x' * 121,
      ),
      throwsArgumentError,
    );
  });

  test('record diagnostics never carry the address', () {
    final record = KumweAccountRecord(
      key: key(),
      state: KumweAccountState.active,
      emailAddress: 'user@example.invalid',
    );
    expect(record.toString(), isNot(contains('user@example.invalid')));
    expect(record.toString(), contains('active'));
  });

  test('withState reports positioning without touching identity', () {
    final pending = KumweAccountRecord(
      key: key(),
      state: KumweAccountState.pending,
      emailAddress: 'user@example.invalid',
    );
    final active = pending.withState(KumweAccountState.active);
    expect(active.key, pending.key);
    expect(active.state, KumweAccountState.active);
    expect(active.emailAddress, pending.emailAddress);
    expect(pending.state, KumweAccountState.pending);
  });

  test('the in-memory directory lists, replaces and removes records', () async {
    final directory = InMemoryAccountDirectory();
    expect(await directory.list(), isEmpty);

    final portal = KumweAccountRecord(
      key: key(),
      state: KumweAccountState.pending,
    );
    final administrator = KumweAccountRecord(
      key: key(area: KumweLoginArea.administrator),
      state: KumweAccountState.active,
    );
    await directory.save(portal);
    await directory.save(administrator);
    expect((await directory.list()).length, 2);

    await directory.save(portal.withState(KumweAccountState.active));
    final records = await directory.list();
    expect(records.length, 2);
    expect(
      records.singleWhere((record) => record.key == portal.key).state,
      KumweAccountState.active,
    );

    await directory.remove(portal.key);
    await directory.remove(portal.key);
    expect((await directory.list()).single.key, administrator.key);
  });
}
