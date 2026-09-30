#!/bin/bash
set -euo pipefail
source <(sed -n '/^ai-update() {$/,/^}$/p' "$(dirname "$0")/../setup-host-aliases.sh")
workspace_test_dir=$(mktemp -d)
trap 'rm -rf "$workspace_test_dir"' EXIT
_ai_container() { :; }
docker() {
    printf '%s\n' "$*" >> "$workspace_test_dir/calls"
    case "$1 $2" in
        'service inspect') echo aiworkspace-herdr:migration-20260930 ;;
        'image inspect') return "${workspace_missing_image:-0}" ;;
        'run --rm') return "${workspace_invalid_image:-0}" ;;
        'service update') return "${workspace_update_failed:-0}" ;;
    esac
}

ai-update >/dev/null
grep -q '^run --rm --entrypoint sh aiworkspace-herdr:migration-20260930 ' "$workspace_test_dir/calls"
grep -q '^service update --no-resolve-image --image aiworkspace-herdr:migration-20260930 ' "$workspace_test_dir/calls"
! grep -q '^pull ' "$workspace_test_dir/calls"

: > "$workspace_test_dir/calls"
workspace_missing_image=1 ai-update example/herdr:next >/dev/null
grep -q '^pull example/herdr:next$' "$workspace_test_dir/calls"

: > "$workspace_test_dir/calls"
if workspace_invalid_image=1 ai-update example/tmux:old >/dev/null 2>&1; then
    echo 'A imagem incompatível foi aceita' >&2
    exit 1
fi
! grep -q '^service update ' "$workspace_test_dir/calls"
if workspace_update_failed=1 ai-update >/dev/null 2>&1; then
    echo 'A falha no deploy foi ignorada' >&2
    exit 1
fi
echo 'ai-update: local image, explicit pull and incompatible image guard OK'
