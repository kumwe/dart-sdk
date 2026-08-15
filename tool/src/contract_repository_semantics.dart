import 'package:kumwe_sdk/kumwe_sdk.dart';

/// Validates cross-field semantics that JSON Schema cannot express.
///
/// Contract kinds are detected from the declared schema's shape. This keeps
/// validation independent of repository filenames, proposal identifiers, and
/// the current number or spelling of profiles, requirements, and surfaces.
final class ContractRepositorySemanticValidator {
  /// Creates a stateless repository semantic validator.
  const ContractRepositorySemanticValidator();

  /// Validates [instance] according to semantic structures in [declaredSchema].
  ContractValidationResult validateInstance(
    KumweJsonObject instance, {
    required KumweJsonObject declaredSchema,
  }) {
    final issues = <ContractValidationIssue>[];
    if (_declaresContractIndex(declaredSchema.value)) {
      _validateContractIndex(instance.value, issues);
    }
    if (_declaresClientSurfaceManifest(declaredSchema.value)) {
      _validateClientSurfaceManifest(instance.value, issues);
    }
    issues.sort(_compareIssues);
    return ContractValidationResult(issues);
  }

  void _validateContractIndex(
    Map<String, Object?> root,
    List<ContractValidationIssue> issues,
  ) {
    final profiles = <_Profile>[];
    final profilesById = <String, _Profile>{};
    final profileLocations = <String, String>{};
    final rawProfiles = _asList(root['profiles']);
    for (var index = 0; index < rawProfiles.length; index++) {
      final value = _asObject(rawProfiles[index]);
      if (value == null) {
        continue;
      }
      final path = '\$.profiles[$index]';
      final id = value['id'];
      if (id is! String) {
        continue;
      }
      _recordUniqueIdentifier(
        id: id,
        path: '$path.id',
        kind: 'Profile',
        locations: profileLocations,
        issues: issues,
      );
      final profile = _Profile(
        id: id,
        path: path,
        requiredRequirements: _references(
          value['required_requirements'],
          '$path.required_requirements',
        ),
      );
      profiles.add(profile);
      profilesById.putIfAbsent(id, () => profile);
    }

    final requirements = <_Requirement>[];
    final requirementsById = <String, _Requirement>{};
    final requirementLocations = <String, String>{};
    final capabilityLocations = <String, String>{};
    final rawRequirements = _asList(root['requirements']);
    for (var index = 0; index < rawRequirements.length; index++) {
      final value = _asObject(rawRequirements[index]);
      if (value == null) {
        continue;
      }
      final path = '\$.requirements[$index]';
      final id = value['id'];
      if (id is! String) {
        continue;
      }
      _recordUniqueIdentifier(
        id: id,
        path: '$path.id',
        kind: 'Requirement',
        locations: requirementLocations,
        issues: issues,
      );
      final capabilityId = value['capability_id'];
      if (capabilityId is String) {
        _recordUniqueIdentifier(
          id: capabilityId,
          path: '$path.capability_id',
          kind: 'Capability',
          locations: capabilityLocations,
          issues: issues,
        );
      }
      final requirement = _Requirement(
        id: id,
        path: path,
        requiredFor: _references(value['required_for'], '$path.required_for'),
        dependencies: _references(value['depends_on'], '$path.depends_on'),
      );
      requirements.add(requirement);
      requirementsById.putIfAbsent(id, () => requirement);
    }

    for (final profile in profiles) {
      for (final reference in profile.requiredRequirements) {
        final requirement = requirementsById[reference.value];
        if (requirement == null) {
          issues.add(
            ContractValidationIssue(
              reference.path,
              'Requirement ${reference.value} does not resolve.',
            ),
          );
          continue;
        }
        if (!requirement.requiredFor.any(
          (candidate) => candidate.value == profile.id,
        )) {
          issues.add(
            ContractValidationIssue(
              reference.path,
              'Requirement ${requirement.id} does not list profile '
              '${profile.id} in required_for.',
            ),
          );
        }
      }
    }

    for (final requirement in requirements) {
      for (final reference in requirement.requiredFor) {
        final profile = profilesById[reference.value];
        if (profile == null) {
          issues.add(
            ContractValidationIssue(
              reference.path,
              'Profile ${reference.value} does not resolve.',
            ),
          );
          continue;
        }
        if (!profile.requiredRequirements.any(
          (candidate) => candidate.value == requirement.id,
        )) {
          issues.add(
            ContractValidationIssue(
              reference.path,
              'Profile ${profile.id} does not list requirement '
              '${requirement.id} in required_requirements.',
            ),
          );
        }
      }
      for (final dependency in requirement.dependencies) {
        if (!requirementsById.containsKey(dependency.value)) {
          issues.add(
            ContractValidationIssue(
              dependency.path,
              'Requirement dependency ${dependency.value} does not resolve.',
            ),
          );
        }
      }
    }

    _validateProfileDependencyClosure(profiles, requirementsById, issues);
    _validateRequirementDependencyCycles(requirementsById, issues);
  }

