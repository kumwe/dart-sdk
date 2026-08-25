import 'dart:collection';

/// An opaque collection continuation token.
///
/// Cursors bind the query shape, scope, definition version and access digest
/// server-side, so the SDK never parses, edits or fabricates one; it only
/// carries a bounded value back to the server that issued it.
final class KumweCursor {
  /// Validates an opaque cursor value.
  factory KumweCursor(String value) {
    if (value.isEmpty ||
        value.length > 4096 ||
        value.codeUnits.any((unit) => unit <= 0x20 || unit > 0x7e)) {
      throw ArgumentError.value(
        '<cursor>',
        'value',
        'Cursors need 1 to 4096 visible ASCII characters.',
      );
    }
    return KumweCursor._(value);
  }

  const KumweCursor._(this.value);

  /// Opaque cursor value presented back to the issuing server.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is KumweCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'KumweCursor(<opaque>)';
}

/// One bounded page of a server collection.
///
/// A page never invents totals: the server said how many items this page
/// carries and whether a continuation exists, and nothing more.
final class KumwePage<T> {
  /// Creates an immutable page.
  KumwePage({required List<T> items, this.continuation})
    : items = UnmodifiableListView(List<T>.of(items));

  /// Items of this page, in server order.
  final List<T> items;

  /// Continuation for the next page; `null` on the final page.
  final KumweCursor? continuation;

  /// Whether the server advertised a further page.
  bool get hasMore => continuation != null;

  /// Maps every item while preserving order and continuation.
  KumwePage<R> map<R>(R Function(T item) transform) {
    return KumwePage<R>(
      items: [for (final item in items) transform(item)],
      continuation: continuation,
    );
  }

  @override
  String toString() =>
      'KumwePage(${items.length} item(s)${hasMore ? ', more' : ''})';
}
