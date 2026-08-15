import 'dart:collection';

import '../http/kumwe_response.dart';
import '../json/kumwe_json.dart';

/// An RFC 9457 Problem Details document.
final class ProblemDetails {
  /// Creates a validated problem document from decoded JSON.
  factory ProblemDetails.fromJson(Map<String, Object?> json) {
    final type = _optionalString(json, 'type') ?? 'about:blank';
    final parsedType = Uri.tryParse(type);
    if (parsedType == null || type.isEmpty) {
      throw const FormatException(
        'Problem Details type must be a URI-reference.',
      );
    }
    final statusValue = json['status'];
    if (statusValue != null &&
        (statusValue is! int || statusValue < 100 || statusValue > 599)) {
      throw const FormatException(
        'Problem Details status must be a three-digit integer.',
      );
    }
    final instance = _optionalString(json, 'instance');
    if (instance != null && Uri.tryParse(instance) == null) {
      throw const FormatException(
        'Problem Details instance must be a URI-reference.',
      );
    }
    final extensions = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_reserved.contains(entry.key)) {
        extensions[entry.key] = KumweJsonValue.from(entry.value).value;
      }
    }
    return ProblemDetails._(
      type: type,
      title: _optionalString(json, 'title'),
      status: statusValue as int?,
      detail: _optionalString(json, 'detail'),
      instance: instance,
      extensions: UnmodifiableMapView<String, Object?>(extensions),
    );
  }

  const ProblemDetails._({
    required this.type,
    required this.title,
    required this.status,
    required this.detail,
    required this.instance,
    required this.extensions,
  });

  /// Problem type URI-reference, defaulting to `about:blank`.
  final String type;

  /// Short human-readable summary.
  final String? title;

  /// Advisory HTTP status repeated in the document.
  final int? status;

  /// Human-readable occurrence detail.
  final String? detail;

  /// URI-reference identifying this occurrence.
  final String? instance;

  /// Extension members preserved as immutable JSON values.
  final Map<String, Object?> extensions;

  /// Kumwe request identity included by the error boundary, when present.
  String? get requestId {
    final value = extensions['request_id'];
    return value is String && _requestId.hasMatch(value) ? value : null;
  }

  /// Parses a Problem Details HTTP response.
  ///
  /// Returns `null` for another media type or a malformed problem document.
  static ProblemDetails? tryParse(KumweResponse response) {
    if (response.mediaType != 'application/problem+json' ||
        response.body.isEmpty) {
      return null;
    }
    try {
      return ProblemDetails.fromJson(response.jsonObject().value);
    } on FormatException {
      return null;
    }
  }

  static String? _optionalString(Map<String, Object?> json, String member) {
    final value = json[member];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('Problem Details $member must be a string.');
    }
    return value;
  }

  static const Set<String> _reserved = {
    'type',
    'title',
    'status',
    'detail',
    'instance',
  };

  static final RegExp _requestId = RegExp(r'^[A-Za-z0-9._-]{8,64}$');
}
