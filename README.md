# AI Workspace — Deploy Guide

Setup containerizado de **8 AI coding agents** no Docker Swarm, com persistência em volumes, SSH tunneling e acesso via Termius ou IDE's com SSH.

**Agents**: Claude Code, Gemini CLI, Qwen Code, Cursor CLI, OpenCode CLI, Codex CLI, Cline CLI, Aider

## Destino OS Agenda em preparação

Em 30/09/2026, o destino é `root@207.180.3.209` (`srv-2j3lui`), em Swarm
independente das origens. A origem `5.189.165.36` permanece disponível até o
usuário validar o acesso pelo PC e pela IDE. Esta seção e
[`aiworkspace-target.yaml`](aiworkspace-target.yaml) definem o destino; o guia
genérico abaixo descreve a instalação com volumes separados e rede compartilhada.

| Contrato | Destino |
|---|---|
| Imagem local | `aiworkspace-herdr:migration-20260930` |
| Persistência | Volume externo `aiworkspace_home` em todo `/home/dev` |
| Multiplexador | Herdr `0.9.1`, exclusivo |
| Limites | 8 CPUs e `32G` de RAM |
| Reservas | 1 CPU e `2G` de RAM |
| Rede | Overlay própria do workspace |
| SSH do container | Porta 2222, acessível pelo loopback do host |

A imagem foi derivada da base pré-copiada com conteúdo conferido, preservando
as versões das CLIs. O volume completo conserva projetos, configurações,
histórico, autenticação e chaves SSH, inclusive arquivos fora dos antigos mounts.
Preservar UID/GID e permissões; backups do home contêm credenciais e devem
permanecer restritos, fora do repositório. Processos e PTYs da origem não migram
com o volume; as sessões de agentes serão iniciadas no Herdr do destino.

No destino confirmado, o deploy usa a imagem já presente no nó, com o home
restaurado e a label `aiworkspace=true`:

```sh
AI_WORKSPACE_IMAGE=aiworkspace-herdr:migration-20260930 \
  docker stack deploy --resolve-image never -c aiworkspace-target.yaml aiworkspace
```

`ai-update` sem argumento reaplica a imagem atual do serviço. Para trocar de
versão, informar uma imagem explícita; se ela já estiver no nó, não há pull.
Antes de atualizar o serviço, o helper verifica Herdr e os arquivos necessários
ao boot fora de `/home/dev`, em container descartável sem montar o home real.
O deploy não escolhe `latest` automaticamente. Usar os aliases do fork validado;
reinstalar os aliases genéricos por `curl` pode desfazer essa proteção.

### Acesso pelo PC e VS Code

O firewall público permite TCP 22, 80 e 443. A porta 2222 fica bloqueada
externamente. O sshd do host permite ao root somente forwarding local para
`127.0.0.1:2222`; clipboard e CDP são encaminhados pela conexão ao container.
A chave operacional `AI_WORKSPACE_DESTINATION_SSH_PRIVATE_KEY` tem fonte no
Infisical `prod`, `/operator/local`, e consumidor `/root/.ssh/id_aiworkspace`
no destino, com modo `0600`. O PC utiliza suas próprias chaves autorizadas.

```sh
ssh -J root@207.180.3.209 -p 2222 \
  -o HostKeyAlias=aiworkspace-destino dev@127.0.0.1
```

Conferir o fingerprint do sshd restaurado antes de aceitar a host key. Para
VS Code Remote SSH, usar um alias distinto da origem em `~/.ssh/config` do PC:

```sshconfig
Host aiworkspace-destino
    HostName 127.0.0.1
    Port 2222
    User dev
    ProxyJump root@207.180.3.209
    HostKeyAlias aiworkspace-destino
```

Para clipboard e CDP, após iniciar os serviços no container:

```sh
ssh -N -J root@207.180.3.209 -p 2222 \
  -o HostKeyAlias=aiworkspace-destino \
  -L 13456:127.0.0.1:3456 -L 19222:127.0.0.1:9222 dev@127.0.0.1
```

O conteúdo do script `idev/osagenda` do PC ainda não foi informado. Preservar o
atalho atual até conferir esse script e validar o novo acesso com o usuário.

### Cópia do home e SQLite

A cópia está em andamento; os seis bancos SQLite do Codex usam online backup.
Não há ainda confirmação de restauração ou validação desses bancos no destino.

1. Inventariar todo `/home/dev` e copiar preservando permissões e arquivos ocultos.
2. Para cada SQLite em uso, gerar um backup consistente pela API
   `sqlite3.Connection.backup`, sem copiar `.db`, `-wal` e `-shm` separadamente.
3. Restaurar os backups com os consumidores do destino parados. Não reutilizar
   WAL/SHM antigos junto do banco restaurado; validar cada cópia com
   `PRAGMA integrity_check` retornando `ok` e conferir caminhos, contagens e
   permissões.
