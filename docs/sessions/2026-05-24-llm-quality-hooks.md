# Session Q&A Log: LLM Quality Hooks

**Date:** 2026-05-24
**Mode:** Brainstorm (transitioning to New Feature for implementation planning)
**Scope:** Standard
**Phases completed:** 0, 1, 2, 3, 4, 5, 7 (Phase 6 skipped — no confidence gaps post-revision)
**Outcome:** Three artifacts produced and committed: brainstorm requirements (`docs/brainstorms/llm-quality-hooks.md`), implementation plan v1.1 with Phase 5 review folded in (`docs/plans/llm-quality-hooks-mvp-plan.md`), and this session log. Plan is ready for implementation; user recommended to start with Unit 0.

---

## Questions & Answers by Phase

### Phase 2: Challenge & Explore

**Q:** Which shape should the brainstorm document explore in depth?
Options offered: (a) Per-hook specialization, (b) Inspection-battery expansion, (c) Profile-based packaging, (d) All three.
**User:** Per-hook specialization.
**AI position:** Recommended (a). Reasoning: different checks at different hook points maximize signal-per-cost. Per-edit feedback (PostToolUse) changes intra-turn agent behavior, not just exit gate. Approach (b) is what already ships, just extended. Approach (c) is good packaging on top, not a substitute. Approach (d) was the most ambitious but risked producing a sprawling doc without commitment.
**Resolved:** Doc structured around per-hook specialization with 18 candidate requirements mapped against the hook event × tool matrix.

### Phase 2 → 3: Gate

**Q:** Ready to proceed to Phase 3 (Define)? Options: (a) Yes — write the requirements doc, (b) First clarify one more thing.
**User:** Yes — write the requirements doc.
**AI position:** No position; user-driven gate.
**Resolved:** Wrote `docs/brainstorms/llm-quality-hooks.md`.

### Phase 7 (interim): Hand Off → continue

**Q:** What's the next step? Options: (a) Continue to implementation planning for the Must-Haves, (b) Stop here, (c) Implement one specific requirement now.
**User:** Continue to implementation planning for the Must-Haves.
**AI position:** Recommended (a). Reasoning: the Must-Haves (R1, R2, R3, R4, R5) form a coherent v0.2 release. Per-edit RuboCop autocorrect is the single highest-leverage item and needs a real plan, not ad-hoc implementation. Option (c) risks shipping one requirement without resolving the cross-cutting open questions (Q6 in particular — bash vs. Ruby for check scripts — affects every subsequent requirement and should be settled before the second script is written).
**Resolved:** Continued to New Feature mode Phase 4 (Structure) for R1–R5.

### Phase 4: Step 4.0 — Clarification before structuring

**Q1:** R1 per-edit RuboCop autocorrect timing. Options: every Edit/Write, debounced after stop-editing, only at Stop.
**User:** Every Edit/Write.
**AI position:** Recommended every Edit/Write — simpler and the autocorrect mode keeps it silent on success, so the noise floor stays low. Debouncing adds state tracking and timing edge cases for marginal benefit.
**Resolved:** Unit 1 implementation uses PostToolUse on every Edit/Write/MultiEdit; MultiEdit dedupes across the file list.

**Q2:** R2 tests-changed behavior when no test file exists for a changed source file. Options: warn and continue, fail loudly, noop silently.
**User:** Warn and continue.
**AI position:** Recommended warn-and-continue — fail loudly is hostile to exploratory work; noop silently hides genuine gaps. Warn surfaces the gap to the agent without blocking.
**Resolved:** Unit 2 emits `[railsdx tests-changed] no test found for <file>\n→ try: create test/<mirror>_test.rb` and exits 0. Future `--strict` flag will fail for CI use.

**Q3:** R12 TaskCompleted gate strictness. Options: any check ran clean this turn, strict bin/agent-check exit 0 only, defer to v0.3.
**User:** Any check ran clean this turn.
**AI position:** Recommended any-check-clean — pragmatic, low false-positive rate, reads from a JSON state file (`.railsdx/last-check.json`) that other hooks write. Strict version is too rigid; deferring leaves R12 with no design.
**Resolved:** Deferred to v0.3 implementation anyway (R12 not in MVP scope), but the state-file shape decision in Unit 0 was made with this answer in mind.

**Q6:** Implementation language for new check scripts. Options: Ruby with shared lib helper, bash like existing rubocop-changed, mixed.
**User:** Ruby with shared lib/railsdx/checks/ helper.
**AI position:** Recommended Ruby with shared helper — testable, DRY, single place for the contract. Bash duplicates per-script; mixed creates inconsistency.
**Resolved:** Unit 0 introduces `Railsdx::Checks::Base`; existing `bin/rubocop-changed` template gets rewritten to use it. Q6 decision is the architectural keystone for v0.2.

### Phase 5: Review Gauntlet

