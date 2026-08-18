# Changelog

## 0.1.0-dev.5

- Follow the core repository's rename from `kumwe/cms` to `kumwe/app`: every audited-core pin, evidence
  citation, schema constant and evidence pattern, documentation link and prose reference now names
  `kumwe/app`, with the touched proposals and control schemas revised accordingly. The audited commit and
  all observed behavior are unchanged — the rename is identity, not content. The `Kumwe CMS` literals in
  the discovery, liveness and readiness clients stay exactly as observed on the wire: the audited core
  still reports that product string, and the SDK tracks core's identity document, not its repository name.

## 0.1.0-dev.4

- Make the authentication link (the industry's magic link) the preferred native sign-in profile, per the
  product owner's decision recorded in ADR 0007: revision `0.2.0-proposal.1` of the native-authorization
  proposal adds the `authentication_link` profile and grant, the anonymous link-request resource, sign-in
  areas (`administrator`, `portal`) as first-class vocabulary, email/link/manual-code limits, and the
  guest-arrival semantics; the PKCE profile of ADR 0006 remains the supported alternative and its invariants
  carry over unchanged.
- Extend the token-response wire schema with the credential's bound `area` and the `account.state`
  (`active`/`pending`) that carries the guest arrival experience, and the discovery document with the
  deployment's advertised sign-in areas; add a pending-guest token-response example.
- Propose the single-use authenticated web-session handoff (`CORE-AUTH-002`) with its closed response schema
  and example, so a client can open the deployment's website already signed in without a token ever entering
  the browser; record the guest arrival and positioning lifecycle as `CORE-ACCOUNT-001` in the contract index.
- Implement the flow's client-side primitives without any endpoint behavior: `AuthenticationLinkProofKey`
  (S256, RFC 7636 test vector), `KumweAuthenticationLinkTicket` with single-use constant-time state
  verification and deep-link/manual completion, `KumweLoginArea`, `KumweAccountState`,
  `KumweWebSessionHandoff` with exact-origin validation, the non-secret `KumweAccountDirectory` roster port
  for Bitwarden-style multi-deployment account switching, and area/account-state metadata on
  `KumweAccessToken`.
- Extend the security model with authentication-link misuse cases (interception, expiry/reuse, enumeration,
  guest escape, handoff leakage) and widen the redaction rules to link codes, states, handoff URLs and email
  addresses.

## 0.1.0-dev.3

- Complete the problem-details registry against the audited source: the four dynamically constructed
  `business-record-idempotency-*` type URIs join the seed, bringing the observed set to 40 codes, and the
  business-record and custom-action mutation families now declare the refusal codes and windows those routes
  actually emit.
- Reconcile cross-contract bounds: token, refresh and scope lengths and the token-lifetime floor now agree
  between the native-authorization limits and the token-response wire schema, and authority-generation values
  are constrained to the separator-free identifier set everywhere they appear.
- Harden the Dart wiring from adversarial review: cache partitions can no longer collide through
  authority-generation separator injection; origins are validated as true scheme-host-port origins across the
  execution context, token requests and credential-store keys; bound sites and generation keys on access tokens
  are validated like their wire counterparts; record-version parsing never throws on oversized versions; strong
  entity tags match the audited core parser including the empty and obs-text forms; wire-object parsing throws
  `FormatException` consistently; and RFC-valid `Retry-After` values with leading zeros are honored.

## 0.1.0-dev.2

- Add the G1 contract-adoption package as validated machine proposals: stable problem-details registry seeded
  from the 36 observed `urn:kumwe:problem:` type URIs, PKCE-first native application authorization with a closed
  token response, pre-authentication native discovery document, per-family mutation replay/precondition
  semantics, and the uniform opaque-cursor collection envelope.
- Add exact-value types `KumweDecimal`, `KumweMoney` and `KumweQuantity` mirroring core's canonical string rules
  without binary floating point.
- Add mutation primitives: validated `IdempotencyKey` with a secure generator, strong `EntityTag` with `"vN"`
  record-version support, and conservative HTTP-semantics retry classification.
- Add the immutable execution-context model with validated site, organization/workspace and locale selection and
  an authority-complete cache partition identity.
- Add the application-facing `KumweAuthorizationProvider` and `KumweCredentialStore` ports with non-secret token
  metadata and an explicitly volatile in-memory test store.
- Record ADR 0006 (native authorization is PKCE-first through an external user agent) and the matching misuse
  cases in the security model.
- Refine the roadmap's M0–M1 adoption package into a requirement-to-proposal table and update status rows to
  `Proposed` where a validated draft now exists.

## 0.1.0-dev.1

- Add a Flutter-independent transport boundary and `package:http` adapter.
- Add site-bound bearer authentication and validated Kumwe request headers.
- Add RFC 9457 Problem Details parsing and typed API failures.
- Add immutable dynamic JSON values for extension-defined payloads.
- Add caller-specific OpenAPI contract metadata, conditional fetching, and caching.
- Add stable API discovery and health clients without speculative endpoint models.
- Add an executable OpenAPI contract validator and continuous integration gates.
- Establish Dart 3.8 as the initial language and toolchain floor; publication remains disabled pending release policy.
