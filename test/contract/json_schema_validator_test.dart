import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  final schemaUri = Uri.parse('file:///contracts/example.schema.json');

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
