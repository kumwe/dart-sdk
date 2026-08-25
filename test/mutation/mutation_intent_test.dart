import 'dart:convert';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  KumweJsonValue body([String name = 'First']) {
    return KumweJsonValue.parse(
      jsonEncode({
        'values': {'name': name, 'total': '19.99'},
      }),
    );
  }

  group('mutation intents', () {
    test('freezes canonical bytes, digest and key at construction', () {
      final intent = KumweMutationIntent(body: body());
      expect(
        utf8.decode(intent.canonicalBytes),
        '{"values":{"name":"First","total":"19.99"}}',
      );
      expect(intent.bodyDigest, hasLength(64));
      expect(intent.matches(body()), isTrue);
      expect(intent.matches(body('Second')), isFalse);
    });

    test('two intents over one body never share a key by accident', () {
      final first = KumweMutationIntent(body: body());
      final second = KumweMutationIntent(body: body());
      expect(first.key.value, isNot(second.key.value));
      expect(first.bodyDigest, second.bodyDigest);
    });

    test('contributes exactly its key and precondition headers', () {
      final keyed = KumweMutationIntent(
        body: body(),
        key: IdempotencyKey('intent-key-0000000001'),
        ifMatch: EntityTag.recordVersion(7),
      );
      expect(keyed.headers(), {
        'Idempotency-Key': 'intent-key-0000000001',
        'If-Match': '"v7"',
      });
      final bare = KumweMutationIntent(body: body());
      expect(bare.headers().keys, ['Idempotency-Key']);
    });

    test('refuses a body that cannot be canonicalized', () {
      final drifting = KumweJsonValue.parse('{"total": 19.99}');
      expect(() => KumweMutationIntent(body: drifting), throwsFormatException);
    });

    test('a non-canonicalizable candidate never matches', () {
      final intent = KumweMutationIntent(body: body());
      expect(intent.matches(KumweJsonValue.parse('{"total": 19.99}')), isFalse);
    });

    test('diagnostics stay to key and byte count', () {
      final intent = KumweMutationIntent(
        body: body('secret-name-material'),
        key: IdempotencyKey('intent-key-0000000002'),
      );
      expect(intent.toString(), contains('intent-key-0000000002'));
      expect(intent.toString(), isNot(contains('secret-name-material')));
    });
  });

  group('mutation outcomes', () {
    test('a fresh success is applied and committed', () {
      final outcome = KumweMutationOutcome<String>.fromSuccess(
        'record-0001',
        KumweResponseMetadata(statusCode: 201),
      );
      expect(outcome.disposition, KumweMutationDisposition.applied);
      expect(outcome.isCommitted, isTrue);
      expect(outcome.result?.valueOrNull, 'record-0001');
    });

    test('a replay marker classifies the outcome as replayed', () {
      final outcome = KumweMutationOutcome<String>.fromSuccess(
        'record-0001',
        KumweResponseMetadata(statusCode: 200, idempotencyReplayed: true),
      );
      expect(outcome.disposition, KumweMutationDisposition.replayed);
      expect(outcome.isCommitted, isTrue);
    });

    test('a refusal wraps only a problem result', () {
      final problem = KumweProblem.fromResponse(
        KumweResponse(
          statusCode: 409,
          headers: HeaderMap({'Content-Type': 'application/problem+json'}),
          body: utf8.encode(
            jsonEncode({'type': 'urn:kumwe:problem:record-version-conflict'}),
          ),
        ),
        registry: KumweProblemRegistry.fromJson({
          'type_uri_prefix': 'urn:kumwe:problem:',
          'retry_classes': ['never'],
          'entries': [
            {
              'code': 'record-version-conflict',
              'title': 'Record version conflict',
              'retry_class': 'never',
              'http_statuses': [409],
            },
          ],
        }),
      );
      final outcome = KumweMutationOutcome<String>.fromProblem(
        KumweResult<String>.problem(problem),
      );
      expect(outcome.disposition, KumweMutationDisposition.refused);
      expect(outcome.isCommitted, isFalse);
      expect(outcome.result?.problemOrNull?.code, 'record-version-conflict');
      expect(
        () => KumweMutationOutcome<String>.fromProblem(
          KumweResult<String>.success(
            'value',
            KumweResponseMetadata(statusCode: 200),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('an ambiguous outcome keeps no result and is not committed', () {
      const outcome = KumweMutationOutcome<String>.ambiguous();
      expect(outcome.disposition, KumweMutationDisposition.ambiguous);
      expect(outcome.result, isNull);
      expect(outcome.isCommitted, isFalse);
      expect(outcome.toString(), 'KumweMutationOutcome(ambiguous)');
    });
  });
}
