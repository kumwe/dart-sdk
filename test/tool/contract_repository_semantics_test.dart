import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

import '../../tool/src/contract_repository_semantics.dart';

void main() {
  const validator = ContractRepositorySemanticValidator();

  group('contract index semantics', () {
    test('accepts reciprocal profiles closed over acyclic dependencies', () {
      final result = validator.validateInstance(
        KumweJsonObject.from({
          'profiles': [
            {
              'id': 'desktop',
              'required_requirements': ['CORE-A', 'CORE-B'],
            },
          ],
          'requirements': [
            {
              'id': 'CORE-A',
              'capability_id': 'core.a',
              'required_for': ['desktop'],
              'depends_on': ['CORE-B'],
            },
            {
              'id': 'CORE-B',
              'capability_id': 'core.b',
              'required_for': ['desktop'],
            },
          ],
        }),
        declaredSchema: _contractIndexSchema,
      );

      expect(result.issues, isEmpty);
    });

    test('rejects dangling, asymmetric, cyclic, and non-closed graphs', () {
      final result = validator.validateInstance(
        KumweJsonObject.from({
          'profiles': [
            {
              'id': 'desktop',
              'required_requirements': ['CORE-A'],
            },
          ],
          'requirements': [
            {
              'id': 'CORE-A',
              'capability_id': 'core.a',
              'required_for': <Object?>[],
              'depends_on': ['CORE-B', 'CORE-MISSING'],
            },
            {
              'id': 'CORE-B',
              'capability_id': 'core.duplicate',
              'required_for': ['desktop', 'unknown_profile'],
              'depends_on': ['CORE-A'],
            },
            {
              'id': 'CORE-C',
              'capability_id': 'core.duplicate',
              'required_for': ['desktop'],
            },
          ],
        }),
        declaredSchema: _contractIndexSchema,
      );
      final messages = result.issues.map((issue) => issue.message).toList();

      expect(messages, contains(contains('CORE-MISSING does not resolve')));
      expect(messages, contains(contains('unknown_profile does not resolve')));
      expect(messages, contains(contains('does not list profile desktop')));
      expect(messages, contains(contains('does not list requirement CORE-B')));
      expect(messages, contains(contains('does not list requirement CORE-C')));
      expect(messages, contains(contains('not closed over dependency CORE-B')));
      expect(messages, contains(contains('dependency cycle detected')));
      expect(messages, contains(contains('Capability identifier')));
    });

    test('rejects duplicate profile and requirement identifiers', () {
      final result = validator.validateInstance(
        KumweJsonObject.from({
          'profiles': [
            {'id': 'desktop', 'required_requirements': <Object?>[]},
            {'id': 'desktop', 'required_requirements': <Object?>[]},
          ],
          'requirements': [
            {
              'id': 'CORE-A',
              'capability_id': 'core.a',
              'required_for': <Object?>[],
            },
            {
              'id': 'CORE-A',
              'capability_id': 'core.b',
              'required_for': <Object?>[],
            },
          ],
        }),
        declaredSchema: _contractIndexSchema,
      );

      expect(
        result.issues.map((issue) => issue.message),
        containsAll([
          contains('Profile identifier desktop duplicates'),
          contains('Requirement identifier CORE-A duplicates'),
        ]),
      );
    });
  });

  group('client-surface manifest semantics', () {
    test('accepts unique identifiers and surface-local screen references', () {
      final result = validator.validateInstance(
        KumweJsonObject.from({
          'required_contracts': [
            {'id': 'kumwe.client-surface'},
          ],
          'surfaces': [
            {
              'id': 'acme.orders.admin',
              'navigation': [
                {
                  'id': 'acme.orders.nav.orders',
                  'screen': 'acme.orders.screen.orders',
                },
              ],
              'screens': [
                {'id': 'acme.orders.screen.orders'},
              ],
            },
          ],
        }),
        declaredSchema: _clientSurfaceManifestSchema,
      );

      expect(result.issues, isEmpty);
    });

    test('rejects duplicate identifiers and cross-surface screen links', () {
      final result = validator.validateInstance(
        KumweJsonObject.from({
          'required_contracts': [
            {'id': 'kumwe.client-surface'},
            {'id': 'kumwe.client-surface'},
          ],
          'surfaces': [
            {
              'id': 'acme.surface',
              'navigation': [
                {'id': 'acme.nav', 'screen': 'acme.screen.other'},
              ],
              'screens': [
                {'id': 'acme.screen.local'},
              ],
            },
            {
              'id': 'acme.surface',
              'navigation': [
                {'id': 'acme.nav', 'screen': 'acme.screen.other'},
              ],
              'screens': [
                {'id': 'acme.screen.other'},
                {'id': 'acme.screen.local'},
              ],
            },
          ],
        }),
        declaredSchema: _clientSurfaceManifestSchema,
      );
      final messages = result.issues.map((issue) => issue.message).toList();

      expect(messages, contains(contains('Required contract identifier')));
      expect(messages, contains(contains('Surface identifier')));
      expect(messages, contains(contains('Navigation item identifier')));
      expect(messages, contains(contains('Screen identifier')));
      expect(
        messages,
        contains(contains('does not resolve within its containing surface')),
      );
    });
  });
}

final KumweJsonObject _contractIndexSchema = KumweJsonObject.from({
  'properties': {'profiles': true, 'requirements': true},
  r'$defs': {'profile': true, 'requirement': true},
});

final KumweJsonObject _clientSurfaceManifestSchema = KumweJsonObject.from({
  'properties': {'required_contracts': true, 'surfaces': true},
  r'$defs': {'surface': true, 'navigationItem': true, 'screen': true},
});
