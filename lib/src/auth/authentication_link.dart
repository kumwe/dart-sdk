import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../context/execution_context.dart';
import 'login_area.dart';

/// Why an authentication-link flow step was refused.
enum AuthenticationLinkFailureReason {
  /// The return carried a state value that does not match the ticket.
  stateMismatch,

  /// The return URI or manual entry did not carry a usable code and state.
  malformedReturn,

  /// The ticket was already completed; codes and states are single-use.
  alreadyCompleted,
}

/// A refused authentication-link flow step.
///
/// The failure names its reason without echoing codes, states or verifier
/// material, so it is safe to log.
final class AuthenticationLinkFailure implements Exception {
  /// Creates a failure for [reason].
  const AuthenticationLinkFailure(this.reason);

  /// Why the step was refused.
  final AuthenticationLinkFailureReason reason;

  @override
  String toString() => 'AuthenticationLinkFailure(${reason.name})';
}

/// An S256 proof key binding an authentication-link request to its client.
///
/// The verifier is generated inside the requesting client and never leaves
/// it; only the derived challenge travels with the link request. Redeeming
/// the emailed link code requires this verifier, so an intercepted or
/// forwarded email cannot complete sign-in anywhere else.
final class AuthenticationLinkProofKey {
  /// Validates an application-supplied verifier and derives its challenge.
  factory AuthenticationLinkProofKey(String verifier) {
    if (!_verifierPattern.hasMatch(verifier)) {
      throw ArgumentError(
        'Proof-key verifiers need 43 to 128 characters from the unreserved '
        'set.',
      );
    }
    return AuthenticationLinkProofKey._(
      verifier,
      base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', ''),
    );
  }

  /// Generates a fresh high-entropy proof key from a cryptographic source.
  factory AuthenticationLinkProofKey.generate() {
    final characters = List<String>.generate(
      64,
      (_) => _unreserved[_random.nextInt(_unreserved.length)],
    );
    return AuthenticationLinkProofKey(characters.join());
  }

  const AuthenticationLinkProofKey._(this.verifier, this.challenge);

  /// The only challenge method the contract offers; `plain` never appears.
  static const String challengeMethod = 'S256';

  /// Secret verifier redeemed with the link code; never sent with the
  /// request and never logged.
  final String verifier;

  /// Non-secret S256 challenge sent with the link request.
  final String challenge;

  @override
  String toString() => 'AuthenticationLinkProofKey(<redacted>)';

  static const String _unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static final RegExp _verifierPattern = RegExp(r'^[A-Za-z0-9\-._~]{43,128}$');

  static final Random _random = Random.secure();
}

/// The non-secret body of one authentication-link request.
///
/// The client sends the address, the target area and the S256 challenge to
/// the deployment origin; the server answers identically whether or not the
/// address resolves, and emails a single-use link either way. The email
/// address is an identifier, not a credential: the rule that the SDK never
/// collects passwords or second factors is unchanged.
final class KumweAuthenticationLinkRequest {
  /// Creates a validated link request.
  factory KumweAuthenticationLinkRequest({
    required Uri origin,
    required String emailAddress,
    required KumweLoginArea area,
    required String codeChallenge,
    String? locale,
  }) {
    return KumweAuthenticationLinkRequest._(
      origin: KumweContextIdentifiers.normalizeOrigin(origin, 'origin'),
      emailAddress: _normalizeEmailAddress(emailAddress),
      area: area,
      codeChallenge: codeChallenge,
      locale: locale == null
          ? null
          : KumweContextIdentifiers.normalizeLocale(locale),
    );
  }

  const KumweAuthenticationLinkRequest._({
    required this.origin,
    required this.emailAddress,
    required this.area,
    required this.codeChallenge,
    required this.locale,
  });

  /// Exact HTTPS deployment origin the link is requested from.
  final Uri origin;

  /// Normalized address the link is emailed to; personal data kept out of
  /// diagnostics.
  final String emailAddress;

  /// Sign-in area the issued credential will be bound to.
  final KumweLoginArea area;

  /// Non-secret S256 challenge binding redemption to the requesting client.
  final String codeChallenge;

  /// Optional bounded IETF language tag for the email's language.
  final String? locale;

  @override
  String toString() =>
      'KumweAuthenticationLinkRequest(origin: $origin, '
      'area: ${area.wireValue}, <address redacted>)';

  /// The audited wire limit on email address length.
  static const int maxEmailAddressLength = 254;

  static String _normalizeEmailAddress(String value) {
    final trimmed = value.trim();
    final at = trimmed.indexOf('@');
    if (trimmed.isEmpty ||
        trimmed.length > maxEmailAddressLength ||
        at < 1 ||
        at != trimmed.lastIndexOf('@') ||
        at == trimmed.length - 1 ||
        trimmed.contains(RegExp(r'[\s\x00-\x1f\x7f]'))) {
      throw ArgumentError(
        'Email addresses need one local part and one domain, at most '
        '$maxEmailAddressLength characters, without whitespace or control '
        'characters.',
      );
    }
    final local = trimmed.substring(0, at);
    final domain = trimmed.substring(at + 1).toLowerCase();
    return '$local@$domain';
  }
}

