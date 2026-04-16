## Context

`ai/scripts/post_review.sh` currently computes `New classes added` via `count_new_java_types_added`, which inspects only newly added Java files under `src/main/java`. This behavior was reasonable for Java-only repositories, but the same label is now consumed in a polyglot codebase where frontend and non-Java backend changes are common.

The change must keep post-review's existing diff-range mechanics and working-tree snapshot behavior while correcting metric semantics to reflect language-inclusive class/type counting.

## Goals / Non-Goals

**Goals:**
- Replace Java-only class counting with a default 10-language baseline while guaranteeing support for `.java`, `.py`, `.tsx`, `.go`, and `.kt`.
- Keep output field name `New classes added` but align its meaning and help text with language-inclusive behavior.
- Preserve current delta boundaries and snapshot-index behavior used by post-review metrics.
- Keep implementation in plain shell (`bash` + existing Unix tools), consistent with repository constraints.

**Non-Goals:**
- No AST parsing or compiler-grade semantic analysis for each language.
- No change to `New lines of code added` semantics.
- No automatic language inference beyond extension-based dispatch in this change.
- No change to aggregation format in `ai/history.md` beyond corrected metric values.

## Decisions

1. Use extension-dispatched matcher rules in `post_review.sh`.
Rationale: the script is already shell-based and must stay shell-only; extension dispatch with curated regex patterns gives predictable behavior with low complexity.
Alternative considered: language parser/AST tooling per language. Rejected due to dependency weight, portability overhead, and mismatch with current script architecture.

2. Define an explicit default 10-language baseline in code.
Rationale: explicit coverage makes metric behavior auditable and avoids ambiguity in "most used languages" wording.
Alternative considered: dynamic language ranking sourced from external data. Rejected because it introduces unstable behavior and external dependency at runtime.

3. Preserve existing diff-scope semantics (newly added files in measured range, plus temporary-index snapshot mode).
Rationale: this change targets metric semantics, not the scope/window logic used by post-review consolidation.
Alternative considered: also count modified files or count per declaration occurrence. Rejected for this change to avoid changing historical comparability and to keep blast radius focused.

4. Keep one-file-one-count semantics aligned with current implementation.
Rationale: existing metric counts new type files, not number of declarations. Preserving that behavior minimizes surprise while still fixing cross-language blindness.
Alternative considered: count each declaration occurrence. Rejected because it can inflate numbers and requires clearer migration messaging.

5. Update help text and inline comments in the same change.
Rationale: the current bug is partly semantic mismatch between label and implementation; documentation and implementation must be corrected atomically.
Alternative considered: update docs in a follow-up change. Rejected because it would leave known ambiguity in active tooling.

## Risks / Trade-offs

- [Risk] Regex-based detection can miss edge-case declarations or count false positives in uncommon syntax patterns. -> Mitigation: include representative positive/negative shell tests per baseline language and keep matchers conservative.
- [Risk] Historical trend continuity for `New classes added` changes after rollout. -> Mitigation: document the semantic shift in change notes and keep scope/window behavior unchanged so only language coverage changes.
- [Risk] Baseline language set may age over time. -> Mitigation: centralize extension map and matcher rules for easy extension in future OpenSpec changes.
- [Risk] Multi-extension families (for example TS/TSX, JS/JSX, C++ header/source variants) can drift if partially configured. -> Mitigation: define baseline by language families with explicit extension lists in one place.

## Migration Plan

1. Replace `count_new_java_types_added` with a language-inclusive counting function that reuses existing metrics diff inputs.
2. Introduce extension-family mapping and matcher predicates for the 10-language baseline.
3. Keep current exclusions that are still valid under inclusive mode (for example Java `package-info.java` and `module-info.java`).
4. Update `--help` text and inline comments to remove Java-only claims and describe the baseline.
5. Add/extend script tests under `tests/ai_scripts/` for required minimum languages and baseline coverage.
6. Validate with `openspec status --change crp-108-multilang-class-count-metric` that artifacts remain apply-ready.

Rollback strategy: restore prior Java-only counting function and Java-only help wording if regressions are detected; this reverts metric semantics to pre-change behavior.

## Open Questions

- Should future changes allow project-level configuration to tune the default language baseline?
- Should a future metric distinguish "new class-like files" from "new class/type declarations count" as separate fields?
