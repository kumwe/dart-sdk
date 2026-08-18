# Quality and conformance

## Quality strategy

The SDK is qualified at three levels:

1. **contract correctness** — schemas, generated code and runtime interpretation match adopted bytes;
2. **behavioral correctness** — requests, values, failures, retries and lifecycle outcomes match core; and
3. **profile parity** — an advertised application profile can complete the same authorized use cases.

Unit coverage alone cannot establish any of these.

## Required checks

| Check | Purpose |
| --- | --- |
| Formatting and analyzer at strictest practical settings | Maintain a predictable public Dart surface |
| Public API diff | Prevent accidental breaking exports/signatures |
| JSON/JSON Schema validation | Keep proposals and adopted runtime documents closed and valid |
| Deterministic generation | Prove pinned inputs produce identical source |
| Unit/property tests | Exact values, identifiers, codecs, cursors and value equality |
| Schema fuzz tests | Reject malformed/deep/wide/unknown runtime documents safely |
| Fake transport tests | Headers, redirects, cancellation, media types, limits and redaction |
| Released-core integration | Verify real routing, context, policy, versions and errors |
| Extension lifecycle conformance | Activate/upgrade/disable/trust-loss cache and surface behavior |
| Mutation/retry tests | Timeout ambiguity, same-key replay, changed-body conflict and stale ETag |
| Downstream host fixtures | Prove the public SDK values are sufficient for the separately owned client conformance suite |
| Dependency/license/secret scans | Supply-chain and accidental credential controls |
| Package consumer smoke test | Verify a clean downstream package can compile and use the public API |

## Contract fixtures

Core and SDK share fixture identities, not mutable copies. A fixture bundle includes:

- canonical request/success/problem examples per operation;
- unknown-field and bound violations;
- capability/context discovery;
- exact values and Unicode edge cases;
- business definition/view/action schemas;
- client-surface manifests for lifecycle states; and
- expected compatibility classification.

The SDK records the core release and bundle digest. Local proposal examples are development fixtures only.

When the adoption-package proposals become adopted contracts, their fixture bundles must additionally cover:

- every registry problem code with its declared statuses, retry class and typed extensions, plus an
  unknown-code instance handled as its status class;
- the authorization flow's misuse cases from [Security](security.md#native-authorization-misuse-cases),
  including link interception/forwarding, link expiry and reuse, address-enumeration probing, guest-capability
  escape, state mismatch, code replay, verifier mismatch, method downgrade, rotated-refresh reuse and
  web-session handoff misuse;
- discovery documents at both edges of the client-contract window and one outside it;
- per-family idempotency declarations exercised against replay, late-duplicate and refusal behavior for the
  general, business-record and custom-action ledgers; and
- cursor iteration across policy revocation, tampered-cursor refusal and page-size ceiling refusal.

## OpenAPI generation gate

Before an operation enters the invariant client:

1. path parameters are declared and required;
2. all request media types/bodies are typed;
3. every advertised success response has content/header schemas or is explicitly bodyless;
4. all actionable failures reference stable Problem Details contracts;
5. authentication and site/context binding are explicit;
6. concurrency/idempotency semantics are represented;
7. operation IDs are unique and compatibility-classified; and
8. references and supported JSON Schema features validate.

An operation that fails remains unavailable; the generator does not synthesize `Map<String, dynamic>` DTOs to
increase route counts.

## Runtime schema conformance

The client-surface/runtime validator is tested for:

- maximum bytes, nodes, depth, properties and array items;
- unknown keys and vocabulary versions;
- owner namespace escape and duplicate IDs;
- dangling screen/navigation/definition/view/report references;
- incompatible widget and JSON Schema value family;
- malformed locale tags and fallback;
- lifecycle generation/checksum mismatch;
- policy omission and mixed-context documents;
- executable-looking unknown properties; and
- deterministic canonical digest where adopted.

Valid manifests are decoded into immutable wire-level model snapshots. Flutter semantic and accessibility evidence
belongs to the separate client conformance suite.

## Cross-surface parity

For each advertised use case, fixtures compare authorized outcomes rather than presentation markup:

| Concern | Compared evidence |
| --- | --- |
| Discovery | Same visible definitions, fields, views, actions and relations |
| Read/query | Same exact values, ordering, cursors, omissions and aggregates |
| Mutation | Same authoritative version, audit actor, replay and failure code |
| Concurrency | Same stale-write refusal and current version evidence |
| Approval | Same adopted native remote result; a browser-only operation is excluded from the advertised profile and fails this parity row |
| Lifecycle | Same disappearance on disable/trust loss and return on reactivation |
| Localization | Same selected labels/fallback contract |
| Reports/exports | Same policy-filtered query identity and artifact authorization |

The server UI need not have the same pixels as Flutter. “One-to-one” means equivalent authorized capability and
outcome for the declared profile, plus documented presentation differences.

## Security and privacy tests

The abuse cases in [Security](security.md) are release-blocking for relevant features. Test fixtures place sentinel
values in tokens, secret fields and payloads, then assert they are absent from logs, exceptions, analytics hooks,
cache metadata and string representations.

Fuzzing targets JSON decoding, schema validation, exact decimal parsing, locale/identifier normalization, cursor
opacity, Problem Details extensions and redirect/origin handling.

## Performance and resource budgets

Budgets are established before beta for:

- maximum response and decompressed bytes;
- runtime schema parse/validation memory and duration;
- manifest validation and wire-level model construction;
- large bounded business pages and includes;
- cache size/eviction;
- export streaming memory; and
- downstream host fixture construction for contract maxima.

Tests use deterministic operation/memory bounds where possible rather than fragile wall-clock thresholds. A valid
maximum-size manifest must not make the UI unresponsive; the host may paginate/lazily construct semantic sections.

## Platform matrix

The stable package declares supported Dart versions and runs pure-Dart transport/model tests independently of
Flutter. The separate client owns Flutter versions and Linux, macOS, Windows, Android, and iOS qualification,
including secure storage, external authorization redirects, proxy/certificate behavior, downloads,
keyboard/accessibility, and application lifecycle.

## Evidence record

Each release report records:

- source and contract digests;
- exact commands/tool versions;
- supported core/platform matrix;
- passed, failed, skipped and not-applicable gates separately;
- fixture/artifact locations and checksums;
- profile conformance result; and
- bounded residual risks with owner.

No “green” summary may hide a skipped required check.