4. Validar SSH, IDE, repositórios e abertura dos agentes em Herdr no destino.
5. Antes de promover o destino, pausar os escritores da origem e os consumidores
   do destino durante o delta final do home e dos backups SQLite. Manter a origem
   e seu backup até a confirmação do usuário, evitando alterações concorrentes
   no mesmo projeto.

---

## TL;DR

```bash
# 1. Preparar chave SSH na VPS (necessaria pra ai-ssh e ai-tunnel)
# So gere se ainda nao tiver uma:
test -f ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -N "" -C "ai-workspace-host"
# Veja sua chave publica:
cat ~/.ssh/id_ed25519.pub
# Copie a saida — vai precisar no proximo passo

# 2. Deploy no Portainer
Portainer → Stacks → Add Stack → cole o conteudo de aiworkspace.yaml
Em SSH_AUTHORIZED_KEYS: descomente a linha e cole a chave publica do passo 1
Deploy the stack

# 3. Instalar atalhos no host
curl -fsSL https://raw.githubusercontent.com/leonardodnldigital-dotcom/ai-workspace/main/setup-host-aliases.sh | bash && source ~/.bashrc

# 4. Testar acesso ao container
ai-enter                                   # shell zsh direto — confirma que tudo subiu
exit

# 5. Usar (cada CLI pede auth na primeira vez)
ai-dev meu-projeto                         # abre os DEFAULTS (configurados via ai-setup)
ai-dev meu-projeto --claude                # só Claude
ai-dev meu-projeto --claude --gemini       # Claude + Gemini
ai-dev meu-projeto --codex --aider         # Codex + Aider
ai-dev meu-projeto --all                   # TODOS os 8 agents
ai-dev meu-projeto --rc                    # defaults + Remote Control no Claude
ai-dev meu-projeto --danger                # defaults + skip-permissions/yolo
ai-dev-danger meu-projeto                  # atalho pra --danger
ai-help                                    # lista todos os comandos

# Dentro do Herdr:
# Ctrl+B 1/2/3...  → alternar abas
# Ctrl+B q          → sair sem encerrar os agents
```

### TL;DR — Clipboard + Browser (tunnel completo)

```bash
# ── VPS host (terminal 1) — criar workspace ──
ai-dev meu-projeto --clipboard --browser

# ── VPS host (terminal 2) — abrir tunnels pro container ──
ai-tunnel 3456 9222

# ── PC local — tunnel ate a VPS ──
ssh -L 13456:localhost:3456 -L 19222:localhost:9222 root@<ip-vps>

# ── PC local — usar ──
# Clipboard:  http://localhost:13456        → Ctrl+V cola imagem
# DevTools:   chrome://inspect → Configure  → localhost:19222 → Inspect
```

---

## Por que esse modelo?

### Continuidade real entre devices

Você começa um refactor no desktop, sai pra almocar, e continua do celular
exatamente de onde parou. Nao e sync de arquivos — e a **mesma sessao** rodando
na VPS. Terminal, contexto do Claude, historico do Gemini, tudo intacto.

### Multiplos AI agents no mesmo projeto, sob demanda

8 agents disponiveis no mesmo diretorio. Use `--all` pra abrir todos, ou
so o que precisar. Cada um numa aba Herdr, sem competir por recursos
quando nao esta em uso. Configure defaults com `ai-setup`.

### Seguranca por isolamento

O container e descartavel. Se um agent executar um `rm -rf /` em modo danger,
o dano fica contido. Sua VPS, seus outros servicos (n8n, Chatwoot, bancos) nao
sao afetados. Recursos de CPU e RAM sao limitados pelo Swarm.

### Preview instantaneo de qualquer lugar

`npm run dev` + `cfd http://localhost:3000` = URL publica em 5 segundos.
Mostra pro cliente no celular, testa no tablet, compartilha com colega.
Sem deploy, sem dominio, sem config. Morreu quando fechou.

### SSH tunneling para debug remoto

sshd integrado (porta 2222) permite SSH tunneling atraves do overlay network
do Swarm. Conecte Chrome DevTools do seu PC ao Chromium headless do container,
forwarde qualquer porta. Veja `docs/cdp-live-debugging.md`.

### Acesso a infra interna

O container roda na `network_swarm_public` — mesma rede do Postgres, Redis,
n8n. MCPs dos agents podem se conectar ao banco, ao cache, as filas.
Seu AI agent tem acesso ao mesmo ecossistema que seus servicos de producao.

### Sessoes que sobrevivem a tudo

Desconectou o SSH? Caiu a internet? Fechou o Termius sem querer? O Herdr
continua rodando. Os agents continuam executando.
Voce reconecta e ta tudo la.

### Zero setup por projeto

