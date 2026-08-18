# Extension client surfaces

## Problem

Kumwe extensions can currently contribute server-side administrator/portal routes, Twig views, navigation, KIS
surfaces, field presenters and generated business definitions. The generated business catalog is machine-readable,
but arbitrary extension pages and KIS presentation declarations are not a Flutter UI contract.

A native client therefore needs a new declarative contribution surface. It must describe intent without copying
server templates or allowing extension code to execute in the client.

## Proposal status

The proposal consists of:

- [`client-surface-contract.proposal.json`](../contracts/client-surface-contract.proposal.json), which declares
  vocabulary and limits;
- [`client-surface-manifest.schema.json`](../contracts/schemas/client-surface-manifest.schema.json), which validates
  an extension contribution; and
- [valid examples](../contracts/examples/).

All are non-authoritative. No audited core endpoint serves them today.

## Design rules

1. **Declarative only.** A manifest contains labels, semantic screen kinds and references to core-owned resources.
2. **No arbitrary routes.** Bindings name a definition, view, action or report handle; they do not supply an HTTP
   method/path.
3. **No executable content.** Dart, JavaScript, WASM, native code, callbacks, templates and expressions are absent
   from the grammar.
4. **Owner namespacing.** Every manifest, surface, navigation item and screen identifier starts with the extension's
   namespace.
5. **Deny by default.** Audience exposure is explicit; portal surfaces are never inferred from administrator
   exposure. Anonymous public presentation is outside this authenticated proposal.
6. **Policy filtered.** Core emits only contributions and bindings the current actor/context may discover.
7. **Server validation remains final.** Client visibility and required fields cannot grant an action or validate a
   record authoritatively.
8. **Lifecycle bound.** Runtime generation, owner version and checksums invalidate cached manifests on extension
   disable, upgrade, trust loss or definition change.
9. **Bounded.** Counts, text, locale maps and nested structures have fixed maximums.
10. **Accessible semantics.** A screen declares intent; the host supplies platform-native controls and focus order.

## Manifest shape

A contribution identifies:

- schema generation and manifest identity;
- extension owner and version;
- trusted runtime generation/checksum supplied by core;
- required client contracts;
- one or more surfaces for `administrator` or `portal` audiences; and
- localized labels, navigation and semantic screens.

Public audience is not part of this proposal. It requires a separate adopted descendant of `CORE-PUBLIC-001` with
anonymous routing, policy, localization, presentation, and extension-lifecycle semantics.

## Screen vocabulary

| Kind | Binding | Host behavior |
| --- | --- | --- |
| `collection` | definition plus optional declared view | Query and render a bounded record collection |
| `record` | definition | Render disclosed record details and relations |
| `form` | definition plus `create` or `update` | Build controls from current field schemas/presentation hints |
| `document` | definition plus document view | Render declared identity/meta/line/total roles |
| `report` | report handle | Render typed parameters and bounded/asynchronous result status |

Action controls come from the policy-filtered business action catalog for the bound definition. A manifest cannot
invent command inputs or override `high_impact`, `bulk`, approval or transition annotations.

## Semantic widget vocabulary

The proposal allows finite presentation hints such as text, multiline text, rich text, integer, decimal, money,
quantity, boolean, choice, date, time, instant, email, URL, phone, media reference, entity reference, object,
collection, secret and output.

Hints are advisory within a compatible JSON Schema/value family. For example, `money` cannot be applied to a string
schema. Core should compile the effective hint from its trusted field presentation registry rather than accepting a
client manifest override that contradicts the field type.

The separate [`kumwe/client`](https://github.com/kumwe/client) host owns screen/view models, widgets, layout, and
interaction. This SDK validates and exposes only the bounded contract values and references.

An unsupported optional hint falls back only to a compatible generic control. An unsupported required field schema
disables mutation and produces an explicit unsupported-contract state.

## Conditions

The audited business catalog intentionally strips stored expression trees and emits only `conditional: true`. The
proposal does not recreate domain conditions in the client manifest. Record-specific visibility/editability remains
server-owned.

Core may later adopt a separate bounded presentation predicate contract, but it must define data dependencies,
policy filtering, type checking, limits and parity tests. Until then:

- conditional fields may be displayed conservatively;
- writes include only user-editable fields disclosed for the operation;
- the server may return validation/visibility changes; and
- the client refreshes the record/definition after a mutation.

## Localization

Labels use a required default plus a bounded BCP 47 translation map. Core chooses the best permitted locale using an
adopted fallback contract or supplies the map. A manifest does not override core validation/error translations.

The client treats all label text as plain text. Markup is not permitted.

## Capability and operation binding

`required_capabilities` are hints for early omission and diagnostics. Core remains responsible for policy filtering.
The client never interprets capability strings as proof that a record/action is authorized.

Screen bindings also name required business operations. If current discovery omits one, the screen or control is
omitted without revealing whether the cause is denial, lifecycle state or absence.

## Cache and lifecycle

An effective manifest cache key includes:

- origin and site;
- credential/actor and selected organization/workspace;
- authorization/policy generation when available;
- trusted runtime generation and checksum;
- owner version; and
- every referenced definition version/checksum.

The client discards the document rather than merging it with a different generation. Core must serve exact-current
metadata or fail closed; a stale generation is never used to preserve extension navigation after disable.

## Unsupported server pages

Some extensions will continue to provide custom server-only routes. They are not represented as native screens. The
host application may offer a separately configured “Open in browser” command for a trusted origin, but the URL comes
from application/core routing policy—not from this manifest—and credentials are not inserted into it. When core
adopts the web-session handoff (`CORE-AUTH-002`), that command may open the browser already signed in through the
handoff's single-use URL; a bearer token, cookie or manifest-supplied URL still never enters the browser.

## Adoption requirements

Core adoption must add:

- a core-owned authenticated client-surface contribution type and compatibility generation;
- activation-time namespace/schema/collision admission;
- policy-aware effective-manifest service;
- REST/OpenAPI discovery with ETag and generation headers;
- lifecycle/cache tests for activate, upgrade, disable, trust loss and recovery mode;
- semantic parity fixtures with administrator/portal generated surfaces; and
- documentation of unsupported server-only routes.

See [ADR 0002](decisions/0002-client-extensions-are-data.md) for the no-code decision.
