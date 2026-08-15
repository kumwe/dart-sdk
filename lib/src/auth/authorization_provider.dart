import '../context/execution_context.dart';
import 'bearer_token_provider.dart';
import 'credential_reference.dart';

/// Why the SDK is asking its application for a token.
enum KumweTokenRequestReason {
  /// A session is being opened and no usable token is held.
  initial,

  /// The held token expired or was rejected once with an authentication
  /// failure; the provider may refresh silently if its flow allows it.
  refresh,

  /// A refreshed token was rejected again; only an interactive
  /// re-authentication decided by the application may follow.
  reauthentication,
}

/// One request from the SDK to its application-owned authorization provider.
final class KumweTokenRequest {
  /// Creates a validated token request.
  KumweTokenRequest({
    required this.origin,
    required this.selection,
    required this.reason,
    this.previousCredential,
  }) {
    if (origin.scheme != 'https' || origin.host.isEmpty) {
      throw ArgumentError.value(
        origin,
        'origin',
        'Token requests are bound to an HTTPS origin.',
      );
    }
    if (reason != KumweTokenRequestReason.initial &&
        previousCredential == null) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Refresh and re-authentication name the previous credential.',
      );
    }
  }

  /// Exact HTTPS origin the token will be used against.
  final Uri origin;

  /// Site, organization, workspace and locale the session is for.
  final KumweContextSelection selection;

  /// Why the token is needed now.
  final KumweTokenRequestReason reason;

  /// Credential the request replaces, when [reason] is not
  /// [KumweTokenRequestReason.initial].
  final KumweCredentialReference? previousCredential;
}

/// An access token beside the non-secret metadata needed to use it safely.
///
/// The SDK never parses the opaque token value to guess bindings; every
/// binding it enforces arrives here as explicit metadata from the provider.
final class KumweAccessToken {
  /// Creates a token with its validated metadata.
  KumweAccessToken({
    required this.token,
    required this.credential,
    required this.boundSite,
    this.boundOrganization,
    this.boundWorkspace,
    this.expiresAt,
    this.refreshEligible = false,
    this.purpose,
    this.audience,
    this.subjectReference,
    Map<String, String> authorityGenerations = const {},
  }) : authorityGenerations = Map.unmodifiable(authorityGenerations) {
    if (this.authorityGenerations.length > 16 ||
        this.authorityGenerations.entries.any(
          (entry) =>
              entry.key.isEmpty ||
              entry.key.length > 64 ||
              entry.value.isEmpty ||
              entry.value.length > 191,
        )) {
      throw ArgumentError(
        'Authority generations are a bounded map of up to 16 short keys '
        'with values of 1 to 191 characters.',
      );
    }
  }

  /// Opaque bearer credential presented on protected requests.
  final BearerToken token;

  /// Non-secret reference naming this credential.
  final KumweCredentialReference credential;

  /// Site the server bound the token to; requests for other sites fail
  /// locally instead of leaking the token across contexts.
  final String boundSite;

  /// Optional organization binding reported by the server.
  final String? boundOrganization;

  /// Optional workspace binding reported by the server.
  final String? boundWorkspace;

  /// Expiry instant when the provider knows it; `null` means unknown, not
  /// unlimited.
  final DateTime? expiresAt;

  /// Whether the provider can refresh this credential without interaction.
  final bool refreshEligible;

  /// Optional server-reported credential purpose.
  final String? purpose;

  /// Optional server-reported credential audience.
  final String? audience;

  /// Optional opaque reference to the authenticated subject.
  final String? subjectReference;

  /// Server-supplied authority generation values bound to this credential,
  /// such as policy generation or security epoch. Keys and values are opaque.
  final Map<String, String> authorityGenerations;

  @override
  String toString() =>
      'KumweAccessToken(credential: ${credential.value}, '
      'site: $boundSite, <redacted>)';
}

/// The application-owned seam that supplies and invalidates access tokens.
///
/// The provider owns every authorization interaction: browser hand-off,
/// refresh, secure persistence and user cancellation. The SDK receives an
/// opaque token with metadata and never a password, one-time code, recovery
/// code or session cookie.
abstract interface class KumweAuthorizationProvider {
  /// Returns a token satisfying [request], or throws the provider's own
  /// error when authorization is declined or cancelled.
  Future<KumweAccessToken> tokenFor(KumweTokenRequest request);

  /// Invalidates one credential after the server rejected or revoked it,
  /// releasing local secret material.
  Future<void> invalidate(KumweCredentialReference credential);
}
