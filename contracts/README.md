# Draft machine contracts

> [!CAUTION]
> Every document in this directory is a **proposal**. None is authoritative for Kumwe core, no endpoint is implied,
> and no production client may require these proposal identifiers. Adoption follows
> [`docs/contract-lifecycle.md`](../docs/contract-lifecycle.md).

## Documents

| Document | Schema | Purpose |
| --- | --- | --- |
| [`contract-index.proposal.json`](contract-index.proposal.json) | [`contract-index.schema.json`](schemas/contract-index.schema.json) | Capability/profile requirements and audited state |
| [`client-surface-contract.proposal.json`](client-surface-contract.proposal.json) | [`client-surface-contract.schema.json`](schemas/client-surface-contract.schema.json) | Proposed vocabulary, limits and security invariants |
| Extension manifest examples | [`client-surface-manifest.schema.json`](schemas/client-surface-manifest.schema.json) | Bounded extension-owned administrator/portal contract surfaces |

Valid examples:

- [`minimal.client-surface.json`](examples/minimal.client-surface.json)
- [`asset-inspection.client-surface.json`](examples/asset-inspection.client-surface.json)

## Status markers

Proposal control documents require:

```json
{
  "status": "proposal",
  "authoritative": false
}
```

Removing these fields is not adoption. When core adopts a descendant, core assigns the authoritative identifier,
version, endpoint/contribution ownership, compatibility fixture and release digest. This directory then records the
mapping and retains historical proposal context as appropriate.

## Validation

Syntax check:

```bash
find contracts -name '*.json' -print0 | xargs -0 -n1 jq empty
```

The repository contract validator must additionally:

1. validate each schema against JSON Schema 2020-12;
2. resolve local relative `$schema`/`$ref` values without network access;
3. validate proposal control documents and examples;
4. check identifiers/references are unique and resolve within each instance;
5. check the contract-index requirement/profile references; and
6. reject unbounded objects, arrays or recursive structures.

## Security properties

The client-surface grammar intentionally has no fields for arbitrary HTTP methods/paths, URLs, Dart, JavaScript,
WASM, native modules, handlers, callbacks, templates, expressions or credentials. All objects are closed. The only
open maps are bounded localization and field-presentation maps with constrained keys and values.

The proposal intentionally excludes an anonymous `public` audience. Public extension presentation requires a
separate adopted descendant of `CORE-PUBLIC-001`; it cannot inherit authenticated context assumptions.

Schema validity does not establish authorization. Core must admission-test, policy-filter and lifecycle-bind an
effective manifest before a client receives it; the client validates again as defense in depth.

## Change policy

- Proposal revisions increment `proposal_version`.
- Bounds may not be loosened without resource/security analysis.
- New required vocabulary is a breaking proposal revision.
- Examples always validate against the same revision in the change.
- A proposal may describe a core requirement, but it must not claim a missing core resource exists.
