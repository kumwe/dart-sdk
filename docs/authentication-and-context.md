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

The preferred profile is the **authentication link** (the pattern the industry calls a magic link), per
[ADR 0007](decisions/0007-authentication-link-is-the-primary-sign-in.md):

1. The person enters the deployment URL once; the application reads discovery from that exact origin and offers
   only the advertised areas and profiles.
2. The person chooses the area — administrator or portal — and enters their email address. The address is an
   identifier, not a credential; ADR 0004 is unchanged.
3. The application opens a `KumweAuthenticationLinkTicket`: a fresh S256 proof-key verifier and challenge plus a
   single-use state, generated inside the requesting client.
4. It sends the link request — address, area, challenge — to the deployment. The response is identical whether or
   not the address is known, and core emails a single-use link either way.
5. Opening the link lands on core's HTTPS page, which returns code and state to the client through a
   platform-verified association or registered private-use scheme. Reading the email elsewhere, the person types
   the landing page's bounded manual completion code into the requesting client instead.
6. The ticket verifies the state in constant time and yields the grant; the provider redeems code plus verifier
   at the token endpoint with the `authentication_link` grant.
7. Core returns the closed token response — bounded metadata, area binding, account state and context; plaintext
   access/refresh tokens enter secure storage.
8. The SDK opens an immutable execution-context session. A pending guest account renders only the arrival page.

Authorization code with PKCE through the system browser remains the supported alternative profile with the same
invariants ([ADR 0006](decisions/0006-native-authorization-is-pkce-first.md)). An embedded WebView that collects
credentials is not an acceptable substitute for either profile.

## Sign-in areas

A deployment exposes at most two authenticated areas — `administrator` and `portal` — as separate session
boundaries, exactly as the web does with its URL paths. The area is chosen before the link request, the issued
credential is bound to that single area, and the token response reports the binding; the SDK never infers an
area or reuses a credential across areas. One client may hold both areas of one deployment as two separate
accounts.

## Guest arrival

Requesting a link for an address the deployment does not know is not an error: core creates a pending guest
account, notifies its stewards, and the emailed link signs the person in with the minimum capability set. The
token response reports `account.state` as `pending`; the client shows its arrival page and nothing else. An
authorized administrator positions the account in core's own UI; core emails the person when access is granted,
and the client learns the new state through refresh. The SDK never asserts a state transition itself.

## Persistent sessions and multiple accounts

A signed-in account stays signed in until the person logs out, the server revokes the family, or authority
changes force re-authentication. Persistence lives in the rotating refresh family — access tokens stay
short-lived, and staying signed in never extends one. The client may hold several accounts across several
deployments and both areas, switch between them freely, and remove one without touching the others. The SDK
keys everything by exact origin, area and credential reference: the non-secret roster is the
`KumweAccountDirectory` port, secret material stays in the credential store under its own key, and caches
partition per account.

## Token metadata

The provider needs enough non-secret metadata to enforce correct use:

- credential reference/family, purpose and audience;
- subject reference;
- bound sign-in area and reported account state;
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

## Web-session handoff

The proposed `POST /api/v1/native/web-session` resource exchanges an authenticated native credential for a
single-use, short-lived HTTPS URL that signs the same subject into the same area in the external browser. That is
how the client opens the website already authenticated — for browser-only administration, extension pages or
step-up — without ever placing a bearer token, cookie or password in the browser. The SDK validates the URL
against the exact deployment origin (`KumweWebSessionHandoff`), treats it as secret material, and opens it at
most once. The browser session is core's own; a handoff is a convenience path, and a browser-only outcome still
cannot satisfy native parity.

## High-impact step-up

The audited core binds approval proof to administrator/portal browser sessions. The SDK therefore reports the
native operation as unsupported and MUST NOT ask for a password or second factor to work around it. The
web-session handoff above is the sanctioned way to continue such work in the browser; it remains outside the
advertised native profile and cannot satisfy native parity.

A future remote approval profile needs an adopted core protocol with phishing-resistant user interaction,
single-use proof, exact action/payload/version/context binding, expiry and replay prevention. It cannot be created
solely in this repository.

## Development token mode

Applications MAY accept a manually provisioned short-lived token for local development or controlled service use.
The mode must be visibly labeled, require an explicit site, avoid persistence by default and never be presented as
the production native login flow.

See [ADR 0004](decisions/0004-sdk-never-collects-user-credentials.md).
