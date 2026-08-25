# Changelog

## 0.1.0-dev.6

The runtime wave: an executable, audit-grounded runtime foundation built from a fresh read-only audit of the
pinned core (`kumwe/app@4e5083b3fe43790605ae5c6c5bf8e392f9822efc`), with every wire shape, bound and header
below traced to serializing core source. Nothing here invents endpoint behavior: business routes are observed
core behavior; native authorization documents are read by proposal-scoped executable consumers.

- Add the sealed result kernel: `KumweResult` with `KumweValueResult`, `KumweProblemResult` and
  `KumweUnsupportedResult`, plus `KumweResponseMetadata` extracting status, correlation, entity tag and the
  replay marker. Expected API failures are data; only programmer errors and protocol violations throw.
- Add `KumweProblemRegistry`, an executable reader for the problem-details registry proposal, and
  `KumweProblem` built through it: retry classes come from declared registry data, only registry-declared
  extensions cross the boundary, an unregistered code is classified by HTTP status alone, and the
  `Retry-After` header outranks a body copy. Problem diagnostics never include detail text.
- Add `KumweCanonicalJson`: keys ordered by UTF-16 code units, a fixed escape vocabulary, refused binary
  floating-point (exact values are strings on this wire), and a SHA-256 digest used for idempotency binding.
- Add honest collection primitives: `KumweCursor` (opaque, bounded to the observed 65536-byte core cursor
  cap, redacted from diagnostics) and `KumwePage` (immutable items, real continuation, no invented totals).
- Add the mutation engine. `KumweMutationSemantics` reads the per-family mutation-semantics proposal —
  replay/retention windows, lease, late-duplicate policy, precondition form and refusal codes per family —
  so retry policy is declared data. `KumweMutationIntent` canonicalizes a body exactly once and freezes its
  bytes, digest, idempotency key and optional strong precondition, so a changed body can never travel under
  an old key. `KumweMutationOutcome` classifies applied/replayed/refused, and a transport failure after send
  becomes an *ambiguous* outcome that keeps the intent alive: the SDK never reports "not applied" without
  server evidence and never mints a fresh key because a request timed out.
- Add executable native wire readers proving the proposed authorization documents as working consumers:
  `KumweNativeDiscoveryDocument` (installation identity, exact HTTPS origins, base path and Kumwe-Site rule
  pins, client-contract window, advertised profiles and sign-in areas, pre-auth limits),
  `KumweNativeTokenResponse` (Bearer-only, bounded lifetimes, credential/area/account-state metadata,
  authority generations, redacted diagnostics, released to exactly one `KumweAccessToken`),
  `KumweNativeWebSessionResponse` (single-use HTTPS handoff URL, bounded TTL, origin-bound release, URL
  never in diagnostics) and the bounded `KumweContractVersion`.
- Model the observed generated business surface from the audit. `KumweBusinessDefinition` and
  `KumweBusinessCatalog` read the policy-filtered definition documents: the closed 25-identifier `core.*`
  field type vocabulary plus namespaced extension types, field uses and schema fragments, view kinds,
  custom contracts, actions with transitions, six relationship kinds, workflow declarations, and the
  omission discipline — a denied member is absent, never annotated, and an empty catalog is a valid
  grant-free document.
- Add the budget-enforced `KumweRecordQuery` filter AST: comparison/text/set/null/boolean/relation nodes,
  sorts, search, projection and aggregates, refusing at the call site everything the server would refuse on
  the wire — page size 1..200, ≤5 unique-field sorts, filter depth ≤8, ≤64 operations, ≤2 relation hops,
  set 1..100, text 1..512, term 1..256, ≤64 fields, ≤4 includes, ≤16 unique-alias aggregates, count without
  a field, exact values only (a `double` never enters the tree).
- Read the record envelopes: `KumweBusinessRecord` (stored null and withheld value stay distinguishable),
  relation records, `KumweRecordPageDocument` (items, opaque continuation, exact-decimal aggregates),
  `KumweRecordMutationDocument` (closed operation vocabulary, replay flag, custom action result) and
  `KumweRecordHistoryDocument` (version continuation that must be internally consistent).
- Read the approval inspection surface (`KumweBusinessApproval`, inbox, votes; decisions stay in the
  browser step-up by core design) and the caller-bound `KumweOperationStatusDocument`, where a served
  status proves the ambiguous mutation committed.
