import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

final class ThrowingTransport implements KumweTransport {
  const ThrowingTransport();

  @override
  Future<KumweResponse> send(KumweRequest request) async {
    throw const KumweTransportException('The socket died mid-flight.');
  }
}

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
    'bearer-token-000000000000000000000001',
  ),
  requestIdFactory: () => 'request-0000001',
);

KumweBusinessApi api(KumweTransport transport) => KumweBusinessApi(
  options: options(),
  transport: transport,
  registry: registry(),
);

KumweResponse jsonResponse(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) {
  return KumweResponse(
    statusCode: status,
    headers: HeaderMap({'Content-Type': 'application/json', ...headers}),
    body: utf8.encode(jsonEncode(body)),
  );
}

Map<String, Object?> mutationEnvelope({
  int version = 6,
  bool replayed = false,
  String operation = 'update',
}) => {
  'definition_version': 4,
  'record_id': 'record-0001',
  'version': version,
  'workflow_state': null,
  'operation': operation,
  'deleted': false,
  'replayed': replayed,
};

void main() {
  group('request discipline', () {
    test('every call carries bearer, site, correlation and accept', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, {'data': <Object?>[]}),
      ]);
      await api(transport).catalog();
      final request = transport.requests.single;
      expect(request.method, KumweHttpMethod.get);
      expect(request.uri.path, '/api/v1/business/definitions');
      expect(
        request.headers['Authorization'],
        'Bearer bearer-token-000000000000000000000001',
      );
      expect(request.headers['Kumwe-Site'], 'corporate');
      expect(request.headers['X-Request-ID'], 'request-0000001');
      expect(request.headers['Accept'], 'application/json');
      expect(
        request.headers['Idempotency-Key'],
        isNull,
        reason: 'reads carry no mutation identity',
      );
    });

    test('search posts the closed query document without a key', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, {'items': <Object?>[], 'next_cursor': null}),
      ]);
      await api(transport).search('invoice', KumweRecordQuery(pageSize: 10));
      final request = transport.requests.single;
      expect(request.uri.path, '/api/v1/business/records/invoice/search');
      expect(request.headers['Idempotency-Key'], isNull);
      expect((jsonDecode(utf8.decode(request.body)) as Map)['page_size'], 10);
    });

    test('reads project through the observed query-string grammar', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, {
          'definition_version': 4,
          'record_id': 'record-0001',
          'version': 5,
          'workflow_state': null,
          'values': <String, Object?>{},
          'created_at': '2026-08-09T08:00:00+00:00',
          'updated_at': '2026-08-09T08:00:00+00:00',
          'archived_at': null,
          'deleted_at': null,
        }),
      ]);
      await api(transport).read(
        'invoice',
        'record-0001',
        fields: ['number', 'total'],
        includes: ['lines'],
        includeArchived: true,
      );
      final uri = transport.requests.single.uri;
      expect(uri.queryParametersAll['projection[fields][]'], [
        'number',
        'total',
      ]);
      expect(uri.queryParametersAll['projection[includes][]'], ['lines']);
      expect(uri.queryParameters['include_archived'], 'true');
      expect(uri.queryParameters.containsKey('include_deleted'), isFalse);
    });

    test('mutations send the intent bytes under its key and tag', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, mutationEnvelope(), headers: {'ETag': '"v6"'}),
      ]);
      final intent = KumweMutationIntent(
        body: KumweJsonValue.from({
          'values': {'notes': 'updated'},
        }),
        key: IdempotencyKey('intent-key-0000000001'),
        ifMatch: EntityTag.recordVersion(5),
      );
      final outcome = await api(
        transport,
      ).update('invoice', 'record-0001', intent);
      final request = transport.requests.single;
      expect(request.method, KumweHttpMethod.patch);
      expect(request.headers['Idempotency-Key'], 'intent-key-0000000001');
      expect(request.headers['If-Match'], '"v5"');
      expect(request.headers['Content-Type'], 'application/json');
      expect(utf8.decode(request.body), '{"values":{"notes":"updated"}}');
      expect(outcome.disposition, KumweMutationDisposition.applied);
      expect(outcome.result?.valueOrNull?.version, 6);
    });

    test('record identifiers are path-encoded', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, mutationEnvelope(operation: 'delete')),
      ]);
      await api(transport).delete(
        'invoice',
        'record/with spaces',
        key: IdempotencyKey('intent-key-0000000002'),
        ifMatch: EntityTag.recordVersion(2),
      );
      final request = transport.requests.single;
      expect(
        request.uri.path,
        '/api/v1/business/records/invoice/record%2Fwith%20spaces',
      );
      expect(
        request.body,
        isEmpty,
        reason: 'delete travels with an empty body',
      );
    });
  });

  group('client-side guards', () {
    test('a create intent must not carry a precondition', () {
      final preconditioned = KumweMutationIntent(
        body: KumweJsonValue.from({'values': <String, Object?>{}}),
        ifMatch: EntityTag.recordVersion(1),
      );
      expect(
        () =>
            api(FakeKumweTransport(const [])).create('invoice', preconditioned),
        throwsArgumentError,
      );
    });

    test('ledger mutations demand a precondition up front', () {
      final bare = KumweMutationIntent(
        body: KumweJsonValue.from({'values': <String, Object?>{}}),
      );
      expect(
        () => api(FakeKumweTransport(const [])).update('invoice', 'r-1', bare),
        throwsArgumentError,
      );
      expect(
        () => api(
          FakeKumweTransport(const []),
        ).act('invoice', 'r-1', 'issue', bare),
        throwsArgumentError,
      );
    });

    test('out-of-grammar handles never reach the wire', () {
      expect(
        () => api(FakeKumweTransport(const [])).definition('Bad-Handle'),
        throwsArgumentError,
      );
      expect(
        () => api(FakeKumweTransport(const [])).approvals(limit: 101),
        throwsArgumentError,
      );
      expect(
        () => api(
          FakeKumweTransport(const []),
        ).history('invoice', 'r-1', limit: 201),
        throwsArgumentError,
      );
    });
  });

  group('outcome discipline', () {
    test(
      'a replay marker classifies the outcome and matches the body',
      () async {
        final transport = FakeKumweTransport([
          jsonResponse(
            200,
            mutationEnvelope(replayed: true),
            headers: {'Idempotency-Replayed': 'true', 'ETag': '"v6"'},
          ),
        ]);
        final outcome = await api(transport).update(
          'invoice',
          'record-0001',
          KumweMutationIntent(
            body: KumweJsonValue.from({'values': <String, Object?>{}}),
            ifMatch: EntityTag.recordVersion(5),
          ),
        );
        expect(outcome.disposition, KumweMutationDisposition.replayed);
      },
    );

    test(
      'a replay marker that disagrees with the envelope is refused',
      () async {
        final transport = FakeKumweTransport([
          jsonResponse(
            200,
            mutationEnvelope(replayed: false),
            headers: {'Idempotency-Replayed': 'true'},
          ),
        ]);
        await expectLater(
          api(transport).update(
            'invoice',
            'record-0001',
            KumweMutationIntent(
              body: KumweJsonValue.from({'values': <String, Object?>{}}),
              ifMatch: EntityTag.recordVersion(5),
            ),
          ),
          throwsA(isA<KumweProtocolException>()),
        );
      },
    );

    test('an entity tag that disagrees with the envelope is refused', () async {
      final transport = FakeKumweTransport([
        jsonResponse(
          200,
          mutationEnvelope(version: 6),
          headers: {'ETag': '"v7"'},
        ),
      ]);
      await expectLater(
        api(transport).update(
          'invoice',
          'record-0001',
          KumweMutationIntent(
            body: KumweJsonValue.from({'values': <String, Object?>{}}),
            ifMatch: EntityTag.recordVersion(5),
          ),
        ),
        throwsA(isA<KumweProtocolException>()),
      );
    });

    test('a problem refusal becomes a refused outcome with its code', () async {
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
      final outcome = await api(transport).update(
        'invoice',
        'record-0001',
        KumweMutationIntent(
          body: KumweJsonValue.from({'values': <String, Object?>{}}),
          ifMatch: EntityTag.recordVersion(4),
        ),
      );
      expect(outcome.disposition, KumweMutationDisposition.refused);
      expect(
        outcome.result?.problemOrNull?.retryClass,
        KumweRetryClass.afterPreconditionRefresh,
      );
    });

    test(
      'a transport failure mid-mutation is ambiguous, never refused',
      () async {
        final outcome = await api(const ThrowingTransport()).update(
          'invoice',
          'record-0001',
          KumweMutationIntent(
            body: KumweJsonValue.from({'values': <String, Object?>{}}),
            ifMatch: EntityTag.recordVersion(5),
          ),
        );
        expect(outcome.disposition, KumweMutationDisposition.ambiguous);
        expect(outcome.result, isNull);
      },
    );

    test(
      'a read transport failure surfaces as the transport exception',
      () async {
        await expectLater(
          api(const ThrowingTransport()).catalog(),
          throwsA(isA<KumweTransportException>()),
        );
      },
    );
  });

  group('read surfaces', () {
    test('a definition read unwraps its data envelope', () async {
      final definition =
          (jsonDecode(
                    File(
                      'test/business/fixtures/invoice.business-definition.json',
                    ).readAsStringSync(),
                  )
                  as Map)
              .cast<String, Object?>();
      final transport = FakeKumweTransport([
        jsonResponse(200, {'data': definition}),
      ]);
      final result = await api(transport).definition('invoice');
      expect(result.valueOrNull?.handle, 'invoice');
      expect(
        transport.requests.single.uri.path,
        '/api/v1/business/definitions/invoice',
      );
    });

    test('a non-enumerating 404 surfaces as its declared problem', () async {
      final transport = FakeKumweTransport([
        KumweResponse(
          statusCode: 404,
          headers: HeaderMap({'Content-Type': 'application/problem+json'}),
          body: utf8.encode(
            jsonEncode({
              'type': 'urn:kumwe:problem:business-record-not-found',
              'status': 404,
            }),
          ),
        ),
      ]);
      final result = await api(transport).definition('secretive');
      expect(result.isSuccess, isFalse);
      expect(result.problemOrNull?.code, 'business-record-not-found');
    });

    test('an operation status read settles an ambiguous mutation', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, {
          'operation_id': 'intent-key-0000000009',
          'state': 'completed',
          'operation': 'business.record.update',
          'created_at': '2026-08-20T10:00:00+00:00',
          'completed_at': '2026-08-20T10:00:01+00:00',
          'expires_at': '2026-09-19T10:00:00+00:00',
          'result': mutationEnvelope(),
        }),
      ]);
      final result = await api(
        transport,
      ).operationStatus(IdempotencyKey('intent-key-0000000009'));
      expect(
        transport.requests.single.uri.path,
        '/api/v1/business/operations/intent-key-0000000009',
      );
      expect(result.valueOrNull?.asMutation()?.version, 6);
    });

    test('a custom view returns its descriptor and data', () async {
      final transport = FakeKumweTransport([
        jsonResponse(200, {
          'view': {
            'handle': 'aging',
            'label': 'Aging report',
            'kind': 'list',
            'fields': ['number'],
            'filters': <Object?>[],
            'sorts': <Object?>[],
          },
          'data': {'buckets': <Object?>[]},
        }),
      ]);
      final result = await api(transport).customView(
        'invoice',
        'aging',
        parameters: KumweJsonValue.from({'as_at': '2026-08-25'}),
      );
      expect(result.valueOrNull?.kind, KumweViewKind.list);
      expect(result.valueOrNull?.data.object['buckets'], isEmpty);
      final sent =
          jsonDecode(utf8.decode(transport.requests.single.body)) as Map;
      expect((sent['parameters'] as Map)['as_at'], '2026-08-25');
    });

    test(
      'a malformed success body is a protocol violation, not a value',
      () async {
        final transport = FakeKumweTransport([
          jsonResponse(200, {'items': 'not-a-list'}),
        ]);
        await expectLater(
          api(transport).search('invoice', KumweRecordQuery()),
          throwsA(isA<KumweProtocolException>()),
        );
      },
    );
  });

  group('approval flow', () {
    test('a stored approval request reports its location outcome', () async {
      final transport = FakeKumweTransport([
        jsonResponse(201, {
          'required': true,
          'approval_request_id': 'approval-0001',
        }),
      ]);
      final outcome = await api(transport).requestApproval(
        'invoice',
        'record-0001',
        'write_off',
        KumweMutationIntent(
          body: KumweJsonValue.from({
            'input': {'reason': 'Uncollectable.'},
          }),
          ifMatch: EntityTag.recordVersion(5),
        ),
      );
      expect(outcome.disposition, KumweMutationDisposition.applied);
      expect(outcome.result?.valueOrNull?.approvalRequestId, 'approval-0001');
      expect(
        transport.requests.single.uri.path,
        '/api/v1/business/records/invoice/record-0001/actions/write_off'
        '/approval',
      );
    });
  });
}
