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
#
# Any other Command value falls back to the codex argv shape (test fixtures rely on this
# to substitute `echo` or a path to a fake model script).

design | codex | gpt-5.4 | --config | model_reasoning_effort='high'
planning | codex | gpt-5.5 | --config | model_reasoning_effort='high'
implementation | codex | gpt-5.4 | --config | model_reasoning_effort='high'
user_review | codex | gpt-5.4 | --config | model_reasoning_effort='high'
ai_audit | claude | claude-opus-4-7 | | 
