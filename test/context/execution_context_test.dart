import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('selection normalizes the site and validates the hierarchy', () {
    final selection = KumweContextSelection(
      site: ' Corporate ',
      organization: 'org-0001',
      workspace: 'workspace-0001',
      locale: 'en-NA',
    );
    expect(selection.site, 'corporate');
    expect(selection.organization, 'org-0001');
    expect(selection.workspace, 'workspace-0001');
    expect(selection.locale, 'en-NA');
    expect(
      () => KumweContextSelection(site: 'corporate', workspace: 'w-1'),
      throwsArgumentError,
    );
  });

  test('selection rejects unsupported identifiers and locales', () {
    expect(() => KumweContextSelection(site: ''), throwsArgumentError);
    expect(() => KumweContextSelection(site: 'bad site'), throwsArgumentError);
    expect(() => KumweContextSelection(site: '-lead'), throwsArgumentError);
    expect(() => KumweContextSelection(site: 'a' * 192), throwsArgumentError);
    expect(
      () => KumweContextSelection(site: 'corporate', locale: 'not a tag'),
      throwsArgumentError,
    );
    expect(
      () => KumweContextSelection(site: 'corporate', locale: 'x'),
      throwsArgumentError,
    );
  });

  test('execution context binds an exact HTTPS origin', () {
    final context = KumweExecutionContext(
      origin: Uri.https('cms.example.invalid'),
      selection: KumweContextSelection(site: 'corporate'),
      credential: KumweCredentialReference('credential-0001'),
    );
    expect(context.siteHeader, 'corporate');
    expect(context.correlationRoot, isNull);
    for (final origin in [
      Uri.http('cms.example.invalid'),
      Uri.parse('https://user:secret@cms.example.invalid'),
      Uri.parse('https://cms.example.invalid/?probe=1'),
      Uri.parse('https://cms.example.invalid/#fragment'),
      Uri.parse('https://cms.example.invalid/base'),
    ]) {
      expect(
        () => KumweExecutionContext(
          origin: origin,
          selection: KumweContextSelection(site: 'corporate'),
          credential: KumweCredentialReference('credential-0001'),
        ),
        throwsArgumentError,
        reason: '$origin',
      );
    }
  });

  test('cache partition covers every authority dimension', () {
    KumweExecutionContext build({
      String site = 'corporate',
      String credential = 'credential-0001',
      String? organization,
      Map<String, String> generations = const {},
    }) {
      return KumweExecutionContext(
        origin: Uri.https('cms.example.invalid'),
        selection: KumweContextSelection(
          site: site,
          organization: organization,
        ),
        credential: KumweCredentialReference(credential),
        authorityGenerations: generations,
      );
    }

    final base = build();
    expect(build().cachePartition, base.cachePartition);
    expect(build(site: 'other').cachePartition, isNot(base.cachePartition));
    expect(
      build(credential: 'credential-0002').cachePartition,
      isNot(base.cachePartition),
    );
    expect(
      build(organization: 'org-0001').cachePartition,
      isNot(base.cachePartition),
    );
    expect(
      build(generations: {'policy_generation': '7'}).cachePartition,
      isNot(base.cachePartition),
    );
    expect(
      build(
        generations: {'policy_generation': '7', 'security_epoch': '1'},
      ).cachePartition,
      build(
        generations: {'security_epoch': '1', 'policy_generation': '7'},
      ).cachePartition,
    );
  });

  test('authority generations are bounded and immutable', () {
    expect(
      () => KumweExecutionContext(
        origin: Uri.https('cms.example.invalid'),
        selection: KumweContextSelection(site: 'corporate'),
        credential: KumweCredentialReference('credential-0001'),
        authorityGenerations: {
          for (var index = 0; index < 17; index++) 'key$index': '$index',
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => KumweExecutionContext(
        origin: Uri.https('cms.example.invalid'),
        selection: KumweContextSelection(site: 'corporate'),
        credential: KumweCredentialReference('credential-0001'),
        authorityGenerations: {'Bad Key': '1'},
      ),
      throwsArgumentError,
    );
    expect(
      () => KumweExecutionContext(
        origin: Uri.https('cms.example.invalid'),
        selection: KumweContextSelection(site: 'corporate'),
        credential: KumweCredentialReference('credential-0001'),
        authorityGenerations: {'k': 'v,k2=v2'},
      ),
      throwsArgumentError,
      reason: 'separator injection into the cache partition must be refused',
    );
    final context = KumweExecutionContext(
      origin: Uri.https('cms.example.invalid'),
      selection: KumweContextSelection(site: 'corporate'),
      credential: KumweCredentialReference('credential-0001'),
      authorityGenerations: {'policy_generation': '7'},
    );
    expect(
      () => context.authorityGenerations['security_epoch'] = '2',
      throwsUnsupportedError,
    );
  });
}
