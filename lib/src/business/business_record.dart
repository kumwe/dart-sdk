import 'dart:collection';

import '../collection/kumwe_page.dart';
import '../json/kumwe_json.dart';
import '../mutation/entity_tag.dart';
import 'business_definition.dart';

/// One disclosed business record.
///
/// The `values` map carries only what the calling credential may see: a
/// `null` entry is a real stored null of a nullable field, while an absent
/// handle is withheld or unprojected — the two are deliberately
/// distinguishable and this model never collapses them.
final class KumweBusinessRecord {
  /// Validates a record envelope.
  factory KumweBusinessRecord.fromJson(Map<String, Object?> json) {
    final envelope = _RecordEnvelope.fromJson(json);
    final includes = <String, List<KumweRelationRecord>>{};
    final rawIncludes = json['includes'];
    if (rawIncludes != null) {
      if (rawIncludes is! Map<String, Object?> || rawIncludes.length > 4) {
        throw const FormatException('Records include at most 4 relationships.');
      }
      for (final entry in rawIncludes.entries) {
        if (!KumweBusinessHandles.isHandle(entry.key)) {
          throw const FormatException(
            'Include keys are bounded relationship handles.',
          );
        }
        final rawRelated = entry.value;
        if (rawRelated is! List<Object?> || rawRelated.length > 1000) {
          throw FormatException(
            'Include ${entry.key} carries at most 1000 related records.',
          );
        }
        includes[entry.key] = List<KumweRelationRecord>.unmodifiable([
          for (final related in rawRelated)
            KumweRelationRecord.fromJson(_object(related, 'related record')),
        ]);
      }
    }
    return KumweBusinessRecord._(
      definitionVersion: envelope.definitionVersion,
      recordId: envelope.recordId,
      version: envelope.version,
      workflowState: envelope.workflowState,
      values: envelope.values,
      createdAt: _instant(json, 'created_at'),
      updatedAt: _instant(json, 'updated_at'),
      archivedAt: _optionalInstant(json, 'archived_at'),
      deletedAt: _optionalInstant(json, 'deleted_at'),
      includes: UnmodifiableMapView(includes),
    );
  }

  const KumweBusinessRecord._({
    required this.definitionVersion,
    required this.recordId,
    required this.version,
    required this.workflowState,
    required this.values,
    required this.createdAt,
    required this.updatedAt,
    required this.archivedAt,
    required this.deletedAt,
    required this.includes,
  });

  /// Definition version the record was projected under.
  final int definitionVersion;

  /// Stable record identifier.
  final String recordId;

  /// Record version; the strong precondition for the next mutation.
  final int version;

  /// Current workflow state, when the definition has a workflow.
  final String? workflowState;

  /// Disclosed field values keyed by handle.
  final Map<String, KumweJsonValue> values;

  /// Creation instant.
  final DateTime createdAt;

  /// Last-update instant.
  final DateTime updatedAt;

  /// Archival instant, when archived.
  final DateTime? archivedAt;

  /// Soft-delete instant, when deleted.
  final DateTime? deletedAt;

  /// Included related records keyed by relationship handle.
  final Map<String, List<KumweRelationRecord>> includes;

  /// The strong entity tag for this record version.
  EntityTag get entityTag => EntityTag.recordVersion(version);

  /// Whether [handle] was disclosed at all — `true` even for a stored null.
  bool discloses(String handle) => values.containsKey(handle);

  @override
  String toString() =>
      'KumweBusinessRecord($recordId v$version, '
      '${values.length} value(s))';
}

/// One related record inside an include — identity, position and values
/// only, never timestamps or nested includes.
final class KumweRelationRecord {
  /// Validates a relation-record envelope.
  factory KumweRelationRecord.fromJson(Map<String, Object?> json) {
    final envelope = _RecordEnvelope.fromJson(json);
    final position = json['position'];
    if (position != null && position is! int) {
      throw const FormatException('Related record positions are integers.');
    }
    return KumweRelationRecord._(
      definitionVersion: envelope.definitionVersion,
      recordId: envelope.recordId,
      version: envelope.version,
      position: position as int?,
      values: envelope.values,
    );
  }

  const KumweRelationRecord._({
    required this.definitionVersion,
    required this.recordId,
    required this.version,
    required this.position,
    required this.values,
  });

  /// Definition version the related record was projected under.
  final int definitionVersion;

  /// Stable record identifier.
  final String recordId;

  /// Record version.
  final int version;

