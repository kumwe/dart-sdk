import 'dart:convert';

import '../collection/kumwe_page.dart';
import 'business_definition.dart';

/// Comparison operators the record query grammar declares.
enum KumweComparisonOperator {
  /// Equal.
  eq('eq'),

  /// Not equal.
  ne('ne'),

  /// Less than.
  lt('lt'),

  /// Less than or equal.
  lte('lte'),

  /// Greater than.
  gt('gt'),

  /// Greater than or equal.
  gte('gte');

  const KumweComparisonOperator(this.wireName);

  /// Exact wire spelling.
  final String wireName;
}

/// Text operators the record query grammar declares.
enum KumweTextOperator {
  /// Substring match.
  contains('contains'),

  /// Prefix match.
  startsWith('starts_with'),

  /// Suffix match.
  endsWith('ends_with');

  const KumweTextOperator(this.wireName);

  /// Exact wire spelling.
  final String wireName;
}

/// Boolean group operators the record query grammar declares.
enum KumweBooleanOperator {
  /// Every child must match.
  all('all'),

  /// Any child may match.
  any('any'),

  /// The single child must not match.
  not('not');

  const KumweBooleanOperator(this.wireName);

  /// Exact wire spelling.
  final String wireName;
}

/// Relation quantifiers the record query grammar declares.
enum KumweRelationQuantifier {
  /// At least one related record matches.
  any('any'),

  /// No related record matches.
  none('none'),

  /// Every related record matches.
  all('all');

  const KumweRelationQuantifier(this.wireName);

  /// Exact wire spelling.
  final String wireName;
}

/// Aggregate functions the record query grammar declares.
enum KumweAggregateFunction {
  /// Row count; must not name a field.
  count('count'),

  /// Exact sum; must name a field.
  sum('sum'),

  /// Minimum; must name a field.
  min('min'),

  /// Maximum; must name a field.
  max('max'),

  /// Average; must name a field.
  avg('avg');

  const KumweAggregateFunction(this.wireName);

  /// Exact wire spelling.
  final String wireName;
}

/// One node of a record filter tree.
///
/// Every node validates its own bounds at construction; whole-tree budgets
/// (depth, operation count, relation hops) are enforced by [KumweRecordQuery]
/// so an over-budget tree is refused before it is ever serialized.
sealed class KumweRecordFilter {
  const KumweRecordFilter();

  /// Serializes the node into the closed wire grammar.
  Map<String, Object?> toJson();
}

/// `field <op> value` over one filterable field.
final class KumweComparisonFilter extends KumweRecordFilter {
  /// Validates a comparison node.
  ///
  /// [value] must be a `bool`, `int` or bounded `String`; a `double` is
  /// refused because the wire carries exact values as strings, and `null`
  /// is refused because null tests use [KumweNullFilter].
  factory KumweComparisonFilter(
    String field,
    KumweComparisonOperator operator,
    Object value,
  ) {
    _requireHandle(field, 'field');
    _requireQueryValue(value);
    return KumweComparisonFilter._(field, operator, value);
  }

  const KumweComparisonFilter._(this.field, this.operator, this.value);

  /// Field handle under comparison.
  final String field;

  /// Declared operator.
  final KumweComparisonOperator operator;

  /// Exact comparison value.
  final Object value;

  @override
  Map<String, Object?> toJson() => {
    'type': 'comparison',
    'field': field,
    'operator': operator.wireName,
    'value': value,
  };
}

/// Substring/prefix/suffix text match over one field.
final class KumweTextFilter extends KumweRecordFilter {
  /// Validates a text node; [text] needs 1 to 512 Unicode code points,
  /// counted the way core counts them.
  factory KumweTextFilter(
    String field,
    KumweTextOperator operator,
    String text,
  ) {
    _requireHandle(field, 'field');
    if (text.isEmpty || text.runes.length > 512) {
      throw ArgumentError.value(
        '<text>',
        'text',
        'Text filters need 1 to 512 characters.',
      );
    }
    return KumweTextFilter._(field, operator, text);
  }

  const KumweTextFilter._(this.field, this.operator, this.text);

  /// Field handle under match.
  final String field;

  /// Declared operator.
  final KumweTextOperator operator;

  /// Match text.
  final String text;

  @override
  Map<String, Object?> toJson() => {
    'type': 'text',
    'field': field,
    'operator': operator.wireName,
    'text': text,
  };
}

/// Set membership over one field.
final class KumweSetFilter extends KumweRecordFilter {
  /// Validates a set node; 1 to 100 non-null exact values.
  factory KumweSetFilter(
    String field,
    List<Object> values, {
    bool negated = false,
  }) {
    _requireHandle(field, 'field');
    if (values.isEmpty || values.length > 100) {
      throw ArgumentError.value(
        values.length,
        'values',
        'Set filters need 1 to 100 values.',
      );
    }
    for (final value in values) {
      _requireQueryValue(value);
    }
    return KumweSetFilter._(List<Object>.unmodifiable(values), field, negated);
  }

