## ADDED Requirements

### Requirement: Worker init warns about missing AGENTS before branch switch
The worker init flow SHALL perform a non-blocking local `AGENTS.md` guidance check after resolving the registered worker class and before switching to branch `overmind`.

#### Scenario: Missing AGENTS warning runs before overmind checkout
- **WHEN** the worker init script validates the bound ASDLC project repo and resolves the worker class from `workers.yaml`
- **THEN** it evaluates whether the current worker repo root contains `AGENTS.md` before calling the `overmind` branch checkout or creation logic

#### Scenario: Existing AGENTS suppresses warning
- **WHEN** the current worker repo root contains `AGENTS.md`
- **THEN** the worker init script does not print a missing `AGENTS.md` warning

#### Scenario: Missing AGENTS does not block binding
- **WHEN** the current worker repo root does not contain `AGENTS.md`
- **THEN** the worker init script prints the applicable guidance warning and continues with branch switching and binding creation
