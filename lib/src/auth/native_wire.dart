import 'dart:collection';

import '../auth/authorization_provider.dart';
import '../auth/bearer_token_provider.dart';
import '../auth/credential_reference.dart';
import '../auth/web_session_handoff.dart';
import '../context/execution_context.dart';
import 'account_state.dart';
import 'login_area.dart';

/// A bounded semantic version, compared numerically.
final class KumweContractVersion implements Comparable<KumweContractVersion> {
  /// Parses a bounded `major.minor.patch` version, ignoring any
  /// prerelease suffix for window comparison.
  factory KumweContractVersion(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw FormatException(
        'Contract versions are bounded major.minor.patch values.',
      );
    }
    return KumweContractVersion._(
      value,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  const KumweContractVersion._(this.value, this.major, this.minor, this.patch);

  /// Complete version string as received.
  final String value;

  /// Major component.
  final int major;

  /// Minor component.
  final int minor;

  /// Patch component.
  final int patch;

  @override
  int compareTo(KumweContractVersion other) {
    if (major != other.major) {
      return major - other.major;
    }
    if (minor != other.minor) {
      return minor - other.minor;
    }
    return patch - other.patch;
  }

  @override
  bool operator ==(Object other) =>
      other is KumweContractVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => 'KumweContractVersion($value)';

  static final RegExp _pattern = RegExp(
    r'^([0-9]{1,5})\.([0-9]{1,5})\.([0-9]{1,5})(?:-[A-Za-z0-9.-]{1,40})?$',
  );
}

/// An executable reader for the native discovery document.
///
/// The discovery document is what a multi-installation client stores per
/// entered deployment URL: installation identity, exact allowed origins, the
/// compatibility window, advertised authorization profiles and sign-in
/// areas, the site-header rule and pre-authentication limits. This reader
/// validates the closed wire shape again as defense in depth and proves the
/// *proposed* contract by consuming it; core adoption (`CORE-CTX-001`)
/// replaces the document, not this reader. A discovery document grants no
/// capability — every advertised capability is re-checked by server
/// authorization on use.
final class KumweNativeDiscoveryDocument {
  /// Validates a discovery document.
  factory KumweNativeDiscoveryDocument.fromJson(Map<String, Object?> json) {
    final installation = _object(json, 'installation');
    final reference = _identifier(installation, 'reference');
    final displayName = installation['display_name'];
    if (displayName is! String ||
        displayName.isEmpty ||
        displayName.length > 120) {
      throw const FormatException(
        'The installation display name needs 1 to 120 characters.',
      );
    }
    final api = _object(json, 'api');
    if (api['base_path'] != '/api/v1') {
      throw const FormatException(
        'The discovery base path must be exactly /api/v1.',
      );
    }
    final rawOrigins = api['allowed_origins'];
    if (rawOrigins is! List<Object?> ||
        rawOrigins.isEmpty ||
        rawOrigins.length > 8) {
      throw const FormatException(
        'Discovery documents list 1 to 8 allowed origins.',
      );
    }
    final origins = <Uri>[];
    for (final rawOrigin in rawOrigins) {
      if (rawOrigin is! String || rawOrigin.length > 128) {
        throw const FormatException(
          'Allowed origins are bounded HTTPS origin strings.',
        );
      }
      final parsed = Uri.tryParse(rawOrigin);
      if (parsed == null) {
        throw const FormatException('An allowed origin is not a valid URI.');
      }
      origins.add(KumweContextIdentifiers.normalizeOrigin(parsed, 'origin'));
    }
    final compatibility = _object(json, 'compatibility');
    final openApiDigest = compatibility['openapi_digest'];
    if (openApiDigest is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(openApiDigest)) {
      throw const FormatException(
        'The compatibility digest is a sha256 value.',
      );
    }
    final minimum = KumweContractVersion(
      _string(compatibility, 'min_client_contract', 64),
    );
    final maximum = KumweContractVersion(
      _string(compatibility, 'max_client_contract', 64),
    );
    if (minimum.compareTo(maximum) > 0) {
      throw const FormatException(
        'The client-contract window minimum exceeds its maximum.',
      );
    }
    final authorization = _object(json, 'authorization');
    final rawProfiles = authorization['profiles'];
    if (rawProfiles is! List<Object?> ||
        rawProfiles.isEmpty ||
        rawProfiles.length > 4) {
      throw const FormatException(
        'Discovery documents advertise 1 to 4 authorization profiles.',
      );
    }
    final profiles = <String>{};
    for (final profile in rawProfiles) {
      if (profile is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{2,63}$').hasMatch(profile)) {
        throw const FormatException(
          'Authorization profiles are bounded lowercase identifiers.',
        );
      }
      if (!profiles.add(profile)) {
        throw const FormatException('Authorization profiles cannot repeat.');
      }
    }
    final areas = <KumweLoginArea>[];
    final rawAreas = authorization['areas'];
    if (rawAreas != null) {
      if (rawAreas is! List<Object?> ||
          rawAreas.isEmpty ||
          rawAreas.length > 2) {
        throw const FormatException(
          'Discovery documents advertise 1 to 2 sign-in areas.',
        );
      }
      for (final rawArea in rawAreas) {
        if (rawArea is! String) {
          throw const FormatException('Advertised areas are strings.');
        }
        final area = KumweLoginArea.parse(rawArea);
        if (areas.contains(area)) {
          throw const FormatException('Advertised areas cannot repeat.');
        }
        areas.add(area);
      }
    }
    final context = _object(json, 'context');
    if (context['site_header'] != 'Kumwe-Site' ||
        context['site_required'] != true) {
      throw const FormatException(
        'The discovery context must pin the Kumwe-Site header rule.',
      );
    }
    final limits = _object(json, 'limits');
    final maxRequestBytes = limits['max_request_bytes'];
    final maxPageSize = limits['max_page_size'];
    if (maxRequestBytes is! int ||
        maxRequestBytes < 1024 ||
        maxRequestBytes > 1073741824) {
      throw const FormatException(
        'The discovery request-byte limit is out of bounds.',
      );
    }
    if (maxPageSize is! int || maxPageSize < 1 || maxPageSize > 1000) {
      throw const FormatException(
        'The discovery page-size limit is out of bounds.',
      );
    }
    return KumweNativeDiscoveryDocument._(
      installationReference: reference,
      installationDisplayName: displayName,
      allowedOrigins: List<Uri>.unmodifiable(origins),
      coreVersion: _string(compatibility, 'core_version', 64),
      openApiDigest: openApiDigest,
      minClientContract: minimum,
      maxClientContract: maximum,
      authorizationProfiles: Set<String>.unmodifiable(profiles),
      advertisedAreas: List<KumweLoginArea>.unmodifiable(areas),
      maxRequestBytes: maxRequestBytes,
      maxPageSize: maxPageSize,
    );
  }

