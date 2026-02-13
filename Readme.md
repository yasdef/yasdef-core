## Yet Another Spec Driven (Enhanced) Framework - YASDEF

### Word from first commit

There’s nothing wrong with vibecoding. Building prototypes with AI — is a new superpower and it’s unlocked a huge wave of experimentation and helps people start something new that really matters. 
But sometimes what you need - is not prototype. Some of us work in complex codebases — often in enterprise environments where predictability, maturity, and long-term maintainability matter more than raw velocity. This is sometimes true for startups as well.
This framework is built to help when vibecoding is not the best option. It uses AI to support developer productivity, but never at the expense of code quality. 

This approach can be expressed in a few sentences:
* Governance over “fire-and-forget” prompting. 
* Reproducibility over speed. 
* Human control over agent swarms.
* Spec-driven science over vibe-magic.

### Quick start

1. copy-past ai/ folder to the root of your project
2. all bash scripts in ai/scripts should be runnable `chmod +x ai/scripts/ai_implementation.sh ai/scripts/ai_plan.sh ai/scripts/ai_review.sh ai/scripts/orchestrator.sh ai/scripts/post_review.sh`
3. You need to provide `implementation_plan.md` in certain format, it should be in root of your project
4. If you run Worker standalone without Coordinator and dont have implementation_plan.md ask your model to generate it based on any plan or requirements you have. Here is simplest prompt: "examine this project carefully, based ot whats alreay done ant this requirements -- START REQUIREMENTS <past your requirements as plain text or path to file here> -- END OF REQUIREMENTS, generate implementation_plan.md and add it to the root folder of my project. Strictly follow ai/templates/implementation_plan_TEMPLATE.md and use ai/golden_examples/implementation_plan_GOLDEN_EXAMPLE.md as an example"
5. add AGENTS.md in root folder, if you dont know what should be in AGENTS.md ask your model to generate it: "generate AGENTS.MD based on my project specific and best proactices, try to make it concise and well-structured". If you already have AGENTS.md make sure it is not included generai ai-dev process rules so this rules will not contradict with YASDEF own set of rules.
6. OPTIONAL - allow your ai cli to work with git (except merge to master) to avoid asking permissions all the time
7. OPTIONAL - allow your ai cli to write in files in /ai folder  to avoid asking permissions all the time
6. run ai/scripts/orchestrator.sh (it's just bash script) and follow the instructions

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

### Phases inputs and outputs

### AI-dev-process gates and artifacts

### AI-dev process main rules 
- we always move from top AI_DEVELOPMENT_PROCESS.md to bottom AGENTS.md, AI_DEVELOPMENT_PROCESS.md newer hold project specific details, AGENTS.md dont know nothing about ai-dev process

### Underwater obstacles

- What if, during the implementation of step 2, we discover functionality we never considered? In that case the Worker requests the Coordinator to add a task. If the Coordinator decides the task belongs to the same branch (stack), it informs the requesting Worker and the Worker creates a new step in the implementation plan. If the new task changes the graph and affects other tasks, the Coordinator recalculates the graph and asks all Workers to update their implementation plans.