Um comando (`ai-dev nome`) cria o workspace completo. Multiplos projetos rodam
em paralelo como sessoes Herdr independentes.

### Reprodutivel e portavel

Tudo e codigo: Dockerfile, stack YAML, scripts. Perdeu a VPS? Sobe outra,
builda a imagem, restaura os volumes do backup.

---

## Arquitetura

```
VPS (Debian 12)
├── Docker Swarm
│   ├── Traefik, Portainer, n8n...     ← seus servicos
│   └── ai-workspace (container)        ← 8 AI agents + browser + tools
│       ├── sshd :2222                  ← SSH tunneling (pubkey only)
│       ├── /home/dev/projects  → vol   ← repos, codigo
│       ├── /home/dev/.config   → vol   ← settings
│       ├── /home/dev/.agents   → vol   ← skills globais (todas as CLIs)
│       ├── /home/dev/.claude   → vol   ← auth Claude
│       ├── /home/dev/.gemini   → vol   ← sessions, memory
│       ├── /home/dev/.qwen     → vol   ← auth Qwen
│       ├── /home/dev/.cursor   → vol   ← auth Cursor
│       ├── /home/dev/.codex    → vol   ← auth Codex
│       ├── /home/dev/.cline    → vol   ← auth Cline
│       ├── /home/dev/.aider    → vol   ← config Aider
│       ├── /home/dev/.local/share/opencode → vol ← auth OpenCode
│       └── /home/dev/.ssh      → vol   ← chaves SSH
│
└── Host
    └── ai-enter / ai-dev / ai-ssh / ai-tunnel   ← atalhos
```

### Por que `node:22-bookworm-slim`?

| Criterio | Decisao |
|----------|---------|
| **Node.js** | Gemini CLI e Qwen Code requerem Node.js 20+. A base ja inclui Node 22 LTS + npm. |
| **glibc vs musl** | Claude Code e uv distribuem binarios nativos linkados contra glibc. Alpine (musl) causa crash. |
| **Debian 12 (Bookworm)** | Mesma distro do host da VPS. Sem surpresas de compatibilidade. |
| **Slim** | Sem docs, man pages e compiladores desnecessarios (~200MB vs ~1.1GB na variante full). |

---

## Stack incluida

### AI Agents

| Ferramenta | Instalacao | Auth |
|------------|------------|------|
| Claude Code | Native installer (`curl`) | `claude /login` (browser OAuth) |
| Gemini CLI | `npm i -g @google/gemini-cli` | `GEMINI_API_KEY` env var no stack |
| Qwen Code | `npm i -g @qwen-code/qwen-code` | Qwen OAuth (free) ou API key no stack |
| Cursor CLI | Native installer (`curl`) | `agent login` (browser OAuth) |
| OpenCode CLI | `npm i -g opencode-ai` | `opencode auth login` (multi-provider) |
| Codex CLI | `npm i -g @openai/codex` | `codex login --device-auth` ou API key |
| Cline CLI | `npm i -g cline` | `cline auth -p <provider> -k <key>` |
| Aider | `uv tool install aider-chat` | Env vars (`ANTHROPIC_API_KEY`, etc.) ou `.env` |

### Browser & Automacao

| Ferramenta | Funcao |
|------------|--------|
| Playwright + Chromium | Browser completo (E2E, scraping avancado, anti-bot) |
| agent-browser | CLI de browser automation para AI agents (usa Chromium do Playwright) |
| Lightpanda | Headless browser leve (MCPs, scraping simples) |

### Ferramentas

| Ferramenta | Funcao |
|------------|--------|
| cloudflared | Quick tunnel pra expor localhost |
| Herdr | Multiplexador de terminal com estado dos agents |
| Go 1.24 | Runtime Go |
| Rust | Toolchain Rust (cargo, rustc) |
| uv + Python 3 | Gerenciador Python moderno + runtime |
| sshd | SSH server (porta 2222, pubkey only) |
| bat, eza, fd, ripgrep | Modern Unix tools |
| Starship | Prompt informativo |
| git | Controle de versao |

---

## Passo 1: Criar volumes externos

```bash
for vol in projects config agents claude gemini qwen cursor opencode codex cline aider ssh; do
    docker volume create aiworkspace_${vol}
done
```

---

## Passo 2: Obter a imagem

### Opcao A — Pull do GHCR (recomendado)

```bash
docker pull ghcr.io/ffmenezes/ai-workspace:latest
```

> Se a imagem e privada:
> ```bash
> echo "$GITHUB_TOKEN" | docker login ghcr.io -u ffmenezes --password-stdin
> ```

### Opcao B — Build local

```bash
docker build -t ai-workspace:latest .
```

---

## Passo 3: Deploy

**Via Portainer**: Stacks → Add Stack → nome `aiworkspace` → colar `aiworkspace.yaml` → Deploy

