# ERC-8210 Receipt Profile Registry

This registry catalogs receipt profiles consumed by ERC-8210 Claims Resolvers. Each profile defines a content-addressable evidence envelope: required fields, signing discipline, verification protocol, and conformance rules.

## Scope

A receipt profile specifies how a single value of `evidenceType` resolves into a verifier-checkable envelope. ERC-8210 defines the on-chain Claim primitive (`evidenceType`, `evidenceURI`, optional `anchoredEvidenceHash`); this registry defines what a Resolver MUST do upon encountering a known `evidenceType`.

## Relationship to ERC-8210

This registry is versioned independently of the ERC body and normatively referenced by it. Profile churn does not require ERC revision; ERC revisions do not invalidate profile entries already in this registry.

## Profile identifier

For every entry:

```
evidenceType = keccak256(profile_identifier)
```

`profile_identifier` MUST be a stable ASCII string of the form `<domain>.v<major>.<minor>` (e.g., `verification.v0.3`). Once published, identifiers are immutable; bumps require a new entry.

## Registry layout

- `docs/receipt-profiles.md`: this file, the registry index and governance
- `docs/profiles/<identifier>.md`: one file per profile entry, written by the profile maintainer

## Entry index

| Identifier | Status | Maintainer | Entry |
| --- | --- | --- | --- |
| `verification.v0.3` | candidate | Joe Krausz (TKCollective) | [docs/profiles/verification-v0.3.md](./profiles/verification-v0.3.md) |

## Profile entry template

A new profile entry MUST include the following sections, in this order:

1. **Identifier**: the `profile_identifier` string and its computed `keccak256` hex
2. **Specification**: normative spec link (IETF Internet-Draft, RFC, or equivalent), reference implementation, reference verifier, fixture pair
3. **Purpose**: one paragraph stating what this profile binds, what lifecycle layer it serves, and its relationship to ERC-8210 authorization
4. **Required receipt fields**: schema table covering required fields and their types
5. **Signing discipline**: signature algorithm, canonicalization rule, content addressing of any mapping documents
6. **Verification protocol**: numbered steps a Resolver executes, with fail-closed defaults
7. **Known issuers**: table of live issuers, their JWKS endpoints, and any issuer-specific mapping IDs
8. **Verifier checklist**: MUST and MUST-NOT items for a conforming Resolver
9. **Versioning**: rules for what constitutes a new mapping vs. a new profile, plus mapping ID format
10. **Cross-references**: ADRs, related profiles, prior art
11. **Maintainer**: entry author, contact, issue tracker

## Governance

### Adding an entry

1. Open a PR adding `docs/profiles/<identifier>.md` and a row in the entry index above.
2. The PR MUST include: a normative spec link (IETF Internet-Draft accepted, RFC preferred long-term), at least one live conforming issuer with a public JWKS endpoint, and an offline-verifiable fixture pair.
3. The registry maintainer (currently the ERC-8210 author, @wangbin9953) reviews for: template compliance, identifier collision, normative reference quality, and feasibility of a second independent issuer within a reasonable horizon.
4. Other registry participants may comment; the merge decision rests with the registry maintainer.

### Mapping ID convention

Each profile entry MUST specify its mapping ID format in section 9 (Versioning). Default convention: `<issuer-slug-or-version>-<YYYY-MM-DD>`, content-addressed; profile authors may override with rationale.

### Status values

- `candidate`: newly added entry, single live issuer, awaiting second independent implementation
- `active`: two or more independent live implementations verified against the same envelope
- `deprecated`: superseded by a later profile; Resolvers SHOULD continue accepting until the sunset date noted in the entry
- `withdrawn`: removed from registry; Resolvers MUST reject

### Deprecation policy

A profile entry MAY be marked `deprecated` by the maintainer with a successor reference and a sunset date no earlier than 12 months from deprecation. Withdrawal requires a documented security or compatibility rationale.

### Changes to this registry document

Changes to the registry index, template, or governance require a PR with at least a 7-day review window on the ERC-8210 v2 discussion thread before merge.

## Cross-references

- ERC-8210 (Agent Assurance Protocol): [ethereum/ERCs PR #1632](https://github.com/ethereum/ERCs/pull/1632)
- Reference implementation: this repository
