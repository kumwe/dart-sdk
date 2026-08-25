import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

Map<String, Object?> shipped() {
  final source = File(
    'contracts/collection-pagination.proposal.json',
  ).readAsStringSync();
  return (jsonDecode(source) as Map).cast<String, Object?>();
}

void main() {
  group('the shipped proposal parses as declared', () {
    test('pins the envelope and its never-invented totals rule', () {
      final pagination = KumweCollectionPagination.fromJson(shipped());
      expect(pagination.itemsMember, 'items');
      expect(pagination.nextCursorMember, 'next_cursor');
      expect(pagination.pageSizeMinimum, 1);
      expect(pagination.pageSizeMaximum, 200);
      expect(pagination.pageSizeDefault, 50);
      expect(pagination.cursorMaxLength, 2048);
    });

    test('declares all six audited collections', () {
      final pagination = KumweCollectionPagination.fromJson(shipped());
      expect(pagination.collections.keys, [
        'business_records',
        'business_record_history',
        'content',
        'navigation',
        'identity',
        'automation',
      ]);
      expect(
        pagination.collection('business_records')?.proposedBehavior,
        KumweCollectionBehavior.alreadyConformant,
      );
      expect(
        pagination.collection('business_record_history')?.proposedBehavior,
        KumweCollectionBehavior.keepBoundedWindow,
      );
      expect(
        pagination.collection('content')?.proposedBehavior,
        KumweCollectionBehavior.adoptCursorEnvelope,
      );
      expect(pagination.collection('surprise'), isNull);
    });

    test('answers page-size requests from declared data', () {
      final pagination = KumweCollectionPagination.fromJson(shipped());
      expect(pagination.allowsPageSize(1), isTrue);
      expect(pagination.allowsPageSize(200), isTrue);
      expect(pagination.allowsPageSize(0), isFalse);
      expect(
        pagination.allowsPageSize(201),
        isFalse,
        reason: 'above the maximum is refused, never clamped',
      );
    });
  });

  group('document bounds', () {
    test('refuses an unpinned totals rule', () {
      final drifted = shipped();
      (drifted['envelope']! as Map<String, Object?>)['totals'] = 'estimated';
      expect(
        () => KumweCollectionPagination.fromJson(drifted),
        throwsFormatException,
      );
    });

    test('refuses inconsistent page-size limits', () {
      final drifted = shipped();
      (drifted['limits']! as Map<String, Object?>)['page_size_default'] = 500;
      expect(
        () => KumweCollectionPagination.fromJson(drifted),
        throwsFormatException,
      );
    });

    test('refuses out-of-vocabulary behaviors and duplicates', () {
      final drifted = shipped();
      ((drifted['collections']! as List<Object?>).first!
              as Map<String, Object?>)['proposed_behavior'] =
          'best_effort';
      expect(
        () => KumweCollectionPagination.fromJson(drifted),
        throwsFormatException,
      );
      final duplicated = shipped();
      final collections = duplicated['collections']! as List<Object?>;
      collections.add(collections.first);
      expect(
        () => KumweCollectionPagination.fromJson(duplicated),
        throwsFormatException,
      );
    });
  });
}
