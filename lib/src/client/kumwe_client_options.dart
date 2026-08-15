import 'dart:math';

import '../auth/bearer_token_provider.dart';

/// Creates one correlation identity for an outgoing request.
typedef KumweRequestIdFactory = String Function();

/// Returns the current time. Applications can inject a deterministic clock.
typedef KumweClock = DateTime Function();

/// Deployment and credential context shared by one [KumweClient].
final class KumweClientOptions {
  /// Creates validated client options.
  factory KumweClientOptions({
    required Uri baseUri,
    String? site,
    BearerTokenProvider? tokenProvider,
    KumweRequestIdFactory? requestIdFactory,
    KumweClock? clock,
    bool allowInsecureHttp = false,
  }) {
    final allowedScheme =
        baseUri.scheme == 'https' ||
        (allowInsecureHttp && baseUri.scheme == 'http');
    if (!allowedScheme ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw ArgumentError.value(
        baseUri,
        'baseUri',
        'The base URI must be an approved HTTPS URI without credentials, query, or fragment.',
      );
    }
    final path = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    final normalizedSite = site == null ? null : _normalizeSite(site);
    return KumweClientOptions._(
      baseUri: baseUri.replace(path: path),
      site: normalizedSite,
      tokenProvider: tokenProvider,
      requestIdFactory: requestIdFactory ?? _secureRequestId,
      clock: clock ?? DateTime.now,
    );
  }

  const KumweClientOptions._({
    required this.baseUri,
    required this.site,
    required this.tokenProvider,
    required this.requestIdFactory,
    required this.clock,
  });

  /// Kumwe deployment URI, normalized with a trailing path separator.
  final Uri baseUri;

  /// Explicit normalized site for protected requests.
  final String? site;

  /// Application-owned source of short-lived bearer credentials.
  final BearerTokenProvider? tokenProvider;

  /// Correlation identity factory used for every request.
  final KumweRequestIdFactory requestIdFactory;

  /// Clock used to timestamp cache validation.
  final KumweClock clock;

  /// Resolves a root-relative Kumwe route beneath [baseUri].
  Uri resolveRoute(String route) {
    if (!route.startsWith('/') || route.startsWith('//')) {
      throw ArgumentError.value(
        route,
        'route',
        'Kumwe routes must start with exactly one slash.',
      );
    }
    try {
      if (route.substring(1).split('/').any((segment) {
        final decoded = Uri.decodeComponent(segment);
        return decoded == '.' || decoded == '..';
      })) {
        throw ArgumentError.value(
          route,
          'route',
          'Kumwe routes cannot contain dot segments.',
        );
      }
    } on FormatException {
      throw ArgumentError.value(
        route,
        'route',
        'Kumwe routes must use valid percent encoding.',
      );
    }
    final parsed = Uri.parse(route);
    if (parsed.hasScheme ||
        parsed.hasAuthority ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw ArgumentError.value(
        route,
        'route',
        'Kumwe routes cannot replace or escape the configured base path.',
      );
    }
    return baseUri.resolve(route.substring(1));
  }

  static String _normalizeSite(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._:-]{0,190}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'site',
        'Sites must contain 1 to 191 supported identifier characters.',
      );
    }
    return normalized;
  }

  static String _secureRequestId() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static final Random _random = Random.secure();
}
