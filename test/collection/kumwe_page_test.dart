import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('cursors', () {
    test('accepts bounded visible ASCII and stays opaque', () {
      final cursor = KumweCursor('cursor-example-0001==');
      expect(cursor, KumweCursor('cursor-example-0001=='));
      expect(cursor.hashCode, KumweCursor('cursor-example-0001==').hashCode);
      expect(cursor.toString(), isNot(contains('cursor-example')));
    });

    test('refuses empty, oversized, spaced and non-ASCII values', () {
      expect(() => KumweCursor(''), throwsArgumentError);
      expect(() => KumweCursor('a' * 4097), throwsArgumentError);
      expect(() => KumweCursor('has space'), throwsArgumentError);
      expect(() => KumweCursor('tab\there'), throwsArgumentError);
      expect(() => KumweCursor('unicodé'), throwsArgumentError);
    });

    test('error text never echoes the refused cursor value', () {
      try {
        KumweCursor('secret cursor material');
        fail('expected an ArgumentError');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains('secret cursor material')));
      }
    });
  });

  group('pages', () {
    test('holds an immutable copy of its items', () {
      final source = <int>[1, 2, 3];
      final page = KumwePage<int>(items: source);
      source.add(4);
      expect(page.items, [1, 2, 3]);
      expect(() => page.items.add(5), throwsUnsupportedError);
    });

    test('never invents totals and reports continuation honestly', () {
      final last = KumwePage<int>(items: const [1]);
      expect(last.hasMore, isFalse);
      final continued = KumwePage<int>(
        items: const [1],
        continuation: KumweCursor('cursor-example-0002'),
      );
      expect(continued.hasMore, isTrue);
      expect(continued.toString(), contains('1 item(s)'));
      expect(continued.toString(), isNot(contains('cursor-example')));
    });

    test('map preserves order and continuation', () {
      final page = KumwePage<int>(
        items: const [1, 2],
        continuation: KumweCursor('cursor-example-0003'),
      );
      final mapped = page.map((item) => 'n$item');
      expect(mapped.items, ['n1', 'n2']);
      expect(mapped.continuation, KumweCursor('cursor-example-0003'));
    });
  });
}
