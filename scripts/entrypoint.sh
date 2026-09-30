#!/bin/bash
# ══════════════════════════════════════════════════════════════
# entrypoint.sh — Boot do container AI Workspace
#
# Roda como root, inicia serviços, dropa pra user dev.
# Substitui o CMD inline do Dockerfile.
# ══════════════════════════════════════════════════════════════
set -e
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Seed a new whole-home volume and update only the scripts owned by this image.
# Existing shell settings, credentials and user scripts remain in the volume.
install -d -o dev -g dev -m 0750 /home/dev
install -d -o dev -g dev -m 0755 /home/dev/bin
for script in /opt/ai-workspace/bin/*; do
    [ -f "$script" ] || continue
    install -o dev -g dev -m 0755 "$script" "/home/dev/bin/$(basename "$script")"
done
for shell in zshrc bashrc; do
    if [ ! -f "/home/dev/.$shell" ] && [ -f "/opt/ai-workspace/$shell" ]; then
        install -o dev -g dev -m 0644 "/opt/ai-workspace/$shell" "/home/dev/.$shell"
    fi
done

LOG="/home/dev/.ai-workspace.log"

log() {
    echo "[$(date -Iseconds)] $*" | tee -a "$LOG"
}

# ── 1. Boot log ──
log "AI Workspace started — version=${AI_WORKSPACE_VERSION} commit=${AI_WORKSPACE_COMMIT} build_date=${AI_WORKSPACE_BUILD_DATE}"

# ── 2. Restaurar ~/.claude.json se ausente ──
if [ ! -f /home/dev/.claude.json ]; then
    LATEST=$(ls -t /home/dev/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
        cp "$LATEST" /home/dev/.claude.json
        chown dev:dev /home/dev/.claude.json
        log "Restored ~/.claude.json from $LATEST"
    fi
fi

# ── 3. Seed default skills ──
mkdir -p /home/dev/.agents/skills
for skill in /opt/default-skills/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    if [ ! -d "/home/dev/.agents/skills/$name" ]; then
        cp -r "$skill" "/home/dev/.agents/skills/$name"
        chown -R dev:dev "/home/dev/.agents/skills/$name"
        log "Seeded default skill: $name"
    fi
done

# ── 4. SSH server ──

# Host keys persistentes: salva no volume ~/.ssh/.host_keys/ para que
# não mudem entre rebuilds (evita "host key changed" no cliente SSH).
HOST_KEYS_DIR="/home/dev/.ssh/.host_keys"
mkdir -p "$HOST_KEYS_DIR"
if [ -z "$(ls -A "$HOST_KEYS_DIR" 2>/dev/null)" ]; then
    # Primeiro boot: gera e salva no volume
    ssh-keygen -A 2>/dev/null
    cp /etc/ssh/ssh_host_* "$HOST_KEYS_DIR/"
    log "SSH host keys generated and saved to volume"
else
    # Boot seguinte: restaura do volume
    cp "$HOST_KEYS_DIR"/ssh_host_* /etc/ssh/
    log "SSH host keys restored from volume"
fi

# Injetar authorized_keys via env var (se definida no stack)
# Permite setup automático sem docker exec manual.
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    mkdir -p /home/dev/.ssh
    # Append sem duplicar: só adiciona se a chave ainda não está presente
    touch /home/dev/.ssh/authorized_keys
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        grep -qF "$key" /home/dev/.ssh/authorized_keys 2>/dev/null || echo "$key" >> /home/dev/.ssh/authorized_keys
    done <<< "$SSH_AUTHORIZED_KEYS"
    log "SSH authorized_keys injected from environment"
fi

# Fixa permissões (sshd é strict)
mkdir -p /run/sshd
chmod 0755 /run/sshd
chmod 700 /home/dev/.ssh 2>/dev/null || true
chmod 600 /home/dev/.ssh/authorized_keys 2>/dev/null || true
chown -R dev:dev /home/dev/.ssh 2>/dev/null || true

# Inicia sshd em background
/usr/sbin/sshd
log "sshd started on port 2222"
chown dev:dev "$LOG"

# ── 5. Dropa pra dev → Herdr + tail ──
# A PID from the previous container cannot identify a process in this boot.
rm -f /home/dev/.ai-browser.pid
exec gosu dev env PATH="/home/dev/bin:/home/dev/.local/bin:/usr/local/go/bin:$PATH" bash -ec '
    herdr --session main server >> /home/dev/.ai-workspace.log 2>&1 &
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        herdr --session main workspace list >/dev/null 2>&1 && break
        sleep 0.2
    done
    state=$(herdr --session main workspace list)
    if ! jq -e ".result.workspaces | length > 0" <<< "$state" >/dev/null; then
        herdr --session main workspace create --cwd /home/dev/projects --label main >/dev/null
    fi
    exec tail -f /home/dev/.ai-workspace.log
'
