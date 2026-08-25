import 'dart:collection';

import '../json/kumwe_json.dart';

/// Who published a business definition.
enum KumweDefinitionOwnerType {
  /// The core product itself.
  core('core'),

  /// An installed extension.
  extension('extension'),

  /// The site's own configuration.
  site('site');

  const KumweDefinitionOwnerType(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed owner-type vocabulary.
  static KumweDefinitionOwnerType parse(Object? value) {
    for (final type in values) {
      if (type.wireName == value) {
        return type;
      }
    }
    throw const FormatException(
      'Definition owners are core, extension or site.',
    );
  }
}

/// The party that published a definition.
final class KumweDefinitionOwner {
  /// Validates an owner declaration.
  factory KumweDefinitionOwner.fromJson(Map<String, Object?> json) {
    final identifier = json['identifier'];
    if (identifier is! String ||
        identifier.isEmpty ||
        identifier.length > 191) {
      throw const FormatException(
        'Definition owners carry a bounded identifier.',
      );
    }
    return KumweDefinitionOwner._(
      type: KumweDefinitionOwnerType.parse(json['type']),
      identifier: identifier,
    );
  }

  const KumweDefinitionOwner._({required this.type, required this.identifier});

  /// Which party published the definition.
  final KumweDefinitionOwnerType type;

  /// Owner identifier within its type.
  final String identifier;

  @override
  String toString() => 'KumweDefinitionOwner(${type.wireName}:$identifier)';
}

/// Where records of a definition live.
enum KumweScopeMode {
  /// One shared collection per installation.
  installation('installation'),

  /// One collection per site.
  site('site'),

  /// One collection per organization.
  organization('organization'),

  /// One collection per site-and-organization pair.
  siteOrganization('site_organization');

  const KumweScopeMode(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed scope vocabulary.
  static KumweScopeMode parse(Object? value) {
    for (final mode in values) {
      if (mode.wireName == value) {
        return mode;
      }
    }
    throw const FormatException('The definition scope is out of vocabulary.');
  }
}

/// One declared workflow state.
final class KumweWorkflowState {
  /// Validates a workflow state declaration.
  factory KumweWorkflowState.fromJson(Map<String, Object?> json) {
    final handle = json['handle'];
    if (handle is! String || !KumweBusinessHandles.isHandle(handle)) {
      throw const FormatException(
        'Workflow states carry a bounded lowercase handle.',
      );
    }
    final label = json['label'];
    if (label is! String || label.isEmpty || label.length > 191) {
      throw const FormatException('Workflow states carry a bounded label.');
    }
    return KumweWorkflowState._(handle: handle, label: label);
  }

  const KumweWorkflowState._({required this.handle, required this.label});

  /// Stable state handle.
  final String handle;

  /// Human-readable label.
  final String label;

  @override
  String toString() => 'KumweWorkflowState($handle)';
}

/// A definition's declared workflow.
final class KumweWorkflowDeclaration {
  /// Validates a workflow declaration.
  factory KumweWorkflowDeclaration.fromJson(Map<String, Object?> json) {
    final initial = json['initial_state'];
    if (initial is! String || !KumweBusinessHandles.isHandle(initial)) {
      throw const FormatException(
        'Workflows name their initial state by handle.',
      );
    }
    final rawStates = json['states'];
    if (rawStates is! List<Object?> ||
        rawStates.isEmpty ||
        rawStates.length > 128) {
      throw const FormatException('Workflows declare 1 to 128 states.');
    }
    final states = <KumweWorkflowState>[];
    final seen = <String>{};
    for (final rawState in rawStates) {
      if (rawState is! Map<String, Object?>) {
        throw const FormatException('Every workflow state is an object.');
      }
      final state = KumweWorkflowState.fromJson(rawState);
      if (!seen.add(state.handle)) {
        throw FormatException('Workflow state ${state.handle} is duplicated.');
      }
      states.add(state);
    }
    if (!seen.contains(initial)) {
      throw const FormatException(
        'The workflow initial state is not among its states.',
      );
    }
    return KumweWorkflowDeclaration._(
      initialState: initial,
      states: List<KumweWorkflowState>.unmodifiable(states),
    );
  }

  const KumweWorkflowDeclaration._({
    required this.initialState,
    required this.states,
  });

  /// Handle of the state a fresh record starts in.
  final String initialState;