**Via CLI**:
```bash
docker stack deploy -c aiworkspace.yaml aiworkspace
```

---

## Passo 4: Configurar aliases no host

```bash
curl -fsSL https://raw.githubusercontent.com/leonardodnldigital-dotcom/ai-workspace/main/setup-host-aliases.sh | bash
source ~/.bashrc
```

Mesmo comando serve pra **resetar** os aliases apos updates — o script remove o bloco antigo antes de reescrever. Rode `ai-help` pra ver a referencia completa.

---

## Passo 5: Autenticar as CLIs

```bash
ai-enter

# ── Claude Code (subscription Pro/Max) ──
claude /login
# Segue a URL no browser. Token fica em ~/.claude/.credentials.json

# ── Gemini CLI ──
# Gere API key em: https://aistudio.google.com/apikey
# IMPORTANTE: configure no aiworkspace.yaml (environment), NAO no ~/.bashrc
# O ~/.bashrc do container e recriado a cada rebuild — env var no stack sobrevive

# ── Qwen Code ──
# Opcao A: Qwen OAuth (gratuito, 1000 req/dia)
qwen
# Na primeira execucao, escolha "Qwen OAuth (Free)" e siga o browser
# Opcao B: API key (DashScope, OpenRouter) — configure no stack file

# ── Cursor CLI ──
agent login
# Browser OAuth. Token persiste em ~/.cursor/cli-config.json

# ── OpenCode CLI ──
opencode auth login
# Interativo: escolhe provider (Anthropic, OpenAI, Google, etc.) e cola a key
# Suporta multiplos providers ao mesmo tempo
opencode auth list

# ── Codex CLI (OpenAI) ──
codex login --device-auth
# Ou configure API key em ~/.codex/config.toml
# Usa file-based credentials (sem keyring em Docker)

# ── Cline CLI ──
cline auth -p anthropic -k SUA_API_KEY
# Suporta: anthropic, openai, openrouter, etc.

# ── Aider ──
# Configure env vars no aiworkspace.yaml ou .env no projeto:
# ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.
# Ou passe direto: aider --api-key anthropic=sk-...

exit
```

> **Persistencia**: Cada CLI guarda auth em seu volume dedicado — sobrevive a rebuild.
> Excecao: Gemini e Aider usam env vars — declare no `aiworkspace.yaml` (secao `environment:`).

---

## Passo 6: Configurar GitHub e clonar projetos

```bash
ai-enter

# Gerar chave SSH
ssh-keygen -t ed25519 -C "ai-workspace"

# Copiar chave publica → GitHub → Settings → SSH and GPG keys → New SSH key
cat ~/.ssh/id_ed25519.pub

# Testar conexao
ssh -T git@github.com

# Clonar um projeto
cd ~/projects
git clone git@github.com:seu-user/seu-repo.git meu-projeto

# Identidade do git (uma vez)
git config --global user.name "Seu Nome"
git config --global user.email "seu@email.com"

exit
ai-dev meu-projeto
```

A chave SSH persiste no volume `aiworkspace_ssh`.
Para multiplas contas GitHub, veja o **Apendice A** no final.

---

## Passo 7: Configurar defaults do ai-dev

Na primeira execucao do `ai-dev`, um wizard (`ai-setup`) pergunta quais agents
abrir por padrao, e se quer ativar **clipboard bridge** e **browser CDP** automaticamente.
Pra reconfigurar depois:

```bash
ai-setup            # wizard interativo
ai-setup --reset    # reseta e roda wizard de novo
```

Se ativados nos defaults, clipboard e browser iniciam automaticamente em todo `ai-dev`.
Flags `--clipboard` e `--browser` na linha de comando fazem override (ativam mesmo se o default e false).

---

## Uso diario

### Comando `ai-dev` — workspace modular

```bash
# Padrao — abre os DEFAULTS (configurados via ai-setup)
ai-dev meu-projeto

# So um agent
ai-dev meu-projeto --claude
ai-dev meu-projeto --aider

# Combinar quem quiser
ai-dev meu-projeto --claude --gemini
ai-dev meu-projeto --codex --cline

# Todos os 8 (override dos defaults)
ai-dev meu-projeto --all

# Modificadores (nao contam como "agent flag" — nao desativam os defaults)
ai-dev meu-projeto --rc                 # adiciona Remote Control no Claude
ai-dev meu-projeto --danger             # skip-permissions/yolo em quem suporta
ai-dev meu-projeto --clipboard          # clipboard bridge (cola imagens do PC via browser)
ai-dev meu-projeto --browser            # Chromium headless com CDP (DevTools remoto)
ai-dev meu-projeto --clipboard --browser  # ambos
ai-dev-danger meu-projeto               # atalho pra --danger
```

**Flags `--danger` por CLI** (cada uma usa o flag nativo):

