# Client-facing API

## Implemented foundation (`0.1.0-dev.5`)

The current pure-Dart package exports an executable protocol foundation:

- immutable JSON, headers, requests, responses, and request-context values;
- a redacting application-supplied bearer-token provider;
- an injected transport plus a bounded, non-redirecting `package:http` adapter;
- RFC 9457 Problem Details and typed API/protocol/authentication failures;
- contract generation/ETag metadata and an authorization-partitioned in-memory cache;
- strict API discovery, liveness, readiness, and protected OpenAPI retrieval;
- exact-value types (`KumweDecimal`, `KumweMoney`, `KumweQuantity`) mirroring core's canonical string rules;
- mutation primitives: validated `IdempotencyKey`, strong `EntityTag` with `"vN"` record versions, and
  conservative HTTP-semantics retry classification;
- the immutable `KumweExecutionContext`/`KumweContextSelection` model with an authority-complete cache partition;
- the `KumweAuthorizationProvider` and `KumweCredentialStore` application ports with non-secret token metadata;
- `ClientSurfaceInterpreter`, reading the proposed client-surface grammar into immutable models with typed
  per-surface rejections and omitted-hint notices; and
- OpenAPI/JSON Schema proposal validators and repository tooling.

`KumweClient` currently accepts `KumweClientOptions`, an injected `KumweTransport`, and optional contract-cache
configuration. It implements only `discover`, `liveness`, `readiness`, and `fetchOpenApiContract`. It intentionally
has no generated content, identity, business, media, or other resource clients while the pinned core OpenAPI fails
the generation gate. See [Current status](status.md) and the package tests for executable evidence.

## Target API after contract adoption

The remainder of this document is the intended public Dart shape, not an implementation claim. Names may change
before the corresponding API review, but the separation of concerns is architectural.

## Entry point

```dart
final client = KumweClient(
  origin: Uri.https('cms.example.invalid'),
  authorization: authorizationProvider,
  transport: transport,
  contractPolicy: contractPolicy,
);

final session = await client.open(
  const KumweContextSelection(site: 'corporate'),
);
```

`KumweClient` owns immutable configuration and validates the origin. `KumweSession` owns one authenticated execution
context. There is no mutable global “current site.” Switching organization or workspace creates a new session and
invalidates context-bound caches.

## Proposed public service graph

| Service | Responsibility | Availability rule |
| --- | --- | --- |
| `session.capabilities` | Contract/profile and optional feature discovery | Always after successful open |
| `session.content` | Content and model resources | Only when adopted DTO contract is present |
| `session.navigation` | Menus and menu items | Only when adopted DTO contract is present |
| `session.identity` | Users, roles, grants and tokens | Capability- and contract-gated |
| `session.settings` | Browser-managed site settings | Contract-gated |
| `session.automation` | Schedules and jobs | Contract-gated |
| `session.extensions` | Installed extension status/lifecycle | Contract-gated; install remains separate if core does |
| `session.business` | Runtime definitions, records, relations, actions and history | Available with generated-business contract |
| `session.reporting` | Reports, exports and status | Capability- and contract-gated |
| `session.clientSurfaces` | Declarative workspaces/navigation/screens | Only after core adopts manifest contract |

Asking for an unavailable service returns a typed compatibility result. It never sends a speculative request.

## Results and failures

Network and server outcomes use an explicit result rather than throwing for expected API failures:

```dart
sealed class KumweResult<T> {}
final class KumweSuccess<T> extends KumweResult<T> {
  final T value;
  final KumweResponseMetadata metadata;
}
final class KumweFailure<T> extends KumweResult<T> {
  final KumweProblem problem;
}
```

Programmer errors such as an invalid origin, malformed local identifier or using a disposed session may throw.
Authentication expiry, denial, stale ETag, validation, unsupported contract and temporary unavailability are data.

`KumweProblem` includes only adopted stable fields:

- stable code/type;
- HTTP status;
- redacted title/detail;
- correlation ID;
- retry class and optional `Retry-After`;
- optional field violations;
- optional expected/actual version; and
- original opaque extension data only when the contract explicitly marks it safe.

Until `CORE-API-002` is adopted, error mapping remains experimental and no public enum may pretend to be complete.

## Context and authorization providers

```dart
abstract interface class KumweAuthorizationProvider {
  Future<KumweAccessToken> tokenFor(KumweTokenRequest request);
  Future<void> invalidate(KumweCredentialReference credential);
}
```

