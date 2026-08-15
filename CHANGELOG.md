# Changelog

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