| CLI | Flag |
|-----|------|
| claude | `--dangerously-skip-permissions` |
| gemini | `--yolo` |
| qwen | `--yolo` |
| cursor | `-f` |
| opencode | — (sem equivalente, ignorado) |
| codex | `--yolo` |
| cline | `--yolo` |
| aider | `--yes-always` |

### Dentro do Herdr

```bash
# ── Abas (cada agent abre numa aba) ──
Ctrl+B 1     → Claude Code
Ctrl+B 2     → Gemini / Qwen / etc. (depende do que abriu)
Ctrl+B n     → proxima aba
Ctrl+B p     → aba anterior
Ctrl+B w     → navegacao de workspaces

# ── Splits ──
Ctrl+B v     → split vertical
Ctrl+B -     → split horizontal
Ctrl+B h/j/k/l → navegar entre panes

# ── Sessoes (cada projeto = uma sessao) ──
Ctrl+B q     → detach (sessao continua rodando)
# Para outro projeto, saia com Ctrl+B q e rode ai-dev outro-projeto
```

### Gerenciar sessoes

```bash
ai-sessions                    # status de tudo (sessoes, agents, recursos)
ai-kill meu-projeto            # mata uma sessao
ai-kill-all                    # mata todas (preserva "main")
ai-delete meu-projeto          # mata sessao + APAGA pasta do projeto
```

### Multiplos projetos ao mesmo tempo

Cada `ai-dev` cria uma sessao Herdr independente:

```bash
ai-dev projeto-a --claude
Ctrl+B q                       # detach

ai-dev projeto-b --gemini
Ctrl+B q

ai-dev projeto-a               # reconecta ao primeiro projeto
```

### Quick Tunnel (acessar localhost de qualquer lugar)

```bash
npm run dev                    # server em localhost:3000
cfd http://localhost:3000      # URL publica instantanea
# Ctrl+C pra encerrar
```

Funciona pra qualquer porta. O tunel e efemero — morre quando fechar.

### SSH tunneling (debug remoto)

O container roda sshd na porta 2222 (pubkey only), permitindo SSH tunneling
atraves do overlay network do Docker Swarm.

```bash
# Do host da VPS:
ai-ssh                         # SSH direto no container
ai-tunnel 9222                 # forward porta 9222 do host pro container
ai-tunnel 9222 3000            # multiplas portas
```

Caso de uso principal: conectar Chrome DevTools do seu PC ao Chromium headless
do container pra debug ao vivo. Veja `docs/cdp-live-debugging.md` pra o guia completo.

**Setup SSH — duas opcoes (escolha uma):**

**Opcao A: Env var no stack (recomendado — sobrevive a tudo)**

```bash
# 1. No host da VPS, gere a chave se nao existir:
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# 2. Copie a chave publica:
cat ~/.ssh/id_ed25519.pub

# 3. Cole no aiworkspace.yaml, descomentando a linha SSH_AUTHORIZED_KEYS:
#    environment:
#      - SSH_AUTHORIZED_KEYS=ssh-ed25519 AAAA...restodachave root@vps

# 4. Redeploy do stack (Portainer ou docker stack deploy)

# 5. Testar:
ai-ssh
```

A chave e injetada automaticamente no boot do container. Mesmo que o volume
SSH esteja vazio ou seja recriado, o SSH funciona imediatamente.

**Opcao B: docker exec (rapido, mas manual)**

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub | docker exec -i $(docker ps -q -f name=aiworkspace) tee /home/dev/.ssh/authorized_keys
ssh -p 2222 dev@localhost
```

A chave persiste no volume `aiworkspace_ssh`, mas precisa ser refeita se o volume
for recriado. Prefira a Opcao A pra setup permanente.

> **Host keys**: as chaves do servidor sshd sao salvas no volume SSH automaticamente.
> Isso evita o erro "host key changed" apos rebuild da imagem.

### Clipboard bridge (colar imagens do PC)

O clipboard bridge permite colar imagens do seu PC diretamente no container,
para referenciar em qualquer CLI com `@path`.

```bash
# Opcao 1: ativado nos defaults (ai-setup)
ai-dev meu-projeto                     # clipboard ja inicia automaticamente

# Opcao 2: flag explicita
ai-dev meu-projeto --clipboard

# Opcao 3: standalone (no host)
ai-clipboard                           # inicia servidor + abre tunnel
```

No host da VPS (se nao usou ai-clipboard): `ai-tunnel 3456`
No PC: `ssh -L 13456:localhost:3456 root@<ip-vps>`
Abra `http://localhost:13456` no browser → **Ctrl+V** cola a imagem → `@path` e copiado automaticamente.
Cole o path no Termius com Ctrl+V.

### Browser CDP (DevTools remoto bidirecional)

