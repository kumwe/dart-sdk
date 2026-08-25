import '../client/kumwe_client_options.dart';
import '../http/header_map.dart';
import '../http/kumwe_request.dart';
import '../http/kumwe_response.dart';
import '../http/kumwe_transport.dart';
import '../json/kumwe_json.dart';
import '../mutation/entity_tag.dart';
import '../mutation/idempotency_key.dart';
import '../mutation/mutation_intent.dart';
import '../problem/api_exception.dart';
import '../problem/kumwe_problem.dart';
import '../problem/problem_registry.dart';
import '../result/kumwe_result.dart';
import 'business_approval.dart';
import 'business_definition.dart';
import 'business_query.dart';
import 'business_record.dart';

/// The `{"view", "data"}` document a custom view returns.
final class KumweCustomViewDocument {
  /// Validates a custom-view response document.
  factory KumweCustomViewDocument.fromJson(Map<String, Object?> json) {
    final view = json['view'];
    if (view is! Map<String, Object?>) {
      throw const FormatException('Custom view responses describe their view.');
    }
    final handle = view['handle'];
    if (handle is! String || !KumweBusinessHandles.isHandle(handle)) {
      throw const FormatException(
        'Custom view descriptors carry a bounded handle.',
      );
    }
    final label = view['label'];
    if (label is! String || label.isEmpty || label.length > 191) {
      throw const FormatException(
        'Custom view descriptors carry a bounded label.',
      );
    }
    final data = json['data'];
    if (data is! Map<String, Object?>) {
      throw const FormatException('Custom view responses carry a data object.');
    }
    return KumweCustomViewDocument._(
      handle: handle,
      label: label,
      kind: KumweViewKind.parse(view['kind']),
      fields: KumweBusinessHandles.handleList(view['fields'], 'view fields'),
      filters: KumweBusinessHandles.handleList(view['filters'], 'view filters'),
      sorts: KumweBusinessHandles.handleList(view['sorts'], 'view sorts'),
      data: KumweJsonValue.from(data),
    );
  }

  const KumweCustomViewDocument._({
    required this.handle,
    required this.label,
    required this.kind,
    required this.fields,
    required this.filters,
    required this.sorts,
    required this.data,
  });

  /// View handle the server executed.
  final String handle;

  /// Human-readable view label.
  final String label;

  /// Declared view kind.
  final KumweViewKind kind;

  /// Field handles the view projects.
  final List<String> fields;

  /// Field handles the view allows filtering on.
  final List<String> filters;

  /// Field handles the view allows sorting on.
  final List<String> sorts;

  /// Contract-validated result document.
  final KumweJsonValue data;

  @override
  String toString() => 'KumweCustomViewDocument($handle)';
}

/// Typed transport for the observed generated business surface.
///
/// Every method speaks one route the audited core serves under
/// `/api/v1/business`, with the exact header discipline those routes
/// enforce: bearer plus `Kumwe-Site` on every call, `Idempotency-Key` on
/// every mutation, a strong `"vN"` `If-Match` where the record ledger
/// demands one. Reads come back as [KumweResult]; mutations come back as
/// [KumweMutationOutcome], and a transport failure after send becomes an
/// ambiguous outcome that keeps the intent alive instead of minting a new
/// key.
final class KumweBusinessApi {
  /// Creates a business API over [options] and [transport].
  ///
  /// The whole surface is authenticated, so [options] must carry a site
  /// and a bearer token provider.
  factory KumweBusinessApi({
    required KumweClientOptions options,
    required KumweTransport transport,
    required KumweProblemRegistry registry,
  }) {
    if (options.site == null || options.tokenProvider == null) {
      throw ArgumentError(
        'The business surface requires a configured site and bearer '
        'token provider.',
      );
    }
    return KumweBusinessApi._(
      options: options,
      transport: transport,
      registry: registry,
    );
  }

  const KumweBusinessApi._({
    required this.options,
    required KumweTransport transport,
    required KumweProblemRegistry registry,
  }) : _transport = transport,
       _registry = registry;

