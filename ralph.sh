#!/bin/bash
# Ralph - Long-running AI agent loop
# Usage: ./ralph.sh [--tool codex|amp|claude] [max_iterations]

set -euo pipefail

TOOL="codex"
MAX_ITERATIONS=10
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"
ITERATION_TIMEOUT_SECONDS="${ITERATION_TIMEOUT_SECONDS:-1800}"
ITERATION_MAX_RETRIES="${ITERATION_MAX_RETRIES:-2}"
CODEX_BIN="${CODEX_BIN:-codex}"
AMP_BIN="${AMP_BIN:-amp}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_DISABLE_MCP_SERVERS="${CODEX_DISABLE_MCP_SERVERS:-}"

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
RUN_LOG_DIR="$SCRIPT_DIR/run-logs"

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

mkdir -p "$RUN_LOG_DIR"

remaining_story_count() {
  jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE"
}

total_story_count() {
  jq '.userStories | length' "$PRD_FILE"
}

completed_story_count() {
  local total remaining
  total="$(total_story_count)"
  remaining="$(remaining_story_count)"
  echo $((total - remaining))
}

next_story_info() {
  jq -r '
    .userStories[]
    | select(.passes != true)
    | [.id, .title]
    | @tsv
  ' "$PRD_FILE" | head -n 1
}

build_context_prefix() {
  cat <<EOF
Ralph runner context:
- Project root: $PROJECT_ROOT
- Prompt file: $PROMPT_FILE
- PRD file: $PRD_FILE
- Progress file: $PROGRESS_FILE
- Tool: codex

EOF
}

run_command_with_timeout() {
  local stdin_file="$1"
  shift

  local output_file timed_out_file exit_code_file
  output_file="$(mktemp)"
  timed_out_file="$(mktemp)"
  exit_code_file="$(mktemp)"

  python3 - "$ITERATION_TIMEOUT_SECONDS" "$stdin_file" "$output_file" "$timed_out_file" "$exit_code_file" "$@" <<'PY'
import os
import signal
import subprocess
import sys
from pathlib import Path

timeout_seconds = float(sys.argv[1])
stdin_file = sys.argv[2]
output_file = Path(sys.argv[3])
timed_out_file = Path(sys.argv[4])
exit_code_file = Path(sys.argv[5])
command = sys.argv[6:]

stdin_handle = None
try:
    if stdin_file:
        stdin_handle = open(stdin_file, "rb")

    process = subprocess.Popen(
        command,
        stdin=stdin_handle,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )

    timed_out = False
    try:
        output, _ = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        output = exc.stdout or ""
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()

    exit_code = 124 if timed_out else process.returncode
    output_file.write_text(output or "")
    timed_out_file.write_text("1\n" if timed_out else "0\n")
    exit_code_file.write_text(f"{exit_code}\n")
finally:
    if stdin_handle is not None:
        stdin_handle.close()
PY

  ITERATION_OUTPUT="$(cat "$output_file")"
  ITERATION_TIMED_OUT="$(tr -d '\n' < "$timed_out_file")"
  ITERATION_EXIT_CODE="$(tr -d '\n' < "$exit_code_file")"
  if [[ -n "$ITERATION_OUTPUT" ]]; then
    printf '%s\n' "$ITERATION_OUTPUT" >&2
  fi

  rm -f "$output_file" "$timed_out_file" "$exit_code_file"
}

run_codex_iteration() {
  local prompt_text
  prompt_text="$(build_context_prefix)$(cat "$PROMPT_FILE")"

  local -a cmd=("$TOOL_BIN" exec "-C" "$PROJECT_ROOT" "--dangerously-bypass-approvals-and-sandbox")
  if [[ -n "$CODEX_MODEL" ]]; then
    cmd+=("-m" "$CODEX_MODEL")
  fi
  if [[ -n "$CODEX_DISABLE_MCP_SERVERS" ]]; then
    local server
    local old_ifs="$IFS"
    IFS=','
    for server in $CODEX_DISABLE_MCP_SERVERS; do
      server="$(echo "$server" | xargs)"
      if [[ -n "$server" ]]; then
        cmd+=("-c" "mcp_servers.${server}.enabled=false")
      fi
    done
    IFS="$old_ifs"
  fi
  cmd+=("$prompt_text")

  run_command_with_timeout "" "${cmd[@]}"
}

