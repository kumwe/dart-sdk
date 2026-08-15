# ADR 0006: native authorization is PKCE-first through an external user agent

- Status: Accepted
- Date: 2026-08-15

## Context

The audited core issues bearer tokens only through the `users.manage` REST route, the administrator browser and
the `token:create` CLI, so a native application cannot bootstrap its own user credential. `CORE-AUTH-001` requires
a reviewed native flow, and [ADR 0004](0004-sdk-never-collects-user-credentials.md) forbids the SDK from ever
collecting credentials itself. The proposal work in
[`contracts/native-authorization.proposal.json`](../../contracts/native-authorization.proposal.json) had to commit
to one preferred profile so core review starts from a concrete design rather than a menu.

## Decision

The proposed native authorization profile is OAuth 2.1 authorization code with PKCE (`S256` only) through an
external user agent, with rotating refresh tokens, revocation and logout resources, and a closed token response
that reports the credential's site, context and authority-generation bindings explicitly. Redirect URIs are exact
loopback or private-use-scheme registrations. The pre-issued bearer path stays supported for controlled
integrations and development, and is never presented as the production user sign-in.

The SDK consumes whichever descendant of this proposal core adopts; it implements no authorization endpoint
behavior before adoption. If core selects device authorization instead, the proposal is revised — the invariants
(external user agent, phishing-resistant origin display, single-use proofs, downgrade refusal, secure storage,
atomic rotation) carry over unchanged.

## Consequences

- Core review of `CORE-AUTH-001` starts from one concrete endpoint set, token response shape and error vocabulary.
- The SDK's `KumweAuthorizationProvider` port and credential-store port can stabilize now, because every candidate
  profile terminates in an opaque token plus non-secret metadata.
- An embedded WebView or in-application credential form remains rejected regardless of profile choice.
- High-impact step-up stays inside core's protected browser UI and outside this profile, per ADR 0004.

## Rejected alternatives

- Embedded credential collection: rejected outright; recorded in the proposal as a rejected profile.
- Device authorization as the preferred profile: acceptable substitute if core decides so, but weaker default
  ergonomics on desktop and no advantage where a system browser exists.
- Proposing token issuance through the existing `users.manage` token route: keeps the administrator in the loop
  for every credential and is not a user sign-in experience.
