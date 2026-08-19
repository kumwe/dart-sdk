import '../contract/contract_cache.dart';
import '../contract/contract_metadata.dart';
import '../contract/contract_validator.dart';
import '../http/header_map.dart';
import '../http/kumwe_request.dart';
import '../http/kumwe_response.dart';
import '../http/kumwe_transport.dart';
import '../http/request_context.dart';
import '../json/kumwe_json.dart';
import '../problem/api_exception.dart';
import 'kumwe_client_options.dart';

/// Static discovery document returned by `GET /api/v1`.
///
/// The `Kumwe CMS` literals below are observed wire values: the audited core
/// still reports that product string after the repository's rename to
/// `kumwe/app`. They change only when core changes its identity document,
/// never to match repository naming.
final class KumweApiDiscovery {
  /// Parses the stable Kumwe v1 discovery representation.
  factory KumweApiDiscovery.fromJson(Map<String, Object?> json) {
    final product = json['product'];
    final apiVersion = json['api_version'];
    final status = json['status'];
    if (product != 'Kumwe CMS' || apiVersion != 'v1' || status != 'available') {
      throw const FormatException(
        'The response is not a Kumwe CMS v1 discovery document.',
      );
    }
    return const KumweApiDiscovery._();
  }

  const KumweApiDiscovery._();

  /// Product identity pinned by the v1 discovery contract.
  String get product => 'Kumwe CMS';

  /// Versioned API identity.
  String get apiVersion => 'v1';

  /// Availability state returned by the static endpoint.
  String get status => 'available';
}

/// Static liveness document returned by `GET /health/live`.
///
/// The `Kumwe CMS` literal below is an observed wire value, kept for the
/// reason given on [KumweApiDiscovery]; changing it needs core's identity
/// document to change first.
final class KumweLiveness {
  /// Parses the stable liveness representation.
  factory KumweLiveness.fromJson(Map<String, Object?> json) {
    if (json['status'] != 'alive' || json['product'] != 'Kumwe CMS') {
      throw const FormatException(
        'The response is not a Kumwe liveness document.',
      );
    }
    return const KumweLiveness._();
  }

  const KumweLiveness._();

  /// Whether the process answered the Kumwe liveness contract.
  bool get isAlive => true;
}

/// Load-balancer readiness state.
enum KumweReadinessState {
  /// The worker can receive traffic.
  ready,

  /// The worker must be drained while a dependency is unavailable.
  notReady,
}

/// Readiness document returned by `GET /health/ready`.
final class KumweReadiness {
  /// Creates a readiness value.
  const KumweReadiness(this.state);

  /// Readiness state matching the HTTP status and response body.
  final KumweReadinessState state;

  /// Whether the worker can receive traffic.
  bool get isReady => state == KumweReadinessState.ready;
}

/// Small hand-written client for Kumwe's stable discovery surfaces.
///
/// Resource clients are intentionally absent until their OpenAPI request and
/// response contracts are complete enough for deterministic generation.
final class KumweClient {
  /// Creates a client over an application-selected [transport].
  factory KumweClient({
    required KumweClientOptions options,
    required KumweTransport transport,
    KumweContractCache? contractCache,
    String? authorizationPartition,
  }) {
    if ((contractCache == null) != (authorizationPartition == null)) {
      throw ArgumentError(
        'Contract caching requires both a cache and a non-secret authorization partition.',
      );
    }
    if (contractCache != null &&
        (options.site == null || options.tokenProvider == null)) {
      throw ArgumentError(
        'Contract caching requires a configured site and bearer token provider.',
      );
    }
    if (contractCache != null) {
      KumweContractCacheKey(
        baseUri: options.baseUri,
        site: options.site!,
        authorizationPartition: authorizationPartition!,
      );
    }
    return KumweClient._(
      options: options,
      transport: transport,
      contractCache: contractCache,
      authorizationPartition: authorizationPartition,
    );
  }

  const KumweClient._({
    required this.options,
    required KumweTransport transport,
    required KumweContractCache? contractCache,
    required String? authorizationPartition,
  }) : _transport = transport,
       _contractCache = contractCache,
       _authorizationPartition = authorizationPartition;

  /// Deployment, site, credential provider, and request identity configuration.
  final KumweClientOptions options;

  final KumweTransport _transport;
  final KumweContractCache? _contractCache;
  final String? _authorizationPartition;

  /// Reads Kumwe's unauthenticated API discovery document.
  Future<KumweApiDiscovery> discover() async {
    final response = await _get('/api/v1');
    _requireStatus(response, 200);
    try {
      return KumweApiDiscovery.fromJson(response.jsonObject().value);
    } on FormatException catch (error) {
      throw KumweProtocolException(
        'The API discovery response is malformed.',
        response: response,
        cause: error,
      );
    }
  }

  /// Reads Kumwe's unauthenticated process liveness document.
  Future<KumweLiveness> liveness() async {
    final response = await _get('/health/live');
    _requireStatus(response, 200);
    try {
      return KumweLiveness.fromJson(response.jsonObject().value);
    } on FormatException catch (error) {
      throw KumweProtocolException(
        'The liveness response is malformed.',
        response: response,
        cause: error,
      );
    }
  }

  /// Reads readiness, preserving `503 not_ready` as a valid probe result.
  Future<KumweReadiness> readiness() async {
    final response = await _get('/health/ready');
    if (response.statusCode != 200 && response.statusCode != 503) {
      throw KumweApiException.fromResponse(response);
    }
    try {
      final status = response.jsonObject()['status'];
      if (response.statusCode == 200 && status == 'ready') {
        return const KumweReadiness(KumweReadinessState.ready);
      }
      if (response.statusCode == 503 && status == 'not_ready') {
        return const KumweReadiness(KumweReadinessState.notReady);
      }
      throw const FormatException(
        'Readiness body and status code do not describe the same state.',
      );
    } on FormatException catch (error) {
      throw KumweProtocolException(
        'The readiness response is malformed.',
        response: response,
        cause: error,
      );
    }
  }

