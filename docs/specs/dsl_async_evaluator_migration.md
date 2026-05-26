# DSL v1.1 Async Evaluator Migration Plan — SUPERSEDED

> **Status: superseded (2026-05-16).** This plan is no longer the direction.
> The problem it addressed — making production evaluation deterministic without
> letting action I/O block or destabilize the roll path — was resolved by a
> different, better approach: the evaluation / recording / effect separation in
> **`docs/design/rule_effect_separation.md`**. Kept for historical context.

## Why this plan was abandoned

The original plan proposed a runtime toggle (`AppService.useAsyncEvaluatorKey`)
selecting between a sync `runRule` and an async `runRuleAsync`, plus an unresolved
"emit results before vs. after awaiting actions" question (Option A vs. B).

The roll-history mobile-Chrome bug forced a cleaner resolution that makes the
toggle unnecessary:

- `runRule` was renamed to **`evaluateRule`** and is **always synchronous and
  pure** — it returns a `RuleEvaluation { result, effects }` plan and performs
  no I/O.
- `runRuleAsync` was **removed**. The async-vs-sync duality no longer exists.
- Side effects are fired **after** the roll is recorded, best-effort, with
  per-effect isolation (`RuleEvaluation.fireEffects`). This is the original
  "Option A" taken to its conclusion — and the *only* path, not a gated one.
- In-block action ordering is preserved by the order of the collected effect
  closures; tests await them deterministically via the test-only `runEffects`
  extension.

## Dead config to remove (follow-up)

`useAsyncEvaluator` / `AppService.getUseAsyncEvaluator` / `useAsyncEvaluatorKey`
are still read into `RollDomain.useAsyncEvaluator` but **nothing branches on the
value anymore**. They are dead. Tracked in `docs/TODO.md` for removal.

## Original plan (for history)

The original migration plan (runtime toggle, parallel async API, Option A/B
emission timing, staged rollout) is preserved in git history prior to
2026-05-16 if needed.
