# Core-facing requirements

This document is an integration backlog, not a claim that Kumwe core already exposes these contracts. The status is
derived from the audit of `kumwe/cms@4e5083b3fe43790605ae5c6c5bf8e392f9822efc`. Machine-readable counterparts are
in [`contracts/contract-index.proposal.json`](../contracts/contract-index.proposal.json).

## Audit summary

The checked-in OpenAPI 3.1 document contains 81 paths, 109 operations and 66 schemas. It is internally useful and
the generated-business family is detailed, but only 35 operations declare any response content. Seventy-four
operations have descriptions without response payload schemas. Nineteen POST/PUT/PATCH operations omit a request
body; several clearly require inputs, including user, role, token, trust-key and menu operations.

Core's roadmap independently identifies generated REST schemas, stable problem codes, semantic versioning,
compatibility windows and fixtures as outstanding machine-contract work.

## P0: required for a supported SDK baseline

### CORE-API-001 — complete invariant OpenAPI

Core MUST publish request, success, documented failure, header and security schemas for every operation admitted to
the SDK profile. Objects MUST declare whether unknown fields are allowed. Every operation MUST have a unique stable
operation ID and stable resource semantics.

Current state: **Missing/partial**. Route presence is broad; DTO coverage is not generation-grade.

### CORE-API-002 — stable Problem Details registry

Core MUST expose a finite stable `code` (or equivalently stable type URI) for each actionable failure, with declared
extensions such as field violations, actual/expected version and retry class. Human `detail` text is not a control
flow API.

Current state: **Missing; proposed here**. The shared `ProblemDetails` schema is open and does not enumerate
codes, although call sites already emit `urn:kumwe:problem:` type URIs. The registry grammar and an
audit-seeded code set are drafted in
[`contracts/problem-details-registry.proposal.json`](../contracts/problem-details-registry.proposal.json).

### CORE-AUTH-001 — native application authorization

Core MUST adopt a user-facing native application authorization flow for desktop and mobile hosts, preferably OAuth
2.1 authorization code with PKCE and an external user-agent, or a comparably reviewed device/session exchange. It
MUST define refresh, revocation, logout, redirect URI registration, scopes/capabilities and failure semantics.

Current state: **Missing; proposed here**. Only pre-issued bearer tokens are available to REST clients. The
PKCE-first profile, endpoint set, closed token response and misuse invariants are drafted in
[`contracts/native-authorization.proposal.json`](../contracts/native-authorization.proposal.json) under
[ADR 0006](decisions/0006-native-authorization-is-pkce-first.md).

### CORE-CTX-001 — authority and context discovery

An authenticated client MUST be able to discover its subject, credential purpose/audience, site, available
organization/workspace selections and the generation/version values needed for safe cache invalidation. Selecting a
context MUST be explicit and authorization checked.

Current state: **Partial; proposed here**. Tokens carry rich bindings, but no native bootstrap/context-switch
resource is exposed. A pre-authentication discovery document is drafted in
[`contracts/native-discovery.proposal.json`](../contracts/native-discovery.proposal.json); authenticated context
selection binds to the token exchange in the native-authorization proposal.

### CORE-MUTATION-001 — per-operation retry and concurrency contract

Every mutation MUST declare whether it requires idempotency, its replay and late-duplicate semantics, required
precondition form, retryable status codes and operation-status support. General HTTP, business-record and custom
action windows MUST not contradict one another under a shared header description.

Current state: **Partial/inconsistent; proposed here**. Per-family replay, late-duplicate, precondition and
status declarations grounded in the two observed ledgers are drafted in
[`contracts/mutation-semantics.proposal.json`](../contracts/mutation-semantics.proposal.json).

### CORE-SURFACE-001 — policy-filtered client-surface discovery

Core MUST adopt a bounded declarative manifest, filter it by current actor/context/policy, bind it to trusted runtime
and definition generations, and remove it on disable/trust loss. It MUST not execute provider code while serving
cached metadata. The proposal is described in [Extension client surfaces](extension-client-surfaces.md).

