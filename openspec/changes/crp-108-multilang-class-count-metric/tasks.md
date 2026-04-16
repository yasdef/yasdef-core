## 1. Update post-review class metric semantics

- [x] 1.1 Replace Java-only class counting in `ai/scripts/post_review.sh` with a language-inclusive counter for the default 10-language baseline.
- [x] 1.2 Guarantee required minimum extension support for `.java`, `.py`, `.tsx`, `.go`, and `.kt`.
- [x] 1.3 Preserve current diff-range and working-tree snapshot behavior while switching metric language coverage.
- [x] 1.4 Keep one-file-one-count metric behavior and preserve existing Java-specific exclusions that remain valid (for example `package-info.java`, `module-info.java`).

## 2. Align operator-facing wording with behavior

- [x] 2.1 Update `ai/scripts/post_review.sh` help text so `New classes added` is documented as multi-language rather than Java-only.
- [x] 2.2 Update inline script comments to remove Java-only semantics and reflect baseline language families and extension mapping.

## 3. Add regression coverage for multi-language counting

- [x] 3.1 Add a post-review metrics shell test suite under `tests/ai_scripts/` for positive detection in `.java`, `.py`, `.tsx`, `.go`, and `.kt`.
- [x] 3.2 Add coverage for the remaining baseline languages (`.ts`, `.js/.jsx`, `.cs`, `.cpp/.cc/.cxx/.hpp`, `.php`, `.rb`) and unsupported-extension negatives.
- [x] 3.3 Add coverage proving modified-but-not-new files do not increment `New classes added`.
- [x] 3.4 Add coverage proving working-tree snapshot mode includes pending newly added matching files.

## 4. Validate and prepare for apply

- [x] 4.1 Run relevant script test suites from repository root and resolve failures.
- [x] 4.2 Confirm `openspec status --change crp-108-multilang-class-count-metric` reports all artifacts complete and apply-ready.
