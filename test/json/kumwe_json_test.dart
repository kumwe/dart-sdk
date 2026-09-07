import 'dart:convert';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('KumweJsonValue', () {
    for (final objectNodes in [false, true]) {
      test('depth 128 succeeds and 129 is refused (objects: $objectNodes)', () {
        Object? source = 'leaf';
        for (var depth = 0; depth < 128; depth++) {
          source = objectNodes
              ? <String, Object?>{'child': source}
              : <Object?>[source];
        }
        final encoded = jsonEncode(source);
        expect(KumweJsonValue.from(source).encode(), encoded);
        expect(KumweJsonValue.parse(encoded).encode(), encoded);
        if (objectNodes) {
          expect(
            KumweJsonObject.from(source! as Map<String, Object?>).encode(),
            encoded,
          );
          expect(KumweJsonObject.parse(encoded).encode(), encoded);
        }
        source = objectNodes
            ? <String, Object?>{'child': source}
            : <Object?>[source];
        expect(() => KumweJsonValue.from(source), throwsFormatException);
        expect(
          () => KumweJsonValue.parse(jsonEncode(source)),
          throwsFormatException,
        );
        if (objectNodes) {
          expect(
            () => KumweJsonObject.from(source! as Map<String, Object?>),
            throwsFormatException,
          );
          expect(
            () => KumweJsonObject.parse(jsonEncode(source)),
            throwsFormatException,
          );
        }
      });
    }
    test('deeply freezes object and array values', () {
      final source = <String, Object?>{
        'record': <String, Object?>{
          'lines': <Object?>[1, true, null],
        },
      };

      final value = KumweJsonValue.from(source);
      source['after'] = 'does not leak';

      expect(value.object, isNot(contains('after')));
      final record = value.object['record']! as Map<String, Object?>;
      final lines = record['lines']! as List<Object?>;
      expect(lines, <Object?>[1, true, null]);
      expect(() => record['changed'] = true, throwsUnsupportedError);
      expect(() => lines.add('changed'), throwsUnsupportedError);
    });

    test('rejects values JSON cannot represent exactly', () {
      expect(
        () => KumweJsonValue.from(<Object?, Object?>{1: 'not a JSON key'}),
        throwsFormatException,
      );
      expect(() => KumweJsonValue.from(double.infinity), throwsFormatException);
      expect(
        () => KumweJsonValue.from(DateTime.utc(2026)),
        throwsFormatException,
      );
    });

    test('requires an object when parsing KumweJsonObject', () {
      expect(() => KumweJsonObject.parse('[1, 2]'), throwsFormatException);
      expect(KumweJsonObject.parse('{"ok":true}')['ok'], isTrue);
    });

    test('rejects cyclic containers', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);

      expect(() => KumweJsonValue.from(cyclic), throwsFormatException);
    });
  });
}
