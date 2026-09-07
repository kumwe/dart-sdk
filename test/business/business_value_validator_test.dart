import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

KumweBusinessDefinition definition({
  bool immutableIssuedOn = false,
  Map<String, Object?>? issuedOnSchema,
}) {
  final source = File(
    'test/business/fixtures/invoice.business-definition.json',
  ).readAsStringSync();
  final decoded = (jsonDecode(source) as Map).cast<String, Object?>();
  for (final field in decoded['fields']! as List<Object?>) {
    final map = field! as Map<String, Object?>;
    if (map['handle'] == 'issued_on') {
      if (immutableIssuedOn) map['immutable_after_create'] = true;
      if (issuedOnSchema != null) map['schema'] = issuedOnSchema;
    }
  }
  return KumweBusinessDefinition.fromJson(decoded);
}

void main() {
  final validator = KumweBusinessValueValidator(definition());

  group('sendable documents', () {
    test('a well-formed create body passes clean', () {
      final violations = validator.validate(
        KumweJsonValue.from({
          'issued_on': '2026-08-25',
          'notes': 'First order.',
        }),
        phase: KumweWritePhase.create,
      );
      expect(violations, isEmpty);
    });

    test('a nullable field accepts an explicit null', () {
      final violations = validator.validate(
        KumweJsonValue.from({'notes': null}),
        phase: KumweWritePhase.update,
      );
      expect(violations, isEmpty);
    });
  });

  group('refused before the wire', () {
    test('an undisclosed field is flagged, not silently dropped', () {
      final violations = validator.validate(
        KumweJsonValue.from({'ghost_field': 1}),
        phase: KumweWritePhase.update,
      );
      expect(violations.single.code, 'undisclosed-field');
      expect(violations.single.field, 'ghost_field');
    });

    test('a read-only field can never be written', () {
      final violations = validator.validate(
        KumweJsonValue.from({'number': 'INV-2026-00099'}),
        phase: KumweWritePhase.create,
      );
      expect(
        violations.map((violation) => violation.code),
        contains('read-only'),
      );
    });

    test('a frozen field is refused on update only', () {
      final frozen = KumweJsonValue.from({'issued_on': '2026-08-25'});
      final frozenValidator = KumweBusinessValueValidator(
        definition(immutableIssuedOn: true),
      );
      expect(
        frozenValidator.validate(frozen, phase: KumweWritePhase.create),
        isEmpty,
      );
      final refused = frozenValidator.validate(
        frozen,
        phase: KumweWritePhase.update,
      );
      expect(refused.single.code, 'immutable-after-create');
      expect(refused.single.field, 'issued_on');
    });

    test('impossible dates are refused through the disclosed field schema', () {
      final refused = validator.validate(
        KumweJsonValue.from({'issued_on': '2025-02-29'}),
        phase: KumweWritePhase.create,
      );
      expect(refused.single.code, 'schema');
      expect(refused.single.field, 'issued_on');
    });

    test('an unevaluable disclosed schema refuses the field safely', () {
      final invalidSchema = KumweBusinessValueValidator(
        definition(issuedOnSchema: {'type': 'string', 'pattern': '['}),
      );
      final refused = invalidSchema.validate(
        KumweJsonValue.from({'issued_on': 'synthetic-private-value'}),
        phase: KumweWritePhase.create,
      );
      expect(refused.single.code, 'schema');
      expect(refused.single.field, 'issued_on');
      expect(
        refused.single.message,
        isNot(contains('synthetic-private-value')),
      );
      expect(refused.single.message, isNot(contains('[')));
    });

    test('a null where none is allowed is refused', () {
      final source =
          (jsonDecode(
                    File(
                      'test/business/fixtures/invoice.business-definition.json',
                    ).readAsStringSync(),
                  )
                  as Map)
              .cast<String, Object?>();
      // Make issued_on writable but non-nullable for this case.
      for (final field in source['fields']! as List<Object?>) {
        final map = field! as Map<String, Object?>;
        if (map['handle'] == 'issued_on') {
          map['nullable'] = false;
          map['schema'] = {'type': 'string', 'format': 'date'};
        }
      }
      final strict = KumweBusinessValueValidator(
        KumweBusinessDefinition.fromJson(source),
      );
      final violations = strict.validate(
        KumweJsonValue.from({'issued_on': null}),
        phase: KumweWritePhase.update,
      );
      expect(violations.single.code, 'null-not-allowed');
    });

    test('a value outside the declared schema fragment is refused', () {
      final violations = validator.validate(
        KumweJsonValue.from({'issued_on': 12345}),
        phase: KumweWritePhase.update,
      );
      expect(violations.map((violation) => violation.code), contains('schema'));
    });

    test('an oversized string is refused by the fragment bound', () {
      final violations = validator.validate(
        KumweJsonValue.from({'notes': 'x' * 2001}),
        phase: KumweWritePhase.update,
      );
      expect(violations.map((violation) => violation.code), contains('schema'));
    });

    test('a non-object values document is a programmer error', () {
      expect(
        () => validator.validate(
          KumweJsonValue.from(<Object?>[1, 2]),
          phase: KumweWritePhase.create,
        ),
        throwsArgumentError,
      );
    });
  });

  group('required-on-create accounting', () {
    test('demands only caller-writable required fields', () {
      final violations = validator.validate(
        KumweJsonValue.from(<String, Object?>{}),
        phase: KumweWritePhase.create,
      );
      // number and total are required but read-only server products;
      // neither may be demanded from the caller.
      expect(
        violations.where((violation) => violation.code == 'required'),
        isEmpty,
      );
    });

    test('a required writable field missing on create is flagged', () {
      final source =
          (jsonDecode(
                    File(
                      'test/business/fixtures/invoice.business-definition.json',
                    ).readAsStringSync(),
                  )
                  as Map)
              .cast<String, Object?>();
      for (final field in source['fields']! as List<Object?>) {
        final map = field! as Map<String, Object?>;
        if (map['handle'] == 'issued_on') {
          map['required'] = true;
        }
      }
      final strict = KumweBusinessValueValidator(
        KumweBusinessDefinition.fromJson(source),
      );
      final violations = strict.validate(
        KumweJsonValue.from(<String, Object?>{}),
        phase: KumweWritePhase.create,
      );
      expect(violations.single.code, 'required');
      expect(violations.single.field, 'issued_on');
    });
  });
}
