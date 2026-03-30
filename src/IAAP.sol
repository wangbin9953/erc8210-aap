// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAAP — Agent Assurance Protocol Core Interface (ERC-1632)
interface IAAP {

    // ─────────────────────────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────────────────────────

    enum CoverageType {
        JobFailure,        // Provider non-performance; Job reached rejected/expired terminal state
        EvaluatorDispute,  // Evaluator decision challenged
        SettlementDefault, // Fund release failure after valid completion, attributable to Assured Agent
        AMLFreeze,         // Extension-reserved: AML freeze (optional)
        SlashingLoss       // Extension-reserved: external slashing (optional)
    }

    enum AccountStatus {
        Active,  // Deposits, withdrawals, and commitments are permitted
        Paused   // New commitments and withdrawals are not permitted
    }

    enum AssuranceState {
        Active,   // Commitment in effect; committedAmount reserved from availableAmount
        Claimed,  // A Claim has been filed; awaiting resolution
        Paid,     // Claim approved and payout completed
        Released, // Job completed successfully; committedAmount returned to availableAmount
        Expired   // Expired without a claim; committedAmount returned to availableAmount
    }

    enum ClaimState {
        None,        // Storage sentinel; not a lifecycle state
        Filed,       // Claim filed; awaiting resolution
        Challenged,  // Optional: resolution challenged
        Approved,    // Claim approved; awaiting settlement
        Denied,      // Claim denied
        Paid         // Payout completed
    }

    // ─────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────

    struct AssuranceAccount {
        address agent;
        address settlementAsset;
        uint256 totalFunded;      // Cumulative net inflow (deposits minus withdrawals)
        uint256 availableAmount;  // Available for new commitments or withdrawal
        uint256 lockedAmount;     // Reserved for active JobAssurances (not withdrawable)
        uint256 paidOutAmount;    // Cumulative amount paid to Beneficiaries
        AccountStatus status;
    }

    struct JobAssurance {
        bytes32      assuranceId;
        address      assuredAgent;
        address      beneficiary;     // Immutable once set
        bytes32      coveredJob;      // ERC-8183 jobId
        CoverageType coverageType;
        uint256      committedAmount;
        uint64       expiry;
        uint256      chainId;         // Must equal block.chainid in this version
        bytes32      claimId;         // bytes32(0) when no Claim filed
        AssuranceState state;
    }

    struct Claim {
        bytes32    claimId;
        bytes32    assuranceId;
        address    beneficiary;
        uint256    requestedAmount;
        uint256    approvedAmount;    // 0 if denied
        ClaimState state;
        uint64     filedAt;
        uint64     resolvedAt;        // 0 while pending
    }

    // ─────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────

    // AssuranceAccount events
    event AssuranceDeposited(address indexed agent, uint256 amount, uint256 newAvailableAmount);
    event AssuranceWithdrawn(address indexed agent, uint256 amount, uint256 newAvailableAmount);
    event AccountStatusChanged(address indexed agent, AccountStatus newStatus);

    // JobAssurance events
    event AssuranceCommitted(
        bytes32 indexed assuranceId,
        address indexed assuredAgent,
        bytes32 jobId,
        address indexed beneficiary,
        CoverageType coverageType,
        uint256 committedAmount,
        uint64 expiry
    );
    event AssuranceReleased(bytes32 indexed assuranceId, address indexed assuredAgent, uint256 releasedAmount);
    event AssuranceExpired(bytes32 indexed assuranceId);

    // Claim events
    event ClaimFiled(
        bytes32 indexed claimId,
        bytes32 indexed assuranceId,
        address indexed beneficiary,
        uint256 requestedAmount
    );
    event ClaimResolved(
        bytes32 indexed claimId,
        bytes32 indexed assuranceId,
        bool approved,
        uint256 approvedAmount,
        address indexed resolver
    );
    event ClaimPaid(
        bytes32 indexed claimId,
        bytes32 indexed assuranceId,
        address indexed beneficiary,
        uint256 amount
    );

    // ─────────────────────────────────────────────────────────────────
    // AssuranceAccount lifecycle
    // ─────────────────────────────────────────────────────────────────

    /// @notice Deposit collateral to register or top up an AssuranceAccount.
    function depositAssurance(uint256 amount) external;

    /// @notice Withdraw available balance. Pass type(uint256).max to withdraw all.
    function withdrawAvailableAssurance(uint256 amount) external;

    /// @notice Query AssuranceAccount for a given agent.
    function getAssuranceAccount(address agent) external view returns (AssuranceAccount memory);

    // ─────────────────────────────────────────────────────────────────
    // JobAssurance lifecycle
    // ─────────────────────────────────────────────────────────────────

    /// @notice Create an assurance commitment for a specific Job.
    function commitToJob(
        bytes32 jobId,
        CoverageType coverageType,
        address beneficiary,
        uint256 amount,
        uint64 expiry
    ) external returns (bytes32 assuranceId);

    /// @notice Release the commitment after successful Job completion.
    function releaseCommitment(bytes32 assuranceId) external;

    /// @notice Expire a JobAssurance that has exceeded its expiry timestamp. Permissionless.
    function expireCommitment(bytes32 assuranceId) external;

    /// @notice Query a JobAssurance by its identifier.
    function getJobAssurance(bytes32 assuranceId) external view returns (JobAssurance memory);

    // ─────────────────────────────────────────────────────────────────
    // Claim lifecycle
    // ─────────────────────────────────────────────────────────────────

    /// @notice File a Claim against an Active JobAssurance.
    function fileClaim(
        bytes32 assuranceId,
        uint256 requestedAmount,
        bytes calldata evidence
    ) external returns (bytes32 claimId);

    /// @notice Resolve a pending Claim (caller must be authorized Claims Resolver).
    function resolveClaim(
        bytes32 claimId,
        bool approved,
        uint256 approvedAmount,
        bytes calldata reason
    ) external;

    /// @notice Settle an approved Claim. Permissionless.
    function payout(bytes32 claimId) external;

    /// @notice Query a Claim by its identifier.
    function getClaim(bytes32 claimId) external view returns (Claim memory);
}
