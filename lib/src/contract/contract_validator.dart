import '../json/kumwe_json.dart';

/// One structural or semantic OpenAPI contract violation.
final class ContractValidationIssue {
  /// Creates an issue at a JSON-style [path].
  const ContractValidationIssue(this.path, this.message);

  /// Location within the validated document.
  final String path;

  /// Human-readable violation.
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Result of validating one OpenAPI contract.
final class ContractValidationResult {
  /// Creates an immutable result.
  ContractValidationResult(Iterable<ContractValidationIssue> issues)
    : issues = List<ContractValidationIssue>.unmodifiable(issues);

  /// Violations found in deterministic traversal order.
  final List<ContractValidationIssue> issues;

  /// Whether no violations were found.
  bool get isValid => issues.isEmpty;
}

/// Performs dependency-free validation needed before SDK consumption.
///
/// This is intentionally endpoint-neutral. It validates OpenAPI structure,
/// operation identity, local references, responses, and path-template
/// parameters without assuming any particular Kumwe route inventory.
final class OpenApiContractValidator {
  /// Validates [document].
  ContractValidationResult validate(KumweJsonObject document) {
    final issues = <ContractValidationIssue>[];
    final root = document.value;
    final version = root['openapi'];
    if (version is! String ||
        !RegExp(r'^3\.[0-9]+\.[0-9]+$').hasMatch(version)) {
      issues.add(
        const ContractValidationIssue(
          r'$.openapi',
          'Expected an OpenAPI 3.x semantic version.',
        ),
      );
    }
    final info = _asObject(root['info']);
    if (info == null) {
      issues.add(
        const ContractValidationIssue(r'$.info', 'Expected an info object.'),
      );
    } else {
      _requireNonEmptyString(info, 'title', r'$.info.title', issues);
      _requireNonEmptyString(info, 'version', r'$.info.version', issues);
    }
    final paths = _asObject(root['paths']);
    if (paths == null) {
      issues.add(
        const ContractValidationIssue(r'$.paths', 'Expected a paths object.'),
      );
    } else {
      _validatePaths(root, paths, issues);
    }
    _validateReferences(root, root, r'$', issues);
    return ContractValidationResult(issues);
  }

  void _validatePaths(
    Map<String, Object?> root,
    Map<String, Object?> paths,
    List<ContractValidationIssue> issues,
  ) {
    final operationIds = <String, String>{};
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      final pathLocation = '\$.paths[${_quoted(path)}]';
      if (!path.startsWith('/')) {
        issues.add(
          ContractValidationIssue(
            pathLocation,
            'Path templates must start with /.',
          ),
        );
      }
      final pathItem = _asObject(pathEntry.value);
      if (pathItem == null) {
        issues.add(
          ContractValidationIssue(pathLocation, 'Expected a Path Item object.'),
        );
        continue;
      }
      final placeholders = RegExp(
        r'\{([^{}]+)\}',
      ).allMatches(path).map((match) => match.group(1)!).toSet();
      final sharedParameters = _parameterList(
        root,
        pathItem['parameters'],
        '$pathLocation.parameters',
        issues,
      );
      for (final method in _methods) {
        if (!pathItem.containsKey(method)) {
          continue;
        }
        final operationLocation = '$pathLocation.$method';
        final operation = _asObject(pathItem[method]);
        if (operation == null) {
          issues.add(
            ContractValidationIssue(
              operationLocation,
              'Expected an operation object.',
            ),
          );
          continue;
        }
        final operationId = operation['operationId'];
        if (operationId is! String || operationId.trim().isEmpty) {
          issues.add(
            ContractValidationIssue(
              '$operationLocation.operationId',
              'Expected a non-empty operationId.',
            ),
          );
        } else {
          final previous = operationIds[operationId];
          if (previous != null) {
            issues.add(
              ContractValidationIssue(
                '$operationLocation.operationId',
                'operationId is already used by $previous.',
              ),
            );
          } else {
            operationIds[operationId] = '${method.toUpperCase()} $path';
          }
        }
        final ownParameters = _parameterList(
          root,
          operation['parameters'],
          '$operationLocation.parameters',
          issues,
        );
        _validatePathParameters(
          placeholders,
          _mergeParameters(sharedParameters, ownParameters),
          operationLocation,
          issues,
        );
        _validateResponses(
          operation['responses'],
          operationLocation,
          method,
          issues,
        );
        _validateRequestBody(
          operation['requestBody'],
          operationLocation,
          issues,
        );
      }
    }
  }

