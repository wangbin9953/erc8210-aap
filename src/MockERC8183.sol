// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title MockERC8183
/// @notice Minimal mock of an ERC-8183 Job contract for IAAP integration testing.
///         Exposes job state and evaluator info so AAPCore can verify claim eligibility.
/// @dev FOR TESTING ONLY. All state transitions are permissionless by design.
///      DO NOT DEPLOY TO MAINNET OR ANY PRODUCTION ENVIRONMENT.
contract MockERC8183 {

    enum JobState {
        None,             // Job does not exist
        Active,           // Job in progress
        Completed,        // Successfully completed and settled (happy path)
        Rejected,         // Provider failed to deliver → JobFailure eligible
        Expired,          // Timed out without delivery → JobFailure eligible
        Disputed,         // Evaluator decision under dispute → EvaluatorDispute eligible
        SettlementFailed  // Valid completion but settlement blocked by provider → SettlementDefault eligible
    }

    struct Job {
        bytes32  jobId;
        address  client;
        address  provider;
        address  evaluator;
        JobState state;
    }

    mapping(bytes32 => Job) private _jobs;

    event JobCreated(bytes32 indexed jobId, address client, address provider, address evaluator);
    event JobStateChanged(bytes32 indexed jobId, JobState newState);

    // ─────────────────────────────────────────────────────────────────
    // Write functions (test helpers / simulation)
    // ─────────────────────────────────────────────────────────────────

    /// @notice Create a new job. In production this would be called by the commerce layer.
    function createJob(
        bytes32 jobId,
        address client,
        address provider,
        address evaluator
    ) external {
        require(_jobs[jobId].state == JobState.None, "ERC8183: job already exists");
        _jobs[jobId] = Job(jobId, client, provider, evaluator, JobState.Active);
        emit JobCreated(jobId, client, provider, evaluator);
    }

    /// @notice Transition job to Completed (successful delivery + settlement).
    function completeJob(bytes32 jobId) external {
        require(_jobs[jobId].state == JobState.Active, "ERC8183: job not Active");
        _jobs[jobId].state = JobState.Completed;
        emit JobStateChanged(jobId, JobState.Completed);
    }

    /// @notice Transition job to Rejected (provider failed to deliver).
    function rejectJob(bytes32 jobId) external {
        require(_jobs[jobId].state == JobState.Active, "ERC8183: job not Active");
        _jobs[jobId].state = JobState.Rejected;
        emit JobStateChanged(jobId, JobState.Rejected);
    }

    /// @notice Transition job to Expired (timeout without delivery).
    function expireJob(bytes32 jobId) external {
        require(_jobs[jobId].state == JobState.Active, "ERC8183: job not Active");
        _jobs[jobId].state = JobState.Expired;
        emit JobStateChanged(jobId, JobState.Expired);
    }

    /// @notice Transition job to Disputed (evaluator decision challenged).
    function disputeJob(bytes32 jobId) external {
        require(_jobs[jobId].state == JobState.Active, "ERC8183: job not Active");
        _jobs[jobId].state = JobState.Disputed;
        emit JobStateChanged(jobId, JobState.Disputed);
    }

    /// @notice Transition job to SettlementFailed (completed but provider blocked settlement).
    function failSettlement(bytes32 jobId) external {
        require(_jobs[jobId].state == JobState.Active, "ERC8183: job not Active");
        _jobs[jobId].state = JobState.SettlementFailed;
        emit JobStateChanged(jobId, JobState.SettlementFailed);
    }

    // ─────────────────────────────────────────────────────────────────
    // Read functions (consumed by AAPCore for eligibility checks)
    // ─────────────────────────────────────────────────────────────────

    function getJobState(bytes32 jobId) external view returns (JobState) {
        return _jobs[jobId].state;
    }

    function getJobEvaluator(bytes32 jobId) external view returns (address) {
        return _jobs[jobId].evaluator;
    }

    function getJob(bytes32 jobId) external view returns (Job memory) {
        return _jobs[jobId];
    }

    /// @notice Returns true if the job is in a successful terminal state (allows releaseCommitment).
    function isSuccessfullyCompleted(bytes32 jobId) external view returns (bool) {
        return _jobs[jobId].state == JobState.Completed;
    }

    /// @notice Returns true if the job has reached a claimable terminal state for the given coverage type.
    function isClaimEligible(bytes32 jobId, uint8 coverageType) external view returns (bool) {
        JobState s = _jobs[jobId].state;
        if (coverageType == 0) {
            // JobFailure: Rejected or Expired
            return s == JobState.Rejected || s == JobState.Expired;
        } else if (coverageType == 1) {
            // EvaluatorDispute: Disputed
            return s == JobState.Disputed;
        } else if (coverageType == 2) {
            // SettlementDefault: SettlementFailed
            return s == JobState.SettlementFailed;
        }
        return false;
    }
}
