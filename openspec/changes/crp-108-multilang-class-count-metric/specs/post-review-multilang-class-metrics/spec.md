## ADDED Requirements

### Requirement: Post-review class metric SHALL be language-inclusive
`ai/scripts/post_review.sh` MUST compute `New classes added` using a default 10-language baseline instead of Java-only counting.

The baseline language set SHALL include:
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

#### Scenario: Required minimum language set is counted
- **WHEN** the measured diff contains newly added files with valid type/class declarations in `.java`, `.py`, `.tsx`, `.go`, and `.kt`
- **THEN** each matching file contributes to the `New classes added` metric
- **AND** the resulting metric value is greater than `0` for a frontend- or polyglot-heavy change that includes such declarations

#### Scenario: Unsupported extensions do not affect the metric
- **WHEN** the measured diff contains newly added files outside the baseline extension set
- **THEN** those files do not increment `New classes added`

### Requirement: Declaration detection SHALL use language-appropriate markers
The class metric implementation MUST evaluate declaration markers appropriate to each baseline language instead of reusing Java-only tokens for all languages.

#### Scenario: Language-specific markers are recognized
- **WHEN** a newly added file contains declarations such as `class` (Python/TS/JS/PHP/Ruby), `type ... struct|interface` (Go), `class|interface|object|enum class|data class` (Kotlin), `class|struct` (C++), or `class|interface|record|struct|enum` (C#)
- **THEN** the file is counted for `New classes added` according to its extension's matcher rules

### Requirement: Metric scope semantics SHALL stay aligned with existing step-delta behavior
This change MUST preserve existing post-review diff-scope semantics for the class metric: count from the same step delta used today and include working-tree snapshot behavior when enabled.

#### Scenario: New-file scope is preserved
- **WHEN** a file is modified but not newly added in the measured diff
- **THEN** it does not increment `New classes added`

#### Scenario: Working-tree snapshot contributes when enabled
- **WHEN** post-review runs with pending local changes and snapshots them into the temporary index
- **THEN** newly added matching files in that snapshot are included in `New classes added`

### Requirement: User-visible wording SHALL match metric behavior
Operator-facing help text and in-script documentation MUST describe class counting as multi-language and MUST NOT describe it as Java-only behavior.

#### Scenario: Help text no longer claims Java-only counting
- **WHEN** an operator reads `ai/scripts/post_review.sh --help` output
- **THEN** the description for `New classes added` reflects the language-inclusive baseline
- **AND** it does not state that counting is restricted to `src/main/java`