  /// Position within an ordered relationship, when ordered.
  final int? position;

  /// Disclosed field values keyed by handle.
  final Map<String, KumweJsonValue> values;

  @override
  String toString() => 'KumweRelationRecord($recordId v$version)';
}

/// One page of a record browse or search.
final class KumweRecordPageDocument {
  /// Validates an `{"items", "next_cursor", "aggregates"}` page envelope.
  factory KumweRecordPageDocument.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    if (rawItems is! List<Object?> || rawItems.length > 200) {
      throw const FormatException(
        'Record pages carry an items list of at most 200 records.',
      );
    }
    final items = <KumweBusinessRecord>[
      for (final item in rawItems)
        KumweBusinessRecord.fromJson(_object(item, 'page item')),
    ];
    final rawCursor = json['next_cursor'];
    KumweCursor? cursor;
    if (rawCursor != null) {
      if (rawCursor is! String) {
        throw const FormatException('The next cursor is a string.');
      }
      try {
        cursor = KumweCursor(rawCursor);
      } on ArgumentError {
        throw const FormatException(
          'The next cursor is out of the opaque token bounds.',
        );
      }
    }
    final aggregates = <String, Object>{};
    final rawAggregates = json['aggregates'];
    if (rawAggregates != null) {
      if (rawAggregates is! Map<String, Object?> || rawAggregates.length > 16) {
        throw const FormatException(
          'Record pages carry at most 16 aggregates.',
        );
      }
      for (final entry in rawAggregates.entries) {
        if (!KumweBusinessHandles.isHandle(entry.key)) {
          throw const FormatException(
            'Aggregate aliases are bounded lowercase handles.',
          );
        }
        final value = entry.value;
        if (value is! int && value is! String) {
          throw FormatException(
            'Aggregate ${entry.key} must be an integer count or an exact '
            'decimal string.',
          );
        }
        aggregates[entry.key] = value as Object;
      }
    }
    return KumweRecordPageDocument._(
      page: KumwePage<KumweBusinessRecord>(items: items, continuation: cursor),
      aggregates: UnmodifiableMapView(aggregates),
    );
  }

  const KumweRecordPageDocument._({
    required this.page,
    required this.aggregates,
  });

  /// The records and their honest continuation.
  final KumwePage<KumweBusinessRecord> page;

  /// Aggregate results keyed by alias: `int` for counts, exact decimal
  /// `String` for sum/min/max/avg — never a binary float.
  final Map<String, Object> aggregates;

  @override
  String toString() =>
      'KumweRecordPageDocument(${page.items.length} item(s)'
      '${page.hasMore ? ', more' : ''})';
}

/// The operation a mutation envelope reports.
enum KumweRecordOperation {
  /// A record was created.
  create('create'),

  /// A record was updated.
  update('update'),

  /// A record was archived.
  archive('archive'),

  /// A record was deleted.
  delete('delete'),

  /// A record was restored.
  restore('restore'),

  /// A declared or custom action ran.
  action('action'),

  /// A relationship was added.
  relate('relate'),

  /// A relationship was removed.
  unrelate('unrelate'),

  /// An ordered relationship was reordered.
  reorder('reorder');

  const KumweRecordOperation(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed operation vocabulary.
  static KumweRecordOperation parse(Object? value) {
    for (final operation in values) {
      if (operation.wireName == value) {
        return operation;
      }
    }
    throw const FormatException('The mutation operation is out of vocabulary.');
  }
}

/// The envelope every record mutation returns.
final class KumweRecordMutationDocument {
  /// Validates a mutation envelope.
  factory KumweRecordMutationDocument.fromJson(Map<String, Object?> json) {
    final definitionVersion = json['definition_version'];
    final version = json['version'];
    if (definitionVersion is! int || definitionVersion < 1) {
      throw const FormatException(
        'Mutation envelopes carry a positive definition version.',
      );
    }
    if (version is! int || version < 1) {
      throw const FormatException(
        'Mutation envelopes carry a positive record version.',
      );
    }
    final recordId = json['record_id'];
    if (recordId is! String || recordId.isEmpty || recordId.length > 191) {
      throw const FormatException(
        'Mutation envelopes carry a bounded record identifier.',
      );
    }
    final workflowState = json['workflow_state'];
    if (workflowState != null &&
        (workflowState is! String ||
            !KumweBusinessHandles.isHandle(workflowState))) {
      throw const FormatException(
        'Mutation workflow states are bounded handles.',
      );
    }
    final deleted = json['deleted'];
    final replayed = json['replayed'];
    if (deleted is! bool || replayed is! bool) {
      throw const FormatException(
        'Mutation envelopes declare deleted and replayed.',
      );
    }
    final rawResult = json['result'];
    if (rawResult != null && rawResult is! Map<String, Object?>) {
      throw const FormatException('A custom action result is a JSON object.');
    }
    return KumweRecordMutationDocument._(
      definitionVersion: definitionVersion,
      recordId: recordId,
      version: version,
      workflowState: workflowState as String?,
      operation: KumweRecordOperation.parse(json['operation']),
      deleted: deleted,
      replayed: replayed,
      result: rawResult == null ? null : KumweJsonValue.from(rawResult),
    );
  }

