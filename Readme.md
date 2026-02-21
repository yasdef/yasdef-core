## Yet Another Spec Driven (Enhanced) Framework - YASDEF

### Word from first commit

There’s nothing wrong with vibecoding. Building prototypes with AI — is a new superpower and it’s unlocked a huge wave of experimentation and helps people start something new that really matters. 
But sometimes what you need - is not prototype. Some of us work in complex codebases — often in enterprise environments where predictability, maturity, and long-term maintainability matter more than raw velocity. This is sometimes true for startups as well.
This framework is built to help when vibecoding is not the best option. It uses AI to support developer productivity, but never at the expense of code quality. It is also designed to reduce token consumption so one can work comfortably with an entry-level subscription, regardless of how complex one’s codebase is and how many tasks should be implemented.

This approach can be expressed in a few sentences:
- Governance over “fire-and-forget” prompting.
- Reproducibility over speed.
- Human control over agent swarms.
- Spec-driven science over vibe-magic.

### Quick start

0. Read this carefully:
- ⚠️ This is pre-alpha — things may break. Use at your own risk. Take precautions before integrating this repo into your project!
- ⚠️ Your `AGENTS.md` will be used as part of the prompt to the AI model, and the AI model may examine your project code — make sure you're comfortable with that.
- ✅ You need the Codex CLI (https://chatgpt.com/codex) available to run this framework, or you can change the model in `ai/setup/models.md` but scripts was not tested with another CLI's

1. Copy-paste the `ai/` folder to the root of your project.

2. Make the bash scripts in `ai/scripts` executable:
  `chmod +x ai/scripts/ai_design.sh ai/scripts/ai_implementation.sh ai/scripts/ai_plan.sh ai/scripts/ai_review.sh ai/scripts/orchestrator.sh ai/scripts/post_review.sh`

3. You need to provide `implementation_plan.md` in certain format, it should be in root of your project

4. If you run Worker standalone without Coordinator and don't have implementation_plan.md ask your model to generate it based on any plan or requirements you have. You can find prompt in "Helpers" block below. 

5. Add `AGENTS.md` to the project root. If you don't know what should be in it, ask your model to generate `AGENTS.md` with project-specific best practices. If you already have `AGENTS.md`, make sure it does not embed or conflict with the AI-dev process rules in `AI_DEVELOPMENT_PROCESS.md`.

6. Run the orchestrator:
  `bash ai/scripts/orchestrator.sh` and follow the instructions.

7. OPTIONAL — allow your AI CLI to work with git (except merge to `main`/`master`) to avoid repeated permission prompts.
  `bash ai/scripts/orchestrator.sh --dry-run`


### Why we need yet another SDD framework?

- I don't like choosing between an agile (fluid) and a strict approach when writing code with AI. I want both. I prefer to be agile at the product level because requirements can appear, change, or disappear unexpectedly. But when AI writes code for me, I want the process to be extremely strict and straightforward to get predictable, reproducible, and deterministic results (as far as that's possible with AI).
- I don't like the idea that a developer works 5 minutes and spends the other 55 minutes doing something else—like playing videogames or doing yoga. I prefer an approach where we work as long as needed but deliver 10× more value per hour. Code quality, maintainability, and readability are not negotiable trade-offs. We should be able to drop all AI tools and continue the project by hand without problems at any time.
- I don't like using dozens of different subagents just to map our AI-dev process to an organization chart. I prefer to avoid unnecessary complexity.
- I agree that we can outsource many tasks to AI, but not thinking and decision making.

### How this works (or will be)

- **Coordinator:** (CURRENTLY NOT AVAILABLE) The Coordinator manages the whole project based on technical requirements, architecture, and core technical decisions. All tasks and subtasks form a cyclic graph. One branch of the graph is a sequence (a stack) of tasks. A stack becomes the source of an implementation plan. Each implementation plan contains a sequence of tasks that can be done one by one. The Coordinator should act agilely, manage the development process and task allocation based on feedback, and constantly optimize and recalculate the graph. The Coordinator never adds new tasks on its own; it only structures them in the graph. Requests to add tasks come from Workers (bottom-up) or from a human operator (top-down) as specific decisions. Coordinator responsible for token management and optimisation, for this it performs task-slicing based on model and reasoning.  

- **Worker:** Workers are the actual code implementers. They take the implementation plan as input and split it into reasonable steps. Each step is implemented following a strict AI-dev process. The main goal is to guarantee high code quality while reducing manual coding burden for the operator. This shifts the human operator's role from coding to making complex technical decisions and ensuring architectural quality.

