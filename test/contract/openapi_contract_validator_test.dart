import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a structurally complete endpoint-neutral contract', () {
    final result = OpenApiContractValidator().validate(
      KumweJsonObject.from(_validContract()),
    );

    expect(result.isValid, isTrue, reason: result.issues.join('\n'));
  });

  test(
    'reports undeclared template parameters and duplicate operation IDs',
    () {
      final document = _validContract();
      final paths = document['paths']! as Map<String, Object?>;
      final first = paths['/things/{id}']! as Map<String, Object?>;
      final get = first['get']! as Map<String, Object?>;
      get.remove('parameters');
      paths['/other'] = <String, Object?>{
        'get': <String, Object?>{
          'operationId': 'readThing',
          'responses': <String, Object?>{
            '200': <String, Object?>{'description': 'Okay'},
          },
        },
      };

      final result = OpenApiContractValidator().validate(
        KumweJsonObject.from(document),
      );

      expect(
        result.issues.map((issue) => issue.message),
        contains('Path template parameter {id} is not declared.'),
      );
      expect(
        result.issues.any(
          (issue) => issue.message.contains('operationId is already used'),
        ),
        isTrue,
      );
    },
  );

  test('reports unresolved local references', () {
    final document = _validContract();
    final paths = document['paths']! as Map<String, Object?>;
    final path = paths['/things/{id}']! as Map<String, Object?>;
    final get = path['get']! as Map<String, Object?>;
    get['responses'] = <String, Object?>{
      '200': <String, Object?>{r'$ref': '#/components/responses/Missing'},
    };

    final result = OpenApiContractValidator().validate(
      KumweJsonObject.from(document),
    );

    expect(
      result.issues.any((issue) => issue.message.contains('does not resolve')),
      isTrue,
    );
  });

  test('requires typed media schemas for response bodies', () {
    final document = _validContract();
    final paths = document['paths']! as Map<String, Object?>;
    final path = paths['/things/{id}']! as Map<String, Object?>;
    final get = path['get']! as Map<String, Object?>;
    final responses = get['responses']! as Map<String, Object?>;
    responses['200'] = <String, Object?>{'description': 'Untyped'};

    final result = OpenApiContractValidator().validate(
      KumweJsonObject.from(document),
    );

    expect(
      result.issues.any((issue) => issue.message.contains('typed content')),
      isTrue,
    );
  });

  test('allows statuses that are intrinsically bodyless', () {
    final document = _validContract();
    final paths = document['paths']! as Map<String, Object?>;
    final path = paths['/things/{id}']! as Map<String, Object?>;
    final get = path['get']! as Map<String, Object?>;
    get['responses'] = <String, Object?>{
      '204': <String, Object?>{'description': 'No content'},
    };

    final result = OpenApiContractValidator().validate(
      KumweJsonObject.from(document),
    );

    expect(result.isValid, isTrue, reason: result.issues.join('\n'));
  });
}

Map<String, Object?> _validContract() {
  return <String, Object?>{
    'openapi': '3.1.0',
    'info': <String, Object?>{'title': 'Example API', 'version': '1.0.0'},
    'paths': <String, Object?>{
      '/things/{id}': <String, Object?>{
        'get': <String, Object?>{
          'operationId': 'readThing',
          'parameters': <Object?>[
            <String, Object?>{
              'name': 'id',
              'in': 'path',
              'required': true,
              'schema': <String, Object?>{'type': 'string'},
            },
          ],
          'responses': <String, Object?>{
            '200': <String, Object?>{
              'description': 'Okay',
              'content': <String, Object?>{
                'application/json': <String, Object?>{
                  'schema': <String, Object?>{
                    r'$ref': '#/components/schemas/Thing',
                  },
                },
              },
            },
          },
        },
      },
    },
    'components': <String, Object?>{
      'schemas': <String, Object?>{
        'Thing': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'id': <String, Object?>{'type': 'string'},
          },
        },
      },
    },
  };
}