  /// Deployment, site, credential and request identity configuration.
  final KumweClientOptions options;

  final KumweTransport _transport;
  final KumweProblemRegistry _registry;

  /// Reads the policy-filtered definition catalog.
  Future<KumweResult<KumweBusinessCatalog>> catalog() {
    return _read(
      '/api/v1/business/definitions',
      (json) => KumweBusinessCatalog.fromJson(json),
      unwrapData: false,
    );
  }

  /// Reads one policy-filtered definition document.
  ///
  /// Absent, disabled, unexposed and denied definitions are the same
  /// non-enumerating `business-record-not-found` problem by design.
  Future<KumweResult<KumweBusinessDefinition>> definition(String handle) {
    _requireHandle(handle, 'handle');
    return _read(
      '/api/v1/business/definitions/${Uri.encodeComponent(handle)}',
      (json) => KumweBusinessDefinition.fromJson(json),
      unwrapData: true,
    );
  }

  /// Runs a typed search over [definition].
  ///
  /// Search is a read-only POST: it carries no idempotency key and may be
  /// retried freely.
  Future<KumweResult<KumweRecordPageDocument>> search(
    String definition,
    KumweRecordQuery query,
  ) async {
    _requireHandle(definition, 'definition');
    final response = await _send(
      KumweHttpMethod.post,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}/search',
      body: KumweJsonValue.from(query.toJson()),
    );
    return _decode(response, (json) => KumweRecordPageDocument.fromJson(json));
  }

  /// Reads one record, optionally with a projection.
  Future<KumweResult<KumweBusinessRecord>> read(
    String definition,
    String recordId, {
    List<String> fields = const [],
    List<String> includes = const [],
    bool includeArchived = false,
    bool includeDeleted = false,
  }) async {
    _requireHandle(definition, 'definition');
    _requireRecordId(recordId);
    final projection = KumweRecordProjection(
      fields: fields,
      includes: includes,
    );
    final response = await _send(
      KumweHttpMethod.get,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}',
      query: {
        if (projection.fields.isNotEmpty)
          'projection[fields][]': projection.fields,
        if (projection.includes.isNotEmpty)
          'projection[includes][]': projection.includes,
        if (includeArchived) 'include_archived': 'true',
        if (includeDeleted) 'include_deleted': 'true',
      },
    );
    return _decode(response, (json) => KumweBusinessRecord.fromJson(json));
  }

  /// Reads a page of a record's history, newest first.
  Future<KumweResult<KumweRecordHistoryDocument>> history(
    String definition,
    String recordId, {
    int? limit,
    int? beforeVersion,
  }) async {
    _requireHandle(definition, 'definition');
    _requireRecordId(recordId);
    if (limit != null && (limit < 1 || limit > 200)) {
      throw ArgumentError.value(
        limit,
        'limit',
        'History limits run from 1 to 200.',
      );
    }
    if (beforeVersion != null && beforeVersion < 1) {
      throw ArgumentError.value(
        beforeVersion,
        'beforeVersion',
        'History continues before a positive version.',
      );
    }
    final response = await _send(
      KumweHttpMethod.get,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/history',
      query: {
        if (limit != null) 'limit': '$limit',
        if (beforeVersion != null) 'before_version': '$beforeVersion',
      },
    );
    return _decode(
      response,
      (json) => KumweRecordHistoryDocument.fromJson(json),
    );
  }

  /// Creates a record from [intent].
  ///
  /// The intent's canonical body is the closed create document —
  /// `{"values": {…}}` with an optional caller-chosen `record_id` — and
  /// must carry no precondition: nothing exists to precondition on.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> create(
    String definition,
    KumweMutationIntent intent,
  ) {
    _requireHandle(definition, 'definition');
    if (intent.ifMatch != null) {
      throw ArgumentError.value(
        intent,
        'intent',
        'Create intents carry no precondition.',
      );
    }
    return _mutate(
      KumweHttpMethod.post,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}',
      intent: intent,
      expectedStatus: 201,
    );
  }

  /// Updates a record from [intent].
  ///
  /// The record ledger demands a strong precondition, so the intent must
  /// have been built with the record's current entity tag.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> update(
    String definition,
    String recordId,
    KumweMutationIntent intent,
  ) {
    _requireHandle(definition, 'definition');
    _requireRecordId(recordId);
    _requirePrecondition(intent.ifMatch);
    return _mutate(
      KumweHttpMethod.patch,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}',
      intent: intent,
    );
  }

  /// Deletes a record; soft when the definition declares soft delete.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> delete(
    String definition,
    String recordId, {
    required IdempotencyKey key,
    required EntityTag ifMatch,
  }) {
    _requireHandle(definition, 'definition');
    _requireRecordId(recordId);
    return _emptyBodyMutation(
      KumweHttpMethod.delete,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}',
      key: key,
      ifMatch: ifMatch,
    );
  }

  /// Archives a record.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> archive(
    String definition,
    String recordId, {
    required IdempotencyKey key,
    required EntityTag ifMatch,
  }) {
    _requireHandle(definition, 'definition');
    _requireRecordId(recordId);
    return _emptyBodyMutation(
      KumweHttpMethod.post,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/archive',
      key: key,
      ifMatch: ifMatch,
    );
  }

  /// Restores an archived or soft-deleted record.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> restore(
    String definition,
    String recordId, {
    required IdempotencyKey key,
    required EntityTag ifMatch,
  }) {
    _requireHandle(definition, 'definition');
    _requireRecordId(recordId);
    return _emptyBodyMutation(
      KumweHttpMethod.post,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/restore',
      key: key,
      ifMatch: ifMatch,
    );
  }

  /// Runs a declared or custom action from [intent].
  ///
  /// The intent's canonical body is the closed action document — an
  /// optional `input` and an optional `approval_request_id` — or `{}`
  /// when the action takes neither.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> act(
    String definition,
    String recordId,
    String action,
    KumweMutationIntent intent,
  ) {
    _requireHandle(definition, 'definition');
    _requireHandle(action, 'action');
    _requireRecordId(recordId);
    _requirePrecondition(intent.ifMatch);
    return _mutate(
      KumweHttpMethod.post,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/actions'
      '/${Uri.encodeComponent(action)}',
      intent: intent,
    );
  }

  /// Asks whether [action] needs approval, storing a request when it does.
  Future<KumweMutationOutcome<KumweApprovalRequestOutcome>> requestApproval(
    String definition,
    String recordId,
    String action,
    KumweMutationIntent intent,
  ) async {
    _requireHandle(definition, 'definition');
    _requireHandle(action, 'action');
    _requireRecordId(recordId);
    _requirePrecondition(intent.ifMatch);
    final KumweResponse response;
    try {
      response = await _send(
        KumweHttpMethod.post,
        '/api/v1/business/records/${Uri.encodeComponent(definition)}'
        '/${Uri.encodeComponent(recordId)}/actions'
        '/${Uri.encodeComponent(action)}/approval',
        bodyBytes: intent.canonicalBytes,
        headers: intent.headers(),
      );
    } on KumweTransportException {
      return const KumweMutationOutcome.ambiguous();
    }
    if (!response.isSuccessful) {
      return KumweMutationOutcome.fromProblem(
        KumweResult<KumweApprovalRequestOutcome>.problem(
          KumweProblem.fromResponse(response, registry: _registry),
        ),
      );
    }
    final metadata = KumweResponseMetadata.fromResponse(response);
    return KumweMutationOutcome.fromSuccess(
      _parseBody(
        response,
        (json) => KumweApprovalRequestOutcome.fromJson(json),
      ),
      metadata,
    );
  }

  /// Reads the source record with exactly one include for [relation].
  Future<KumweResult<KumweBusinessRecord>> relations(
    String definition,
    String recordId,
    String relation,
  ) async {
    _requireHandle(definition, 'definition');
    _requireHandle(relation, 'relation');
    _requireRecordId(recordId);
    final response = await _send(
      KumweHttpMethod.get,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/relations'
      '/${Uri.encodeComponent(relation)}',
    );
    return _decode(response, (json) => KumweBusinessRecord.fromJson(json));
  }

  /// Relates a target record — or creates an owned line — from [intent].
  ///
  /// The intent's canonical body is the closed relate document:
  /// `target_record_id`, optional `position`, optional `target_values`.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> relate(
    String definition,
    String recordId,
    String relation,
    KumweMutationIntent intent,
  ) {
    _requireHandle(definition, 'definition');
    _requireHandle(relation, 'relation');
    _requireRecordId(recordId);
    _requirePrecondition(intent.ifMatch);
    return _mutate(
      KumweHttpMethod.post,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/relations'
      '/${Uri.encodeComponent(relation)}',
      intent: intent,
    );
  }

  /// Removes one related record.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> unrelate(
    String definition,
    String recordId,
    String relation,
    String targetRecordId, {
    required IdempotencyKey key,
    required EntityTag ifMatch,
  }) {
    _requireHandle(definition, 'definition');
    _requireHandle(relation, 'relation');
    _requireRecordId(recordId);
    _requireRecordId(targetRecordId);
    return _emptyBodyMutation(
      KumweHttpMethod.delete,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/relations'
      '/${Uri.encodeComponent(relation)}'
      '/${Uri.encodeComponent(targetRecordId)}',
      key: key,
      ifMatch: ifMatch,
    );
  }

  /// Reorders an ordered relationship from [intent].
  ///
  /// The intent's canonical body is the closed reorder document:
  /// `{"ordered_record_ids": […]}`.
  Future<KumweMutationOutcome<KumweRecordMutationDocument>> reorder(
    String definition,
    String recordId,
    String relation,
    KumweMutationIntent intent,
  ) {
    _requireHandle(definition, 'definition');
    _requireHandle(relation, 'relation');
    _requireRecordId(recordId);
    _requirePrecondition(intent.ifMatch);
    return _mutate(
      KumweHttpMethod.put,
      '/api/v1/business/records/${Uri.encodeComponent(definition)}'
      '/${Uri.encodeComponent(recordId)}/relations'
      '/${Uri.encodeComponent(relation)}/order',
      intent: intent,
    );
  }

  /// Executes a custom collection view.
  Future<KumweResult<KumweCustomViewDocument>> customView(
    String definition,
    String view, {
    String? recordId,
    KumweRecordQuery? query,
    KumweJsonValue? parameters,
  }) async {
    _requireHandle(definition, 'definition');
    _requireHandle(view, 'view');
    if (recordId != null) {
      _requireRecordId(recordId);
    }
    final route = recordId == null
        ? '/api/v1/business/views/${Uri.encodeComponent(definition)}'
              '/${Uri.encodeComponent(view)}'
        : '/api/v1/business/views/${Uri.encodeComponent(definition)}'
              '/${Uri.encodeComponent(recordId)}'
              '/${Uri.encodeComponent(view)}';
    final response = await _send(
      KumweHttpMethod.post,
      route,
      body: KumweJsonValue.from({
        if (query != null) 'query': query.toJson(),
        if (parameters != null) 'parameters': parameters.value,
      }),
    );
    return _decode(response, (json) => KumweCustomViewDocument.fromJson(json));
  }

  /// Reads the caller's approval inbox.
  Future<KumweResult<KumweApprovalInboxDocument>> approvals({
    int? limit,
  }) async {
    if (limit != null && (limit < 1 || limit > 100)) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Approval inbox limits run from 1 to 100.',
      );
    }
    final response = await _send(
      KumweHttpMethod.get,
      '/api/v1/business/approvals',
      query: {if (limit != null) 'limit': '$limit'},
    );
    return _decode(
      response,
      (json) => KumweApprovalInboxDocument.fromJson(json),
    );
  }

  /// Reads one approval request with its votes.
  Future<KumweResult<KumweBusinessApproval>> approval(
    String approvalRequestId,
  ) async {
    if (approvalRequestId.isEmpty || approvalRequestId.length > 64) {
      throw ArgumentError.value(
        '<id>',
        'approvalRequestId',
        'Approval identifiers are bounded strings.',
      );
    }
    final response = await _send(
      KumweHttpMethod.get,
      '/api/v1/business/approvals'
      '/${Uri.encodeComponent(approvalRequestId)}',
    );
    return _decode(response, (json) => KumweBusinessApproval.fromJson(json));
  }

  /// Reads the caller-bound status of one completed mutation by its
  /// idempotency key — the read that settles an ambiguous outcome.
  ///
  /// A pending, expired or foreign operation is the same non-enumerating
  /// `business-operation-not-found` problem; a served document proves the
  /// mutation committed.
  Future<KumweResult<KumweOperationStatusDocument>> operationStatus(
    IdempotencyKey key,
  ) async {
    final response = await _send(
      KumweHttpMethod.get,
      '/api/v1/business/operations/${Uri.encodeComponent(key.value)}',
    );
    return _decode(
      response,
      (json) => KumweOperationStatusDocument.fromJson(json),
    );
  }

  Future<KumweResult<T>> _read<T>(
    String route,
    T Function(Map<String, Object?>) parse, {
    required bool unwrapData,
  }) async {
    final response = await _send(KumweHttpMethod.get, route);
    if (!response.isSuccessful) {
      return KumweResult<T>.problem(
        KumweProblem.fromResponse(response, registry: _registry),
      );
    }
    final metadata = KumweResponseMetadata.fromResponse(response);
    final json = _bodyObject(response);
    if (unwrapData) {
      final data = json['data'];
      if (data is! Map<String, Object?>) {
        throw KumweProtocolException(
          'The response data member is not an object.',
          response: response,
        );
      }
      return KumweResult<T>.success(_guarded(parse, data, response), metadata);
    }
    return KumweResult<T>.success(_guarded(parse, json, response), metadata);
  }

  Future<KumweResult<T>> _decode<T>(
    KumweResponse response,
    T Function(Map<String, Object?>) parse,
  ) async {
    if (!response.isSuccessful) {
      return KumweResult<T>.problem(
        KumweProblem.fromResponse(response, registry: _registry),
      );
    }
    final metadata = KumweResponseMetadata.fromResponse(response);
    return KumweResult<T>.success(_parseBody(response, parse), metadata);
  }

  Future<KumweMutationOutcome<KumweRecordMutationDocument>> _mutate(
    KumweHttpMethod method,
    String route, {
    required KumweMutationIntent intent,
    int? expectedStatus,
  }) async {
    final KumweResponse response;
    try {
      response = await _send(
        method,
        route,
        bodyBytes: intent.canonicalBytes,
        headers: intent.headers(),
      );
    } on KumweTransportException {
      return const KumweMutationOutcome.ambiguous();
    }
    return _mutationOutcome(response, expectedStatus: expectedStatus);
  }

  Future<KumweMutationOutcome<KumweRecordMutationDocument>> _emptyBodyMutation(
    KumweHttpMethod method,
    String route, {
    required IdempotencyKey key,
    required EntityTag ifMatch,
  }) async {
    final KumweResponse response;
    try {
      response = await _send(
        method,
        route,
        headers: {
          IdempotencyKey.headerName: key.value,
          'If-Match': ifMatch.value,
        },
      );
    } on KumweTransportException {
      return const KumweMutationOutcome.ambiguous();
    }
    return _mutationOutcome(response);
  }

  KumweMutationOutcome<KumweRecordMutationDocument> _mutationOutcome(
    KumweResponse response, {
    int? expectedStatus,
  }) {
    if (!response.isSuccessful) {
      return KumweMutationOutcome.fromProblem(
        KumweResult<KumweRecordMutationDocument>.problem(
          KumweProblem.fromResponse(response, registry: _registry),
        ),
      );
    }
    if (expectedStatus != null && response.statusCode != expectedStatus) {
      throw KumweProtocolException(
        'Expected status $expectedStatus for this mutation.',
        response: response,
      );
    }
    final metadata = KumweResponseMetadata.fromResponse(response);
    final envelope = _parseBody(
      response,
      (json) => KumweRecordMutationDocument.fromJson(json),
    );
    if (envelope.replayed != metadata.idempotencyReplayed) {
      throw KumweProtocolException(
        'The replay marker header and envelope disagree.',
        response: response,
      );
    }
    final etag = metadata.etag;
    if (etag != null && etag != envelope.entityTag.value) {
      throw KumweProtocolException(
        'The response entity tag does not match the envelope version.',
        response: response,
      );
    }
    return KumweMutationOutcome.fromSuccess(envelope, metadata);
  }

  T _parseBody<T>(
    KumweResponse response,
    T Function(Map<String, Object?>) parse,
  ) {
    return _guarded(parse, _bodyObject(response), response);
  }

  Map<String, Object?> _bodyObject(KumweResponse response) {
    try {
      return response.jsonObject().value;
    } on FormatException catch (error) {
      throw KumweProtocolException(
        'The business response body is not a JSON object.',
        response: response,
        cause: error,
      );
    }
  }

  T _guarded<T>(
    T Function(Map<String, Object?>) parse,
    Map<String, Object?> json,
    KumweResponse response,
  ) {
    try {
      return parse(json);
    } on FormatException catch (error) {
      throw KumweProtocolException(
        'The business response is malformed.',
        response: response,
        cause: error,
      );
    }
  }

  Future<KumweResponse> _send(
    KumweHttpMethod method,
    String route, {
    KumweJsonValue? body,
    List<int>? bodyBytes,
    Map<String, String> headers = const {},
    Map<String, Object> query = const {},
  }) async {
    final provider = options.tokenProvider!;
    final token = await provider.token();
    if (token == null) {
      throw const KumweAuthenticationException(
        'The bearer token provider has no authenticated session.',
      );
    }
    var uri = options.resolveRoute(route);
    if (query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    var headerMap = HeaderMap({
      'Accept': 'application/json',
      'Authorization': 'Bearer ${token.value}',
      'Kumwe-Site': options.site!,
      'X-Request-ID': options.requestIdFactory(),
    }).overlay(headers);
    final List<int> bytes;
    if (body != null) {
      headerMap = headerMap.overlay(const {'Content-Type': 'application/json'});
      bytes = KumweRequest.json(method: method, uri: uri, body: body).body;
    } else if (bodyBytes != null) {
      headerMap = headerMap.overlay(const {'Content-Type': 'application/json'});
      bytes = bodyBytes;
    } else {
      bytes = const [];
    }
    return _transport.send(
      KumweRequest(method: method, uri: uri, headers: headerMap, body: bytes),
    );
  }

  static void _requireHandle(String value, String name) {
    if (!KumweBusinessHandles.isHandle(value)) {
      throw ArgumentError.value(
        '<handle>',
        name,
        'Business handles are bounded lowercase identifiers.',
      );
    }
  }

  static void _requireRecordId(String value) {
    if (value.isEmpty ||
        value.length > 191 ||
        value.codeUnits.any((unit) => unit <= 0x1f || unit == 0x7f)) {
      throw ArgumentError.value(
        '<recordId>',
        'recordId',
        'Record identifiers are bounded control-free strings.',
      );
    }
  }

  static void _requirePrecondition(EntityTag? ifMatch) {
    if (ifMatch == null) {
      throw ArgumentError(
        'This mutation family demands a strong "vN" precondition; build '
        'the intent with the record\'s current entity tag.',
      );
    }
  }
}
