import 'dart:collection';

import '../http/kumwe_response.dart';
import '../mutation/retry_classification.dart';
import 'problem_details.dart';
import 'problem_registry.dart';

/// One API failure reduced to its adopted stable fields.
///
/// This is the failure value SDK results carry: a stable code where the
/// registry declares one, the HTTP status, redacted human text, the
/// correlation identifier, the declared retry behavior, and only the typed
/// extension members the registry marks safe. Undeclared extension data
/// never crosses this boundary, and control flow never reads detail text.
final class KumweProblem {
  /// Builds a problem report from an HTTP [response] and its optional
  /// parsed [details], resolved against [registry].
  factory KumweProblem.fromResponse(
    KumweResponse response, {
    required KumweProblemRegistry registry,
    ProblemDetails? details,
  }) {
    final parsed = details ?? ProblemDetails.tryParse(response);
    final resolution = registry.resolve(
      parsed?.type ?? 'about:blank',
      httpStatus: response.statusCode,
    );
    final entry = resolution.entry;
    final allowed = entry?.extensionMembers ?? const <String>{};
    final requestId =
        _cleanRequestId(response.headers['x-request-id']) ?? parsed?.requestId;
    return KumweProblem._(
      code: resolution.isRegistered ? resolution.code : null,
      typeUri: parsed?.type ?? 'about:blank',
      httpStatus: response.statusCode,
      title: _boundedText(parsed?.title, 120) ?? entry?.title,
      detail: _boundedText(parsed?.detail, 500),
      requestId: requestId,
      retryClass: resolution.retryClass,
      retryAfter: _retryAfter(response, parsed, allowed),
      fieldViolations: _fieldViolations(parsed, allowed),
      expectedVersion: _versionExtension(parsed, allowed, 'expected_version'),
      actualVersion: _versionExtension(parsed, allowed, 'actual_version'),
    );
  }

  const KumweProblem._({
    required this.code,
    required this.typeUri,
    required this.httpStatus,
    required this.title,
    required this.detail,
    required this.requestId,
    required this.retryClass,
    required this.retryAfter,
    required this.fieldViolations,
    required this.expectedVersion,
    required this.actualVersion,
  });

  /// Registered stable code; `null` for an unregistered or foreign type,
  /// which is then handled by [httpStatus] class alone.
  final String? code;

  /// Problem type URI as received, for diagnostics only.
  final String typeUri;

  /// HTTP status of the failing response.
  final int httpStatus;

  /// Redacted short summary, from the document or the registry title.
  final String? title;

  /// Redacted occurrence detail; never a control-flow input.
  final String? detail;

  /// Correlation identifier for operator lookup.
  final String? requestId;

  /// Declared retry behavior, or the conservative HTTP fallback.
  final KumweRetryClass retryClass;

  /// Server-advertised retry delay, when declared safe for this code.
  final Duration? retryAfter;

  /// Typed validation failures, when declared safe for this code.
  final List<KumweFieldViolation> fieldViolations;

  /// Version the failed precondition required, when declared safe.
  final String? expectedVersion;

  /// Current authoritative version, when declared safe.
  final String? actualVersion;

  /// Whether the problem resolved to a registered stable code.
  bool get isRegistered => code != null;

  @override
  String toString() {
    final identity = code ?? 'http-$httpStatus';
    final correlation = requestId == null ? '' : ' request $requestId';
    return 'KumweProblem($identity,$correlation retry ${retryClass.name})';
  }

  static String? _boundedText(String? value, int maxLength) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.length > maxLength) {
      return value.substring(0, maxLength);
    }
    return value;
  }

  static String? _cleanRequestId(String? value) {
    return value != null && RegExp(r'^[A-Za-z0-9._-]{8,64}$').hasMatch(value)
        ? value
        : null;
  }

  static Duration? _retryAfter(
    KumweResponse response,
    ProblemDetails? details,
    Set<String> allowed,
  ) {
    final header = const KumweRetryClassifier().retryAfter(response);
    if (header != null) {
      return header;
    }
    if (!allowed.contains('retry_after_seconds')) {
      return null;
    }
    final seconds = details?.extensions['retry_after_seconds'];
    if (seconds is! int || seconds < 0 || seconds > 86400) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  static List<KumweFieldViolation> _fieldViolations(
    ProblemDetails? details,
    Set<String> allowed,
  ) {
    if (!allowed.contains('field_violations')) {
      return const [];
    }
    final raw = details?.extensions['field_violations'];
    if (raw is! List<Object?> || raw.isEmpty || raw.length > 128) {
      return const [];
    }
    final violations = <KumweFieldViolation>[];
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        return const [];
      }
      final field = item['field'];
      final code = item['code'];
      final message = item['message'];
      if (field is! String || code is! String) {
        return const [];
      }
      try {
        violations.add(
          KumweFieldViolation(
            field: field,
            code: code,
            message: message is String ? message : null,
          ),
        );
      } on FormatException {
        return const [];
      }
    }
    return UnmodifiableListView(violations);
  }

  static String? _versionExtension(
    ProblemDetails? details,
    Set<String> allowed,
    String member,
  ) {
    if (!allowed.contains(member)) {
      return null;
    }
    final value = details?.extensions[member];
    return value is String &&
            RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$').hasMatch(value)
        ? value
        : null;
  }
}