  void _validatePathParameters(
    Set<String> placeholders,
    List<Map<String, Object?>> parameters,
    String operationLocation,
    List<ContractValidationIssue> issues,
  ) {
    final declared = <String, int>{};
    for (final parameter in parameters) {
      if (parameter['in'] != 'path') {
        continue;
      }
      final name = parameter['name'];
      if (name is! String || name.isEmpty) {
        issues.add(
          ContractValidationIssue(
            '$operationLocation.parameters',
            'Path parameters require a non-empty name.',
          ),
        );
        continue;
      }
      declared[name] = (declared[name] ?? 0) + 1;
      if (parameter['required'] != true) {
        issues.add(
          ContractValidationIssue(
            '$operationLocation.parameters',
            'Path parameter {$name} must set required to true.',
          ),
        );
      }
    }
    for (final placeholder in placeholders) {
      final count = declared[placeholder] ?? 0;
      if (count == 0) {
        issues.add(
          ContractValidationIssue(
            '$operationLocation.parameters',
            'Path template parameter {$placeholder} is not declared.',
          ),
        );
      } else if (count > 1) {
        issues.add(
          ContractValidationIssue(
            '$operationLocation.parameters',
            'Path template parameter {$placeholder} is declared more than once.',
          ),
        );
      }
    }
    for (final name in declared.keys) {
      if (!placeholders.contains(name)) {
        issues.add(
          ContractValidationIssue(
            '$operationLocation.parameters',
            'Path parameter {$name} does not occur in the template.',
          ),
        );
      }
    }
  }

  List<Map<String, Object?>> _parameterList(
    Map<String, Object?> root,
    Object? value,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    if (value == null) {
      return const [];
    }
    final list = _asList(value);
    if (list == null) {
      issues.add(
        ContractValidationIssue(location, 'Expected a parameter array.'),
      );
      return const [];
    }
    final parameters = <Map<String, Object?>>[];
    final identities = <String>{};
    for (var index = 0; index < list.length; index++) {
      final itemLocation = '$location[$index]';
      final candidate = _asObject(list[index]);
      if (candidate == null) {
        issues.add(
          ContractValidationIssue(itemLocation, 'Expected a parameter object.'),
        );
        continue;
      }
      final reference = candidate[r'$ref'];
      if (reference is String) {
        if (reference.startsWith('#/')) {
          final resolved = _asObject(_resolvePointer(root, reference));
          if (resolved != null) {
            parameters.add(resolved);
            _validateParameter(resolved, itemLocation, issues);
            _recordParameterIdentity(
              resolved,
              itemLocation,
              identities,
              issues,
            );
          }
        }
        continue;
      }
      parameters.add(candidate);
      _validateParameter(candidate, itemLocation, issues);
      _recordParameterIdentity(candidate, itemLocation, identities, issues);
    }
    return parameters;
  }

  List<Map<String, Object?>> _mergeParameters(
    List<Map<String, Object?>> shared,
    List<Map<String, Object?>> operation,
  ) {
    final merged = <String, Map<String, Object?>>{};
    var anonymous = 0;
    for (final parameter in [...shared, ...operation]) {
      final name = parameter['name'];
      final location = parameter['in'];
      final identity = name is String && location is String
          ? '$location\u0000$name'
          : '\u0000anonymous-${anonymous++}';
      merged[identity] = parameter;
    }
    return merged.values.toList(growable: false);
  }

  void _validateParameter(
    Map<String, Object?> parameter,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final name = parameter['name'];
    final source = parameter['in'];
    if (name is! String || name.trim().isEmpty) {
      issues.add(
        ContractValidationIssue(
          '$location.name',
          'Expected a non-empty parameter name.',
        ),
      );
    }
    if (source is! String || !_parameterLocations.contains(source)) {
      issues.add(
        ContractValidationIssue(
          '$location.in',
          'Parameter location must be query, header, path, or cookie.',
        ),
      );
    }
    if (source == 'path' && parameter['required'] != true) {
      issues.add(
        ContractValidationIssue(
          '$location.required',
          'Path parameters must set required to true.',
        ),
      );
    }
    final schema = parameter['schema'];
    final content = parameter['content'];
    final hasSchema = schema is Map<String, Object?> || schema is bool;
    final hasContent = content != null;
    if (hasSchema == hasContent) {
      issues.add(
        ContractValidationIssue(
          location,
          'Parameters require exactly one schema or content declaration.',
        ),
      );
    }
    if (hasContent) {
      _validateContent(content, '$location.content', issues);
    }
  }

  void _recordParameterIdentity(
    Map<String, Object?> parameter,
    String location,
    Set<String> identities,
    List<ContractValidationIssue> issues,
  ) {
    final name = parameter['name'];
    final source = parameter['in'];
    if (name is! String || source is! String) {
      return;
    }
    if (!identities.add('$source\u0000$name')) {
      issues.add(
        ContractValidationIssue(
          location,
          'A parameter with the same name and location is declared twice.',
        ),
      );
    }
  }

