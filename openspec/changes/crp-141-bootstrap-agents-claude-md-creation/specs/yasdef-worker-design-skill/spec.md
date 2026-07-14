## MODIFIED Requirements

### Requirement: Design skill ships a blueprint-finder Python helper inside its own scripts/ directory

The `yasdef-worker-design` skill SHALL ship a Python script at `scripts/find_blueprints.py` inside the skill bundle that performs class-aware discovery of project-level bootstrap artifacts for the design phase.

The script SHALL:

- Resolve the feature directory by preferring `cwd` when it contains both `implementation_plan.md` and (`requirements_ears.md` OR `reqirements_ears.md` — the typo fallback is preserved); otherwise fall back to `dirname(os.environ["ASDLC_RUNTIME_PLAN_PATH"])` when that env var is set and the resolved path is a directory.
- Resolve the worker repo binding file by walking up from the script's own physically resolved location (`Path(__file__).resolve()`) until a directory containing `.asdlc_worker/project_overmind.yaml` is found; when no such directory is found, the class SHALL resolve as unresolved. The binding file SHALL NOT be resolved relative to the feature directory's parent. This behavior assumes the supported `yasdef init` layout, which copies real skill files into the worker repo and rejects symlinked package data/destinations; manually symlink-installed skill bundles are not a supported resolver input.
- Read the `class` scalar from the resolved binding file, handling single-quoted, double-quoted, and unquoted YAML values, and stripping trailing `# comment` content from the line.
- Normalize the class string using the map: `back|backend|api|server → back`; `front|frontend|front-end|web|ui → front`; `mobile|ios|android|react-native → mobile`. Any other value resolves to an empty string (unresolved).
- Search the parent of the feature directory non-recursively for files matching `project_stack_blueprint_*.md`, sorted lexically (LC_ALL=C equivalent).
- Partition the matched blueprints into "relevant" (basename contains a class-substring for the normalized class: `back|backend` for back; `front|frontend|web` for front; `mobile|ios|android` for mobile) and "irrelevant" (everything else).
- Resolve the worker repo root from the binding-file location and report the local state of `<worker-root>/AGENTS.md` and `<worker-root>/CLAUDE.md`. A regular file or symlink at the exact project-root path counts as `present`, no directory entry counts as `absent`, and a directory SHALL be reported as `invalid-directory`. Global or user-home guidance paths SHALL NOT be inspected.
- Emit a single human-readable text block to stdout containing: the `Blueprint helper result` preamble; the existing five labeled lines (`Feature folder:`, `Project-level search root:`, `Binding file:`, `Raw project class:`, `Normalized project class:`); the additional `Worker repo root:`, `Project AGENTS.md state:`, and `Project CLAUDE.md state:` lines; the `All blueprint candidates:` block; the per-class `Relevant blueprint candidates for class <X>:` and `Irrelevant blueprint candidates for class <X>:` blocks; and the `Relevant blueprint result:` summary line.
- Exit with code 0 in all successful paths (including the no-class-resolvable and no-artifacts-found paths). Exit non-zero only when the feature directory cannot be resolved.

#### Scenario: Feature directory resolved from cwd

- **WHEN** the script is invoked from a directory that contains `implementation_plan.md` and `requirements_ears.md`
- **THEN** the resolved feature directory is the cwd, regardless of the `ASDLC_RUNTIME_PLAN_PATH` environment variable

#### Scenario: Feature directory resolved from ASDLC_RUNTIME_PLAN_PATH

- **WHEN** the cwd does not contain the feature marker files and `ASDLC_RUNTIME_PLAN_PATH` is set to a path whose dirname exists
- **THEN** the resolved feature directory is the dirname of `ASDLC_RUNTIME_PLAN_PATH`

#### Scenario: Feature directory cannot be resolved

- **WHEN** neither the cwd nor `ASDLC_RUNTIME_PLAN_PATH` yields a feature directory
- **THEN** the script exits non-zero with the message `Blueprint lookup failed: run this helper from an ASDLC feature folder with implementation_plan.md and requirements_ears.md, or ensure ASDLC_RUNTIME_PLAN_PATH is set.`

