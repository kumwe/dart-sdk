# Current status

Status date: 2026-08-15

SDK stage: executable transport and contract foundation

Audited core: `kumwe/cms@4e5083b3fe43790605ae5c6c5bf8e392f9822efc`

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
| Stable problem-code registry | Missing | Generic open Problem Details object; core roadmap marks machine contract work outstanding |
| Uniform collection pagination | Partial | Generated business is strong; content is capped at 100 without continuation |
| Consistent idempotency semantics | Partial | General contract says 24 hours; business defaults differ; custom actions retain a one-day path |
| Native application authorization flow | Missing | Bearer tokens are pre-issued; no PKCE/device/session-exchange endpoint |
| Media administration API | Missing | Public media fetch exists; management upload/list/delete is graphical |
| Business-security administration API | Missing | Organizations, memberships, policies and step-up administration are graphical |
| High-impact approval decision API | Missing by current design | Fresh browser session-bound step-up is required |
| Client-surface manifest | Proposed | Draft under `contracts/`; no core endpoint exists |
| Arbitrary extension UI in native Flutter | Unsupported | Core extension routes/templates are server-side and not OpenAPI contributions |
| Headless public-site contract | Missing | Public pages are server-rendered through active Twig/theme infrastructure |
| Durable client change feed | Missing | Internal outbox/events are not a client API |
| Realtime client subscription | Missing | No SSE/WebSocket or push contract found |
| Offline sync | Deferred | Foundations exist; queue/delta/reconciliation and numbering decision do not |
| Dart SDK foundation | Partial | Pure-Dart transport, immutable JSON/HTTP values, bearer-provider boundary, Problem Details, discovery/health, OpenAPI cache/validation, proposal validation, tests and CI are implemented; generated resource clients are blocked on core contract maturity |

## Gate status

These gates are outcomes, not calendar phases. The separate [roadmap](roadmap.md) schedules work toward them.
They are local SDK gates, not names or statuses of current core programme gates.

| Gate | Exit condition | Status |
| --- | --- | --- |
| G0 — Honest baseline | Scope, decisions, requirements and proposal contracts agree | Drafted in this foundation |
| G1 — Core contract adoption | Core owns complete typed REST/errors/auth discovery and client-surface versions | Blocked on upstream adoption |
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