Chromium headless compartilhado entre dev e agents. Voce interage via Chrome DevTools,
os agents conectam via CDP — mesmas abas, mesmo estado.

```bash
# Opcao 1: ativado nos defaults (ai-setup)
ai-dev meu-projeto

# Opcao 2: flag explicita
ai-dev meu-projeto --browser

# Opcao 3: direto no container
ai-browser                             # inicia Chromium CDP na porta 9222
ai-browser status                      # verifica se esta rodando
ai-browser stop                        # para o Chromium
```

No host da VPS: `ai-tunnel 9222`
No PC: `ssh -L 19222:localhost:9222 root@<ip-vps>`
Chrome: `chrome://inspect` → Configure → `localhost:19222` → Inspect

Dentro de qualquer CLI, peca ao agent:
> "Tira um screenshot do que estou vendo no browser"
> "Abre uma nova aba em https://example.com"

O agent conecta ao mesmo Chromium via `connectOverCDP('http://localhost:9222')`.

### Ralph Loop (agent autonomo)

O `ralph` roda um AI agent em loop ate completar uma tarefa:

```bash
ai-enter
cd ~/projects/meu-projeto

# Modo wizard (interativo)
ralph

# Modo direto
ralph -a claude   -p "implemente os testes do modulo auth" -d -m 30
ralph -a gemini   -f prompt.md
ralph -a qwen     -p "refatore o componente X" --done "FINALIZADO"
ralph -a cursor   -p "corrija os warnings do typescript" -d
ralph -a opencode -p "documente as funcoes publicas"
ralph -a codex    -p "adicione testes unitarios" -d
ralph -a cline    -p "resolva os TODOs no codigo"
ralph -a aider    -p "migre pra nova API" -d
```

| Flag | Descricao | Default |
|------|-----------|---------|
| `-a, --agent` | claude, gemini, qwen, cursor, opencode, codex, cline, aider | claude |
| `-p, --prompt` | prompt inline | — |
| `-f, --file` | prompt de arquivo | — |
| `-m, --max` | maximo de loops | 50 |
| `-d, --danger` | skip-permissions/yolo | false |
| `--done` | palavra de parada | RALPH_DONE |

Logs de cada iteracao ficam em `.ralph-logs/` dentro do projeto.

### Agent Links — skills compartilhadas entre todas as CLIs

O `ai-dev` roda automaticamente o `setup-agent-links` a cada abertura de projeto,
garantindo que **todas as 8 CLIs** enxerguem as mesmas skills:

```
~/projects/meu-app/
  .agents/
    skills/                          ← diretorio canonico (REAL)
      ralph-prompt → ~/.agents/skills/ralph-prompt   ← global (symlink)
      minha-skill/SKILL.md                           ← local (criada por qualquer CLI)

  .claude/skills → .agents/skills    ← symlink de diretorio (auto)
  .qwen/skills   → .agents/skills    ← symlink de diretorio (auto)
  # Gemini, Cursor, OpenCode, Codex ja leem .agents/skills/ nativamente
```

**Skills globais** ficam em `~/.agents/skills/` (volume `aiworkspace_agents`).
Skills novas adicionadas por qualquer CLI vao parar em `.agents/skills/` gracas
aos symlinks — todas as CLIs enxergam imediatamente.

**Instruction files** sao thin wrappers gerados automaticamente se nao existirem:

| Arquivo | CLI |
|---------|-----|
| `AGENTS.md` | OpenCode, Codex — fonte de verdade principal |
| `CLAUDE.md` | Claude Code → aponta para AGENTS.md |
| `GEMINI.md` | Gemini CLI → aponta para AGENTS.md |
| `QWEN.md` | Qwen Code → aponta para AGENTS.md |
| `.cursor/rules/base.mdc` | Cursor → aponta para AGENTS.md |
| `.clinerules` | Cline → aponta para AGENTS.md |
| `CONVENTIONS.md` | Aider → aponta para AGENTS.md |

### Default Skills (baked na imagem)

Skills em `.agents/skills/` do repo sao incluidas na imagem e seeded automaticamente
no primeiro boot. Modificacoes do user no volume nao sao sobrescritas.

| Skill | Descricao |
|-------|-----------|
| `agent-browser` | Browser automation via CDP (agent-browser CLI) |
| `cdp-shared` | Conectar ao Chromium CDP compartilhado (dev + agents na mesma instancia) |
| `clipboard` | Clipboard bridge — imagens coladas do PC, screenshots dos agents |
| `ralph-prompt` | Prompt architect para loops autonomos do ralph |

---

## Referencia de comandos

Rode `ai-help` pra ver a referencia completa. Resumo:

