## Yet Another Spec Driven (Enhanced) Framework - YASDEF

### Word from first commit

There’s nothing wrong with vibecoding. Building prototypes with AI — is a new superpower and it’s unlocked a huge wave of experimentation and helps people start something new that really matters. 
But sometimes what you need - is not prototype. Some of us work in complex codebases — often in enterprise environments where predictability, maturity, and long-term maintainability matter more than raw velocity. This is sometimes true for startups as well.
This framework is built to help when vibecoding is not the best option. It uses AI to support developer productivity, but never at the expense of code quality. It is also designed to reduce token consumption so one can work comfortably with an entry-level subscription, regardless of how complex one’s codebase is and how many tasks should be implemented.

This approach can be expressed in a few sentences:
* Governance over “fire-and-forget” prompting. 
* Reproducibility over speed. 
* Human control over agent swarms.
* Spec-driven science over vibe-magic.

### Quick start

0. Read this carefully:
⚠️ This is pre-alpha — things may break. Use at your own risk. Take precautions before integrating this repo into your project! 
⚠️ Your AGENTS.md will be used as part of promt to ai-model and ai-model in most cases will examine your project code - make sure you're ok with this.
✅ You need codex cli https://chatgpt.com/codex available to run this framework, or you can change model in ai/setup/models.md

1. copy-past ai/ folder to the root of your project

2. all bash scripts in ai/scripts should be runnable `chmod +x ai/scripts/ai_implementation.sh ai/scripts/ai_plan.sh ai/scripts/ai_review.sh ai/scripts/orchestrator.sh ai/scripts/post_review.sh`

3. You need to provide `implementation_plan.md` in certain format, it should be in root of your project

4. If you run Worker standalone without Coordinator and dont have implementation_plan.md ask your model to generate it based on any plan or requirements you have. Here is simplest prompt: "examine this project carefully, based ot whats alreay done ant this requirements -- START REQUIREMENTS <past your requirements as plain text or path to file here> -- END OF REQUIREMENTS, generate implementation_plan.md and add it to the root folder of my project. Strictly follow ai/templates/implementation_plan_TEMPLATE.md and use ai/golden_examples/implementation_plan_GOLDEN_EXAMPLE.md as an example"

5. add AGENTS.md in root folder, if you dont know what should be in AGENTS.md ask your model to generate it: "generate AGENTS.MD based on my project specific and best proactices, try to make it concise and well-structured". If you already have AGENTS.md make sure it is not included generai ai-dev process rules so this rules will not contradict with YASDEF own set of rules.

6. run `bash ai/scripts/orchestrator.sh` and follow the instructions

7. OPTIONAL - allow your ai cli to work with git (except merge to master) to avoid asking permissions all the time


### Why we need another one

- I don't like choosing between an agile (fluid) and a strict approach when writing code with AI. I want both. I prefer to be agile at the product level because requirements can appear, change, or disappear unexpectedly. But when AI writes code for me, I want the process to be extremely strict and straightforward to get predictable, reproducible, and deterministic results (as far as that's possible with AI).
- I don't like the idea that a developer works 5 minutes and spends the other 55 minutes doing something else—like playing videogames or doing yoga. I prefer an approach where we work as long as needed but deliver 10× more value per hour. Code quality, maintainability, and readability are not negotiable trade-offs. We should be able to drop all AI tools and continue the project by hand without problems at any time.
- I don't like to use dozens of different subagents just to map our AI-dev process to an organization chart. I prefer to avoid unnecessary complexity.
- I agree that we can outsource many tasks to AI, but not thinking and decision making.

### How this will work

- **Coordinator:** The Coordinator manages the whole project based on technical requirements, architecture, and core technical decisions. All tasks and subtasks form a cyclic graph. One branch of the graph is a sequence (a stack) of tasks. A stack becomes the source of an implementation plan. Each implementation plan contains a sequence of tasks that can be done one by one. The Coordinator should act agilely, manage the development process and task allocation based on feedback, and constantly optimize and recalculate the graph. The Coordinator never adds new tasks on its own; it only structures them in the graph. Requests to add tasks come from Workers (bottom-up) or from a human operator (top-down) as specific decisions. Coordinator responsible for token management and optimisation, for this it performs task-slicing based on model and reasoning.  

- **Worker:** Workers are the actual code implementers. They take the implementation plan as input and split it into reasonable steps. Each step is implemented following a strict AI-dev process. The main goal is to guarantee high code quality while reducing manual coding burden for the operator. This shifts the human operator's role from coding to making complex technical decisions and ensuring architectural quality.

- **AI-dev process:** The AI-dev process is a set of rules for Workers and a strict sequence of gates that involve the human operator in some loops. The process has three main phases: planning, implementation, and review. We do not share ai-context between these phases. Each phase can run in a separate AI-agent session. We run phase-scripts to create a stable, comprehensive prompt from the process artifacts and pass it to the chosen model.

- **Phase-script behavior:** A phase-script must be executed by a model; that same model consumes the script's result as a prompt. Specifically, we run a coding agent with parameters like model, reasoning effort, and a request to run a script. Example:
	`codex -m gpt-5.2-codex --config model_reasoning_effort='"high"' "run ai/step_plans/step-1.5.md"`.
