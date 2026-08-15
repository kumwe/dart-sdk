import 'dart:convert';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('parses RFC 9457 members and preserves extensions immutably', () {
    final response = KumweResponse(
      statusCode: 409,
      headers: HeaderMap({
        'Content-Type': 'application/problem+json; charset=utf-8',
        'X-Request-ID': 'server-request-0001',
      }),
      body: utf8.encode(
        jsonEncode({
          'type': 'urn:kumwe:problem:conflict',
          'title': 'Conflict',
          'status': 409,
          'detail': 'The record changed.',
          'instance': '/api/v1/content/example',
          'request_id': 'body-request-0001',
          'errors': <Object?>['revision'],
        }),
      ),
    );

    final problem = ProblemDetails.tryParse(response)!;
    final exception = KumweApiException.fromResponse(response);

    expect(problem.type, 'urn:kumwe:problem:conflict');
    expect(problem.status, 409);
    expect(problem.requestId, 'body-request-0001');
    expect(() => problem.extensions['changed'] = true, throwsUnsupportedError);
    expect(exception.requestId, 'server-request-0001');
    expect(exception.toString(), isNot(contains('The record changed.')));
    expect(exception.toString(), contains('server-request-0001'));
  });

  test('does not reinterpret malformed or non-problem JSON', () {
    final wrongType = KumweResponse(
      statusCode: 400,
      headers: HeaderMap({'Content-Type': 'application/json'}),
      body: utf8.encode('{"status":400}'),
    );
    final malformed = KumweResponse(
      statusCode: 400,
      headers: HeaderMap({'Content-Type': 'application/problem+json'}),
      body: utf8.encode('{"status":"400"}'),
    );

    expect(ProblemDetails.tryParse(wrongType), isNull);
    expect(ProblemDetails.tryParse(malformed), isNull);
  });

  test('does not expose an unsafe body correlation value', () {
    final problem = ProblemDetails.fromJson({
      'type': 'about:blank',
      'request_id': 'unsafe\nvalue',
    });

    expect(problem.requestId, isNull);
  });
}
