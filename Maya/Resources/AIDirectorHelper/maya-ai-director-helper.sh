#!/bin/zsh
set -euo pipefail

RUN_DIR="$1"
CODEX_BIN="${2:-codex}"

PROMPT_FILE="$RUN_DIR/prompt.txt"
SCHEMA_FILE="$RUN_DIR/output-schema.json"
PLAN_FILE="$RUN_DIR/generated-plan.json"
FRAME_ARGS_FILE="$RUN_DIR/frame-args.txt"

args=(exec --skip-git-repo-check --output-schema "$SCHEMA_FILE" --output-last-message "$PLAN_FILE")

if [[ -f "$FRAME_ARGS_FILE" ]]; then
  while IFS= read -r frame; do
    [[ -n "$frame" ]] && args+=(--image "$frame")
  done < "$FRAME_ARGS_FILE"
fi

"$CODEX_BIN" "${args[@]}" - < "$PROMPT_FILE"