  const KumweNativeDiscoveryDocument._({
    required this.installationReference,
    required this.installationDisplayName,
    required this.allowedOrigins,
    required this.coreVersion,
    required this.openApiDigest,
    required this.minClientContract,
    required this.maxClientContract,
    required this.authorizationProfiles,
    required this.advertisedAreas,
    required this.maxRequestBytes,
    required this.maxPageSize,
  });

  /// Opaque installation reference.
  final String installationReference;

  /// Human-readable installation name for the account switcher.
  final String installationDisplayName;

  /// Exact HTTPS origins credentials may be sent to.
  final List<Uri> allowedOrigins;

  /// Advertised core product version.
  final String coreVersion;

  /// Digest of the deployment's OpenAPI contract.
  final String openApiDigest;

  /// Oldest client contract the deployment supports.
  final KumweContractVersion minClientContract;

  /// Newest client contract the deployment supports.
  final KumweContractVersion maxClientContract;

  /// Authorization profiles a client may attempt; an unlisted flow is
  /// never attempted as a fallback.
  final Set<String> authorizationProfiles;

  /// Sign-in areas the deployment enables; empty when the document does
  /// not advertise them, in which case no area chooser is offered.
  final List<KumweLoginArea> advertisedAreas;

  /// Pre-authentication request byte limit.
  final int maxRequestBytes;

