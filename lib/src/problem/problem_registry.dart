import 'dart:collection';

import '../mutation/retry_classification.dart';

/// One validation failure bound to the exact input field it names.
final class KumweFieldViolation {
  /// Creates a validated field violation.
  factory KumweFieldViolation({
    required String field,
    required String code,
    String? message,
  }) {
    if (!_fieldPattern.hasMatch(field)) {
      throw const FormatException(
        'Field violation paths need 1 to 256 supported characters.',
      );
    }
    if (!_codePattern.hasMatch(code)) {
      throw const FormatException(
        'Field violation codes are lowercase hyphenated identifiers.',
      );
    }
    if (message != null && (message.isEmpty || message.length > 500)) {
      throw const FormatException(
        'Field violation messages need 1 to 500 characters.',
      );
    }
    return KumweFieldViolation._(field: field, code: code, message: message);
  }

  const KumweFieldViolation._({
    required this.field,
    required this.code,
    required this.message,
  });

  /// Path of the violated input field.
  final String field;

  /// Stable machine code naming the violation.
  final String code;

  /// Optional redacted human-readable message.
  final String? message;

  @override
  String toString() => 'KumweFieldViolation($field: $code)';

  static final RegExp _fieldPattern = RegExp(
    r'^[A-Za-z0-9_$][A-Za-z0-9_.\[\]$-]{0,255}$',
  );

  static final RegExp _codePattern = RegExp(
    r'^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*$',
  );
}

/// One registered problem code with its declared behavior.
final class KumweProblemRegistryEntry {
  const KumweProblemRegistryEntry._({
    required this.code,
    required this.title,
    required this.httpStatuses,
    required this.retryClass,
    required this.extensionMembers,
  });

  /// Stable lowercase hyphenated code, unique within its registry.
  final String code;

  /// Short human-readable title.
  final String title;

  /// HTTP statuses the code has been declared with; empty when the
  /// registry leaves the status undeclared.
  final List<int> httpStatuses;

  /// Declared retry behavior for this code.
  final KumweRetryClass retryClass;

  /// Names of the typed extension members this code may carry.
  final Set<String> extensionMembers;

  @override
  String toString() => 'KumweProblemRegistryEntry($code)';
}

/// The resolution of one problem document against a registry.
final class KumweProblemResolution {
  const KumweProblemResolution._({
    required this.code,
    required this.entry,
    required this.retryClass,
  });

  /// Registry code extracted from the problem type URI, when the URI uses
  /// the registry prefix; `null` for foreign or `about:blank` types.
  final String? code;

  /// Matched registry entry; `null` when the code is unknown, in which case
  /// the caller handles the problem by its HTTP status class.
  final KumweProblemRegistryEntry? entry;

  /// Declared retry class, or the conservative HTTP-status fallback when
  /// the code is unregistered.
  final KumweRetryClass retryClass;

  /// Whether the problem resolved to a registered code.
  bool get isRegistered => entry != null;
}

