#!/bin/bash
# Ralph - Long-running AI agent loop
# Usage: ./ralph.sh [--tool codex|amp|claude] [max_iterations]

set -euo pipefail

TOOL="codex"
MAX_ITERATIONS=10
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"
CODEX_BIN="${CODEX_BIN:-codex}"
AMP_BIN="${AMP_BIN:-amp}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CODEX_MODEL="${CODEX_MODEL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

if [[ "$TOOL" != "codex" && "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'codex', 'amp', or 'claude'." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

case "$TOOL" in
  codex)
    TOOL_BIN="$CODEX_BIN"
    PROMPT_FILE="$SCRIPT_DIR/CODEX.md"
    ;;
  amp)
    TOOL_BIN="$AMP_BIN"
    PROMPT_FILE="$SCRIPT_DIR/prompt.md"
    ;;
  claude)
    TOOL_BIN="$CLAUDE_BIN"
    PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
    ;;
esac

if ! command -v "$TOOL_BIN" >/dev/null 2>&1; then
  echo "Error: Required binary not found for tool '$TOOL': $TOOL_BIN" >&2
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: Prompt file missing for tool '$TOOL': $PROMPT_FILE" >&2
  exit 1
fi

if [[ ! -f "$PRD_FILE" ]]; then
  echo "Error: Missing PRD file: $PRD_FILE" >&2
  exit 1
fi

# Archive previous run if branch changed
if [[ -f "$LAST_BRANCH_FILE" ]]; then
  CURRENT_BRANCH="$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")"
  LAST_BRANCH="$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")"

  if [[ -n "$CURRENT_BRANCH" && -n "$LAST_BRANCH" && "$CURRENT_BRANCH" != "$LAST_BRANCH" ]]; then
    DATE="$(date +%Y-%m-%d)"
    FOLDER_NAME="$(echo "$LAST_BRANCH" | sed 's|^ralph/||')"
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [[ -f "$PRD_FILE" ]] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [[ -f "$PROGRESS_FILE" ]] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

CURRENT_BRANCH="$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")"
if [[ -n "$CURRENT_BRANCH" ]]; then
  echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

run_codex_iteration() {
  local prompt_text
  prompt_text="$(cat "$PROMPT_FILE")"
  local context_prefix
  context_prefix=$(
    cat <<EOF
Ralph runner context:
- Project root: $PROJECT_ROOT
- Prompt file: $PROMPT_FILE
- PRD file: $PRD_FILE
- Progress file: $PROGRESS_FILE
- Tool: codex

EOF
  )
  prompt_text="${context_prefix}${prompt_text}"

  local -a cmd=("$TOOL_BIN" exec "-C" "$PROJECT_ROOT" "--dangerously-bypass-approvals-and-sandbox")
  if [[ -n "$CODEX_MODEL" ]]; then
    cmd+=("-m" "$CODEX_MODEL")
  fi
  cmd+=("$prompt_text")

  set +e
  local output
  output="$("${cmd[@]}" 2>&1 | tee /dev/stderr)"
  set -e
  printf '%s' "$output"
}

run_amp_iteration() {
  local prompt_text
  prompt_text="$(cat "$PROMPT_FILE")"

  set +e
  local output
  output="$(printf '%s\n' "$prompt_text" | "$TOOL_BIN" --dangerously-allow-all 2>&1 | tee /dev/stderr)"
  set -e
  printf '%s' "$output"
}

run_claude_iteration() {
  set +e
  local output
  output="$("$TOOL_BIN" --dangerously-skip-permissions --print < "$PROMPT_FILE" 2>&1 | tee /dev/stderr)"
  set -e
  printf '%s' "$output"
}

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS - Project root: $PROJECT_ROOT"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  case "$TOOL" in
    codex)
      OUTPUT="$(run_codex_iteration)"
      ;;
    amp)
      OUTPUT="$(run_amp_iteration)"
      ;;
    claude)
      OUTPUT="$(run_claude_iteration)"
      ;;
  esac

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep "$SLEEP_SECONDS"
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