  /// Declared states in server order.
  final List<KumweWorkflowState> states;

  @override
  String toString() =>
      'KumweWorkflowDeclaration($initialState, ${states.length} state(s))';
}

/// The abstract value shape behind a field type.
enum KumweFieldValueType {
  /// A JSON string.
  string('string'),

  /// A JSON integer.
  integer('integer'),

  /// A JSON boolean.
  boolean('boolean'),

  /// A closed JSON object composite.
  object('object'),

  /// A bounded JSON array.
  collection('collection'),

  /// A reference to another record.
  reference('reference');

  const KumweFieldValueType(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed value-type vocabulary.
  static KumweFieldValueType parse(Object? value) {
    for (final type in values) {
      if (type.wireName == value) {
        return type;
      }
    }
    throw const FormatException('The field value type is out of vocabulary.');
  }
}

/// Which projections and forms one field participates in.
final class KumweFieldUses {
  /// Validates a field-uses declaration; absent flags read as `false`.
  factory KumweFieldUses.fromJson(Map<String, Object?> json) {
    bool flag(String member) {
      final value = json[member];
      if (value == null) {
        return false;
      }
      if (value is! bool) {
        throw FormatException('The field use $member must be a boolean.');
      }
      return value;
    }

    return KumweFieldUses._(
      create: flag('create'),
      update: flag('update'),
      detail: flag('detail'),
      list: flag('list'),
      filter: flag('filter'),
      search: flag('search'),
      sort: flag('sort'),
      report: flag('report'),
      export: flag('export'),
    );
  }

  const KumweFieldUses._({
    required this.create,
    required this.update,
    required this.detail,
    required this.list,
    required this.filter,
    required this.search,
    required this.sort,
    required this.report,
    required this.export,
  });

  /// Whether the field may appear in create payloads.
  final bool create;

  /// Whether the field may appear in update payloads.
  final bool update;

  /// Whether the field appears on detail projections.
  final bool detail;

  /// Whether the field appears on list projections.
  final bool list;

  /// Whether the field may be filtered on.
  final bool filter;

  /// Whether the field participates in text search.
  final bool search;

  /// Whether the field may be sorted on.
  final bool sort;

  /// Whether the field participates in reporting.
  final bool report;

  /// Whether the field participates in exports.
  final bool export;

  @override
  String toString() => 'KumweFieldUses()';
}

/// One disclosed field of a business definition.
///
/// A field the caller may not see is absent from the document entirely, so
/// this model never carries a denial marker: what is here is usable.
final class KumweBusinessField {
  /// Validates a field declaration.
  factory KumweBusinessField.fromJson(Map<String, Object?> json) {
    final handle = json['handle'];
    if (handle is! String || !KumweBusinessHandles.isHandle(handle)) {
      throw const FormatException('Fields carry a bounded lowercase handle.');
    }
    final type = json['type'];
    if (type is! String || !KumweBusinessHandles.isFieldType(type)) {
      throw FormatException('Field $handle carries an out-of-grammar type.');
    }
    final rawUses = json['uses'];
    if (rawUses is! Map<String, Object?>) {
      throw FormatException('Field $handle must declare its uses.');
    }
    final rawSchema = json['schema'];
    if (rawSchema is! Map<String, Object?>) {
      throw FormatException('Field $handle must carry a schema fragment.');
    }
    final order = json['order'];
    if (order is! int) {
      throw FormatException('Field $handle must carry an integer order.');
    }
    final placements = <String>[];
    final rawPlacements = json['placements'];
    if (rawPlacements != null) {
      if (rawPlacements is! List<Object?> || rawPlacements.length > 32) {
        throw FormatException('Field $handle declares at most 32 placements.');
      }
      for (final placement in rawPlacements) {
        if (placement is! String ||
            placement.isEmpty ||
            placement.length > 191) {
          throw FormatException(
            'Field $handle declares an out-of-bounds placement.',
          );
        }
        placements.add(placement);
      }
    }
    return KumweBusinessField._(
      handle: handle,
      label: _text(json, 'label', handle),
      description: _optionalText(json, 'description', handle),
      helpText: _optionalText(json, 'help_text', handle),
      type: type,
      valueType: KumweFieldValueType.parse(json['value_type']),
      required: _flag(json, 'required', handle),
      nullable: _flag(json, 'nullable', handle),
      readOnly: _flag(json, 'read_only', handle),
      writeOnly: _flag(json, 'write_only', handle),
      immutableAfterCreate: _flag(json, 'immutable_after_create', handle),
      conditional: _flag(json, 'conditional', handle),
      formGroup: _optionalText(json, 'form_group', handle),
      order: order,
      placements: List<String>.unmodifiable(placements),
      uses: KumweFieldUses.fromJson(rawUses),
      schema: KumweJsonValue.from(rawSchema),
    );
  }