**Q:** CEO Review scope mode. Options: HOLD, REDUCE, SELECTIVE EXPANSION, EXPANSION.
**User:** HOLD SCOPE.
**AI position:** Recommended HOLD — R1–R5 are already a deliberate subset (Must-Haves from a deliberate cut). Review value is in making them watertight, not in re-litigating scope.
**Resolved:** Ran CEO with HOLD lens, Design Review, Engineering Review. Surfaced 0 P0 / 6 distinct P1 findings.

**Q:** How to resolve the 6 P1 findings? Options: fold all 6 into the plan, fold cheap ones only, accept all without changes, defer to implementation.
**User:** Fold all 6 into the plan.
**AI position:** Recommended fold all 6 — findings 1, 2, 4 collapse to one shared helper in Unit 0; finding 3 (doctor) is a force multiplier worth its own unit; findings 5 and 6 are zero-cost decisions to lock in now. Risk of accepting-as-known-caveat: the 6 P1s become "known to be ignored" rather than "resolved."
**Resolved:** Plan revised to v1.1. Unit 0 expanded with Thor + format_failure helper + interface contract test. New Unit 6 (doctor) added. Release Strategy extended with end-to-end fixture integration test as v0.2 gate. Appendix "Phase 5 Findings Folded In" added to the plan.

### Phase 7 (final): Hand Off

**Q:** Final next step? Options: begin Unit 0 implementation, stop here, create GitHub issues, peer review.
**User:** Stop here — plan is the deliverable.
**AI position:** Recommended begin Unit 0 — risky abstraction, getting it right unblocks everything. Respect user's call to pause; the plan is committed and ready when work resumes.
**Resolved:** Session ends. Three artifacts committed. When work resumes, recommended entry point is Unit 0 implementation.

---

## Key Decisions

| Decision | Chosen | Phase | Rationale |
|----------|--------|-------|-----------|
| Hook architecture | Per-hook specialization | 2 | Different checks at different events maximize signal-per-cost; per-edit feedback changes intra-turn behavior |
| Cross-agent strategy | Graceful degradation (Claude full, Codex shared subset, OpenCode observation-only) | 3 (Define) | Hook capabilities are fundamentally asymmetric — pretending otherwise compromises everywhere |
| Tool selection | Local CLIs only (RuboCop, Brakeman, bundler-audit, gitleaks, Sorbet/Steep, strong_migrations) | 3 | Deterministic, free, fast, no API keys; matches existing precedent |
| Distribution | Single gem; check scripts in `bin/`; install generator wires hook configs | 3 | Extends current `bin/rubocop-changed` model; composes naturally |
| Opt-out granularity | Both named profiles (R17) and per-check skip flags (R18) | 3 | Two audiences — curated-default users and per-project tuners — should both be served |
| OpenCode positioning | Observation-only plugins, explicitly documented as such | 3 | OpenCode plugins genuinely can't block; honesty over false parity |
| Next step | Continue to implementation planning for R1–R5 | 7 (interim) | Must-Haves form a coherent release; needs a real plan |
| R1 timing | Every Edit/Write (no debounce) | 4 | Simpler; autocorrect mode keeps it quiet |
| R2 missing-test | Warn and continue | 4 | Don't block exploratory work; don't hide gaps |
| R6 script language | Ruby with shared `lib/railsdx/checks/` helper | 4 | Testable, DRY, single place for the contract |
| CEO scope mode | HOLD SCOPE | 5 | Re-litigating scope on a Must-Have subset is wasted effort |
| P1 resolution | Fold all 6 into the plan | 5 | Cluster of 3 collapses to one helper; doctor is a force multiplier |
| Dispatcher | Thor (via railties) | 5 | Free `--help` / arg parsing / subcommand routing |

---

## Positions Where AI Pushed Back

| Topic | AI Position | User Response | Final Resolution |
|-------|------------|---------------|------------------|
| Premise framing — "high quality code" | Pushed back during Phase 2 pressure test: the framing is wider than hooks can deliver. Reframed to "catch every mechanically-detectable defect before the agent declares a task done." User did not contest the reframe. | Implicitly accepted via continued engagement with the per-hook-specialization approach. | Scope boundaries section of requirements doc explicitly excludes semantic/behavioral quality. |
| Hook coverage ambition | Pushed for honest cross-agent asymmetry rather than lowest-common-denominator coverage. | Selected "per-hook specialization" which embraces the asymmetry. | Hook × Tool matrix in requirements doc documents Claude-only events (PostToolBatch R13, TaskCompleted R12) separately from cross-agent events. |
| Stopping after the brainstorm | Recommended continuing to implementation planning (a) over stopping (b) or jumping to one-requirement implementation (c). Reasoning: open question Q6 (bash vs. Ruby) is cross-cutting and should be resolved before any second script is written. | Agreed — selected (a). | Transitioning to New Feature mode Phase 4. |
