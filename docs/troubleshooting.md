# Troubleshooting — AI Workspace

Guia de diagnóstico para problemas comuns. Cada seção inclui o **sintoma**, a **causa** e a **solução**.

---

## Diagnóstico geral

Antes de procurar o problema específico, rode esses comandos pra entender o estado atual:

```bash
# === Do HOST da VPS ===

# Container está rodando?
docker ps --filter name=aiworkspace

# Logs do container (últimas 20 linhas)
docker logs $(docker ps -q -f name=aiworkspace) 2>&1 | tail -20

# Com qual user o container está rodando?
docker exec $(docker ps -q -f name=aiworkspace) whoami
# Esperado: root (o entrypoint roda como root, mas dropa pra dev)

# Sessões Herdr ativas
ai-sessions

# Versão da imagem
ai-version

# Recursos (memória e disco)
docker exec -u dev $(docker ps -q -f name=aiworkspace) bash -c 'free -h; echo "---"; df -h /home/dev'
```

---

## Problemas de identidade (user root vs dev)

### Sintoma: "arquivos desaparecem" ou "pasta vazia onde deviam ter arquivos"

**Causa**: O Dockerfile termina com `USER root` (necessário para o sshd). Se o `docker exec` não especificar `-u dev`, entra como root — e root tem `/root` como home, não `/home/dev`. O `~/projects/` de root é um diretório diferente, vazio.

**Diagnóstico**:

```bash
# Confirma com qual user você está
whoami
# Se retornar "root", esse é o problema

# Compara os homes
echo $HOME
# root:  /root
# dev:   /home/dev
```

**Solução**: Sempre use `-u dev` no `docker exec`:

```bash
# ERRADO (entra como root):
docker exec -it $(docker ps -q -f name=aiworkspace) zsh -l

# CERTO (entra como dev):
docker exec -it -u dev $(docker ps -q -f name=aiworkspace) zsh -l
```

Os aliases do host (`ai-enter`, `ai-dev`, etc.) já incluem `-u dev` — use-os sempre que possível. Se atualizou a imagem mas não reinstalou os aliases, eles podem estar sem o `-u dev`:

```bash
# Reinstalar aliases (do host):
curl -fsSL https://raw.githubusercontent.com/ffmenezes/ai-workspace/main/setup-host-aliases.sh | bash
source ~/.bashrc
```

### Sintoma: "Permission denied" ao criar/editar arquivos em ~/projects

**Causa**: Arquivos criados por root (via docker exec sem `-u dev`) ficam com owner `root:root`. O user `dev` não consegue editar.

**Diagnóstico**:

```bash
# Ver owner dos arquivos
ls -la ~/projects/<projeto>/

# Se algum arquivo mostra "root root" em vez de "dev dev", é isso
```

**Solução**:

```bash
# Do HOST da VPS:
ai-fix-perms

# Ou manualmente:
docker exec -u root $(docker ps -q -f name=aiworkspace) chown -R dev:dev /home/dev/projects
```

---

## Problemas de SSH

### Sintoma: "Connection refused" ao tentar `ssh -p 2222 dev@localhost`

**Causa**: O sshd não está rodando ou a porta 2222 não está publicada.

**Diagnóstico**:

```bash
# 1. Verificar se sshd iniciou (nos logs do container)
docker logs $(docker ps -q -f name=aiworkspace) 2>&1 | grep sshd
# Esperado: "sshd started on port 2222"

# 2. Verificar se sshd está escutando DENTRO do container
docker exec $(docker ps -q -f name=aiworkspace) ss -tlnp | grep 2222
# Esperado: LISTEN ... *:2222

# 3. Verificar se a porta está publicada no HOST
ss -tlnp | grep 2222
# Esperado: docker-proxy escutando na 2222
```

**Soluções por cenário**:

- **sshd não iniciou**: Verifique se o entrypoint.sh está correto e se o container é da versão mais recente (`ai-update`)
- **sshd escuta no container mas não no host**: A porta 2222 não está no `aiworkspace.yaml`. Adicione e faça redeploy
- **docker-proxy escuta mas não conecta**: Swarm overlay issue — tente `docker stack deploy -c aiworkspace.yaml aiworkspace` novamente

