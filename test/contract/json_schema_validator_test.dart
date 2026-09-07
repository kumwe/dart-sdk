import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  final schemaUri = Uri.parse('file:///contracts/example.schema.json');

  test('date formats refuse normalized impossible Gregorian dates', () {
    const validDates = [
      '0000-02-29',
      '1900-02-28',
      '2000-02-29',
      '2024-02-29',
      '2026-04-30',
      '9999-12-31',
    ];
    const invalidDates = [
      '1900-02-29',
      '2000-02-30',
      '2025-02-29',
      '2026-04-31',
      '2026-06-31',
      '2026-00-01',
      '2026-13-01',
      '2026-01-00',
      '2026-01-32',
    ];
    for (final format in ['date', 'date-time']) {
      final schema = KumweJsonObject.from({'type': 'string', 'format': format});
      for (final date in [...validDates, ...invalidDates]) {
        for (final suffix
            in format == 'date'
                ? ['']
                : ['T00:00:00Z', 'T23:30:00-05:30', 'T00:30:00+05:30']) {
          final result = const JsonSchemaContractValidator().validateInstance(
            KumweJsonValue.from('$date$suffix'),
            schema: schema,
            schemaUri: schemaUri,
          );
          expect(
            result.isValid,
            validDates.contains(date),
            reason: '$format: $date$suffix',
          );
        }
      }
    }
  });

  test(
    'dependentSchemas applies to the whole object only when its key exists',
    () {
      final schema = KumweJsonObject.from({
        'type': 'object',
        'properties': {'a': true, 'b': true, 'forbidden': true},
        'additionalProperties': false,
        'dependentSchemas': {
          'a': {
            'required': ['b'],
          },
          'forbidden': false,
        },
      });
      for (final (value, valid) in <(Map<String, Object?>, bool)>[
        ({}, true),
        ({'b': 1}, true),
        ({'a': 1, 'b': 2}, true),
        ({'a': 1}, false),
        ({'a': null}, false),
        ({'forbidden': null}, false),
      ]) {
        final result = const JsonSchemaContractValidator().validateInstance(
          KumweJsonValue.from(value),
          schema: schema,
          schemaUri: schemaUri,
        );
        expect(result.isValid, valid, reason: value.toString());
      }
    },
  );

  test('validates bounded schema structure and local references', () {
    final schema = KumweJsonObject.from(_schema());
    final catalog = JsonSchemaCatalog()..add(schemaUri, schema);

    final result = JsonSchemaContractValidator(
      catalog,
    ).validateSchema(schema, documentUri: schemaUri);

    expect(result.isValid, isTrue, reason: result.issues.join('\n'));
  });

  test('reports unbounded strings and unresolved references', () {
    final schema = _schema();
    final definitions = schema[r'$defs']! as Map<String, Object?>;
    definitions['label'] = <String, Object?>{'type': 'string'};
    final properties = schema['properties']! as Map<String, Object?>;
    properties['missing'] = <String, Object?>{r'$ref': r'#/$defs/missing'};
    final document = KumweJsonObject.from(schema);
    final catalog = JsonSchemaCatalog()..add(schemaUri, document);

    final result = JsonSchemaContractValidator(
      catalog,
    ).validateSchema(document, documentUri: schemaUri);

    expect(
      result.issues.any((issue) => issue.message.contains('finite maxLength')),
      isTrue,
    );
    expect(
      result.issues.any((issue) => issue.message.contains('does not resolve')),
      isTrue,
    );
  });

  test('validates instances including if/then and boolean schemas', () {
    final schema = KumweJsonObject.from(_schema());
    final catalog = JsonSchemaCatalog()..add(schemaUri, schema);
    final validator = JsonSchemaContractValidator(catalog);

    final valid = validator.validateInstance(
      KumweJsonValue.from({'kind': 'open', 'label': 'Example'}),
      schema: schema,
      schemaUri: schemaUri,
    );
    final invalid = validator.validateInstance(
      KumweJsonValue.from({'kind': 'locked', 'label': 'Forbidden'}),
      schema: schema,
      schemaUri: schemaUri,
    );

    expect(valid.isValid, isTrue, reason: valid.issues.join('\n'));
    expect(
      invalid.issues.any((issue) => issue.message.contains('forbidden')),
      isTrue,
    );
  });
}

Map<String, Object?> _schema() {
  return <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': 'urn:example:bounded-schema:1',
    'type': 'object',
    'additionalProperties': false,
    'required': <Object?>['kind'],
    'properties': <String, Object?>{
      'kind': <String, Object?>{
        'enum': <Object?>['open', 'locked'],
      },
      'label': <String, Object?>{r'$ref': r'#/$defs/label'},
    },
    'allOf': <Object?>[
      <String, Object?>{
        'if': <String, Object?>{
          'properties': <String, Object?>{
            'kind': <String, Object?>{'const': 'locked'},
          },
        },
        'then': <String, Object?>{
          'properties': <String, Object?>{'label': false},
        },
      },
    ],
    r'$defs': <String, Object?>{
      'label': <String, Object?>{
        'type': 'string',
        'minLength': 1,
        'maxLength': 80,
      },
    },
  };
}