  /// Pre-authentication page size limit.
  final int maxPageSize;

  /// Whether credentials may be sent to [origin].
  bool allowsOrigin(Uri origin) {
    final normalized = KumweContextIdentifiers.normalizeOrigin(
      origin,
      'origin',
    );
    return allowedOrigins.contains(normalized);
  }

  /// Whether the deployment advertises [profile].
  bool supportsProfile(String profile) =>
      authorizationProfiles.contains(profile);

  /// Whether a client speaking [version] is inside the supported window.
  ///
  /// A client outside the window refuses mutations before sending them
  /// rather than degrading silently.
  bool supportsClientContract(KumweContractVersion version) {
    return minClientContract.compareTo(version) <= 0 &&
        version.compareTo(maxClientContract) <= 0;
  }

  @override
  String toString() =>
      'KumweNativeDiscoveryDocument($installationReference, '
      '${allowedOrigins.length} origin(s))';

  static Map<String, Object?> _object(
    Map<String, Object?> json,
    String member,
  ) {
    final value = json[member];
    if (value is! Map<String, Object?>) {
      throw FormatException('The discovery $member member is an object.');
    }
    return value;
  }

  static String _string(
    Map<String, Object?> json,
    String member,
    int maxLength,
  ) {
    final value = json[member];
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw FormatException(
        'The discovery $member member needs 1 to $maxLength characters.',
      );
    }
    return value;
  }

  static String _identifier(Map<String, Object?> json, String member) {
    final value = json[member];
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$').hasMatch(value)) {
      throw FormatException(
        'The discovery $member member is a bounded identifier.',
      );
    }
    return value;
  }
}

