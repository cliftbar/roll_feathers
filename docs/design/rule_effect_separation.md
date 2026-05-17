# Rule Evaluation / Recording / Effect Separation Design

Separate three responsibilities that were fused in one fire-and-forget call: evaluating a rule, recording the roll, and performing side effects (blink / webhook / Discord). Fusing them let a side-effect failure silently destroy the roll record — the root cause of roll history vanishing on mobile Chrome.

## The problem

`RollDomain._stopRollWithResult` ran inside a fire-and-forget `Timer` in `rollAllVirtualDice`. The old `runRule` did evaluation **and** fired side effects inline, and it was awaited *before* `_rollHistory.insert`. Effects transitively hit `getConfig()` → `SharedPreferencesAsync` → IndexedDB, which can throw on mobile Chrome. The ordering was:

```
[fallible effect I/O]  →  [record the roll]
```

An inverted dependency: the must-never-fail operation (recording) sat downstream of, and gated by, the least reliable one (effect I/O). When IndexedDB threw, the exception propagated through the un-awaited Timer and the roll was never recorded.

## Design Decisions

### Three phases, ordered by reliability tier

`_stopRollWithResult` runs in explicit phases:

1. **Evaluate** — pure, no I/O. Collect a *plan* of effects, don't fire them.
2. **Record** — `_rollHistory.insert` + stream emits. No fallible work in front of it; always runs.
3. **Effects** — best-effort, fired after recording.

Recording can no longer be destroyed by anything downstream — on any platform, for any effect failure (IndexedDB, webhook, blink).

### Evaluation returns a plan, not performed effects

`evaluateRule` returns `RuleEvaluation { result, effects }` where `effects` is a list of `Future<void> Function()` closures. The ordering constraint ("record before any effect I/O") is only knowable by the orchestrator (`_stopRollWithResult`), not by `evaluateRule`. A try/catch inside `runRule` would not fix this — it would still perform I/O before the caller could record. The only correct fix is for evaluation to not do the I/O at all and hand back a plan. This is functional-core / imperative-shell: `evaluateRule` is the pure core; `_stopRollWithResult` is the shell that sequences the unsafe parts.

### Why not the band-aids

A try/catch around `getConfig()`, or an `available` check, stops the crash but leaves the inverted dependency intact — recording would still happen only *after* surviving the I/O. The abstraction leak is the real defect; the separation is the real fix.

### `runRule` → `evaluateRule`

The method no longer runs anything — it evaluates and returns a plan. A `runRule` name (and a `Future` return) implied side effects and async that no longer exist. Renamed and made synchronous so the signature tells the truth.

### `fireEffects` vs the test-only `runEffects`

Two distinct semantics, deliberately not shared:

- **Production — `RuleEvaluation.fireEffects(onError)`**: fires each effect with its own `.catchError` + log. Per-effect isolation; one failing effect never affects another or the caller. This is the load-bearing semantic of the fix.
- **Test-only — `runEffects()`** (extension in `lib/testing/rule_evaluation_test_effects.dart`): `Future.wait` over all effects so a test can deterministically await completion before asserting on spies. All-or-throw; acceptable only because `WebhookDomain.fireWebhook` swallows its own errors.

`runEffects` is intentionally **off** the production type. "Simplifying" Phase 3 to `await eval.runEffects()` would reintroduce all-or-throw and lose per-effect logging — a partial regression of this bug.

## Affected files

- `lib/domains/roll_parser/rule_evaluator.dart` — `evaluateRule` (sync), `RuleEvaluation`, `fireEffects`
- `lib/domains/roll_domain.dart` — three-phase `_stopRollWithResult`, awaited Timer
- `lib/repositories/home_assistant_repository.dart` — `blinkEntity` early-exit
- `lib/ui/die_screen/dice_screen.dart` — empty-roll bounds guard
- `lib/testing/rule_evaluation_test_effects.dart` — test-only `runEffects`

## Related

- Supersedes `docs/specs/dsl_async_evaluator_migration.md` (the `runRuleAsync` / `useAsyncEvaluator` plan).
- Open follow-up: `useAsyncEvaluator` is now dead config (read, never branched on). See `docs/TODO.md`.