  void _validateProfileDependencyClosure(
    List<_Profile> profiles,
    Map<String, _Requirement> requirementsById,
    List<ContractValidationIssue> issues,
  ) {
    for (final profile in profiles) {
      final declared = profile.requiredRequirements
          .map((reference) => reference.value)
          .toSet();
      final missing = <String, String>{};
      for (final rootReference in profile.requiredRequirements) {
        _collectMissingDependencies(
          rootRequirement: rootReference.value,
          currentRequirement: rootReference.value,
          chain: <String>[rootReference.value],
          active: <String>{},
          declared: declared,
          requirementsById: requirementsById,
          missing: missing,
        );
      }
      final missingIds = missing.keys.toList()..sort();
      for (final id in missingIds) {
        issues.add(
          ContractValidationIssue(
            '${profile.path}.required_requirements',
            'Profile ${profile.id} is not closed over dependency $id '
                '(${missing[id]}).',
          ),
        );
      }
    }
  }

  void _collectMissingDependencies({
    required String rootRequirement,
    required String currentRequirement,
    required List<String> chain,
    required Set<String> active,
    required Set<String> declared,
    required Map<String, _Requirement> requirementsById,
    required Map<String, String> missing,
  }) {
    if (!active.add(currentRequirement)) {
      return;
    }
    final requirement = requirementsById[currentRequirement];
    if (requirement != null) {
      for (final dependency in requirement.dependencies) {
        if (!requirementsById.containsKey(dependency.value)) {
          continue;
        }
        final nextChain = <String>[...chain, dependency.value];
        if (!declared.contains(dependency.value)) {
          missing.putIfAbsent(
            dependency.value,
            () => '${nextChain.join(' -> ')} from $rootRequirement',
          );
        }
        _collectMissingDependencies(
          rootRequirement: rootRequirement,
          currentRequirement: dependency.value,
          chain: nextChain,
          active: active,
          declared: declared,
          requirementsById: requirementsById,
          missing: missing,
        );
      }
    }
    active.remove(currentRequirement);
  }

  void _validateRequirementDependencyCycles(
    Map<String, _Requirement> requirementsById,
    List<ContractValidationIssue> issues,
  ) {
    final state = <String, int>{};
    final stack = <String>[];
    final reportedCycles = <String>{};

    void visit(String id) {
      state[id] = 1;
      stack.add(id);
      final requirement = requirementsById[id]!;
      for (final dependency in requirement.dependencies) {
        if (!requirementsById.containsKey(dependency.value)) {
          continue;
        }
        final dependencyState = state[dependency.value] ?? 0;
        if (dependencyState == 0) {
          visit(dependency.value);
        } else if (dependencyState == 1) {
          final start = stack.indexOf(dependency.value);
          final cycle = <String>[...stack.sublist(start), dependency.value];
          final canonical = _canonicalCycle(cycle);
          if (reportedCycles.add(canonical.key)) {
            issues.add(
              ContractValidationIssue(
                dependency.path,
                'Requirement dependency cycle detected: '
                '${canonical.display}.',
              ),
            );
          }
        }
      }
      stack.removeLast();
      state[id] = 2;
    }

    for (final id in requirementsById.keys) {
      if ((state[id] ?? 0) == 0) {
        visit(id);
      }
    }
  }