/// An executable reader for the closed native token response.
///
/// The token response is the terminal wire shape of every authorization
/// profile: the opaque credential beside the non-secret metadata a client
/// needs to use it safely. This reader validates the *proposed* shape as a
/// working consumer; core adoption (`CORE-AUTH-001`) replaces the wire
/// document, not this reader. Secret material is redacted from diagnostics
/// and leaves this reader only through [toAccessToken].
final class KumweNativeTokenResponse {
  /// Validates a token response document.
  factory KumweNativeTokenResponse.fromJson(Map<String, Object?> json) {
    final accessToken = json['access_token'];
    if (accessToken is! String ||
        accessToken.length < 16 ||
        accessToken.length > 1024) {
      throw const FormatException(
        'Token responses carry a bounded access token.',
      );
    }
    if (json['token_type'] != 'Bearer') {
      throw const FormatException('Token responses are Bearer only.');
    }
    final expiresIn = json['expires_in'];
    if (expiresIn is! int || expiresIn < 300 || expiresIn > 7776000) {
      throw const FormatException(
        'Token lifetimes are between 300 and 7776000 seconds.',
      );
    }
    final refreshToken = json['refresh_token'];
    if (refreshToken != null &&
        (refreshToken is! String ||
            refreshToken.length < 16 ||
            refreshToken.length > 1024)) {
      throw const FormatException('Refresh tokens are bounded when present.');
    }
    final scope = json['scope'];
    if (scope != null &&
        (scope is! String ||
            scope.length > 1024 ||
            !RegExp(
              r'^[A-Za-z0-9._:-]+(?: [A-Za-z0-9._:-]+)*$',
            ).hasMatch(scope))) {
      throw const FormatException('Scopes are bounded token lists.');
    }
    final credential = json['credential'];
    if (credential is! Map<String, Object?>) {
      throw const FormatException('Token responses carry a credential object.');
    }
    final reference = _identifier(credential, 'reference', required: true)!;
    KumweLoginArea? area;
    final rawArea = credential['area'];
    if (rawArea != null) {
      if (rawArea is! String) {
        throw const FormatException('The credential area is a string.');
      }
      area = KumweLoginArea.parse(rawArea);
    }
    KumweAccountState? accountState;
    final account = json['account'];
    if (account != null) {
      if (account is! Map<String, Object?>) {
        throw const FormatException('The account member is an object.');
      }
      final state = account['state'];
      if (state is! String) {
        throw const FormatException('The account state is a string.');
      }
      accountState = KumweAccountState.parse(state);
    }
    final context = json['context'];
    if (context is! Map<String, Object?>) {
      throw const FormatException('Token responses carry a context object.');
    }
    final site = context['site'];
    if (site is! String) {
      throw const FormatException('The token context names its site.');
    }
    final generations = <String, String>{};
    final rawGenerations = json['authority_generations'];
    if (rawGenerations != null) {
      if (rawGenerations is! Map<String, Object?> ||
          rawGenerations.length > 16) {
        throw const FormatException('Authority generations are a bounded map.');
      }
      for (final entry in rawGenerations.entries) {
        final value = entry.value;
        if (!_generationKeyPattern.hasMatch(entry.key)) {
          throw const FormatException(
            'Authority generation keys are bounded identifiers.',
          );
        }
        if (value is! String ||
            value.isEmpty ||
            value.length > 191 ||
            !_generationValuePattern.hasMatch(value)) {
          throw const FormatException(
            'Authority generation values are bounded identifiers.',
          );
        }
        generations[entry.key] = value;
      }
    }
    return KumweNativeTokenResponse._(
      accessToken: accessToken,
      refreshToken: refreshToken as String?,
      expiresIn: Duration(seconds: expiresIn),
      scope: scope as String?,
      credentialReference: KumweCredentialReference(reference),
      credentialFamily: _identifier(credential, 'family'),
      purpose: _identifier(credential, 'purpose'),
      audience: _identifier(credential, 'audience'),
      subjectReference: _identifier(credential, 'subject_reference'),
      area: area,
      accountState: accountState,
      site: KumweContextIdentifiers.normalizeSite(site),
      organization: _identifier(context, 'organization'),
      workspace: _identifier(context, 'workspace'),
      authorityGenerations: UnmodifiableMapView(generations),
    );
  }

  const KumweNativeTokenResponse._({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.scope,
    required this.credentialReference,
    required this.credentialFamily,
    required this.purpose,
    required this.audience,
    required this.subjectReference,
    required this.area,
    required this.accountState,
    required this.site,
    required this.organization,
    required this.workspace,
    required this.authorityGenerations,
  });

  /// Opaque access token; secret material for the credential store only.
  final String accessToken;

  /// Opaque rotating refresh token, when the profile grants persistence.
  final String? refreshToken;

  /// Access token lifetime.
  final Duration expiresIn;

  /// Granted scope summary, when reported.
  final String? scope;

  /// Non-secret reference naming the issued credential.
  final KumweCredentialReference credentialReference;

  /// Credential family, when reported.
  final String? credentialFamily;

  /// Credential purpose, when reported.
  final String? purpose;

  /// Credential audience, when reported.
  final String? audience;

  /// Opaque subject reference, when reported.
  final String? subjectReference;

  /// Sign-in area binding, when reported.
  final KumweLoginArea? area;

  /// Account lifecycle state; pending renders the guest arrival page.
  final KumweAccountState? accountState;

  /// Site the credential is bound to.
  final String site;

  /// Organization binding, when reported.
  final String? organization;

  /// Workspace binding, when reported.
  final String? workspace;

  /// Authority generation bindings, when reported.
  final Map<String, String> authorityGenerations;

  /// Whether the credential can refresh without interaction.
  bool get refreshEligible => refreshToken != null;

