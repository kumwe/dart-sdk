import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

KumweResponse _response(int statusCode, [Map<String, String>? headers]) {
  return KumweResponse(
    statusCode: statusCode,
    headers: HeaderMap(headers ?? const {}),
  );
}

void main() {
  const classifier = KumweRetryClassifier();

  test('classifies transient statuses as retryable after a delay', () {
    for (final status in [408, 425, 429, 502, 503, 504]) {
      expect(
        classifier.classify(_response(status)),
        KumweRetryClass.afterDelay,
        reason: '$status',
      );
    }
  });

  test('classifies deterministic client failures as never retryable', () {
    for (final status in [400, 403, 404, 405, 413, 422]) {
      expect(
        classifier.classify(_response(status)),
        KumweRetryClass.never,
        reason: '$status',
      );
    }
  });

  test('routes authentication and precondition failures to their remedies', () {
    expect(
      classifier.classify(_response(401)),
      KumweRetryClass.afterReauthentication,
    );
    expect(
      classifier.classify(_response(412)),
      KumweRetryClass.afterPreconditionRefresh,
    );
    expect(
      classifier.classify(_response(428)),
      KumweRetryClass.afterPreconditionRefresh,
    );
  });

  test('leaves ambiguous statuses unspecified rather than guessing', () {
    expect(classifier.classify(_response(409)), KumweRetryClass.unspecified);
    expect(classifier.classify(_response(500)), KumweRetryClass.unspecified);
    expect(classifier.classify(_response(418)), KumweRetryClass.unspecified);
  });

  test('reads only well-formed delta-seconds Retry-After values', () {
    expect(
      classifier.retryAfter(_response(503, {'Retry-After': '30'})),
      const Duration(seconds: 30),
    );
    expect(
      classifier.retryAfter(_response(503, {'retry-after': '0'})),
      Duration.zero,
    );
    expect(classifier.retryAfter(_response(503)), isNull);
    expect(
      classifier.retryAfter(
        _response(503, {'Retry-After': 'Fri, 15 Aug 2026 12:00:00 GMT'}),
      ),
      isNull,
    );
    expect(
      classifier.retryAfter(_response(503, {'Retry-After': '-1'})),
      isNull,
    );
    expect(
      classifier.retryAfter(_response(503, {'Retry-After': '1000000000'})),
      isNull,
    );
  });
}
