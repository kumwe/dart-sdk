# Authentication and execution context

## Observed core behavior

The audited REST API accepts an opaque bearer token and requires exactly one `Kumwe-Site` header matching the site
bound to that token. Tokens may also bind organization/workspace, membership version, policy generation, subject
security epoch, audience, purpose, family and delegation depth.

No public API login, OAuth/OIDC authorization-code flow, device flow, refresh flow or administrator-session exchange
was found. An already authorized administrator or CLI must issue the initial token. That is suitable for controlled
integration credentials, not a complete native user sign-in experience.

## SDK rule

The SDK is a token consumer, not a credential verifier. It MUST NOT accept:

- Kumwe account passwords;
- authenticator one-time codes;
- recovery codes;
- administrator session cookies;
- extension signing keys; or
- database/host credentials.

Authorization interaction belongs behind `KumweAuthorizationProvider`, implemented by the application or a separate
reviewed adapter.

## Required native application profile

The preferred core addition is authorization code with PKCE using the system browser:

1. The application discovers the authorization metadata from a pinned/approved Kumwe origin.
2. It creates a high-entropy verifier, challenge, nonce and state.
3. It launches an external user-agent to the exact HTTPS authorization endpoint.
4. Core authenticates and performs any step-up in its own protected UI.
5. A registered loopback/custom redirect returns only an authorization code and state.
6. The provider verifies state and exchanges the code with the verifier.
7. Core returns bounded token metadata and available context; plaintext access/refresh tokens enter secure storage.
8. The SDK opens an immutable execution-context session.

If core chooses device authorization instead, it must preserve phishing-resistant origin display, polling bounds,
expiry, cancellation and least privilege. An embedded WebView that collects credentials is not an acceptable
substitute.

## Token metadata

The provider needs enough non-secret metadata to enforce correct use:

- credential reference/family, purpose and audience;
- subject reference;
- expiration and refresh eligibility;
- bound site and optional organization/workspace;
- security epoch/membership/policy generation when exposed;
- granted scope/capability summary; and
- server/core contract generation.

The SDK never parses an opaque token to guess these values.

## Execution context

`KumweExecutionContext` is immutable and includes:

```text
origin
site
credential reference
organization? / workspace?
locale
correlation root
authority generation metadata when supplied
```

Every request receives the context explicitly. The `Kumwe-Site` header is derived from this validated object, never
from the origin's host. Organization/workspace are not accepted as arbitrary request headers unless core adopts
that contract; they are selected through an authorized context resource or token exchange.

## Context discovery and switching

Core needs an endpoint that returns only contexts the current actor may select, with opaque stable identifiers and
display labels. A switch must issue or bind a credential/context that core recognizes. The SDK then:

1. closes the old session for new work;
2. cancels or lets explicitly detached reads finish;
3. clears old authority-bound caches;
4. requests a token/context for the new selection; and
5. performs capability/contract discovery again.

It never edits organization/workspace identifiers on an existing token speculatively.

## Secure persistence

The Dart package exposes a credential-store port. Platform adapters may use Keychain, Credential Manager, Secret
Service or another OS facility. Requirements:

- access/refresh tokens never enter ordinary preferences, logs, crash reports or analytics;
- storage entries are keyed by origin and credential reference, not username alone;
- refresh-token reads are minimized and values are zeroed/released where the platform permits;
- logout/revoke removes local material after the server attempt and records uncertain revocation state safely;
- backup/synchronization behavior of the OS store is documented; and
- test stores use obvious synthetic tokens and are unavailable in production builds.

## Expiry, revocation and authority changes

- A 401 invalidates the access token and invokes the provider's refresh/re-authentication policy once.
- A repeated 401 terminates the session; it does not loop.
- A 403 or omitted business field/action does not trigger broader-token acquisition automatically.
- Security epoch, membership or policy generation changes invalidate context metadata.
- Token rotation is atomic from the application's perspective: old and new tokens are never mixed across one
  request or cache key.

## High-impact step-up

The audited core binds approval proof to administrator/portal browser sessions. The SDK therefore reports the
native operation as unsupported and MUST NOT ask for a password or second factor to work around it. An optional
external-system-browser handoff is outside the SDK profile and cannot satisfy native parity.

A future remote approval profile needs an adopted core protocol with phishing-resistant user interaction,
single-use proof, exact action/payload/version/context binding, expiry and replay prevention. It cannot be created
solely in this repository.

## Development token mode

Applications MAY accept a manually provisioned short-lived token for local development or controlled service use.
The mode must be visibly labeled, require an explicit site, avoid persistence by default and never be presented as
the production native login flow.

See [ADR 0004](decisions/0004-sdk-never-collects-user-credentials.md).