#### Scenario: Binding file resolved from the worker repo containing the installed skill

- **WHEN** the script runs from a skill bundle copied by `yasdef init` inside a worker repo whose root contains `.asdlc_worker/project_overmind.yaml`, and the feature directory lives outside that worker repo (bound overmind project folder)
- **THEN** the reported `Binding file:` is the worker repo's `.asdlc_worker/project_overmind.yaml` and the class is read from it

#### Scenario: Editable tool install still produces a copied worker skill

- **WHEN** the `yasdef` Python tool is installed from editable source and `yasdef init` installs the design skill into a worker repo
- **THEN** the installed helper is a real copied file under the worker repo, not a symlink to the editable source, and worker-root binding discovery behaves the same as for a wheel-installed tool

#### Scenario: Project-root guidance state is reported

- **WHEN** the worker repo contains `AGENTS.md` but does not contain `CLAUDE.md`
- **THEN** the helper reports `Project AGENTS.md state: present` and `Project CLAUDE.md state: absent`

#### Scenario: Global guidance does not satisfy project-root state

- **WHEN** the project-root files are absent but similarly named files exist outside the worker repo, including under a user-home tool configuration directory
- **THEN** both project-root states are reported as absent and the external files are neither read nor reported

#### Scenario: No worker repo found above the script location

- **WHEN** no directory on the path from the script's location to the filesystem root contains `.asdlc_worker/project_overmind.yaml`
- **THEN** the output reports the worker repo and project-root guidance states as unresolved, reports the class as unresolved, lists all candidates unfiltered, and exits 0

#### Scenario: Class normalization

- **WHEN** the raw class value in the binding file is any of `back`, `backend`, `api`, `server` (case-insensitive)
- **THEN** the normalized class is `back`

#### Scenario: Unresolved class produces an empty relevant list

- **WHEN** the raw class value does not match any known alias
- **THEN** the output prints `Normalized project class: unresolved` and the `Relevant blueprint result:` summary indicates no class-matching blueprint found

#### Scenario: Class-substring partition of blueprints

- **WHEN** the normalized class is `back` and the parent directory contains `project_stack_blueprint_back.md` and `project_stack_blueprint_front.md`
- **THEN** the back blueprint appears under `Relevant blueprint candidates for class back:` and the front blueprint appears under `Irrelevant blueprint candidates for class back:`

## ADDED Requirements

### Requirement: Discovery helper reports project-level agents-guidance artifacts

In the same invocation, `find_blueprints.py` SHALL search the parent of the feature directory non-recursively for files matching `project_agents_md_claude_md_*.md`, sorted lexically, and partition them by the normalized worker class using the same class-substring rules as blueprints.

After the blueprint blocks, the output SHALL contain an agents-guidance section with: an `All agents guidance candidates:` block (or a no-candidates statement); per-class `Relevant agents guidance candidates for class <X>:` and `Irrelevant agents guidance candidates for class <X>:` blocks when the class is resolved; and a final `Relevant agents guidance result:` summary line stating either the count of class-matching candidates or that none were found.

Agents-guidance discovery SHALL NOT change the script's exit-code behavior.

#### Scenario: Class-matching agents-guidance artifact found

- **WHEN** the normalized class is `back` and the project-level root contains `project_agents_md_claude_md_backend.md`
- **THEN** the file is listed under `Relevant agents guidance candidates for class back:` and the `Relevant agents guidance result:` line reports one class-matching candidate

#### Scenario: No agents-guidance artifact exists

- **WHEN** the project-level root contains blueprint files but no `project_agents_md_claude_md_*.md` files
- **THEN** the agents-guidance section states that no agents-guidance files were found, the `Relevant agents guidance result:` line reports none found, and the script still exits 0

#### Scenario: Agents-guidance partition with multiple classes