  void _validateResponses(
    Object? value,
    String operationLocation,
    String method,
    List<ContractValidationIssue> issues,
  ) {
    final responses = _asObject(value);
    if (responses == null || responses.isEmpty) {
      issues.add(
        ContractValidationIssue(
          '$operationLocation.responses',
          'Expected at least one response.',
        ),
      );
      return;
    }
    for (final responseEntry in responses.entries) {
      if (responseEntry.key != 'default' &&
          !RegExp(r'^[1-5](?:[0-9]{2}|XX)$').hasMatch(responseEntry.key)) {
        issues.add(
          ContractValidationIssue(
            '$operationLocation.responses.${responseEntry.key}',
            'Response keys must be an HTTP status, status range, or default.',
          ),
        );
      }
      final response = _asObject(responseEntry.value);
      final responseLocation =
          '$operationLocation.responses.${responseEntry.key}';
      if (response == null) {
        issues.add(
          ContractValidationIssue(
            responseLocation,
            'Expected a response object.',
          ),
        );
        continue;
      }
      if (response.containsKey(r'$ref')) {
        continue;
      }
      final description = response['description'];
      if (description is! String || description.trim().isEmpty) {
        issues.add(
          ContractValidationIssue(
            '$responseLocation.description',
            'Expected a non-empty response description.',
          ),
        );
      }
      final content = response['content'];
      if (content != null) {
        _validateContent(content, '$responseLocation.content', issues);
      } else if (!_isBodylessResponse(responseEntry.key, method, response)) {
        issues.add(
          ContractValidationIssue(
            '$responseLocation.content',
            'Responses require typed content or an explicit bodyless declaration.',
          ),
        );
      }
    }
  }

  void _validateRequestBody(
    Object? value,
    String operationLocation,
    List<ContractValidationIssue> issues,
  ) {
    if (value == null) {
      return;
    }
    final body = _asObject(value);
    final location = '$operationLocation.requestBody';
    if (body == null) {
      issues.add(
        ContractValidationIssue(location, 'Expected a Request Body object.'),
      );
      return;
    }
    if (body.containsKey(r'$ref')) {
      return;
    }
    final content = _asObject(body['content']);
    if (content == null || content.isEmpty) {
      issues.add(
        ContractValidationIssue(location, 'Request bodies require content.'),
      );
      return;
    }
    _validateContent(content, '$location.content', issues);
  }

  void _validateContent(
    Object? value,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final content = _asObject(value);
    if (content == null || content.isEmpty) {
      issues.add(
        ContractValidationIssue(location, 'Expected at least one media type.'),
      );
      return;
    }
    for (final entry in content.entries) {
      final mediaLocation = '$location.${entry.key}';
      if (entry.key.trim().isEmpty) {
        issues.add(
          ContractValidationIssue(
            mediaLocation,
            'Media types cannot be empty.',
          ),
        );
      }
      final media = _asObject(entry.value);
      if (media == null) {
        issues.add(
          ContractValidationIssue(
            mediaLocation,
            'Expected a Media Type object.',
          ),
        );
        continue;
      }
      final schema = media['schema'];
      if (schema is! Map<String, Object?> && schema is! bool) {
        issues.add(
          ContractValidationIssue(
            '$mediaLocation.schema',
            'Media types require a response or request schema.',
          ),
        );
      }
    }
  }

  bool _isBodylessResponse(
    String status,
    String method,
    Map<String, Object?> response,
  ) {
    return method == 'head' ||
        status.startsWith('1') ||
        status == '204' ||
        status == '205' ||
        status == '304' ||
        response['x-kumwe-bodyless'] == true;
  }

  void _validateReferences(
    Map<String, Object?> root,
    Object? value,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final object = _asObject(value);
    if (object != null) {
      final reference = object[r'$ref'];
      if (reference is String && reference.startsWith('#/')) {
        if (_resolvePointer(root, reference) == null) {
          issues.add(
            ContractValidationIssue(
              location,
              'Local reference does not resolve: $reference',
            ),
          );
        }
      }
      for (final entry in object.entries) {
        _validateReferences(
          root,
          entry.value,
          '$location.${entry.key}',
          issues,
        );
      }
      return;
    }
    final list = _asList(value);
    if (list != null) {
      for (var index = 0; index < list.length; index++) {
        _validateReferences(root, list[index], '$location[$index]', issues);
      }
    }
  }

  Object? _resolvePointer(Map<String, Object?> root, String reference) {
    Object? current = root;
    for (final encoded in reference.substring(2).split('/')) {
      final segment = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
      final object = _asObject(current);
      if (object != null) {
        if (!object.containsKey(segment)) {
          return null;
        }
        current = object[segment];
        continue;
      }
      final list = _asList(current);
      final index = int.tryParse(segment);
      if (list == null || index == null || index < 0 || index >= list.length) {
        return null;
      }
      current = list[index];
    }
    return current;
  }

  void _requireNonEmptyString(
    Map<String, Object?> object,
    String member,
    String location,
    List<ContractValidationIssue> issues,
  ) {
    final value = object[member];
    if (value is! String || value.trim().isEmpty) {
      issues.add(
        ContractValidationIssue(location, 'Expected a non-empty string.'),
      );
    }
  }

  static Map<String, Object?>? _asObject(Object? value) {
    return value is Map<String, Object?> ? value : null;
  }

  static List<Object?>? _asList(Object? value) {
    return value is List<Object?> ? value : null;
  }

  static String _quoted(String value) {
    return '"${value.replaceAll('"', r'\"')}"';
  }

  static const Set<String> _methods = {
    'get',
    'put',
    'post',
    'delete',
    'options',
    'head',
    'patch',
    'trace',
  };

  static const Set<String> _parameterLocations = {
    'query',
    'header',
    'path',
    'cookie',
  };
}
