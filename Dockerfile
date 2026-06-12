FROM node:22-bookworm-slim

# ══════════════════════════════════════════════════════════════
# AI Workspace Container
#
# Base: node:22-bookworm-slim (Debian 12 + Node.js 22 LTS)
# Organizado por frequência de mudança (cache-friendly):
#   1. Sistema + apt          (quase nunca muda)
#   2. Build tools + runtimes (raramente muda)
#   3. Ferramentas estáticas  (raramente muda)
#   4. User + configs         (muda às vezes)
#   5. AI CLIs                (atualizam frequentemente)
#   6. Fix permissões         (depende das CLIs)
# ══════════════════════════════════════════════════════════════

ENV DEBIAN_FRONTEND=noninteractive

# ══════════════════════════════════════════════════════════════
# LAYER 1: Sistema (quase nunca muda)
# ══════════════════════════════════════════════════════════════

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essenciais
    curl wget git jq unzip ca-certificates gnupg \
    # Terminal
    tmux zsh \
    # Busca rápida (usado pelos AI agents)
    ripgrep fd-find \
    # Python
    python3 python3-pip python3-venv \
    # Build tools (gcc, make — compilar do source)
    build-essential pkg-config libssl-dev \
    # SSH client + server (sshd para tunneling através do Swarm overlay)
    openssh-client openssh-server gosu \
    # Utilitários
    less nano htop tree \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    # sshd config: pubkey only, porta 2222, tunnel habilitado
    && mkdir -p /run/sshd \
    && printf 'Port 2222\nPermitRootLogin no\nPasswordAuthentication no\nPubkeyAuthentication yes\nAllowUsers dev\nX11Forwarding no\nAllowTcpForwarding yes\nGatewayPorts no\nPrintMotd no\n' > /etc/ssh/sshd_config.d/workspace.conf

# ══════════════════════════════════════════════════════════════
# LAYER 2: Runtimes e build tools (raramente muda)
# ══════════════════════════════════════════════════════════════

# ── Rust toolchain ──
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# ── Go ──
RUN curl -L -o /tmp/go.tar.gz https://go.dev/dl/go1.24.2.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# ── uv (gerenciador Python moderno) ──
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ══════════════════════════════════════════════════════════════
# LAYER 3: Ferramentas estáticas (raramente muda)
# ══════════════════════════════════════════════════════════════

# ── Modern Unix tools ──
RUN curl -L -o /tmp/bat.deb https://github.com/sharkdp/bat/releases/download/v0.24.0/bat_0.24.0_amd64.deb \
    && dpkg -i /tmp/bat.deb && rm /tmp/bat.deb \
    && curl -L -o /tmp/eza.tar.gz https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz \
    && tar xzf /tmp/eza.tar.gz -C /usr/local/bin && rm /tmp/eza.tar.gz \
    && chmod a+x /usr/local/bin/eza

# ── Starship prompt ──
RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

# ── Lightpanda (headless browser) ──
RUN curl -L -o /usr/local/bin/lightpanda \
    https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux \
    && chmod a+x /usr/local/bin/lightpanda

# ── cloudflared (quick tunnel) ──
RUN curl -L -o /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod a+x /usr/local/bin/cloudflared

# ── Playwright + Chromium (browser automation, E2E, scraping avançado) ──
# Instala Playwright global + Chromium + todas as deps do sistema (libnss, libatk, etc.)
# Pesa ~500MB mas permite bypass de anti-bot, testes E2E, scraping de sites protegidos
RUN npm install -g playwright \
    && npx playwright install --with-deps chromium \
    # Copiar browsers pra path compartilhado (user dev precisa acessar)
    && mv /root/.cache/ms-playwright /opt/ms-playwright \
    && chmod -R a+rX /opt/ms-playwright
ENV PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"

# ── agent-browser (CLI de browser automation para AI agents) ──
# Usa Chromium do Playwright (auto-detect) + Lightpanda como engine alternativo.
# Skill SKILL.md incluída em /opt/default-skills/ e seeded no boot.
RUN npm install -g agent-browser

# ══════════════════════════════════════════════════════════════
# LAYER 4: User, configs e scripts (muda às vezes)
# ══════════════════════════════════════════════════════════════

