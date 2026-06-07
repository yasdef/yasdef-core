# Phase | Command | Model | Extra Arg 1 (optional) | Extra Arg 2 (optional) | ...
# Example: implementation | codex | gpt-5.2-codex | --config | model_reasoning_effort='high'
#
# Command column accepts:
#   codex  - invoked as: codex -m <model> <extras...> "<prompt>"
#   claude - invoked as: claude --model <model> <extras...> "<prompt>"
#            Both runners get an interactive TTY via run_with_output_log's
#            `script -q` wrapper, so claude opens its UI for tool approvals.
#            Extras pass through verbatim — operator may add e.g. `--allowed-tools`
#            to skip approval prompts for specific tools.
#            Example: ai_audit | claude | claude-opus-4-7 | |
#   echo   - test/local harness runner, invoked as: echo -m <model> <extras...> "<prompt>"
#
# Any other Command value is rejected by the Python orchestrator.

# design | claude | claude-sonnet-4-6 | | 
# planning | claude | claude-opus-4-7 | | 
# implementation | claude | claude-sonnet-4-6 | | 
# user_review | claude | claude-sonnet-4-6 | | 
# ai_audit | claude | claude-opus-4-7 | | 

design | codex | gpt-5.4 | --config | model_reasoning_effort='high'
planning | codex | gpt-5.5 | --config | model_reasoning_effort='high'
implementation | codex | gpt-5.4 | --config | model_reasoning_effort='high'
user_review | codex | gpt-5.4 | --config | model_reasoning_effort='high'
ai_audit |  codex | gpt-5.4 | --config | model_reasoning_effort='high'