/// The code-and-verifier pair an application redeems at the token endpoint.
///
/// This is the terminal value of the client-side flow: the application's
/// authorization provider exchanges it — with the adopted
/// `authentication_link` grant — for the closed token response. Code and
/// verifier are single-use.
final class KumweAuthenticationLinkGrant {
  const KumweAuthenticationLinkGrant._({
    required this.origin,
    required this.area,
    required this.code,
    required this.codeVerifier,
  });

  /// Exact HTTPS deployment origin the grant may be redeemed at.
  final Uri origin;

  /// Sign-in area the resulting credential will be bound to.
  final KumweLoginArea area;

  /// Single-use link code carried by the emailed link or typed manually.
  final String code;

  /// Secret proof-key verifier that never left the requesting client.
  final String codeVerifier;

  @override
  String toString() =>
      'KumweAuthenticationLinkGrant(origin: $origin, '
      'area: ${area.wireValue}, <redacted>)';
}

/// One pending authentication-link sign-in held by the requesting client.
///
/// The ticket owns the flow's secret state: the proof-key verifier and the
/// opaque state value the deep-link return must echo. It is single-use — one
/// successful completion consumes it — and it never performs any network
/// interaction itself: the application sends [request] and redeems the
/// resulting [KumweAuthenticationLinkGrant] through its authorization
/// provider once core adopts the contract.
final class KumweAuthenticationLinkTicket {
  /// Opens a ticket for [origin], [emailAddress] and [area].
  ///
  /// A fresh proof key and state are generated from a cryptographic source
  /// unless supplied, which only tests should do.
  factory KumweAuthenticationLinkTicket.issue({
    required Uri origin,
    required String emailAddress,
    required KumweLoginArea area,
    String? locale,
    AuthenticationLinkProofKey? proofKey,
    String? state,
  }) {
    final key = proofKey ?? AuthenticationLinkProofKey.generate();
    final stateValue = state ?? _generateState();
    if (!_statePattern.hasMatch(stateValue)) {
      throw ArgumentError(
        'States need 43 to 128 characters from the unreserved set.',
      );
    }
    return KumweAuthenticationLinkTicket._(
      request: KumweAuthenticationLinkRequest(
        origin: origin,
        emailAddress: emailAddress,
        area: area,
        codeChallenge: key.challenge,
        locale: locale,
      ),
      proofKey: key,
      state: stateValue,
    );
  }

  KumweAuthenticationLinkTicket._({
    required this.request,
    required AuthenticationLinkProofKey proofKey,
    required this.state,
  }) : _proofKey = proofKey;

  /// Non-secret request body the application sends to the deployment.
  final KumweAuthenticationLinkRequest request;

  /// Opaque single-use value the sign-in return must echo exactly.
  final String state;

  final AuthenticationLinkProofKey _proofKey;

  bool _completed = false;

  /// Whether this ticket has produced its grant; a ticket completes once.
  bool get isCompleted => _completed;

  /// Completes the flow from an explicit code and returned state.
  ///
  /// The state comparison is constant-time and the ticket is consumed on
  /// success. The code may come from the deep-link return or be typed from
  /// the link landing page's manual completion code on another device.
  KumweAuthenticationLinkGrant complete({
    required String code,
    required String returnedState,
  }) {
    if (_completed) {
      throw const AuthenticationLinkFailure(
        AuthenticationLinkFailureReason.alreadyCompleted,
      );
    }
    final trimmed = code.trim();
    if (!_codePattern.hasMatch(trimmed)) {
      throw const AuthenticationLinkFailure(
        AuthenticationLinkFailureReason.malformedReturn,
      );
    }
    if (!_constantTimeEquals(returnedState, state)) {
      throw const AuthenticationLinkFailure(
        AuthenticationLinkFailureReason.stateMismatch,
      );
    }
    _completed = true;
    return KumweAuthenticationLinkGrant._(
      origin: request.origin,
      area: request.area,
      code: trimmed,
      codeVerifier: _proofKey.verifier,
    );
  }

  /// Completes the flow from the deep-link return URI.
  ///
  /// Only the `code` and `state` query parameters are read; an unsolicited
  /// or replayed return fails on the state comparison, and a return without
  /// both parameters is refused as malformed.
  KumweAuthenticationLinkGrant completeFromReturnUri(Uri returnUri) {
    final code = returnUri.queryParameters['code'];
    final returnedState = returnUri.queryParameters['state'];
    if (code == null || returnedState == null) {
      throw const AuthenticationLinkFailure(
        AuthenticationLinkFailureReason.malformedReturn,
      );
    }
    return complete(code: code, returnedState: returnedState);
  }

  @override
  String toString() =>
      'KumweAuthenticationLinkTicket(origin: ${request.origin}, '
      'area: ${request.area.wireValue}, completed: $_completed, <redacted>)';

  static String _generateState() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var difference = leftBytes.length ^ rightBytes.length;
    final length = leftBytes.length < rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var index = 0; index < length; index++) {
      difference |= leftBytes[index] ^ rightBytes[index];
    }
    return difference == 0;
  }

  static final RegExp _codePattern = RegExp(r'^[A-Za-z0-9\-._~]{8,512}$');

  static final RegExp _statePattern = RegExp(r'^[A-Za-z0-9\-._~]{43,128}$');

  static final Random _random = Random.secure();
}
