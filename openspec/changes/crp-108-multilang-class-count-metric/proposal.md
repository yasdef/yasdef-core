## Why

`ai/scripts/post_review.sh` currently reports `New classes added` using Java-only logic (`src/main/java` new type files). In this repository, that label is semantically incorrect for frontend- or polyglot-heavy changes and produces misleading `ai/history.md` summaries.

## What Changes

- Redefine the `New classes added` metric as a multi-language class/type count instead of Java-only count.
- Update post-review metric extraction logic to detect class/type declarations in a default set of 10 languages:
  - Java (`.java`)
  - Python (`.py`)
  - TypeScript (`.ts`, `.tsx`)
  - JavaScript (`.js`, `.jsx`)
  - Go (`.go`)
  - Kotlin (`.kt`)
  - C# (`.cs`)
  - C++ (`.cpp`, `.cc`, `.cxx`, `.hpp`)
  - PHP (`.php`)
  - Ruby (`.rb`)
- Treat the language list as the default baseline and allow follow-up extension in later changes without breaking current behavior.
- Remove Java-specific wording from CLI help and inline comments so behavior and labels match.
- Keep existing diff scope semantics (newly added files in the measured step delta, including working-tree snapshot behavior) unless explicitly changed in follow-up artifacts.
- **BREAKING**: historical metric values for `New classes added` may increase for non-Java repos or frontend-heavy commits because counting semantics become language-inclusive.

## Capabilities

### New Capabilities
- `post-review-multilang-class-metrics`: Post-review history generation reports `New classes added` using language-inclusive detection rules across a default top-10 language extension set (including `.java`, `.py`, `.tsx`, `.go`, `.kt`).

### Modified Capabilities
- None.

## Impact

- Affected code:
  - `ai/scripts/post_review.sh`
- Affected artifacts/output:
  - `ai/history.md` consolidated step records (`New classes added`)
- Affected tests:
  - `tests/ai_scripts/` coverage for post-review metrics and language-specific class/type detection cases
- Affected documentation/help text:
  - `ai/scripts/post_review.sh` usage/help and implementation comments describing metric scope