### Sintoma: "Permission denied (publickey)"

**Causa**: A chave SSH do host não está no `authorized_keys` do container, ou as permissões estão erradas.

**Diagnóstico**:

```bash
# Verificar se authorized_keys tem conteúdo
docker exec $(docker ps -q -f name=aiworkspace) cat /home/dev/.ssh/authorized_keys
# Se vazio ou não existe, a chave não foi copiada

# Verificar permissões (sshd é MUITO strict com permissões)
docker exec $(docker ps -q -f name=aiworkspace) ls -la /home/dev/.ssh/
# Esperado:
#   drwx------  .ssh/              (700, owner dev)
#   -rw-------  authorized_keys    (600, owner dev)
```

**Solução**:

```bash
# Copiar a chave (do host):
cat ~/.ssh/id_ed25519.pub | docker exec -i $(docker ps -q -f name=aiworkspace) tee /home/dev/.ssh/authorized_keys

# Corrigir permissões:
docker exec $(docker ps -q -f name=aiworkspace) chmod 700 /home/dev/.ssh
docker exec $(docker ps -q -f name=aiworkspace) chmod 600 /home/dev/.ssh/authorized_keys
docker exec $(docker ps -q -f name=aiworkspace) chown -R dev:dev /home/dev/.ssh
```

> **Atenção**: `docker exec ... bash -c 'cat >> file' < local_file` **NÃO funciona** — o redirect `<` é consumido pelo shell local, não pelo docker exec. Use pipe: `cat file | docker exec -i ... tee target`.

### Sintoma: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"

**Causa**: O container foi recriado e gerou novas host keys.

**Solução**:

```bash
# No host da VPS:
ssh-keygen -R "[localhost]:2222"

# No seu PC (se conecta direto):
ssh-keygen -R "[<ip-vps>]:2222"
```

---

## Problemas de SSH tunnel / CDP

### Sintoma: `curl -s http://localhost:9222/json` retorna vazio

**Diagnóstico (do host)**:

```bash
# 1. Está entrando no container? (o script CDP está rodando?)
docker exec -u dev $(docker ps -q -f name=aiworkspace) curl -s http://localhost:9222/json
# Se retornar JSON aqui, o problema é o tunnel

# 2. O tunnel ai-tunnel está ativo?
ss -tlnp | grep 9222
# Deve mostrar ssh escutando na 9222
```

**Solução**: Se o `docker exec curl` retorna JSON mas o host não:
- Verifique se o `ai-tunnel 9222` está rodando
- Reinicie: Ctrl+C no ai-tunnel e rode novamente

### Sintoma: `http://localhost:19222/json` no PC fica carregando infinito

**Diagnóstico**:

```bash
# No host da VPS, confirme que a cadeia funciona:
curl -s http://localhost:9222/json
# Se retornar JSON, o problema é entre o PC e a VPS
```

**Soluções**:

- Verifique se o SSH tunnel do PC está ativo: `ssh -L 19222:localhost:9222 root@<ip>`
- Se deu "Permission denied" no bind, use porta mais alta (19222, 29222, etc.)
- Se o SSH conectou mas o tunnel não funciona, feche e reconecte

### Sintoma: `chrome://inspect` mostra "Device information is stale" sem targets

**Causa**: O Chrome não consegue conectar via WebSocket ao CDP target.

**Solução**:

1. Teste primeiro `http://localhost:19222/json` no browser — deve retornar JSON
2. Em `chrome://inspect` → Configure, confirme que tem `localhost:19222`
3. Se o JSON funciona mas os targets não aparecem, feche e reabra o `chrome://inspect`

---

## Problemas do Playwright

### Sintoma: "Cannot find module 'playwright'"

**Causa**: Playwright está instalado globalmente, mas `require('playwright')` procura localmente.

**Solução**: Use o require dinâmico nos scripts:

```javascript
const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');
```

Ou rode com NODE_PATH:

```bash
NODE_PATH=/usr/local/lib/node_modules node meu-script.js
```

### Sintoma: CDP não responde mesmo com `--remote-debugging-port=9222` no launch

**Causa**: `chromium.launch({ args: ['--remote-debugging-port=9222'] })` do Playwright **ignora** esse argumento — ele gerencia a porta CDP internamente.