  const KumweBusinessField._({
    required this.handle,
    required this.label,
    required this.description,
    required this.helpText,
    required this.type,
    required this.valueType,
    required this.required,
    required this.nullable,
    required this.readOnly,
    required this.writeOnly,
    required this.immutableAfterCreate,
    required this.conditional,
    required this.formGroup,
    required this.order,
    required this.placements,
    required this.uses,
    required this.schema,
  });

  /// Stable field handle.
  final String handle;

  /// Human-readable label.
  final String label;

  /// Longer description, when declared.
  final String? description;

  /// Inline help text, when declared.
  final String? helpText;

  /// Field type identifier; `core.*` or a namespaced extension type.
  final String type;

  /// Abstract value shape.
  final KumweFieldValueType valueType;

  /// Whether the field is required on create.
  final bool required;

  /// Whether a stored `null` is a legal value.
  final bool nullable;

  /// Whether the field can never be written by the caller.
  final bool readOnly;

  /// Whether the field's value is never read back (secrets).
  final bool writeOnly;

  /// Whether the field freezes after the record is created.
  final bool immutableAfterCreate;

  /// Whether visibility depends on other values.
  final bool conditional;

  /// Form group the field renders under, when declared.
  final String? formGroup;

  /// Display order within its group.
  final int order;

  /// Declared placements.
  final List<String> placements;

  /// Projections and forms the field participates in.
  final KumweFieldUses uses;

  /// Bounded JSON Schema 2020-12 fragment for the field's values.
  final KumweJsonValue schema;

  /// Whether this field is one of the 25 built-in core types.
  bool get isCoreType => type.startsWith('core.');

  @override
  String toString() => 'KumweBusinessField($handle: $type)';

  static String _text(Map<String, Object?> json, String member, String handle) {
    final value = json[member];
    if (value is! String || value.isEmpty || value.length > 191) {
      throw FormatException('Field $handle needs a bounded $member.');
    }
    return value;
  }

  static String? _optionalText(
    Map<String, Object?> json,
    String member,
    String handle,
  ) {
    final value = json[member];
    if (value == null || value == '') {
      return null;
    }
    if (value is! String || value.length > 2048) {
      throw FormatException('Field $handle carries an oversized $member.');
    }
    return value;
  }

  static bool _flag(Map<String, Object?> json, String member, String handle) {
    final value = json[member];
    if (value == null) {
      return false;
    }
    if (value is! bool) {
      throw FormatException('Field $handle member $member must be boolean.');
    }
    return value;
  }
}

/// The kind of a declared view.
enum KumweViewKind {
  /// A list projection.
  list('list'),

  /// A detail projection.
  detail('detail'),

  /// A create/update form.
  form('form'),

  /// A history projection.
  history('history'),

  /// A relation projection.
  relation('relation'),

  /// A document-style projection with roles.
  document('document');

  const KumweViewKind(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed view-kind vocabulary.
  static KumweViewKind parse(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) {
        return kind;
      }
    }
    throw const FormatException('The view kind is out of vocabulary.');
  }
}

/// The schema pair a custom view or action publishes.
final class KumweCustomContract {
  /// Validates a custom contract declaration.
  factory KumweCustomContract.fromJson(
    Map<String, Object?> json, {
    required String requestMember,
  }) {
    final request = json[requestMember];
    final result = json['result_schema'];
    if (request is! Map<String, Object?> || result is! Map<String, Object?>) {
      throw FormatException(
        'Custom contracts carry $requestMember and result_schema objects.',
      );
    }
    return KumweCustomContract._(
      requestSchema: KumweJsonValue.from(request),
      resultSchema: KumweJsonValue.from(result),
    );
  }

  const KumweCustomContract._({
    required this.requestSchema,
    required this.resultSchema,
  });

  /// Schema of the request document (query or command).
  final KumweJsonValue requestSchema;