- **AI-dev process:** The AI_DEVELOPMENT_PROCESS.md is a set of rules for Workers and a strict sequence of gates that involve the human operator in some loops. The process flow is: design -> plan -> implementation + user review -> post-step audit and review (AI) -> post-review (non-AI). We do not share ai-context between model-driven phases. We run phase-scripts to create a stable, comprehensive prompt from the process artifacts and pass it to the chosen model.

- **Phase-script behavior:** A phase-script managed by orchestrator, creates prompt, then model (via pipe orchestrator -> cli) consumes the script's result as a prompt. Specifically, orchestrator runs a coding agent (cli) with parameters like model, reasoning effort, and a request to run a script. Script-driven prompt generation make input prompt stable and guaranty it fils up context with correct set of system files. 

- **Orchestration:** Since each phase starts as a terminal command, we can orchestrate the whole process from top-level script `ai/scripts/orchestrator.sh`.

### AI-dev process main rules

- **Single source of truth for workflow rules**: Behavioral and process rules for AI execution live in `AI_DEVELOPMENT_PROCESS.md`. Scripts stay minimal and phase-scoped. All rules are defined once and referenced; they are never duplicated across phase scripts.
- **Clean separation of concerns**:
  - `AI_DEVELOPMENT_PROCESS.md` defines the generic workflow (phases, gates, artifacts, per-step loop). It is project-agnostic and never includes project-specific details.
  - `AGENTS.md` defines project-specific constraints: build commands, test runners, API specs, validation rules, branch strategy, tool paths, idempotency expectations. It never discusses the AI-dev process itself.
  - Both files are required; they are kept independent so that workflow improvements do not leak into project configuration, and vice versa.
- **Phase isolation**: Each model-driven phase (design, planning, implementation + user review, post-step audit/review) is executed in a separate AI-agent session with a distinct prompt. Context is never shared between phases (e.g., planning artifacts are frozen when implementation starts). Post-review is a non-AI phase. This ensures each phase uses the most suitable model and reasoning effort.
- **Determinism over speed**: Every decision, blocker, and new finding is recorded in durable artifacts (`decisions.md`, `blocker_log.md`, `open_questions.md`, `step_review_results/`). This enables reproducibility and allows the project to continue without AI assistance at any point. Since technical decisions records in structured format to further retro with team or/and with AI
- **Human in the loop**: Complex technical decisions and architectural choices are not made by the Worker. Workers must explicitly ask the user for decisions before proceeding; user feedback during implementation + user review is incorporated as generalizable rules in `user_review.md` to improve future iterations. 

### Main process artifacts and responsibilities

Each artifact below serves a specific role in the AI-dev process:

