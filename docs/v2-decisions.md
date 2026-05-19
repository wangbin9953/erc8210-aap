# ERC-8210 v2 改动清单 — 参考实现侧

跟踪 v2 修改清单里 17 条改动在参考实现 repo (`wangbin9953/erc8210-aap`) 的落地状态。

> 流程约束：spec PR (`ethereum/ERCs#1632`) v1 必须先被 EIP editor merge 进 Draft 状态后才能开始 v2 spec 工作。参考实现 repo 是分离的，可在 `v2-draft` 分支上提前推进。

---

## 状态图例

- ✅ 已落地（在 `v2-draft` 分支）
- 📝 纯 spec 文本改动，参考实现无对应代码（等 v1 merge）
- ⏸ 待定（pending 决策或外部输入）
- ❌ 不进入 v2

---

## 改动 1 — Inherited Assumptions 章节
- **位置：** Rationale 段末尾，新增独立小节
- **类型：** 📝 纯 spec 文本
- **决策点：** 无（直接撰写）
- **时机：** v1 merge 之后

## 改动 2 — 扩展 EvaluatorDispute eligibility
- **位置：** Specification 段 "Integration with ERC-8183" 小节
- **类型：** 📝 纯 spec 文本（参考实现的 eligibility 条件由 MockERC8183 驱动，跟改动 2 解耦）
- **决策点：** 宽限期长度（建议 ≥ 7 天）
- **时机：** v1 merge 之后

## 改动 3 — IRiskHook 独立性检查 use case
- **位置：** Optional Extensions 段 IRiskHook 小节
- **类型：** 📝 纯 spec 文本
- **决策点：** 是否在 spec 里直接 reference `assessIndependence(addrA, addrB)` 形态
- **时机：** v1 merge 之后

## 改动 4 — Role Independence Assumption (Security Considerations)
- **位置：** Security Considerations 段
- **类型：** 📝 纯 spec 文本
- **决策点：** 无
- **时机：** v1 merge 之后

## 改动 5 — Custom errors for commitToJob
- **位置：** `src/IAAP.sol`, `src/AAPCore.sol`, `test/AAPCore.t.sol`
- **类型：** ✅ 已落地（commit `c74edda`）
- **落地内容：**
  - 4 个 typed errors：`InsufficientAvailableAmount(available, requested)`、`DuplicateCommitment(jobId, coverageType)`、`AdverseSelectionBlocked(jobId)`、`AccountNotActive(agent)`
  - `commitToJob` 4 处 require 改成 revert with selector
  - 测试用 `abi.encodeWithSelector` 适配

## 改动 6 — Chained workflows 已知限制声明
- **位置：** Rationale 段
- **类型：** 📝 纯 spec 文本
- **决策点：** 无
- **时机：** v1 merge 之后

## 改动 7 — totalFunded 措辞修正
- **位置：** Rationale 段
- **类型：** 📝 纯 spec 文本（参考实现注释 `IAAP.sol` 早已是 "cumulative net inflow"，无需改）
- **决策点：** 无
- **时机：** v1 merge 之后

## 改动 8 — resolveClaim 存 keccak256(reason)
- **位置：** `src/IAAP.sol`, `src/AAPCore.sol`
- **类型：** ✅ 已落地（commit `c74edda`）
- **落地内容：**
  - `Claim` struct 加 `bytes32 reasonHash` 字段
  - `resolveClaim` 写入 `keccak256(reason)`
  - `ClaimResolved` event 加 raw `bytes reason` 字段供 indexer 消费

## 改动 9 — 在 spec 引用 PR #1653 reference scenarios
- **位置：** Reference Implementation 段或新增 "Composition Patterns" 小节
- **类型：** 📝 纯 spec 文本
- **决策点：** 是否点名具体 contributor（spec 正文不点名，致谢段点名）
- **时机：** v1 merge 之后

## 改动 10 — 新 CoverageType: RoleCollusion
- **位置：** `src/IAAP.sol`, `src/AAPCore.sol`, `src/MockERC8183.sol`, `test/AAPCore.t.sol`
- **类型：** ✅ 已落地（方案 B，commit `8e473d0`）
- **落地内容：**
  - `CoverageType.RoleCollusion` 加在 SettlementDefault 和 AMLFreeze 之间
  - `commitToJob` bound 放宽到 RoleCollusion
  - `MockERC8183` 加 `_roleCollusionAttested` mapping + `markRoleCollusion(jobId)` helper（模拟外部独立性层 attestation，注释明确不来自 ERC-8183 本身）
  - `isClaimEligible` 加 case 3 = `Completed && attested`
  - `test_15`：pre-attestation revert → post-attestation 成功 → resolve + payout 全链路通过
- **待办：** spec 侧 "Integration with ERC-8183" 章节加 RoleCollusion 独立 eligibility 行（post-completion attestation + 宽限期），等 v1 merge

## 改动 11 — IRiskHook 接口扩展（evidence + score）
- **位置：** `src/IRiskHook.sol`（新文件）
- **类型：** ✅ 已落地（commit `c74edda`）
- **落地内容：**
  - 单输出方法 `computeRecommendedAmount(assuredAgent, beneficiary, jobId, coverageType) → uint256`（v1 兼容）
  - 双输出方法 `computeRecommendedAmountWithEvidence(...) → (uint256, bytes32 evidenceRef)`（v2 evidence-first）
  - NatSpec 头部标注 "v2 draft pending review"
