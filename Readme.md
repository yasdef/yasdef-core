# Yet Another Spec Driven (Enhanced) Framework - YASDEF

## Word from first commit

There's nothing wrong with vibecoding. Building prototypes with AI — is a new superpower and it's unlocked a huge wave of experimentation and helps people start something new that really matters. 
But sometimes what you need - is not prototype. Some of us work in complex codebases — often in enterprise environments where predictability, maturity, and long-term maintainability matter more than raw velocity. This is sometimes true for startups as well.
This framework is built to help when vibecoding is not enough. It uses AI to support developer productivity, but never at the expense of code quality. It is also designed to reduce token consumption so one can work comfortably with an entry-level subscription, regardless of how complex one's codebase is and how many tasks should be implemented.

This approach can be expressed in a few sentences:
- Spec-driven, but you dont need to write and read specs -> developers will deliver maximum value by making the right system design decisions.
- Human in the loop who supervise the model -> guaranty of predictable code quality level and responcibility shift from model to operator
- Strict phase-based context management -> stable reproduceble outcome and efficient token usage 
- Design/Plan split -> separation of "WHAT we building" question from "HOW we build", which previent model drift and improve codebase consistency
- Final ai-backed audit for each implementation step -> clear and efficient way to handle implementation issues

## Quick start

0. Read this carefully:
- ⚠️ This is alpha — things may break. Use at your own risk. Take precautions before integrating this repo into your project!
- ⚠️ Your `AGENTS.md` will be used as part of the prompt to the AI model, and the AI model may examine your project code — make sure you're comfortable with that. 
- ✅ You need a supported AI CLI available (currently `codex cli` and `claude cli`). Configure your model runner in `.asdlc_worker/setup/models.md` after init.
- ✅ You need at least Python3 installed. For real prod instalation you need [uv](https://docs.astral.sh/uv/)
- ✅ Yasdef worker is part of framework. You need yasdef-coordinator to make it work. To get started with yasdef-coordinator you can a) examine yasdef-coordinator Readme.md here https://github.com/yasdef/yasdef-overmind/blob/main/README.md and follow instructions. b) mock yasdef-coordinator if you just need to take a look at framework. Step-by-step instruction can be found in this readme (scroll down to "How to mock yasdef-coordinator" section). 

