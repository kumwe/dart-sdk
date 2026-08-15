# Security model

## Trust boundaries

| Boundary | Trusted for | Not trusted for |
| --- | --- | --- |
| Kumwe core release artifact | Adopted contract bytes and version metadata | Runtime authorization for a particular actor |
| HTTPS Kumwe deployment | Authenticated responses after TLS/origin validation | Undeclared schema extensions or redirects to another origin |
| Access token | Opaque credential presented to its bound origin/context | Client-side capability proof or decoded claims |
| Runtime business catalog | Current policy-filtered metadata for its generation | Executable code, HTML or authority beyond the server result |
| Extension client manifest | Bounded semantic navigation/screen declarations after core admission | Dart/JS/WASM execution, arbitrary URLs, templates or credentials |
| Flutter host application | User interaction and selected platform adapters | Relaxing server validation or context binding |
| Local cache | Performance for non-secret context-bound data | Source of truth, approval proof or offline synchronization |

## Security invariants

1. Tokens are sent only to the configured HTTPS origin and never forwarded across an origin-changing redirect.
2. Exactly one canonical site context accompanies each authenticated request.
3. Organization/workspace context is obtained from adopted server authority, not user-edited strings.
4. Extension data cannot cause dynamic code loading or arbitrary network requests.
5. Unknown required schema vocabulary fails closed.
6. Server denial/omission is preserved; the client does not probe for hidden definitions, fields or records.
7. Exact values never transit binary floating point.
8. A mutation retry reuses the same key and canonical bytes; no automatic new intent is created after ambiguity.
9. Strong entity versions are retained and supplied when the contract requires them.
10. Sensitive values, tokens and write-only fields are excluded from logs, diagnostics, analytics and ordinary cache.

## Threats and controls

| Threat | Required control |
| --- | --- |
| Token theft from disk | Application-selected OS secure storage, short lifetimes, revocation and no plain preferences |
| Token sent to malicious host | Immutable approved origin, HTTPS, strict redirect policy, no manifest URLs |
| Site/context confusion | Typed immutable context and cache/request binding |
| Privilege change with stale UI | Generation-aware cache invalidation; server reauthorizes every operation |
| Hidden-field inference | Render/query only disclosed handles; preserve non-enumerating errors |
| Extension client-code injection | Closed declarative grammar; static scan for executable keys; no dynamic library loading |
| JSON/schema resource exhaustion | Byte, depth, node, map, array and string bounds before model construction |
| Rich-text/script injection | Treat manifest labels as text; sanitize/render content only under an adopted content policy |
| Spreadsheet formula injection | Use core's safe export artifact; do not reconstruct CSV from record values by default |
| Replay/duplicate mutation | Stable idempotency key, canonical body digest and terminal-result tracking |
| Lost update | Strong ETag/If-Match and explicit conflict result |
| Retry storm | Bounded exponential backoff, jitter, `Retry-After`, circuit/attempt budget |
| Sensitive error leakage | Stable code plus redacted detail; correlation ID for operator lookup |
| Cache cross-user disclosure | Authority-complete cache key and purge on session/context change |
| Downgrade to older contract | Minimum generation policy and immutable release digest |
| Supply-chain substitution | Reproducible generation, package checksums, signed/provenance artifacts where supported |

## Origin and TLS policy

- Production origins use `https`; insecure HTTP is rejected outside an explicitly compiled development policy.
- Userinfo, fragments and ambiguous Unicode host representations are rejected during origin creation.
- Redirects are disabled by default for authenticated API calls. If an adopted endpoint requires one, only same-origin
  redirects with an allowlisted status/method policy are followed.
- Certificate validation uses the platform trust store unless an application injects a documented enterprise trust
  adapter. Trust-all callbacks are never part of the public API.
- Certificate pinning is an application policy because rotation and platform behavior require operational ownership.

## Input and schema validation

Validation occurs before a runtime document becomes a model:

1. enforce response byte and decompression bounds;
2. decode JSON with depth/node limits;
3. validate the declared contract identifier/version;
4. validate against the closed adopted schema;
5. check namespacing, counts and cross-references;
6. check schema/widget compatibility; and
7. construct immutable wire-level contract and value models.

The SDK never evaluates regexes or recursive structures outside the adopted bounded subset. Unsupported JSON Schema
formats do not become permissive strings for write operations.

## Extension contribution safety

The proposed manifest has no properties for HTTP URLs, routes, methods, scripts, modules, handlers, templates,
expressions or credentials. Its required `$schema` value is one exact non-network contract identifier, and clients
must never dereference a runtime `$schema` value. Additional properties are rejected. References use namespaced
handles resolved through core discovery.

Core must admit contributions during extension activation and serve effective policy-filtered documents without
executing extension providers. The client verifies schema and generation again as defense in depth. See
[Extension client surfaces](extension-client-surfaces.md).

## Content and display

Manifest labels, help text and error summaries are plain text. Business rich text/media need an adopted rendering
policy covering sanitization, schemes, external resource loading, CSP-equivalent restrictions and download size.
Until that policy exists, a host application may display a safe text representation or mark the field unsupported.

## Logging and observability

Allowed diagnostic fields include:

- correlation ID;
- method classification and normalized operation ID;
- status/problem code;
- duration and retry count;
- SDK/core contract versions; and
- non-sensitive site/context references if application policy permits.

Forbidden fields include bearer/refresh tokens, cookies, authorization codes/verifiers, passwords, second factors,
secret/write-only field values, complete mutation bodies, arbitrary error extensions and personally identifying
record content.

`toString()` implementations for credentials, request bodies and records must be redacted by construction.

## Mutation safety

The SDK canonicalizes a mutation once, binds its idempotency key and preserves bytes for an identical retry. It does
not retry after a stale ETag, authorization failure, validation failure or unknown server outcome unless the adopted
problem code and operation contract explicitly allow it.

A cancelled client request may still have committed. Cancellation returns an ambiguous outcome with an operation
reference when available; it never reports “not applied” without server evidence.

## Local data

The baseline cache is online-first and disposable. It stores only policy-disclosed, non-write-only data required for
performance. Applications needing encrypted durable record storage require a separate reviewed profile.

Deleting local data must remove context indexes, cached manifests/contracts and credential references. OS storage
and filesystem deletion guarantees are documented honestly; secure erasure is not claimed on copy-on-write media.

## Abuse-case gate

Before beta, automated tests cover:

- cross-origin redirect with authorization header;
- site/organization/workspace cache collision;
- revoked/expired token and repeated refresh failure;
- policy/runtime/definition generation change;
- malformed, oversized and deeply nested runtime schemas;
- unknown required surface/widget kind;
- manifest executable/URL-shaped properties;
- decimal exponent/overflow and Unicode confusables in identifiers;
- mutation timeout before and after commit;
- stale ETag and changed-body idempotency reuse;
- logs/crash diagnostics containing sentinel secrets; and
- extension disable while a surface is cached/open.

Passing client tests does not replace a core threat model or external application review.
