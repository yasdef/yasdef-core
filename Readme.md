# Yet Another Spec Driven (Enhanced) Framework - YASDEF

## Word from first commit

There’s nothing wrong with vibecoding. Building prototypes with AI — is a new superpower and it’s unlocked a huge wave of experimentation and helps people start something new that really matters. 
But sometimes what you need - is not prototype. Some of us work in complex codebases — often in enterprise environments where predictability, maturity, and long-term maintainability matter more than raw velocity. This is sometimes true for startups as well.
This framework is built to help when vibecoding is not the best option. It uses AI to support developer productivity, but never at the expense of code quality. It is also designed to reduce token consumption so one can work comfortably with an entry-level subscription, regardless of how complex one’s codebase is and how many tasks should be implemented.

This approach can be expressed in a few sentences:
- Governance over “fire-and-forget” prompting.
- Reproducibility over speed.
- Human control over agent swarms.
- Spec-driven science over vibe-magic.

## Ouick start

0. Read this carefully:
- ⚠️ This is pre-alpha — things may break. Use at your own risk. Take precautions before integrating this repo into your project!
- ⚠️ Your `AGENTS.md` will be used as part of the prompt to the AI model, and the AI model may examine your project code — make sure you're comfortable with that.
- ✅ You need the Codex CLI (https://chatgpt.com/codex) available to run this framework, or you can change the model in `ai/setup/models.md` but scripts was not tested with another CLI's

1. Copy-paste the `ai/` folder to the root of your project.

2. Make the bash scripts in `ai/scripts` executable:
  `chmod +x ai/scripts/ai_design.sh ai/scripts/ai_implementation.sh ai/scripts/ai_plan.sh ai/scripts/ai_user_review.sh ai/scripts/ai_audit.sh ai/scripts/orchestrator.sh ai/scripts/post_review.sh ai/scripts/init_worker.sh`

3. Add `AGENTS.md` to the project root. If you don't know what should be in it, ask your model to generate `AGENTS.md` with project-specific best practices. If you already have `AGENTS.md`, make sure it does not embed or conflict with the AI-dev process rules in `AI_DEVELOPMENT_PROCESS.md`.

4. Create `overmind` branch

5. Run `bash ai/scripts/init_worker.sh` to bind your local worker repo to an already registered overmind worker UUID.
   The script prompts for:
   - worker UUID (must already exist in overmind project `workers.yaml`),
   - path to the overmind repo root.
   On success it creates/checks out local branch `overmind`, writes `ai/project_overmind.yaml` there, and commits the change.

6. You need to provide `overmind/implementation_plan.md` and `overmind/reqirements_ears.md` in `overmind` branch with the required format (you can have it in maser but it wont be used by ai, because all worker jobs started from `overmind` branch). If you don't have `overmind/implementation_plan.md` and `overmind/reqirements_ears.md`, ask your model to generate it based on your requirements. You can find prompts in the "Helpers" block below.

7. In `overmind/implementation_plan.md`, keep one shared plan for BE/FE/mobile and mark repo ownership on every step with `#### Repo:`. Only steps with your worker UUID (provided in overmind-side registration and used in p.5) will be available for you. You can add worker ownership manually with `#### Assigned:`. You can assign to your worker any number of steps. Example of `implementation_plan.md` with repo + assigned step:
```
### Step 1.9 Some cool feature here
#### Repo: backend
#### Depends on: none
#### Assigned: 7d88ab4d-be02-4bb2-9c92-d8c8d0c8591a
/some plan bullets/
```

8. Run the orchestrator:
  `bash ai/scripts/orchestrator.sh` and follow the instructions.
  Use debug mode to keep per-step artifacts:
  `bash ai/scripts/orchestrator.sh --debug -- --step 1.3`
  To recover interrupted work for a specific step deterministically:
  `bash ai/scripts/orchestrator.sh --resume <step>`
  Preview planned resume behavior without executing:
  `bash ai/scripts/orchestrator.sh --resume <step> --dry-run`

7. OPTIONAL — allow your AI CLI to work with git (except merge to `main`/`master`) to avoid repeated permission prompts.
  `bash ai/scripts/orchestrator.sh --dry-run`

## Why we need yet another SDD framework?

	•	Current SDD frameworks are great (I strongly recommend you forget about vibecoding and try open-spec, spec-kit, or another SDD framework), but they are built with the purpose of growing a vibecoder into a conscious product manager. That’s not actually what enterprise developer teams need right now.
	•	YASDEF is built for seamless adoption of AI in the usual SDLC — upgrading it to ASDLC. The goal is 10× productivity while keeping enterprise-level quality, familiar processes, and, most importantly, not shifting responsibility from the developer to AI. If that sounds boring — we’re probably on the right track.
	•	We consider AI coding agents as another tool for engineers — maybe the best and most promising one in many years — but still… it’s a tool. And don’t forget: the bottleneck is never technology, it’s always people.
	•	YASDEF has a distributed architecture for distributed teams: someone establishes plans, others write code, we have feedback loops, quality gates, and agile rituals… and we don’t really think we need to throw all of that away just because AI appeared.
	•	YASDEF is about shifting developers from writing code to making architectural decisions and finding effective approaches. AI can write code. The engineer’s duty is to think, decide, and supervise.
	•	We don’t really need to choose between an agile (fluid) and a strict approach when writing code with AI. We prefer to stay agile at the product level, because requirements can appear, change, or disappear unexpectedly. But when AI writes code, the process should be extremely strict and straightforward to get predictable, reproducible, and deterministic results (as much as that’s possible with AI).
	•	We don’t like the idea that a developer works for 5 minutes and spends the rest of the time doing something else. YASDEF is about an approach where we work as long as needed but deliver 10× more value per unit of time. Code quality, maintainability, and readability are not negotiable trade-offs.
	•	We can outsource many tasks to AI — but not thinking and decision-making.

## How this works (or will be)

- **Coordinator:** The Coordinator manages the whole project based on technical requirements, architecture, and core technical decisions. All tasks and subtasks form a cyclic graph. One branch of the graph is a sequence (a stack) of tasks. A stack becomes the source of an implementation plan. Each implementation plan contains a sequence of tasks that can be done one by one. The Coordinator should act agilely, manage the development process and task allocation based on feedback, and constantly optimize and recalculate the graph. The Coordinator never adds new tasks on its own; it only structures them in the graph. Requests to add tasks come from Workers (bottom-up) or from a human operator (top-down) as specific decisions. Coordinator responsible for token management and optimisation, for this it performs task-slicing based on model and reasoning.  

- **Worker:** (/ai) Workers are the actual code implementers. They take the implementation plan as input and split it into reasonable steps. Each step is implemented following a strict AI-dev process. The main goal is to guarantee high code quality while reducing manual coding burden for the operator. This shifts the human operator's role from coding to making complex technical decisions and ensuring architectural quality.

- **AI-dev process:** The AI_DEVELOPMENT_PROCESS.md is a set of rules for Workers and a strict sequence of gates that involve the human operator in some loops. The process flow is: design -> plan -> implementation -> user_review -> ai_audit (post-step audit/review, AI) -> post-review (non-AI). We do not share ai-context between model-driven phases. We run phase-scripts to create a stable, comprehensive prompt from the process artifacts and pass it to the chosen model.

- **Phase-script behavior:** A phase-script managed by orchestrator, creates prompt, then model (via pipe orchestrator -> cli) consumes the script's result as a prompt. Specifically, orchestrator runs a coding agent (cli) with parameters like model, reasoning effort, and a request to run a script. Script-driven prompt generation make input prompt stable and guaranty it fils up context with correct set of system files. 

- **Orchestration:** Since each phase starts as a terminal command, we can orchestrate the whole process from top-level script `ai/scripts/orchestrator.sh`.
  - Worker-assigned discovery rule: when phase step is not provided explicitly, orchestrator resolves the next step from `overmind/implementation_plan.md` using worker UUID (`ai/*_dont_touch.txt`) and `#### Assigned: <uuid>` ownership blocks only.
  - Resume mode: `--resume <step>` evaluates phase completion markers in canonical order (`design -> planning -> implementation -> user_review -> ai_audit -> post_review`) and starts at the first unfinished phase.
  - Determinism rule: any missing/partial/inconsistent marker set is treated as unfinished, so the phase is re-run from phase start.
  - Debug mode: `--debug` switches artifact retention to step-specific logs/prompts (`ai/logs/<project>-<phase>-<step>-log` and step-specific prompt filenames).
  - Default mode (without `--debug`): orchestrator writes only latest-per-phase artifacts (`ai/logs/<project>-<phase>-latest-log` and `ai/prompts/<phase>_prompts/<project>-latest-<phase>-prompt.txt`), overwriting those latest files each run.
  - Non-debug safeguard: previously generated step-specific prompt files are not modified when `--debug` is off.

## AI-dev process main rules

- **Single source of truth for workflow rules**: Behavioral and process rules for AI execution live in `AI_DEVELOPMENT_PROCESS.md`. Scripts stay minimal and phase-scoped. All rules are defined once and referenced; they are never duplicated across phase scripts.
- **Clean separation of concerns**:
  - `AI_DEVELOPMENT_PROCESS.md` defines the generic workflow (phases, gates, artifacts, per-step loop). It is project-agnostic and never includes project-specific details.
  - `AGENTS.md` defines project-specific constraints: build commands, test runners, API specs, validation rules, branch strategy, tool paths, idempotency expectations. It never discusses the AI-dev process itself.
  - Both files are required; they are kept independent so that workflow improvements do not leak into project configuration, and vice versa.
- **Phase isolation**: Each model-driven phase (design, planning, implementation, user review, ai_audit/post-step audit) is executed in a separate AI-agent session with a distinct prompt. Context is never shared between phases (e.g., planning artifacts are frozen when implementation starts). Post-review is a non-AI phase. This ensures each phase uses the most suitable model and reasoning effort.
- **Determinism over speed**: Every decision, blocker, and new finding is recorded in durable artifacts (`decisions.md`, `blocker_log.md`, `open_questions.md`, `step_review_results/`). This enables reproducibility and allows the project to continue without AI assistance at any point. Since technical decisions records in structured format to further retro with team or/and with AI
- **Human in the loop**: Complex technical decisions and architectural choices are not made by the Worker. Workers must explicitly ask the user for decisions before proceeding; user feedback during the dedicated user review phase is incorporated as generalizable rules in `user_review.md` to improve future iterations. 

## Main process artifacts and responsibilities

Each artifact below serves a specific role in the AI-dev process:

- **overmind/reqirements_ears.md**: Source of truth for behavioral requirements and acceptance criteria (EARS format).
- **overmind/implementation_plan.md**: Ordered execution plan at the step level; tracks all tasks and subtasks with story point estimates. Keep one shared plan across backend/frontend/mobile and mark repo ownership per step with `#### Repo:`. Work happens bullet-by-bullet. Updated dynamically as the Coordinator refactors the graph.
- **designs/**: Per-step design artifacts (`feature-<N>.md`) with API/UX and data-flow decisions. Acts as input for planning and implementation.
- **step_plans/**: Per-step planning artifacts (`step-<N>.md`) produced during the "Plan and discuss the step" bullet. Serve as the detailed execution contract for Workers. Include `## Plan (ordered)`, translated functional requirements, preconditions, architecture, risks, and test strategy.
- **blocker_log.md**: Unknowns and blocking issues discovered during implementation, organized by step. Includes impact, required decision, and resolution status. Only for in-progress steps.
- **open_questions.md**: Non-blocking questions tracked per step, reviewed at step planning start. Removed once answered.
- **decisions.md**: Durable technical decisions (Architecture Decision Records) recorded during planning and implementation. Includes decision context, alternatives considered, and rationale. Used to avoid rehashing settled choices.
- **user_review.md**: Rule-based review insights, generalizable feedback patterns, and references to accepted implementations. Evolves as design patterns stabilize.
- **step_review_results/**: Post-step audit findings (`review_result-<N>.md`), organized by severity (Critical/High/Medium/Low). Each finding has an explicit disposition (Accepted/Rejected) and follow-up work assignment.
- **history.md**: Optional step completion log tracking dates, effort, surprises, and key decisions per step.

## Phases inputs and outputs

### Coordinator phases

### Worker cycle  - The AI-dev process runs in six phases per step:

**Phase 1: Design**
- Input: Current `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, `decisions.md`, existing architecture/context docs.
- Output: `ai/designs/feature-<N>.md` with feature-level design decisions and constraints.
- Gate: Design assumptions and unknowns are captured before planning starts.

**Phase 2: Planning**
- Input: Current `overmind/implementation_plan.md`, `overmind/reqirements_ears.md`, `decisions.md`, `blocker_log.md`, `open_questions.md`.
- Input (additional): `ai/designs/feature-<N>.md`.
- Output: `ai/step_plans/step-<N>.md` with `## Plan (ordered)`, translated functional requirements from design-selected EARS blocks, architecture, test strategy, and execution command for the implementation phase.
- Gate: All open questions must be answered before planning completion.

**Phase 3: Implementation**
- Input: Step plan (`ai/step_plans/step-<N>.md`), design (`ai/designs/feature-<N>.md`), source code, test suite, `AGENTS.md`, `decisions.md`.
- Output: Implemented changes on a local topic branch (`step-<N>-implementation`), updated tests/docs/planning artifacts, plus Evidence Reasoning Summary and Review Brief handoff for the next phase.
- Gate: All ordered bullets must be `[x]`, all translated functional requirement checklist items must be `[x]`, verification closure must pass, and implementation does not commit before user review starts.

**Phase 4: User Review**
- Input: Implementation outputs from Phase 3, step plan/design context, `ai/user_review.md`.
- Output: User-requested adjustments on `step-<N>-user-review`, targeted tests/docs updates, and generalized review rules in `ai/user_review.md` when applicable.
- Gate: Entry precheck requires all `## Plan (ordered)` checklist items `[x]` and all translated functional requirement checklist items `[x]` before model execution.

**Phase 5: Post-Step Audit & Review (AI)**
- Input: Implemented + user-review changes, step plan, design, and user feedback outcomes.
- Output: `ai/step_review_results/review_result-<N>.md`, updated `implementation_plan.md`, commit on review branch (`step-<N>-review`). No push or merge to `main`/`master`.
- Gate: Every finding must have an explicit disposition; all accepted work must be captured as follow-up steps or questions.

**Phase 6: Post-Review**
- Input: `ai/step_review_results/review_result-<N>.md`, updated plan artifacts, review branch state.
- Output: Post-review updates (for example metrics/history updates and follow-up step alignment), performed without AI model execution.
- Gate: Review dispositions are reflected in planning artifacts before next step starts.

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

V-0.1.1 (current)
- CRP-044 — Worker Init Script for Overmind Registration (worker now can register in orchestrator with unique id)
- CRP-045 — Split Worker Identity Persistence (`master`) From Registry Coordination (`overmind`)
- CRP-046 — UUID-Scoped Step Selection From `overmind` Git Branch
- CRP-047 — Phase Denial Must Stop Downstream Prompts (improve phase stop/resume logic)
- CRP-048 — ai_audit TODO Marker Processing Into Findings (now you can add TODO and they will be converted to folowing tasks by AI)
- CRP-050 — Remove Target Bullets From Step Plans (now plan, implementation and user_review steps operates with internat complex plan and set od FRs, design and ai_audit phases translate EARS and high-level plan to and from this inter-step plan/FRs)
- CRP-051 — In-Phase Readiness Gates (significanly improved betwen-phases sanity check logic, extract logic from orchestrator to hooks, 2-times check when finish one phase and when start following one)
- removed --phase support specific phase cant be run anymore via orchestrator
- sync between overmind and actual feature/master branch fixed


2. known problems/to-do's:
- only codex cli supported
- you need to manually ctrl-c from codex session in the end of each model-driven phase
- ai_audit step creates relatively small improvement/tech-debt steps (5-8 SP) which is not efficient from token management perspective
- incorrect SP countion on post_review

3. main plans
- change bash scripts to lightweight cli (wrapper above coding agent cli's), see yasdef-wrapper
- investigate "skills" usage
- coordinator service
- onboarding script

### security_improvement_proposals

Scope: General
- Introduce checksums 
Scope: command-execution safety (non-git concerns).
- Restrict runner command to trusted values only. Do not execute arbitrary binaries from config; use an allowlist-based runner mapping.
- For implementation execution, use only `ai/setup/models.md` as the trusted source of runner/model/args.
- Treat step-plan metadata as non-executable context only (for example prompt path/version), not as command authority.
- Add integrity checks for command-driving artifacts (at minimum `ai/setup/models.md`) using a trust-lock/checksum file and require explicit re-trust after changes.
- Run child model commands with a minimal environment allowlist by default: `PATH`, `HOME`, `LANG`, `TMPDIR`.
- Add explicit opt-in for extra environment variables (for example `--pass-env KEY1,KEY2`) instead of inheriting full environment.

### Helpers
- Here is the prompt to create `overmind/reqirements_ears.md` from usual technical requirements (run from repo root):
`carefully examine technical_requirements.md and create overmind/reqirements_ears.md; use the reqirements_ears template and golden example from the standalone yasdef-overmind repo`
--Here is the prompt to create `overmind/implementation_plan.md` from `overmind/reqirements_ears.md` and `technical_requirements.md` (run from repo root): 
`carefully examine all project files especially AGENTS.md and README.md if they are presented, then from overmind/reqirements_ears.md, technical_requirements.md, and feature_contract_delta.md (all mandatory when presented in the feature flow), create overmind/implementation_plan.md using the implementation_plan template and golden example from the standalone yasdef-overmind repo; keep a single implementation plan for backend/frontend/mobile, assign every step to exactly one repo with \`#### Repo:\`, use \`#### Depends on:\` when cross-repo sequencing matters, add already implemented steps as well as not implemented ones, and slice not implemented steps by concrete function/component so implementation effort stays roughly balanced (10-20 SP means 1-3 day of work for a human dev)`

### License

This project is licensed under the MIT License. See `LICENSE`.