# ── Usuário não-root com zsh ──
# Cria os mountpoints pra todos os volumes do stack — sem isso, mounts viram
# diretórios root-owned e o user `dev` perde acesso à própria auth.
RUN useradd -m -s /bin/zsh dev \
    && mkdir -p /home/dev/projects \
    && mkdir -p /home/dev/.config \
    && mkdir -p /home/dev/.claude \
    && mkdir -p /home/dev/.gemini \
    && mkdir -p /home/dev/.qwen \
    && mkdir -p /home/dev/.cursor \
    && mkdir -p /home/dev/.local/share/opencode \
    && mkdir -p /home/dev/.codex \
    && mkdir -p /home/dev/.cline \
    && mkdir -p /home/dev/.aider \
    && mkdir -p /home/dev/.ssh \
    && mkdir -p /home/dev/.agents/skills \
    && mkdir -p /home/dev/bin \
    && chown -R dev:dev /home/dev

# ══════════════════════════════════════════════════════════════
# LAYER 5: AI CLIs (atualizam frequentemente — no fim pro cache)
#
# CLI_CACHE_BUSTER: invalidado em cada push pelo CI (recebe github.sha).
# Sem isso, o cache-gha do Actions devolve eternamente a mesma versão
# de cada CLI — o `RUN curl | bash` e os `npm install -g` não têm
# nenhum input que mude entre builds, então hit de cache = CLIs velhas.
# ══════════════════════════════════════════════════════════════

ARG CLI_CACHE_BUSTER=dev
RUN echo "CLI layer build: $CLI_CACHE_BUSTER"

# ── Claude Code ──
RUN curl -fsSL https://claude.ai/install.sh | bash

# ── Gemini CLI ──
RUN npm install -g @google/gemini-cli

# ── Qwen Code ──
RUN npm install -g @qwen-code/qwen-code

# ── Cursor CLI ──
RUN curl -fsSL https://cursor.com/install | bash

# ── OpenCode CLI ──
RUN npm install -g opencode-ai

# ── Codex CLI (OpenAI) ──
RUN npm install -g @openai/codex

# ── Cline CLI ──
# kanban é uma dep companion que o cline tenta auto-instalar no 1º run;
# pré-instalamos aqui pra evitar EACCES em /usr/local/lib/node_modules/ como user dev.
RUN npm install -g cline kanban

# ── Aider (Python — instala via uv que já está no PATH do root) ──
# UV_TOOL_DIR/UV_TOOL_BIN_DIR redirecionam a instalação pra /opt (acessível pelo
# user `dev`); instalar no default /root/.local/share/uv/ cria um shim com shebang
# apontando pra /root/... que é 700 e não-atravessável pelo dev → "permission denied".
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    /root/.local/bin/uv tool install aider-chat \
    && chmod -R a+rX /opt/uv-tools

# ══════════════════════════════════════════════════════════════
# LAYER 6: Fix permissões (depende das CLIs acima)
#
# Claude e Cursor instalam em /root/.local/share/{claude,cursor-agent}/ e os
# binários ficam inacessíveis pro user `dev`. Aqui copiamos pra /opt/* e
# symlinkamos em /usr/local/bin (read-only, world-readable).
#
# Side effect intencional: o auto-updater nativo dessas CLIs grava novas
# versões em ~/.local/share/.../versions/, mas o symlink em PATH continua
# apontando pra versão de build em /opt — então auto-updates SÃO BAIXADOS
# MAS NUNCA EXECUTADOS. Atualizar Claude/Cursor exige rebuild da imagem.
# Ver README "Por que rebuild e não auto-update?".
# ══════════════════════════════════════════════════════════════

