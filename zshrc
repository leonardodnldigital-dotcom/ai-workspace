# ══════════════════════════════════════════════════════════════
# AI Workspace — Zsh Config
# ══════════════════════════════════════════════════════════════

# ── Histórico ──
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# ── Autocompletar ──
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# ── Path ──
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/local/go/bin:$PATH"

# ── Starship prompt ──
eval "$(starship init zsh)"

# ── Banner de versão (só em shell interativo) ──
if [[ -o interactive ]] && [ -n "$AI_WORKSPACE_VERSION" ]; then
    echo "🤖 AI Workspace v${AI_WORKSPACE_VERSION} (commit ${AI_WORKSPACE_COMMIT:0:7}, built ${AI_WORKSPACE_BUILD_DATE})"
    echo "   Welcome $(whoami)@$(hostname)"
fi

# ── Modern Unix tools (sem sobrescrever comandos nativos) ──
# Mantemos ls/cat/find originais pra compatibilidade com tools de AI agents
# Use os modernos diretamente quando quiser:
alias ll='eza -la --icons --group-directories-first'
alias lt='eza -la --tree --level=2 --icons'
alias lsi='eza --icons --group-directories-first'

# ── AI Workspace aliases ──
alias tls='herdr session list'
alias ta='herdr session attach'

# Atalho para os projetos: p buga, p osagenda, p (lista de projetos)
p() { cd "$HOME/projects/${1:-}"; }
compdef '_files -W ~/projects -/' p

# ── AI agents ──
alias cc='claude'
alias gm='gemini'
alias qc='qwen'
alias cu='cursor'
alias ccp='claude -p'

# ── Ferramentas ──
alias lp='lightpanda'
alias lps='lightpanda serve --host 0.0.0.0 --port 9222'
alias cfd='cloudflared tunnel --url'

# ── Git ──
alias gs='git status'
alias gl='git log --oneline -20'
alias gp='git pull'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gco='git checkout'

# ── Env vars ──
export LIGHTPANDA_DISABLE_TELEMETRY=true
export RUSTUP_HOME="/root/.rustup"
export CARGO_HOME="$HOME/.cargo"
export STARSHIP_CONFIG="$HOME/.config/starship.toml"
