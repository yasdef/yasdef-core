## 1. Fix binding-file / class resolution in the discovery helper

- [x] 1.1 In `src/yasdef_worker/_data/skills/yasdef-worker-design/scripts/find_blueprints.py`, add a worker-repo resolver: walk up from `Path(__file__).resolve().parent` until a directory containing `.asdlc_worker/project_overmind.yaml` is found; return that binding file path, or `None` when the filesystem root is reached without a match.
- [x] 1.2 Replace the current `binding_file = project_root / ".asdlc_worker" / "project_overmind.yaml"` with the resolver result. When no binding file is found, keep today's unresolved-class behavior: print the `Binding file:` line (report the lookup outcome), `Raw project class: unresolved`, list all candidates unfiltered, exit 0.
- [x] 1.3 Leave feature-directory resolution, YAML scalar read, class normalization, blueprint search/partition, blueprint output labels, and exit-code behavior unchanged.
- [x] 1.4 Document that binding discovery assumes a real skill copy produced by `yasdef init`; editable tool installs still copy the skill, while manually symlink-installed skill bundles are unsupported and may resolve as unbound.

## 2. Add agents-guidance discovery to the same helper run

- [x] 2.1 After the blueprint blocks, glob `project_agents_md_claude_md_*.md` non-recursively in the same project-level search root (`feature_dir.parent`), sorted lexically.
- [x] 2.2 Partition the matches with the existing `_matches_class` substring rules and print the agents-guidance section: `All agents guidance candidates:` (or a no-candidates statement), per-class `Relevant agents guidance candidates for class <X>:` / `Irrelevant agents guidance candidates for class <X>:` blocks when the class is resolved, and a final `Relevant agents guidance result:` summary line (count found, none class-matching, or none found).
- [x] 2.3 Keep exit codes unchanged: 0 on all successful paths regardless of agents-guidance findings.
- [x] 2.4 Resolve the worker repo root from the discovered binding and print `Worker repo root:`, `Project AGENTS.md state:`, and `Project CLAUDE.md state:`. Count exact-root regular files and symlinks as `present`, missing entries as `absent`, directories as `invalid-directory`, and do not inspect global/user-home guidance.

## 3. Add the all-or-nothing Bootstrap Decision contract

- [x] 3.1 In `src/yasdef_worker/_data/skills/yasdef-worker-design/SKILL.md`, require the bootstrap section to record the agents-guidance lookup/evidence, both project-root file states, and one disposition: `both-present-no-action`, `regenerate-both-approved`, or `leave-unchanged-declined`.
- [x] 3.2 When both files are present, require `both-present-no-action` without inspecting content or prompting, including placeholder and symlink content.
- [x] 3.3 When either file is absent and one matching guidance artifact exists, require one binary prompt that reports both states and clearly says approval backs up any existing root guidance path and overwrites both files with identical knowledgebase content, while decline leaves the repository unchanged. Offer only `Yes, regenerate both files` and `No, leave the repository unchanged`.
- [x] 3.4 Prohibit per-file choices, merge behavior, partial preservation, global guidance lookup, and creating only the missing file.
- [x] 3.5 When the class/source is unresolved or ambiguous, ask for guidance direction and do not approve regeneration from invented content.
- [x] 3.6 When either local state is `invalid-directory`, block readiness and ask the user to resolve the directory; do not offer regeneration or record a disposition until the helper reports only present/absent states.

## 4. Enforce and materialize the recorded decision

- [x] 4.1 Extend `check_design_readiness.py` to require the two project-root state fields and a valid, state-consistent disposition whenever `Bootstrap required: yes`; approved regeneration also requires one recorded guidance source.
- [x] 4.2 Add a worker application/infra operation that consumes `regenerate-both-approved`, reads the selected artifact once, replaces both exact-root paths without following symlinks, and verifies two regular byte-identical outputs.
- [x] 4.3 Integrate materialization after design completion and before the scaffold implementation model launches. `both-present-no-action` and `leave-unchanged-declined` must perform no write.
- [x] 4.4 Make pair installation failure-safe: do not report success for a partial pair and preserve or restore pre-operation state where feasible.
- [x] 4.5 Revalidate destination types before writing and fail without changing either path when `AGENTS.md` or `CLAUDE.md` is a directory.
- [x] 4.6 When at least one root guidance path exists, before replacement preserve each existing regular file or symlink under a new collision-resistant `.asdlc_worker/agent_guidance_backups/<operation-id>/` directory without following symlinks; verify and report the backup, never overwrite an earlier backup, and abort before root-path changes on backup failure. Skip backup creation when both paths are absent.
- [x] 4.7 When a backup is created, add `.asdlc_worker/agent_guidance_backups` to runtime git exclude entries. Both-absent approval, declined, and both-present dispositions must not create backup or exclude side effects.

## 5. Update tests

- [x] 5.1 In `tests/skills_python_scripts/yasdef_worker_design_find_blueprints_tests.sh`, update the fixture so the binding file lives in a synthetic worker-repo root above a copied script location (not under the project dir), and assert class plus both local file-state lines resolve from it.
- [x] 5.2 Add helper cases for relevant/irrelevant guidance artifacts, no guidance artifacts, no worker binding, both files present, one file absent, an invalid directory path, and external/global files that must not affect project-root state.
- [x] 5.3 Extend design-skill/readiness tests for all three dispositions, inconsistent state/disposition combinations, invalid-directory blocking, missing approved source, the exact two-choice interaction, and the prohibition on per-file choices.
- [x] 5.4 Add application/unit tests proving approval backs up existing regular-file bytes, preserves a symlink without following it, overwrites both outputs with verbatim identical bytes, refuses a directory without modifying either path, aborts cleanly on backup failure/collision, decline creates no backup and changes neither path, both-present changes neither path, and a failed pair write does not report success.
- [x] 5.5 Add an integration test proving approved files exist before the scaffold implementation process is launched.
- [x] 5.6 Retain installer coverage proving package-data/destination symlinks are rejected and add or retain coverage that editable package resources are emitted as copied install entries rather than target-repo symlinks.

## 6. Validate

- [x] 6.1 Run `tests/skills_python_scripts/yasdef_worker_design_find_blueprints_tests.sh` and `tests/skills_python_scripts/yasdef_worker_design_tests.sh` and confirm pass.
- [x] 6.2 Run the relevant Python unit/integration tests for design phase materialization and process launch ordering.
- [x] 6.3 Run the repo's full script-test suite per `AGENTS.md` test commands and confirm no regressions.
- [x] 6.4 Smoke test in a scratch worker repo bound to a synthetic overmind project folder: approve regeneration with only one local guidance file present, then verify both files are overwritten from the matching artifact before scaffold implementation and are byte-identical.
- [x] 6.5 Verify `SKILL.md` contains no per-file/merge choice and no global-guidance lookup behavior.
