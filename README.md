# ERC-8210: Agent Assurance Protocol : Reference Implementation

A minimal Solidity reference implementation of [ERC-8210](https://github.com/ethereum/ERCs/pull/1632) (Agent Assurance Protocol), a programmable fulfillment assurance primitive for autonomous agent commerce built on ERC-8183.

## Overview

ERC-8210 introduces three core primitives:

| Primitive | Description |
|-----------|-------------|
| **AssuranceAccount** | Per-agent reserve of self-funded collateral |
| **JobAssurance** | Commitment allocation against a specific ERC-8183 Job |
| **Claim** | Payout request filed by the Beneficiary when coverage conditions are met |

AAP is a **self-funded collateral model** where each Assured Agent locks its own capital as a fulfillment guarantee. Payouts come from the agent's own AssuranceAccount, not from pooled liquidity.

## Architecture

```
src/
├── IAAP.sol          # Core interface: all structs, enums, events, and function signatures
├── AAPCore.sol       # Reference implementation of IAAP
└── MockERC8183.sol   # Mock ERC-8183 job contract for eligibility verification

test/
└── AAPCore.t.sol     # 14 test cases covering all spec scenarios

script/
└── Deploy.s.sol      # Deployment script targeting Base Sepolia + USDC
```

## Coverage Types

```solidity
enum CoverageType {
    JobFailure,        // Provider non-performance (job rejected or expired)
    EvaluatorDispute,  // Evaluator decision challenged
    SettlementDefault, // Fund release failure after valid completion
    AMLFreeze,         // Extension-reserved (optional)
    SlashingLoss       // Extension-reserved (optional)
}
```

## State Machines

**AssuranceAccount:** `Active <-> Paused`

**JobAssurance:**
```
Active  -> Claimed  (fileClaim)
Active  -> Released (releaseCommitment, job successfully completed)
Active  -> Expired  (expireCommitment, past expiry timestamp)
Claimed -> Paid     (payout, after claim approved)
Claimed -> Active   (resolveClaim denied, claimId retained as audit trail)
```

**Claim:**
```
None -> Filed -> Approved -> Paid
              -> Denied
```

## Core Invariant

After every state-mutating operation:

```
totalFunded == availableAmount + lockedAmount + paidOutAmount
```

## Getting Started

### Prerequisites

Install [Foundry](https://book.getfoundry.sh/getting-started/installation):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Install dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-git
```

### Build

```bash
forge build
```

### Test

```bash
forge test -v
```

All 14 test cases pass:

```
[PASS] test_01_HappyPathAssurance
[PASS] test_02_HappyPathClaims
[PASS] test_03_DenialPath
[PASS] test_04_ExpiryPath
[PASS] test_05_PrematureExpiryReverts
[PASS] test_06_InsolvencyPayoutReverts
[PASS] test_07_WithdrawalBoundary
[PASS] test_08_InvalidStateTransitions
[PASS] test_09_EligibilityGating
[PASS] test_10_AdverseSelection
[PASS] test_11_DuplicateCommitment
[PASS] test_12_AmountValidation
[PASS] test_13_RecusalRule
[PASS] test_14_InvariantVerification
```

### Deploy to Base Sepolia

```bash
PRIVATE_KEY=<your_key> RESOLVER_ADDR=<resolver_address> \
  forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

Settlement asset: USDC on Base Sepolia (`0x036CbD53842c5426634e7929541eC2318f3dCF7e`)

## ERC Specification

- ERC-8210 PR: https://github.com/ethereum/ERCs/pull/1632
- Requires: ERC-8183, ERC-20
- Optionally integrates: ERC-8004 (identity and reputation)

## License

CC0-1.0
