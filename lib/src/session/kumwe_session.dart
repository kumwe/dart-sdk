import 'dart:async';

import '../auth/authorization_provider.dart';
import '../auth/bearer_token_provider.dart';
import '../auth/credential_reference.dart';
import '../client/kumwe_client_options.dart';
import '../context/execution_context.dart';
import '../problem/api_exception.dart';

/// Lifecycle states of one authenticated session.
enum KumweSessionState {
  /// A usable token is held.
  active,

  /// The held token was rejected once; a silent refresh is permitted.
  refreshing,

  /// Refresh was exhausted; only interactive re-authentication may follow.
  reauthenticationRequired,

  /// The session was closed and its credential invalidated.
  signedOut,
}

/// One authenticated session against one deployment origin and context.
///
/// The session owns the token lifecycle discipline the contracts demand and
/// nothing else — the application-owned [KumweAuthorizationProvider] owns
/// every actual authorization interaction:
///
/// * one silent refresh per rejection, never a retry loop: the first
///   authentication failure of a credential invalidates it and asks the
///   provider to refresh; a failure of the *refreshed* credential escalates
///   to interactive re-authentication instead of hammering the server;
/// * single-flight refresh: concurrent callers awaiting a token during a
///   refresh share one provider call rather than racing rotations;
/// * binding checks: a provider-returned token bound to a different site,
///   organization or workspace than this session's selection is refused
///   before it can ever be attached to a request;
/// * proactive expiry: a token inside its expiry margin is refreshed
///   before use rather than spent on a guaranteed 401.
final class KumweSession implements BearerTokenProvider {
  /// Opens a session lazily; no token is requested until first use.
  factory KumweSession({
    required Uri origin,
    required KumweContextSelection selection,
    required KumweAuthorizationProvider provider,
    KumweClock? clock,
    Duration expiryMargin = const Duration(seconds: 30),
  }) {
    if (expiryMargin.isNegative || expiryMargin > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        expiryMargin,
        'expiryMargin',
        'Expiry margins run from zero to five minutes.',
      );
    }
    return KumweSession._(
      origin: KumweContextIdentifiers.normalizeOrigin(origin, 'origin'),
      selection: selection,
      provider: provider,
      clock: clock ?? DateTime.now,
      expiryMargin: expiryMargin,
    );
  }

  KumweSession._({
    required this.origin,
    required this.selection,
    required KumweAuthorizationProvider provider,
    required KumweClock clock,
    required Duration expiryMargin,
  }) : _provider = provider,
       _clock = clock,
       _expiryMargin = expiryMargin;

  /// Exact deployment origin this session speaks to.
  final Uri origin;

  /// Site, organization, workspace and locale this session is bound to.
  final KumweContextSelection selection;

  final KumweAuthorizationProvider _provider;
  final KumweClock _clock;
  final Duration _expiryMargin;

  KumweAccessToken? _token;
  KumweSessionState _state = KumweSessionState.active;
  Future<KumweAccessToken>? _inFlight;
  KumweCredentialReference? _bornFromRejection;
  KumweCredentialReference? _lastCredential;

  /// Current lifecycle state.
  KumweSessionState get state => _state;

  /// The held access token, when one is held and usable.
  KumweAccessToken? get accessToken => _token;

  /// Authority generations of the held token; empty without a token.
  Map<String, String> get authorityGenerations =>
      _token?.authorityGenerations ?? const {};

  /// Returns a usable bearer token, acquiring or refreshing as needed.
  ///
  /// Returns `null` once the session is signed out or awaiting interactive
  /// re-authentication, so a transport never sends a credential the
  /// session no longer trusts.
  @override
  Future<BearerToken?> token() async {
    final KumweAccessToken? access;
    try {
      access = await _usableAccessToken();
    } on KumweAuthenticationException {
      if (_state == KumweSessionState.signedOut) {
        return null;
      }
      rethrow;
    }
    return access?.token;
  }

  /// Returns the full access token, acquiring or refreshing as needed.
  Future<KumweAccessToken?> _usableAccessToken() async {
    if (_state == KumweSessionState.signedOut ||
        _state == KumweSessionState.reauthenticationRequired) {
      return null;
    }
    final held = _token;
    if (held != null && !_isExpiring(held)) {
      return held;
    }
    return _acquire(
      held == null && _state == KumweSessionState.active
          ? KumweTokenRequestReason.initial
          : KumweTokenRequestReason.refresh,
      previous: held?.credential,
    );
  }

  /// Reports that the server rejected [rejected] with an authentication
  /// failure (401), returning the replacement token to retry with — or
  /// `null` when the one permitted silent refresh is exhausted and only
  /// interactive re-authentication may follow.
  ///
  /// The rejected credential must be named so a *late* 401 — a response
  /// still traveling under a superseded credential while the session
  /// already recovered — can never invalidate the fresh credential: a
  /// rejection of anything but the held credential is answered with the
  /// currently usable token and touches nothing.
  ///
  /// The caller retries the original request at most once with the
  /// replacement. A rejection of a credential that was itself obtained in
  /// answer to a rejection ends silent recovery: the session escalates to
  /// interactive re-authentication rather than rotating credentials in a
  /// loop against a server that keeps refusing them.
  Future<KumweAccessToken?> handleAuthenticationFailure(
    KumweCredentialReference rejected,
  ) async {
    if (_state == KumweSessionState.signedOut) {
      return null;
    }
    final held = _token;
    if (held == null || held.credential != rejected) {
      // A stale rejection of a superseded credential; the session has
      // already moved on. Hand back whatever is currently usable.
      return _usableAccessToken();
    }
    await _provider.invalidate(held.credential);
    if (_state == KumweSessionState.signedOut) {
      // Signed out while the invalidation was in flight; stay closed.
      return null;
    }
    _token = null;
    if (held.credential == _bornFromRejection) {
      // The replacement credential was rejected too: stop refreshing.
      _state = KumweSessionState.reauthenticationRequired;
      return null;
    }
    _state = KumweSessionState.refreshing;
    try {
      final replacement = await _acquire(
        KumweTokenRequestReason.refresh,
        previous: held.credential,
      );
      _bornFromRejection = replacement.credential;
      return replacement;
    } on Object {
      if (_state != KumweSessionState.signedOut) {
        _state = KumweSessionState.reauthenticationRequired;
      }
      rethrow;
    }
  }

  /// Re-authenticates interactively through the provider after silent
  /// refresh was exhausted, restoring the session on success.
  Future<KumweAccessToken> reauthenticate() async {
    if (_state == KumweSessionState.signedOut) {
      throw StateError('A signed-out session cannot re-authenticate.');
    }
    final previous = _token?.credential ?? _lastCredential;
    _token = null;
    _bornFromRejection = null;
    final token = await _request(
      previous == null
          ? KumweTokenRequestReason.initial
          : KumweTokenRequestReason.reauthentication,
      previous: previous,
    );
    _adopt(token);
    return token;
  }

  /// Signs out: invalidates the held credential and closes the session.
  ///
  /// Local sign-out always completes; the provider is responsible for
  /// reporting — not blocking on — an unreachable server-side revocation.
  Future<void> signOut() async {
    final held = _token;
    _token = null;
    _state = KumweSessionState.signedOut;
    _inFlight = null;
    if (held != null) {
      await _provider.invalidate(held.credential);
    }
  }

  Future<KumweAccessToken> _acquire(
    KumweTokenRequestReason reason, {
    KumweCredentialReference? previous,
  }) {
    final running = _inFlight;
    if (running != null) {
      return running;
    }
    final flight = _request(reason, previous: previous)
        .then((token) async {
          if (_state == KumweSessionState.signedOut) {
            // The session closed while the provider was working; the
            // fresh credential must die unused rather than leak out live.
            await _provider.invalidate(token.credential);
            throw const KumweAuthenticationException(
              'The session was signed out during token acquisition.',
            );
          }
          _adopt(token);
          return token;
        })
        .whenComplete(() {
          _inFlight = null;
        });
    _inFlight = flight;
    return flight;
  }

  Future<KumweAccessToken> _request(
    KumweTokenRequestReason reason, {
    KumweCredentialReference? previous,
  }) {
    return _provider.tokenFor(
      KumweTokenRequest(
        origin: origin,
        selection: selection,
        reason: reason,
        previousCredential: previous,
      ),
    );
  }

  void _adopt(KumweAccessToken token) {
    if (token.boundSite != selection.site ||
        token.boundOrganization != selection.organization ||
        token.boundWorkspace != selection.workspace) {
      throw const KumweAuthenticationException(
        'The provider returned a token bound to a different context '
        'than this session.',
      );
    }
    if (_isExpiring(token)) {
      throw const KumweAuthenticationException(
        'The provider returned a token that is already expiring.',
      );
    }
    _token = token;
    _lastCredential = token.credential;
    if (_state != KumweSessionState.signedOut) {
      _state = KumweSessionState.active;
    }
  }

  bool _isExpiring(KumweAccessToken token) {
    final expiresAt = token.expiresAt;
    if (expiresAt == null) {
      return false;
    }
    return !_clock().add(_expiryMargin).isBefore(expiresAt);
  }

  @override
  String toString() =>
      'KumweSession(${selection.site}@${origin.host}, ${_state.name})';
}