run_amp_iteration() {
  local prompt_file
  prompt_file="$(mktemp)"
  printf '%s\n' "$(cat "$PROMPT_FILE")" > "$prompt_file"
  run_command_with_timeout "$prompt_file" "$TOOL_BIN" --dangerously-allow-all
  rm -f "$prompt_file"
}

run_claude_iteration() {
  run_command_with_timeout "$PROMPT_FILE" "$TOOL_BIN" --dangerously-skip-permissions --print
}

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS - Project root: $PROJECT_ROOT"
echo "Iteration timeout: ${ITERATION_TIMEOUT_SECONDS}s - Max retries per story: $ITERATION_MAX_RETRIES"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  REMAINING_BEFORE_RUN="$(remaining_story_count)"
  COMPLETED_BEFORE_RUN="$(completed_story_count)"
  TOTAL_STORIES="$(total_story_count)"
  NEXT_STORY="$(next_story_info)"
  if [[ -n "$NEXT_STORY" ]]; then
    CURRENT_STORY_ID="${NEXT_STORY%%$'\t'*}"
    CURRENT_STORY_TITLE="${NEXT_STORY#*$'\t'}"
  else
    CURRENT_STORY_ID=""
    CURRENT_STORY_TITLE=""
  fi

  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="
  ITERATION_LOG_FILE="$RUN_LOG_DIR/iteration-$(printf '%03d' "$i").log"
  : > "$ITERATION_LOG_FILE"

  echo "Current story: ${CURRENT_STORY_ID:-none} ${CURRENT_STORY_TITLE}"
  echo "Remaining stories before run: $REMAINING_BEFORE_RUN"
  echo "Completed stories before run: $COMPLETED_BEFORE_RUN / $TOTAL_STORIES"

  ATTEMPT=1
  while true; do
    echo "Attempt $ATTEMPT of $((ITERATION_MAX_RETRIES + 1)) for ${CURRENT_STORY_ID:-no-story}"

    case "$TOOL" in
      codex)
        run_codex_iteration
        ;;
      amp)
        run_amp_iteration
        ;;
      claude)
        run_claude_iteration
        ;;
    esac

    {
      echo "### Attempt $ATTEMPT"
      echo "Timed out: $ITERATION_TIMED_OUT"
      echo "Exit code: $ITERATION_EXIT_CODE"
      printf '%s\n' "$ITERATION_OUTPUT"
    } >> "$ITERATION_LOG_FILE"

    if [[ "$ITERATION_TIMED_OUT" == "1" ]]; then
      echo "Iteration $i timed out after ${ITERATION_TIMEOUT_SECONDS}s."
      if (( ATTEMPT <= ITERATION_MAX_RETRIES )); then
        echo "Retrying story ${CURRENT_STORY_ID:-unknown} (${ATTEMPT}/${ITERATION_MAX_RETRIES})."
        ATTEMPT=$((ATTEMPT + 1))
        continue
      fi

      echo "Story ${CURRENT_STORY_ID:-unknown} exceeded the retry limit after timeout."
      exit 1
    fi

    OUTPUT="$ITERATION_OUTPUT"
    break
  done

  REMAINING_STORIES="$(remaining_story_count)"
  COMPLETED_STORIES="$(completed_story_count)"
  SAID_COMPLETE="0"
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    SAID_COMPLETE="1"
  fi

  if [[ "$REMAINING_STORIES" == "0" ]]; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  if [[ "$SAID_COMPLETE" == "1" ]]; then
    echo ""
    echo "Warning: tool reported COMPLETE at iteration $i, but $REMAINING_STORIES story/stories still have passes=false."
    echo "Continuing because PRD state is the source of truth."
  fi

  NEXT_STORY_AFTER_RUN="$(next_story_info)"
  if [[ -n "$NEXT_STORY_AFTER_RUN" ]]; then
    NEXT_STORY_ID="${NEXT_STORY_AFTER_RUN%%$'\t'*}"
    NEXT_STORY_TITLE="${NEXT_STORY_AFTER_RUN#*$'\t'}"
    echo "Next story: $NEXT_STORY_ID $NEXT_STORY_TITLE"
  fi

  echo "Iteration $i complete. Completed stories: $COMPLETED_STORIES / $TOTAL_STORIES. Remaining stories: $REMAINING_STORIES. Continuing..."
  sleep "$SLEEP_SECONDS"
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
