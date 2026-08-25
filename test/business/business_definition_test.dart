import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture() {
  final source = File(
    'test/business/fixtures/invoice.business-definition.json',
  ).readAsStringSync();
  return (jsonDecode(source) as Map).cast<String, Object?>();
}

void main() {
  group('definition documents', () {
    test('the invoice fixture parses into a complete model', () {
      final definition = KumweBusinessDefinition.fromJson(fixture());
      expect(definition.handle, 'invoice');
      expect(definition.version, 4);
      expect(definition.owner.type, KumweDefinitionOwnerType.extension);
      expect(definition.owner.identifier, 'kumwe.accounting');
      expect(definition.scope, KumweScopeMode.siteOrganization);
      expect(definition.softDelete, isTrue);
      expect(definition.operation, 'read');
      expect(definition.fields.keys, ['number', 'total', 'issued_on', 'notes']);
      expect(definition.views.keys, ['default_list', 'aging']);
      expect(definition.actions.keys, ['issue', 'write_off']);
      expect(definition.relationships.keys, ['lines', 'customer']);
    });

    test('the workflow names its states and initial state', () {
      final workflow = KumweBusinessDefinition.fromJson(fixture()).workflow!;
      expect(workflow.initialState, 'draft');
      expect(workflow.states, hasLength(4));
      expect(workflow.states.last.label, 'Written off');
    });

    test('fields carry the declared type facts and uses', () {
      final fields = KumweBusinessDefinition.fromJson(fixture()).fields;
      final number = fields['number']!;
      expect(number.type, 'core.sequence');
      expect(number.isCoreType, isTrue);
      expect(number.readOnly, isTrue);
      expect(number.immutableAfterCreate, isTrue);
      expect(number.uses.create, isFalse);
      expect(number.uses.sort, isTrue);
      final total = fields['total']!;
      expect(total.valueType, KumweFieldValueType.object);
      expect(
        total.schema.object['properties'],
        isA<Map<String, Object?>>(),
        reason: 'schema fragments survive as frozen JSON',
      );
      final notes = fields['notes']!;
      expect(notes.type, 'acct.legal_note');
      expect(notes.isCoreType, isFalse);
      expect(notes.nullable, isTrue);
      expect(notes.helpText, isNull);
    });

    test('views expose kinds and the custom contract pair', () {
      final views = KumweBusinessDefinition.fromJson(fixture()).views;
      final list = views['default_list']!;
      expect(list.kind, KumweViewKind.list);
      expect(list.custom, isFalse);
      expect(list.customContract, isNull);
      expect(list.fields, ['number', 'total', 'issued_on']);
      final aging = views['aging']!;
      expect(aging.custom, isTrue);
      expect(aging.customContract, isNotNull);
      expect(aging.customContract!.requestSchema.isObject, isTrue);
    });

    test('actions distinguish transitions from custom contracts', () {
      final actions = KumweBusinessDefinition.fromJson(fixture()).actions;
      final issue = actions['issue']!;
      expect(issue.transition, 'issued');
      expect(issue.highImpact, isFalse);
      expect(issue.customContract, isNull);
      final writeOff = actions['write_off']!;
      expect(writeOff.highImpact, isTrue);
      expect(writeOff.customContract, isNotNull);
    });

    test('relationships carry kind, target and ordering', () {
      final relationships = KumweBusinessDefinition.fromJson(
        fixture(),
      ).relationships;
      final lines = relationships['lines']!;
      expect(lines.kind, KumweRelationshipKind.ownedLineCollection);
      expect(lines.target, 'invoice_line');
      expect(lines.ordered, isTrue);
      expect(relationships['customer']!.kind, KumweRelationshipKind.manyToOne);
    });

    test('sections are unmodifiable', () {
      final definition = KumweBusinessDefinition.fromJson(fixture());
      expect(() => definition.fields.remove('number'), throwsUnsupportedError);
    });

    test('refuses drifted identity members', () {
      final badId = fixture();
      badId['id'] = 'not-a-uuid';
      expect(
        () => KumweBusinessDefinition.fromJson(badId),
        throwsFormatException,
      );
      final badChecksum = fixture();
      badChecksum['checksum'] = 'abc';
      expect(
        () => KumweBusinessDefinition.fromJson(badChecksum),
        throwsFormatException,
      );
      final badVersion = fixture();
      badVersion['version'] = 0;
      expect(
        () => KumweBusinessDefinition.fromJson(badVersion),
        throwsFormatException,
      );
    });

    test('refuses out-of-vocabulary enumerations', () {
      final badScope = fixture();
      badScope['scope'] = 'global';
      expect(
        () => KumweBusinessDefinition.fromJson(badScope),
        throwsFormatException,
      );
      final badOwner = fixture();
      (badOwner['owner']! as Map<String, Object?>)['type'] = 'vendor';
      expect(
        () => KumweBusinessDefinition.fromJson(badOwner),
        throwsFormatException,
      );
      final badKind = fixture();
      ((badKind['relationships']! as List<Object?>).first!
              as Map<String, Object?>)['kind'] =
          'linked';
      expect(
        () => KumweBusinessDefinition.fromJson(badKind),
        throwsFormatException,
      );
    });

    test('refuses a workflow whose initial state is undeclared', () {
      final drifted = fixture();
      (drifted['workflow']! as Map<String, Object?>)['initial_state'] = 'ghost';
      expect(
        () => KumweBusinessDefinition.fromJson(drifted),
        throwsFormatException,
      );
    });

    test('refuses a field type outside the core or extension grammar', () {
      final drifted = fixture();
      ((drifted['fields']! as List<Object?>).first!
              as Map<String, Object?>)['type'] =
          'core.hologram';
      expect(
        () => KumweBusinessDefinition.fromJson(drifted),
        throwsFormatException,
      );
      final bare = fixture();
      ((bare['fields']! as List<Object?>).first!
              as Map<String, Object?>)['type'] =
          'plaintype';
      expect(
        () => KumweBusinessDefinition.fromJson(bare),
        throwsFormatException,
      );
    });

    test('refuses duplicated section handles', () {
      final drifted = fixture();
      final fields = drifted['fields']! as List<Object?>;
      fields.add(
        Map<String, Object?>.from(fields.first! as Map<String, Object?>),
      );
      expect(
        () => KumweBusinessDefinition.fromJson(drifted),
        throwsFormatException,
      );
    });
  });

  group('the closed core field vocabulary', () {
    test('holds exactly the 25 observed identifiers', () {
      expect(KumweBusinessHandles.coreFieldTypes, hasLength(25));
      expect(
        KumweBusinessHandles.coreFieldTypes,
        containsAll(['core.uuid', 'core.money', 'core.sequence']),
      );
    });

    test('accepts namespaced extension types and refuses core drift', () {
      expect(KumweBusinessHandles.isFieldType('acct.legal_note'), isTrue);
      expect(KumweBusinessHandles.isFieldType('core.money'), isTrue);
      expect(KumweBusinessHandles.isFieldType('core.new_thing'), isFalse);
      expect(KumweBusinessHandles.isFieldType('NoCaps.here'), isFalse);
      expect(KumweBusinessHandles.isFieldType('bare'), isFalse);
    });
  });

  group('catalogs', () {
    test('an empty catalog is a valid grant-free document', () {
      final catalog = KumweBusinessCatalog.fromJson({'data': <Object?>[]});
      expect(catalog.definitions, isEmpty);
      expect(catalog.definition('invoice'), isNull);
    });

    test('a populated catalog resolves definitions by handle', () {
      final catalog = KumweBusinessCatalog.fromJson({
        'data': [fixture()],
      });
      expect(catalog.definition('invoice')?.version, 4);
      expect(catalog.definition('ghost'), isNull);
    });

    test('refuses duplicated and overflowing catalogs', () {
      expect(
        () => KumweBusinessCatalog.fromJson({
          'data': [fixture(), fixture()],
        }),
        throwsFormatException,
      );
      expect(
        () => KumweBusinessCatalog.fromJson({'data': 'not-a-list'}),
        throwsFormatException,
      );
    });
  });
}
