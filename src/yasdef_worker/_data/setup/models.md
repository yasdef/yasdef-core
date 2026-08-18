# Phase | Command | Model | Extra Arg 1 (optional) | Extra Arg 2 (optional) | ...
# Example: implementation | codex | gpt-5.2-codex | --config | model_reasoning_effort='high'
#
# Command column accepts:
#   copilot - invoked as: copilot --model <model> <extras...> -i "<prompt>"
#             `-i` starts GitHub Copilot CLI's interactive UI and automatically
#             executes the phase prompt, so extras always come before `-i` and the
#             prompt is the final argument. Copilot must be installed and
#             authenticated by the operator; yasdef does not manage either.
#             Example: implementation | copilot | claude-haiku-4.5 | --effort | high
#   codex   - invoked as: codex -m <model> <extras...> "<prompt>"
#   claude  - invoked as: claude --model <model> <extras...> "<prompt>"
#             All three runners get an interactive TTY via run_with_output_log's
#             `script -q` wrapper, so each opens its UI for tool approvals.
#             Extras pass through verbatim — operator may add e.g. `--allowed-tools`
#             to skip approval prompts for specific tools.
#             Example: ai_audit | claude | claude-opus-4-7 | |
#   echo    - test/local harness runner, invoked as: echo -m <model> <extras...> "<prompt>"
#
# Any other Command value is rejected by yasdef.

# design | copilot | claude-haiku-4.5
# planning | copilot | claude-haiku-4.5
# implementation | copilot | claude-haiku-4.5
# user_review | copilot | claude-haiku-4.5
# ai_audit | copilot | claude-haiku-4.5

# design | claude | claude-sonnet-4-6 | | 
# planning | claude | claude-opus-4-7 | | 
# implementation | claude | claude-sonnet-4-6 | | 
# user_review | claude | claude-sonnet-4-6 | | 
# ai_audit | claude | claude-opus-4-7 | | 

# design | codex | gpt-5.4 | --config | model_reasoning_effort='high'
# planning | codex | gpt-5.5 | --config | model_reasoning_effort='high'
# implementation | codex | gpt-5.4 | --config | model_reasoning_effort='high'
# user_review | codex | gpt-5.4 | --config | model_reasoning_effort='high'
# ai_audit | codex | gpt-5.4 | --config | model_reasoning_effort='high'

design | copilot | claude-haiku-4.5
planning | claude | claude-opus-4-8 | |
implementation | codex | gpt-5.5 | --config | model_reasoning_effort='high'
user_review | codex | gpt-5.5 | --config | model_reasoning_effort='high'
ai_audit | claude | claude-opus-4-8 | |