1. Install the `yasdef` tool. Recommended global install requires [uv](https://docs.astral.sh/uv/):
  
  * Option A (prod level instalation):

   ```
   uv tool install yasdef-worker
   ```
   This puts `yasdef` on your `PATH`. Run `yasdef --help` to verify.

  * Option B (self-build instalation): 
   
   During local development from this repository, you can build and install the local wheel instead:
   ```
   cd /path/to/yasdef
   rm -rf dist
   uv build
   uv tool install --force dist/*.whl
   yasdef --help
   ```

  * Option C (no UV, simplest option just to try it out):

   Without `uv`, install into a normal Python venv:
   ```
   python3.11 -m venv ~/.venvs/yasdef
   source ~/.venvs/yasdef/bin/activate
   python -m pip install /path/to/yasdef
   yasdef --help
   ```
   That same venv should be activated from any worker repo before running `yasdef`:
   ```
   cd /path/to/worker-repo
   source ~/.venvs/yasdef/bin/activate
   yasdef run
   ```
   ⚠️ when you re-install yasdef it will not update installed skills in project-level folders (like .claude, .codex etc) - re-run init phase (see below)

2. Bootstrap a worker directory:
   ```
   yasdef init <path-to-your-worker-repo>
   ```
   The command creates `.asdlc_worker/` inside the target git repo, installs worker skills into `.claude/skills/`, `.codex/skills/`, `.github/skills/`, and `.agents/skills/`, and commits on a new `init_yasdef_worker` branch. Configure the model runner in `.asdlc_worker/setup/models.md` before first run. ⚠️ After init phase will be finished you need to merge changes in main/master manually.

   This is also valid way to re-write this folders to apply skills.

3. Add `AGENTS.md` to the project root. If you don't know what should be in it, ask your model to generate `AGENTS.md` (or `CLAUDE.md` for claude.cli) with project-specific best practices in a root of you working project - it's extremely important for codebase consistency.

4. Register this worker with an ASDLC project:
  - prepare the ASDLC project folder path, for example `<asdlc-repo>/projects/<project-id>`
  - prepare your worker UUID from that ASDLC project's `workers.yaml`
   ```
   cd /path/to/worker-repo
   yasdef register
   ```
   The command prompts for the ASDLC project path and worker UUID. The path must be the project folder that contains `workers.yaml`, `init_progress_definition.yaml`, and feature folders; for the coordinator layout this is usually `<asdlc-repo>/projects/<project-id>`, not the ASDLC repo root. The worker UUID must already exist in that project's `workers.yaml`. The command reads `project_id` from `<asdlc-project-path>/init_progress_definition.yaml` under `meta_info.project_id`, writes a deterministic binding to `.asdlc_worker/project_overmind.yaml`, and commits on a new `register_yasdef_worker_in_coordinator` branch. This path is not the implementation codebase repo.

5. Run the worker:

  - simply run worker and follow interactive steps.
   ```
   yasdef run
   ```

  - here is the brief explanation how exactly worker will operate, just in case anyone interested, since all works in interactive mode it can be skiped

   The worker reads `.asdlc_worker/project_overmind.yaml`, refreshes the bound ASDLC project worktree with `git pull --rebase`, and scans feature folders for `implementation_plan.md` / `requirements_ears.md`.

   5.1. Feature and step selection:
   - The worker looks for steps assigned to its `worker_uuid` with `#### Assigned: <worker-uuid>`.
   - If `.asdlc_worker/feature_meta_sync.yaml` points to a valid unfinished feature, the worker reuses it.
   - Otherwise, if one candidate feature exists, the worker selects it automatically.
   - If multiple candidate features exist, the worker asks the operator to choose one.
   - The selected feature and step are written back to `.asdlc_worker/feature_meta_sync.yaml`.

   5.2. Worker execution:
   - The worker runs configured phases one by one in order, normally `design -> planning -> implementation -> user_review -> ai_audit -> post_review`.
   - Each model-driven phase uses its installed `yasdef-worker-*` skill and the selected feature/step context.
   - Each model-driven phase uses model and (sometimes) reasoning depth based on `/setup/models.md`, so it can be changed manually at any time. You can mix different cli's and models in one setup, it'll work. ⚠️ All works in interactive mode, NOT headless (which will save your tokens).
   - After `ai_audit`, the worker commits the updated ASDLC implementation plan and pushes it through the bound ASDLC repo. If outbound sync fails, interactive mode offers retry/finish; non-interactive mode stops before `post_review`.

6. To recover interrupted work for a specific step deterministically:
   ```
   yasdef run --resume <step>
   ```

7. OPTIONAL — uninstall the tool when no longer needed:
   ```
   yasdef uninstall
   ```
   This removes the global `yasdef` tool. Worker skills and `.asdlc_worker/` artifacts in target repos are unaffected.

## Why we need yet another SDD framework?

* Current SDD frameworks are great (I strongly recommend you forget about vibecoding and try open-spec, spec-kit, or another SDD framework), but they are built with the purpose of growing a vibecoder into a conscious product manager. That's not actually what enterprise developer teams need right now.
* YASDEF is built for seamless adoption of AI in the usual SDLC — upgrading it to ASDLC. The goal is 10× productivity while keeping enterprise-level quality, familiar processes, and, most importantly, not shifting responsibility from the developer to AI. If that sounds boring — we're probably on the right track.
* We consider AI coding agents as another tool for engineers — maybe the best and most promising one in many years — but still… it's a tool. And don't forget: the bottleneck is never technology, it's always people.
* YASDEF has a distributed architecture for distributed teams: someone establishes plans, others write code, we have feedback loops, quality gates, and agile rituals… and we don't really think we need to throw all of that away just because AI appeared.
* YASDEF is about shifting developers from writing code to making architectural decisions and finding effective approaches. AI can write code. The engineer's duty is to think, decide, and supervise.
* We don't really need to choose between an agile and a strict approach when writing code with AI. We prefer to stay agile at the product level, because requirements can appear, change, or disappear unexpectedly. But when AI writes code, the process should be extremely strict and straightforward to get predictable, reproducible, and deterministic results (as much as that's possible with AI).
* We don't like the idea that a developer works for 5 minutes and spends the rest of the time doing something else. YASDEF is about an approach where we work as long as needed but deliver 10× more value per unit of time. Code quality, maintainability, and readability are not negotiable trade-offs.
* We can outsource many tasks to AI — but not thinking and decision-making.