**Solução**: Lance o Chromium diretamente com `spawn()` e conecte o Playwright via `connectOverCDP()`. Veja o `pw-login-cdp.js` como referência.

---

## CLI presa no diretório de outro projeto

### Sintoma: Abre `ai-dev projeto-b`, mas a CLI continua operando em `projeto-a`

**Causa**: A CLI já estava rodando numa sessão anterior com `projeto-a`. Ao reconectar ou abrir um novo projeto, o processo da CLI mantém o working directory original — ele não muda de pasta automaticamente.

**Diagnóstico**:

Dentro da janela da CLI, use o comando de shell escape para verificar o diretório atual:

```
# No Claude Code:
!pwd

# No Gemini CLI:
!pwd

# No Aider:
/run pwd
```

Se o resultado for `/home/dev/projects/projeto-a` mas você esperava `projeto-b`, é isso.

**Solução**:

1. **Mate a sessão antiga e reabra**:
   ```bash
   ai-kill projeto-a
   ai-dev projeto-b --claude
   ```

2. **Ou mate todas e comece limpo**:
   ```bash
   ai-kill-all
   ai-dev projeto-b
   ```

> **Por quê isso acontece?** O `ai-dev` cria a sessão Herdr em `~/projects/<projeto>` e lança a CLI nesse diretório. Mas se a sessão já existe (reconexão), ele apenas faz attach — não reinicia as CLIs. O working directory fica travado no que era quando a CLI iniciou.

---

## Problemas do container

### Sintoma: Container reinicia em loop

**Diagnóstico**:

```bash
# Ver logs de crash
docker service logs aiworkspace_aiworkspace --tail 50

# Ver eventos recentes
docker service ps aiworkspace_aiworkspace
```

**Causas comuns**:
- Entrypoint com erro de sintaxe (o container morre imediatamente)
- OOM kill (memória insuficiente — verifique os limites no yaml)

### Sintoma: Sessão Herdr "main" sumiu

**Causa**: O container pode ter reiniciado. A sessão "main" é criada pelo entrypoint no boot.

**Diagnóstico**:

```bash
# Ver se existe
docker exec -u dev $(docker ps -q -f name=aiworkspace) herdr session list
```

**Solução**: Se não existir, o container provavelmente reiniciou. Verifique os logs. As sessões de projeto (`ai-dev`) são independentes da "main".

### Sintoma: Falta de espaço em disco

```bash
# Verificar uso de disco
df -h

# Limpar imagens Docker antigas
docker image prune -a

# Limpar volumes não utilizados (CUIDADO — não apaga os external)
docker volume prune
```

---

## Comandos de diagnóstico rápido

Referência rápida dos comandos mais úteis pra investigar problemas:

```bash
# === IDENTIDADE ===
whoami                              # root ou dev?
echo $HOME                         # /root ou /home/dev?
id                                  # uid, gid, groups

# === CONTAINER ===
docker ps --filter name=aiworkspace                    # está rodando?
docker logs $(docker ps -q -f name=aiworkspace) 2>&1 | tail -20   # logs recentes
docker inspect $(docker ps -q -f name=aiworkspace) --format '{{.State.Status}}'

# === REDE / PORTAS ===
ss -tlnp | grep <porta>            # quem escuta nessa porta? (no host)
docker exec $(docker ps -q -f name=aiworkspace) ss -tlnp | grep <porta>  # no container
curl -s http://localhost:<porta>/   # porta responde?

# === SSH ===
ssh -v -p 2222 dev@localhost        # verbose — mostra cada passo da autenticação
docker exec $(docker ps -q -f name=aiworkspace) cat /home/dev/.ssh/authorized_keys
docker exec $(docker ps -q -f name=aiworkspace) ls -la /home/dev/.ssh/

# === PERMISSÕES ===
ls -la ~/projects/<projeto>/        # owner dos arquivos
stat -c '%a %U:%G' <arquivo>        # permissões numéricas

# === RECURSOS ===
docker exec -u dev $(docker ps -q -f name=aiworkspace) free -h    # memória
docker exec -u dev $(docker ps -q -f name=aiworkspace) df -h      # disco
htop                                                                # processos (interativo)
```
