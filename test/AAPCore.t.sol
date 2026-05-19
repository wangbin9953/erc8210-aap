// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AAPCore} from "../src/AAPCore.sol";
import {MockERC8183} from "../src/MockERC8183.sol";
import {IAAP} from "../src/IAAP.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AAPCoreTest is Test {

    AAPCore    public aap;
    MockERC8183 public jobs;
    ERC20Mock  public usdc;

    address public agent     = makeAddr("agent");
    address public beneficiary = makeAddr("beneficiary");
    address public resolver  = makeAddr("resolver");
    address public evaluator = makeAddr("evaluator");

    bytes32 public constant JOB_ID = keccak256("job-001");

    uint256 constant DEPOSIT = 1000e6;  // 1000 USDC (6 decimals)
    uint256 constant COMMIT  = 100e6;   // 100 USDC
    uint64  constant EXPIRY  = type(uint64).max; // far future

    function setUp() public {
        usdc = new ERC20Mock();
        jobs = new MockERC8183();
        aap  = new AAPCore(address(usdc), address(jobs), resolver);

        // Fund agent with USDC and approve AAP
        usdc.mint(agent, DEPOSIT * 10);
        vm.prank(agent);
        usdc.approve(address(aap), type(uint256).max);

        // Create a fresh job for each test
        jobs.createJob(JOB_ID, beneficiary, agent, evaluator);
    }

    // ─────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────

    function _deposit() internal returns (bytes32) {
        vm.prank(agent);
        aap.depositAssurance(DEPOSIT);
        return JOB_ID;
    }

    function _commit(bytes32 jobId) internal returns (bytes32 assuranceId) {
        vm.prank(agent);
        assuranceId = aap.commitToJob(jobId, IAAP.CoverageType.JobFailure, beneficiary, COMMIT, EXPIRY);
    }

    function _depositAndCommit() internal returns (bytes32 assuranceId) {
        _deposit();
        assuranceId = _commit(JOB_ID);
    }

    function _fileClaim(bytes32 assuranceId) internal returns (bytes32 claimId) {
        vm.prank(beneficiary);
        // v2 改动 17B: pass zero for the three optional composition fields.
        claimId = aap.fileClaim(assuranceId, COMMIT, bytes32(0), bytes32(0), bytes32(0), "");
    }

    function _assertInvariant() internal view {
        IAAP.AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(
            acct.totalFunded,
            acct.availableAmount + acct.lockedAmount + acct.paidOutAmount,
            "INVARIANT: totalFunded != available + locked + paidOut"
        );
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 1: Full happy path (assurance path)
    // depositAssurance → commitToJob → job completes → releaseCommitment
    // ─────────────────────────────────────────────────────────────────
    function test_01_HappyPathAssurance() public {
        bytes32 assuranceId = _depositAndCommit();

        // Complete the job
        jobs.completeJob(JOB_ID);

        vm.prank(agent);
        aap.releaseCommitment(assuranceId);

        IAAP.JobAssurance memory ja = aap.getJobAssurance(assuranceId);
        assertEq(uint8(ja.state), uint8(IAAP.AssuranceState.Released));

        IAAP.AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, DEPOSIT);   // committedAmount returned
        assertEq(acct.lockedAmount, 0);

        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 2: Full happy path (claims path)
    // depositAssurance → commitToJob → job fails → fileClaim → resolveClaim(approved) → payout
    // ─────────────────────────────────────────────────────────────────
    function test_02_HappyPathClaims() public {
        bytes32 assuranceId = _depositAndCommit();

        // Job rejected (provider non-performance)
        jobs.rejectJob(JOB_ID);

        bytes32 claimId = _fileClaim(assuranceId);

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, COMMIT, "");

        aap.payout(claimId);

        IAAP.Claim memory claim = aap.getClaim(claimId);
        assertEq(uint8(claim.state), uint8(IAAP.ClaimState.Paid));

        IAAP.JobAssurance memory ja = aap.getJobAssurance(assuranceId);
        assertEq(uint8(ja.state), uint8(IAAP.AssuranceState.Paid));

        // approvedAmount debited from lockedAmount and credited to paidOutAmount
        IAAP.AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.paidOutAmount, COMMIT);
        assertEq(acct.lockedAmount, 0);
        assertEq(usdc.balanceOf(beneficiary), COMMIT);

        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 3: Denial path
    // fileClaim → resolveClaim(denied) → JobAssurance reverts to Active
    // subsequent fileClaim MUST revert (claimId retained)
    // new commitToJob for same (jobId, coverageType) MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_03_DenialPath() public {
        bytes32 assuranceId = _depositAndCommit();
        jobs.rejectJob(JOB_ID);
        bytes32 claimId = _fileClaim(assuranceId);

        vm.prank(resolver);
        aap.resolveClaim(claimId, false, 0, "");

        // JobAssurance reverts to Active
        IAAP.JobAssurance memory ja = aap.getJobAssurance(assuranceId);
        assertEq(uint8(ja.state), uint8(IAAP.AssuranceState.Active));

        // Claim is Denied
        IAAP.Claim memory claim = aap.getClaim(claimId);
        assertEq(uint8(claim.state), uint8(IAAP.ClaimState.Denied));

        // claimId retained (not cleared)
        assertNotEq(ja.claimId, bytes32(0));

        // committedAmount still in lockedAmount
        IAAP.AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.lockedAmount, COMMIT);

        // Second fileClaim against same JobAssurance MUST revert
        vm.prank(beneficiary);
        vm.expectRevert("AAP: claim already filed");
        aap.fileClaim(assuranceId, COMMIT, bytes32(0), bytes32(0), bytes32(0), "");

        // New commitToJob for same (jobId, coverageType) MUST revert while prior is Active.
        // Since job is already Rejected, adverse-selection check fires first (v2 改动 5 custom error).
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IAAP.AdverseSelectionBlocked.selector, JOB_ID));
        aap.commitToJob(JOB_ID, IAAP.CoverageType.JobFailure, beneficiary, COMMIT, EXPIRY);

        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 4: Expiry path
    // commitToJob → time exceeds expiry → expireCommitment → Expired; funds returned
    // ─────────────────────────────────────────────────────────────────
    function test_04_ExpiryPath() public {
        _deposit();
        uint64 shortExpiry = uint64(block.timestamp + 1 hours);

        vm.prank(agent);
        bytes32 assuranceId = aap.commitToJob(JOB_ID, IAAP.CoverageType.JobFailure, beneficiary, COMMIT, shortExpiry);

        // Advance time past expiry
        vm.warp(block.timestamp + 2 hours);

        aap.expireCommitment(assuranceId);

        IAAP.JobAssurance memory ja = aap.getJobAssurance(assuranceId);
        assertEq(uint8(ja.state), uint8(IAAP.AssuranceState.Expired));

        IAAP.AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, DEPOSIT);   // funds returned
        assertEq(acct.lockedAmount, 0);

        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 5: Premature expiry MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_05_PrematureExpiryReverts() public {
        bytes32 assuranceId = _depositAndCommit();

        vm.expectRevert("AAP: not yet expired");
        aap.expireCommitment(assuranceId);
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 6: Insolvency — payout reverts when lockedAmount is insufficient
    // ─────────────────────────────────────────────────────────────────
    function test_06_InsolvencyPayoutReverts() public {
        bytes32 assuranceId = _depositAndCommit();
        jobs.rejectJob(JOB_ID);
        bytes32 claimId = _fileClaim(assuranceId);

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, COMMIT, "");

        // Drain lockedAmount by direct manipulation (simulate external slashing)
        // We achieve this by having the agent withdraw all available and then...
        // Actually, in a base impl lockedAmount is never < approvedAmount.
        // To force the revert, we manipulate storage directly via vm.store.
        // lockedAmount slot: find it in AAPCore layout.
        // For simplicity, we use a crafted scenario: approve more than locked.
        // Instead: create a second assurance, drain available, then manipulate storage.
        // Use vm.store to set lockedAmount to 0 directly for this test.
        bytes32 accountSlot = keccak256(abi.encode(agent, uint256(0))); // _accounts mapping slot 0
        // lockedAmount is offset 4 in AssuranceAccount struct
        bytes32 lockedSlot = bytes32(uint256(accountSlot) + 4);
        vm.store(address(aap), lockedSlot, bytes32(0));

        vm.expectRevert("AAP: insufficient lockedAmount");
        aap.payout(claimId);
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 7: Withdrawal boundary
    // withdrawAvailableAssurance succeeds up to availableAmount;
    // attempting to exceed it MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_07_WithdrawalBoundary() public {
        _depositAndCommit(); // lockedAmount = COMMIT, availableAmount = DEPOSIT - COMMIT

        IAAP.AssuranceAccount memory acct = aap.getAssuranceAccount(agent);
        uint256 available = acct.availableAmount;

        // Withdraw exactly available — should succeed
        vm.prank(agent);
        aap.withdrawAvailableAssurance(available);

        acct = aap.getAssuranceAccount(agent);
        assertEq(acct.availableAmount, 0);

        // Withdraw 1 more — should revert
        vm.prank(agent);
        vm.expectRevert("AAP: exceeds availableAmount");
        aap.withdrawAvailableAssurance(1);

        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 8: Invalid state transitions
    // Filing a Claim against non-Active MUST revert
    // payout on non-Approved Claim MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_08_InvalidStateTransitions() public {
        bytes32 assuranceId = _depositAndCommit();
        jobs.rejectJob(JOB_ID);
        bytes32 claimId = _fileClaim(assuranceId);

        // Assurance is now Claimed, not Active → second fileClaim MUST revert
        vm.prank(beneficiary);
        vm.expectRevert("AAP: assurance not Active");
        aap.fileClaim(assuranceId, COMMIT, bytes32(0), bytes32(0), bytes32(0), "");

        // Claim is Filed, not Approved → payout MUST revert
        vm.expectRevert("AAP: claim not Approved");
        aap.payout(claimId);
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 9: Eligibility gating
    // fileClaim MUST revert if job has NOT reached required terminal state
    // ─────────────────────────────────────────────────────────────────
    function test_09_EligibilityGating() public {
        bytes32 assuranceId = _depositAndCommit();
        // Job is still Active (not failed) → not eligible

        vm.prank(beneficiary);
        vm.expectRevert("AAP: eligibility condition not met");
        aap.fileClaim(assuranceId, COMMIT, bytes32(0), bytes32(0), bytes32(0), "");
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 10: Adverse selection
    // If coverage conditions already qualify, commitToJob MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_10_AdverseSelection() public {
        _deposit();

        // Fail the job BEFORE creating assurance
        jobs.rejectJob(JOB_ID);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IAAP.AdverseSelectionBlocked.selector, JOB_ID));
        aap.commitToJob(JOB_ID, IAAP.CoverageType.JobFailure, beneficiary, COMMIT, EXPIRY);
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 11: Duplicate commitment
    // Second commitToJob for same (jobId, coverageType) MUST revert while Active exists
    // ─────────────────────────────────────────────────────────────────
    function test_11_DuplicateCommitment() public {
        _depositAndCommit();

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAAP.DuplicateCommitment.selector,
                JOB_ID,
                IAAP.CoverageType.JobFailure
            )
        );
        aap.commitToJob(JOB_ID, IAAP.CoverageType.JobFailure, beneficiary, COMMIT, EXPIRY);
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 12: Amount validation
    // fileClaim with requestedAmount == 0 MUST revert
    // resolveClaim(approved) with approvedAmount == 0 MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_12_AmountValidation() public {
        bytes32 assuranceId = _depositAndCommit();
        jobs.rejectJob(JOB_ID);

        // requestedAmount == 0 → revert
        vm.prank(beneficiary);
        vm.expectRevert("AAP: requestedAmount is 0");
        aap.fileClaim(assuranceId, 0, bytes32(0), bytes32(0), bytes32(0), "");

        // Valid file
        bytes32 claimId = _fileClaim(assuranceId);

        // approvedAmount == 0 when approved == true → revert
        vm.prank(resolver);
        vm.expectRevert("AAP: approvedAmount must be > 0");
        aap.resolveClaim(claimId, true, 0, "");
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 13: Recusal rule enforcement
    // For EvaluatorDispute, resolver == ERC-8183 evaluator MUST revert
    // ─────────────────────────────────────────────────────────────────
    function test_13_RecusalRule() public {
        _deposit();

        // Create an EvaluatorDispute assurance
        vm.prank(agent);
        bytes32 assuranceId = aap.commitToJob(
            JOB_ID,
            IAAP.CoverageType.EvaluatorDispute,
            beneficiary,
            COMMIT,
            EXPIRY
        );

        // Set job to Disputed
        jobs.disputeJob(JOB_ID);

        bytes32 claimId = _fileClaim(assuranceId);

        // evaluator tries to resolve → must revert (recusal)
        aap.addResolver(evaluator);
        vm.prank(evaluator);
        vm.expectRevert("AAP: resolver is the job evaluator (recusal)");
        aap.resolveClaim(claimId, true, COMMIT, "");

        // A different resolver can resolve
        vm.prank(resolver);
        aap.resolveClaim(claimId, true, COMMIT, "");
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 14: Invariant verification
    // After every operation: totalFunded == availableAmount + lockedAmount + paidOutAmount
    // ─────────────────────────────────────────────────────────────────
    function test_14_InvariantVerification() public {
        // Deposit
        vm.prank(agent);
        aap.depositAssurance(DEPOSIT);
        _assertInvariant();

        // Commit
        vm.prank(agent);
        bytes32 assuranceId = aap.commitToJob(JOB_ID, IAAP.CoverageType.JobFailure, beneficiary, COMMIT, EXPIRY);
        _assertInvariant();

        // Partial withdraw of available
        vm.prank(agent);
        aap.withdrawAvailableAssurance(50e6);
        _assertInvariant();

        // Job fails → file claim
        jobs.rejectJob(JOB_ID);
        vm.prank(beneficiary);
        bytes32 claimId = aap.fileClaim(assuranceId, COMMIT, bytes32(0), bytes32(0), bytes32(0), "");
        _assertInvariant();

        // Resolve approved
        vm.prank(resolver);
        aap.resolveClaim(claimId, true, COMMIT, "");
        _assertInvariant();

        // Payout
        aap.payout(claimId);
        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 15: RoleCollusion CoverageType (v2 改动 10B)
    // Provider/Evaluator collusion attested post-completion by an external
    // independence layer → Beneficiary can file a RoleCollusion claim.
    // ─────────────────────────────────────────────────────────────────
    function test_15_RoleCollusionCoverageType() public {
        _deposit();

        // Commit to a RoleCollusion-typed assurance up front.
        vm.prank(agent);
        bytes32 assuranceId = aap.commitToJob(
            JOB_ID,
            IAAP.CoverageType.RoleCollusion,
            beneficiary,
            COMMIT,
            EXPIRY
        );

        // Job completes normally; collusion is only discovered afterwards.
        jobs.completeJob(JOB_ID);

        // Before the external attestation lands, the claim is not eligible.
        vm.prank(beneficiary);
        vm.expectRevert("AAP: eligibility condition not met");
        aap.fileClaim(assuranceId, COMMIT, bytes32(0), bytes32(0), bytes32(0), "");

        // External independence-signal layer attests collusion.
        jobs.markRoleCollusion(JOB_ID);

        // Now the Beneficiary can file and the standard claim path proceeds.
        bytes32 claimId = _fileClaim(assuranceId);

        vm.prank(resolver);
        aap.resolveClaim(claimId, true, COMMIT, "collusion-attestation-cid");

        aap.payout(claimId);

        IAAP.Claim memory claim = aap.getClaim(claimId);
        assertEq(uint8(claim.state), uint8(IAAP.ClaimState.Paid));
        assertEq(claim.reasonHash, keccak256("collusion-attestation-cid"));
        _assertInvariant();
    }

    // ─────────────────────────────────────────────────────────────────
    // Test 16: First-class composition fields are stored + indexable
    // (v2 改动 17B)
    // ─────────────────────────────────────────────────────────────────
    function test_16_FirstClassCompositionFields() public {
        bytes32 assuranceId = _depositAndCommit();
        jobs.rejectJob(JOB_ID);

        bytes32 upstream         = keccak256("upstream-claim-or-job");
        bytes32 reasoningCID     = keccak256("ipfs://reasoning");
        bytes32 slashEvidence    = keccak256("slash-record-hash");

        vm.prank(beneficiary);
        bytes32 claimId = aap.fileClaim(
            assuranceId,
            COMMIT,
            upstream,
            reasoningCID,
            slashEvidence,
            ""
        );

        IAAP.Claim memory claim = aap.getClaim(claimId);
        assertEq(claim.upstream, upstream);
        assertEq(claim.reasoningCID, reasoningCID);
        assertEq(claim.slashEvidenceHash, slashEvidence);
    }
}
