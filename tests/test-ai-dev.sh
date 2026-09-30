#!/bin/bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.config/ai-workspace"
mkdir -p "$tmp/home/projects/buga" "$tmp/home/projects/osagenda"
cat > "$tmp/home/.config/ai-workspace/defaults.conf" <<'EOF'
DEFAULT_AGENTS="gemini"
DEFAULT_CLIPBOARD=false
DEFAULT_BROWSER=false
EOF
cat > "$tmp/bin/herdr" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HERDR_TEST_LOG"
shift 2
case "$*" in
    'workspace list') test -f "$HERDR_TEST_STATE" || exit 1; if test -f "$HERDR_TEST_WORKSPACE"; then echo '{"result":{"workspaces":[{"workspace_id":"w1"}]}}'; else echo '{"result":{"workspaces":[]}}'; fi ;;
    'server') ps -o sid= -p "$$" | tr -d ' ' > "$HERDR_TEST_SERVER_SID"; touch "$HERDR_TEST_STATE" ;;
    'workspace create '* ) touch "$HERDR_TEST_WORKSPACE"; echo '{"result":{"workspace":{"workspace_id":"w1"},"tab":{"tab_id":"w1:t1"},"root_pane":{"pane_id":"w1:p1"}}}' ;;
    'tab create '* ) echo '{"result":{"root_pane":{"pane_id":"w1:p2"}}}' ;;
esac
EOF
chmod +x "$tmp/bin/herdr"
mkdir -p "$tmp/home/bin"
cat > "$tmp/home/bin/ai-browser" <<'EOF'
#!/bin/bash
echo browser >> "$HERDR_TEST_LOG"
EOF
chmod +x "$tmp/home/bin/ai-browser"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH"
export HERDR_TEST_LOG="$tmp/herdr.log" HERDR_TEST_STATE="$tmp/herdr.state" HERDR_TEST_WORKSPACE="$tmp/workspace.state"
export HERDR_TEST_SERVER_SID="$tmp/server.sid"

bash "$(dirname "$0")/../scripts/ai-dev" test --claude >/dev/null
test "$(cat "$HERDR_TEST_SERVER_SID")" != "$(ps -o sid= -p "$$" | tr -d ' ')"
bash "$(dirname "$0")/../scripts/ai-dev" test --claude >/dev/null
bash "$(dirname "$0")/../scripts/ai-dev" test --claude --browser >/dev/null
grep -q '^browser$' "$HERDR_TEST_LOG"
printf '2\n' | bash "$(dirname "$0")/../scripts/ai-dev" >/dev/null 2>&1
before=$(wc -l < "$HERDR_TEST_LOG")
same=$(HERDR_ENV=1 HERDR_SESSION=osagenda bash "$(dirname "$0")/../scripts/ai-dev" osagenda)
other=$(HERDR_ENV=1 HERDR_SESSION=main bash "$(dirname "$0")/../scripts/ai-dev" osagenda)
[[ "$same" == *'p osagenda'* ]]
[[ "$other" == *'Ctrl+B'*'ai-dev osagenda'* ]]
test "$(wc -l < "$HERDR_TEST_LOG")" = "$before"

test "$(grep -c 'workspace create' "$HERDR_TEST_LOG")" = 1
grep -q 'pane run w1:p1 claude$' "$HERDR_TEST_LOG"
! grep -q 'pane run .*gemini' "$HERDR_TEST_LOG"
grep -q 'tab create --workspace w1 .* --label shell' "$HERDR_TEST_LOG"
grep -q '^--session osagenda workspace list$' "$HERDR_TEST_LOG"
echo 'ai-dev: detached server, create, reconnect, menu and nested Herdr guard OK'
