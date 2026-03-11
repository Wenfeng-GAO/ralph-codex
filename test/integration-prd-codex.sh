#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/ralph.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/project"
RALPH_DIR="$PROJECT_DIR/scripts/ralph"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/codex.log"
PHYSICAL_PROJECT_DIR=""

mkdir -p "$RALPH_DIR" "$BIN_DIR"

cp "$ROOT/ralph.sh" "$RALPH_DIR/ralph.sh"
cp "$ROOT/CODEX.md" "$RALPH_DIR/CODEX.md"

cat > "$RALPH_DIR/prd.json" <<'EOF'
{
  "project": "IntegrationTest",
  "branchName": "ralph/integration-test",
  "description": "Single-story integration test for Codex Ralph.",
  "userStories": [
    {
      "id": "US-001",
      "title": "Create hello file",
      "description": "As a maintainer, I want a hello file so the integration test can verify one complete Ralph iteration.",
      "acceptanceCriteria": [
        "Create hello.txt at the repo root",
        "Append a progress entry",
        "Commit passes"
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

echo "$*" >> "${FAKE_CODEX_LOG:?}"

project_root=""
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [[ "$arg" == "-C" ]]; then
    next_index=$((i + 1))
    project_root="${!next_index}"
    break
  fi
done

if [[ -z "$project_root" ]]; then
  echo "missing -C project root" >&2
  exit 1
fi

ralph_dir="$project_root/scripts/ralph"
prd_file="$ralph_dir/prd.json"
progress_file="$ralph_dir/progress.txt"

git -C "$project_root" checkout -B "ralph/integration-test" >/dev/null 2>&1
printf '%s\n' "hello from fake codex" > "$project_root/hello.txt"

node -e '
const fs = require("fs");
const path = process.argv[1];
const prd = JSON.parse(fs.readFileSync(path, "utf8"));
prd.userStories[0].passes = true;
fs.writeFileSync(path, `${JSON.stringify(prd, null, 2)}\n`);
' "$prd_file"

cat >> "$progress_file" <<'PROGRESS'
## 2026-03-12 12:00 - US-001
- Implemented hello.txt
- Files changed: hello.txt, scripts/ralph/prd.json, scripts/ralph/progress.txt
- Quality checks run: integration fake codex smoke test
- Commit created
- Learnings for future iterations:
  - The Ralph runner injects project, PRD, and progress file paths into the prompt.
---
PROGRESS

git -C "$project_root" add hello.txt scripts/ralph/prd.json scripts/ralph/progress.txt
git -C "$project_root" -c user.name="Ralph Test" -c user.email="ralph-test@example.com" commit -m "feat: US-001 - Create hello file" >/dev/null

printf '%s\n' "fake codex completed a story"
printf '%s\n' "<promise>COMPLETE</promise>"
EOF
chmod +x "$BIN_DIR/codex"

git init -b main "$PROJECT_DIR" >/dev/null
PHYSICAL_PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
git -C "$PROJECT_DIR" -c user.name="Ralph Test" -c user.email="ralph-test@example.com" commit --allow-empty -m "chore: initial" >/dev/null

(
  cd "$PROJECT_DIR"
  PATH="$BIN_DIR:$PATH" \
  FAKE_CODEX_LOG="$LOG_FILE" \
  ./scripts/ralph/ralph.sh 1 >"$TMP_DIR/out.txt" 2>&1
)

grep -q "Ralph completed all tasks!" "$TMP_DIR/out.txt"
grep -q -- "--dangerously-bypass-approvals-and-sandbox" "$LOG_FILE"
grep -q "Ralph runner context:" "$LOG_FILE"
grep -q -- "- Project root: $PHYSICAL_PROJECT_DIR" "$LOG_FILE"
grep -q -- "- PRD file: $PHYSICAL_PROJECT_DIR/scripts/ralph/prd.json" "$LOG_FILE"

test -f "$PROJECT_DIR/hello.txt"
grep -q "hello from fake codex" "$PROJECT_DIR/hello.txt"
grep -q '"passes": true' "$RALPH_DIR/prd.json"
grep -q "US-001" "$RALPH_DIR/progress.txt"
grep -q "feat: US-001 - Create hello file" <(git -C "$PROJECT_DIR" log --oneline -1)
test "$(git -C "$PROJECT_DIR" branch --show-current)" = "ralph/integration-test"

echo "integration-prd-codex: ok"