  const KumweRecordMutationDocument._({
    required this.definitionVersion,
    required this.recordId,
    required this.version,
    required this.workflowState,
    required this.operation,
    required this.deleted,
    required this.replayed,
    required this.result,
  });

  /// Definition version the mutation ran under.
  final int definitionVersion;

  /// Stable record identifier.
  final String recordId;

  /// Record version after the mutation.
  final int version;

  /// Workflow state after the mutation, when the definition has one.
  final String? workflowState;

  /// Which operation the envelope reports.
  final KumweRecordOperation operation;

  /// Whether the record is now deleted.
  final bool deleted;

  /// Whether the body is an idempotent replay of an earlier attempt.
  final bool replayed;

  /// Contract-validated custom action result, on custom actions only.
  final KumweJsonValue? result;

  /// The strong entity tag for the post-mutation version.
  EntityTag get entityTag => EntityTag.recordVersion(version);

  @override
  String toString() =>
      'KumweRecordMutationDocument(${operation.wireName} $recordId '
      'v$version${replayed ? ', replayed' : ''})';
}

/// One disclosed revision of a record's history.
final class KumweRecordRevision {
  /// Validates a revision document.
  factory KumweRecordRevision.fromJson(Map<String, Object?> json) {
    final definitionVersion = json['definition_version'];
    final recordVersion = json['record_version'];
    final revisionNumber = json['revision_number'];
    if (definitionVersion is! int ||
        recordVersion is! int ||
        revisionNumber is! int) {
      throw const FormatException(
        'Revisions carry integer version and revision numbers.',
      );
    }
    final operation = json['operation'];
    if (operation is! String || operation.isEmpty || operation.length > 96) {
      throw const FormatException(
        'Revision operations are bounded dotted identifiers.',
      );
    }
    final rawSnapshot = json['snapshot'];
    if (rawSnapshot is! Map<String, Object?> || rawSnapshot.length > 256) {
      throw const FormatException(
        'Revision snapshots carry at most 256 disclosed values.',
      );
    }
    final snapshot = <String, KumweJsonValue>{};
    for (final entry in rawSnapshot.entries) {
      if (!KumweBusinessHandles.isHandle(entry.key)) {
        throw const FormatException('Snapshot keys are bounded field handles.');
      }
      snapshot[entry.key] = KumweJsonValue.from(entry.value);
    }
    final rawChanged = json['changed_fields'];
    if (rawChanged is! List<Object?> || rawChanged.length > 256) {
      throw const FormatException('Revisions list at most 256 changed fields.');
    }
    final changed = <String>[];
    for (final field in rawChanged) {
      if (field is! String || !snapshot.containsKey(field)) {
        throw const FormatException(
          'Changed fields name only disclosed snapshot keys.',
        );
      }
      changed.add(field);
    }
    return KumweRecordRevision._(
      definitionVersion: definitionVersion,
      recordVersion: recordVersion,
      revisionNumber: revisionNumber,
      operation: operation,
      snapshot: UnmodifiableMapView(snapshot),
      changedFields: List<String>.unmodifiable(changed),
      occurredAt: _instant(json, 'occurred_at'),
    );
  }

  const KumweRecordRevision._({
    required this.definitionVersion,
    required this.recordVersion,
    required this.revisionNumber,
    required this.operation,
    required this.snapshot,
    required this.changedFields,
    required this.occurredAt,
  });

  /// Definition version at the revision.
  final int definitionVersion;

  /// Record version the revision produced.
  final int recordVersion;

  /// Monotonic revision number.
  final int revisionNumber;

  /// Dotted operation identifier that produced the revision.
  final String operation;

  /// Disclosed values after the revision, keyed by handle.
  final Map<String, KumweJsonValue> snapshot;