  const KumweSetFilter._(this.values, this.field, this.negated);

  /// Field handle under membership test.
  final String field;

  /// Exact member values.
  final List<Object> values;

  /// Whether membership is negated.
  final bool negated;

  @override
  Map<String, Object?> toJson() => {
    'type': 'set',
    'field': field,
    'values': values,
    if (negated) 'negated': true,
  };
}

/// Null test over one nullable field.
final class KumweNullFilter extends KumweRecordFilter {
  /// Validates a null-test node.
  factory KumweNullFilter(String field, {bool isNull = true}) {
    _requireHandle(field, 'field');
    return KumweNullFilter._(field, isNull);
  }

  const KumweNullFilter._(this.field, this.isNull);

  /// Field handle under test.
  final String field;

  /// Whether the field must be null (`true`) or non-null (`false`).
  final bool isNull;

  @override
  Map<String, Object?> toJson() => {
    'type': 'null',
    'field': field,
    'is_null': isNull,
  };
}

/// Boolean combination of child filters.
final class KumweBooleanFilter extends KumweRecordFilter {
  /// Validates a boolean group; 1 to 16 children, `not` exactly one.
  factory KumweBooleanFilter(
    KumweBooleanOperator operator,
    List<KumweRecordFilter> children,
  ) {
    if (children.isEmpty || children.length > 16) {
      throw ArgumentError.value(
        children.length,
        'children',
        'Boolean groups need 1 to 16 children.',
      );
    }
    if (operator == KumweBooleanOperator.not && children.length != 1) {
      throw ArgumentError.value(
        children.length,
        'children',
        'A not-group takes exactly one child.',
      );
    }
    return KumweBooleanFilter._(
      operator,
      List<KumweRecordFilter>.unmodifiable(children),
    );
  }

  const KumweBooleanFilter._(this.operator, this.children);

  /// Declared operator.
  final KumweBooleanOperator operator;

  /// Child nodes.
  final List<KumweRecordFilter> children;

  @override
  Map<String, Object?> toJson() => {
    'type': 'boolean',
    'operator': operator.wireName,
    'children': [for (final child in children) child.toJson()],
  };
}

/// Quantified filter over a declared relationship.
final class KumweRelationFilter extends KumweRecordFilter {
  /// Validates a relation node.
  factory KumweRelationFilter(
    String relationship,
    KumweRelationQuantifier quantifier,
    KumweRecordFilter target,
  ) {
    _requireHandle(relationship, 'relationship');
    return KumweRelationFilter._(relationship, quantifier, target);
  }

  const KumweRelationFilter._(this.relationship, this.quantifier, this.target);

  /// Relationship handle under quantification.
  final String relationship;

  /// Declared quantifier.
  final KumweRelationQuantifier quantifier;

  /// Filter applied to related records.
  final KumweRecordFilter target;

  @override
  Map<String, Object?> toJson() => {
    'type': 'relation',
    'relationship': relationship,
    'quantifier': quantifier.wireName,
    'target': target.toJson(),
  };
}

/// One sort clause of a record query.
final class KumweRecordSort {
  /// Validates a sort clause.
  factory KumweRecordSort(
    String field, {
    bool descending = false,
    bool nullsLast = true,
  }) {
    _requireHandle(field, 'field');
    return KumweRecordSort._(field, descending, nullsLast);
  }

  const KumweRecordSort._(this.field, this.descending, this.nullsLast);

  /// Field handle to sort by.
  final String field;

  /// Whether the sort runs descending.
  final bool descending;

  /// Whether null values sort last.
  final bool nullsLast;

  /// Serializes the clause into the closed wire grammar.
  Map<String, Object?> toJson() => {
    'field': field,
    'direction': descending ? 'desc' : 'asc',
    'nulls_last': nullsLast,
  };
}

/// Full-text search over declared searchable fields.
final class KumweRecordSearch {
  /// Validates a search clause; the term needs 1 to 256 non-blank Unicode
  /// code points and 1 to 16 fields.
  factory KumweRecordSearch(String term, List<String> fields) {
    if (term.trim().isEmpty || term.runes.length > 256) {
      throw ArgumentError.value(
        '<term>',
        'term',
        'Search terms need 1 to 256 non-blank code points.',
      );
    }
    if (fields.isEmpty || fields.length > 16) {
      throw ArgumentError.value(
        fields.length,
        'fields',
        'Searches name 1 to 16 fields.',
      );
    }
    for (final field in fields) {
      _requireHandle(field, 'fields');
    }
    return KumweRecordSearch._(term, List<String>.unmodifiable(fields));
  }