  /// Schema of the result document.
  final KumweJsonValue resultSchema;

  @override
  String toString() => 'KumweCustomContract()';
}

/// One disclosed view of a business definition.
final class KumweBusinessView {
  /// Validates a view declaration.
  factory KumweBusinessView.fromJson(Map<String, Object?> json) {
    final handle = json['handle'];
    if (handle is! String || !KumweBusinessHandles.isHandle(handle)) {
      throw const FormatException('Views carry a bounded lowercase handle.');
    }
    final label = json['label'];
    if (label is! String || label.isEmpty || label.length > 191) {
      throw FormatException('View $handle needs a bounded label.');
    }
    final custom = json['custom'];
    if (custom is! bool) {
      throw FormatException('View $handle must declare whether it is custom.');
    }
    final rawContract = json['custom_contract'];
    KumweCustomContract? contract;
    if (rawContract != null) {
      if (rawContract is! Map<String, Object?>) {
        throw FormatException('View $handle custom contract is an object.');
      }
      contract = KumweCustomContract.fromJson(
        rawContract,
        requestMember: 'query_schema',
      );
    }
    return KumweBusinessView._(
      handle: handle,
      label: label,
      kind: KumweViewKind.parse(json['kind']),
      custom: custom,
      fields: KumweBusinessHandles.handleList(json['fields'], 'view fields'),
      filters: KumweBusinessHandles.handleList(json['filters'], 'view filters'),
      sorts: KumweBusinessHandles.handleList(json['sorts'], 'view sorts'),
      customContract: contract,
      document: json['document'] is Map<String, Object?>
          ? KumweJsonValue.from(json['document'])
          : null,
    );
  }

  const KumweBusinessView._({
    required this.handle,
    required this.label,
    required this.kind,
    required this.custom,
    required this.fields,
    required this.filters,
    required this.sorts,
    required this.customContract,
    required this.document,
  });

  /// Stable view handle.
  final String handle;

  /// Human-readable label.
  final String label;

  /// Declared kind.
  final KumweViewKind kind;

  /// Whether the view executes a custom contract.
  final bool custom;

  /// Field handles the view projects.
  final List<String> fields;

  /// Field handles the view allows filtering on.
  final List<String> filters;

  /// Field handles the view allows sorting on.
  final List<String> sorts;

  /// Query/result schema pair, present only on custom views.
  final KumweCustomContract? customContract;

  /// Document-role declaration for document views, kept as validated JSON.
  final KumweJsonValue? document;

  @override
  String toString() => 'KumweBusinessView($handle: ${kind.wireName})';
}

/// One disclosed action of a business definition.
final class KumweBusinessAction {
  /// Validates an action declaration.
  factory KumweBusinessAction.fromJson(Map<String, Object?> json) {
    final handle = json['handle'];
    if (handle is! String || !KumweBusinessHandles.isHandle(handle)) {
      throw const FormatException('Actions carry a bounded lowercase handle.');
    }
    final label = json['label'];
    if (label is! String || label.isEmpty || label.length > 191) {
      throw FormatException('Action $handle needs a bounded label.');
    }
    final transition = json['transition'];
    if (transition != null &&
        (transition is! String || !KumweBusinessHandles.isHandle(transition))) {
      throw FormatException(
        'Action $handle names an out-of-grammar transition.',
      );
    }
    final rawContract = json['custom_contract'];
    KumweCustomContract? contract;
    if (rawContract != null) {
      if (rawContract is! Map<String, Object?>) {
        throw FormatException('Action $handle custom contract is an object.');
      }
      contract = KumweCustomContract.fromJson(
        rawContract,
        requestMember: 'command_schema',
      );
    }
    bool flag(String member) {
      final value = json[member];
      if (value is! bool) {
        throw FormatException('Action $handle member $member is boolean.');
      }
      return value;
    }

    return KumweBusinessAction._(
      handle: handle,
      label: label,
      bulk: flag('bulk'),
      highImpact: flag('high_impact'),
      transition: transition as String?,
      conditional: flag('conditional'),
      customContract: contract,
    );
  }

  const KumweBusinessAction._({
    required this.handle,
    required this.label,
    required this.bulk,
    required this.highImpact,
    required this.transition,
    required this.conditional,
    required this.customContract,
  });

  /// Stable action handle.
  final String handle;