The provider owns authorization interaction and secure persistence. The SDK receives an opaque access token and
metadata; it never receives a username/password, second factor or recovery code. See
[Authentication and context](authentication-and-context.md).

The authentication-link flow ships as endpoint-free primitives the provider builds on: a
`KumweAuthenticationLinkTicket` opens with a generated proof key and state, its `request` is what the
application sends to the deployment, and its single-use completion — from the deep-link return URI or the
manually typed cross-device code — yields the `KumweAuthenticationLinkGrant` the provider redeems once core
adopts the contract. `KumweLoginArea` and `KumweAccountState` are the area and guest-arrival vocabulary,
`KumweWebSessionHandoff` validates the single-use browser handoff against the exact deployment origin, and the
`KumweAccountDirectory` port holds the non-secret multi-deployment account roster beside the credential store.

## Core resource conventions

Generated resources follow a common vocabulary without erasing resource-specific contracts:

```dart
Future<KumweResult<KumwePage<ContentSummary>>> list(ContentQuery query);
Future<KumweResult<Versioned<Content>>> read(ContentId id);
Future<KumweResult<MutationReceipt<Content>>> update(
  ContentId id,
  ContentPatch patch, {
  required EntityTag ifMatch,
  required IdempotencyKey idempotencyKey,
});
```

- `KumwePage<T>` contains items and an optional opaque continuation token; it does not invent total counts.
- `Versioned<T>` carries a strong ETag separately from the payload.
- `MutationReceipt<T>` carries replay state, new ETag, status reference and correlation metadata.
- A generated method exists only when its request and all advertised responses are schema-complete.

## Dynamic business API

Business values are runtime-schema data, not generated entity classes:

```dart
final definition = await session.business.definition('acme.asset');
final page = await session.business.search(
  definition: definition.value.reference,
  query: BusinessQuery(...),
);
```

Proposed key types:

| Type | Meaning |
| --- | --- |
| `BusinessDefinition` | Policy-filtered fields, views, actions, relations, workflow and schemas |
| `BusinessRecord` | Public identity, authoritative version and disclosed semantic values |
| `BusinessQuery` | Closed bounded filter/search/sort/projection/include/aggregate AST |
| `BusinessMutationIntent` | Context-bound canonical input, idempotency key and expected version |
| `BusinessActionContract` | Action identity, safety annotations and command/result schemas |
| `BusinessOperationReference` | Caller-bound asynchronous/replay status identity |

The SDK validator recognizes only the adopted JSON Schema subset. A value can be displayed before every optional
presentation feature is understood, but a write is disabled if its required input schema cannot be interpreted.

## Exact-value API

`KumweDecimal`, `KumweMoney` and `KumweQuantity` parse and preserve canonical strings. They do not expose implicit
conversion to `double`.

```dart
final price = KumweMoney(
  amount: KumweDecimal.parse('19.95'),
  currency: IsoCurrency.parse('NAD'),
);
```

Locale formatting produces display text and never mutates the canonical value.

## Mutations and retries

The application creates one `IdempotencyKey` per user intent and retains it until the terminal result is known.
The SDK may provide a key generator, but it never replaces a key merely because a request timed out.

Automatic retry is permitted only when all are true:

1. the operation's adopted contract marks an identical retry safe;
2. request bytes, execution context and authorization binding are unchanged;
3. the same idempotency key is retained for a mutation;
4. the deadline and server `Retry-After` permit it; and
5. the failure is classified transient by stable code.

Stale ETags and validation failures always return to the application.

## Capability checks

Applications can test support without exception-driven probing:

```dart
final support = session.capabilities.requireAll({
  'kumwe.core.business.generated',
  'kumwe.core.problem-details.v1',
});
```

The result distinguishes missing, incompatible, deprecated and denied/undisclosed capabilities. A server may omit a
policy-denied business operation, so absence is not proof that the deployment lacks its implementation.

## Cancellation, timeouts and progress

Every call accepts a cancellation token and deadline. Downloads expose bounded byte streams with checksum and
content-type metadata. Upload progress belongs to a future media contract; no API is declared before
`CORE-MEDIA-001` is adopted.

## Flutter host integration

The separate [`kumwe/client`](https://github.com/kumwe/client) application consumes validated SDK contract values and
owns:

- accessible controls for the adopted widget vocabulary;
- navigation/workspace composition;
- secure-storage and external-user-agent adapters selected by the application;
- loading, unsupported, stale and denied states; and
- locale-aware display formatting.

These are client responsibilities, not packages or adapters owned by this SDK repository. They do not expose raw
HTTP clients, authorization headers, or extension-provided rendering code.
