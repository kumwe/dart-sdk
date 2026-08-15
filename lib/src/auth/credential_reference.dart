/// An opaque non-secret name for one stored credential.
///
/// References identify credentials in stores, caches and diagnostics without
/// carrying token material, so they may appear in logs where a token never
/// can.
final class KumweCredentialReference {
  /// Validates an opaque credential reference.
  factory KumweCredentialReference(String value) {
    final normalized = value.trim();
    if (!_pattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'value',
        'Credential references must contain 1 to 191 supported characters.',
      );
    }
    return KumweCredentialReference._(normalized);
  }

  const KumweCredentialReference._(this.value);

  /// Opaque reference value; never secret material.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is KumweCredentialReference && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'KumweCredentialReference($value)';

  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$');
}