  /// Human-readable label.
  final String label;

  /// Whether the action may run over many records.
  final bool bulk;

  /// Whether the action is flagged high impact (may require approval).
  final bool highImpact;

  /// Workflow state the action transitions to, when it is a transition.
  final String? transition;

  /// Whether availability depends on record state.
  final bool conditional;

  /// Command/result schema pair, present only on custom actions.
  final KumweCustomContract? customContract;

  @override
  String toString() => 'KumweBusinessAction($handle)';
}

/// The kind of a declared relationship.
enum KumweRelationshipKind {
  /// Exactly one related record either way.
  oneToOne('one_to_one'),

  /// Many records point at one target.
  manyToOne('many_to_one'),

  /// One record owns many targets.
  oneToMany('one_to_many'),

  /// Free many-to-many association.
  manyToMany('many_to_many'),

  /// Ordered line collection owned by the source record.
  ownedLineCollection('owned_line_collection'),

  /// Reversal linkage between correcting documents.
  reversal('reversal');

  const KumweRelationshipKind(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed relationship-kind vocabulary.
  static KumweRelationshipKind parse(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) {
        return kind;
      }
    }
    throw const FormatException('The relationship kind is out of vocabulary.');
  }
}

/// One disclosed relationship of a business definition.
final class KumweBusinessRelationship {
  /// Validates a relationship declaration.
  factory KumweBusinessRelationship.fromJson(Map<String, Object?> json) {
    final handle = json['handle'];
    if (handle is! String || !KumweBusinessHandles.isHandle(handle)) {
      throw const FormatException(
        'Relationships carry a bounded lowercase handle.',
      );
    }
    final label = json['label'];
    if (label is! String || label.isEmpty || label.length > 191) {
      throw FormatException('Relationship $handle needs a bounded label.');
    }
    final target = json['target'];
    if (target is! String || !KumweBusinessHandles.isDefinitionHandle(target)) {
      throw FormatException(
        'Relationship $handle targets an out-of-grammar definition.',
      );
    }
    final required = json['required'];
    final ordered = json['ordered'];
    if (required is! bool || ordered is! bool) {
      throw FormatException(
        'Relationship $handle must declare required and ordered.',
      );
    }
    return KumweBusinessRelationship._(
      handle: handle,
      label: label,
      kind: KumweRelationshipKind.parse(json['kind']),
      target: target,
      required: required,
      ordered: ordered,
    );
  }

  const KumweBusinessRelationship._({
    required this.handle,
    required this.label,
    required this.kind,
    required this.target,
    required this.required,
    required this.ordered,
  });

  /// Stable relationship handle.
  final String handle;

  /// Human-readable label.
  final String label;

  /// Declared kind.
  final KumweRelationshipKind kind;

  /// Handle of the target definition.
  final String target;

  /// Whether the relationship must be populated.
  final bool required;

  /// Whether related records carry positions.
  final bool ordered;