  /// Builds the validated access token for the authorization provider.
  ///
  /// [issuedAt] anchors the expiry instant; inject a deterministic clock
  /// value in tests.
  KumweAccessToken toAccessToken({required DateTime issuedAt}) {
    return KumweAccessToken(
      token: BearerToken(accessToken),
      credential: credentialReference,
      boundSite: site,
      boundOrganization: organization,
      boundWorkspace: workspace,
      expiresAt: issuedAt.add(expiresIn),
      refreshEligible: refreshEligible,
      purpose: purpose,
      audience: audience,
      subjectReference: subjectReference,
      area: area,
      accountState: accountState,
      authorityGenerations: authorityGenerations,
    );
  }

  @override
  String toString() =>
      'KumweNativeTokenResponse(${credentialReference.value}, '
      'site: $site, <redacted>)';

  static final RegExp _generationKeyPattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]{0,63}$',
  );

  static final RegExp _generationValuePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$',
  );

  static String? _identifier(
    Map<String, Object?> json,
    String member, {
    bool required = false,
  }) {
    final value = json[member];
    if (value == null) {
      if (required) {
        throw FormatException('The token $member member is required.');
      }
      return null;
    }
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,190}$').hasMatch(value)) {
      throw FormatException(
        'The token $member member is a bounded identifier.',
      );
    }
    return value;
  }
}

/// An executable reader for the closed web-session handoff response.
///
/// The response carries one single-use, short-lived HTTPS URL that signs
/// the credential's subject into its bound area in an external browser.
/// The URL is secret material; this reader validates the *proposed* wire
/// shape (`CORE-AUTH-002`) and releases the URL only through a validated
/// [KumweWebSessionHandoff] bound to the expected deployment origin.
final class KumweNativeWebSessionResponse {
  /// Validates a web-session response document.
  factory KumweNativeWebSessionResponse.fromJson(Map<String, Object?> json) {
    final handoffUrl = json['handoff_url'];
    if (handoffUrl is! String ||
        handoffUrl.length > 320 ||
        !RegExp(r'^https://\S{1,300}$').hasMatch(handoffUrl)) {
      throw const FormatException(
        'Web-session responses carry a bounded HTTPS handoff URL.',
      );
    }
    // Uri.parse embeds its source in its FormatException, which would
    // put the secret URL into diagnostics; parse tentatively instead and
    // refuse with a redacted error.
    final parsedHandoff = Uri.tryParse(handoffUrl);
    if (parsedHandoff == null ||
        !parsedHandoff.isScheme('https') ||
        parsedHandoff.host.isEmpty) {
      throw const FormatException(
        'Web-session responses carry a bounded HTTPS handoff URL.',
      );
    }
    final expiresIn = json['expires_in'];
    if (expiresIn is! int ||
        expiresIn < KumweWebSessionHandoff.minTtlSeconds ||
        expiresIn > KumweWebSessionHandoff.maxTtlSeconds) {
      throw const FormatException(
        'Web-session lifetimes are between 10 and 300 seconds.',
      );
    }
    return KumweNativeWebSessionResponse._(
      handoffUrl: parsedHandoff,
      expiresIn: expiresIn,
    );
  }

  const KumweNativeWebSessionResponse._({
    required this.handoffUrl,
    required this.expiresIn,
  });

  /// Single-use handoff URL; secret material.
  final Uri handoffUrl;

  /// Seconds the unopened handoff stays redeemable.
  final int expiresIn;

  /// Builds the validated handoff, refusing a URL outside
  /// [expectedOrigin].
  KumweWebSessionHandoff toHandoff({required Uri expectedOrigin}) {
    return KumweWebSessionHandoff(
      handoffUrl: handoffUrl,
      expiresIn: expiresIn,
      expectedOrigin: expectedOrigin,
    );
  }

  @override
  String toString() =>
      'KumweNativeWebSessionResponse(expiresIn: ${expiresIn}s, '
      '<url redacted>)';
}