- **WHEN** the normalized class is `front` and the project-level root contains `project_agents_md_claude_md_frontend.md` and `project_agents_md_claude_md_backend.md`
- **THEN** the frontend file appears under the relevant block and the backend file appears under the irrelevant block

### Requirement: Bootstrap design records an all-or-nothing project-guidance reconciliation decision

The design skill's `SKILL.md` Bootstrap Decision section SHALL require, whenever `Bootstrap required: yes`:

- The `## First-Feature Bootstrap (only if needed)` section SHALL record the agents-guidance lookup result and evidence, `Project AGENTS.md state`, `Project CLAUDE.md state`, and exactly one `Agent-guidance disposition` value: `both-present-no-action`, `regenerate-both-approved`, or `leave-unchanged-declined`.
- When both project-root files are present, the skill SHALL NOT inspect their content quality or ask a reconciliation question. It SHALL record `both-present-no-action` and leave both files unchanged, including when either file is a placeholder or symlink.
- When either project-root file is absent and exactly one class-matching guidance artifact is available, the skill SHALL ask one binary question. The question SHALL report which local files are present/absent and SHALL state that approval backs up any existing root guidance path, then regenerates and overwrites both project-root files with identical knowledgebase content, while decline leaves the repository unchanged.
- When either project-root state is `invalid-directory`, the skill SHALL NOT treat that path as present or absent, SHALL NOT offer the standard regeneration question, and SHALL NOT record any reconciliation disposition. It SHALL ask the user to resolve the directory conflict and rerun the lookup before design readiness can pass.
- The two choices SHALL be `Yes, regenerate both files` and `No, leave the repository unchanged`. The skill SHALL NOT offer a per-file choice, merge, partial preservation, or creation of only the missing file.
- Approval SHALL be recorded as `regenerate-both-approved`; decline SHALL be recorded as `leave-unchanged-declined`.
- When no unique class-matching `project_agents_md_claude_md_<class>.md` exists or the class is unresolved, the skill SHALL ask the user for agent-guidance direction instead of offering regeneration from invented or ambiguous content.
- Global or user-home `AGENTS.md`/`CLAUDE.md` files SHALL have no effect on this decision.

#### Scenario: Both project-root guidance files already exist

- **WHEN** first-feature bootstrap is required and both project-root files are present
- **THEN** the design records `Agent-guidance disposition: both-present-no-action`, asks no reconciliation question, and imposes no write regardless of either file's content

#### Scenario: One project-root guidance file is absent and regeneration is approved

- **WHEN** first-feature bootstrap is required, either project-root file is absent, exactly one class-matching guidance artifact exists, and the user chooses `Yes, regenerate both files`
- **THEN** the design records `Agent-guidance disposition: regenerate-both-approved` and identifies that artifact as the verbatim source for both outputs

#### Scenario: One project-root guidance file is absent and regeneration is declined

- **WHEN** first-feature bootstrap is required, either project-root file is absent, and the user chooses `No, leave the repository unchanged`
- **THEN** the design records `Agent-guidance disposition: leave-unchanged-declined` and no creation, overwrite, merge, or deletion is required

#### Scenario: Bootstrap guidance source is unavailable or ambiguous

- **WHEN** first-feature bootstrap is required, either local file is absent, and no unique class-matching guidance artifact is available
- **THEN** the skill asks for direction and SHALL NOT record `regenerate-both-approved` until an explicit source is resolved

#### Scenario: A project-root guidance path is a directory

- **WHEN** first-feature bootstrap is required and either `<worker-root>/AGENTS.md` or `<worker-root>/CLAUDE.md` is a directory
- **THEN** the helper reports that path as `invalid-directory`, the skill asks the user to resolve the filesystem conflict, no reconciliation disposition is recorded, and design readiness remains blocked

#### Scenario: Non-bootstrap feature is unaffected

- **WHEN** the design phase determines the step is normal feature extension work (`Bootstrap required` is not `yes`)
- **THEN** the design artifact carries no AGENTS.md/CLAUDE.md creation obligation from this skill

