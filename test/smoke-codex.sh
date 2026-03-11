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
cp "$ROOT/prd.json.example" "$RALPH_DIR/prd.json"

cat > "$BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${FAKE_CODEX_LOG:?}"
printf '%s\n' "fake codex run"
printf '%s\n' "<promise>COMPLETE</promise>"
EOF
chmod +x "$BIN_DIR/codex"

git init -b main "$PROJECT_DIR" >/dev/null
PHYSICAL_PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

(
  cd "$PROJECT_DIR"
  PATH="$BIN_DIR:$PATH" \
  FAKE_CODEX_LOG="$LOG_FILE" \
  ./scripts/ralph/ralph.sh 1 >"$TMP_DIR/out.txt" 2>&1
)

grep -q "Ralph completed all tasks!" "$TMP_DIR/out.txt"
grep -q -- "--dangerously-bypass-approvals-and-sandbox" "$LOG_FILE"
grep -q "Ralph runner context:" "$LOG_FILE"
grep -q "Read the PRD at the path given in the injected \`Ralph runner context\` block." "$LOG_FILE"
grep -q -- "-C $PHYSICAL_PROJECT_DIR" "$LOG_FILE"
grep -q -- "- PRD file: $PHYSICAL_PROJECT_DIR/scripts/ralph/prd.json" "$LOG_FILE"

echo "smoke-codex: ok"
