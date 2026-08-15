import '../json/kumwe_json.dart';
import 'contract_validator.dart';

/// One resolved JSON Schema resource and the schema selected within it.
final class ResolvedJsonSchema {
  /// Creates a resolved schema.
  const ResolvedJsonSchema({
    required this.document,
    required this.schema,
    required this.uri,
  });

  /// Root document containing [schema].
  final KumweJsonObject document;

  /// Selected schema, which can be an object or a boolean schema.
  final Object schema;

  /// Absolute resolved reference, including any fragment.
  final Uri uri;
}

/// Registry used to resolve local and cross-file JSON Schema references.
final class JsonSchemaCatalog {
  final Map<String, KumweJsonObject> _documents = {};

  /// Adds [document] under its retrieval URI and root `$id`, when present.
  void add(Uri retrievalUri, KumweJsonObject document) {
    if (!retrievalUri.isAbsolute) {
      throw ArgumentError.value(
        retrievalUri,
        'retrievalUri',
        'Schema retrieval URIs must be absolute.',
      );
    }
    _register(_withoutFragment(retrievalUri), document);
    final identifier = document[r'$id'];
    if (identifier is String) {
      final resolvedIdentifier = retrievalUri.resolve(identifier);
      if (!resolvedIdentifier.isAbsolute) {
        throw ArgumentError.value(
          identifier,
          r'$id',
          'Schema identifiers must resolve to an absolute URI.',
        );
      }
      _register(_withoutFragment(resolvedIdentifier), document);
    }
  }

  /// Resolves [reference] against [baseUri].
  ///
  /// [currentDocument] is required for a fragment-only reference when the
  /// document has not otherwise been registered under [baseUri].
  ResolvedJsonSchema? resolve({
    required Uri baseUri,
    required String reference,
    KumweJsonObject? currentDocument,
  }) {
    final Uri target;
    try {
      target = baseUri.resolve(reference);
    } on FormatException {
      return null;
    }
    final document = reference.startsWith('#') && currentDocument != null
        ? currentDocument
        : _documents[_key(_withoutFragment(target))];
    if (document == null) {
      return null;
    }
    final fragment = target.fragment;
    final Object? schema;
    if (fragment.isEmpty) {
      schema = document.value;
    } else if (fragment.startsWith('/')) {
      schema = _resolvePointer(document.value, fragment);
    } else {
      schema = _findAnchor(document.value, fragment);
    }
    if (schema is! Map<String, Object?> && schema is! bool) {
      return null;
    }
    return ResolvedJsonSchema(
      document: document,
      schema: schema as Object,
      uri: target,
    );
  }

  void _register(Uri identifier, KumweJsonObject document) {
    final key = _key(identifier);
    final previous = _documents[key];
    if (previous != null && !identical(previous, document)) {
      throw ArgumentError.value(
        identifier,
        'identifier',
        'Two schema documents use the same identifier.',
      );
    }
    _documents[key] = document;
  }

