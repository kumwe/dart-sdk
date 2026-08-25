import 'dart:convert';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('filter nodes', () {
    test('each node serializes into the closed wire grammar', () {
      expect(
        KumweComparisonFilter(
          'total',
          KumweComparisonOperator.gte,
          '100.00',
        ).toJson(),
        {
          'type': 'comparison',
          'field': 'total',
          'operator': 'gte',
          'value': '100.00',
        },
      );
      expect(
        KumweTextFilter(
          'number',
          KumweTextOperator.startsWith,
          'INV-',
        ).toJson(),
        {
          'type': 'text',
          'field': 'number',
          'operator': 'starts_with',
          'text': 'INV-',
        },
      );
      expect(
        KumweSetFilter('state', ['draft', 'issued'], negated: true).toJson(),
        {
          'type': 'set',
          'field': 'state',
          'values': ['draft', 'issued'],
          'negated': true,
        },
      );
      expect(KumweNullFilter('issued_on').toJson(), {
        'type': 'null',
        'field': 'issued_on',
        'is_null': true,
      });
      expect(
        KumweRelationFilter(
          'lines',
          KumweRelationQuantifier.any,
          KumweNullFilter('description', isNull: false),
        ).toJson(),
        {
          'type': 'relation',
          'relationship': 'lines',
          'quantifier': 'any',
          'target': {'type': 'null', 'field': 'description', 'is_null': false},
        },
      );
      expect(
        KumweBooleanFilter(KumweBooleanOperator.not, [
          KumweNullFilter('issued_on'),
        ]).toJson()['operator'],
        'not',
      );
    });

    test('exact values only: doubles and nulls never enter the tree', () {
      expect(
        () => KumweComparisonFilter('total', KumweComparisonOperator.eq, 19.99),
        throwsArgumentError,
      );
      expect(() => KumweSetFilter('total', [19.99]), throwsArgumentError);
      expect(
        () => KumweComparisonFilter(
          'total',
          KumweComparisonOperator.eq,
          'x' * 4097,
        ),
        throwsArgumentError,
      );
    });

    test('node-local bounds hold', () {
      expect(
        () => KumweTextFilter('number', KumweTextOperator.contains, ''),
        throwsArgumentError,
      );
      expect(
        () => KumweTextFilter('number', KumweTextOperator.contains, 'x' * 513),
        throwsArgumentError,
      );
      expect(() => KumweSetFilter('state', []), throwsArgumentError);
      expect(
        () => KumweSetFilter(
          'state',
          List<Object>.generate(101, (index) => 'v$index'),
        ),
        throwsArgumentError,
      );
      expect(
        () => KumweBooleanFilter(KumweBooleanOperator.not, [
          KumweNullFilter('a'),
          KumweNullFilter('b'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => KumweBooleanFilter(KumweBooleanOperator.all, []),
        throwsArgumentError,
      );
      expect(
        () =>
            KumweComparisonFilter('Bad-Handle', KumweComparisonOperator.eq, 1),
        throwsArgumentError,
      );
    });
  });

  group('query budgets', () {
    test('depth beyond 8 is refused at construction', () {
      KumweRecordFilter tree = KumweNullFilter('leaf');
      for (var level = 0; level < 7; level++) {
        tree = KumweBooleanFilter(KumweBooleanOperator.all, [tree]);
      }
      // Depth 8 passes…
      KumweRecordQuery(filter: tree);
      // …and one more level breaks the budget.
      expect(
        () => KumweRecordQuery(
          filter: KumweBooleanFilter(KumweBooleanOperator.all, [tree]),
        ),
        throwsArgumentError,
      );
    });

    test('more than 64 operations are refused', () {
      final wide = KumweBooleanFilter(KumweBooleanOperator.all, [
        for (var branch = 0; branch < 5; branch++)
          KumweBooleanFilter(KumweBooleanOperator.any, [
            for (var leaf = 0; leaf < 13; leaf++)
              KumweNullFilter('field_${branch}_$leaf'),
          ]),
      ]);
      expect(
        () => KumweRecordQuery(filter: wide),
        throwsArgumentError,
        reason: '1 + 5 + 65 nodes exceed the 64-operation budget',
      );
    });

    test('a third relation hop is refused', () {
      final twoHops = KumweRelationFilter(
        'lines',
        KumweRelationQuantifier.any,
        KumweRelationFilter(
          'product',
          KumweRelationQuantifier.any,
          KumweNullFilter('name', isNull: false),
        ),
      );
      KumweRecordQuery(filter: twoHops);
      expect(
        () => KumweRecordQuery(
          filter: KumweRelationFilter(
            'customer',
            KumweRelationQuantifier.all,
            twoHops,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('page size, sort count and sort repetition are bounded', () {
      expect(() => KumweRecordQuery(pageSize: 0), throwsArgumentError);
      expect(() => KumweRecordQuery(pageSize: 201), throwsArgumentError);
      expect(
        () => KumweRecordQuery(
          sorts: [
            for (var index = 0; index < 6; index++)
              KumweRecordSort('field_$index'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => KumweRecordQuery(
          sorts: [KumweRecordSort('number'), KumweRecordSort('number')],
        ),
        throwsArgumentError,
      );
    });
  });

  group('search, projection and aggregates', () {
    test('search bounds hold', () {
      expect(() => KumweRecordSearch('', ['number']), throwsArgumentError);
      expect(
        () => KumweRecordSearch('x' * 257, ['number']),
        throwsArgumentError,
      );
      expect(() => KumweRecordSearch('term', []), throwsArgumentError);
      expect(
        () => KumweRecordSearch(
          'term',
          List<String>.generate(17, (index) => 'field_$index'),
        ),
        throwsArgumentError,
      );
    });

    test('count omits its field and the rest require one', () {
      expect(
        KumweRecordAggregate(
          'total_count',
          KumweAggregateFunction.count,
        ).toJson(),
        {'alias': 'total_count', 'function': 'count'},
      );
      expect(
        () => KumweRecordAggregate(
          'bad',
          KumweAggregateFunction.count,
          field: 'total',
        ),
        throwsArgumentError,
      );
      expect(
        () => KumweRecordAggregate('bad', KumweAggregateFunction.sum),
        throwsArgumentError,
      );
    });

    test('projection bounds and alias uniqueness hold', () {
      expect(
        () => KumweRecordProjection(
          fields: List<String>.generate(65, (index) => 'field_$index'),
        ),
        throwsArgumentError,
      );
      expect(
        () => KumweRecordProjection(includes: ['a', 'b', 'c', 'd', 'e']),
        throwsArgumentError,
      );
      expect(
        () => KumweRecordProjection(
          aggregates: [
            KumweRecordAggregate('n', KumweAggregateFunction.count),
            KumweRecordAggregate(
              'n',
              KumweAggregateFunction.sum,
              field: 'total',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('whole queries', () {
    test('serializes exactly the members the caller set', () {
      final query = KumweRecordQuery(
        filter: KumweTextFilter('number', KumweTextOperator.startsWith, 'INV-'),
        search: KumweRecordSearch('hosting', ['notes']),
        sorts: [KumweRecordSort('issued_on', descending: true)],
        pageSize: 25,
        projection: KumweRecordProjection(
          fields: ['number', 'total'],
          includes: ['lines'],
          aggregates: [KumweRecordAggregate('n', KumweAggregateFunction.count)],
        ),
        includeArchived: true,
      );
      expect(query.toJson(), {
        'filter': {
          'type': 'text',
          'field': 'number',
          'operator': 'starts_with',
          'text': 'INV-',
        },
        'search': {
          'term': 'hosting',
          'fields': ['notes'],
        },
        'sorts': [
          {'field': 'issued_on', 'direction': 'desc', 'nulls_last': true},
        ],
        'page_size': 25,
        'projection': {
          'fields': ['number', 'total'],
          'includes': ['lines'],
          'aggregates': [
            {'alias': 'n', 'function': 'count'},
          ],
        },
        'include_archived': true,
      });
    });

    test('an empty query is the empty document', () {
      expect(KumweRecordQuery().toJson(), isEmpty);
    });

    test('continueAfter keeps the shape and swaps the cursor', () {
      final query = KumweRecordQuery(pageSize: 10);
      final continued = query.continueAfter(KumweCursor('cursor-a.sig-a'));
      expect(continued.toJson()['after'], 'cursor-a.sig-a');
      expect(continued.pageSize, 10);
      expect(query.after, isNull, reason: 'queries are immutable');
    });

    test('the serialized document is canonicalizable for transport', () {
      final query = KumweRecordQuery(
        filter: KumweComparisonFilter('total', KumweComparisonOperator.gt, '0'),
      );
      final bytes = KumweCanonicalJson.encode(
        KumweJsonValue.from(query.toJson()),
      );
      expect(utf8.decode(bytes), contains('"filter"'));
    });
  });
}
