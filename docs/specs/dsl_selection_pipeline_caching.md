DSL v1.1 — Selection-pipeline caching (design note)

Status: Deferred (documented for future use)

Summary
- Within a single runRuleAsync evaluation, multiple "use selection @NAME" blocks may reference the same named selection built via "make selection". Recomputing the same pure transform pipeline multiple times is usually cheap at our current scales, but this note documents how to add a safe per-evaluation cache if profiling ever shows a hotspot.

Rationale
- Current rules typically operate on small dice pools (1–20). Filters and a single sort are fast; async actions dominate latency.
- Caching can reduce duplicate work when the same selection is reused 3+ times, or when future transforms become heavier (for example, grouping with per-group sorting) or pools are very large.

Scope
- Cache only within one runRuleAsync invocation.
- Do not persist across evaluations, sessions, or devices.
- Cache only pure, deterministic pipelines (no time or side-effects).

What to cache
- The resolved selection map for a named pipeline applied to the current immutable roll snapshot: the selected dice and their transformed values.
- Optionally, lightweight derived values required by aggregates, if those are expensive to recompute.

Cache key
- Tuple: (selectionName, rollSnapshotId, pipelineHash[, optionsVersion])
  - selectionName: DSL name from "make selection".
  - rollSnapshotId: identity/version for the base roll snapshot of this evaluation.
  - pipelineHash: stable hash over the pipeline AST (operator names plus normalized args in order).
  - optionsVersion (optional): include if runtime flags can alter semantics.

Lifetime
- Construct a small map at the start of runRuleAsync and discard after completion.

Correctness guardrails
- Read-through cache: miss -> compute and store; hit -> return an immutable/deep-frozen copy to prevent mutation leaks.
- Exclude any impure transforms from caching.
- If future features allow "on result" to mutate dice state, bump/invalidate rollSnapshotId upon mutation or disable caching for that rule.

Complexity and expected benefit
- Implementation complexity: low (one map plus a pipelineHash function plus lookups at selection resolve sites).
- Benefit today: negligible for small pools; likely sub-millisecond. Potentially useful with hundreds of dice and many reuse blocks.

Decision
- Defer implementation. Keep this note as a reference. Revisit only if profiling on target devices shows selection resolution dominating (>1–2 ms per reuse for large pools).

Testing guidance (when/if implemented)
- Functional: Ensure results are identical with cache on vs off for scripts that reuse a selection across multiple blocks.
- Performance: Micro-bench synthetic rules with large pools (for example, 100–1000 dice) and 5–10 reuses; measure wall-clock before/after.