- **requirements_ears.md**: Source of truth for behavioral requirements and acceptance criteria (EARS format).
- **implementation_plan.md**: Ordered execution plan at the step level; tracks all tasks and subtasks with story point estimates. Work happens bullet-by-bullet. Updated dynamically as the Coordinator refactors the graph.
- **designs/**: Per-step design artifacts (`feature-<N>.md`) with API/UX and data-flow decisions. Acts as input for planning and implementation.
- **step_plans/**: Per-step planning artifacts (`step-<N>.md`) produced during the "Plan and discuss the step" bullet. Serve as the detailed execution contract for Workers. Include scope, preconditions, architecture, risks, and test strategy.
- **blocker_log.md**: Unknowns and blocking issues discovered during implementation, organized by step. Includes impact, required decision, and resolution status. Only for in-progress steps.
- **open_questions.md**: Non-blocking questions tracked per step, reviewed at step planning start. Removed once answered.
- **decisions.md**: Durable technical decisions (Architecture Decision Records) recorded during planning and implementation. Includes decision context, alternatives considered, and rationale. Used to avoid rehashing settled choices.
- **user_review.md**: Rule-based review insights, generalizable feedback patterns, and references to accepted implementations. Evolves as design patterns stabilize.
- **step_review_results/**: Post-step audit findings (`review_result-<N>.md`), organized by severity (Critical/High/Medium/Low). Each finding has an explicit disposition (Accepted/Rejected) and follow-up work assignment.
- **history.md**: Optional step completion log tracking dates, effort, surprises, and key decisions per step.

### Phases inputs and outputs

The AI-dev process runs in five phases per step:

**Phase 1: Design**
- Input: Current `implementation_plan.md`, `requirements_ears.md`, `decisions.md`, existing architecture/context docs.
- Output: `ai/designs/feature-<N>.md` with feature-level design decisions and constraints.
- Gate: Design assumptions and unknowns are captured before planning starts.

**Phase 2: Planning**
- Input: Current `implementation_plan.md`, `requirements_ears.md`, `decisions.md`, `blocker_log.md`, `open_questions.md`.
- Input (additional): `ai/designs/feature-<N>.md`.
- Output: `ai/step_plans/step-<N>.md` with full scope, architecture, test strategy, and execution command for the implementation phase.
- Gate: All open questions must be answered before planning completion.

**Phase 3: Implementation + User Review**
- Input: Step plan (`ai/step_plans/step-<N>.md`), design (`ai/designs/feature-<N>.md`), source code, test suite, `AGENTS.md`, `decisions.md`.
- Output: Implemented changes on a local topic branch (`step-<N>-implementation`), updated tests, docs, and planning artifacts (`blocker_log.md`, `open_questions.md`, `decisions.md`).
- Gate: All non-review bullets must be `[x]` before user review; all tests must pass.

**Phase 4: Post-Step Audit & Review (AI)**
- Input: Implemented changes from Phase 3 (git changes), user feedback, step plan, design.
- Output: `ai/step_review_results/review_result-<N>.md`, updated `implementation_plan.md`, commit on review branch (`step-<N>-review`). No push or merge to `main`/`master`.
- Gate: Every finding must have an explicit disposition; all accepted work must be captured as follow-up steps or questions.

**Phase 5: Post-Review**
- Input: `ai/step_review_results/review_result-<N>.md`, updated plan artifacts, review branch state.
- Output: Post-review updates (for example metrics/history updates and follow-up step alignment), performed without AI model execution.
- Gate: Review dispositions are reflected in planning artifacts before next step starts.

### What's done + plans

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

V-0.0.2 (current)

1. whats added
- new design step
- phase scripts improved significantly

2. known problems/to-do's:
- only codex cli supported
- you need to manually ctrl-c from codex session in the end of each model-driven phase
- review step creates relatively small improvement/tech-debt steps (5-8 SP) which is not efficient from token management perspective
- should we distinct tech-debt from blockers - place blockers to certain steps and manage tech debt some other way?
- incorrect SP countion on post_review

3. main plans
- security proposals (see below)
- distinct tech debt from blockers and create alternative process for tech debt tasks
- change bash scripts to lightweight cli (wrapper above coding agent cli's), see yasdef-wrapper
- investigate "skills" usage
- test how good this framework for frontend/mobile development, not only enterprise backend

### security_improvement_proposals

Scope: command-execution safety (non-git concerns).

- Restrict runner command to trusted values only. Do not execute arbitrary binaries from config; use an allowlist-based runner mapping.
- For implementation execution, use only `ai/setup/models.md` as the trusted source of runner/model/args.
- Treat step-plan metadata as non-executable context only (for example prompt path/version), not as command authority.
- Add integrity checks for command-driving artifacts (at minimum `ai/setup/models.md`) using a trust-lock/checksum file and require explicit re-trust after changes.
- Run child model commands with a minimal environment allowlist by default: `PATH`, `HOME`, `LANG`, `TMPDIR`.
- Add explicit opt-in for extra environment variables (for example `--pass-env KEY1,KEY2`) instead of inheriting full environment.

### Helpers
- Here is the prompt to create requirements_ears.md from usual technical requirements (you should run it from root after ai/ folder was added)
`carefully examine technical_requirements.md and create reqirements_ears.md in root folder, follow ai/templates/reqirements_ears_TEMPLATE.md and ai/golden_examples/reqirements_ears_GOLDEN_EXAMPLE.md`
--Here is the prompt to create implementation_plan from reqirements_ears.md and technical_requirements.md including the partially developed projects (you should run it from root after ai/ folder was added): 
`carefully examine all project files especially AGENTS.md and README.md if they are presented, then from reqirements_ears.md (use is mandatory) and technical_requirements.md (optionally, if they are presented), create in ai/ folder implementation_plan.md based on ai/templates/implementation_plan_TEMPLATE.md and ai/golden_examples/implementation_plan_GOLDEN_EXAMPLE.md; in this implementation plan you should add already implemented steps as well and not implemented, not implemented steps should be sliced based on functional, try to make it equal in terms of implementation efforts (10-20 SP means 1-3 day of work for human dev )`

### License

This project is licensed under the MIT License. See `LICENSE`.
