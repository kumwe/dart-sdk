import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('static provider validates and redacts its token value', () async {
    final provider = StaticBearerTokenProvider('opaque-token-value');
    final token = await provider.token();

    expect(token.value, 'opaque-token-value');
    expect(token.toString(), isNot(contains('opaque-token-value')));
    expect(
      () => StaticBearerTokenProvider('token with whitespace'),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('token with whitespace')),
        ),
      ),
    );
  });

  test('callback provider validates refreshed credential material', () async {
    final absent = CallbackBearerTokenProvider(() async => null);
    final invalid = CallbackBearerTokenProvider(() async => 'bad token');

    expect(await absent.token(), isNull);
    await expectLater(invalid.token(), throwsArgumentError);
  });
}