  /// Handles changed in this revision, filtered to disclosed keys.
  final List<String> changedFields;

  /// When the revision occurred.
  final DateTime occurredAt;

  @override
  String toString() =>
      'KumweRecordRevision(#$revisionNumber $operation '
      'v$recordVersion)';
}

/// One page of a record's history.
///
/// History pages continue by version, not by cursor: when [hasMore] is
/// `true`, [nextBeforeVersion] names the `before_version` of the next
/// request.
final class KumweRecordHistoryDocument {
  /// Validates a history envelope.
  factory KumweRecordHistoryDocument.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    if (rawItems is! List<Object?> || rawItems.length > 200) {
      throw const FormatException('History pages carry at most 200 revisions.');
    }
    final hasMore = json['has_more'];
    if (hasMore is! bool) {
      throw const FormatException('History pages declare has_more.');
    }
    final nextBeforeVersion = json['next_before_version'];
    if (hasMore && (nextBeforeVersion is! int || nextBeforeVersion < 1)) {
      throw const FormatException(
        'A continuing history page names its next before-version.',
      );
    }
    if (!hasMore && nextBeforeVersion != null) {
      throw const FormatException(
        'A final history page carries no continuation version.',
      );
    }
    return KumweRecordHistoryDocument._(
      items: List<KumweRecordRevision>.unmodifiable([
        for (final item in rawItems)
          KumweRecordRevision.fromJson(_object(item, 'revision')),
      ]),
      hasMore: hasMore,
      nextBeforeVersion: nextBeforeVersion as int?,
    );
  }

  const KumweRecordHistoryDocument._({
    required this.items,
    required this.hasMore,
    required this.nextBeforeVersion,
  });

  /// Revisions on this page, newest first.
  final List<KumweRecordRevision> items;

  /// Whether older revisions exist.
  final bool hasMore;

  /// `before_version` for the next request; `null` on the final page.
  final int? nextBeforeVersion;

  @override
  String toString() =>
      'KumweRecordHistoryDocument(${items.length} revision(s)'
      '${hasMore ? ', more' : ''})';
}

final class _RecordEnvelope {
  factory _RecordEnvelope.fromJson(Map<String, Object?> json) {
    final definitionVersion = json['definition_version'];
    final version = json['version'];
    if (definitionVersion is! int || definitionVersion < 1) {
      throw const FormatException(
        'Records carry a positive definition version.',
      );
    }
    if (version is! int || version < 1) {
      throw const FormatException('Records carry a positive record version.');
    }
    final recordId = json['record_id'];
    if (recordId is! String || recordId.isEmpty || recordId.length > 191) {
      throw const FormatException('Records carry a bounded record identifier.');
    }
    final workflowState = json['workflow_state'];
    if (workflowState != null &&
        (workflowState is! String ||
            !KumweBusinessHandles.isHandle(workflowState))) {
      throw const FormatException(
        'Record workflow states are bounded handles.',
      );
    }
    final rawValues = json['values'];
    if (rawValues is! Map<String, Object?> || rawValues.length > 256) {
      throw const FormatException(
        'Records carry at most 256 disclosed values.',
      );
    }
    final values = <String, KumweJsonValue>{};
    for (final entry in rawValues.entries) {
      if (!KumweBusinessHandles.isHandle(entry.key)) {
        throw const FormatException('Value keys are bounded field handles.');
      }
      values[entry.key] = KumweJsonValue.from(entry.value);
    }
    return _RecordEnvelope._(
      definitionVersion: definitionVersion,
      recordId: recordId,
      version: version,
      workflowState: workflowState as String?,
      values: UnmodifiableMapView(values),
    );
  }

  const _RecordEnvelope._({
    required this.definitionVersion,
    required this.recordId,
    required this.version,
    required this.workflowState,
    required this.values,
  });

  final int definitionVersion;
  final String recordId;
  final int version;
  final String? workflowState;
  final Map<String, KumweJsonValue> values;
}

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Every $context is an object.');
  }
  return value;
}

DateTime _instant(Map<String, Object?> json, String member) {
  final value = json[member];
  if (value is! String || value.isEmpty || value.length > 64) {
    throw FormatException('The $member timestamp is a bounded string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('The $member timestamp is not a valid instant.');
  }
  return parsed;
}

DateTime? _optionalInstant(Map<String, Object?> json, String member) {
  if (json[member] == null) {
    return null;
  }
  return _instant(json, member);
}