  const KumweRecordSearch._(this.term, this.fields);

  /// Search term.
  final String term;

  /// Field handles searched.
  final List<String> fields;

  /// Serializes the clause into the closed wire grammar.
  Map<String, Object?> toJson() => {'term': term, 'fields': fields};
}

/// One aggregate request of a record query.
final class KumweRecordAggregate {
  /// Validates an aggregate; `count` must omit [field], the rest need one.
  factory KumweRecordAggregate(
    String alias,
    KumweAggregateFunction function, {
    String? field,
  }) {
    _requireHandle(alias, 'alias');
    if (function == KumweAggregateFunction.count) {
      if (field != null) {
        throw ArgumentError.value(
          field,
          'field',
          'A count aggregate must not name a field.',
        );
      }
    } else {
      if (field == null) {
        throw ArgumentError.value(
          null,
          'field',
          'A ${function.wireName} aggregate must name a field.',
        );
      }
      _requireHandle(field, 'field');
    }
    return KumweRecordAggregate._(alias, function, field);
  }

  const KumweRecordAggregate._(this.alias, this.function, this.field);

  /// Result alias.
  final String alias;

  /// Declared function.
  final KumweAggregateFunction function;

  /// Field the function runs over; `null` only for count.
  final String? field;

  /// Serializes the aggregate into the closed wire grammar.
  Map<String, Object?> toJson() => {
    'alias': alias,
    'function': function.wireName,
    if (field != null) 'field': field,
  };
}

/// Field, include and aggregate projection of a record query.
final class KumweRecordProjection {
  /// Validates a projection: ≤64 fields, ≤4 includes, ≤16 aggregates with
  /// unique aliases.
  factory KumweRecordProjection({
    List<String> fields = const [],
    List<String> includes = const [],
    List<KumweRecordAggregate> aggregates = const [],
  }) {
    if (fields.length > 64) {
      throw ArgumentError.value(
        fields.length,
        'fields',
        'Projections name at most 64 fields.',
      );
    }
    for (final field in fields) {
      _requireHandle(field, 'fields');
    }
    if (includes.length > 4) {
      throw ArgumentError.value(
        includes.length,
        'includes',
        'Projections include at most 4 relationships.',
      );
    }
    for (final include in includes) {
      _requireHandle(include, 'includes');
    }
    if (aggregates.length > 16) {
      throw ArgumentError.value(
        aggregates.length,
        'aggregates',
        'Projections request at most 16 aggregates.',
      );
    }
    final aliases = <String>{};
    for (final aggregate in aggregates) {
      if (!aliases.add(aggregate.alias)) {
        throw ArgumentError.value(
          aggregate.alias,
          'aggregates',
          'Aggregate aliases must be unique.',
        );
      }
    }
    return KumweRecordProjection._(
      List<String>.unmodifiable(fields),
      List<String>.unmodifiable(includes),
      List<KumweRecordAggregate>.unmodifiable(aggregates),
    );
  }

  const KumweRecordProjection._(this.fields, this.includes, this.aggregates);

  /// Field handles to project; empty means the server default.
  final List<String> fields;

  /// Relationship handles to include.
  final List<String> includes;

  /// Requested aggregates.
  final List<KumweRecordAggregate> aggregates;

  /// Whether the projection asks for anything.
  bool get isEmpty => fields.isEmpty && includes.isEmpty && aggregates.isEmpty;

  /// Serializes the projection into the closed wire grammar.
  Map<String, Object?> toJson() => {
    if (fields.isNotEmpty) 'fields': fields,
    if (includes.isNotEmpty) 'includes': includes,
    if (aggregates.isNotEmpty)
      'aggregates': [for (final aggregate in aggregates) aggregate.toJson()],
  };
}

