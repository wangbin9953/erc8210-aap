// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IIndependenceSignal — Optional Extension (ERC-8210 v2 改动 15)
/// @notice Abstract interface for independence assessment between two
///         addresses. Trust-scoring layers, attestation issuers, and
///         sybil-detection oracles implement this interface so Resolvers,
///         IRiskHook implementations, and Claims pipelines can consume
///         independence signals through a single canonical surface.
///
/// @dev This is a v2 DRAFT interface. Two unresolved items pending Henry
///      (co-author) review at v2 PR launch:
///
///      1. **Composition with IRiskHook**: whether this interface is consumed
///         in parallel with IRiskHook, inherited by IRiskHook, or composed by
///         a higher-level hook. The draft assumes parallel consumption: a
///         Resolver MAY call IRiskHook for amount + evidence and
///         IIndependenceSignal for independence judgement, then combine.
///
///      2. **5th "Behavioral similarity" category** (open class): rationale
///         currently specifies four minimum signal categories below; whether
///         to elevate "behavioral fingerprint" to a 5th core category is
///         pending community feedback (see 待确认事项 #2 in the changelog).
///
/// ─── Minimum signal categories the `evidence` payload SHOULD encode ─────
///
///   1. Funding origin overlap   — shared funder / cluster membership
///   2. Temporal proximity        — creation/activity timeline alignment
///   3. Relationship density      — on-chain interaction graph proximity
///   4. Ownership signals         — funder-to-owner match, declared ownership
///
///   (5. Behavioral similarity   — open category, may move to core in v2 final.)
///
/// ─── Output contract (rationale-level invariants) ──────────────────────
///
///   - Partial signals are LEGAL. `evidence` MAY omit categories the issuer
///     cannot observe; `confidence` reflects "best-effort given the data we
///     do have", not "completeness".
///   - Empty `evidence` MUST imply `confidence == 0`, and vice versa.
///   - When `confidence == 0`, the `independent` field is UNDEFINED and
///     consumers MUST NOT rely on it. Implementations MUST NOT fail-closed
///     (i.e., MUST NOT return `independent == false` to signal "no data"),
///     because fail-closed rewards manufactured history over honest absence.
///   - The relation is symmetric: `assess(A, B)` MUST return the same result
///     as `assess(B, A)`.
interface IIndependenceSignal {

    /// @notice Delivery mode 1 — on-chain oracle view.
    ///         Trust layers that maintain a live on-chain oracle expose
    ///         independence assessments via this view function. Suitable
    ///         for Resolvers running on-chain in the same execution context.
    /// @param addrA First address.
    /// @param addrB Second address.
    /// @return independent True iff the two addresses are independent per the
    ///         trust layer's methodology. UNDEFINED when `confidence == 0`.
    /// @return confidence 0–255 confidence score. `0` means "no usable
    ///         signal" and `independent` MUST be ignored by the consumer.
    /// @return evidence Opaque bytes carrying signals from the four minimum
    ///         categories (and optionally the 5th). MAY be empty bytes, in
    ///         which case `confidence` MUST be 0.
    function assessIndependence(
        address addrA,
        address addrB
    ) external view returns (
        bool independent,
        uint8 confidence,
        bytes memory evidence
    );

    /// @notice Delivery mode 2 — signed attestation verification.
    ///         Trust layers that publish signed off-chain attestations expose
    ///         verification via this function. The attestation payload
    ///         carries the same output shape (`independent`, `confidence`,
    ///         `evidence`) plus signing metadata (algorithm, kid, payload
    ///         signature). Implementations verify against their published
    ///         public key set (e.g., a JWKS endpoint mirrored on-chain).
    /// @dev    Use cases the on-chain oracle mode cannot serve: off-chain
    ///         orchestrators, chains without a deployed oracle, and
    ///         point-in-time evidence snapshots for dispute resolution.
    function verifyAttestation(
        address addrA,
        address addrB,
        bytes calldata attestation
    ) external view returns (
        bool independent,
        uint8 confidence,
        bytes memory evidence
    );
}
