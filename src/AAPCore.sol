// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAAP} from "./IAAP.sol";
import {MockERC8183} from "./MockERC8183.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AAPCore — Minimal reference implementation of ERC-1632 Agent Assurance Protocol
contract AAPCore is IAAP {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────
    // Immutables
    // ─────────────────────────────────────────────────────────────────

    IERC20 public immutable settlementAsset;
    MockERC8183 public immutable erc8183;

    // ─────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────

    mapping(address => AssuranceAccount) private _accounts;
    mapping(bytes32 => JobAssurance)     private _assurances;
    mapping(bytes32 => Claim)            private _claims;
    mapping(address => bool)             private _resolvers;

    // Per-agent nonce for collision-resistant ID generation
    mapping(address => uint256) private _assuranceNonce;
    uint256 private _claimNonce;

    // ─────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────

    constructor(address _settlementAsset, address _erc8183, address _initialResolver) {
        require(_settlementAsset != address(0), "AAP: zero asset");
        require(_erc8183 != address(0), "AAP: zero erc8183");
        require(_initialResolver != address(0), "AAP: zero resolver");
        settlementAsset = IERC20(_settlementAsset);
        erc8183 = MockERC8183(_erc8183);
        _resolvers[_initialResolver] = true;
    }

    // ─────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────

    modifier onlyResolver() {
        require(_resolvers[msg.sender], "AAP: caller is not a resolver");
        _;
    }

    // ─────────────────────────────────────────────────────────────────
    // Resolver management (minimal, no governance)
    // ─────────────────────────────────────────────────────────────────

    function addResolver(address resolver) external {
        // In production this should be access-controlled (owner/DAO).
        // For the reference implementation we keep it open so tests can set up resolvers freely.
        require(resolver != address(0), "AAP: zero resolver");
        _resolvers[resolver] = true;
    }

    function isResolver(address resolver) external view returns (bool) {
        return _resolvers[resolver];
    }

    // ─────────────────────────────────────────────────────────────────
    // AssuranceAccount lifecycle
    // ─────────────────────────────────────────────────────────────────

    function depositAssurance(uint256 amount) external override {
        require(amount > 0, "AAP: amount is 0");
        AssuranceAccount storage acct = _accounts[msg.sender];

        if (acct.agent == address(0)) {
            // First deposit: create account
            acct.agent = msg.sender;
            acct.settlementAsset = address(settlementAsset);
            acct.status = AccountStatus.Active;
        }

        require(acct.status == AccountStatus.Active, "AAP: account is Paused");

        settlementAsset.safeTransferFrom(msg.sender, address(this), amount);
        acct.totalFunded += amount;
        acct.availableAmount += amount;

        emit AssuranceDeposited(msg.sender, amount, acct.availableAmount);
        _assertInvariant(msg.sender);
    }

    function withdrawAvailableAssurance(uint256 amount) external override {
        AssuranceAccount storage acct = _accounts[msg.sender];
        require(acct.agent != address(0), "AAP: no account");
        require(acct.status == AccountStatus.Active, "AAP: account is Paused");

        uint256 withdrawAmt = (amount == type(uint256).max) ? acct.availableAmount : amount;
        require(withdrawAmt > 0, "AAP: nothing to withdraw");
        require(withdrawAmt <= acct.availableAmount, "AAP: exceeds availableAmount");

        // Checks-effects-interactions
        acct.availableAmount -= withdrawAmt;
        acct.totalFunded     -= withdrawAmt;

        settlementAsset.safeTransfer(msg.sender, withdrawAmt);

        emit AssuranceWithdrawn(msg.sender, withdrawAmt, acct.availableAmount);
        _assertInvariant(msg.sender);
    }

    function getAssuranceAccount(address agent) external view override returns (AssuranceAccount memory) {
        return _accounts[agent];
    }

    // ─────────────────────────────────────────────────────────────────
    // JobAssurance lifecycle
    // ─────────────────────────────────────────────────────────────────

    function commitToJob(
        bytes32 jobId,
        CoverageType coverageType,
        address beneficiary,
        uint256 amount,
        uint64 expiry
    ) external override returns (bytes32 assuranceId) {
        require(coverageType <= CoverageType.SettlementDefault, "AAP: unsupported coverage type");
        require(amount > 0, "AAP: amount is 0");
        require(beneficiary != address(0), "AAP: zero beneficiary");
        require(expiry > block.timestamp, "AAP: expiry in the past");

        AssuranceAccount storage acct = _accounts[msg.sender];
        require(acct.agent != address(0), "AAP: no account");
        // v2 改动 5: typed custom errors so off-chain orchestrators can branch on reason.
        if (acct.status != AccountStatus.Active) revert AccountNotActive(msg.sender);
        if (acct.availableAmount < amount) {
            revert InsufficientAvailableAmount(acct.availableAmount, amount);
        }

        // Adverse selection check: coverage condition must NOT already be met
        if (erc8183.isClaimEligible(jobId, uint8(coverageType))) {
            revert AdverseSelectionBlocked(jobId);
        }

        // Duplicate commitment check: no Active or Claimed assurance for same (jobId, coverageType)
        bytes32 dedupKey = keccak256(abi.encodePacked(msg.sender, jobId, coverageType));
        if (_activeDedupKeys[dedupKey]) revert DuplicateCommitment(jobId, coverageType);

        // Generate collision-resistant assuranceId
        assuranceId = keccak256(abi.encodePacked(
            "AAP_ASSURANCE",
            msg.sender,
            jobId,
            uint8(coverageType),
            _assuranceNonce[msg.sender]++
        ));

        // Reserve funds
        acct.availableAmount -= amount;
        acct.lockedAmount    += amount;

        _assurances[assuranceId] = JobAssurance({
            assuranceId:     assuranceId,
            assuredAgent:    msg.sender,
            beneficiary:     beneficiary,
            coveredJob:      jobId,
            coverageType:    coverageType,
            committedAmount: amount,
            expiry:          expiry,
            chainId:         block.chainid,
            claimId:         bytes32(0),
            state:           AssuranceState.Active
        });

        _activeDedupKeys[dedupKey] = true;

        emit AssuranceCommitted(assuranceId, msg.sender, jobId, beneficiary, coverageType, amount, expiry);
        _assertInvariant(msg.sender);
    }

    function releaseCommitment(bytes32 assuranceId) external override {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.assuredAgent == msg.sender, "AAP: not assuredAgent");
        require(ja.state == AssuranceState.Active, "AAP: not Active");

        // Job must be in a successful terminal state
        require(erc8183.isSuccessfullyCompleted(ja.coveredJob), "AAP: job not successfully completed");

        uint256 amt = ja.committedAmount;
        AssuranceAccount storage acct = _accounts[msg.sender];
        acct.lockedAmount    -= amt;
        acct.availableAmount += amt;
        ja.state = AssuranceState.Released;

        _clearDedupKey(ja);

        emit AssuranceReleased(assuranceId, msg.sender, amt);
        _assertInvariant(msg.sender);
    }

    function expireCommitment(bytes32 assuranceId) external override {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.state == AssuranceState.Active, "AAP: not Active");
        require(block.timestamp > ja.expiry, "AAP: not yet expired");

        uint256 amt = ja.committedAmount;
        AssuranceAccount storage acct = _accounts[ja.assuredAgent];
        acct.lockedAmount    -= amt;
        acct.availableAmount += amt;
        ja.state = AssuranceState.Expired;

        _clearDedupKey(ja);

        emit AssuranceExpired(assuranceId);
        _assertInvariant(ja.assuredAgent);
    }

    function getJobAssurance(bytes32 assuranceId) external view override returns (JobAssurance memory) {
        return _assurances[assuranceId];
    }

    // ─────────────────────────────────────────────────────────────────
    // Claim lifecycle
    // ─────────────────────────────────────────────────────────────────

    function fileClaim(
        bytes32 assuranceId,
        uint256 requestedAmount,
        bytes calldata /*evidence*/
    ) external override returns (bytes32 claimId) {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.state == AssuranceState.Active, "AAP: assurance not Active");
        require(ja.beneficiary == msg.sender, "AAP: caller is not beneficiary");
        require(ja.claimId == bytes32(0), "AAP: claim already filed");
        require(requestedAmount > 0, "AAP: requestedAmount is 0");
        require(requestedAmount <= ja.committedAmount, "AAP: exceeds committedAmount");

        // Eligibility check: coverage condition must be met on-chain
        require(
            erc8183.isClaimEligible(ja.coveredJob, uint8(ja.coverageType)),
            "AAP: eligibility condition not met"
        );

        // Recusal check for EvaluatorDispute: resolver ≠ evaluator enforced at resolveClaim

        // Generate claimId
        claimId = keccak256(abi.encodePacked(
            "AAP_CLAIM",
            assuranceId,
            _claimNonce++
        ));

        // Transition: JobAssurance Active → Claimed
        ja.state   = AssuranceState.Claimed;
        ja.claimId = claimId;

        _claims[claimId] = Claim({
            claimId:         claimId,
            assuranceId:     assuranceId,
            beneficiary:     msg.sender,
            requestedAmount: requestedAmount,
            approvedAmount:  0,
            state:           ClaimState.Filed,
            filedAt:         uint64(block.timestamp),
            resolvedAt:      0,
            reasonHash:      bytes32(0)   // v2 改动 8: set at resolveClaim
        });

        emit ClaimFiled(claimId, assuranceId, msg.sender, requestedAmount);
    }

    function resolveClaim(
        bytes32 claimId,
        bool approved,
        uint256 approvedAmount,
        bytes calldata reason
    ) external override onlyResolver {
        Claim storage claim = _claims[claimId];
        require(claim.state == ClaimState.Filed, "AAP: claim not in Filed state");

        JobAssurance storage ja = _assurances[claim.assuranceId];

        // Recusal rule: for EvaluatorDispute, the ERC-8183 evaluator cannot be the resolver
        if (ja.coverageType == CoverageType.EvaluatorDispute) {
            address evaluator = erc8183.getJobEvaluator(ja.coveredJob);
            require(msg.sender != evaluator, "AAP: resolver is the job evaluator (recusal)");
        }

        claim.resolvedAt = uint64(block.timestamp);
        // v2 改动 8: store keccak256(reason); raw bytes flow via the event for indexers.
        claim.reasonHash = keccak256(reason);

        if (approved) {
            require(approvedAmount > 0, "AAP: approvedAmount must be > 0");
            require(approvedAmount <= claim.requestedAmount, "AAP: approvedAmount exceeds requested");
            claim.approvedAmount = approvedAmount;
            claim.state = ClaimState.Approved;
            // JobAssurance stays Claimed until payout()
        } else {
            // Denial: revert JobAssurance to Active, retain claimId as audit trail
            claim.approvedAmount = 0;
            claim.state = ClaimState.Denied;
            ja.state = AssuranceState.Active;
            // claimId intentionally NOT cleared (prevents duplicate filing)
        }

        emit ClaimResolved(claimId, claim.assuranceId, approved, claim.approvedAmount, msg.sender, reason);
    }

    function payout(bytes32 claimId) external override {
        Claim storage claim = _claims[claimId];
        require(claim.state == ClaimState.Approved, "AAP: claim not Approved");

        JobAssurance storage ja = _assurances[claim.assuranceId];
        AssuranceAccount storage acct = _accounts[ja.assuredAgent];

        uint256 amt = claim.approvedAmount;
        require(acct.lockedAmount >= amt, "AAP: insufficient lockedAmount");

        // Checks-effects-interactions
        acct.lockedAmount  -= amt;
        acct.paidOutAmount += amt;
        claim.state = ClaimState.Paid;
        ja.state    = AssuranceState.Paid;

        _clearDedupKey(ja);

        settlementAsset.safeTransfer(claim.beneficiary, amt);

        emit ClaimPaid(claimId, claim.assuranceId, claim.beneficiary, amt);
        _assertInvariant(ja.assuredAgent);
    }

    function getClaim(bytes32 claimId) external view override returns (Claim memory) {
        return _claims[claimId];
    }

    // ─────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────

    // Dedup key tracking: (assuredAgent, jobId, coverageType) must be unique for Active/Claimed assurances
    mapping(bytes32 => bool) private _activeDedupKeys;

    function _clearDedupKey(JobAssurance storage ja) internal {
        bytes32 dedupKey = keccak256(abi.encodePacked(
            ja.assuredAgent,
            ja.coveredJob,
            ja.coverageType
        ));
        _activeDedupKeys[dedupKey] = false;
    }

    /// @dev Asserts the core accounting invariant. Should never revert in a correct implementation.
    function _assertInvariant(address agent) internal view {
        AssuranceAccount storage acct = _accounts[agent];
        if (acct.agent != address(0)) {
            assert(acct.totalFunded == acct.availableAmount + acct.lockedAmount + acct.paidOutAmount);
        }
    }
}
