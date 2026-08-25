import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  KumweProblemRegistry registry() {
    final source = File(
      'contracts/problem-details-registry.proposal.json',
    ).readAsStringSync();
    return KumweProblemRegistry.fromJson(
      (jsonDecode(source) as Map).cast<String, Object?>(),
    );
  }

  KumweResponse problemResponse(
    int status,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) {
    return KumweResponse(
      statusCode: status,
      headers: HeaderMap({
        'Content-Type': 'application/problem+json',
        ...headers,
      }),
      body: utf8.encode(jsonEncode(body)),
    );
  }

  group('response metadata', () {
    test('extracts status, correlation, entity tag and replay marker', () {
      final metadata = KumweResponseMetadata.fromResponse(
        KumweResponse(
          statusCode: 200,
          headers: HeaderMap({
            'X-Request-Id': 'request-0000001',
            'ETag': '"v7"',
            'Idempotency-Replayed': 'true',
          }),
        ),
      );
      expect(metadata.statusCode, 200);
      expect(metadata.requestId, 'request-0000001');
      expect(metadata.etag, '"v7"');
      expect(metadata.idempotencyReplayed, isTrue);
    });

    test('drops an out-of-grammar correlation identifier', () {
      final metadata = KumweResponseMetadata.fromResponse(
        KumweResponse(
          statusCode: 200,
          headers: HeaderMap({'X-Request-Id': 'bad id with spaces'}),
        ),
      );
      expect(metadata.requestId, isNull);
      expect(metadata.idempotencyReplayed, isFalse);
    });

    test('validates constructed metadata bounds', () {
      expect(() => KumweResponseMetadata(statusCode: 99), throwsArgumentError);
      expect(
        () => KumweResponseMetadata(statusCode: 200, requestId: 'short'),
        throwsArgumentError,
      );
    });
  });

  group('sealed results', () {
    const metadataFree = KumweUnsupportedResult<int>(
      KumweUnsupportedReason.contractNotAdopted,
    );

    test('success carries its value and metadata through map', () {
      final result = KumweResult<int>.success(
        21,
        KumweResponseMetadata(statusCode: 200),
      );
      final doubled = result.map((value) => value * 2);
      expect(doubled.valueOrNull, 42);
      expect(doubled.isSuccess, isTrue);
      expect(doubled.problemOrNull, isNull);
      expect((doubled as KumweValueResult<int>).metadata.statusCode, 200);
    });

    test('problem outcomes preserve the report through map', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(422, {
          'type': 'urn:kumwe:problem:validation-failed',
          'status': 422,
        }),
        registry: registry(),
      );
      final result = KumweResult<int>.problem(problem).map((value) => value);
      expect(result.isSuccess, isFalse);
      expect(result.valueOrNull, isNull);
      expect(result.problemOrNull?.code, 'validation-failed');
    });

    test('unsupported outcomes preserve their reason through map', () {
      final mapped = metadataFree.map((value) => '$value');
      expect(mapped, isA<KumweUnsupportedResult<String>>());
      expect(
        (mapped as KumweUnsupportedResult<String>).reason,
        KumweUnsupportedReason.contractNotAdopted,
      );
    });
  });

  group('problem reports', () {
    test('a registered code carries only its declared extensions', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(422, {
          'type': 'urn:kumwe:problem:validation-failed',
          'title': 'Validation failed',
          'detail': 'Two fields are invalid.',
          'request_id': 'request-0000002',
          'field_violations': [
            {'field': 'name', 'code': 'required'},
            {'field': 'lines[0].total', 'code': 'exact-value', 'message': 'x'},
          ],
          'retry_after_seconds': 30,
        }),
        registry: registry(),
      );
      expect(problem.code, 'validation-failed');
      expect(problem.retryClass, KumweRetryClass.never);
      expect(problem.requestId, 'request-0000002');
      expect(problem.fieldViolations, hasLength(2));
      expect(problem.fieldViolations.first.field, 'name');
      expect(
        problem.retryAfter,
        isNull,
        reason: 'validation-failed does not declare retry_after_seconds',
      );
    });

    test('a declared retry delay survives without the header', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(429, {
          'type': 'urn:kumwe:problem:authentication-throttled',
          'retry_after_seconds': 900,
        }),
        registry: registry(),
      );
      expect(problem.code, 'authentication-throttled');
      expect(problem.retryClass, KumweRetryClass.afterDelay);
      expect(problem.retryAfter, const Duration(minutes: 15));
    });

    test('the Retry-After header outranks the body copy', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(
          429,
          {
            'type': 'urn:kumwe:problem:authentication-throttled',
            'retry_after_seconds': 900,
          },
          headers: {'Retry-After': '60'},
        ),
        registry: registry(),
      );
      expect(problem.retryAfter, const Duration(seconds: 60));
    });

    test('precondition failures expose declared version evidence', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(412, {
          'type': 'urn:kumwe:problem:precondition-failed',
          'expected_version': 'v3',
          'actual_version': 'v5',
        }),
        registry: registry(),
      );
      expect(problem.code, 'precondition-failed');
      expect(problem.retryClass, KumweRetryClass.afterPreconditionRefresh);
      expect(problem.expectedVersion, 'v3');
      expect(problem.actualVersion, 'v5');
    });

    test('an unregistered code is classified by status alone', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(503, {
          'type': 'urn:kumwe:problem:brand-new-code',
          'expected_version': 'v3',
        }),
        registry: registry(),
      );
      expect(problem.code, isNull);
      expect(problem.retryClass, KumweRetryClass.afterDelay);
      expect(
        problem.expectedVersion,
        isNull,
        reason: 'undeclared extensions never cross the boundary',
      );
    });

    test('a non-problem body still produces a status-classified report', () {
      final problem = KumweProblem.fromResponse(
        KumweResponse(statusCode: 404),
        registry: registry(),
      );
      expect(problem.code, isNull);
      expect(problem.typeUri, 'about:blank');
      expect(problem.retryClass, KumweRetryClass.never);
    });

    test('malformed field violations degrade to none, not to a throw', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(422, {
          'type': 'urn:kumwe:problem:validation-failed',
          'field_violations': [
            {'field': 'ok', 'code': 'required'},
            {'field': 42, 'code': 'required'},
          ],
        }),
        registry: registry(),
      );
      expect(problem.fieldViolations, isEmpty);
    });

    test('diagnostics never include detail text', () {
      final problem = KumweProblem.fromResponse(
        problemResponse(422, {
          'type': 'urn:kumwe:problem:validation-failed',
          'detail': 'sentinel-secret-value',
        }),
        registry: registry(),
      );
      expect(problem.toString(), isNot(contains('sentinel-secret-value')));
      expect(problem.toString(), contains('validation-failed'));
    });
  });
}
