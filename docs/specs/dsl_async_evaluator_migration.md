# DSL v1.1 Async Evaluator Migration Plan

## Summary
- Objective: make production evaluation use `runRuleAsync` for deterministic, in‑block sequential action execution.
- Current: tests use `runRuleAsync`; production still calls `runRule` (sync). A toggle is added via `AppService.useAsyncEvaluatorKey` to gate the change.

## Rationale
- Deterministic visuals: Actions inside a `use selection` block (e.g., `blink`, `sequence`) should execute in the order defined by the rule.
- TDD alignment: Our v1.1 tests assert awaited, in‑order behavior.
- UX trade‑off: Async path may delay emitting final roll results until actions finish; we can decide per product requirements whether to await actions before or after publishing results.

## Scope of Change
1. Wire the toggle to actually select async vs. sync at runtime:
   - RollDomain._stopRollWithResult():
     - If `useAsyncEvaluator` is true, call `await ruleParser.runRuleAsync(...)` (method must become `Future<int>` or split into an async branch that awaits before assembling `RollResult`).
     - Else, keep current sync path with `runRule(...)`.
2. Propagate async where needed:
   - Any callers of `_stopRollWithResult` that need to await completion should be updated (timers/callbacks already async‑capable).
3. Emission timing decision:
   - Option A (recommended): compute `ParseResult` synchronously, emit `RollResult`, then fire/await visual actions in the background (still preserving in‑block order per die). Pros: UI stays responsive; Cons: actions may overlap with next roll if spammed.
   - Option B: fully await all actions before emitting `RollResult`. Pros: strict determinism end‑to‑end; Cons: slower perceived response.

## Backward Compatibility
- Keep the default toggle off (`false`) to avoid behavior change until explicitly enabled.
- Public API stability: Prefer not to change method signatures exposed outside the domain. If needed, add parallel async API (e.g., `stopRollWithResultAsync`) during transition.

## Risks & Mitigations
- Risk: UI regressions if result emission timing changes. Mitigation: behind toggle; test on target platforms.
- Risk: Long chains of actions increase latency. Mitigation: document expectations; optionally cap total duration per block.

## Rollout Plan
1) Land runtime toggle (done).
2) Add wiring for async branch under the toggle (no default behavior change).
3) Manual QA on iOS/Android/Desktop with built‑ins and sample rules.
4) Flip toggle in release config once approved.

## Notes
- Selection‑pipeline caching remains deferred (see `dsl_selection_pipeline_caching.md`).
