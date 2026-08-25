import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

KumweProblemRegistry registry() {
  final source = File(
    'contracts/problem-details-registry.proposal.json',
  ).readAsStringSync();
  return KumweProblemRegistry.fromJson(
    (jsonDecode(source) as Map).cast<String, Object?>(),
  );
}

KumweClientOptions options() => KumweClientOptions(
  baseUri: Uri.parse('https://cms.example.invalid'),
  site: 'corporate',
  tokenProvider: StaticBearerTokenProvider(
    'sentinel-bearer-000000000000000000000001',
  ),
  requestIdFactory: () => 'request-0000001',
);

void main() {
  group('cross-origin confinement', () {
    test('every business request stays on the configured origin', () async {
      final transport = FakeKumweTransport([
        KumweResponse(
          statusCode: 200,
          headers: HeaderMap({'Content-Type': 'application/json'}),
          body: utf8.encode('{"data": []}'),
        ),
      ]);
      final api = KumweBusinessApi(
        options: options(),
        transport: transport,
        registry: registry(),
      );
      await api.catalog();
      final uri = transport.requests.single.uri;
      expect(uri.host, 'cms.example.invalid');
      expect(uri.scheme, 'https');
    });

    test('a route cannot escape or replace the deployment origin', () {
      final subject = options();
      expect(
        () => subject.resolveRoute('https://evil.example.invalid/api'),
        throwsArgumentError,
      );
      expect(
        () => subject.resolveRoute('//evil.example.invalid/api'),
        throwsArgumentError,
      );
      expect(
        () => subject.resolveRoute('/api/v1/../../secrets'),
        throwsArgumentError,
      );
      expect(
        () => subject.resolveRoute('/api/v1/%2e%2e/secrets'),
        throwsArgumentError,
      );
    });

    test('a discovery document never admits a non-HTTPS origin', () {
      expect(
        () => KumweNativeDiscoveryDocument.fromJson({
          'installation': {
            'reference': 'installation-0001',
            'display_name': 'Example',
          },
          'api': {
            'allowed_origins': ['http://cms.example.invalid'],
            'base_path': '/api/v1',
          },
          'compatibility': <String, Object?>{},
          'authorization': <String, Object?>{},
          'context': <String, Object?>{},
          'limits': <String, Object?>{},
        }),
        throwsA(anything),
      );
    });
  });

  group('context collision', () {
    final origin = Uri.parse('https://cms.example.invalid');
    final credential = KumweCredentialReference('credential-0001');

    test('two organizations under one credential never share a view', () {
      final cache = KumweRuntimeCache<String>();
      final orgA = KumweAuthorityPartition(
        origin: origin,
        site: 'corporate',
        credential: credential,
        organization: 'org-a',
      );
      final orgB = KumweAuthorityPartition(
        origin: origin,
        site: 'corporate',
        credential: credential,
        organization: 'org-b',
      );
      cache.adopt(orgA);
      cache.adopt(orgB);
      cache.write(orgA, 'catalog', 'org-a-catalog');
      expect(cache.read(orgB, 'catalog'), isNull);
      expect(cache.read(orgA, 'catalog'), 'org-a-catalog');
    });

    test('workspaces separate views inside one organization', () {
      final inner = KumweAuthorityPartition(
        origin: origin,
        site: 'corporate',
        credential: credential,
        organization: 'org-a',
        workspace: 'ws-1',
      );
      final other = KumweAuthorityPartition(
        origin: origin,
        site: 'corporate',
        credential: credential,
        organization: 'org-a',
        workspace: 'ws-2',
      );
      expect(inner.scope, isNot(other.scope));
      expect(
        () => KumweAuthorityPartition(
          origin: origin,
          site: 'corporate',
          credential: credential,
          workspace: 'ws-orphan',
        ),
        throwsArgumentError,
        reason: 'a workspace outside an organization is meaningless',
      );
    });
  });

  group('hostile runtime documents', () {
    test('a definition with an absurdly nested schema is refused', () {
      Map<String, Object?> nested(int depth) {
        Map<String, Object?> node = {'type': 'object'};
        for (var level = 0; level < depth; level++) {
          node = {
            'type': 'object',
            'properties': {'child': node},
          };
        }
        return node;
      }

      final definition =
          (jsonDecode(
                    File(
                      'test/business/fixtures/invoice.business-definition.json',
                    ).readAsStringSync(),
                  )
                  as Map)
              .cast<String, Object?>();
      ((definition['fields']! as List<Object?>).first!
          as Map<String, Object?>)['schema'] = nested(
        200,
      );
      expect(
        () => KumweBusinessDefinition.fromJson(definition),
        throwsA(anything),
        reason: 'the frozen JSON boundary caps nesting depth',
      );
    });

    test('an oversized catalog is refused before any entry parses', () {
      expect(
        () => KumweBusinessCatalog.fromJson({
          'data': List<Object?>.filled(257, <String, Object?>{}),
        }),
        throwsFormatException,
      );
    });

    test('Unicode confusables never pass the handle grammar', () {
      // Cyrillic small а (U+0430) beside Latin a.
      expect(KumweBusinessHandles.isHandle('totаl'), isFalse);
      expect(
        () => KumweComparisonFilter('totаl', KumweComparisonOperator.eq, 1),
        throwsArgumentError,
      );
      expect(
        KumweBusinessHandles.isHandle('total​'),
        isFalse,
        reason: 'zero-width characters are out of grammar',
      );
    });

    test('exponent and overflow spellings never pass the decimal grammar', () {
      expect(() => KumweDecimal.parse('1e5'), throwsFormatException);
      expect(() => KumweDecimal.parse('1E5'), throwsFormatException);
      expect(() => KumweDecimal.parse('Infinity'), throwsFormatException);
      expect(() => KumweDecimal.parse('NaN'), throwsFormatException);
      expect(() => KumweDecimal.parse('0x10'), throwsFormatException);
    });
  });

  group('idempotent retry discipline', () {
    test('a changed body can never travel under the old key', () {
      final original = KumweMutationIntent(
        body: KumweJsonValue.from({
          'values': {'total': '100.00'},
        }),
        key: IdempotencyKey('intent-key-0000000001'),
      );
      final tampered = KumweJsonValue.from({
        'values': {'total': '999999.00'},
      });
      expect(original.matches(tampered), isFalse);
      // A new intent over the changed body mints a fresh key by
      // construction; the old key is unreachable from the new bytes.
      final replacement = KumweMutationIntent(body: tampered);
      expect(replacement.key.value, isNot(original.key.value));
    });

    test('an ambiguous timeout settles through the operation ledger, '
        'never a fresh key', () async {
      final intent = KumweMutationIntent(
        body: KumweJsonValue.from({
          'values': {'total': '100.00'},
        }),
        key: IdempotencyKey('intent-key-0000000009'),
        ifMatch: EntityTag.recordVersion(5),
      );
      const outcome =
          KumweMutationOutcome<KumweRecordMutationDocument>.ambiguous();
      expect(outcome.isCommitted, isFalse);
      expect(outcome.result, isNull);
      // The settle read addresses the ledger by the retained key.
      final transport = FakeKumweTransport([
        KumweResponse(
          statusCode: 200,
          headers: HeaderMap({'Content-Type': 'application/json'}),
          body: utf8.encode(
            jsonEncode({
              'operation_id': intent.key.value,
              'state': 'completed',
              'operation': 'business.record.update',
              'created_at': '2026-08-20T10:00:00+00:00',
              'completed_at': '2026-08-20T10:00:01+00:00',
              'expires_at': '2026-09-19T10:00:00+00:00',
              'result': {
                'definition_version': 4,
                'record_id': 'record-0001',
                'version': 6,
                'workflow_state': null,
                'operation': 'update',
                'deleted': false,
                'replayed': false,
              },
            }),
          ),
        ),
      ]);
      final api = KumweBusinessApi(
        options: options(),
        transport: transport,
        registry: registry(),
      );
      final settled = await api.operationStatus(intent.key);
      expect(
        settled.valueOrNull?.asMutation()?.version,
        6,
        reason: 'a served status proves the ambiguous mutation committed',
      );
    });

    test(
      'a stale precondition is a terminal refusal, not a retry loop',
      () async {
        final transport = FakeKumweTransport([
          KumweResponse(
            statusCode: 412,
            headers: HeaderMap({'Content-Type': 'application/problem+json'}),
            body: utf8.encode(
              jsonEncode({
                'type': 'urn:kumwe:problem:precondition-failed',
                'status': 412,
              }),
            ),
          ),
        ]);
        final api = KumweBusinessApi(
          options: options(),
          transport: transport,
          registry: registry(),
        );
        final outcome = await api.update(
          'invoice',
          'record-0001',
          KumweMutationIntent(
            body: KumweJsonValue.from({'values': <String, Object?>{}}),
            ifMatch: EntityTag.recordVersion(3),
          ),
        );
        expect(outcome.disposition, KumweMutationDisposition.refused);
        expect(
          outcome.result?.problemOrNull?.retryClass,
          KumweRetryClass.afterPreconditionRefresh,
          reason: 'the registry directs a re-read, never a blind resend',
        );
      },
    );
  });

  group('diagnostics hygiene', () {
    test('no runtime type ever echoes sentinel secret material', () {
      final sentinel = 'sentinel-secret-material-0001';
      final diagnostics = <String>[
        KumweMutationIntent(
          body: KumweJsonValue.from({
            'values': {'secret': sentinel},
          }),
        ).toString(),
        KumweCursor('$sentinel-cursor').toString(),
        KumweNativeTokenResponse.fromJson({
          'access_token': '$sentinel-access-0000000000000000',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'refresh_token': '$sentinel-refresh-000000000000000',
          'credential': {'reference': 'credential-0001'},
          'context': {'site': 'corporate'},
        }).toString(),
        KumweNativeWebSessionResponse.fromJson({
          'handoff_url':
              'https://cms.example.invalid/native/web-session/$sentinel',
          'expires_in': 60,
        }).toString(),
        KumweAuthorityPartition(
          origin: Uri.parse('https://cms.example.invalid'),
          site: 'corporate',
          credential: KumweCredentialReference(sentinel),
        ).toString(),
      ];
      for (final line in diagnostics) {
        expect(line, isNot(contains(sentinel)));
      }
    });

    test('problem reports never carry detail text into diagnostics', () {
      final problem = KumweProblem.fromResponse(
        KumweResponse(
          statusCode: 422,
          headers: HeaderMap({'Content-Type': 'application/problem+json'}),
          body: utf8.encode(
            jsonEncode({
              'type': 'urn:kumwe:problem:validation-failed',
              'detail': 'The tax number sentinel-tax-0001 is invalid.',
            }),
          ),
        ),
        registry: registry(),
      );
      expect(problem.toString(), isNot(contains('sentinel-tax-0001')));
    });
  });
}
