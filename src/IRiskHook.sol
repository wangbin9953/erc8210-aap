// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAAP} from "./IAAP.sol";

/// @title IRiskHook — Optional Extension (ERC-8210 v2 改动 11)
/// @notice Pluggable hook that recommends a `committedAmount` for an Agent's
///         JobAssurance. Implementations MAY consult Agent reputation, on-chain
///         independence signals between the Beneficiary and the Assured Agent,
///         pre-commitment eligibility facts (e.g., staking status, AML
///         screening), or any combination thereof.
///
/// @dev This is a v2 DRAFT interface. The single-output method is preserved
///      from v1 for backward compatibility; the two-output method is the
///      "evidence + score" composition pattern formalised in v2 (Evidence-First
///      Composability Principle, 改动 12). Implementations MAY return only the
///      single-output form, in which case `evidenceRef` is conceptually
///      `bytes32(0)`.
///
///      Pending co-author review: the final composition story between
///      IRiskHook and IIndependenceSignal (see src/IIndependenceSignal.sol)
///      is not locked in. This file ships the contract surface so reference
///      implementations and integration examples can begin.
interface IRiskHook {

    /// @notice Backward-compatible v1 surface: recommend a committedAmount only.
    /// @param assuredAgent The Agent that will post the assurance.
    /// @param beneficiary The Beneficiary the assurance protects.
    /// @param jobId       The ERC-8183 Job identifier the assurance binds to.
    /// @param coverageType The coverage type being committed against.
    /// @return amount A recommended committedAmount, in settlementAsset units.
    function computeRecommendedAmount(
        address assuredAgent,
        address beneficiary,
        bytes32 jobId,
        IAAP.CoverageType coverageType
    ) external view returns (uint256 amount);

    /// @notice v2 "evidence + score" surface. Same recommendation, plus an
    ///         opaque evidence reference (IPFS CID, on-chain attestation
    ///         pointer, multi-attestation envelope identifier, etc.) that
    ///         downstream consumers can dereference for verification context.
    /// @dev    `evidenceRef` MAY be `bytes32(0)` when the implementation has
    ///         no evidence to publish; consumers MUST treat zero as "no
    ///         evidence available" rather than as a valid reference.
    function computeRecommendedAmountWithEvidence(
        address assuredAgent,
        address beneficiary,
        bytes32 jobId,
        IAAP.CoverageType coverageType
    ) external view returns (uint256 amount, bytes32 evidenceRef);
}
