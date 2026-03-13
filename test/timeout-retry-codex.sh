#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/ralph.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/project"
RALPH_DIR="$PROJECT_DIR/scripts/ralph"
BIN_DIR="$TMP_DIR/bin"
ATTEMPT_FILE="$TMP_DIR/attempt.txt"

mkdir -p "$RALPH_DIR" "$BIN_DIR"

cp "$ROOT/ralph.sh" "$RALPH_DIR/ralph.sh"
cp "$ROOT/CODEX.md" "$RALPH_DIR/CODEX.md"

cat > "$RALPH_DIR/prd.json" <<'EOF'
{
  "project": "TimeoutRetryTest",
  "branchName": "ralph/timeout-retry-test",
  "description": "Verify Ralph retries a timed-out Codex iteration.",
  "userStories": [
    {
      "id": "US-001",
      "title": "Finish after retry",
      "description": "As a maintainer, I want timed-out iterations retried automatically.",
      "acceptanceCriteria": [
        "Retry the same story after timeout",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
EOF

cat > "$BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

attempt="$(cat "$FAKE_ATTEMPT_FILE" 2>/dev/null || echo 0)"
attempt=$((attempt + 1))
printf '%s' "$attempt" > "$FAKE_ATTEMPT_FILE"

if [[ "$attempt" -eq 1 ]]; then
  sleep 2
  exit 0
fi

python3 - "$FAKE_PRD_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["userStories"][0]["passes"] = True
path.write_text(json.dumps(data, indent=2) + "\n")
PY

printf '%s\n' "fake codex completed after retry"
printf '%s\n' "<promise>COMPLETE</promise>"
EOF
chmod +x "$BIN_DIR/codex"

git init -b main "$PROJECT_DIR" >/dev/null

(
  cd "$PROJECT_DIR"
  PATH="$BIN_DIR:$PATH" \
  FAKE_ATTEMPT_FILE="$ATTEMPT_FILE" \
  FAKE_PRD_FILE="$RALPH_DIR/prd.json" \
  ITERATION_TIMEOUT_SECONDS=1 \
  ITERATION_MAX_RETRIES=2 \
  ./scripts/ralph/ralph.sh 1 >"$TMP_DIR/out.txt" 2>&1
)

test "$(cat "$ATTEMPT_FILE")" = "2"
grep -q "Current story: US-001 Finish after retry" "$TMP_DIR/out.txt"
grep -q "timed out" "$TMP_DIR/out.txt"
grep -q "Retrying story US-001" "$TMP_DIR/out.txt"
grep -q "Ralph completed all tasks!" "$TMP_DIR/out.txt"
grep -q '"passes": true' "$RALPH_DIR/prd.json"

echo "timeout-retry-codex: ok"