- **待办：** spec 侧 IRiskHook 小节正式纳入双输出，等 v1 merge

## 改动 12 — Evidence-First Composability Principle
- **位置：** Rationale 段
- **类型：** 📝 纯 spec 文本
- **决策点：** Multi-issuer envelope 引用方式
  - 方向 A：spec 点名 Douglas 的 insumer-examples#1（带 URL）
  - 方向 B：protocol-neutral 措辞描述模式，不点名（当前倾向）
  - 方向 C：完全不提，留给参考实现 repo 的 Integration Examples
- **时机：** v1 merge 之后

## 改动 13 — 跨供应商独立性 API
- **位置：** 已升级为改动 15（IIndependenceSignal 接口）
- **类型：** ✅ 已落地（合并进改动 15）

## 改动 14 — Stake-weighted Evaluator selection 参考模式
- **位置：** 改动 1 新增 Inherited Assumptions 章节中
- **类型：** 📝 纯 spec 文本（protocol-neutral 措辞，不点名 Demsys；具体合约地址进参考实现 repo 的 Integration Examples）
- **决策点：** 无
- **时机：** v1 merge 之后

## 改动 15 — IIndependenceSignal 接口
- **位置：** `src/IIndependenceSignal.sol`（新文件）
- **类型：** ✅ 已落地接口（commit `c74edda`，标注 v2 draft pending Henry review）
- **落地内容：**
  - 两种 delivery 模式：`assessIndependence(addrA, addrB)`（on-chain oracle）+ `verifyAttestation(addrA, addrB, attestation)`（signed payload）
  - 共享 output shape：`(bool independent, uint8 confidence, bytes evidence)`
  - NatSpec 写明四类最小信号 + 三条 output 不变式（partial 合法 / 空 evidence ↔ confidence=0 / confidence=0 时 independent undefined / 对称性）
- **待定项（标注在 NatSpec）：**
  1. 与 IRiskHook 的最终组合方式（平行 / 继承 / 组合） — pending Henry
  2. 第 5 类 Behavioral similarity 是否升核心类别 — pending 社区反馈

## 改动 16 — Integer Job Identifiers Implementation Note
- **位置：** `src/IAAP.sol` 的 `Claim` struct NatSpec
- **类型：** ✅ 已落地（commit `c74edda`）
- **落地内容：** NatSpec 说明 `claimId = keccak256(abi.encode(jobId, claimant))` 派生模式 + 本地声明 / `getCanonicalClaim` view 的 adaptation path

## 改动 17 — High-frequency composition metadata first-class 化
- **位置：** `src/IAAP.sol`, `src/AAPCore.sol`, `test/AAPCore.t.sol`
- **类型：** ✅ 已落地（方向 B，commit `8e473d0`）
- **落地内容：**
  - `Claim` struct 加 3 个 optional bytes32 字段：`upstream` / `reasoningCID` / `slashEvidenceHash`（默认 zero）
  - `fileClaim` 签名扩展 3 个 bytes32 参数（NatSpec 对应 Scenario 1/3/2）
  - `ClaimFiled` event 加 3 个非 indexed bytes32 字段（已用满 3 indexed 槽，indexer 用现有 indexed 过滤后直接读）
  - `test_16` round-trip 验证

---

## 不进入 v2（已评估）

- ❌ Delegated Funding — 留独立扩展 ERC
- ❌ Cross-chain assurance — 留独立扩展 ERC
- ❌ Partial payout — 破坏会计恒等式简洁性
- ❌ Resolver 治理机制 — 部署文档范围

---

## 参考实现 repo 配套工作（不属 spec 本身）

- ⏳ `docs/integration-examples/` 新建（已对 RNWY 承诺）
  - 内容：RNWY oracle 地址 `0xD5fdccD492bB5568bC7aeB1f1E888e0BbA6276f4`（Base 主网）、methodology 链接、可运行 Solidity 集成代码、IIndependenceSignal mock 测试
  - 时机：v2 PR merge 后两周内
  - 依赖：IIndependenceSignal 最终形状确定 + Pablo 确认 oracle 接口
- ⏳ custom errors 示例实现（部分已在 v2-draft 落地）
- ⏳ IRiskHook example 实现
- ⏳ Base Sepolia 测试网部署
- ⏳ multi-hop example 实现
- ⏳ bounded re-draw pattern 引用示例（Demsys 2026-04-13 已上线）

---

## v2 PR 启动前待确认事项

1. ~~IIndependenceSignal 接口 delivery 模式~~ ✅ 关闭：两种都要
2. ⏳ 第 5 类 Behavioral similarity 是否升核心 — pending 社区
3. ~~RoleCollusion 方案 A/B~~ ✅ 关闭：方案 B（已落地）
4. ⏳ IIndependenceSignal 跟 IRiskHook 的组合方式 — pending Henry
5. ⏳ RNWY methodology 版本引用策略（nullification ship 时机）— 被动观察
6. ~~Demsys bounded re-draw 上线时间~~ ✅ 关闭：2026-04-13 已上线
7. ~~改动 17 方向 A/B~~ ✅ 关闭：方向 B（已落地）
8. ⏳ multi-issuer envelope 在 v2 rationale 的引用方式（A 点名 / B 中立 / C 不提）— pending Henry + Douglas
