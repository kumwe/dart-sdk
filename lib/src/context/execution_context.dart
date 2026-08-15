import '../auth/credential_reference.dart';

/// The context an application asks to open a session for.
///
/// Selection is explicit: the SDK never derives a site from an origin host
/// and never edits organization or workspace bindings speculatively. The
/// server remains the authority on whether the selection is permitted.
final class KumweContextSelection {
  /// Creates a validated, normalized selection.
  factory KumweContextSelection({
    required String site,
    String? organization,
    String? workspace,
    String? locale,
  }) {
    if (workspace != null && organization == null) {
      throw ArgumentError.value(
        workspace,
        'workspace',
        'A workspace is selected inside an organization.',
      );
    }
    return KumweContextSelection._(
      site: KumweContextIdentifiers.normalizeSite(site),
      organization: organization == null
          ? null
          : KumweContextIdentifiers.normalizeSelection(
              organization,
              'organization',
            ),
      workspace: workspace == null
          ? null
          : KumweContextIdentifiers.normalizeSelection(workspace, 'workspace'),
      locale: locale == null
          ? null
          : KumweContextIdentifiers.normalizeLocale(locale),
    );
  }

  const KumweContextSelection._({
    required this.site,
    required this.organization,
    required this.workspace,
    required this.locale,
  });

  /// Normalized site identifier sent as the `Kumwe-Site` header.
  final String site;

  /// Optional opaque organization selection identifier.
  final String? organization;

  /// Optional opaque workspace selection identifier within [organization].
  final String? workspace;

  /// Optional normalized IETF language tag for localized metadata.
  final String? locale;

  @override
  bool operator ==(Object other) =>
      other is KumweContextSelection &&
      other.site == site &&
      other.organization == organization &&
      other.workspace == workspace &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(site, organization, workspace, locale);

  @override
  String toString() =>
      'KumweContextSelection(site: $site, organization: $organization, '
      'workspace: $workspace, locale: $locale)';
}

/// Shared validation for the bounded context identifier vocabulary.
final class KumweContextIdentifiers {
  const KumweContextIdentifiers._();

  /// Normalizes and validates a site identifier.
  ///
  /// The bounds mirror the audited `Kumwe-Site` header vocabulary: 1 to 191
  /// characters from the supported identifier set, compared lowercase.
  static String normalizeSite(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_sitePattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'site',
        'Sites must contain 1 to 191 supported identifier characters.',
      );
    }
    return normalized;
  }

  /// Validates an opaque organization or workspace selection identifier.
  ///
  /// Selection identifiers come from the server's context discovery; they are
  /// only bounded here, never interpreted.
  static String normalizeSelection(String value, String name) {
    final normalized = value.trim();
    if (!_selectionPattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        name,
        'Selection identifiers must contain 1 to 191 supported characters.',
      );
    }
    return normalized;
  }

  /// Validates and canonicalizes a true HTTPS origin.
  ///
  /// An origin is scheme, host and optional port only: user information,
  /// path, query and fragment are rejected rather than dropped, so two
  /// spellings can never alias one credential or cache partition. The
  /// returned URI is the canonical no-path form.
  static Uri normalizeOrigin(Uri origin, String name) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw ArgumentError.value(
        origin,
        name,
        'Origins are an exact HTTPS scheme, host and optional port without '
        'credentials, path, query, or fragment.',
      );
    }
    return origin.hasPort
        ? Uri(scheme: 'https', host: origin.host, port: origin.port)
        : Uri(scheme: 'https', host: origin.host);
  }

  /// Normalizes and validates a bounded IETF language tag such as `en-NA`.
  static String normalizeLocale(String value) {
    final normalized = value.trim();
    if (normalized.length > 35 || !_localePattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'locale',
        'Locales use a bounded IETF language tag such as en or en-NA.',
      );
    }
    return normalized;
  }

  static final RegExp _sitePattern = RegExp(r'^[a-z0-9][a-z0-9._:-]{0,190}$');

  static final RegExp _selectionPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$',
  );

  static final RegExp _localePattern = RegExp(
    r'^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$',
  );
}

/// One immutable authenticated execution context.
///
/// Every protected request derives its `Kumwe-Site` header and cache identity
/// from this validated object, never from the origin host. Switching context
/// means closing the session this context belongs to and opening a new one;
/// nothing here is mutable.
final class KumweExecutionContext {
  /// Creates a validated execution context.
  factory KumweExecutionContext({
    required Uri origin,
    required KumweContextSelection selection,
    required KumweCredentialReference credential,
    String? correlationRoot,
    Map<String, String> authorityGenerations = const {},
  }) {
    final canonicalOrigin = KumweContextIdentifiers.normalizeOrigin(
      origin,
      'origin',
    );
    final root = correlationRoot?.trim();
    if (root != null && !_correlationPattern.hasMatch(root)) {
      throw ArgumentError.value(
        correlationRoot,
        'correlationRoot',
        'Correlation roots must contain 1 to 128 supported characters.',
      );
    }
    if (authorityGenerations.length > 16 ||
        authorityGenerations.entries.any(
          (entry) =>
              !_generationKeyPattern.hasMatch(entry.key) ||
              !_generationValuePattern.hasMatch(entry.value),
        )) {
      throw ArgumentError.value(
        authorityGenerations,
        'authorityGenerations',
        'Authority generations are a bounded map of up to 16 identifier '
            'keys with identifier values of 1 to 191 characters.',
      );
    }
    return KumweExecutionContext._(
      origin: canonicalOrigin,
      selection: selection,
      credential: credential,
      correlationRoot: root,
      authorityGenerations: Map.unmodifiable(authorityGenerations),
    );
  }

  const KumweExecutionContext._({
    required this.origin,
    required this.selection,
    required this.credential,
    required this.correlationRoot,
    required this.authorityGenerations,
  });

  /// Exact HTTPS origin this context is bound to.
  final Uri origin;

  /// Validated site, organization, workspace and locale selection.
  final KumweContextSelection selection;

  /// Opaque non-secret reference naming the credential in use.
  final KumweCredentialReference credential;

  /// Optional root value correlating every request in this context.
  final String? correlationRoot;

  /// Server-supplied authority generation values used in cache identities,
  /// such as policy generation or security epoch, when the server exposes
  /// them. Keys and values are opaque identifiers; the identifier character
  /// set keeps them free of the partition separators below.
  final Map<String, String> authorityGenerations;

  /// Site header value derived from the validated [selection].
  String get siteHeader => selection.site;

  /// Stable cache partition identity for this context.
  ///
  /// Includes origin, site, credential reference, organization/workspace and
  /// every authority generation, so cached data can never leak across
  /// credential or authority boundaries.
  String get cachePartition {
    final generations =
        authorityGenerations.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .toList()
          ..sort();
    return [
      origin.toString(),
      selection.site,
      credential.value,
      selection.organization ?? '',
      selection.workspace ?? '',
      generations.join(','),
    ].join('|');
  }

  @override
  String toString() =>
      'KumweExecutionContext(origin: $origin, site: ${selection.site}, '
      'credential: ${credential.value})';

  static final RegExp _correlationPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
  );

  static final RegExp _generationKeyPattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]{0,63}$',
  );

  static final RegExp _generationValuePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$',
  );
}