## How this works (or will be)

- **Coordinator:** The Coordinator manages the whole project based on technical requirements, architecture, and core technical decisions. All tasks and subtasks form a cyclic graph. Each implementation plan contains a sequence of tasks that can be done one by one. The Coordinator should act agilely, manage the development process and task allocation based on feedback, and constantly optimize and recalculate the graph. The Coordinator never adds new tasks on its own; it only structures them in the graph. Requests to add tasks come from Workers (bottom-up) or from a human operator (top-down) as specific decisions. 

- **Worker:** Workers are the actual code implementers. They take the implementation plan as input and split it into reasonable steps. Each step is implemented following a strict AI-dev process. The main goal is to guarantee high code quality while reducing manual coding burden for the operator. This shifts the human operator's role from coding to making complex technical decisions and ensuring architectural quality.

- **Phase-script behavior:** A phase-script, managed by the model, creates a task context, then the model (via pipe worker -> cli) consumes this context. Specifically, the worker runs a coding agent (cli) with parameters like model, reasoning effort, and a request to run a script. Script-driven context generation makes the input prompt stable.

- **Orchestration:** `yasdef run` drives the configured worker phase pipeline.
  - Worker/project binding rule: reads `worker_uuid` and `project_id` from `.asdlc_worker/project_overmind.yaml`.
  - Phase configuration rule: phase order comes from `.asdlc_worker/setup/models.md`; phases normally run as `design -> planning -> implementation -> user_review -> ai_audit -> post_review`.
  - Candidate discovery rule: scans bound ASDLC project features (`<asdlc-project-path>/<feature-id>/implementation_plan.md`), skipping `.git` and directories without usable `implementation_plan.md` / `requirements_ears.md`, and considers only `#### Assigned: <worker-uuid>` blocks.
  - Bound-project freshness rule: when the bound ASDLC project path is inside a Git worktree, the worker runs `git pull --rebase` before feature discovery.
  - Explicit selection rule: `0` candidates fails, `1` candidate auto-selects, and `>1` candidates require explicit user choice.
  - Single-source rule: reads and writes `implementation_plan.md` and `requirements_ears.md` directly at the bound-source paths — there is no local runtime mirror.
  - Post-ai_audit sync rule: before `post_review`, stages the updated bound-source `implementation_plan.md`, commits it in the bound ASDLC repo, runs `git pull --rebase`, and pushes on success.
  - Outbound failure rule: commit/rebase/push failures offer exactly `1. retry` or `2. finish`; `finish` continues to `post_review`, while non-interactive runs stop before `post_review`.
  - Feature sync state: records selected feature metadata in `.asdlc_worker/feature_meta_sync.yaml` (4 fields: `project_id`, `worker_uuid`, `feature_id`, `selected_step`); valid metadata is sticky across runs. Stale metadata (identity mismatch or missing bound-source plan) is discarded and triggers slow-path discovery. If the stored feature is blocked by an upstream step, exits with an explicit blocker message. If the stored feature is exhausted (all assigned bullets complete), offers an interactive prompt to delete `.asdlc_worker/feature_meta_sync.yaml` (choice 1) or exit for manual handling (choice 2); non-interactive mode exits with an error. To reselect a feature manually, remove `.asdlc_worker/feature_meta_sync.yaml` before re-running.
  - Resume mode: `--resume <step>` evaluates phase completion markers in canonical order (`design -> planning -> implementation -> user_review -> ai_audit -> post_review`) and starts at the first unfinished phase.
  - Determinism rule: any missing/partial/inconsistent marker set is treated as unfinished, so the phase is re-run from phase start.

## AI-dev process main rules