/// One complete record browse/search query.
///
/// The constructor enforces every observed server budget — page size 1..200,
/// at most 5 sorts without repeated fields, filter depth ≤8, at most 64
/// filter operations and at most 2 nested relation hops — so an over-budget
/// query fails at the call site instead of as a wire refusal.
final class KumweRecordQuery {
  /// Validates a query against the closed grammar and its budgets.
  factory KumweRecordQuery({
    KumweRecordFilter? filter,
    KumweRecordSearch? search,
    List<KumweRecordSort> sorts = const [],
    KumweCursor? after,
    int? pageSize,
    KumweRecordProjection? projection,
    bool includeArchived = false,
    bool includeDeleted = false,
  }) {
    if (pageSize != null && (pageSize < 1 || pageSize > 200)) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Page sizes run from 1 to 200.',
      );
    }
    if (sorts.length > 5) {
      throw ArgumentError.value(
        sorts.length,
        'sorts',
        'Queries carry at most 5 sort clauses.',
      );
    }
    final sortFields = <String>{};
    for (final sort in sorts) {
      if (!sortFields.add(sort.field)) {
        throw ArgumentError.value(
          sort.field,
          'sorts',
          'Sort fields must not repeat.',
        );
      }
    }
    if (filter != null) {
      final budget = _FilterBudget()..measure(filter, 1, 0);
      if (budget.maxDepth > 8) {
        throw ArgumentError.value(
          budget.maxDepth,
          'filter',
          'Filter trees nest at most 8 levels.',
        );
      }
      if (budget.operations > 64) {
        throw ArgumentError.value(
          budget.operations,
          'filter',
          'Filter trees carry at most 64 operations.',
        );
      }
      if (budget.maxHops > 2) {
        throw ArgumentError.value(
          budget.maxHops,
          'filter',
          'Filter trees traverse at most 2 relation hops.',
        );
      }
    }
    return KumweRecordQuery._(
      filter: filter,
      search: search,
      sorts: List<KumweRecordSort>.unmodifiable(sorts),
      after: after,
      pageSize: pageSize,
      projection: projection,
      includeArchived: includeArchived,
      includeDeleted: includeDeleted,
    );
  }

  const KumweRecordQuery._({
    required this.filter,
    required this.search,
    required this.sorts,
    required this.after,
    required this.pageSize,
    required this.projection,
    required this.includeArchived,
    required this.includeDeleted,
  });

  /// Filter tree, when the query filters.
  final KumweRecordFilter? filter;

  /// Text search, when the query searches.
  final KumweRecordSearch? search;

  /// Sort clauses in priority order.
  final List<KumweRecordSort> sorts;

  /// Continuation cursor from the previous page.
  final KumweCursor? after;

  /// Requested page size; `null` uses the server default of 50.
  final int? pageSize;

  /// Field/include/aggregate projection.
  final KumweRecordProjection? projection;

  /// Whether archived records are included.
  final bool includeArchived;

  /// Whether soft-deleted records are included.
  final bool includeDeleted;

  /// Returns this query continued after [cursor], all else unchanged.
  KumweRecordQuery continueAfter(KumweCursor cursor) {
    return KumweRecordQuery._(
      filter: filter,
      search: search,
      sorts: sorts,
      after: cursor,
      pageSize: pageSize,
      projection: projection,
      includeArchived: includeArchived,
      includeDeleted: includeDeleted,
    );
  }

  /// Serializes the query into the closed wire document, omitting every
  /// member the server would default.
  Map<String, Object?> toJson() => {
    if (filter != null) 'filter': filter!.toJson(),
    if (search != null) 'search': search!.toJson(),
    if (sorts.isNotEmpty) 'sorts': [for (final sort in sorts) sort.toJson()],
    if (after != null) 'after': after!.value,
    if (pageSize != null) 'page_size': pageSize,
    if (projection != null && !projection!.isEmpty)
      'projection': projection!.toJson(),
    if (includeArchived) 'include_archived': true,
    if (includeDeleted) 'include_deleted': true,
  };

  @override
  String toString() =>
      'KumweRecordQuery(${filter == null ? 'unfiltered' : 'filtered'}, '
      '${sorts.length} sort(s))';
}

final class _FilterBudget {
  int operations = 0;
  int maxDepth = 0;
  int maxHops = 0;

  void measure(KumweRecordFilter node, int depth, int hops) {
    operations += 1;
    if (depth > maxDepth) {
      maxDepth = depth;
    }
    if (hops > maxHops) {
      maxHops = hops;
    }
    switch (node) {
      case KumweBooleanFilter(:final children):
        for (final child in children) {
          measure(child, depth + 1, hops);
        }
      case KumweRelationFilter(:final target):
        measure(target, depth + 1, hops + 1);
      case KumweComparisonFilter() ||
          KumweTextFilter() ||
          KumweSetFilter() ||
          KumweNullFilter():
        break;
    }
  }
}

void _requireHandle(String value, String name) {
  if (!KumweBusinessHandles.isHandle(value)) {
    throw ArgumentError.value(
      '<handle>',
      name,
      'Business handles are bounded lowercase identifiers.',
    );
  }
}

void _requireQueryValue(Object value) {
  if (value is bool || value is int) {
    return;
  }
  if (value is String) {
    if (utf8.encode(value).length > 4096) {
      throw ArgumentError.value(
        '<value>',
        'value',
        'Query strings carry at most 4096 UTF-8 bytes.',
      );
    }
    return;
  }
  throw ArgumentError.value(
    value is double ? '<double>' : value.runtimeType,
    'value',
    'Query values are bool, int or string; exact numbers travel as '
        'strings.',
  );
}