  /// Fetches the authenticated, caller-specific OpenAPI contract.
  ///
  /// A configured cache is partitioned by deployment, site, and an
  /// application-owned actor/credential-family identity. [forceRefresh]
  /// bypasses conditional reuse.
  Future<KumweContractFetchResult> fetchOpenApiContract({
    bool forceRefresh = false,
  }) async {
    final site = options.site;
    if (site == null) {
      throw const KumweAuthenticationException(
        'A Kumwe site is required to fetch the protected OpenAPI contract.',
      );
    }
    final cacheKey = _cacheKey(site);
    final cache = _contractCache;
    final cached = !forceRefresh && cacheKey != null && cache != null
        ? await cache.read(cacheKey)
        : null;
    final context = cached == null
        ? null
        : KumweRequestContext(ifNoneMatch: cached.metadata.etag);
    final response = await _get(
      '/api/v1/openapi.json',
      authenticated: true,
      context: context,
      accept: 'application/vnd.oai.openapi+json;version=3.1',
    );
    if (response.statusCode == 304) {
      if (cached == null || cacheKey == null || cache == null) {
        throw KumweProtocolException(
          'Kumwe returned 304 without a matching cached contract.',
          response: response,
        );
      }
      _requireConditionalIdentity(response, cached);
      _requireValidOpenApiDocument(cached.document, response);
      await cache.write(cacheKey, cached);
      return KumweContractFetchResult(contract: cached, notModified: true);
    }
    _requireStatus(response, 200);
    if (response.mediaType != 'application/vnd.oai.openapi+json') {
      throw KumweProtocolException(
        'The contract response has an unexpected media type.',
        response: response,
      );
    }
    try {
      final document = response.jsonObject();
      _requireValidOpenApiDocument(document, response);
      final generation = response.headers['x-kumwe-contract-generation'];
      final etag = response.headers['etag'];
      if (generation == null || etag == null) {
        throw const FormatException(
          'Contract generation and entity-tag headers are required.',
        );
      }
      final metadata = KumweContractMetadata(
        generation: generation,
        etag: etag,
        fetchedAt: options.clock(),
      );
      final contract = KumweOpenApiContract(
        document: document,
        metadata: metadata,
      );
      if (cacheKey != null && cache != null) {
        await cache.write(cacheKey, contract);
      }
      return KumweContractFetchResult(contract: contract, notModified: false);
    } on FormatException catch (error) {
      throw KumweProtocolException(
        'The contract response is malformed.',
        response: response,
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw KumweProtocolException(
        'The contract response carries inconsistent identity metadata.',
        response: response,
        cause: error,
      );
    }
  }

  KumweContractCacheKey? _cacheKey(String site) {
    final partition = _authorizationPartition;
    if (_contractCache == null || partition == null) {
      return null;
    }
    return KumweContractCacheKey(
      baseUri: options.baseUri,
      site: site,
      authorizationPartition: partition,
    );
  }

  Future<KumweResponse> _get(
    String route, {
    bool authenticated = false,
    KumweRequestContext? context,
    String accept = 'application/json',
  }) async {
    final requestId = context?.requestId ?? options.requestIdFactory();
    final effectiveContext = KumweRequestContext(
      requestId: requestId,
      idempotencyKey: context?.idempotencyKey,
      ifMatch: context?.ifMatch,
      ifNoneMatch: context?.ifNoneMatch,
    );
    var headers = HeaderMap({
      'Accept': accept,
    }).overlay(effectiveContext.toHeaders());
    if (authenticated) {
      final site = options.site;
      final provider = options.tokenProvider;
      if (site == null || provider == null) {
        throw const KumweAuthenticationException(
          'A bearer token provider and Kumwe site are required for this request.',
        );
      }
      final token = await provider.token();
      if (token == null) {
        throw const KumweAuthenticationException(
          'The bearer token provider has no authenticated session.',
        );
      }
      headers = headers.overlay({
        'Authorization': 'Bearer ${token.value}',
        'Kumwe-Site': site,
      });
    }
    return _transport.send(
      KumweRequest(
        method: KumweHttpMethod.get,
        uri: options.resolveRoute(route),
        headers: headers,
      ),
    );
  }

  void _requireConditionalIdentity(
    KumweResponse response,
    KumweOpenApiContract cached,
  ) {
    final etag = response.headers['etag'];
    final generation = response.headers['x-kumwe-contract-generation'];
    if (etag != cached.metadata.etag ||
        generation != cached.metadata.generation ||
        response.body.isNotEmpty) {
      throw KumweProtocolException(
        'The 304 response does not match the cached contract identity.',
        response: response,
      );
    }
  }

  void _requireValidOpenApiDocument(
    KumweJsonObject document,
    KumweResponse response,
  ) {
    if (document['openapi'] != '3.1.0') {
      throw KumweProtocolException(
        'Expected an OpenAPI 3.1.0 document.',
        response: response,
      );
    }
    final validation = OpenApiContractValidator().validate(document);
    if (!validation.isValid) {
      final first = validation.issues.first;
      throw KumweProtocolException(
        'The OpenAPI contract has ${validation.issues.length} validation issue(s); '
        'first issue: $first',
        response: response,
      );
    }
  }

  void _requireStatus(KumweResponse response, int status) {
    if (response.statusCode != status) {
      throw KumweApiException.fromResponse(response);
    }
  }
}
