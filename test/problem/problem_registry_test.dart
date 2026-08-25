import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> shippedRegistry() {
    final source = File(
      'contracts/problem-details-registry.proposal.json',
    ).readAsStringSync();
    return (jsonDecode(source) as Map).cast<String, Object?>();
  }

  test('reads the shipped registry proposal as an executable consumer', () {
    final registry = KumweProblemRegistry.fromJson(shippedRegistry());
    expect(registry.typeUriPrefix, 'urn:kumwe:problem:');
    expect(registry.entries.length, 43);

    final validation = registry.resolve('urn:kumwe:problem:validation-failed');
    expect(validation.isRegistered, isTrue);
    expect(validation.retryClass, KumweRetryClass.never);
    expect(validation.entry!.extensionMembers, contains('field_violations'));

    final context = registry.resolve('urn:kumwe:problem:site-context-invalid');
    expect(context.retryClass, KumweRetryClass.afterContextRefresh);
  });

  test('an unregistered code falls back to conservative HTTP semantics', () {
    final registry = KumweProblemRegistry.fromJson(shippedRegistry());
    final unknown = registry.resolve(
      'urn:kumwe:problem:not-a-registered-code',
      httpStatus: 503,
    );
    expect(unknown.code, 'not-a-registered-code');
    expect(unknown.isRegistered, isFalse);
    expect(unknown.retryClass, KumweRetryClass.afterDelay);

    final statusless = registry.resolve(
      'urn:kumwe:problem:not-a-registered-code',
    );
    expect(statusless.retryClass, KumweRetryClass.unspecified);
  });

  test('a foreign type URI resolves without a code', () {
    final registry = KumweProblemRegistry.fromJson(shippedRegistry());
    final foreign = registry.resolve('about:blank', httpStatus: 404);
    expect(foreign.code, isNull);
    expect(foreign.retryClass, KumweRetryClass.never);
  });

  Map<String, Object?> minimal({
    List<Object?>? entries,
    List<Object?>? members,
  }) {
    return {
      'type_uri_prefix': 'urn:kumwe:problem:',
      'retry_classes': ['never', 'after_delay'],
      'extension_members':
          members ??
          [
            {'name': 'request_id', 'value_kind': 'string'},
          ],
      'entries':
          entries ??
          [
            {
              'code': 'example-code',
              'title': 'Example',
              'retry_class': 'never',
            },
          ],
    };
  }

  test('refuses duplicated codes', () {
    final entry = {'code': 'twice', 'title': 'Twice', 'retry_class': 'never'};
    expect(
      () => KumweProblemRegistry.fromJson(minimal(entries: [entry, entry])),
      throwsA(isA<FormatException>()),
    );
  });

  test('refuses an unknown retry class and undeclared extensions', () {
    expect(
      () => KumweProblemRegistry.fromJson(
        minimal(
          entries: [
            {'code': 'bad', 'title': 'Bad', 'retry_class': 'sometimes'},
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => KumweProblemRegistry.fromJson(
        minimal(
          entries: [
            {
              'code': 'bad',
              'title': 'Bad',
              'retry_class': 'never',
              'extensions': ['undeclared_member'],
            },
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('refuses out-of-grammar codes, prefixes and statuses', () {
    expect(
      () => KumweProblemRegistry.fromJson(
        minimal(
          entries: [
            {'code': 'Not-Lower', 'title': 'Bad', 'retry_class': 'never'},
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    final badPrefix = minimal();
    badPrefix['type_uri_prefix'] = 'https://example.invalid/problems#';
    expect(
      () => KumweProblemRegistry.fromJson(badPrefix),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => KumweProblemRegistry.fromJson(
        minimal(
          entries: [
            {
              'code': 'bad-status',
              'title': 'Bad',
              'retry_class': 'never',
              'http_statuses': [99],
            },
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
