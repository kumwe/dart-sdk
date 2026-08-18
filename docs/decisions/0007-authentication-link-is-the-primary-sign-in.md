# ADR 0007: the authentication link is the primary end-user sign-in

- Status: Accepted
- Date: 2026-08-18

## Context

The product owner has decided how a person signs in to a Kumwe client: they choose the deployment (its exact
HTTPS URL, because Kumwe is self-hosted), choose the area (administrator or portal), enter their email address,
and receive an email whose link opens the client and completes sign-in — the pattern the industry calls a magic
link, named the **authentication link** in Kumwe. An address the deployment does not know still signs in: the
person arrives as a pending guest, the client shows an arrival page, designated stewards are notified, and an
administrator positions the account before real capability is granted. Sessions persist until explicit logout,
the client may hold and switch between several deployments and areas at once, the web keeps its password login,
and the client can open the website already authenticated.

[ADR 0006](0006-native-authorization-is-pkce-first.md) had committed the proposal to PKCE through an external
user agent as the preferred profile. That decision anticipated revision when core selects an equivalent reviewed
flow; the owner's selection is this flow. [ADR 0004](0004-sdk-never-collects-user-credentials.md) is unaffected:
an email address is an identifier, not a credential, and the SDK still never receives a password, one-time code,
recovery code or session cookie.

## Decision

The preferred profile in [`contracts/native-authorization.proposal.json`](../../contracts/native-authorization.proposal.json)
is `authentication_link`. The flow keeps the proof-key discipline of ADR 0006 rather than replacing it: the
requesting client generates an S256 challenge, the emailed link carries a single-use code, and redemption at the
token endpoint requires the verifier that never left the requesting client — so an intercepted or forwarded email
cannot complete sign-in anywhere else, and cross-device delivery goes through the landing page's bounded manual
completion code typed into the requesting client. Link requests name exactly one area; issued credentials are
area-bound. Unknown addresses receive the same response and a guest-arrival link that signs in to a pending
account with the minimum capability set (`account.state` in the token response). Persistence is the rotating
refresh family, never a long-lived access token. A bearer-authenticated web-session handoff resource mints a
single-use, short-lived URL that signs the same subject into the same area in the external browser; raw tokens
never enter a browser.

Authorization code with PKCE remains a supported alternative profile with unchanged invariants. The pre-issued
bearer path remains for controlled integrations. Embedded credential collection remains rejected. The SDK ships
flow value types and proof-key primitives now (`KumweAuthenticationLinkTicket`, `KumweLoginArea`,
`KumweAccountState`, `KumweWebSessionHandoff`, the account directory), and still implements no authorization
endpoint behavior before core adoption.

## Consequences

- ADR 0006's preferred-profile choice is superseded; its security invariants, its rejection of embedded
  credential collection and its external-user-agent rule carry over unchanged.
- Core review of `CORE-AUTH-001` starts from the authentication-link profile; `CORE-ACCOUNT-001` (guest arrival
  and positioning) and `CORE-AUTH-002` (web-session handoff) join the adoption package, because the sign-in
  experience the owner requires depends on all three.
- The token response gains area binding and account state; the discovery document advertises enabled areas, so
  the client's area chooser never guesses.
- The client shows one sign-in path on every platform; password entry exists only in core's own browser UI.

## Rejected alternatives

- Keeping PKCE-first with the authentication link as secondary: contradicts the owner's product decision and
  would make the everyday flow the untested one.
- Emailed links that sign in whoever opens them, without proof-key binding: link interception or forwarding
  would become account takeover; rejected outright.
- A separate registration form for unknown addresses: duplicates the flow, invites enumeration, and contradicts
  the guest-arrival experience the owner specified.
- Collecting the Kumwe password in the client as a fallback: rejected by ADR 0004; unchanged.
