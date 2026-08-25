import '../contract/contract_validator.dart';
import '../contract/json_schema_validator.dart';
import '../json/kumwe_json.dart';
import 'business_definition.dart';

/// Which write a values document is for.
enum KumweWritePhase {
  /// A create body's `values`.
  create,

  /// An update body's `values`.
  update,
}

/// One pre-send violation of a values document.
final class KumweValueViolation {
  /// Creates a violation for [field].
  const KumweValueViolation({
    required this.field,
    required this.code,
    required this.message,
  });

  /// Field handle the violation is about.
  final String field;

  /// Stable violation code.
  final String code;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'KumweValueViolation($field: $code)';
}

/// Pre-send validation of a `values` document against one disclosed
/// definition.
///
/// The server remains the authority — its refusals are the contract — but a
/// client that already holds the policy-filtered definition can refuse an
/// impossible write before spending a request and an idempotency key on it:
/// a value for an undisclosed field, a write to a read-only or frozen
/// field, a missing required value, a null where none is allowed, or a
/// value outside the field's declared schema fragment.
final class KumweBusinessValueValidator {
  /// Creates a validator over [definition].
  const KumweBusinessValueValidator(this.definition);

  /// The disclosed definition writes are checked against.
  final KumweBusinessDefinition definition;

  /// Checks the `values` object of a [phase] write, returning every
  /// violation found — an empty list means the document is sendable as
  /// far as the disclosed definition can tell.
  List<KumweValueViolation> validate(
    KumweJsonValue values, {
    required KumweWritePhase phase,
  }) {
    final raw = values.value;
    if (raw is! Map<String, Object?>) {
      throw ArgumentError.value(
        values,
        'values',
        'A values document is a JSON object keyed by field handle.',
      );
    }
    final violations = <KumweValueViolation>[];
    for (final entry in raw.entries) {
      final field = definition.fields[entry.key];
      if (field == null) {
        violations.add(
          KumweValueViolation(
            field: entry.key,
            code: 'undisclosed-field',
            message:
                'The field is not disclosed to this caller; the '
                'server will refuse or silently cannot store it.',
          ),
        );
        continue;
      }
      if (field.readOnly) {
        violations.add(
          KumweValueViolation(
            field: field.handle,
            code: 'read-only',
            message: 'The field is never written by the caller.',
          ),
        );
        continue;
      }
      if (phase == KumweWritePhase.update && field.immutableAfterCreate) {
        violations.add(
          KumweValueViolation(
            field: field.handle,
            code: 'immutable-after-create',
            message: 'The field froze when the record was created.',
          ),
        );
        continue;
      }
      if (entry.value == null) {
        if (!field.nullable) {
          violations.add(
            KumweValueViolation(
              field: field.handle,
              code: 'null-not-allowed',
              message: 'The field does not accept a stored null.',
            ),
          );
        }
        continue;
      }
      violations.addAll(_schemaViolations(field, entry.value));
    }
    if (phase == KumweWritePhase.create) {
      for (final field in definition.fields.values) {
        if (field.required &&
            !field.readOnly &&
            field.uses.create &&
            !raw.containsKey(field.handle)) {
          violations.add(
            KumweValueViolation(
              field: field.handle,
              code: 'required',
              message: 'The field is required on create.',
            ),
          );
        }
      }
    }
    return List<KumweValueViolation>.unmodifiable(violations);
  }

  List<KumweValueViolation> _schemaViolations(
    KumweBusinessField field,
    Object? value,
  ) {
    final fragment = field.schema.value;
    if (fragment is! Map<String, Object?>) {
      return const [];
    }
    final ContractValidationResult result;
    try {
      result = const JsonSchemaContractValidator().validateInstance(
        KumweJsonValue.from(value),
        schema: KumweJsonObject.from(fragment),
        schemaUri: Uri.parse(
          'urn:kumwe:sdk:field-schema:${definition.handle}:${field.handle}',
        ),
      );
    } on FormatException {
      return const [];
    }
    return [
      for (final issue in result.issues)
        KumweValueViolation(
          field: field.handle,
          code: 'schema',
          message: '${issue.path}: ${issue.message}',
        ),
    ];
  }

  @override
  String toString() => 'KumweBusinessValueValidator(${definition.handle})';
}
