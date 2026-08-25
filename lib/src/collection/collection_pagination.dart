import 'dart:collection';

/// How a collection relates to the uniform cursor envelope.
enum KumweCollectionBehavior {
  /// The collection already speaks the envelope exactly.
  alreadyConformant('already_conformant'),

  /// The collection keeps its bounded-window read instead of a cursor.
  keepBoundedWindow('keep_bounded_window'),

  /// The collection adopts the cursor envelope.
  adoptCursorEnvelope('adopt_cursor_envelope');

  const KumweCollectionBehavior(this.wireName);

  /// Exact wire spelling.
  final String wireName;

  /// Parses the declared behavior vocabulary.
  static KumweCollectionBehavior parse(Object? value) {
    for (final behavior in values) {
      if (behavior.wireName == value) {
        return behavior;
      }
    }
    throw const FormatException(
      'The collection behavior is out of vocabulary.',
    );
  }
}

/// One collection's pagination declaration.
final class KumweCollectionDeclaration {
  /// Validates a collection declaration.
  factory KumweCollectionDeclaration.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || !_identifierPattern.hasMatch(id)) {
      throw const FormatException(
        'Collection identifiers are bounded lowercase identifiers.',
      );
    }
    final title = json['title'];
    if (title is! String || title.isEmpty || title.length > 120) {
      throw FormatException('Collection $id needs a bounded title.');
    }
    final observed = json['observed_behavior'];
    if (observed is! String || observed.isEmpty || observed.length > 1024) {
      throw FormatException(
        'Collection $id needs a bounded observed-behavior sentence.',
      );
    }
    return KumweCollectionDeclaration._(
      id: id,
      title: title,
      observedBehavior: observed,
      proposedBehavior: KumweCollectionBehavior.parse(
        json['proposed_behavior'],
      ),
    );
  }

  const KumweCollectionDeclaration._({
    required this.id,
    required this.title,
    required this.observedBehavior,
    required this.proposedBehavior,
  });

  /// Stable collection identifier.
  final String id;

  /// Short human-readable title.
  final String title;

  /// What the audited core does today.
  final String observedBehavior;

  /// What the proposal asks the collection to do.
  final KumweCollectionBehavior proposedBehavior;

  @override
  String toString() =>
      'KumweCollectionDeclaration($id: ${proposedBehavior.wireName})';

  static final RegExp _identifierPattern = RegExp(r'^[a-z][a-z0-9_]{2,63}$');
}

/// An executable reader for the collection-pagination contract.
///
/// The contract extends the collection envelope the generated business
/// surface already proves — `items` beside an opaque `next_cursor`, bounded
/// page sizes, no invented totals — to every management collection. This
/// reader consumes the *proposed* document (`CORE-COLLECTION-001`) as a
/// working consumer; core adoption replaces the document, not the reader.
final class KumweCollectionPagination {
  /// Validates a collection-pagination document.
  factory KumweCollectionPagination.fromJson(Map<String, Object?> json) {
    final envelope = json['envelope'];
    if (envelope is! Map<String, Object?>) {
      throw const FormatException(
        'Collection pagination declares its envelope.',
      );
    }
    final itemsMember = envelope['items_member'];
    final cursorMember = envelope['next_cursor_member'];
    if (itemsMember is! String ||
        !_memberPattern.hasMatch(itemsMember) ||
        cursorMember is! String ||
        !_memberPattern.hasMatch(cursorMember)) {
      throw const FormatException(
        'Envelope member names are bounded lowercase identifiers.',
      );
    }
    if (envelope['totals'] != 'never_invented') {
      throw const FormatException(
        'The envelope must pin the never-invented totals rule.',
      );
    }
    final limits = json['limits'];
    if (limits is! Map<String, Object?>) {
      throw const FormatException('Collection pagination declares its limits.');
    }
    final minimum = limits['page_size_minimum'];
    final maximum = limits['page_size_maximum'];
    final fallback = limits['page_size_default'];
    final cursorMax = limits['cursor_max_length'];
    if (minimum is! int ||
        maximum is! int ||
        fallback is! int ||
        cursorMax is! int ||
        minimum < 1 ||
        maximum > 1000 ||
        minimum > fallback ||
        fallback > maximum ||
        cursorMax < 1 ||
        cursorMax > 65536) {
      throw const FormatException(
        'Collection pagination limits are out of bounds or inconsistent.',
      );
    }
    final rawCollections = json['collections'];
    if (rawCollections is! List<Object?> ||
        rawCollections.isEmpty ||
        rawCollections.length > 64) {
      throw const FormatException(
        'Collection pagination declares 1 to 64 collections.',
      );
    }
    final collections = <String, KumweCollectionDeclaration>{};
    for (final rawCollection in rawCollections) {
      if (rawCollection is! Map<String, Object?>) {
        throw const FormatException('Every collection is an object.');
      }
      final collection = KumweCollectionDeclaration.fromJson(rawCollection);
      if (collections.containsKey(collection.id)) {
        throw FormatException('Collection ${collection.id} is duplicated.');
      }
      collections[collection.id] = collection;
    }
    return KumweCollectionPagination._(
      itemsMember: itemsMember,
      nextCursorMember: cursorMember,
      pageSizeMinimum: minimum,
      pageSizeMaximum: maximum,
      pageSizeDefault: fallback,
      cursorMaxLength: cursorMax,
      collections: UnmodifiableMapView(collections),
    );
  }

  const KumweCollectionPagination._({
    required this.itemsMember,
    required this.nextCursorMember,
    required this.pageSizeMinimum,
    required this.pageSizeMaximum,
    required this.pageSizeDefault,
    required this.cursorMaxLength,
    required this.collections,
  });

  /// Envelope member carrying the page items.
  final String itemsMember;

  /// Envelope member carrying the opaque continuation.
  final String nextCursorMember;

  /// Smallest requestable page size.
  final int pageSizeMinimum;

  /// Largest requestable page size; above it is refused, never clamped.
  final int pageSizeMaximum;

  /// Page size when the request names none.
  final int pageSizeDefault;

  /// Largest cursor the uniform envelope may mint.
  final int cursorMaxLength;

  /// Declared collections keyed by identifier.
  final Map<String, KumweCollectionDeclaration> collections;

  /// Returns the declared collection, or `null` for an unknown identifier.
  KumweCollectionDeclaration? collection(String id) => collections[id];

  /// Whether [pageSize] is inside the declared request window.
  bool allowsPageSize(int pageSize) =>
      pageSize >= pageSizeMinimum && pageSize <= pageSizeMaximum;

  @override
  String toString() =>
      'KumweCollectionPagination(${collections.length} collection(s))';

  static final RegExp _memberPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
}
