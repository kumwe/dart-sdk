/// A strong HTTP entity tag guarding optimistic concurrency.
///
/// Kumwe mutations of versioned resources require the latest strong `ETag`
/// echoed back through `If-Match`. Weak validators cannot guard a mutation,
/// so `W/`-prefixed tags are rejected. Business records use the audited
/// `"vN"` form, which this type surfaces as [recordVersion] without making
/// other strong tags invalid.
final class EntityTag {
  /// Validates a strong entity tag in its quoted wire form, such as `"v3"`.
  factory EntityTag(String value) {
    if (value.startsWith('W/')) {
      throw ArgumentError.value(
        value,
        'value',
        'Weak entity tags cannot guard a Kumwe mutation.',
      );
    }
    if (!_strongPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Entity tags use the quoted strong form, such as "v3".',
      );
    }
    return EntityTag._(value);
  }

  /// Builds the strong `"vN"` tag for a positive business record version.
  factory EntityTag.recordVersion(int version) {
    if (version < 1) {
      throw ArgumentError.value(
        version,
        'version',
        'Record versions are positive.',
      );
    }
    return EntityTag._('"v$version"');
  }

  const EntityTag._(this.value);

  /// Header name that returns the current tag on reads and mutations.
  static const String headerName = 'ETag';

  /// Header name that carries the precondition on a mutation request.
  static const String ifMatchHeaderName = 'If-Match';

  /// Complete quoted wire value sent in `If-Match`.
  final String value;

  /// Positive `N` when the tag uses the audited `"vN"` record form,
  /// or `null` for any other strong tag, including versions too large for
  /// an exact integer.
  int? get recordVersion {
    final match = _recordPattern.firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  @override
  bool operator ==(Object other) => other is EntityTag && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EntityTag($value)';

  static final RegExp _strongPattern = RegExp(r'^"[\x21\x23-\x7E\x80-\xFF]*"$');

  static final RegExp _recordPattern = RegExp(r'^"v([1-9][0-9]{0,17})"$');
}