  @override
  String toString() =>
      'KumweBusinessRelationship($handle -> $target, ${kind.wireName})';
}

/// One policy-filtered business definition document.
///
/// The document is already filtered to the calling credential: a field,
/// view, action or relationship the caller may not use is absent, never
/// annotated, so everything this model exposes is usable as-is. Two callers
/// can legitimately hold different documents for the same definition.
final class KumweBusinessDefinition {
  /// Validates a definition document.
  factory KumweBusinessDefinition.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || !_uuidPattern.hasMatch(id)) {
      throw const FormatException('Definitions carry a UUID identifier.');
    }
    final handle = json['handle'];
    if (handle is! String || !KumweBusinessHandles.isDefinitionHandle(handle)) {
      throw const FormatException(
        'Definitions carry a bounded namespaced handle.',
      );
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw FormatException(
        'Definition $handle needs a positive integer version.',
      );
    }
    final checksum = json['checksum'];
    if (checksum is! String || !_checksumPattern.hasMatch(checksum)) {
      throw FormatException('Definition $handle needs a 64-hex checksum.');
    }
    final owner = json['owner'];
    if (owner is! Map<String, Object?>) {
      throw FormatException('Definition $handle needs an owner object.');
    }
    final softDelete = json['soft_delete'];
    if (softDelete is! bool) {
      throw FormatException('Definition $handle must declare soft_delete.');
    }
    final rawWorkflow = json['workflow'];
    KumweWorkflowDeclaration? workflow;
    if (rawWorkflow != null) {
      if (rawWorkflow is! Map<String, Object?>) {
        throw FormatException('Definition $handle workflow is an object.');
      }
      workflow = KumweWorkflowDeclaration.fromJson(rawWorkflow);
    }
    final operation = json['operation'];
    if (operation is! String || operation.isEmpty || operation.length > 96) {
      throw FormatException(
        'Definition $handle names the operation it was filtered for.',
      );
    }
    return KumweBusinessDefinition._(
      id: id,
      handle: handle,
      singularLabel: _label(json, 'singular_label', handle),
      pluralLabel: _label(json, 'plural_label', handle),
      version: version,
      checksum: checksum,
      owner: KumweDefinitionOwner.fromJson(owner),
      scope: KumweScopeMode.parse(json['scope']),
      softDelete: softDelete,
      workflow: workflow,
      operation: operation,
      fields: _section(
        json['fields'],
        256,
        'fields',
        handle,
        KumweBusinessField.fromJson,
        (field) => field.handle,
      ),
      views: _section(
        json['views'],
        128,
        'views',
        handle,
        KumweBusinessView.fromJson,
        (view) => view.handle,
      ),
      actions: _section(
        json['actions'],
        128,
        'actions',
        handle,
        KumweBusinessAction.fromJson,
        (action) => action.handle,
      ),
      relationships: _section(
        json['relationships'],
        128,
        'relationships',
        handle,
        KumweBusinessRelationship.fromJson,
        (relationship) => relationship.handle,
      ),
    );
  }

  const KumweBusinessDefinition._({
    required this.id,
    required this.handle,
    required this.singularLabel,
    required this.pluralLabel,
    required this.version,
    required this.checksum,
    required this.owner,
    required this.scope,
    required this.softDelete,
    required this.workflow,
    required this.operation,
    required this.fields,
    required this.views,
    required this.actions,
    required this.relationships,
  });

  /// Definition UUID.
  final String id;

  /// Stable definition handle.
  final String handle;

  /// Localized singular label.
  final String singularLabel;

  /// Localized plural label.
  final String pluralLabel;

  /// Definition version this document projects.
  final int version;

  /// Per-definition disclosure checksum (64 lowercase hex).
  final String checksum;

  /// Publishing party.
  final KumweDefinitionOwner owner;

  /// Where records of this definition live.
  final KumweScopeMode scope;

  /// Whether deletes are soft.
  final bool softDelete;

  /// Declared workflow, when the definition has one.
  final KumweWorkflowDeclaration? workflow;

  /// The surface operation the document was filtered for.
  final String operation;

  /// Disclosed fields keyed by handle.
  final Map<String, KumweBusinessField> fields;

  /// Disclosed views keyed by handle.
  final Map<String, KumweBusinessView> views;

  /// Disclosed actions keyed by handle.
  final Map<String, KumweBusinessAction> actions;

  /// Disclosed relationships keyed by handle.
  final Map<String, KumweBusinessRelationship> relationships;

  @override
  String toString() =>
      'KumweBusinessDefinition($handle v$version, '
      '${fields.length} field(s))';

  static String _label(
    Map<String, Object?> json,
    String member,
    String handle,
  ) {
    final value = json[member];
    if (value is! String || value.isEmpty || value.length > 191) {
      throw FormatException('Definition $handle needs a bounded $member.');
    }
    return value;
  }

  static Map<String, T> _section<T>(
    Object? raw,
    int maxItems,
    String name,
    String handle,
    T Function(Map<String, Object?>) parse,
    String Function(T) key,
  ) {
    if (raw == null) {
      return const {};
    }
    if (raw is! List<Object?> || raw.length > maxItems) {
      throw FormatException(
        'Definition $handle declares at most $maxItems $name.',
      );
    }
    final section = <String, T>{};
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        throw FormatException(
          'Every entry in definition $handle $name is an object.',
        );
      }
      final parsed = parse(item);
      final itemKey = key(parsed);
      if (section.containsKey(itemKey)) {
        throw FormatException(
          'Definition $handle $name entry $itemKey is duplicated.',
        );
      }
      section[itemKey] = parsed;
    }
    return UnmodifiableMapView(section);
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static final RegExp _checksumPattern = RegExp(r'^[0-9a-f]{64}$');
}

