import '../json/kumwe_json.dart';
import 'business_record.dart';

/// Lifecycle states of an approval request.
enum KumweApprovalStatus {
  /// Waiting for quorum.
  pending('pending'),

  /// Quorum reached; the action may consume it.
  approved('approved'),

  /// Rejected by a voter.
  rejected('rejected'),

  /// Cancelled by its requester.
  cancelled('cancelled'),

  /// Revoked by an authority.
  revoked('revoked'),

  /// Consumed by the executed action.
  consumed('consumed');

  const KumweApprovalStatus(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the observed status vocabulary.
  static KumweApprovalStatus parse(Object? value) {
    for (final status in values) {
      if (status.wireName == value) {
        return status;
      }
    }
    throw const FormatException('The approval status is out of vocabulary.');
  }
}

/// One recorded approval vote.
final class KumweApprovalVote {
  /// Validates a vote document.
  factory KumweApprovalVote.fromJson(Map<String, Object?> json) {
    final decision = json['decision'];
    if (decision != 'approve' && decision != 'reject') {
      throw const FormatException('Approval decisions are approve or reject.');
    }
    final reason = json['reason'];
    if (reason != null && (reason is! String || reason.length > 2048)) {
      throw const FormatException('Vote reasons are bounded strings.');
    }
    return KumweApprovalVote._(
      approved: decision == 'approve',
      reason: reason as String?,
      decidedAt: _instant(json, 'decided_at'),
    );
  }

  const KumweApprovalVote._({
    required this.approved,
    required this.reason,
    required this.decidedAt,
  });

  /// Whether the vote approved.
  final bool approved;

  /// Voter-supplied reason, when given.
  final String? reason;

  /// When the vote was cast.
  final DateTime decidedAt;

  @override
  String toString() => 'KumweApprovalVote(${approved ? 'approve' : 'reject'})';
}

/// One approval request as this credential may see it.
///
/// Decisions never travel over the bearer API by design — approving,
/// rejecting, cancelling and revoking are browser step-up operations — so
/// this model is a read-only inspection surface: the `can*` flags say what
/// the subject could do *there*, not here.
final class KumweBusinessApproval {
  /// Validates an approval summary or detail document.
  ///
  /// Votes are present only on a single-approval fetch; an inbox row
  /// leaves [votes] `null`, which is distinct from an empty vote list.
  factory KumweBusinessApproval.fromJson(Map<String, Object?> json) {
    final id = json['approval_request_id'];
    if (id is! String || id.isEmpty || id.length > 64) {
      throw const FormatException(
        'Approvals carry a bounded request identifier.',
      );
    }
    final action = json['action'];
    if (action is! String ||
        action.isEmpty ||
        action.length > 191 ||
        !action.startsWith('business.record.action:')) {
      throw const FormatException(
        'Approval actions are business.record.action:<handle> values.',
      );
    }
    if (json['resource_type'] != 'business_record') {
      throw const FormatException('Approvals target business records.');
    }
    final resourceVersion = json['resource_version'];
    final requiredQuorum = json['required_quorum'];
    final approvalCount = json['approval_count'];
    final version = json['version'];
    if (resourceVersion is! int ||
        requiredQuorum is! int ||
        requiredQuorum < 1 ||
        approvalCount is! int ||
        approvalCount < 0 ||
        version is! int) {
      throw const FormatException(
        'Approvals carry integer version and quorum counters.',
      );
    }
    final canApprove = json['can_approve'];
    final canCancel = json['can_cancel'];
    final canRevoke = json['can_revoke'];
    if (canApprove is! bool || canCancel is! bool || canRevoke is! bool) {
      throw const FormatException(
        'Approvals declare the step-up abilities of the caller.',
      );
    }
    List<KumweApprovalVote>? votes;
    final rawVotes = json['votes'];
    if (rawVotes != null) {
      if (rawVotes is! List<Object?> || rawVotes.length > 100) {
        throw const FormatException('Approvals carry at most 100 votes.');
      }
      votes = List<KumweApprovalVote>.unmodifiable([
        for (final vote in rawVotes)
          KumweApprovalVote.fromJson(_voteObject(vote)),
      ]);
    }
    return KumweBusinessApproval._(
      approvalRequestId: id,
      action: action,
      resourceVersion: resourceVersion,
      requiredQuorum: requiredQuorum,
      approvalCount: approvalCount,
      status: KumweApprovalStatus.parse(json['status']),
      version: version,
      createdAt: _instant(json, 'created_at'),
      expiresAt: _instant(json, 'expires_at'),
      canApprove: canApprove,
      canCancel: canCancel,
      canRevoke: canRevoke,
      votes: votes,
    );
  }

  const KumweBusinessApproval._({
    required this.approvalRequestId,
    required this.action,
    required this.resourceVersion,
    required this.requiredQuorum,
    required this.approvalCount,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.expiresAt,
    required this.canApprove,
    required this.canCancel,
    required this.canRevoke,
    required this.votes,
  });

  /// Approval request identifier.
  final String approvalRequestId;

  /// Qualified action, `business.record.action:<handle>`.
  final String action;

  /// Record version the approval binds to.
  final int resourceVersion;

  /// Approvals needed before the action may consume the request.
  final int requiredQuorum;

  /// Approvals recorded so far.
  final int approvalCount;

  /// Lifecycle status.
  final KumweApprovalStatus status;

  /// Approval request version.
  final int version;

  /// When the request was created.
  final DateTime createdAt;

  /// When the request lapses.
  final DateTime expiresAt;

