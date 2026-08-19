# Current status

Status date: 2026-08-18

SDK stage: executable transport and contract foundation

Audited core: `kumwe/app@4e5083b3fe43790605ae5c6c5bf8e392f9822efc`

Head drift: core's default branch (`df715e39c6269c50c6f4c73d6fb32d1570917945` at this status date) has advanced
sixty commits past the audited commit. `api/openapi/kumwe-v1.json` gains the business-period family
(`/api/v1/business-periods` plus close/reopen); the remainder is localization, quality-gate, deployment and
Studio-integration work. A targeted re-audit of the authentication surface at head confirmed the audited picture
is unchanged: password login at `/administrator/login` and `/portal/login`, pre-issued bearer tokens only, no
mailer in `src/`, no self-registration and no `/api/v1/native/` resources. The audit pin is retained. The
localization changes (`LocalizedDefinitionText`, catalogue translation, wording administration) may move the
`CORE-LOCALIZATION-001` assessment and need a targeted re-audit before that row is trusted for adoption review.

## Programme status

This repository is parallel preparatory work for a **proposed Version 3 Native Client Platform**. It does not change
or provide completion evidence for Kumwe core Version 2, Gate A or Gate B. No Version 3 native-client programme or
gate is treated here as adopted. The recommended future core roadmap additions are a native-client
contract/SDK-readiness gate followed by a final parity-qualification gate; both would require core-owned evidence.

## Status vocabulary

| State | Meaning |
| --- | --- |
| Observed | Present in the pinned core source or an adopted SDK artifact |
| Partial | Useful implementation exists but the stated client contract is incomplete |
| Missing | No suitable public contract was found in the pinned core source |
| Proposed | Designed here, but not adopted by core and not authoritative |
| Deferred | Intentionally outside the current delivery profile |
| Blocked | Work depends on an unmet upstream or security prerequisite |

## Capability baseline

| Capability | State | Evidence or limitation |
| --- | --- | --- |
| Versioned REST root and OpenAPI 3.1 document | Observed | `/api/v1`; checked-in and caller-specific contracts |
| Generated business discovery/records | Observed | Policy-filtered generic route family |
| Business search and cursor pagination | Observed | Closed bounded query document |
| ETag/If-Match for business records | Observed | Strong `"vN"` preconditions |
| Complete management request/response schemas | Missing | Most audited operations lack response content; multiple input operations lack bodies |
| Stable problem-code registry | Proposed | Draft under `contracts/`, seeded from the 40 `urn:kumwe:problem:` type URIs observed at the audited commit, including the four dynamically constructed business idempotency codes |
| Uniform collection pagination | Proposed | Draft under `contracts/` extends the observed business cursor envelope; content remains capped at 100 without continuation |
| Consistent idempotency semantics | Proposed | Draft under `contracts/` declares the two observed ledgers per family; the shared 24-hour text still contradicts them in core |
| Native application authorization flow | Proposed | Draft under `contracts/` (authentication-link-first, ADR 0007; PKCE alternative, ADR 0006); core still exposes only pre-issued bearer tokens and password web login |
| Guest arrival and positioning lifecycle | Proposed | Draft under `contracts/` (`CORE-ACCOUNT-001`); core creates users only through administration and the CLI |
| Authenticated web-session handoff | Proposed | Draft under `contracts/` (`CORE-AUTH-002`); core mints web sessions only from password login |
| Core product identity accepted by the clients | Observed, with a scheduled break | `KumweApiDiscovery` and `KumweLiveness` refuse any `product` value but the observed `Kumwe CMS`. Core's `V2-DOC-002` will change that value now that the repository is `kumwe/app`; this SDK must release acceptance of the new value before core closes it, or every deployed client fails at discovery and liveness. Tracked in the [roadmap](roadmap.md) |
| Native client bootstrap discovery | Proposed | Draft under `contracts/` (now advertising sign-in areas); core serves an API identity document but no native discovery resource |
| Media administration API | Missing | Public media fetch exists; management upload/list/delete is graphical |
| Business-security administration API | Missing | Organizations, memberships, policies and step-up administration are graphical |
| High-impact approval decision API | Missing by current design | Fresh browser session-bound step-up is required |
| Client-surface manifest | Proposed | Draft under `contracts/`; no core endpoint exists. The SDK now carries an executable interpreter for the proposed grammar, so the vocabulary is proven by a working consumer rather than by schema review alone |
| Arbitrary extension UI in native Flutter | Unsupported | Core extension routes/templates are server-side and not OpenAPI contributions |
| Headless public-site contract | Missing | Public pages are server-rendered through active Twig/theme infrastructure |
| Durable client change feed | Missing | Internal outbox/events are not a client API |
| Realtime client subscription | Missing | No SSE/WebSocket or push contract found |
| Offline sync | Deferred | Foundations exist; queue/delta/reconciliation and numbering decision do not |
| Dart SDK foundation | Partial | Pure-Dart transport, immutable JSON/HTTP values, bearer-provider boundary, Problem Details, discovery/health, OpenAPI cache/validation, proposal validation, tests and CI are implemented, plus exact-value types, idempotency/entity-tag primitives, HTTP-semantics retry classification, immutable execution context, the authorization-provider/credential-store ports, the authentication-link flow primitives (proof key, ticket, grant, login areas, account states, account directory, web-session handoff value) and the client-surface manifest interpreter; generated resource clients and all authorization endpoint behavior remain blocked on core contract maturity |

## Gate status

These gates are outcomes, not calendar phases. The separate [roadmap](roadmap.md) schedules work toward them.
They are local SDK gates, not names or statuses of current core programme gates.

| Gate | Exit condition | Status |
| --- | --- | --- |
| G0 — Honest baseline | Scope, decisions, requirements and proposal contracts agree | Drafted in this foundation |
| G1 — Core contract adoption | Core owns complete typed REST/errors/auth discovery and client-surface versions | Adoption package drafted under `contracts/`; blocked on upstream adoption |
| G2 — Generated SDK alpha | Reproducible invariant client passes contract fixtures | Foundation implemented; generated resource client blocked on G1 |
| G3 — Dynamic runtime alpha | Runtime metadata and client-surface interpreter pass lifecycle fixtures | Blocked on G1 |
| G4 — Native authorization/context beta | Supported authorization-provider integration and context switching pass abuse tests | Blocked on upstream auth decision |
| G5 — Advertised profile parity | Every advertised profile passes cross-surface conformance | Not started |
| G6 — Stable release | Compatibility, package, documentation and release-evidence gates pass | Not started |

## Known contradictions requiring resolution

- Core documentation calls its OpenAPI document authoritative while its own roadmap says generated REST schemas and
  stable problem codes remain outstanding.
- The shared OpenAPI idempotency header promises 24 hours, while the business-record runtime defaults to seven-day
  replay and thirty-day retention; custom extension actions still use one day.
- The ERP programme asks for equivalent UI/REST/OpenAPI/CLI/MCP outcomes, while high-impact approvals and several
  administrator functions lack native machine contracts. Those operations must remain outside advertised native
  profiles until core exposes equivalent APIs; a browser-only outcome cannot satisfy parity.
- The atomic multi-line document command exists in the application layer but is not exposed through the audited
  machine surfaces.
- Definition translations and semantic field presenters exist in core, but discovery exposes raw labels and JSON
  Schema rather than a locale-aware client presentation contract.

No SDK release may normalize these contradictions silently. Resolution belongs in the adoption process described in
[Contract lifecycle](contract-lifecycle.md).