RUN mkdir -p /opt/claude \
    && cp -rL /root/.local/share/claude/* /opt/claude/ 2>/dev/null || true \
    && rm -f /usr/local/bin/claude \
    && ln -sf /opt/claude/versions/$(ls /opt/claude/versions/ | head -1) /usr/local/bin/claude \
    && chmod -R a+rX /opt/claude \
    # Cursor CLI: instala como "agent" em /root/.local/share/cursor-agent/
    && mkdir -p /opt/cursor-agent \
    && cp -rL /root/.local/share/cursor-agent/* /opt/cursor-agent/ 2>/dev/null || true \
    && rm -f /usr/local/bin/cursor \
    && ln -sf /opt/cursor-agent/versions/$(ls /opt/cursor-agent/versions/ | head -1)/cursor-agent /usr/local/bin/cursor \
    && chmod -R a+rX /opt/cursor-agent \
    # uv + rust (cargo, rustc, rustup)
    && cp /root/.cargo/bin/* /usr/local/bin/ 2>/dev/null || true \
    && chmod -R a+rX /root/.rustup 2>/dev/null || true \
    # Aider: já instalado direto em /usr/local/bin via UV_TOOL_BIN_DIR (LAYER 5)
    # Codex: config padrão p/ usar file-based credentials (sem keyring em Docker)
    && mkdir -p /home/dev/.codex \
    && echo 'cli_auth_credentials_store = "file"' > /home/dev/.codex/config.toml \
    && chown -R dev:dev /home/dev/.codex

# ══════════════════════════════════════════════════════════════
# LAYER 7: Configs do user dev (COPY invalida cache se mudou)
# ══════════════════════════════════════════════════════════════

USER dev
WORKDIR /home/dev

# ── Starship preset ──
RUN mkdir -p /home/dev/.config \
    && starship preset gruvbox-rainbow -o /home/dev/.config/starship.toml \
    && printf '\n[container]\ndisabled = true\n' >> /home/dev/.config/starship.toml \
    && printf '\n[gcloud]\ndisabled = true\n' >> /home/dev/.config/starship.toml

# ── tmux ──
COPY --chown=dev:dev tmux.conf /home/dev/.tmux.conf

# ── Scripts ──
COPY --chown=dev:dev scripts/ /home/dev/bin/
RUN chmod +x /home/dev/bin/*

# ── Zshrc ──
COPY --chown=dev:dev zshrc /home/dev/.zshrc

# ── Bashrc (fallback) ──
COPY --chown=dev:dev bashrc.append /tmp/bashrc.append
RUN cat /tmp/bashrc.append >> /home/dev/.bashrc && rm /tmp/bashrc.append

# ── Docs (acessíveis dentro do container em ~/docs) ──
COPY --chown=dev:dev docs/ /opt/docs/
COPY --chown=dev:dev README.md /opt/docs/README.md
RUN ln -s /opt/docs /home/dev/docs

# ── Default skills (baked na imagem, seeded no volume no boot) ──
COPY --chown=dev:dev .agents/skills/ /opt/default-skills/

# ══════════════════════════════════════════════════════════════
# Version metadata (injetado pelo CI)
# ══════════════════════════════════════════════════════════════

ARG AI_WORKSPACE_VERSION=dev
ARG AI_WORKSPACE_COMMIT=unknown
ARG AI_WORKSPACE_BUILD_DATE=unknown

ENV AI_WORKSPACE_VERSION=${AI_WORKSPACE_VERSION}
ENV AI_WORKSPACE_COMMIT=${AI_WORKSPACE_COMMIT}
ENV AI_WORKSPACE_BUILD_DATE=${AI_WORKSPACE_BUILD_DATE}

# OCI labels (visíveis em `docker inspect` e na UI do GHCR)
LABEL org.opencontainers.image.version="${AI_WORKSPACE_VERSION}"
LABEL org.opencontainers.image.revision="${AI_WORKSPACE_COMMIT}"
LABEL org.opencontainers.image.created="${AI_WORKSPACE_BUILD_DATE}"

# ══════════════════════════════════════════════════════════════
# ENV + CMD
# ══════════════════════════════════════════════════════════════

ENV PATH="/home/dev/bin:/home/dev/.local/bin:/usr/local/bin:/usr/local/go/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1
ENV LIGHTPANDA_DISABLE_TELEMETRY=true
ENV RUSTUP_HOME="/root/.rustup"
ENV CARGO_HOME="/home/dev/.cargo"
ENV STARSHIP_CONFIG="/home/dev/.config/starship.toml"

# Entrypoint: roda como root (inicia sshd), dropa pra dev (tmux + tail).
# Lógica extraída para scripts/entrypoint.sh pra manutenção.
USER root
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 2222

CMD ["/usr/local/bin/entrypoint.sh"]