/// The policy-filtered definition catalog one credential can see.
final class KumweBusinessCatalog {
  /// Validates a `{"data": […]}` catalog envelope.
  ///
  /// A caller with no business grant receives an empty catalog rather than
  /// a refusal, so an empty list is a valid, meaningful document.
  factory KumweBusinessCatalog.fromJson(Map<String, Object?> json) {
    final data = json['data'];
    if (data is! List<Object?> || data.length > 256) {
      throw const FormatException(
        'Definition catalogs carry a data list of at most 256 entries.',
      );
    }
    final definitions = <String, KumweBusinessDefinition>{};
    for (final entry in data) {
      if (entry is! Map<String, Object?>) {
        throw const FormatException('Every catalog entry is an object.');
      }
      final definition = KumweBusinessDefinition.fromJson(entry);
      if (definitions.containsKey(definition.handle)) {
        throw FormatException(
          'Catalog definition ${definition.handle} is duplicated.',
        );
      }
      definitions[definition.handle] = definition;
    }
    return KumweBusinessCatalog._(
      definitions: UnmodifiableMapView(definitions),
    );
  }

  const KumweBusinessCatalog._({required this.definitions});

  /// Disclosed definitions keyed by handle.
  final Map<String, KumweBusinessDefinition> definitions;

  /// Returns the disclosed definition, or `null` when this credential
  /// cannot see it — indistinguishable, by design, from it not existing.
  KumweBusinessDefinition? definition(String handle) => definitions[handle];

  @override
  String toString() =>
      'KumweBusinessCatalog(${definitions.length} definition(s))';
}

/// Shared handle and type grammar for the generated business surface.
final class KumweBusinessHandles {
  const KumweBusinessHandles._();

  /// Whether [value] is a bounded lowercase member handle — the short
  /// grammar core applies to field, view, action, relationship, alias and
  /// workflow-state handles.
  static bool isHandle(String value) => _handlePattern.hasMatch(value);

  /// Whether [value] is a namespaced definition handle.
  ///
  /// Core forces every definition handle under an owner namespace —
  /// `core.`, `site.<id>.` or `<vendor>.<package>.` — so a real handle
  /// always contains at least one `.`, `_` or `-` separator and runs to
  /// 191 characters; relationship targets use the same grammar.
  static bool isDefinitionHandle(String value) =>
      value.length <= 191 && _namespacedPattern.hasMatch(value);

  /// Whether [value] is a declared core or namespaced extension field type.
  ///
  /// Extension types sit under the owner namespace of their publishing
  /// package, where hyphens are legal (`acme.crm-pro.rating`); an
  /// undeclared `core.*` spelling is refused rather than admitted as an
  /// extension.
  static bool isFieldType(String value) =>
      coreFieldTypes.contains(value) ||
      (value.length <= 191 &&
          _namespacedPattern.hasMatch(value) &&
          !value.startsWith('core.'));

  /// Parses a bounded list of handles.
  static List<String> handleList(Object? raw, String context) {
    if (raw == null) {
      return const [];
    }
    if (raw is! List<Object?> || raw.length > 256) {
      throw FormatException('$context lists at most 256 handles.');
    }
    final handles = <String>[];
    for (final value in raw) {
      if (value is! String || !isHandle(value)) {
        throw FormatException('$context carries an out-of-grammar handle.');
      }
      handles.add(value);
    }
    return List<String>.unmodifiable(handles);
  }

  /// The closed built-in field type vocabulary (25 identifiers).
  static const Set<String> coreFieldTypes = {
    'core.uuid',
    'core.reference_identity',
    'core.text',
    'core.rich_text',
    'core.integer',
    'core.decimal',
    'core.money',
    'core.quantity',
    'core.boolean',
    'core.enum',
    'core.date',
    'core.local_time',
    'core.instant',
    'core.zoned_datetime',
    'core.email',
    'core.url',
    'core.phone',
    'core.media_reference',
    'core.entity_reference',
    'core.embedded_value',
    'core.ordered_lines',
    'core.bounded_json',
    'core.secret',
    'core.computed',
    'core.sequence',
  };

  static final RegExp _handlePattern = RegExp(r'^[a-z][a-z0-9_]{0,62}$');

  static final RegExp _namespacedPattern = RegExp(
    r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$',
  );
}