/// An executable reader for the problem-details registry contract.
///
/// The registry is machine data: a finite list of stable codes with declared
/// statuses, retry classes and typed extension members. This reader validates
/// a registry document again as defense in depth and resolves problem type
/// URIs to declared behavior, so client control flow never parses human
/// detail text. It reads the *proposed* registry today; core adoption
/// (`CORE-API-002`) replaces the document, not this reader.
final class KumweProblemRegistry {
  /// Validates a registry document.
  ///
  /// Accepts both a proposal control document and a future adopted registry:
  /// only the machine members below are read, and every bound is enforced
  /// locally rather than trusted.
  factory KumweProblemRegistry.fromJson(Map<String, Object?> json) {
    final prefix = json['type_uri_prefix'];
    if (prefix is! String ||
        !RegExp(
          r'^urn:[a-z0-9][a-z0-9-]{0,30}:[a-z0-9:._-]{1,80}:$',
        ).hasMatch(prefix)) {
      throw const FormatException(
        'The registry type-URI prefix must be a bounded URN prefix '
        'ending in a colon.',
      );
    }
    final declaredClasses = _stringList(json['retry_classes'], 16);
    final retryClasses = <String, KumweRetryClass>{};
    for (final name in declaredClasses) {
      retryClasses[name] = _retryClass(name);
    }
    final memberNames = <String>{};
    final members = json['extension_members'];
    if (members is List<Object?>) {
      if (members.length > 32) {
        throw const FormatException(
          'The registry declares at most 32 extension members.',
        );
      }
      for (final member in members) {
        if (member is! Map<String, Object?>) {
          throw const FormatException(
            'Every registry extension member is an object.',
          );
        }
        final name = member['name'];
        if (name is! String || !_memberPattern.hasMatch(name)) {
          throw const FormatException(
            'Extension member names are bounded lowercase identifiers.',
          );
        }
        if (!memberNames.add(name)) {
          throw FormatException('Extension member $name is declared twice.');
        }
      }
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List<Object?> ||
        rawEntries.isEmpty ||
        rawEntries.length > 256) {
      throw const FormatException('The registry carries 1 to 256 entries.');
    }
    final entries = <String, KumweProblemRegistryEntry>{};
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, Object?>) {
        throw const FormatException('Every registry entry is an object.');
      }
      final entry = _entry(rawEntry, retryClasses, memberNames);
      if (entries.containsKey(entry.code)) {
        throw FormatException('Registry code ${entry.code} is duplicated.');
      }
      entries[entry.code] = entry;
    }
    return KumweProblemRegistry._(
      typeUriPrefix: prefix,
      entries: UnmodifiableMapView(entries),
    );
  }

  const KumweProblemRegistry._({
    required this.typeUriPrefix,
    required this.entries,
  });

  /// Exact URN prefix registered problem type URIs start with.
  final String typeUriPrefix;

  /// Registered entries keyed by stable code.
  final Map<String, KumweProblemRegistryEntry> entries;

  /// Resolves a problem [typeUri] to declared behavior.
  ///
  /// [httpStatus] drives the conservative fallback classification when the
  /// code is unregistered; an unknown code never becomes a silent retry.
  KumweProblemResolution resolve(String typeUri, {int? httpStatus}) {
    String? code;
    if (typeUri.startsWith(typeUriPrefix)) {
      final candidate = typeUri.substring(typeUriPrefix.length);
      if (_codePattern.hasMatch(candidate)) {
        code = candidate;
      }
    }
    final entry = code == null ? null : entries[code];
    final retryClass =
        entry?.retryClass ??
        (httpStatus == null
            ? KumweRetryClass.unspecified
            : const KumweRetryClassifier().classifyStatus(httpStatus));
    return KumweProblemResolution._(
      code: code,
      entry: entry,
      retryClass: retryClass,
    );
  }

  static KumweProblemRegistryEntry _entry(
    Map<String, Object?> json,
    Map<String, KumweRetryClass> retryClasses,
    Set<String> memberNames,
  ) {
    final code = json['code'];
    if (code is! String || !_codePattern.hasMatch(code)) {
      throw const FormatException(
        'Registry codes are bounded lowercase hyphenated identifiers.',
      );
    }
    final title = json['title'];
    if (title is! String || title.isEmpty || title.length > 120) {
      throw FormatException('Registry code $code needs a bounded title.');
    }
    final retryClassName = json['retry_class'];
    final retryClass = retryClassName is String
        ? retryClasses[retryClassName]
        : null;
    if (retryClass == null) {
      throw FormatException(
        'Registry code $code declares an unknown retry class.',
      );
    }
    final statuses = <int>[];
    final rawStatuses = json['http_statuses'];
    if (rawStatuses != null) {
      if (rawStatuses is! List<Object?> || rawStatuses.length > 4) {
        throw FormatException(
          'Registry code $code declares at most 4 HTTP statuses.',
        );
      }
      for (final status in rawStatuses) {
        if (status is! int || status < 100 || status > 599) {
          throw FormatException(
            'Registry code $code declares a non-HTTP status.',
          );
        }
        statuses.add(status);
      }
    }
    final extensions = <String>{};
    final rawExtensions = json['extensions'];
    if (rawExtensions != null) {
      for (final name in _stringList(rawExtensions, 16)) {
        if (!memberNames.contains(name)) {
          throw FormatException(
            'Registry code $code references undeclared extension $name.',
          );
        }
        extensions.add(name);
      }
    }
    return KumweProblemRegistryEntry._(
      code: code,
      title: title,
      httpStatuses: List<int>.unmodifiable(statuses),
      retryClass: retryClass,
      extensionMembers: Set<String>.unmodifiable(extensions),
    );
  }

  static List<String> _stringList(Object? value, int maxItems) {
    if (value is! List<Object?> || value.isEmpty || value.length > maxItems) {
      throw FormatException('Expected a list of 1 to $maxItems strings.');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String || item.isEmpty || item.length > 64) {
        throw const FormatException('Expected bounded string list items.');
      }
      result.add(item);
    }
    return result;
  }

  static KumweRetryClass _retryClass(String name) {
    return switch (name) {
      'never' => KumweRetryClass.never,
      'after_delay' => KumweRetryClass.afterDelay,
      'after_reauthentication' => KumweRetryClass.afterReauthentication,
      'after_precondition_refresh' => KumweRetryClass.afterPreconditionRefresh,
      'after_context_refresh' => KumweRetryClass.afterContextRefresh,
      'unspecified' => KumweRetryClass.unspecified,
      _ => throw FormatException('Unknown registry retry class $name.'),
    };
  }

  static final RegExp _codePattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');

  static final RegExp _memberPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
}
