import 'dart:collection';

/// How a family treats a retry arriving after its replay window.
enum KumweLateDuplicatePolicy {
  /// The late retry executes as a new operation; the general ledger has
  /// forgotten the key.
  executedAsNew,

  /// The late retry is refused by name rather than applied twice.
  refusedWindowElapsed,
}

/// Which write precondition a family demands.
enum KumweMutationPrecondition {
  /// Existing-resource mutations require a strong `"vN"` entity tag.
  ifMatchStrongV,

  /// Routes in the family differ; the operation contract decides.
  mixed,

  /// No precondition is demanded.
  none,
}

/// A bounded seconds declaration with optional deployment bounds.
final class KumweSecondsWindow {
  const KumweSecondsWindow._({
    required this.defaultSeconds,
    required this.minimumSeconds,
    required this.maximumSeconds,
  });

  /// Default window length in seconds.
  final int defaultSeconds;

  /// Smallest length a deployment may configure, when declared.
  final int? minimumSeconds;

  /// Largest length a deployment may configure, when declared.
  final int? maximumSeconds;

  /// Default window as a duration.
  Duration get defaultDuration => Duration(seconds: defaultSeconds);

  @override
  String toString() => 'KumweSecondsWindow(${defaultSeconds}s)';
}

/// Idempotency behavior one mutation family declares.
final class KumweIdempotencyDeclaration {
  const KumweIdempotencyDeclaration._({
    required this.required,
    required this.replayWindow,
    required this.retentionWindow,
    required this.leaseSeconds,
    required this.lateDuplicate,
    required this.refusalCodes,
  });

  /// Whether every mutation in the family must carry an idempotency key.
  final bool required;

  /// Replay window during which an identical retry replays the stored
  /// response; `null` when the family declares none.
  final KumweSecondsWindow? replayWindow;

  /// Retention window for refusing late duplicates by name, when declared.
  final KumweSecondsWindow? retentionWindow;

  /// In-progress lease length in seconds, when declared.
  final int? leaseSeconds;

  /// What happens to a retry arriving after the replay window.
  final KumweLateDuplicatePolicy lateDuplicate;

  /// Stable registry problem codes the family refuses with.
  final Set<String> refusalCodes;

  @override
  String toString() =>
      'KumweIdempotencyDeclaration(required: $required, '
      'late: ${lateDuplicate.name})';
}

/// One mutation family's declared semantics.
final class KumweMutationFamily {
  const KumweMutationFamily._({
    required this.id,
    required this.title,
    required this.idempotency,
    required this.precondition,
    required this.operationStatus,
  });

  /// Stable family identifier.
  final String id;

  /// Short human-readable title.
  final String title;

  /// Declared idempotency behavior.
  final KumweIdempotencyDeclaration idempotency;

  /// Declared write precondition.
  final KumweMutationPrecondition precondition;

  /// Whether the family exposes an asynchronous operation-status resource.
  final bool operationStatus;

  @override
  String toString() => 'KumweMutationFamily($id)';
}

/// An executable reader for the per-family mutation-semantics contract.
///
/// The contract declares, per family, whether idempotency keys are required,
/// how long replay and retention windows run, what a late duplicate does and
/// which precondition a write must carry — so a client's retry policy comes
/// from declared data instead of a shared prose paragraph. It reads the
/// *proposed* contract today; core adoption (`CORE-MUTATION-001`) replaces
/// the document, not this reader.
final class KumweMutationSemantics {
  /// Validates a mutation-semantics document.
  factory KumweMutationSemantics.fromJson(Map<String, Object?> json) {
    final keyHeader = json['key_header'];
    final replayedHeader = json['replayed_header'];
    if (keyHeader is! String || !_headerPattern.hasMatch(keyHeader)) {
      throw const FormatException(
        'The mutation-semantics key header must be a bounded header name.',
      );
    }
    if (replayedHeader is! String || !_headerPattern.hasMatch(replayedHeader)) {
      throw const FormatException(
        'The mutation-semantics replayed header must be a bounded header '
        'name.',
      );
    }
    final rawFamilies = json['families'];
    if (rawFamilies is! List<Object?> ||
        rawFamilies.isEmpty ||
        rawFamilies.length > 16) {
      throw const FormatException(
        'Mutation semantics declare 1 to 16 families.',
      );
    }
    final families = <String, KumweMutationFamily>{};
    for (final rawFamily in rawFamilies) {
      if (rawFamily is! Map<String, Object?>) {
        throw const FormatException('Every mutation family is an object.');
      }
      final family = _family(rawFamily);
      if (families.containsKey(family.id)) {
        throw FormatException('Mutation family ${family.id} is duplicated.');
      }
      families[family.id] = family;
    }
    return KumweMutationSemantics._(
      keyHeader: keyHeader,
      replayedHeader: replayedHeader,
      families: UnmodifiableMapView(families),
    );
  }

  const KumweMutationSemantics._({
    required this.keyHeader,
    required this.replayedHeader,
    required this.families,
  });

  /// Header carrying the caller-minted idempotency key.
  final String keyHeader;