  void _validateClientSurfaceManifest(
    Map<String, Object?> root,
    List<ContractValidationIssue> issues,
  ) {
    final contractLocations = <String, String>{};
    final requiredContracts = _asList(root['required_contracts']);
    for (var index = 0; index < requiredContracts.length; index++) {
      final contract = _asObject(requiredContracts[index]);
      final id = contract?['id'];
      if (id is String) {
        _recordUniqueIdentifier(
          id: id,
          path: '\$.required_contracts[$index].id',
          kind: 'Required contract',
          locations: contractLocations,
          issues: issues,
        );
      }
    }

    final identifierLocations = <String, String>{};
    final surfaces = _asList(root['surfaces']);
    for (var surfaceIndex = 0; surfaceIndex < surfaces.length; surfaceIndex++) {
      final surface = _asObject(surfaces[surfaceIndex]);
      if (surface == null) {
        continue;
      }
      final surfacePath = '\$.surfaces[$surfaceIndex]';
      final surfaceId = surface['id'];
      if (surfaceId is String) {
        _recordUniqueIdentifier(
          id: surfaceId,
          path: '$surfacePath.id',
          kind: 'Surface',
          locations: identifierLocations,
          issues: issues,
        );
      }

      final localScreenIds = <String>{};
      final screens = _asList(surface['screens']);
      for (final rawScreen in screens) {
        final screen = _asObject(rawScreen);
        final id = screen?['id'];
        if (id is String) {
          localScreenIds.add(id);
        }
      }

      final navigation = _asList(surface['navigation']);
      for (
        var navigationIndex = 0;
        navigationIndex < navigation.length;
        navigationIndex++
      ) {
        final item = _asObject(navigation[navigationIndex]);
        if (item == null) {
          continue;
        }
        final path = '$surfacePath.navigation[$navigationIndex]';
        final id = item['id'];
        if (id is String) {
          _recordUniqueIdentifier(
            id: id,
            path: '$path.id',
            kind: 'Navigation item',
            locations: identifierLocations,
            issues: issues,
          );
        }
        final screenReference = item['screen'];
        if (screenReference is String &&
            !localScreenIds.contains(screenReference)) {
          issues.add(
            ContractValidationIssue(
              '$path.screen',
              'Screen $screenReference does not resolve within its '
                  'containing surface.',
            ),
          );
        }
      }

      for (var screenIndex = 0; screenIndex < screens.length; screenIndex++) {
        final screen = _asObject(screens[screenIndex]);
        final id = screen?['id'];
        if (id is String) {
          _recordUniqueIdentifier(
            id: id,
            path: '$surfacePath.screens[$screenIndex].id',
            kind: 'Screen',
            locations: identifierLocations,
            issues: issues,
          );
        }
      }
    }
  }

  static void _recordUniqueIdentifier({
    required String id,
    required String path,
    required String kind,
    required Map<String, String> locations,
    required List<ContractValidationIssue> issues,
  }) {
    final previous = locations[id];
    if (previous == null) {
      locations[id] = path;
      return;
    }
    issues.add(
      ContractValidationIssue(
        path,
        '$kind identifier $id duplicates $previous.',
      ),
    );
  }

  static List<_Reference> _references(Object? value, String path) {
    final list = _asList(value);
    final references = <_Reference>[];
    for (var index = 0; index < list.length; index++) {
      final reference = list[index];
      if (reference is String) {
        references.add(_Reference(reference, '$path[$index]'));
      }
    }
    return references;
  }

  static bool _declaresContractIndex(Map<String, Object?> schema) {
    return _hasSchemaProperties(schema, const {'profiles', 'requirements'}) &&
        _hasDefinitions(schema, const {'profile', 'requirement'});
  }

  static bool _declaresClientSurfaceManifest(Map<String, Object?> schema) {
    return _hasSchemaProperties(schema, const {
          'required_contracts',
          'surfaces',
        }) &&
        _hasDefinitions(schema, const {'surface', 'navigationItem', 'screen'});
  }

  static bool _hasSchemaProperties(
    Map<String, Object?> schema,
    Set<String> expected,
  ) {
    final properties = _asObject(schema['properties']);
    return properties != null && expected.every(properties.containsKey);
  }

  static bool _hasDefinitions(
    Map<String, Object?> schema,
    Set<String> expected,
  ) {
    final definitions = _asObject(schema[r'$defs']);
    return definitions != null && expected.every(definitions.containsKey);
  }

  static List<Object?> _asList(Object? value) {
    return value is List<Object?> ? value : const <Object?>[];
  }

  static Map<String, Object?>? _asObject(Object? value) {
    return value is Map<String, Object?> ? value : null;
  }

  static int _compareIssues(
    ContractValidationIssue left,
    ContractValidationIssue right,
  ) {
    final byPath = left.path.compareTo(right.path);
    return byPath != 0 ? byPath : left.message.compareTo(right.message);
  }

  static _CanonicalCycle _canonicalCycle(List<String> cycle) {
    final body = cycle.sublist(0, cycle.length - 1);
    var best = body;
    var bestKey = body.join('\u0000');
    for (var index = 1; index < body.length; index++) {
      final candidate = <String>[
        ...body.sublist(index),
        ...body.sublist(0, index),
      ];
      final candidateKey = candidate.join('\u0000');
      if (candidateKey.compareTo(bestKey) < 0) {
        best = candidate;
        bestKey = candidateKey;
      }
    }
    return _CanonicalCycle(bestKey, <String>[...best, best.first].join(' -> '));
  }
}

final class _Reference {
  const _Reference(this.value, this.path);

  final String value;
  final String path;
}

final class _Profile {
  const _Profile({
    required this.id,
    required this.path,
    required this.requiredRequirements,
  });

  final String id;
  final String path;
  final List<_Reference> requiredRequirements;
}

final class _Requirement {
  const _Requirement({
    required this.id,
    required this.path,
    required this.requiredFor,
    required this.dependencies,
  });

  final String id;
  final String path;
  final List<_Reference> requiredFor;
  final List<_Reference> dependencies;
}

final class _CanonicalCycle {
  const _CanonicalCycle(this.key, this.display);

  final String key;
  final String display;
}
