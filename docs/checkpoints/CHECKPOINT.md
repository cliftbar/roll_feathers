# Checkpoint: cb_roll-history-mobile-fix

## Branch state (2026-05-16)

Fixes roll history silently vanishing on mobile Chrome, plus the follow-on
naming/API cleanup it exposed.

Commits since `main`:
- `9adccd1` fix roll history silently lost on mobile Chrome
- `12c30ba` update tests for attempted history race condition fix
- (pending) evaluateRule rename + fireEffects / test-only runEffects extraction
- (pending) docs: design rationale, superseded spec, checkpoint, TODO

Modified / added:
- `lib/domains/roll_parser/rule_evaluator.dart`
- `lib/domains/roll_domain.dart`
- `lib/repositories/home_assistant_repository.dart`
- `lib/ui/die_screen/dice_screen.dart`
- `lib/testing/dsl_test_harness.dart`
- `lib/testing/rule_evaluation_test_effects.dart` (new)
- `test/domains/roll_parser/dsl_{v11,discord,webhook_evaluation,webhook_integration}_evaluation_test.dart`
- `CHANGELOG.md` (`## 0.12.18`)
- `docs/design/rule_effect_separation.md` (new), `docs/specs/dsl_async_evaluator_migration.md` (superseded), `docs/TODO.md`

Status: full suite green (260 pass / 9 skip / 0 fail), analyzer clean for changed files.

---

## What was completed

### The fix (root cause: inverted dependency)

`_stopRollWithResult` ran fire-and-forget in a `Timer`; the old `runRule` fired
side effects inline and was awaited *before* `_rollHistory.insert`. An effect
hitting `getConfig()` → `SharedPreferencesAsync` → IndexedDB could throw on
mobile Chrome, propagate through the un-awaited call, and skip recording.

Three-phase `_stopRollWithResult`: evaluate (pure, collect effect plan) →
record (no I/O in front of it, always runs) → effects (best-effort, after
recording). Rationale in `docs/design/rule_effect_separation.md`.

Also: `blinkEntity` early-exits when HA is unavailable (skips 4 IndexedDB reads
per roll); `rollAllVirtualDice` Timer now awaits; `_makeRollText` guards an
empty `rollsWithColors`.

### Naming / API cleanup

- `runRule` → **`evaluateRule`**, synchronous and pure, returns
  `RuleEvaluation { result, effects }` (a plan; no I/O).
- Production effect firing encapsulated as **`RuleEvaluation.fireEffects(onError)`**
  — per-effect `.catchError` + log isolation; called from Phase 3 over a
  `List<RuleEvaluation>`.
- The old await-all `runEffects()` moved to a **test-only** extension,
  `lib/testing/rule_evaluation_test_effects.dart` (Future.wait / all-or-throw —
  fine for tests since `fireWebhook` swallows its own errors). Off the
  production type by design.
- `runRuleAsync` removed. The 4 DSL test files + harness updated.

---

## Open items

- **pubspec version not bumped.** CHANGELOG has `## 0.12.18`; `pubspec.yaml` is
  unchanged. `tagged_release.yaml` is tag-triggered and does not edit pubspec —
  bump manually + tag `v0.12.18` at release if the in-app version should match.
- **Dead `useAsyncEvaluator` config** — read but never branched on after this
  change. Removal tracked in `docs/TODO.md`.
- **Reproducing the original bug** is environmental (needs IndexedDB to actually
  throw — incognito / blocked site data / storage pressure) AND an effect-firing
  enabled rule on a virtual roll. Not reproducing on a clean device does not
  invalidate the fix; the fix removes the failure class regardless. Phase 3's
  `_log.warning('side effect error', ...)` will surface the real exception once
  in the field.