  /// Header marking a stored idempotent replay.
  final String replayedHeader;

  /// Declared families keyed by identifier.
  final Map<String, KumweMutationFamily> families;

  /// Returns the declared family, or `null` for an unknown identifier.
  ///
  /// An unknown family means the operation's semantics are undeclared; the
  /// caller treats its retries as unspecified rather than guessing.
  KumweMutationFamily? family(String id) => families[id];

  static KumweMutationFamily _family(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || !_familyPattern.hasMatch(id)) {
      throw const FormatException(
        'Mutation family identifiers are bounded lowercase identifiers.',
      );
    }
    final title = json['title'];
    if (title is! String || title.isEmpty || title.length > 120) {
      throw FormatException('Mutation family $id needs a bounded title.');
    }
    final rawIdempotency = json['idempotency'];
    if (rawIdempotency is! Map<String, Object?>) {
      throw FormatException(
        'Mutation family $id needs an idempotency declaration.',
      );
    }
    final precondition = switch (json['precondition']) {
      'if_match_strong_v' => KumweMutationPrecondition.ifMatchStrongV,
      'mixed' => KumweMutationPrecondition.mixed,
      'none' => KumweMutationPrecondition.none,
      _ => throw FormatException(
        'Mutation family $id declares an unknown precondition.',
      ),
    };
    final operationStatus = json['operation_status'];
    if (operationStatus is! bool) {
      throw FormatException(
        'Mutation family $id must declare operation_status.',
      );
    }
    return KumweMutationFamily._(
      id: id,
      title: title,
      idempotency: _idempotency(id, rawIdempotency),
      precondition: precondition,
      operationStatus: operationStatus,
    );
  }

  static KumweIdempotencyDeclaration _idempotency(
    String familyId,
    Map<String, Object?> json,
  ) {
    final required = json['required'];
    if (required is! bool) {
      throw FormatException(
        'Mutation family $familyId must declare whether keys are required.',
      );
    }
    final lateDuplicate = switch (json['late_duplicate']) {
      'executed_as_new' => KumweLateDuplicatePolicy.executedAsNew,
      'refused_window_elapsed' => KumweLateDuplicatePolicy.refusedWindowElapsed,
      _ => throw FormatException(
        'Mutation family $familyId declares an unknown late-duplicate '
        'policy.',
      ),
    };
    final leaseSeconds = json['lease_seconds'];
    if (leaseSeconds != null &&
        (leaseSeconds is! int || leaseSeconds < 1 || leaseSeconds > 86400)) {
      throw FormatException(
        'Mutation family $familyId declares an out-of-bounds lease.',
      );
    }
    final refusals = <String>{};
    final rawRefusals = json['refusals'];
    if (rawRefusals != null) {
      if (rawRefusals is! List<Object?> || rawRefusals.length > 16) {
        throw FormatException(
          'Mutation family $familyId declares at most 16 refusal codes.',
        );
      }
      for (final code in rawRefusals) {
        if (code is! String || !_codePattern.hasMatch(code)) {
          throw FormatException(
            'Mutation family $familyId declares an out-of-grammar refusal '
            'code.',
          );
        }
        refusals.add(code);
      }
    }
    return KumweIdempotencyDeclaration._(
      required: required,
      replayWindow: _window(familyId, json['replay_seconds']),
      retentionWindow: _window(familyId, json['retention_seconds']),
      leaseSeconds: leaseSeconds as int?,
      lateDuplicate: lateDuplicate,
      refusalCodes: Set<String>.unmodifiable(refusals),
    );
  }

  static KumweSecondsWindow? _window(String familyId, Object? json) {
    if (json == null) {
      return null;
    }
    if (json is! Map<String, Object?>) {
      throw FormatException(
        'Mutation family $familyId declares a non-object window.',
      );
    }
    final defaultSeconds = json['default'];
    if (defaultSeconds is! int ||
        defaultSeconds < 1 ||
        defaultSeconds > 31536000) {
      throw FormatException(
        'Mutation family $familyId declares an out-of-bounds window '
        'default.',
      );
    }
    final minimum = json['minimum'];
    final maximum = json['maximum'];
    if (minimum != null &&
        (minimum is! int || minimum < 1 || minimum > defaultSeconds)) {
      throw FormatException(
        'Mutation family $familyId declares an inconsistent window minimum.',
      );
    }
    if (maximum != null &&
        (maximum is! int || maximum > 31536000 || maximum < defaultSeconds)) {
      throw FormatException(
        'Mutation family $familyId declares an inconsistent window maximum.',
      );
    }
    return KumweSecondsWindow._(
      defaultSeconds: defaultSeconds,
      minimumSeconds: minimum as int?,
      maximumSeconds: maximum as int?,
    );
  }

  static final RegExp _headerPattern = RegExp(r'^[A-Za-z][A-Za-z0-9-]{0,63}$');

  static final RegExp _familyPattern = RegExp(r'^[a-z][a-z0-9_]{2,63}$');

  static final RegExp _codePattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');
}