### Requirement: Approved project guidance is materialized before scaffold implementation starts

For a bootstrap-required design with `Agent-guidance disposition: regenerate-both-approved`, the worker SHALL materialize the decision after design completion and before launching the scaffold implementation model.

The materializer SHALL:

- Revalidate that the recorded guidance source is a unique, readable project-level `project_agents_md_claude_md_<class>.md` artifact.
- Read one canonical byte payload from that artifact and install it verbatim as both `<worker-root>/AGENTS.md` and `<worker-root>/CLAUDE.md`.
- When at least one root guidance path exists, before replacing either root path create a new collision-resistant backup directory under `<worker-root>/.asdlc_worker/agent_guidance_backups/<operation-id>/`. Preserve every existing regular file or symlink there under its original basename without following symlinks, verify the backup, and report the retained backup directory on success. When both root paths are absent, skip backup creation.
- Abort before replacing either root path if the backup directory cannot be created, already exists, or any existing path cannot be preserved and verified. Existing backup directories and files SHALL NOT be overwritten.
- Replace either existing regular file or symlink at those paths. It SHALL replace a symlink itself and SHALL NOT follow it to modify its target.
- Revalidate before any destination change that neither output path is a directory. If either path is a directory, the operation SHALL fail without modifying either output path.
- Treat the pair as one operation: it SHALL report success only when both paths are regular files with byte-identical content. On failure it SHALL avoid reporting a partial successful reconciliation and preserve or restore pre-operation local state where feasible.
- Perform no write for `both-present-no-action` or `leave-unchanged-declined`.
- When a backup is created, add `.asdlc_worker/agent_guidance_backups` to the worker repo's local git exclude entries so recovery copies are not included by ordinary source-control staging.

The design readiness gate SHALL reject a bootstrap-required design when either recorded project-root state is `invalid-directory`, when the required file-state fields or disposition are missing, when a disposition is inconsistent with the recorded states, or when `regenerate-both-approved` lacks one unambiguous guidance source.

#### Scenario: Approved regeneration overwrites both outputs identically

- **WHEN** `AGENTS.md` exists with local content, `CLAUDE.md` is absent, and the user approved regeneration from a valid class-matching artifact
- **THEN** before the scaffold implementation model launches, the previous `AGENTS.md` bytes are retained under the reported backup directory, both root paths are regular files whose bytes exactly match the selected artifact, and the root `AGENTS.md` content is replaced

#### Scenario: Approved regeneration replaces a local symlink without following it

- **WHEN** one existing project-root guidance path is a symlink and regeneration is approved
- **THEN** the symlink itself is preserved under the backup directory, the root symlink is replaced by a regular file, its former target is unchanged, and both project-root files contain identical knowledgebase bytes

#### Scenario: Declined regeneration makes no changes

- **WHEN** either project-root file is absent and the recorded disposition is `leave-unchanged-declined`
- **THEN** the worker launches no materialization write and all pre-existing project-root guidance state remains unchanged

#### Scenario: Directory appears after regeneration was approved

- **WHEN** regeneration was approved but a directory exists at either destination when materialization begins
- **THEN** materialization fails before changing either destination and reports that the directory conflict requires explicit user resolution

#### Scenario: Backup creation fails

- **WHEN** regeneration was approved but an existing root guidance path cannot be preserved and verified in a new backup operation directory
- **THEN** materialization fails before replacing either root path, leaves both root paths unchanged, and does not overwrite any prior backup

#### Scenario: Both project-root files are absent when regeneration is approved

- **WHEN** regeneration is approved and neither project-root guidance path exists
- **THEN** both files are created from the knowledgebase payload without creating an empty backup operation directory or changing git exclude state

#### Scenario: Regeneration is declined without backup side effects

- **WHEN** the recorded disposition is `leave-unchanged-declined`
- **THEN** no backup directory is created and neither project-root path nor git exclude state is changed