- **Single source of truth for workflow rules**: Behavioral and process rules for AI execution live in the per-phase worker skills (`.claude/skills/yasdef-worker-*`, also installed under `.codex/`, `.github/`, `.agents/`). Scripts stay minimal and phase-scoped. All rules are defined once in the relevant skill and referenced; they are never duplicated across phase scripts.
- **Clean separation of concerns**:
  - The worker skills define the generic workflow (phases, gates, artifacts, per-step loop). They are project-agnostic and never include project-specific details.
  - `AGENTS.md` defines project-specific constraints: build commands, test runners, API specs, validation rules, branch strategy, tool paths, idempotency expectations. It never discusses the AI-dev process itself.
  - Both the skills and `AGENTS.md` are required; they are kept independent so that workflow improvements do not leak into project configuration, and vice versa.
- **Phase isolation**: Each model-driven phase (design, planning, implementation, user review, ai_audit/post-step audit) is executed in a separate AI-agent session with a distinct prompt. Context is never shared between phases (e.g., planning artifacts are frozen when implementation starts). Post-review is a non-AI phase. This ensures each phase uses the most suitable model and reasoning effort.
- **Determinism over speed**: Every decision, blocker, and new finding is recorded in durable artifacts (`decisions.md`, `blocker_log.md`, `open_questions.md`, `step_review_results/`). This enables reproducibility and allows the project to continue without AI assistance at any point. Since technical decisions records in structured format to further retro with team or/and with AI
- **Human in the loop**: Complex technical decisions and architectural choices are not made by the Worker. Workers must explicitly ask the user for decisions before proceeding; user feedback during the dedicated user review phase is incorporated as generalizable rules in `user_review.md` to improve future iterations. 

## Main process artifacts and responsibilities

Each artifact below serves a specific role in the AI-dev process:

- **<asdlc-project-repo>/<feature-id>/requirements_ears.md**: Source-of-truth behavioral requirements for each feature (EARS format).
- **<asdlc-project-repo>/<feature-id>/implementation_plan.md**: Source-of-truth execution plan for each feature; `#### Assigned:` routes work to workers.
- **.asdlc_worker/project_overmind.yaml**: Durable local binding created by `yasdef register`; stores the bound ASDLC repo path, `project_id`, worker UUID, class, and status.
- **.asdlc_worker/feature_meta_sync.yaml**: Selected-feature cache (`project_id`, `worker_uuid`, `feature_id`, `selected_step`) used for traceability and `--resume` reuse.
- **.asdlc_worker/step_designs/**: Per-step design artifacts (`step-<N>-<feature-id>-design.md`) with scope, data-flow, API/UX, risks, and planning handoff decisions.
- **.asdlc_worker/step_plans/**: Per-step planning artifacts (`step-<N>-<feature-id>.md`) that define ordered implementation work, translated functional requirements, architecture, risks, and test strategy.
- **.asdlc_worker/blocker_log.md**: Durable blocker ledger for unresolved issues that stop progress.
- **.asdlc_worker/open_questions.md**: Durable non-blocking question ledger for questions that should be resolved in the appropriate phase.
- **.asdlc_worker/decisions.md**: Durable technical decisions recorded during the worker process. Used to avoid rehashing settled choices.
- **.asdlc_worker/user_review.md**: Generalizable user-review rules and accepted feedback patterns that should influence future work.
- **.asdlc_worker/step_review_results/**: Post-step audit findings (`review_result-<N>-<feature-id>.md`). Each finding has exactly one terminal disposition: `follow_up_created`, `raised_to_coordinator`, or `rejected`.
- **.asdlc_worker/history.md**: Step completion log tracking outcomes, effort, surprises, and key decisions.

## What's done + plans

V-0.0.1

1. what's added:
- main architecture and concept findings
- based functionality in form of bash scripts
- templates and golden examples for all artifacts
- orchestrator.sh, so all steps run semi-automatically from 1 command
- orchestrator runs phase sessions with isolated context
- different model and reasonong depth for each phase (/setup/models.sh)
- each finished step of plan has recorded metrics (including token counts) in history.md
- each phase can be run separately (manually)

V-0.0.2

1. whats added
- new design step
- phase scripts improved significantly

V-0.0.3

1. whats added
- CRP-023 — Evidence-Based Bullet Completion Gate (model check if implementation plan bulets are realy implemented with strict prove of implementation gate)
- CRP-025 — Orchestrator Explicit Debug Mode for Logs and Prompts (if no --debug flag only "latest" step atrifacts will be recorded)
- CRP-026 — Strict Numbered Decision Prompts in Planning (on planing model always asked with 1 and 2 to simplify user answer)
- CRP-028 — Orchestrator Resume Mode per Step (run orchestrator with --resume <step> flag to proceed current step from last finished phase)
- CRP-011 — Human Review Explanation Mode ai helps user to perform codereview

V-0.0.4

1. whats added
- CRP-030 — Extract User Review as a Distinct Phase (Context Optimization)
- CRP-031 — Review Brief Output (improved), more human-friendly and product oriented description)
- CRP-032 — Evidence Reasoning Summary in Model Output (improved) - model povide evidence that implementation is done to user (stdout)
- CRP-033 — Rename Review Phase to `ai_audit` (Consistent Phase Naming)

V-0.0.5

1. whats added
- CRP-034 — Move `implementation_plan.md` Bullet-Closure Gate to `ai_audit` (now we check implementation plan bullets on ai audit phase, implementation phase works only with internal ordered plan)
- CRP-035 — User Review Gate Uses Step Plan Ordered Checkboxes (we use now internal implementation ordered plan on user_review)
- CRP-036 — Orchestrator Resume Based on Ordered Plan State
- CRP-039 — Planning Gate: Step Plan Must Declare Applicable UR Shortlist (improve how ai works with previous user review items)

V-0.1.0

- first wave (worker POC) features implemented
- reduce token consumption about 25-30%
- CRP-037 — Implementation Prompt Slimming (Rule De-dup)
- CRP-038 — Deterministic Concise Implementation Prompt From Step Plan + Design
- CRP-041 — UR Hygiene: Enforce Template Schema + De-dup on Update
- CRP-042 — Optional Feature-Rich Design/Planning Mode

V-0.1.1
- CRP-044 — Worker Init Script for Overmind Registration (worker now can register in orchestrator with unique id)
- CRP-045 — Split Worker Identity Persistence (`master`) From Registry Coordination (`overmind`)
- CRP-046 — UUID-Scoped Step Selection From `overmind` Git Branch
- CRP-047 — Phase Denial Must Stop Downstream Prompts (improve phase stop/resume logic)
- CRP-048 — ai_audit TODO Marker Processing Into Findings (now you can add TODO and they will be converted to folowing tasks by AI)
- CRP-050 — Remove Target Bullets From Step Plans (now plan, implementation and user_review steps operates with internat complex plan and set od FRs, design and ai_audit phases translate EARS and high-level plan to and from this inter-step plan/FRs)
- CRP-051 — In-Phase Readiness Gates (significanly improved betwen-phases sanity check logic, extract logic from orchestrator to hooks, 2-times check when finish one phase and when start following one)
- removed --phase support specific phase cant be run anymore via orchestrator
- sync between overmind and actual feature/master branch fixed

V-0.1.2
- add integration with new coordinator (asdlc folder) - now orchestrator can register itself in overmind and 
fetch tasks directly from asdlc folder for particular feature (user can select if mutliple features available) 

V-0.1.3
- remove outdated git logic from worker-overmind interaction
- add init script
- add agents.md warning and blueprint search
- add external links processing
- add first commit work logic

V-0.2.0
- Python CLI (`yasdef`) replaces all bash scripts — see CHANGELOG.md for the full command rename table
- Phase rules and helper scripts for all phases now is agentic skills, setup in native folders (.codex, .claude etc) in init phase 

V-0.2.1 (current)
- multiple bug fixes


2. known problems/to-do's:
- incorrect SP countion on post_review


### security_improvement_proposals

- **Config trust check:** add a small trust file for `.asdlc_worker/setup/models.md` so runner/model changes require explicit operator approval before execution.
- **Minimal child environment:** run model CLI subprocesses with a narrow environment allowlist and add explicit opt-in for extra variables when needed.
- **Path safety:** continue rejecting symlinks and path escapes during `yasdef init`; extend the same checks to any future writable install/runtime paths.
- **Prompt-input boundaries:** treat implementation plans, step plans, and model outputs as data only; never let artifact content become executable command arguments.
- **Audit trail:** record runner, model, phase, branch, selected feature/step, and relevant config checksum in `.asdlc_worker/history.md` or a dedicated run log.
- **Secret hygiene:** add lightweight checks to avoid printing common secret-like values from child command environments or captured logs.


## How to mock yasdef-coordinator

Create a minimal mock ASDLC project folder for local testing.
✅ Or you can just pass this instruction to you model/agent

---
Instruction for mock yasdef-coordinator:

Required files:
- Worker repo before `yasdef init`: any existing Git repo root.
- ASDLC project folder before `yasdef register`: root `init_progress_definition.yaml` with `meta_info.project_id`, and root `workers.yaml` with the worker UUID, class, and status.
- Feature folder before `yasdef run`: `requirements_ears.md` and `implementation_plan.md`.

Create the mock ASDLC project folder:

```bash
mkdir -p /tmp/mock-asdlc/project-demo/feature-demo
cd /tmp/mock-asdlc/project-demo
git init -b main
git config user.name "Mock ASDLC"
git config user.email "mock-asdlc@example.local"
cat > init_progress_definition.yaml <<'EOF'
meta_info:
  project_id: project-demo
EOF
cat > workers.yaml <<'EOF'
workers:
  - uuid: worker-demo
    class: platform
    status: ready
EOF
touch feature-demo/feature_request.txt
git add .
git commit -m "Create mock ASDLC project"
git init --bare ../project-demo-remote.git
git remote add origin ../project-demo-remote.git
git push -u origin main
```

--- IF YOU ARE USER ---
Fill `feature-demo/feature_request.txt` with the feature you want to implement.

--- IF YOU ARE MODEL/AGENT ---
ask user to provide you a path to valid requirements in txt format, examine them, ask user if something not clear before starting next prompts. Then run Prompt to create `requirements_ears.md` (see below). Then run Prompt to create `implementation_plan.md`, use `requirements_ears.md` as valid input for `implementation_plan.md`.
--- IF YOU ARE MODEL/AGENT BLOCK END---

Prompt to create `requirements_ears.md`:

`Carefully examine feature-demo/feature_request.txt and create feature-demo/requirements_ears.md in EARS format. Keep requirements clear, testable, and scoped to this feature. Respect this strict structure:`

```markdown
# Requirements (EARS)

System name: <feature/system name>
Scope: <one paragraph describing included behavior and explicit exclusions>

---

## Overview
- Product/Domain: <domain>
- Goals: <goal list in one line>
- Out of scope: <explicit exclusions>

## Glossary
- <Term>: <meaning>

## Actors
- <Actor>: <what they do>

## Assumptions
- <Assumption or unresolved gap>

---

## Requirements

### Requirement 1 — <short requirement title>
**User Story:** As a <actor>, I want <capability>, so that <outcome>.

**Acceptance Criteria (EARS):**
- WHEN <trigger>, THE <system name> SHALL <observable behavior>.

**Verification:** <test or evidence that proves this requirement>
```

Prompt to create `implementation_plan.md`:

`Carefully examine feature-demo/feature_request.txt and feature-demo/requirements_ears.md, then create feature-demo/implementation_plan.md. Keep one implementation plan for all repos, add concrete steps, include #### Repo: for every step, include #### Assigned: worker-demo for worker-owned steps, use #### Depends on: when sequencing matters, and keep each step small enough for one focused implementation cycle. Respect this strict structure:`

```markdown
# Implementation Plan

Use one shared implementation plan for the whole feature.
Ground the plan in `feature_request.txt` and `requirements_ears.md`.
Each step belongs to exactly one repo class so workers can execute independently while following one ordered delivery sequence.

### Step 1.1 <short step title> [REQ-1]
Est. step total: <number> SP
#### Repo: <backend|frontend|mobile|platform|docs>
#### Depends on: none
#### Evidence: <requirement ids, files, or components that justify the step>
#### Assigned: worker-demo
- [ ] Plan and discuss the step
- [ ] <concrete implementation task>
- [ ] <focused verification task>
- [ ] Review step implementation
```

Commit generated ASDLC artifacts before registering/running a worker:

```bash
git add .
git commit -m "Add feature plan"
git push
```

### License

This project is licensed under the MIT License. See `LICENSE`.