| Comando | Onde | Descricao |
|---------|------|-----------|
| `ai-enter` | Host | Shell zsh dentro do container |
| `ai-attach` | Host | Anexa ao Herdr principal ("main") |
| `ai-update [imagem]` | Host | Reaplica a imagem atual; argumento explícito troca versão após validação |
| `ai-version` | Host | Versao da imagem + boot log |
| `ai-fix-perms` | Host | Corrige owner em ~/projects (dev:dev) |
| `ai-ssh` | Host | SSH direto no container (porta 2222) |
| `ai-tunnel <porta> [...]` | Host | SSH tunnel de portas para o container |
| `ai-clipboard [porta]` | Host | Clipboard bridge: cola imagens via browser (default :3456) |
| `ai-browser [porta\|status\|stop]` | Container | Chromium headless com CDP (default :9222) |
| `ai-dev <projeto> [flags]` | H/C | Cria/reconecta sessao Herdr |
| `ai-dev-danger <projeto>` | H/C | Atalho: ai-dev + --danger |
| `ai-sessions` | H/C | Lista sessoes + processos + recursos |
| `ai-kill <projeto>` | H/C | Mata uma sessao Herdr |
| `ai-kill-all` | H/C | Mata todas as sessoes (preserva "main") |
| `ai-delete <projeto>` | H/C | Mata sessao + apaga pasta do projeto |
| `ai-setup` | H/C | Define quais agents abrem por padrao |
| `ai-help` | H/C | Referencia completa |
| `ralph -a <agent> -p "..."` | C | Loop autonomo de um agent |

---

## Documentacao detalhada

Guias especificos ficam em `docs/`:

| Documento | Conteudo |
|-----------|----------|
| `docs/browser-automation.md` | agent-browser, Playwright, Lightpanda — quando usar cada um |
| `docs/cdp-live-debugging.md` | Chrome DevTools remoto: SSH tunnel setup, 3 terminais, interacao ao vivo |
| `docs/troubleshooting.md` | Diagnostico: root vs dev, SSH, CDP, permissoes, container |

---

## Snippets do Termius

Configure em **Settings > Snippets**:

| Nome     | Comando                        |
|----------|--------------------------------|
| `enter`  | `ai-enter`                     |
| `dev`    | `ai-dev`                       |
| `claude` | `ai-dev --claude`              |
| `dev-rc` | `ai-dev --rc`                  |
| `ws`     | `ai-sessions`                  |
| `help`   | `ai-help`                      |

---

## Manutencao

### Instalar pacotes no container

O container roda como user `dev` (sem sudo). Para pacotes globais,
use `docker exec -u root` do host:

```bash
# npm global
docker exec -u root $(docker ps -q -f name=aiworkspace) npm install -g nome-do-pacote

# apt
docker exec -u root $(docker ps -q -f name=aiworkspace) bash -c "apt-get update && apt-get install -y nome-do-pacote"
```

Pacotes assim **nao sobrevivem a rebuild**. Se for algo permanente, adicione ao Dockerfile.

### Atualizar as CLIs

Para atualizar CLIs, construir uma imagem validada com Herdr e informar sua
referência explicitamente ao `ai-update`. Sem argumento, ele reaplica a imagem
atual do serviço, preservando a versão.

```bash
# Na VPS, com a imagem local validada nesta preparação:
ai-update aiworkspace-herdr:migration-20260930

# Reaplicar a imagem atual sem escolher uma nova versão:
ai-update
```

Uma imagem local já presente dispensa pull. Caso contrário, o helper busca a
referência explícita e valida Herdr e os artefatos de boot em container
descartável antes do rolling update. Para uma nova versão pelo GitHub Actions:

1. Editar Dockerfile (ou qualquer arquivo)
2. `git push`
3. Aguardar Actions (~5-10min)
4. Na VPS: chamar `ai-update` com a referência da imagem Herdr validada
5. Sessoes em execucao sao encerradas; os volumes persistem

Para usar uma instancia Swarm com nome diferente, exporte
`AI_WORKSPACE_SERVICE=meu_servico` antes de chamar `ai-update`.

### Por que rebuild e nao auto-update?

| CLI | Auto-update funciona? | Por que |
|-----|------------------------|---------|
| Claude Code | Nao | Binario copiado pra `/opt/claude` (read-only) e symlinkado em PATH. Auto-updater baixa novas versoes mas o symlink aponta pra versao de build. |
| Cursor CLI | Nao | Mesmo padrao (`/opt/cursor-agent` read-only). |
| Gemini / Qwen / OpenCode / Codex / Cline | Parcial | npm globals. `npm update -g <pkg>` funciona mas some no rebuild. |
| Aider | Parcial | `uv tool upgrade aider-chat` funciona mas some no rebuild. |

### Atualizar pontualmente (efemero, so dura ate o proximo rebuild)