A phase-script can produce a specific artifact (like an implementation plan for step N) and must output a dynamically created command for the next step. To create that command we use a config that specifies agent, mode, reasoning, and the key command for each phase.

- **Orchestration:** Since each phase starts as a terminal command, we can orchestrate the whole process from elsewhere.

### Main process artifacts and responsibilities

Each artifact below serves a specific role in the AI-dev process:

- **requirements_ears.md**: Source of truth for behavioral requirements and acceptance criteria (EARS format).
- **implementation_plan.md**: Ordered execution plan at the step level; tracks all tasks and subtasks with story point estimates. Work happens bullet-by-bullet. Updated dynamically as the Coordinator refactors the graph.
- **step_plans/**: Per-step planning artifacts (`step-<N>.md`) produced during the "Plan and discuss the step" bullet. Serve as the detailed execution contract for Workers. Include scope, preconditions, architecture, risks, and test strategy.
- **blocker_log.md**: Unknowns and blocking issues discovered during implementation, organized by step. Includes impact, required decision, and resolution status. Only for in-progress steps.
- **open_questions.md**: Non-blocking questions tracked per step, reviewed at step planning start. Removed once answered.
- **decisions.md**: Durable technical decisions (Architecture Decision Records) recorded during planning and implementation. Includes decision context, alternatives considered, and rationale. Used to avoid rehashing settled choices.
- **user_review.md**: Rule-based review insights, generalizable feedback patterns, and references to accepted implementations. Evolves as design patterns stabilize.
- **step_review_results/**: Post-step audit findings (`review_result-<N>.md`), organized by severity (Critical/High/Medium/Low). Each finding has an explicit disposition (Accepted/Rejected) and follow-up work assignment.
- **history.md**: Optional step completion log tracking dates, effort, surprises, and key decisions per step.

### Phases inputs and outputs

The AI-dev process runs in three phases per step:

**Phase 1: Planning**
- Input: Current `implementation_plan.md`, `requirements_ears.md`, `decisions.md`, `blocker_log.md`, `open_questions.md`.
- Output: `ai/step_plans/step-<N>.md` with full scope, architecture, test strategy, and execution command for the implementation phase.
- Gate: All open questions must be answered before planning completion.

**Phase 2: Implementation**
- Input: Step plan (`ai/step_plans/step-<N>.md`), source code, test suite, `AGENTS.md`, `decisions.md`.
- Output: Implemented changes on a local topic branch (`step-<N>-implementation`), updated tests, docs, and planning artifacts (`blocker_log.md`, `open_questions.md`, `decisions.md`).
- Gate: All non-review bullets must be `[x]` before user review; all tests must pass.

**Phase 3: Review & Audit**
- Input: Implemented changes from Phase 2, user feedback, step plan.
- Output: `ai/step_review_results/review_result-<N>.md`, updated `implementation_plan.md`, commit on review branch (`step-<N>-review`). No push or merge to `main`/`master`.
- Gate: Every finding must have an explicit disposition; all accepted work must be captured as follow-up steps or questions.

### AI-dev process main rules

- **Single source of truth for workflow rules**: Behavioral and process rules for AI execution live in `AI_DEVELOPMENT_PROCESS.md`. Scripts stay minimal and phase-scoped. All rules are defined once and referenced; they are never duplicated across phase scripts.
- **Clean separation of concerns**:
  - `AI_DEVELOPMENT_PROCESS.md` defines the generic workflow (phases, gates, artifacts, per-step loop). It is project-agnostic and never includes project-specific details.
  - `AGENTS.md` defines project-specific constraints: build commands, test runners, API specs, validation rules, branch strategy, tool paths, idempotency expectations. It never discusses the AI-dev process itself.
  - Both files are required; they are kept independent so that workflow improvements do not leak into project configuration, and vice versa.
- **Phase isolation**: Each phase (planning, implementation, review) is executed in a potentially separate AI-agent session with a distinct prompt. Context is never shared between phases (e.g., planning artifacts are frozen when implementation starts). This ensures each phase uses the most suitable model and reasoning effort.
- **Determinism over speed**: Every decision, blocker, and new finding is recorded in durable artifacts (`decisions.md`, `blocker_log.md`, `open_questions.md`, `step_review_results/`). This enables reproducibility and allows the project to continue without AI assistance at any point.
- **Human in the loop**: Complex technical decisions and architectural choices are not made by the Worker alone. Workers must explicitly ask the user for decisions before proceeding; user feedback during review is incorporated as generalizable rules in `user_review.md` to improve future iterations.

### Whats done + planes

V-0.0.1
1. whats added:
- main architecture and concept findings
- based functionality added in form of bash scripts
- orchestrator added so all steps run semi-automatically form 1 command
- each phase can be run manually separately
- orchestrator consumes implementation_plan.md and defile nex step to work automatically
2. known problems:
- only codex cli supported
- you need to manualy ctrl-c from codex session in the end of each phase (planing/implementation/review)
- review step creates relatively small improvement/tech-debt steps (5-8 SP) which is not efficient from token management perspective, should we distinct tech-debt from blockers - place blockers to certain steps and manage tech debt some other way?
3. main planes
- security proposals (see below)
- disticnct tech debt from blockers and create alternative process for tech debt tasks
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

### License

This project is licensed under the MIT License. See `LICENSE`.
