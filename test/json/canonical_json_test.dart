import 'dart:convert';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  String canonical(Object? value) =>
      utf8.decode(KumweCanonicalJson.encode(KumweJsonValue.from(value)));

  test('orders object members by UTF-16 code units at every depth', () {
    expect(
      canonical({
        'z': {'b': 1, 'a': 2},
        'a': true,
        'Z': 'upper sorts before lower',
      }),
      '{"Z":"upper sorts before lower","a":true,"z":{"a":2,"b":1}}',
    );
  });

  test('preserves array order and integer decimal forms', () {
    expect(canonical([3, 1, 2, -7, 0]), '[3,1,2,-7,0]');
  });

  test('escapes strings with one fixed vocabulary', () {
    final input =
        '"'
        r'\'
        '\b\t\n\f\r'
        '${String.fromCharCode(7)} plain ré\u{1F600}';
    expect(
      canonical({'k': input}),
      r'{"k":"\"\\\b\t\n\f\r\u0007 plain ré'
      '\u{1F600}"}',
    );
  });

  test('refuses binary floating-point numbers', () {
    expect(() => canonical({'amount': 1.5}), throwsA(isA<FormatException>()));
  });

  test('two key orders of the same document share one digest', () {
    final first = KumweCanonicalJson.sha256Hex(
      KumweJsonValue.from({
        'b': [1, true, null],
        'a': 'x',
        'z': {'k': ''},
      }),
    );
    final second = KumweCanonicalJson.sha256Hex(
      KumweJsonValue.from({
        'z': {'k': ''},
        'a': 'x',
        'b': [1, true, null],
      }),
    );
    expect(first, second);
    expect(
      first,
      '0d3921ae0f584f0604a38511b60776d003f8bfd87a5b56c1bb28b7171c7da490',
    );
  });

  test('encodes the empty object and array exactly', () {
    expect(canonical(<String, Object?>{}), '{}');
    expect(canonical(<Object?>[]), '[]');
  });
}