```bash
ai-enter
npm update -g @google/gemini-cli      # Gemini
npm update -g @qwen-code/qwen-code    # Qwen
npm update -g opencode-ai             # OpenCode
npm update -g @openai/codex           # Codex
npm update -g cline                   # Cline
# Claude e Cursor: NAO ha caminho pontual — so rebuild.
# Aider: uv tool upgrade aider-chat
```

### Backup dos volumes

```bash
for vol in projects config agents claude gemini qwen cursor opencode codex cline aider ssh; do
    docker run --rm \
        -v aiworkspace_${vol}:/data \
        -v /opt/backups:/backup \
        debian:12-slim \
        tar czf /backup/aiworkspace_${vol}_$(date +%Y%m%d).tar.gz -C /data .
done
```

### Restaurar volume

```bash
docker run --rm \
    -v aiworkspace_projects:/data \
    -v /opt/backups:/backup \
    debian:12-slim \
    tar xzf /backup/aiworkspace_projects_20260330.tar.gz -C /data
```

---

## Checklist de verificacao

```bash
ai-enter                      # Entrou no container
whoami                        # Deve retornar "dev" (nao root)
claude --version              # Claude Code
gemini --version              # Gemini CLI
qwen --version                # Qwen Code
cursor --version              # Cursor CLI
opencode --version            # OpenCode CLI
codex --version               # Codex CLI
cline --version               # Cline CLI
aider --version               # Aider
cloudflared --version         # cloudflared
ai-dev teste --claude         # Workspace criado
Ctrl+B q                      # Detach
ai-kill teste                 # Cleanup
ai-sessions                   # Status
exit

# SSH (requer setup da chave — ver secao SSH tunneling)
ai-ssh                        # SSH no container
ai-tunnel 9222                # Tunnel de porta
```

---

## Seguranca

- Container roda como user `dev` (nao root). Entrypoint inicia como root (sshd), depois dropa pra `dev` via `gosu`
- sshd na porta 2222: pubkey only, sem root login, TCP forwarding habilitado
- Tokens ficam dentro dos volumes (nao expostos no YAML)
- `network_swarm_public` da acesso ao Postgres, Redis, etc. — util se MCPs precisarem
- Claude Remote Control usa outbound HTTPS — nao abre portas
- Limites de CPU/RAM controlados pelo Swarm (`deploy.resources.limits`)

---

## Versionamento — v0.x beta permanente

O projeto fica em **v0.x indefinidamente**. Nao ha plano de v1.0.0.

**Voce nao precisa marcar tag.** Cada `git push origin main` dispara o
GitHub Actions, que:

1. Le a ultima tag `v0.x.y` do repo
2. Bumpa o patch (`v0.1.5` → `v0.1.6`)
3. Cria a tag e empurra de volta pro repo
4. Builda a imagem e publica no GHCR com multiplas tags
5. Cria uma GitHub Release (prerelease) com changelog

**Tags publicadas**:

| Tag | Quando atualiza | Uso |
|-----|-----------------|-----|
| `:0.3.0` | Nunca (pin exato) | Producao que nao pode mudar |
| `:0.3` | A cada `v0.3.x` | Patches automaticos no minor |
| `:latest` | A cada push em main | Dev/teste |
| `:sha-abc1234` | Nunca (pin por commit) | Rollback granular |
| `:main` | A cada push em main | Bleeding edge |

**Minor bump manual** (raro — nova CLI, breaking change):

```bash
git tag v0.4.0
git push origin main --tags
```

**Pinar no `aiworkspace.yaml`**:

```yaml
image: ghcr.io/ffmenezes/ai-workspace:0.3       # patches automaticos
image: ghcr.io/ffmenezes/ai-workspace:0.3.0     # pin exato
image: ghcr.io/ffmenezes/ai-workspace:latest     # sempre o ultimo
```

**Atualizar pra versao especifica**:

```bash
ai-update ghcr.io/ffmenezes/ai-workspace:0.3.0
ai-update ghcr.io/ffmenezes/ai-workspace:sha-abc1234   # rollback
```

---

## Apendice A: Multiplas contas GitHub

O GitHub nao permite a mesma chave SSH em mais de uma conta. Gere chaves separadas:

```bash
ai-enter

# Chave da segunda conta
ssh-keygen -t ed25519 -C "conta2" -f ~/.ssh/id_ed25519_conta2
cat ~/.ssh/id_ed25519_conta2.pub
# → Adicionar no GitHub da segunda conta

# SSH config pra rotear automaticamente
cat > ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519

Host github-conta2
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_conta2
EOF

chmod 600 ~/.ssh/config
```

Uso:

```bash
git clone git@github.com:ffmenezes/meu-repo.git           # conta principal
git clone git@github-conta2:outra-conta/repo.git           # segunda conta

cd ~/projects/repo-conta2
git config user.name "Nome Conta2"
git config user.email "email@conta2.com"
```

Tudo persiste no volume `aiworkspace_ssh`.