This requirement is for authenticated administrator and portal surfaces. Anonymous extension presentation, if
adopted, belongs to `CORE-PUBLIC-001` and must not inherit authenticated authority/context dependencies.

Current state: **Missing; proposed here**.

### CORE-LOCALIZATION-001 — locale-aware machine metadata

Core MUST either resolve metadata for an explicit accepted locale or expose bounded translation maps plus fallback
rules. Entity, field, view, action, navigation and validation wording require one coherent locale contract.

Current state: **Missing/partial**. Definition translation methods exist, but business discovery emits raw labels.

## P0 for administrator, portal or public-site parity profiles

| Requirement | Needed contract | Current state |
| --- | --- | --- |
| CORE-MEDIA-001 | Media list, metadata, upload, progress/resume policy, replacement/deletion and authorization | Missing |
| CORE-SECURITY-001 | Organizations, workspaces, memberships, row/field/action policy, SoD, approval and step-up administration | Missing |
| CORE-SESSION-001 | Account, session list/revoke, logout and selected membership context | Missing |
| CORE-APPROVAL-001 | Reviewed native remote step-up/approval decision protocol with action/context binding and replay protection | Missing; browser-session-only today |
| CORE-KIS-001 | KIS surface/workspace/navigation/presentation preference discovery | Missing |
| CORE-EXTENSION-001 | Safe extension installation boundary or explicit host/browser handoff; lifecycle status remains typed | Install absent by design |
| CORE-PUBLIC-001 | Anonymous headless pages/routes/navigation/media/theme-semantic contract | Missing |

Until these are adopted, the SDK MUST NOT advertise the corresponding parity profile.

## P1: scale and integration quality

### CORE-COLLECTION-001 — uniform bounded collections

Collections MUST define cursor semantics, page size bounds, sort/filter vocabulary, stable ordering and total/count
behavior. The content list's fixed 100-record cap without continuation is not sufficient for a full client. The
uniform envelope extending the observed business cursor contract is drafted in
[`contracts/collection-pagination.proposal.json`](../contracts/collection-pagination.proposal.json).

### CORE-DOCUMENT-001 — atomic aggregate documents

Core SHOULD expose its atomic header-plus-owned-lines command through a typed REST resource with idempotency,
optimistic concurrency, aggregate result/version and stable validation failures. A sequence of relation mutations is
not an equivalent transaction.

### CORE-BULK-001 — bounded bulk operations

Core SHOULD expose the existing bounded business bulk semantics through REST/OpenAPI with one operation status,
all-or-nothing definition, per-item evidence and a maximum selection.

### CORE-EVENTS-001 — durable client change feed

Core SHOULD provide a policy-filtered durable change feed with opaque cursor, tombstones, snapshot recovery,
retention and authority-change semantics. Internal outbox and integration consumers are not this contract.

### CORE-REALTIME-001 — notification hints

SSE/WebSocket/push MAY notify a client that a durable feed advanced. Delivery is a hint; correctness comes from the
feed. Subscription authentication, reauthorization and bounded payloads are required.

## Deferred profile: offline synchronization

### CORE-SYNC-001

An offline profile requires a durable delta pull, mutation push envelope, stable client operation identities,
partial acknowledgement, conflict documents, tombstones, attachments, clock semantics, authorization changes and
document-numbering decision. These are not implied by current idempotency support.

Current state: **Deferred**. Core explicitly leaves disconnected numbering as an open product decision.

## Requirements already useful

The SDK should preserve, not replace, these observed contracts:

- explicit bearer and `Kumwe-Site` binding;
- policy-filtered business discovery with non-enumerating denial;
- closed bounded business query grammar and opaque signed cursors;
- strong business-record ETags/If-Match;
- exact decimal, money and quantity wire values;
- deterministic caller-specific live OpenAPI with ETag and fail-closed 503;
- custom view/action command and result schemas;
- bounded reports, exports and operation status; and
- trusted extension/runtime generation and lifecycle admission.

The adoption process is defined in [Contract lifecycle](contract-lifecycle.md).
