import '../context/execution_context.dart';

/// A single-use, short-lived URL that signs the current subject into its
/// bound area in an external browser.
///
/// The handoff lets browser-only work continue without the client ever
/// collecting a password: the server mints the URL against an authenticated
/// native credential, the client opens it in the system browser, and the
/// browser establishes its own session there. The URL is secret material —
/// it is held only long enough to be opened, and it never enters logs,
/// diagnostics or persistence. Native bearer tokens never enter the browser.
final class KumweWebSessionHandoff {
  /// Validates a handoff the server minted for [expectedOrigin].
  ///
  /// The URL must be HTTPS at exactly the expected deployment origin; a
  /// handoff pointing anywhere else is refused rather than opened, so a
  /// compromised response can never steer the browser to a foreign host.
  /// [expiresIn] mirrors the wire bounds: 10 to 300 seconds.
  factory KumweWebSessionHandoff({
    required Uri handoffUrl,
    required int expiresIn,
    required Uri expectedOrigin,
  }) {
    final origin = KumweContextIdentifiers.normalizeOrigin(
      expectedOrigin,
      'expectedOrigin',
    );
    if (handoffUrl.scheme != 'https' ||
        handoffUrl.host != origin.host ||
        (handoffUrl.hasPort ? handoffUrl.port : 443) !=
            (origin.hasPort ? origin.port : 443) ||
        handoffUrl.userInfo.isNotEmpty ||
        handoffUrl.toString().length > maxUrlLength) {
      throw ArgumentError(
        'Handoff URLs are bounded HTTPS URLs at exactly the expected '
        'deployment origin.',
      );
    }
    if (expiresIn < minTtlSeconds || expiresIn > maxTtlSeconds) {
      throw ArgumentError.value(
        expiresIn,
        'expiresIn',
        'Handoff lifetimes are $minTtlSeconds to $maxTtlSeconds seconds.',
      );
    }
    return KumweWebSessionHandoff._(
      handoffUrl: handoffUrl,
      expiresIn: expiresIn,
      origin: origin,
    );
  }

  const KumweWebSessionHandoff._({
    required this.handoffUrl,
    required this.expiresIn,
    required this.origin,
  });

  /// Shortest lifetime the wire contract admits.
  static const int minTtlSeconds = 10;

  /// Longest lifetime the wire contract admits.
  static const int maxTtlSeconds = 300;

  /// Bound on the handoff URL's total length.
  static const int maxUrlLength = 320;

  /// Single-use HTTPS URL to open in the external browser; secret material.
  final Uri handoffUrl;

  /// Seconds the unopened handoff stays redeemable.
  final int expiresIn;

  /// Validated deployment origin the handoff belongs to.
  final Uri origin;

  @override
  String toString() =>
      'KumweWebSessionHandoff(origin: $origin, expiresIn: $expiresIn, '
      '<url redacted>)';
}