- Add `KumweBusinessApi`: a typed transport speaking every observed `/api/v1/business` route with the exact
  observed header discipline — bearer plus `Kumwe-Site` everywhere, `Idempotency-Key` on every mutation,
  strong `"vN"` `If-Match` where the record ledger demands one, none on search. It cross-checks the replay
  header against the envelope and the response entity tag against the envelope version, returns
  non-enumerating problems as data, and turns a mid-mutation transport failure into an ambiguous outcome.
- Add `KumweSession`: one authenticated session per origin and context selection behind the
  application-owned authorization provider, with single-flight acquisition, proactive expiry, context
  binding checks, and the 401-once discipline — one silent refresh per rejection, escalation to interactive
  re-authentication when a rejection-born credential is rejected again, and local sign-out that always
  completes.
- Add `KumweAuthorityPartition` and `KumweRuntimeCache`: a disposable, online-first cache whose partitions
  digest origin, site, credential, organization, workspace and every authority generation, so any authority
  movement drops the caller's whole cached view and two contexts can never collide.
- Add the first cross-module abuse suite covering origin confinement, organization/workspace cache
  collision, hostile deeply nested and oversized documents, Unicode-confusable identifiers, decimal
  exponent/overflow spellings, changed-body key reuse, ambiguous-timeout settlement through the operation
  ledger, stale-precondition terminal refusal and sentinel-secret diagnostics sweeps.
- Documentation: `client-api.md` now separates what is implemented from the adoption-gated target shape
  using the real type names; `status.md` and `roadmap.md` record the runtime wave against their gates.

## 0.1.0-dev.5

- Follow the core repository's rename from `kumwe/cms` to `kumwe/app`: every audited-core pin, evidence
  citation, schema constant and evidence pattern, documentation link and prose reference now names
  `kumwe/app`, with the touched proposals and control schemas revised accordingly. The audited commit and
  all observed behavior are unchanged — the rename is identity, not content. The `Kumwe CMS` literals in
  the discovery and liveness clients stay exactly as observed on the wire: the audited core still reports
  that product string, and the SDK tracks core's identity document, not its repository name. Core records
  the eventual outward-identity change as `V2-DOC-002`; the roadmap now carries the SDK half of that
  coupling, because both parsers reject an unrecognized product value.
- Restore `test/auth/authentication_link_test.dart` to text: the control-character rejection case carried a
  raw NUL byte, which made git classify the whole file as binary and hid its diff and blame. The escape
  `\u0000` builds the identical Dart string, so the assertion is unchanged.
- Add `ClientSurfaceInterpreter`, an executable reader for the proposed extension client-surface grammar. It
  validates the closed manifest schema again as defense in depth and exposes immutable typed models.
- Scope failure deliberately: a malformed envelope refuses the whole manifest, while a surface that cannot be
  fully understood is refused alone so the remaining surfaces stay usable. Required vocabulary outside its closed
  set fails its surface closed; an optional presentation hint outside its set is omitted with a notice, and the
  notices of a refused surface are withdrawn with it.
- Enforce reference integrity, per-kind screen shape, identifier uniqueness, closed objects and every declared
  bound, matching the manifest schema rather than trusting the server to have checked.
- Enforce owner namespacing as defense in depth: a manifest, surface, screen or navigation identifier outside the
  owning package's namespace is refused, so a contribution cannot present itself under another extension's
  identity even if core admission were bypassed.
- Add `LocalizedText` with case-insensitive language-tag fallback for bounded manifest translations.
- Prove the grammar against the shipped proposal examples: both interpret with zero rejections and zero notices.
- Refuse a member present carrying an explicit `null`. The grammar declares no nullable member, and reading a
  null as an omission defeated every per-kind prohibition: a report screen could declare `definition: null` and
  be admitted as well formed. Presence, not value, now decides a forbidden member.
- Refuse an optional presentation hint carrying non-text. Forgiveness is for a word from a later contract
  revision, not for arbitrary JSON, which the closed schema rejects outright.
- Measure string length in Unicode code points rather than UTF-16 units, so a label in a non-BMP script is no
  longer refused at roughly half its declared bound.
- Accept an integer written with a fractional zero, which JSON Schema counts as an integer.
- Bound translation language tags at their declared 35 characters; the pattern alone allowed unbounded subtag
  repetition, admitting multi-megabyte keys.
- Add `interpretJson`, which applies the contract's encoded-byte bound to the source before parsing it, where a
  limit on an already-parsed document would come too late.

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
