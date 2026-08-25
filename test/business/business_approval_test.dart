import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

Map<String, Object?> summary() => {
  'approval_request_id': '7c9e6679-7425-40de-944b-e07fc1f90ae7',
  'action': 'business.record.action:write_off',
  'resource_type': 'business_record',
  'resource_version': 5,
  'required_quorum': 2,
  'approval_count': 1,
  'status': 'pending',
  'version': 3,
  'created_at': '2026-08-20T10:00:00+00:00',
  'expires_at': '2026-08-27T10:00:00+00:00',
  'can_approve': true,
  'can_cancel': false,
  'can_revoke': false,
};

void main() {
  group('approval documents', () {
    test('an inbox row parses without votes', () {
      final approval = KumweBusinessApproval.fromJson(summary());
      expect(approval.actionHandle, 'write_off');
      expect(approval.status, KumweApprovalStatus.pending);
      expect(approval.requiredQuorum, 2);
      expect(approval.approvalCount, 1);
      expect(approval.canApprove, isTrue);
      expect(
        approval.votes,
        isNull,
        reason: 'no votes member means an inbox row, not zero votes',
      );
    });

    test('a detail document parses its votes', () {
      final detail = summary()
        ..['votes'] = [
          {
            'decision': 'approve',
            'reason': 'Verified against the ledger.',
            'decided_at': '2026-08-21T08:00:00+00:00',
          },
          {
            'decision': 'reject',
            'reason': null,
            'decided_at': '2026-08-21T09:00:00+00:00',
          },
        ];
      final approval = KumweBusinessApproval.fromJson(detail);
      expect(approval.votes, hasLength(2));
      expect(approval.votes!.first.approved, isTrue);
      expect(approval.votes![1].approved, isFalse);
      expect(approval.votes![1].reason, isNull);
    });

    test('refuses drift in action, resource and status vocabulary', () {
      expect(
        () => KumweBusinessApproval.fromJson(
          summary()..['action'] = 'content.publish',
        ),
        throwsFormatException,
      );
      expect(
        () => KumweBusinessApproval.fromJson(
          summary()..['resource_type'] = 'content',
        ),
        throwsFormatException,
      );
      expect(
        () => KumweBusinessApproval.fromJson(summary()..['status'] = 'stalled'),
        throwsFormatException,
      );
      expect(
        () =>
            KumweBusinessApproval.fromJson(summary()..['required_quorum'] = 0),
        throwsFormatException,
      );
    });

    test('inbox envelopes are bounded', () {
      final inbox = KumweApprovalInboxDocument.fromJson({
        'items': [summary()],
      });
      expect(inbox.items.single.approvalRequestId, startsWith('7c9e'));
      expect(
        () => KumweApprovalInboxDocument.fromJson({
          'items': List<Object?>.filled(101, summary()),
        }),
        throwsFormatException,
      );
    });
  });

  group('approval request outcomes', () {
    test('parses both branches and refuses the inconsistent one', () {
      final unneeded = KumweApprovalRequestOutcome.fromJson({
        'required': false,
        'approval_request_id': null,
      });
      expect(unneeded.required, isFalse);
      expect(unneeded.approvalRequestId, isNull);
      final stored = KumweApprovalRequestOutcome.fromJson({
        'required': true,
        'approval_request_id': 'approval-0001',
      });
      expect(stored.approvalRequestId, 'approval-0001');
      expect(
        () => KumweApprovalRequestOutcome.fromJson({'required': true}),
        throwsFormatException,
        reason: 'a required approval without its id is unusable',
      );
    });
  });

  group('operation status', () {
    Map<String, Object?> document() => {
      'operation_id': 'intent-key-0000000001',
      'state': 'completed',
      'operation': 'business.record.update',
      'created_at': '2026-08-20T10:00:00+00:00',
      'completed_at': '2026-08-20T10:00:01+00:00',
      'expires_at': '2026-09-19T10:00:00+00:00',
      'result': {
        'definition_version': 4,
        'record_id': 'record-0001',
        'version': 6,
        'workflow_state': null,
        'operation': 'update',
        'deleted': false,
        'replayed': false,
      },
    };

    test('a completed operation parses and yields its mutation', () {
      final status = KumweOperationStatusDocument.fromJson(document());
      expect(status.operationId, 'intent-key-0000000001');
      expect(status.operation, 'business.record.update');
      final mutation = status.asMutation()!;
      expect(mutation.version, 6);
      expect(mutation.operation, KumweRecordOperation.update);
    });

    test('a non-mutation result degrades to null, not to a throw', () {
      final status = KumweOperationStatusDocument.fromJson(
        document()..['result'] = {'approval_request_id': 'approval-0001'},
      );
      expect(status.asMutation(), isNull);
      expect(status.result.object['approval_request_id'], 'approval-0001');
    });

    test('refuses any state other than completed', () {
      expect(
        () => KumweOperationStatusDocument.fromJson(
          document()..['state'] = 'pending',
        ),
        throwsFormatException,
        reason: 'the server never serves a pending operation',
      );
    });

    test('refuses an out-of-grammar operation identifier', () {
      expect(
        () => KumweOperationStatusDocument.fromJson(
          document()..['operation_id'] = 'short',
        ),
        throwsFormatException,
      );
    });
  });
}
