import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> shipped() {
    final source = File(
      'contracts/mutation-semantics.proposal.json',
    ).readAsStringSync();
    return (jsonDecode(source) as Map).cast<String, Object?>();
  }

  Map<String, Object?> minimal({
    Object? keyHeader = 'Idempotency-Key',
    Object? replayedHeader = 'Idempotency-Replayed',
    Object? families,
  }) {
    return {
      'key_header': keyHeader,
      'replayed_header': replayedHeader,
      'families':
          families ??
          [
            {
              'id': 'general_http',
              'title': 'General HTTP mutations',
              'idempotency': {
                'required': true,
                'late_duplicate': 'executed_as_new',
              },
              'precondition': 'mixed',
              'operation_status': false,
            },
          ],
    };
  }

  group('the shipped proposal parses as declared', () {
    test('declares both ledger headers and all four families', () {
      final semantics = KumweMutationSemantics.fromJson(shipped());
      expect(semantics.keyHeader, IdempotencyKey.headerName);
      expect(semantics.replayedHeader, IdempotencyKey.replayedHeaderName);
      expect(semantics.families.keys, [
        'general_http',
        'business_record',
        'custom_business_action',
        'business_query',
      ]);
    });

    test('the general ledger replays for a day and forgets late keys', () {
      final family = KumweMutationSemantics.fromJson(
        shipped(),
      ).family('general_http')!;
      expect(family.idempotency.required, isTrue);
      expect(family.idempotency.replayWindow?.defaultSeconds, 86400);
      expect(family.idempotency.leaseSeconds, 900);
      expect(
        family.idempotency.lateDuplicate,
        KumweLateDuplicatePolicy.executedAsNew,
      );
      expect(family.precondition, KumweMutationPrecondition.mixed);
      expect(family.operationStatus, isFalse);
      expect(
        family.idempotency.refusalCodes,
        contains('idempotency-key-reused'),
      );
    });

    test('the business ledger declares its longer windows and refusals', () {
      final family = KumweMutationSemantics.fromJson(
        shipped(),
      ).family('business_record')!;
      final replay = family.idempotency.replayWindow!;
      expect(replay.defaultSeconds, 604800);
      expect(replay.minimumSeconds, 3600);
      expect(replay.maximumSeconds, 7776000);
      expect(replay.defaultDuration, const Duration(days: 7));
      expect(family.idempotency.retentionWindow?.defaultSeconds, 2592000);
      expect(
        family.idempotency.lateDuplicate,
        KumweLateDuplicatePolicy.refusedWindowElapsed,
      );
      expect(family.precondition, KumweMutationPrecondition.ifMatchStrongV);
      expect(family.operationStatus, isTrue);
      expect(
        family.idempotency.refusalCodes,
        contains('business-record-idempotency-replay-window-elapsed'),
      );
    });

    test('business queries need no key and no precondition', () {
      final family = KumweMutationSemantics.fromJson(
        shipped(),
      ).family('business_query')!;
      expect(family.idempotency.required, isFalse);
      expect(family.idempotency.replayWindow, isNull);
      expect(family.precondition, KumweMutationPrecondition.none);
    });

    test('an undeclared family resolves to null, never to a guess', () {
      final semantics = KumweMutationSemantics.fromJson(shipped());
      expect(semantics.family('surprise_family'), isNull);
    });

    test('the family map is unmodifiable', () {
      final semantics = KumweMutationSemantics.fromJson(shipped());
      expect(
        () => semantics.families.remove('general_http'),
        throwsUnsupportedError,
      );
    });
  });

  group('document bounds', () {
    test('refuses out-of-grammar headers', () {
      expect(
        () => KumweMutationSemantics.fromJson(minimal(keyHeader: '')),
        throwsFormatException,
      );
      expect(
        () => KumweMutationSemantics.fromJson(
          minimal(replayedHeader: 'X-${'a' * 70}'),
        ),
        throwsFormatException,
      );
      expect(
        () => KumweMutationSemantics.fromJson(minimal(keyHeader: 7)),
        throwsFormatException,
      );
    });

    test('refuses an empty, oversized or duplicated family list', () {
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: <Object?>[])),
        throwsFormatException,
      );
      final family = (minimal()['families']! as List<Object?>).first;
      expect(
        () => KumweMutationSemantics.fromJson(
          minimal(families: List<Object?>.filled(17, family)),
        ),
        throwsFormatException,
      );
      expect(
        () => KumweMutationSemantics.fromJson(
          minimal(families: [family, family]),
        ),
        throwsFormatException,
      );
    });

    test('refuses unknown enumerations instead of coercing them', () {
      final family = Map<String, Object?>.from(
        (minimal()['families']! as List<Object?>).first!
            as Map<String, Object?>,
      );
      family['precondition'] = 'if-match-weak';
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
      family['precondition'] = 'mixed';
      family['idempotency'] = {
        'required': true,
        'late_duplicate': 'silently_dropped',
      };
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
    });

    test('refuses inconsistent windows', () {
      final family = Map<String, Object?>.from(
        (minimal()['families']! as List<Object?>).first!
            as Map<String, Object?>,
      );
      family['idempotency'] = {
        'required': true,
        'late_duplicate': 'executed_as_new',
        'replay_seconds': {'default': 86400, 'minimum': 86401},
      };
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
      family['idempotency'] = {
        'required': true,
        'late_duplicate': 'executed_as_new',
        'replay_seconds': {'default': 86400, 'maximum': 3600},
      };
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
      family['idempotency'] = {
        'required': true,
        'late_duplicate': 'executed_as_new',
        'replay_seconds': {'default': 31536001},
      };
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
    });

    test('refuses out-of-grammar refusal codes and oversized lists', () {
      final family = Map<String, Object?>.from(
        (minimal()['families']! as List<Object?>).first!
            as Map<String, Object?>,
      );
      family['idempotency'] = {
        'required': true,
        'late_duplicate': 'executed_as_new',
        'refusals': ['UPPER-CASE'],
      };
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
      family['idempotency'] = {
        'required': true,
        'late_duplicate': 'executed_as_new',
        'refusals': List<Object?>.generate(17, (index) => 'code-$index'),
      };
      expect(
        () => KumweMutationSemantics.fromJson(minimal(families: [family])),
        throwsFormatException,
      );
    });
  });
}