  static Object? _resolvePointer(Map<String, Object?> root, String pointer) {
    Object? current = root;
    for (final encoded in pointer.substring(1).split('/')) {
      final segment = Uri.decodeComponent(
        encoded,
      ).replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is Map<String, Object?>) {
        if (!current.containsKey(segment)) {
          return null;
        }
        current = current[segment];
        continue;
      }
      if (current is List<Object?>) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) {
          return null;
        }
        current = current[index];
        continue;
      }
      return null;
    }
    return current;
  }

  static Object? _findAnchor(Object? value, String anchor) {
    if (value is Map<String, Object?>) {
      if (value[r'$anchor'] == anchor || value[r'$dynamicAnchor'] == anchor) {
        return value;
      }
      for (final child in value.values) {
        final found = _findAnchor(child, anchor);
        if (found != null) {
          return found;
        }
      }
    } else if (value is List<Object?>) {
      for (final child in value) {
        final found = _findAnchor(child, anchor);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  static Uri _withoutFragment(Uri uri) {
    final source = uri.toString();
    final marker = source.indexOf('#');
    return Uri.parse(marker == -1 ? source : source.substring(0, marker));
  }

  static String _key(Uri uri) => uri.toString();
}

/// Validates repository JSON Schema contracts and their example instances.
///
/// The structural checks supplement JSON Schema semantics with the repository's
/// bounded-data rules: object shapes must be closed or explicitly bounded,
/// arrays and strings must have finite limits, and references must resolve.
final class JsonSchemaContractValidator {
  /// Creates a validator using [catalog] for cross-document references.
  const JsonSchemaContractValidator([this.catalog]);

  /// Optional catalog of sibling schemas.
  final JsonSchemaCatalog? catalog;

  /// Validates a JSON Schema 2020-12 contract.
  ContractValidationResult validateSchema(
    KumweJsonObject document, {
    required Uri documentUri,
  }) {
    final issues = <ContractValidationIssue>[];
    final root = document.value;
    if (root[r'$schema'] != 'https://json-schema.org/draft/2020-12/schema') {
      issues.add(
        const ContractValidationIssue(
          r'$.$schema',
          'Expected the JSON Schema 2020-12 dialect URI.',
        ),
      );
    }
    final identifier = root[r'$id'];
    final identifierUri = identifier is String
        ? Uri.tryParse(identifier)
        : null;
    if (identifier is! String ||
        identifier.isEmpty ||
        identifierUri == null ||
        !identifierUri.isAbsolute) {
      issues.add(
        const ContractValidationIssue(
          r'$.$id',
          'Expected a non-empty absolute schema identifier.',
        ),
      );
    }
    _validateSchemaNode(
      root,
      document: document,
      baseUri: _schemaBase(root, documentUri),
      location: r'$',
      issues: issues,
      depth: 0,
    );
    return ContractValidationResult(issues);
  }

  /// Validates [instance] against [schema].
  ContractValidationResult validateInstance(
    KumweJsonValue instance, {
    required KumweJsonObject schema,
    required Uri schemaUri,
  }) {
    return validateResolvedInstance(
      instance,
      schema: ResolvedJsonSchema(
        document: schema,
        schema: schema.value,
        uri: schemaUri,
      ),
    );
  }

  /// Validates [instance] against a catalog-resolved schema or subschema.
  ContractValidationResult validateResolvedInstance(
    KumweJsonValue instance, {
    required ResolvedJsonSchema schema,
  }) {
    final issues = <ContractValidationIssue>[];
    _validateValue(
      instance.value,
      schema.schema,
      document: schema.document,
      baseUri: schema.uri,
      location: r'$',
      issues: issues,
      depth: 0,
    );
    return ContractValidationResult(issues);
  }

  void _validateSchemaNode(
    Object? node, {
    required KumweJsonObject document,
    required Uri baseUri,
    required String location,
    required List<ContractValidationIssue> issues,
    required int depth,
  }) {
    if (depth > 128) {
      issues.add(
        ContractValidationIssue(location, 'Schema nesting exceeds 128 levels.'),
      );
      return;
    }
    if (node is bool) {
      return;
    }
    if (node is! Map<String, Object?>) {
      issues.add(
        ContractValidationIssue(
          location,
          'Expected an object or boolean schema.',
        ),
      );
      return;
    }
    final nodeBase = _schemaBase(node, baseUri);
    _validateReference(node, r'$ref', document, nodeBase, location, issues);
    _validateReference(
      node,
      r'$dynamicRef',
      document,
      nodeBase,
      location,
      issues,
    );
    _validateTypeKeyword(node['type'], '$location.type', issues);
    _validateEnum(node['enum'], '$location.enum', issues);
    _validateRequired(node['required'], '$location.required', issues);
    _validateNonNegativeInteger(node, 'minLength', location, issues);
    _validateNonNegativeInteger(node, 'maxLength', location, issues);
    _validateNonNegativeInteger(node, 'minItems', location, issues);
    _validateNonNegativeInteger(node, 'maxItems', location, issues);
    _validateNonNegativeInteger(node, 'minProperties', location, issues);
    _validateNonNegativeInteger(node, 'maxProperties', location, issues);
    _validateOrderedBounds(node, 'minLength', 'maxLength', location, issues);
    _validateOrderedBounds(node, 'minItems', 'maxItems', location, issues);
    _validateOrderedBounds(
      node,
      'minProperties',
      'maxProperties',
      location,
      issues,
    );

    final pattern = node['pattern'];
    if (pattern != null) {
      if (pattern is! String) {
        issues.add(
          ContractValidationIssue('$location.pattern', 'Expected a string.'),
        );
      } else {
        try {
          RegExp(pattern);
        } on FormatException {
          issues.add(
            ContractValidationIssue(
              '$location.pattern',
              'Invalid regular expression.',
            ),
          );
        }
      }
    }

    final objectShaped =
        _hasType(node, 'object') ||
        node.containsKey('additionalProperties') ||
        node.containsKey('patternProperties');
    if (objectShaped) {
      _validateObjectSchema(node, location, issues);
    }
    final arrayShaped =
        _hasType(node, 'array') ||
        node.containsKey('items') ||
        node.containsKey('prefixItems') ||
        node.containsKey('contains');
    if (arrayShaped &&
        !node.containsKey('maxItems') &&
        !node.containsKey('const') &&
        !node.containsKey('enum')) {
      issues.add(
        ContractValidationIssue(
          '$location.maxItems',
          'Array schemas require a finite maxItems bound.',
        ),
      );
    }
    if (_hasType(node, 'string') &&
        !node.containsKey('maxLength') &&
        !node.containsKey('const') &&
        !node.containsKey('enum')) {
      issues.add(
        ContractValidationIssue(
          '$location.maxLength',
          'String schemas require a finite maxLength bound.',
        ),
      );
    }

    for (final keyword in _schemaMapKeywords) {
      final children = node[keyword];
      if (children == null) {
        continue;
      }
      if (children is! Map<String, Object?>) {
        issues.add(
          ContractValidationIssue(
            '$location.$keyword',
            'Expected an object containing schemas.',
          ),
        );
        continue;
      }
      for (final entry in children.entries) {
        _validateSchemaNode(
          entry.value,
          document: document,
          baseUri: nodeBase,
          location: '$location.$keyword.${entry.key}',
          issues: issues,
          depth: depth + 1,
        );
      }
    }
    for (final keyword in _schemaArrayKeywords) {
      final children = node[keyword];
      if (children == null) {
        continue;
      }
      if (children is! List<Object?> || children.isEmpty) {
        issues.add(
          ContractValidationIssue(
            '$location.$keyword',
            'Expected a non-empty array of schemas.',
          ),
        );
        continue;
      }
      for (var index = 0; index < children.length; index++) {
        _validateSchemaNode(
          children[index],
          document: document,
          baseUri: nodeBase,
          location: '$location.$keyword[$index]',
          issues: issues,
          depth: depth + 1,
        );
      }
    }
    for (final keyword in _singleSchemaKeywords) {
      if (!node.containsKey(keyword)) {
        continue;
      }
      _validateSchemaNode(
        node[keyword],
        document: document,
        baseUri: nodeBase,
        location: '$location.$keyword',
        issues: issues,
        depth: depth + 1,
      );
    }
  }

  void _validateObjectSchema(
    Map<String, Object?> schema,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    if (!schema.containsKey('additionalProperties')) {
      issues.add(
        ContractValidationIssue(
          '$location.additionalProperties',
          'Object schemas must close or explicitly bound additional properties.',
        ),
      );
      return;
    }
    final additional = schema['additionalProperties'];
    if (additional is! bool && additional is! Map<String, Object?>) {
      issues.add(
        ContractValidationIssue(
          '$location.additionalProperties',
          'Expected a boolean or schema.',
        ),
      );
      return;
    }
    if (additional != false) {
      if (additional == true) {
        issues.add(
          ContractValidationIssue(
            '$location.additionalProperties',
            'Open maps require a bounded value schema.',
          ),
        );
      }
      if (schema['maxProperties'] is! int) {
        issues.add(
          ContractValidationIssue(
            '$location.maxProperties',
            'Open maps require a finite maxProperties bound.',
          ),
        );
      }
      if (schema['propertyNames'] is! Map<String, Object?> &&
          schema['propertyNames'] is! bool) {
        issues.add(
          ContractValidationIssue(
            '$location.propertyNames',
            'Open maps require a propertyNames schema.',
          ),
        );
      }
    }
  }

  void _validateReference(
    Map<String, Object?> schema,
    String keyword,
    KumweJsonObject document,
    Uri baseUri,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final reference = schema[keyword];
    if (reference == null) {
      return;
    }
    if (reference is! String || reference.isEmpty) {
      issues.add(
        ContractValidationIssue(
          '$location.$keyword',
          'Expected a non-empty URI-reference.',
        ),
      );
      return;
    }
    final resolved = catalog?.resolve(
      baseUri: baseUri,
      reference: reference,
      currentDocument: document,
    );
    if (catalog != null && resolved == null) {
      issues.add(
        ContractValidationIssue(
          '$location.$keyword',
          'Schema reference does not resolve: $reference',
        ),
      );
    }
  }

  void _validateValue(
    Object? instance,
    Object? schemaNode, {
    required KumweJsonObject document,
    required Uri baseUri,
    required String location,
    required List<ContractValidationIssue> issues,
    required int depth,
  }) {
    if (depth > 128) {
      issues.add(
        ContractValidationIssue(
          location,
          'Instance nesting exceeds 128 levels.',
        ),
      );
      return;
    }
    if (schemaNode == true) {
      return;
    }
    if (schemaNode == false) {
      issues.add(
        ContractValidationIssue(
          location,
          'The value is forbidden by its schema.',
        ),
      );
      return;
    }
    if (schemaNode is! Map<String, Object?>) {
      issues.add(
        ContractValidationIssue(location, 'The selected schema is invalid.'),
      );
      return;
    }
    final nodeBase = _schemaBase(schemaNode, baseUri);
    final reference = schemaNode[r'$ref'];
    if (reference is String) {
      final resolved = catalog?.resolve(
        baseUri: nodeBase,
        reference: reference,
        currentDocument: document,
      );
      if (resolved == null) {
        issues.add(
          ContractValidationIssue(
            location,
            'Schema reference does not resolve: $reference',
          ),
        );
      } else {
        _validateValue(
          instance,
          resolved.schema,
          document: resolved.document,
          baseUri: resolved.uri,
          location: location,
          issues: issues,
          depth: depth + 1,
        );
      }
    }

    if (!_matchesDeclaredType(instance, schemaNode['type'])) {
      issues.add(
        ContractValidationIssue(
          location,
          'Value does not match the declared JSON type.',
        ),
      );
      return;
    }
    if (schemaNode.containsKey('const') &&
        !_jsonEquals(instance, schemaNode['const'])) {
      issues.add(
        ContractValidationIssue(location, 'Value does not match const.'),
      );
    }
    final enumValues = schemaNode['enum'];
    if (enumValues is List<Object?> &&
        !enumValues.any((candidate) => _jsonEquals(instance, candidate))) {
      issues.add(
        ContractValidationIssue(
          location,
          'Value is not one of the allowed enum values.',
        ),
      );
    }

    _validateCompositions(
      instance,
      schemaNode,
      document,
      nodeBase,
      location,
      issues,
      depth,
    );
    if (instance is Map<String, Object?>) {
      _validateObjectValue(
        instance,
        schemaNode,
        document,
        nodeBase,
        location,
        issues,
        depth,
      );
    } else if (instance is List<Object?>) {
      _validateArrayValue(
        instance,
        schemaNode,
        document,
        nodeBase,
        location,
        issues,
        depth,
      );
    } else if (instance is String) {
      _validateStringValue(instance, schemaNode, location, issues);
    } else if (instance is num) {
      _validateNumberValue(instance, schemaNode, location, issues);
    }
  }

  void _validateCompositions(
    Object? instance,
    Map<String, Object?> schema,
    KumweJsonObject document,
    Uri baseUri,
    String location,
    List<ContractValidationIssue> issues,
    int depth,
  ) {
    final allOf = schema['allOf'];
    if (allOf is List<Object?>) {
      for (final branch in allOf) {
        _validateValue(
          instance,
          branch,
          document: document,
          baseUri: baseUri,
          location: location,
          issues: issues,
          depth: depth + 1,
        );
      }
    }
    final anyOf = schema['anyOf'];
    if (anyOf is List<Object?> &&
        _matchingBranches(
          instance,
          anyOf,
          document,
          baseUri,
          location,
          depth,
        ).isEmpty) {
      issues.add(
        ContractValidationIssue(
          location,
          'Value does not satisfy any anyOf branch.',
        ),
      );
    }
    final oneOf = schema['oneOf'];
    if (oneOf is List<Object?>) {
      final matches = _matchingBranches(
        instance,
        oneOf,
        document,
        baseUri,
        location,
        depth,
      );
      if (matches.length != 1) {
        issues.add(
          ContractValidationIssue(
            location,
            'Value must satisfy exactly one oneOf branch; matched ${matches.length}.',
          ),
        );
      }
    }
    final notSchema = schema['not'];
    if (notSchema != null &&
        _branchMatches(
          instance,
          notSchema,
          document,
          baseUri,
          location,
          depth,
        )) {
      issues.add(
        ContractValidationIssue(
          location,
          'Value matches the forbidden not schema.',
        ),
      );
    }
    final ifSchema = schema['if'];
    if (ifSchema != null) {
      final matches = _branchMatches(
        instance,
        ifSchema,
        document,
        baseUri,
        location,
        depth,
      );
      final selected = matches ? schema['then'] : schema['else'];
      if (selected != null) {
        _validateValue(
          instance,
          selected,
          document: document,
          baseUri: baseUri,
          location: location,
          issues: issues,
          depth: depth + 1,
        );
      }
    }
  }

  void _validateObjectValue(
    Map<String, Object?> instance,
    Map<String, Object?> schema,
    KumweJsonObject document,
    Uri baseUri,
    String location,
    List<ContractValidationIssue> issues,
    int depth,
  ) {
    final minProperties = schema['minProperties'];
    final maxProperties = schema['maxProperties'];
    if (minProperties is int && instance.length < minProperties) {
      issues.add(
        ContractValidationIssue(
          location,
          'Object has fewer than $minProperties properties.',
        ),
      );
    }
    if (maxProperties is int && instance.length > maxProperties) {
      issues.add(
        ContractValidationIssue(
          location,
          'Object has more than $maxProperties properties.',
        ),
      );
    }
    final required = schema['required'];
    if (required is List<Object?>) {
      for (final name in required.whereType<String>()) {
        if (!instance.containsKey(name)) {
          issues.add(
            ContractValidationIssue(
              '$location.$name',
              'Required property is missing.',
            ),
          );
        }
      }
    }
    final properties = schema['properties'] is Map<String, Object?>
        ? schema['properties']! as Map<String, Object?>
        : const <String, Object?>{};
    final patternProperties =
        schema['patternProperties'] is Map<String, Object?>
        ? schema['patternProperties']! as Map<String, Object?>
        : const <String, Object?>{};
    final additional = schema['additionalProperties'];
    for (final entry in instance.entries) {
      final propertyLocation = '$location.${entry.key}';
      var matched = false;
      if (properties.containsKey(entry.key)) {
        matched = true;
        _validateValue(
          entry.value,
          properties[entry.key],
          document: document,
          baseUri: baseUri,
          location: propertyLocation,
          issues: issues,
          depth: depth + 1,
        );
      }
      for (final patternEntry in patternProperties.entries) {
        if (RegExp(patternEntry.key).hasMatch(entry.key)) {
          matched = true;
          _validateValue(
            entry.value,
            patternEntry.value,
            document: document,
            baseUri: baseUri,
            location: propertyLocation,
            issues: issues,
            depth: depth + 1,
          );
        }
      }
      if (!matched) {
        if (additional == false) {
          issues.add(
            ContractValidationIssue(
              propertyLocation,
              'Additional property is not allowed.',
            ),
          );
        } else if (additional is Map<String, Object?> || additional is bool) {
          _validateValue(
            entry.value,
            additional,
            document: document,
            baseUri: baseUri,
            location: propertyLocation,
            issues: issues,
            depth: depth + 1,
          );
        }
      }
      final propertyNames = schema['propertyNames'];
      if (propertyNames is Map<String, Object?> || propertyNames is bool) {
        _validateValue(
          entry.key,
          propertyNames,
          document: document,
          baseUri: baseUri,
          location: '$propertyLocation (name)',
          issues: issues,
          depth: depth + 1,
        );
      }
    }
    final dependentRequired = schema['dependentRequired'];
    if (dependentRequired is Map<String, Object?>) {
      for (final entry in dependentRequired.entries) {
        if (!instance.containsKey(entry.key) || entry.value is! List<Object?>) {
          continue;
        }
        for (final dependency
            in (entry.value! as List<Object?>).whereType<String>()) {
          if (!instance.containsKey(dependency)) {
            issues.add(
              ContractValidationIssue(
                '$location.$dependency',
                'Property is required when ${entry.key} is present.',
              ),
            );
          }
        }
      }
    }
  }

  void _validateArrayValue(
    List<Object?> instance,
    Map<String, Object?> schema,
    KumweJsonObject document,
    Uri baseUri,
    String location,
    List<ContractValidationIssue> issues,
    int depth,
  ) {
    final minItems = schema['minItems'];
    final maxItems = schema['maxItems'];
    if (minItems is int && instance.length < minItems) {
      issues.add(
        ContractValidationIssue(
          location,
          'Array has fewer than $minItems items.',
        ),
      );
    }
    if (maxItems is int && instance.length > maxItems) {
      issues.add(
        ContractValidationIssue(
          location,
          'Array has more than $maxItems items.',
        ),
      );
    }
    if (schema['uniqueItems'] == true) {
      for (var left = 0; left < instance.length; left++) {
        for (var right = left + 1; right < instance.length; right++) {
          if (_jsonEquals(instance[left], instance[right])) {
            issues.add(
              ContractValidationIssue(
                '$location[$right]',
                'Array items must be unique.',
              ),
            );
          }
        }
      }
    }
    final prefixItems = schema['prefixItems'];
    var prefixCount = 0;
    if (prefixItems is List<Object?>) {
      prefixCount = prefixItems.length;
      final count = instance.length < prefixCount
          ? instance.length
          : prefixCount;
      for (var index = 0; index < count; index++) {
        _validateValue(
          instance[index],
          prefixItems[index],
          document: document,
          baseUri: baseUri,
          location: '$location[$index]',
          issues: issues,
          depth: depth + 1,
        );
      }
    }
    final items = schema['items'];
    if (items is Map<String, Object?> || items is bool) {
      for (var index = prefixCount; index < instance.length; index++) {
        _validateValue(
          instance[index],
          items,
          document: document,
          baseUri: baseUri,
          location: '$location[$index]',
          issues: issues,
          depth: depth + 1,
        );
      }
    }
    final contains = schema['contains'];
    if (contains is Map<String, Object?> || contains is bool) {
      var matches = 0;
      for (var index = 0; index < instance.length; index++) {
        if (_branchMatches(
          instance[index],
          contains,
          document,
          baseUri,
          '$location[$index]',
          depth,
        )) {
          matches++;
        }
      }
      final minContains = schema['minContains'] is int
          ? schema['minContains']! as int
          : 1;
      final maxContains = schema['maxContains'];
      if (matches < minContains ||
          (maxContains is int && matches > maxContains)) {
        issues.add(
          ContractValidationIssue(
            location,
            'Array does not satisfy contains bounds.',
          ),
        );
      }
    }
  }

  void _validateStringValue(
    String instance,
    Map<String, Object?> schema,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final length = instance.runes.length;
    final minLength = schema['minLength'];
    final maxLength = schema['maxLength'];
    if (minLength is int && length < minLength) {
      issues.add(
        ContractValidationIssue(
          location,
          'String is shorter than $minLength characters.',
        ),
      );
    }
    if (maxLength is int && length > maxLength) {
      issues.add(
        ContractValidationIssue(
          location,
          'String is longer than $maxLength characters.',
        ),
      );
    }
    final pattern = schema['pattern'];
    if (pattern is String && !RegExp(pattern).hasMatch(instance)) {
      issues.add(
        ContractValidationIssue(
          location,
          'String does not match the required pattern.',
        ),
      );
    }
    final format = schema['format'];
    if (format == 'uri') {
      final uri = Uri.tryParse(instance);
      if (uri == null || !uri.isAbsolute) {
        issues.add(
          ContractValidationIssue(location, 'String is not an absolute URI.'),
        );
      }
    } else if (format == 'uri-reference') {
      if (Uri.tryParse(instance) == null) {
        issues.add(
          ContractValidationIssue(location, 'String is not a URI-reference.'),
        );
      }
    } else if (format == 'uuid' &&
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(instance)) {
      issues.add(ContractValidationIssue(location, 'String is not a UUID.'));
    } else if (format == 'date-time' &&
        (!instance.contains('T') || DateTime.tryParse(instance) == null)) {
      issues.add(
        ContractValidationIssue(
          location,
          'String is not an RFC 3339 date-time.',
        ),
      );
    } else if (format == 'date' && !_date.hasMatch(instance)) {
      issues.add(
        ContractValidationIssue(
          location,
          'String is not an RFC 3339 full-date.',
        ),
      );
    }
  }

  void _validateNumberValue(
    num instance,
    Map<String, Object?> schema,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final minimum = schema['minimum'];
    final maximum = schema['maximum'];
    final exclusiveMinimum = schema['exclusiveMinimum'];
    final exclusiveMaximum = schema['exclusiveMaximum'];
    if (minimum is num && instance < minimum) {
      issues.add(
        ContractValidationIssue(location, 'Number is below minimum $minimum.'),
      );
    }
    if (maximum is num && instance > maximum) {
      issues.add(
        ContractValidationIssue(location, 'Number is above maximum $maximum.'),
      );
    }
    if (exclusiveMinimum is num && instance <= exclusiveMinimum) {
      issues.add(
        ContractValidationIssue(
          location,
          'Number must be greater than $exclusiveMinimum.',
        ),
      );
    }
    if (exclusiveMaximum is num && instance >= exclusiveMaximum) {
      issues.add(
        ContractValidationIssue(
          location,
          'Number must be less than $exclusiveMaximum.',
        ),
      );
    }
    final multipleOf = schema['multipleOf'];
    if (multipleOf is num && multipleOf > 0) {
      final quotient = instance / multipleOf;
      if ((quotient - quotient.round()).abs() > 1e-10) {
        issues.add(
          ContractValidationIssue(
            location,
            'Number is not a multiple of $multipleOf.',
          ),
        );
      }
    }
  }

  List<int> _matchingBranches(
    Object? instance,
    List<Object?> branches,
    KumweJsonObject document,
    Uri baseUri,
    String location,
    int depth,
  ) {
    final matches = <int>[];
    for (var index = 0; index < branches.length; index++) {
      if (_branchMatches(
        instance,
        branches[index],
        document,
        baseUri,
        location,
        depth,
      )) {
        matches.add(index);
      }
    }
    return matches;
  }

  bool _branchMatches(
    Object? instance,
    Object? schema,
    KumweJsonObject document,
    Uri baseUri,
    String location,
    int depth,
  ) {
    final branchIssues = <ContractValidationIssue>[];
    _validateValue(
      instance,
      schema,
      document: document,
      baseUri: baseUri,
      location: location,
      issues: branchIssues,
      depth: depth + 1,
    );
    return branchIssues.isEmpty;
  }

  static bool _matchesDeclaredType(Object? value, Object? declared) {
    if (declared == null) {
      return true;
    }
    if (declared is String) {
      return _matchesType(value, declared);
    }
    if (declared is List<Object?>) {
      return declared.whereType<String>().any(
        (type) => _matchesType(value, type),
      );
    }
    return false;
  }

  static bool _matchesType(Object? value, String type) {
    return switch (type) {
      'null' => value == null,
      'boolean' => value is bool,
      'object' => value is Map<String, Object?>,
      'array' => value is List<Object?>,
      'number' => value is num,
      'integer' =>
        value is int ||
            (value is double &&
                value.isFinite &&
                value == value.roundToDouble()),
      'string' => value is String,
      _ => false,
    };
  }

  static bool _jsonEquals(Object? left, Object? right) {
    if (left is num && right is num) {
      return left == right;
    }
    if (left is List<Object?> && right is List<Object?>) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index++) {
        if (!_jsonEquals(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map<String, Object?> && right is Map<String, Object?>) {
      if (left.length != right.length || !left.keys.every(right.containsKey)) {
        return false;
      }
      return left.entries.every(
        (entry) => _jsonEquals(entry.value, right[entry.key]),
      );
    }
    return left == right;
  }

  static bool _hasType(Map<String, Object?> schema, String expected) {
    final type = schema['type'];
    return type == expected ||
        (type is List<Object?> && type.contains(expected));
  }

  static Uri _schemaBase(Map<String, Object?> schema, Uri fallback) {
    final identifier = schema[r'$id'];
    if (identifier is! String) {
      return fallback;
    }
    try {
      return fallback.resolve(identifier);
    } on FormatException {
      return fallback;
    }
  }

  static void _validateRequired(
    Object? value,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    if (value != null &&
        (value is! List<Object?> ||
            value.any((item) => item is! String) ||
            value.toSet().length != value.length)) {
      issues.add(
        ContractValidationIssue(
          location,
          'Expected an array of unique string property names.',
        ),
      );
    }
  }

  static void _validateTypeKeyword(
    Object? value,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    if (value == null) {
      return;
    }
    if (value is String) {
      if (!_jsonTypes.contains(value)) {
        issues.add(
          ContractValidationIssue(location, 'Unknown JSON type $value.'),
        );
      }
      return;
    }
    if (value is! List<Object?> ||
        value.isEmpty ||
        value.any((type) => type is! String || !_jsonTypes.contains(type)) ||
        value.toSet().length != value.length) {
      issues.add(
        ContractValidationIssue(
          location,
          'Expected a JSON type or a non-empty array of unique JSON types.',
        ),
      );
    }
  }

  static void _validateEnum(
    Object? value,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    if (value == null) {
      return;
    }
    if (value is! List<Object?> || value.isEmpty) {
      issues.add(
        ContractValidationIssue(location, 'Expected a non-empty enum array.'),
      );
      return;
    }
    for (var left = 0; left < value.length; left++) {
      for (var right = left + 1; right < value.length; right++) {
        if (_jsonEquals(value[left], value[right])) {
          issues.add(
            ContractValidationIssue(location, 'Enum values must be unique.'),
          );
          return;
        }
      }
    }
  }

  static void _validateNonNegativeInteger(
    Map<String, Object?> schema,
    String keyword,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final value = schema[keyword];
    if (value != null && (value is! int || value < 0)) {
      issues.add(
        ContractValidationIssue(
          '$location.$keyword',
          'Expected a non-negative integer.',
        ),
      );
    }
  }

  static void _validateOrderedBounds(
    Map<String, Object?> schema,
    String minimumKeyword,
    String maximumKeyword,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final minimum = schema[minimumKeyword];
    final maximum = schema[maximumKeyword];
    if (minimum is int && maximum is int && minimum > maximum) {
      issues.add(
        ContractValidationIssue(
          '$location.$maximumKeyword',
          '$maximumKeyword cannot be smaller than $minimumKeyword.',
        ),
      );
    }
  }

  static const Set<String> _jsonTypes = {
    'null',
    'boolean',
    'object',
    'array',
    'number',
    'integer',
    'string',
  };

  static const Set<String> _schemaMapKeywords = {
    r'$defs',
    'definitions',
    'properties',
    'patternProperties',
    'dependentSchemas',
  };

  static const Set<String> _schemaArrayKeywords = {
    'allOf',
    'anyOf',
    'oneOf',
    'prefixItems',
  };

  static const Set<String> _singleSchemaKeywords = {
    'additionalProperties',
    'propertyNames',
    'items',
    'contains',
    'not',
    'if',
    'then',
    'else',
  };

  static final RegExp _date = RegExp(
    r'^[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])$',
  );
}
