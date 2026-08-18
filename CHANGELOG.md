# CHANGELOG

## v0.2.5 — GitHub Copilot CLI support (2026-08-18)

### Added

- GitHub Copilot CLI as a supported model runner for every model-driven phase,
  using the shared interactive TTY, log capture, prompts, and installed skills.
- Exact Copilot argument handling for configured models and extra options, with
  the rendered phase prompt passed through `-i` as one final argument.

### Changed

- Fresh workers now default all five model-driven phases to `codex` with
  `gpt-5.5`; existing operator-edited model configurations remain
  preserved during reinitialization.
- Runner documentation now covers Copilot installation and authentication
  prerequisites and per-phase mixing with Codex and Claude.

### Quality

- Added runner, configuration, package-resource, and installer coverage for the
  Copilot integration and Codex/GPT-5.5 packaged defaults.

---

## v0.2.4 — Design bootstrap guidance and deterministic pipelines (2026-08-18)

### Added

- Class-aware first-feature bootstrap guidance for project `AGENTS.md` and
  `CLAUDE.md`, with explicit operator approval, recovery backups, verification,
  and rollback-safe pair installation.
- Deterministic design-readiness validation and expanded blueprint / project
  guidance discovery.

### Changed

- Model configuration is validated completely before workflow side effects.
  All five model-driven phases are required and always run in canonical order.
- Non-resume runs must start from a clean `main` or `master`; explicit resume
  continues to support in-progress workflow branches.
- Package and runtime CLI versions now share one verified release value.
- Source distributions are limited to package, test, and release files so local
  agent configuration cannot be included accidentally.

### Quality

- Expanded unit, integration, and skill-helper coverage for bootstrap guidance,
  pipeline configuration, Git synchronization, and bound ASDLC repositories.
- Ruff and full-package mypy checks are clean.

---

## v0.2.0 — Python CLI cutover (2026-06-07)

All operator-facing invocations changed in this release. The bash scripts under
`ai/scripts/` are deleted. Upgrade by installing the Python tool and switching
every invocation using the table below.

### Install

```
# Before (bash era — no install step; repo was pulled locally)
cd /path/to/yasdef
# ... manually ran scripts from ai/scripts/

# After
uv tool install yasdef-worker
yasdef --help
```

Local wheel install from this repository and plain Python venv installation are
also supported; see `Readme.md` for commands.

### Command rename table

| Old command (bash) | New command (yasdef CLI) |
|--------------------|--------------------------|
| `bash .asdlc_worker/scripts/init_asdlc_worker.sh` | `yasdef init <target-repo-path>` |
| `chmod -R +x .asdlc_worker/scripts` | *(no longer needed — tool is installed globally)* |
| `bash .asdlc_worker/scripts/register_worker.sh` | `yasdef register` |
| `bash .asdlc_worker/scripts/orchestrator.sh` | `yasdef run` |
| `bash .asdlc_worker/scripts/orchestrator.sh --resume <step>` | `yasdef run --resume <step>` |
| `bash .asdlc_worker/scripts/orchestrator.sh --dry-run` | `yasdef run --dry-run` |
| `bash .asdlc_worker/scripts/orchestrator.sh --debug -- --step 1.3` | `yasdef run --resume 1.3` |
| `bash .asdlc_worker/scripts/post_review.sh` | `yasdef post-review` |
| *(no equivalent)* | `yasdef uninstall` — remove the global tool |

### Behavior changes

- **Exhausted cached feature**: when `feature_meta_sync.yaml` exists but all
  assigned steps are complete, interactive mode prompts to delete or keep the
  file; non-interactive mode exits non-zero with removal instructions.
- **Merge-back offer**: after `yasdef init` and `yasdef register`, interactive
  mode offers to fast-forward merge the work branch back into the start branch
  (default: no; skipped in non-interactive mode with a reminder).
- **Skill-based pipeline**: the workflow moved fully from broad model
  instructions and generated phase prompts to per-phase `yasdef-worker-*`
  skills as the process authority.
- **No `chmod` needed**: the tool is installed by `uv tool install` and is on
  `PATH` immediately.

### Migration steps for existing installations

1. `uv tool install yasdef-worker`, or use the local wheel / venv install
   options documented in `Readme.md` when developing from a checkout.
2. Replace every `bash .asdlc_worker/scripts/orchestrator.sh` in CI configs,
   wrapper scripts, and operator runbooks with `yasdef run`.
3. Replace `bash .asdlc_worker/scripts/register_worker.sh` with
   `yasdef register`.
4. If you previously ran `bash .asdlc_worker/scripts/init_asdlc_worker.sh` on
   new machines, use `yasdef init <target-repo-path>` instead.
5. Delete any local copies of `ai/scripts/` if you had them checked out.

---

## v0.1.3

- Remove outdated git logic from worker-overmind interaction
- Add init script
- Add AGENTS.md warning and blueprint search
- Add external links processing
- Add first commit work logic

## v0.1.2

- Integration with new coordinator (asdlc folder) — orchestrator can register
  itself in overmind and fetch tasks directly from asdlc folder

## v0.1.1

- CRP-044 — Worker Init Script for Overmind Registration
- CRP-045 — Split Worker Identity Persistence from Registry Coordination
- CRP-046 — UUID-Scoped Step Selection From overmind Git Branch
- CRP-047 — Phase Denial Must Stop Downstream Prompts
- CRP-048 — ai_audit TODO Marker Processing Into Findings
- CRP-050 — Remove Target Bullets From Step Plans
- CRP-051 — In-Phase Readiness Gates

## v0.1.0

- First wave (worker POC) features implemented
- Token consumption reduced ~25-30%
- CRP-037 — Implementation Prompt Slimming
- CRP-038 — Deterministic Concise Implementation Prompt From Step Plan + Design
- CRP-041 — UR Hygiene: Enforce Template Schema + De-dup on Update
- CRP-042 — Optional Feature-Rich Design/Planning Mode
