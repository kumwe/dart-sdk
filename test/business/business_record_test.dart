import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture(String name) {
  final source = File('test/business/fixtures/$name.json').readAsStringSync();
  return (jsonDecode(source) as Map).cast<String, Object?>();
}

void main() {
  group('record envelopes', () {
    test('the page fixture parses records, includes and aggregates', () {
      final document = KumweRecordPageDocument.fromJson(
        fixture('invoice-page.business-records'),
      );
      expect(document.page.items, hasLength(2));
      expect(document.page.hasMore, isTrue);
      final first = document.page.items.first;
      expect(first.recordId, endsWith('0001'));
      expect(first.version, 5);
      expect(first.workflowState, 'issued');
      expect(first.entityTag.value, '"v5"');
      expect(first.createdAt, DateTime.parse('2026-08-09T08:00:00+00:00'));
      expect(first.archivedAt, isNull);
      expect(document.aggregates['invoice_count'], 2);
      expect(
        document.aggregates['total_sum'],
        '1234567890.123400',
        reason: 'exact decimals stay strings',
      );
    });

    test('stored null and withheld value stay distinguishable', () {
      final document = KumweRecordPageDocument.fromJson(
        fixture('invoice-page.business-records'),
      );
      final first = document.page.items.first;
      expect(first.discloses('notes'), isTrue);
      expect(first.values['notes']!.value, isNull);
      final second = document.page.items[1];
      expect(second.discloses('notes'), isFalse);
      expect(second.values['notes'], isNull);
    });

    test('included relation records carry position but no timestamps', () {
      final first = KumweRecordPageDocument.fromJson(
        fixture('invoice-page.business-records'),
      ).page.items.first;
      final lines = first.includes['lines']!;
      expect(lines, hasLength(2));
      expect(lines.first.position, 1);
      expect(lines[1].version, 3);
      expect(
        (lines.first.values['line_total']!.value!
            as Map<String, Object?>)['amount'],
        '1000.00',
      );
    });

    test('money values survive as exact structured strings', () {
      final first = KumweRecordPageDocument.fromJson(
        fixture('invoice-page.business-records'),
      ).page.items.first;
      final total = first.values['total']!.value! as Map<String, Object?>;
      expect(total['amount'], '1234567890.123400');
      expect(total['currency'], 'EUR');
      expect(
        KumweDecimal.parse(total['amount']! as String).value,
        '1234567890.123400',
      );
    });

    test('an empty-set aggregate null survives as core serves it', () {
      final document = KumweRecordPageDocument.fromJson({
        'items': <Object?>[],
        'next_cursor': null,
        'aggregates': {'total_sum': null, 'invoice_count': 0},
      });
      expect(document.aggregates.containsKey('total_sum'), isTrue);
      expect(document.aggregates['total_sum'], isNull);
      expect(document.aggregates['invoice_count'], 0);
    });

    test('refuses out-of-bounds pages and malformed cursors', () {
      final overflowing = fixture('invoice-page.business-records');
      overflowing['items'] = List<Object?>.filled(
        201,
        (fixture('invoice-page.business-records')['items']! as List<Object?>)
            .first,
      );
      expect(
        () => KumweRecordPageDocument.fromJson(overflowing),
        throwsFormatException,
      );
      final badCursor = fixture('invoice-page.business-records');
      badCursor['next_cursor'] = 'has space';
      expect(
        () => KumweRecordPageDocument.fromJson(badCursor),
        throwsFormatException,
      );
      final badAggregate = fixture('invoice-page.business-records');
      badAggregate['aggregates'] = {'sum': 19.99};
      expect(
        () => KumweRecordPageDocument.fromJson(badAggregate),
        throwsFormatException,
        reason: 'a float aggregate would silently lose exactness',
      );
    });

    test('refuses a record whose value keys drift from the grammar', () {
      final drifted = fixture('invoice-page.business-records');
      final record =
          ((drifted['items']! as List<Object?>).first! as Map<String, Object?>);
      record['values'] = {'Bad-Key': 1};
      expect(
        () => KumweRecordPageDocument.fromJson(drifted),
        throwsFormatException,
      );
    });
  });

  group('mutation envelopes', () {
    test('the fixture parses with its replay marker and custom result', () {
      final document = KumweRecordMutationDocument.fromJson(
        fixture('mutation.business-record'),
      );
      expect(document.operation, KumweRecordOperation.action);
      expect(document.version, 6);
      expect(document.replayed, isTrue);
      expect(document.deleted, isFalse);
      expect(document.workflowState, 'written_off');
      expect(document.entityTag.value, '"v6"');
      expect(document.result, isNotNull);
      expect(
        (document.result!.object['written_off_total']!
            as Map<String, Object?>)['amount'],
        '1234.50',
      );
    });

    test('refuses out-of-vocabulary operations', () {
      final drifted = fixture('mutation.business-record');
      drifted['operation'] = 'merge';
      expect(
        () => KumweRecordMutationDocument.fromJson(drifted),
        throwsFormatException,
      );
    });

    test('refuses missing replay and deletion declarations', () {
      final drifted = fixture('mutation.business-record');
      drifted.remove('replayed');
      expect(
        () => KumweRecordMutationDocument.fromJson(drifted),
        throwsFormatException,
      );
    });
  });

  group('history envelopes', () {
    test('the fixture parses revisions newest first', () {
      final document = KumweRecordHistoryDocument.fromJson(
        fixture('history.business-record'),
      );
      expect(document.items, hasLength(2));
      expect(document.hasMore, isTrue);
      expect(document.nextBeforeVersion, 4);
      final latest = document.items.first;
      expect(latest.revisionNumber, 7);
      expect(latest.operation, 'business.record.action');
      expect(latest.changedFields, ['issued_on']);
      expect(latest.snapshot['number']!.value, 'INV-2026-00042');
    });

    test('changed fields must name disclosed snapshot keys', () {
      final drifted = fixture('history.business-record');
      ((drifted['items']! as List<Object?>).first!
          as Map<String, Object?>)['changed_fields'] = [
        'ghost_field',
      ];
      expect(
        () => KumweRecordHistoryDocument.fromJson(drifted),
        throwsFormatException,
      );
    });

    test('continuation must be internally consistent', () {
      final silentMore = fixture('history.business-record');
      silentMore['next_before_version'] = null;
      expect(
        () => KumweRecordHistoryDocument.fromJson(silentMore),
        throwsFormatException,
        reason: 'has_more without a continuation version is unusable',
      );
      final finalPage = fixture('history.business-record');
      finalPage['has_more'] = false;
      expect(
        () => KumweRecordHistoryDocument.fromJson(finalPage),
        throwsFormatException,
        reason: 'a final page must not dangle a continuation version',
      );
    });
  });
}