  /// Whether the subject could approve via browser step-up.
  final bool canApprove;

  /// Whether the subject could cancel via browser step-up.
  final bool canCancel;

  /// Whether the subject could revoke via browser step-up.
  final bool canRevoke;

  /// Recorded votes; `null` on inbox rows, a list on a single fetch.
  final List<KumweApprovalVote>? votes;

  /// The action handle behind the qualified [action] name.
  String get actionHandle => action.substring('business.record.action:'.length);

  @override
  String toString() =>
      'KumweBusinessApproval($approvalRequestId ${status.wireName} '
      '$approvalCount/$requiredQuorum)';

  static Map<String, Object?> _voteObject(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Every approval vote is an object.');
    }
    return value;
  }
}

/// The `{"items": […]}` approval inbox envelope.
final class KumweApprovalInboxDocument {
  /// Validates an inbox envelope.
  factory KumweApprovalInboxDocument.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    if (rawItems is! List<Object?> || rawItems.length > 100) {
      throw const FormatException('Approval inboxes carry at most 100 rows.');
    }
    return KumweApprovalInboxDocument._(
      items: List<KumweBusinessApproval>.unmodifiable([
        for (final item in rawItems)
          KumweBusinessApproval.fromJson(_itemObject(item)),
      ]),
    );
  }

  const KumweApprovalInboxDocument._({required this.items});

  /// Approval rows disclosed to this credential.
  final List<KumweBusinessApproval> items;

  @override
  String toString() => 'KumweApprovalInboxDocument(${items.length} row(s))';

  static Map<String, Object?> _itemObject(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Every inbox row is an object.');
    }
    return value;
  }
}

/// The `{"required", "approval_request_id"}` outcome of asking whether an
/// action needs approval.
final class KumweApprovalRequestOutcome {
  /// Validates an approval-request outcome document.
  factory KumweApprovalRequestOutcome.fromJson(Map<String, Object?> json) {
    final required = json['required'];
    if (required is! bool) {
      throw const FormatException(
        'Approval outcomes declare whether approval is required.',
      );
    }
    final id = json['approval_request_id'];
    if (id != null && (id is! String || id.isEmpty || id.length > 64)) {
      throw const FormatException(
        'Approval outcome identifiers are bounded strings.',
      );
    }
    if (required && id == null) {
      throw const FormatException(
        'A required approval names its stored request.',
      );
    }
    return KumweApprovalRequestOutcome._(
      required: required,
      approvalRequestId: id as String?,
    );
  }

  const KumweApprovalRequestOutcome._({
    required this.required,
    required this.approvalRequestId,
  });

  /// Whether the action needs an approval before it can run.
  final bool required;

  /// Stored approval request, when one was created or already exists.
  final String? approvalRequestId;

  @override
  String toString() => 'KumweApprovalRequestOutcome(required: $required)';
}

/// The caller-bound status of one completed mutation, addressed by its
/// idempotency key.
///
/// The server serves only *completed* operations; a pending, expired or
/// foreign operation is the same non-enumerating 404, so observing this
/// document at all proves the mutation committed.
final class KumweOperationStatusDocument {
  /// Validates an operation-status document.
  factory KumweOperationStatusDocument.fromJson(Map<String, Object?> json) {
    final id = json['operation_id'];
    if (id is! String || !_operationIdPattern.hasMatch(id)) {
      throw const FormatException(
        'Operation identifiers use the idempotency key grammar.',
      );
    }
    if (json['state'] != 'completed') {
      throw const FormatException('Only completed operations are ever served.');
    }
    final operation = json['operation'];
    if (operation is! String || operation.isEmpty || operation.length > 96) {
      throw const FormatException(
        'Operation names are bounded dotted identifiers.',
      );
    }
    final rawResult = json['result'];
    if (rawResult is! Map<String, Object?>) {
      throw const FormatException(
        'Completed operations carry their result document.',
      );
    }
    return KumweOperationStatusDocument._(
      operationId: id,
      operation: operation,
      createdAt: _instant(json, 'created_at'),
      completedAt: json['completed_at'] == null
          ? null
          : _instant(json, 'completed_at'),
      expiresAt: _instant(json, 'expires_at'),
      result: KumweJsonValue.from(rawResult),
    );
  }

  const KumweOperationStatusDocument._({
    required this.operationId,
    required this.operation,
    required this.createdAt,
    required this.completedAt,
    required this.expiresAt,
    required this.result,
  });

  /// The idempotency key that identifies the operation.
  final String operationId;

  /// Dotted operation name, e.g. `business.record.update`.
  final String operation;

  /// When the operation was recorded.
  final DateTime createdAt;

  /// When the operation completed, when recorded.
  final DateTime? completedAt;

  /// When the status record lapses.
  final DateTime expiresAt;

  /// The stored result document.
  final KumweJsonValue result;

  /// Reads [result] as a record mutation envelope, or `null` when the
  /// stored result is a different shape (approval outcome, custom result).
  KumweRecordMutationDocument? asMutation() {
    try {
      return KumweRecordMutationDocument.fromJson(result.object);
    } on FormatException {
      return null;
    } on StateError {
      return null;
    }
  }

  @override
  String toString() => 'KumweOperationStatusDocument($operationId $operation)';

  static final RegExp _operationIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$',
  );
}

DateTime _instant(Map<String, Object?> json, String member) {
  final value = json[member];
  if (value is! String || value.isEmpty || value.length > 64) {
    throw FormatException('The $member timestamp is a bounded string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('The $member timestamp is not a valid instant.');
  }
  return parsed;
}
