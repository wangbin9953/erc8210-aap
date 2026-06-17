# Receipt Profile: `verification.v0.3`

## Identifier

```
profile_identifier = "verification.v0.3"
evidenceType       = keccak256("verification.v0.3")
                   = 0x<computed at registry time — Solidity: keccak256(abi.encodePacked("verification.v0.3"))>
```

## Specification

| Resource | Location |
| --- | --- |
| Normative spec | IETF Internet-Draft [draft-krausz-verification-state-01](https://datatracker.ietf.org/doc/draft-krausz-verification-state/) (filed 2026-06-06, -01 published 2026-06-12) |
| Reference implementation | [TKCollective/agentoracle-receipt-spec](https://github.com/TKCollective/agentoracle-receipt-spec/tree/v0.3-binary-halt) |
| Reference verifier | [TKCollective/agentoracle-receipt-verify](https://github.com/TKCollective/agentoracle-receipt-verify) |
| Fixture pair | [examples/v0.3/](https://github.com/TKCollective/agentoracle-receipt-spec/tree/v0.3-binary-halt/examples/v0.3) (allow.jws + halt.jws + canonical-input.json + jwks-fixture.json + verify-fixture.mjs) |

## Purpose

Binds a content-level verdict (act / halt) over a specific factual claim, gated by a named, content-addressed mapping document, signed by the issuer's JWKS-published key, and verifiable offline by any relying party without contacting the issuer's runtime.

This is the *verification* lifecycle layer — orthogonal to ERC-8210's authorization lifecycle (delegation / revocation / scope). Both can ride in the same envelope as sibling evidence references.

## Required receipt fields

A conforming `verification.v0.3` receipt is a JWS (JWS JSON serialization, flattened form) over a canonical JSON payload containing at minimum:

| Field | Type | Description |
| --- | --- | --- |
| `receipt_version` | string | MUST be `"0.3.0"` |
| `mapping_id` | string | Named mapping document, e.g. `"agentoracle-v0.3-2026-05-30"` |
| `subject.claim_hash` | string | SHA-256 hash of the canonical claim text, prefixed `sha256-` |
| `v_verdict` | enum | `"supported"` / `"refuted"` / `"unverifiable"` |
| `v_confidence` | number | 0.0 – 1.0 |
| `v_gate_threshold` | number | 0.0 – 1.0; the threshold this evaluation used |
| `v_adversarial_result` | enum | `"resilient"` / `"vulnerable"` / `"not_checked"` |
| `v_recommendation` | enum | Derived: `"confident_supported"` / `"weak_supported"` / `"vulnerable_supported"` / `"refuted"` / `"unverifiable"` |
| `v_gate` | enum | Derived: `"act"` / `"halt"` |
| `v_gate_mapping` | string | MUST equal `mapping_id` |
| `v_gate_mapping_hash` | string | SHA-256 content hash of the mapping document, prefixed `sha256-` |
| `signature_meta.jwks_url` | string | Public JWKS endpoint of the issuer |

## Signing discipline

- **Signature algorithm**: `EdDSA` (Ed25519) for the v0.3 reference profile; `ES256` also conforming.
- **Canonicalization**: payload canonicalized per RFC 8785 (JSON Canonicalization Scheme) before signing. All `*_hash` field values are SHA-256 over canonicalized bytes.
- **Content addressing**: the mapping document referenced by `v_gate_mapping` is immutable and content-addressed; `v_gate_mapping_hash` MUST equal SHA-256 of the mapping document bytes as fetched.

JWS protected header MUST include:

- `alg` — `EdDSA` (Ed25519) for v0.3 reference; `ES256` also conforming
- `kid` — key identifier resolvable in the JWKS at `signature_meta.jwks_url`
- `typ` — `application/vnd.verification.v0.3+jws` (profile-namespaced, not issuer-namespaced; any v0.3 issuer produces receipts with this `typ`)

## Verification protocol

Given a Claim with `evidenceType = keccak256("verification.v0.3")` and `evidenceURI` resolving to a JWS receipt:

1. **Fetch** the JWS from `evidenceURI`.
2. **Verify JWS signature** against the issuer's JWKS at `signature_meta.jwks_url`, matching by `kid`.
3. **If `anchoredEvidenceHash` is non-zero on the Claim:** compute SHA-256 of the fetched JWS bytes and confirm it equals `anchoredEvidenceHash`. Reject on mismatch.
4. **Resolve `v_gate_mapping`** to its named mapping document. Compute SHA-256 of the document bytes; confirm it equals `v_gate_mapping_hash`. Reject on mismatch.
5. **Recompute `v_recommendation`** locally from `v_verdict` + `v_confidence` + `v_gate_threshold` + `v_adversarial_result` per the mapping document rules. Confirm it equals the signed `v_recommendation`. Reject on mismatch.
6. **Recompute `v_gate`** from `v_recommendation` under the mapping. Confirm it equals the signed `v_gate`. Reject on mismatch.
7. **Accept** the verdict iff every step above passes.

The issuer's runtime is never trusted. The only trusted artifacts are: (a) the JWS signature, (b) the mapping document at the content-addressed hash.

## Known issuers

| Issuer | JWKS endpoint | Mapping ID | Domain |
| --- | --- | --- | --- |
| AgentOracle | https://agentoracle.co/.well-known/jwks.json | `agentoracle-v0.3-2026-05-30`<sup>1</sup> | Factual claim verification |
| AgentTrust | https://agenttrust.uk/.well-known/jwks.json | `agenttrust-v0.3-2026-06-07` | Skill / MCP / endpoint threat scanning |

<sup>1</sup> AgentOracle's current production mapping ID is `v0.3.0-2026-05-30` (no issuer prefix); normalizes to `agentoracle-v0.3-2026-05-30` at the next mapping rotation per the §9 convention below.

Two live implementations verify each other's receipts under the same envelope. Adding an issuer requires a published JWKS endpoint and an immutable mapping document at a content-addressable URL.

## Verifier checklist for Resolvers

A Resolver implementation conforming to this profile MUST:

- [ ] Reject any receipt whose JWS signature does not validate against the issuer's published JWKS.
- [ ] Reject any receipt whose mapping document hash does not match `v_gate_mapping_hash`.
- [ ] Recompute `v_recommendation` and `v_gate` locally; reject on mismatch with signed values.
- [ ] When `anchoredEvidenceHash` is non-zero, reject if SHA-256(fetched JWS bytes) ≠ `anchoredEvidenceHash`.
- [ ] Treat any of `v_gate = "halt"`, missing required field, malformed JWS, unreachable JWKS, or unrecognized mapping document as `halt` — fail-closed.

## Versioning

### Profile-vs-mapping distinction

- `verification.v0.3` is immutable. Future mapping documents (new domains, new gate predicates, threshold revisions) ship as new `mapping_id` values, signed and content-addressed, under the same profile envelope.
- A future `verification.v0.4` profile (if envelope changes) would register a new `evidenceType` and live as a sibling entry in this registry.
- Mappings published once cannot be retroactively rewritten — content-addressing prevents post-hoc rule changes from flipping a historical receipt's verdict.

### Mapping ID format

Mapping IDs for this profile MUST follow:

```
<issuer-slug>-v<major>.<minor>-<YYYY-MM-DD>
```

Examples:

- `agentoracle-v0.3-2026-05-30`
- `agenttrust-v0.3-2026-06-07`

This tightens the registry default (`<issuer-slug-or-version>-<YYYY-MM-DD>`) by requiring the issuer-slug prefix and the profile version. Rationale: with two or more issuers operating under the same `verification.v<major>.<minor>` envelope, an unprefixed mapping ID risks collision across issuers (two different issuers could both publish a mapping dated 2026-05-30). The issuer-slug prefix makes the mapping ID uniquely resolvable; the version segment makes the binding between mapping and profile envelope explicit.

## Cross-references

- IETF Internet-Draft: [`draft-krausz-verification-state-01`](https://datatracker.ietf.org/doc/draft-krausz-verification-state/)
- Conforming-implementations table: [agentoracle-receipt-spec §8](https://github.com/TKCollective/agentoracle-receipt-spec#8-conforming-implementations)
- ADR-001 (binary halt gate): [agentoracle-receipt-spec/adr/ADR-001](https://github.com/TKCollective/agentoracle-receipt-spec/blob/v0.3-binary-halt/adr/ADR-001-binary-halt.md)
- ADR-002 (canonical/derived/version-bound mapping): [agentoracle-receipt-spec/adr/ADR-002](https://github.com/TKCollective/agentoracle-receipt-spec/blob/v0.3-binary-halt/adr/ADR-002-canonical-derived-version-binding.md)

## Maintainer

- Profile authored by Joe Krausz (TKCollective LLC)
- Maintained alongside `draft-krausz-verification-state`
- Contact: Joe@agentoracle.co
- Issues / questions: GitHub issues on [agentoracle-receipt-spec](https://github.com/TKCollective/agentoracle-receipt-spec/issues)
