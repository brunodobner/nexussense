# Fase A — Expurgo do histórico do git

> **Para trabalhadores agênticos:** SUB-SKILL OBRIGATÓRIA: use
> superpowers:subagent-driven-development (recomendado) ou
> superpowers:executing-plans para implementar tarefa a tarefa. Os passos
> usam checkbox (`- [ ]`) para acompanhamento.

**Goal:** Remover os dois binários de `original/` e a pasta `versaopessoal/`
levando `.git` de 142 MB para menos de 5 MB, sem perder os binários do disco
nem quebrar a suíte de testes.

**Architecture:** `git-filter-repo` reescreve os 36 commits removendo três
caminhos: os dois binários e a pasta inteira. Como ele termina com reset forte sobre o histórico
reescrito, os binários são copiados para fora antes e devolvidos depois,
passando a viver no disco como arquivos ignorados. A tag anotada é recriada
com o nome correto e as referências de hash no README são corrigidas a
partir do mapa de commits que o próprio filter-repo gera.

**Tech Stack:** git 2.55.0, git-filter-repo 2.47.0-3 (pacote `extra` do
Arch), bash.

**Spec:** [docs/superpowers/specs/2026-09-05-melhorias-e-reforma-design.md](../specs/2026-09-05-melhorias-e-reforma-design.md) — §3 e §6.1

---

## Global Constraints

Valem para todas as tarefas. Qualquer violação interrompe a fase.

- **Suíte:** `./tests/run-all.sh` tem de terminar `8 passaram, 0 falharam, 0
  pularam... ` (sem root) e `sudo -A ./tests/run-all.sh` tem de dar
  **9 passaram, 0 falharam**. Antes e depois.
- **Sudo:** esta máquina pede senha e a sessão não é interativa. Usar
  `export SUDO_ASKPASS=~/.local/bin/claude-askpass` e `sudo -A`. Agrupar o
  trabalho com root em poucas chamadas grandes.
- **sha256 dos binários, imutáveis ao longo de toda a fase:**
  - `original/DAMX-GUI/DivAcerManagerMax` →
    `664f4e27312314d2084938ade0e3c8bd7b8937d14388754d72d3a32097bc51aa`
  - `original/DAMX-Daemon/DAMX-Daemon` →
    `801ccba4b24569fdb72b323124d5d39336265df5922148f54138993ff17ed993`
- **Nunca guardar nada em `/tmp`.** É tmpfs e some no reboot (Armadilha 11).
  A cópia de segurança dos binários vai em `~/damx-binarios-fase-a/`.
- **Caminhos a expurgar — exatamente estes três, nem um a mais:**
  ```
  original/DAMX-GUI/DivAcerManagerMax
  original/DAMX-Daemon/DAMX-Daemon
  versaopessoal/                        <- a pasta inteira, 15 arquivos
  ```
  Decidido em 2026-09-05: a `versaopessoal/` é obsoleta e sai por completo,
  não só seus dois binários. Isso apaga do histórico também o fonte
  adaptado, `install-damx.sh`, `uninstall-damx.sh`, `diagnostico-dkms.sh` e
  `patches/anv15-52.patch`. **Irreversível depois que `.git-backup` for
  apagado** (Task 6).
- **Contagem de commits:** medido antes de planejar — nenhum commit fica
  vazio. `689de2a` toca 17 arquivos (15 da pasta, 2 fora) e `375e3c5` toca
  28 (15 da pasta); os dois sobrevivem. Os 36 commits permanecem.
- **Estado de partida:** 36 commits, 1 tag anotada `upstream/1.0.2`
  apontando para `375e3c5`, árvore limpa, sem stash, sem submódulos, um
  worktree só.

---

## Task 1: Linha de base e rede de segurança

Nada é reescrito nesta tarefa. Ela existe para que, depois, se possa provar
o que mudou e o que não mudou.

**Files:**
- Create: `~/damx-fase-a-baseline.txt` (fora do repositório, não versionado)
- Create: `.git-backup/` (cópia integral, apagada na Task 6)

- [x] **Step 1: Instalar o git-filter-repo**

```bash
export SUDO_ASKPASS=~/.local/bin/claude-askpass
sudo -A pacman -S --needed --noconfirm git-filter-repo
```

- [x] **Step 2: Verificar que ficou instalado**

```bash
git filter-repo --version
```

Esperado: uma versão, `2.47.0` ou maior. Se sair "não é um comando git",
parar — o resto da fase depende dele.

- [x] **Step 3: Confirmar que a suíte está verde ANTES de tocar em qualquer coisa**

```bash
cd /home/brunodobner/Claude/Nitrosense
export SUDO_ASKPASS=~/.local/bin/claude-askpass
sudo -A ./tests/run-all.sh
```

Esperado: `9 passaram, 0 falharam, 0 pularam, 0 com alvo ausente`.

Se não estiver 9/9 aqui, **parar**. Um expurgo sobre base já quebrada
impede saber depois o que o expurgo quebrou.

- [x] **Step 4: Registrar a linha de base**

```bash
cd /home/brunodobner/Claude/Nitrosense
{
  echo "=== commits ==="; git rev-list --count HEAD
  echo "=== HEAD ==="; git rev-parse HEAD
  echo "=== tag ==="; git cat-file -t upstream/1.0.2; git rev-list -n1 upstream/1.0.2
  echo "=== .git ==="; du -sb .git | cut -f1
  echo "=== sha256 dos binarios ==="
  sha256sum original/DAMX-GUI/DivAcerManagerMax original/DAMX-Daemon/DAMX-Daemon
  echo "=== arquivos rastreados ==="; git ls-files | wc -l
  echo "=== lista completa de arquivos rastreados ==="; git ls-files
} > ~/damx-fase-a-baseline.txt
cat ~/damx-fase-a-baseline.txt | head -20
```

Esperado: 36 commits, `.git` na ordem de 148 milhões de bytes, os dois
sha256 batendo com os das Global Constraints.

- [x] **Step 5: Criar a cópia de segurança do .git**

```bash
cd /home/brunodobner/Claude/Nitrosense
cp -a .git .git-backup
du -sh .git-backup
```

Esperado: ~142 MB. Esta cópia é a rede de segurança da operação
destrutiva. Ela é apagada só na Task 6, depois de tudo verificado.

- [x] **Step 6: Confirmar o efeito, não o comando** (Armadilha 11)

```bash
[ -d .git-backup/refs ] && [ -s ~/damx-fase-a-baseline.txt ] \
  && echo "OK: backup e baseline existem e nao estao vazios" \
  || echo "FALHA: parar aqui"
```

Esperado: `OK: ...`. Se falhar, não prosseguir.

---

## Task 2: Preservar os binários fora do repositório

**Por que:** `git-filter-repo` termina com reset forte sobre o histórico
reescrito. Um arquivo que não existe mais em commit nenhum não sobrevive a
esse reset — sem esta tarefa, o expurgo apagaria os binários do disco.

**Files:**
- Create: `~/damx-binarios-fase-a/DivAcerManagerMax`
- Create: `~/damx-binarios-fase-a/DAMX-Daemon`

- [x] **Step 1: Copiar os dois binários para fora do repositório**

```bash
mkdir -p ~/damx-binarios-fase-a
cd /home/brunodobner/Claude/Nitrosense
cp -p original/DAMX-GUI/DivAcerManagerMax ~/damx-binarios-fase-a/
cp -p original/DAMX-Daemon/DAMX-Daemon    ~/damx-binarios-fase-a/
ls -l ~/damx-binarios-fase-a/
```

Esperado: dois arquivos, ~104 MB e ~17 MB.

Nota: `~/damx-binarios-fase-a/`, nunca `/tmp` — tmpfs some no reboot.

- [x] **Step 2: Provar que a cópia é fiel, byte a byte**

```bash
cd ~/damx-binarios-fase-a
sha256sum -c <<'EOF'
664f4e27312314d2084938ade0e3c8bd7b8937d14388754d72d3a32097bc51aa  DivAcerManagerMax
801ccba4b24569fdb72b323124d5d39336265df5922148f54138993ff17ed993  DAMX-Daemon
EOF
```

Esperado: duas linhas terminando em `OK`.

Se qualquer uma disser `FAILED`, **parar** e refazer a cópia. Prosseguir com
cópia ruim significa perder o binário de vez.

---

## Task 3: Expurgar os binários e a versaopessoal do histórico

Esta é a tarefa destrutiva. As duas anteriores existem para torná-la
reversível.

**Files:**
- Modify: todo o histórico do git (36 commits reescritos)
- Create: `.git/filter-repo/commit-map` (gerado pela ferramenta)

- [x] **Step 1: Ver, antes, quais blobs grandes existem**

```bash
cd /home/brunodobner/Claude/Nitrosense
git rev-list --objects --all \
 | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
 | awk '$1=="blob" && $3 > 1000000 {printf "  %8.1f MB  %s\n", $3/1048576, $4}' | sort -rn
```

Esperado: exatamente quatro linhas — 99.7 MB e 95.5 MB (as duas GUIs),
16.8 MB e 16.5 MB (os dois daemons).

Se aparecerem outras, **parar** e reavaliar: o plano assume estes quatro.

Registrar também a contagem de commits **imediatamente antes** da reescrita.
Números absolutos no texto do plano envelhecem — cada commit de documentação
muda o total. A verificação da Task 6 compara contra este arquivo, não
contra um número escrito à mão:

```bash
cd /home/brunodobner/Claude/Nitrosense
git rev-list --count HEAD > ~/damx-fase-a-commits-antes.txt
cat ~/damx-fase-a-commits-antes.txt
```

- [x] **Step 2: Rodar o filter-repo**

`--force` é necessário porque este não é um clone recém-feito. `--invert-paths`
inverte o sentido de `--path`: em vez de manter só esses caminhos, remove-os.

```bash
cd /home/brunodobner/Claude/Nitrosense
git filter-repo --force --invert-paths \
  --path original/DAMX-GUI/DivAcerManagerMax \
  --path original/DAMX-Daemon/DAMX-Daemon \
  --path versaopessoal/
```

Esperado: barra de progresso e, ao final, `Completely finished after ...`.

A barra final `versaopessoal/` remove a pasta inteira e tudo abaixo dela —
os dois binários e os 13 arquivos de fonte.

- [x] **Step 3: Recolher o lixo de verdade**

O filter-repo já roda um `gc`, mas os objetos antigos só somem depois de o
reflog expirar. Sem este passo, `.git` continua grande e o critério de
conclusão falha por engano.

```bash
cd /home/brunodobner/Claude/Nitrosense
git reflog expire --expire=now --all
git gc --prune=now --aggressive
du -sh .git
```

Esperado: `.git` **abaixo de 5 MB**. Se continuar grande, verificar se
`.git-backup` foi contado por engano (ele é um diretório separado, não deve
entrar) e se o reflog realmente expirou.

- [x] **Step 4: Confirmar que os blobs grandes sumiram**

```bash
cd /home/brunodobner/Claude/Nitrosense
git rev-list --objects --all \
 | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
 | awk '$1=="blob" && $3 > 1000000 {print "  RESTOU:", $3, $4}' \
 || true
echo "  (nenhuma linha RESTOU acima = expurgo completo)"
```

Esperado: nenhuma linha `RESTOU`.

- [x] **Step 5: Confirmar que o histórico continua íntegro no resto**

```bash
cd /home/brunodobner/Claude/Nitrosense
printf 'commits agora: '; git rev-list --count HEAD
printf 'commits antes: '; grep -A1 '=== commits ===' ~/damx-fase-a-baseline.txt | tail -1
echo "--- versaopessoal/ sumiu do historico inteiro? ---"
git log --oneline --all -- versaopessoal/ | sed 's/^/  RESTOU: /'
echo "  (sem linhas RESTOU = a pasta saiu de todos os commits)"
echo "--- os dois commits que a tocavam sobreviveram? ---"
git log --oneline --all | grep -c 'baseline intocado\|remover versaopessoal'
```

Esperado: **36 commits nos dois casos** — o expurgo remove conteúdo de
arquivo, não commits, e foi medido antes que nenhum commit ficaria vazio.
Nenhuma linha `RESTOU`. E a última contagem deve dar **2**: os dois commits
que mexiam na pasta continuam no histórico, agora com as mensagens falando
de arquivos que não existem mais — o que é o registro correto do que houve.

- [x] **Step 6: Confirmar que os binários sumiram da árvore de trabalho**

Isto não é defeito — é o comportamento esperado, e é a razão de existir da
Task 2.

```bash
cd /home/brunodobner/Claude/Nitrosense
ls -l original/DAMX-GUI/ original/DAMX-Daemon/ 2>&1
```

Esperado: os `.png` continuam em `DAMX-GUI/`, mas `DivAcerManagerMax` e
`DAMX-Daemon` não estão mais lá. A Task 4 os devolve.

---

## Task 4: Devolver os binários e passar a ignorá-los

**Files:**
- Modify: `.gitignore`
- Restore: `original/DAMX-GUI/DivAcerManagerMax`, `original/DAMX-Daemon/DAMX-Daemon`

- [x] **Step 1: Acrescentar os binários ao .gitignore**

O `.gitignore` atual só cobre artefatos de build de módulo do kernel. As
duas entradas novas vão com um comentário que explica a decisão, no estilo
do arquivo.

```bash
cd /home/brunodobner/Claude/Nitrosense
cat >> .gitignore <<'EOF'

# Binarios distribuidos pelo upstream, nao versionados de proposito.
#
# Sao blobs opacos de ~121 MB somados: nao dao para ler, comparar nem
# revisar, e cada release nova acrescentaria outro tanto ao historico
# para sempre. Ficam no disco, onde o setup.sh os encontra -- a
# instalacao continua funcionando offline.
#
# Para obte-los numa maquina limpa: baixar DAMX-<versao>.tar.xz e o
# .sha256 correspondente das releases do upstream, conferir e extrair.
original/DAMX-GUI/DivAcerManagerMax
original/DAMX-Daemon/DAMX-Daemon
EOF
tail -15 .gitignore
```

- [x] **Step 2: Comitar o .gitignore ANTES de devolver os arquivos**

Nesta ordem, os binários já nascem ignorados e não há janela em que
`git add .` possa recolocá-los no histórico.

```bash
cd /home/brunodobner/Claude/Nitrosense
git add .gitignore
git -c user.name="brunodobner" -c user.email="contato@brunodobner.com" \
    commit -m "chore: parar de versionar os binarios do upstream

Sao ~121 MB de blob opaco que nao dao para ler, comparar nem revisar, e
cada release nova somaria outro tanto ao historico para sempre. Ficam no
disco, onde o setup.sh os encontra: a instalacao continua offline.

O historico deles acabou de ser expurgado com git-filter-repo; esta
entrada impede que voltem.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [x] **Step 3: Devolver os binários ao lugar**

```bash
cd /home/brunodobner/Claude/Nitrosense
cp -p ~/damx-binarios-fase-a/DivAcerManagerMax original/DAMX-GUI/
cp -p ~/damx-binarios-fase-a/DAMX-Daemon       original/DAMX-Daemon/
chmod +x original/DAMX-GUI/DivAcerManagerMax original/DAMX-Daemon/DAMX-Daemon
ls -l original/DAMX-GUI/ original/DAMX-Daemon/
```

Esperado: os dois binários de volta, com bit de execução.

- [x] **Step 4: Provar que voltaram idênticos**

```bash
cd /home/brunodobner/Claude/Nitrosense
sha256sum -c <<'EOF'
664f4e27312314d2084938ade0e3c8bd7b8937d14388754d72d3a32097bc51aa  original/DAMX-GUI/DivAcerManagerMax
801ccba4b24569fdb72b323124d5d39336265df5922148f54138993ff17ed993  original/DAMX-Daemon/DAMX-Daemon
EOF
```

Esperado: duas linhas `OK`. Este é o critério 2 da §10 da spec.

- [x] **Step 5: Provar que o git realmente os ignora**

```bash
cd /home/brunodobner/Claude/Nitrosense
git status --porcelain | grep -v '^?? \.git-backup/$'
echo "  (vazio acima = os binarios estao ignorados, como deve ser)"
git check-ignore -v original/DAMX-GUI/DivAcerManagerMax original/DAMX-Daemon/DAMX-Daemon
```

O `grep -v` exclui `.git-backup/`, que é a cópia de segurança criada na
Task 1 e vive na raiz do repositório até a Task 6. Ela aparece como não
rastreada e **não é problema** — sem esta exclusão, a verificação soaria
alarme falso.

Esperado: nenhuma outra linha, e o `check-ignore` mostrando a linha do
`.gitignore` que casa com cada binário. Se os binários aparecerem como não
rastreados, o `.gitignore` não pegou — corrigir antes de seguir.

---

## Task 5: Renomear a tag e corrigir as referências de hash

O `filter-repo` reescreveu a tag junto com os commits, mas manteve o nome
`upstream/1.0.2` — que está errado desde sempre: `1f88341` é a tag
`1.0.2-h1` do upstream, não a `1.0.2` (que é `c1a4292`). Ver §7 da spec.

**Files:**
- Modify: `README.md`
- Modify: refs de tag do git

- [x] **Step 1: Descobrir o novo hash do commit da baseline**

O filter-repo grava o mapa antigo→novo. `375e3c5` é o commit que o README
cita e para onde a tag aponta.

```bash
cd /home/brunodobner/Claude/Nitrosense
NOVO=$(grep -i '^375e3c53bab4a10688fb1bc27c4c91a5eb4a3a18' .git/filter-repo/commit-map | awk '{print $2}')
echo "375e3c5 (antigo) -> ${NOVO} (novo)"
echo "$NOVO" > ~/damx-fase-a-novo-hash.txt
git log --oneline -1 "$NOVO"
```

Esperado: um hash novo de 40 caracteres, e o `git log` mostrando
`chore: baseline intocado (upstream 1f88341 + versaopessoal)`.

Se o `grep` não achar, listar o mapa (`head .git/filter-repo/commit-map`)
e localizar a linha manualmente.

- [x] **Step 2: Criar a tag com o nome correto, preservando a anotação**

```bash
cd /home/brunodobner/Claude/Nitrosense
NOVO=$(cat ~/damx-fase-a-novo-hash.txt)
git -c user.name="brunodobner" -c user.email="contato@brunodobner.com" \
    tag -a upstream/1.0.2-h1 "$NOVO" \
    -m "DAMX 1.0.2-h1 / daemon 0.5.2 / drivers 25.701 - upstream 1f88341, intocado

Renomeada de upstream/1.0.2: o commit 1f88341 e a tag 1.0.2-h1 do upstream
(o hotfix de 2026-07-23), nao a 1.0.2, que e c1a4292."
git tag -d upstream/1.0.2
git tag -n99
```

Esperado: só `upstream/1.0.2-h1` na listagem, com a anotação nova.

- [x] **Step 3: Confirmar que a tag aponta para o commit certo**

```bash
cd /home/brunodobner/Claude/Nitrosense
git cat-file -t upstream/1.0.2-h1
git log --oneline -1 upstream/1.0.2-h1
git ls-tree --name-only upstream/1.0.2-h1
```

Esperado: tipo `tag` (anotada), o commit da baseline, e a árvore contendo
`.gitignore`, `original` e `versaopessoal`.

- [x] **Step 4: Verificar que o diff contra a tag ainda funciona**

É o comando que o README documenta como o procedimento de atualização — se
ele quebrar, o repositório perdeu sua ferramenta principal.

```bash
cd /home/brunodobner/Claude/Nitrosense
git diff --stat upstream/1.0.2-h1 -- original/
```

Esperado: os mesmos 6 arquivos de sempre — `Makefile`, `dkms.conf`,
`linuwu_sense.service`, `linuwu_sense.c`, `nitro-key-detection.sh`,
`setup.sh`. Os binários **não** aparecem: saíram do histórico dos dois
lados.

- [x] **Step 5: Corrigir as referências quebradas no README**

O README cita `375e3c5` e `upstream/1.0.2`, ambos inexistentes agora.

```bash
cd /home/brunodobner/Claude/Nitrosense
NOVO=$(cat ~/damx-fase-a-novo-hash.txt)
CURTO=$(git rev-parse --short "$NOVO")
sed -i "s|upstream/1\.0\.2\b|upstream/1.0.2-h1|g; s|375e3c5|${CURTO}|g" README.md
grep -n "upstream/1.0.2-h1\|${CURTO}" README.md | sed 's/^/  /'
```

Esperado: as ocorrências atualizadas. Conferir que nenhuma linha ficou
dizendo `upstream/1.0.2-h1-h1` (duplicação por substituição repetida).

- [x] **Step 6: Remover do README a seção da versaopessoal**

O README tem um parágrafo dizendo que a `versaopessoal/` *"continua íntegra
no histórico"* e ensinando `git checkout 375e3c5 -- versaopessoal/`. Nada
disso é mais verdade — a pasta saiu de todos os commits.

Localizar esse trecho em `README.md` (fica na seção **Histórico**, depois do
parágrafo sobre `docs/superpowers/`) e **apagá-lo por inteiro**, incluindo o
bloco de código com o `git checkout`. Substituir por uma frase que registre o
que houve:

```markdown
A pasta `versaopessoal/`, fork local de 2025 que originou este trabalho, foi
removida do histórico no expurgo de 2026-09-05, depois de suas adaptações
terem sido portadas para `original/`. Era obsoleta e respondia por 112 MB
dos 142 MB do repositório.
```

Conferir depois que nenhuma menção órfã sobreviveu:

```bash
cd /home/brunodobner/Claude/Nitrosense
grep -n 'versaopessoal' README.md | sed 's/^/  /'
```

Esperado: só a frase nova. Qualquer linha ainda mandando fazer `git
checkout ... versaopessoal/` é instrução quebrada e tem de sair.

- [x] **Step 7: Comitar as correções do README**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add README.md
git -c user.name="brunodobner" -c user.email="contato@brunodobner.com" \
    commit -m "docs: corrigir as referencias quebradas pelo expurgo

A tag passou a se chamar upstream/1.0.2-h1: o commit 1f88341 e o hotfix
1.0.2-h1 do upstream, nao a 1.0.2, que e c1a4292. O rotulo estava errado
desde o inicio, e o filter-repo recriou as tags de qualquer forma -- era o
momento de acertar.

O hash da baseline mudou com a reescrita do historico, e a secao sobre a
versaopessoal saiu: a pasta foi removida de todos os commits, entao o
'git checkout ... -- versaopessoal/' que o README ensinava virou instrucao
quebrada.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Verificação final e remoção da rede de segurança

**Files:**
- Delete: `.git-backup/`
- Delete: `~/damx-binarios-fase-a/`

- [x] **Step 1: Rodar a suíte inteira**

```bash
cd /home/brunodobner/Claude/Nitrosense
export SUDO_ASKPASS=~/.local/bin/claude-askpass
sudo -A ./tests/run-all.sh
```

Esperado: `9 passaram, 0 falharam, 0 pularam, 0 com alvo ausente` — igual
ao Step 3 da Task 1.

Se algum teste falhar ou reportar alvo ausente, **não apagar o backup**.
Diagnosticar primeiro; a restauração está descrita no Step 5.

- [x] **Step 2: Conferir todos os critérios de conclusão da fase**

```bash
cd /home/brunodobner/Claude/Nitrosense
echo "=== 1. .git abaixo de 5 MB ==="
du -sm .git | awk '{print ($1 < 5) ? "  OK  " $1 " MB" : "  FALHA  " $1 " MB"}'

echo "=== 2. tag correta e unica ==="
git tag | sed 's/^/  /'

echo "=== 3. binarios presentes, integros e ignorados ==="
sha256sum -c <<'EOF' 2>&1 | sed 's/^/  /'
664f4e27312314d2084938ade0e3c8bd7b8937d14388754d72d3a32097bc51aa  original/DAMX-GUI/DivAcerManagerMax
801ccba4b24569fdb72b323124d5d39336265df5922148f54138993ff17ed993  original/DAMX-Daemon/DAMX-Daemon
EOF
git status --porcelain | grep -v '^?? \.git-backup/$' | sed 's/^/  pendente: /'

echo "=== 4. nenhum blob grande no historico ==="
git rev-list --objects --all \
 | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' \
 | awk '$1=="blob" && $2 > 1000000 {print "  RESTOU: " $3}'
echo "  (sem linhas RESTOU = limpo)"

echo "=== 5. contagem de commits preservada ==="
ANTES=$(cat ~/damx-fase-a-commits-antes.txt)
AGORA=$(git rev-list --count HEAD)
echo "  antes da reescrita: $ANTES | agora: $AGORA | esperado: $((ANTES + 2))"
[ "$AGORA" -eq "$((ANTES + 2))" ] && echo "  OK" || echo "  FALHA: commits perdidos ou a mais"

echo "=== 6. integridade do repositorio ==="
git fsck --no-progress 2>&1 | head -5 | sed 's/^/  /'
echo "  (sem saida = integro)"
```

Esperado: todos OK, `git status` vazio, nenhuma linha `RESTOU`, `git fsck`
silencioso.

- [x] **Step 3: Verificar que o driver ainda compila**

O expurgo não deveria tocar em fonte, mas é barato provar.

```bash
cd /home/brunodobner/Claude/Nitrosense/original/Linuwu-Sense
make W=1 2>&1 | tail -5
make clean > /dev/null 2>&1
```

Esperado: compilação limpa, sem warnings, terminando em `LD [M]
src/linuwu_sense.ko`.

- [x] **Step 4: Apagar a rede de segurança — só depois de tudo acima passar**

```bash
cd /home/brunodobner/Claude/Nitrosense
rm -rf .git-backup
rm -rf ~/damx-binarios-fase-a
rm -f ~/damx-fase-a-baseline.txt ~/damx-fase-a-novo-hash.txt
du -sh .git
git status --porcelain; echo "(vazio = fim da fase A)"
```

- [x] **Step 5: Procedimento de restauração — se algo deu errado antes do Step 4**

Enquanto `.git-backup` existir, a fase é reversível por inteiro:

```bash
cd /home/brunodobner/Claude/Nitrosense
rm -rf .git
mv .git-backup .git
git checkout -- .
cp -p ~/damx-binarios-fase-a/DivAcerManagerMax original/DAMX-GUI/
cp -p ~/damx-binarios-fase-a/DAMX-Daemon       original/DAMX-Daemon/
git status
```

Depois disso o repositório volta exatamente ao estado do Step 4 da Task 1,
com os 36 commits e a tag `upstream/1.0.2` originais.

---

## Depois desta fase

Conforme §12 da spec e a sequência combinada:

```
fase A (este plano)
   ↓
brainstorm + spec do projeto da GUI/daemon em fonte propria
   ↓
fases B-G, ja sabendo o destino da §6
```

As fases B-G **não** têm plano escrito ainda, de propósito: a §6 (binários e
manifesto) depende do que a spec da GUI decidir, e planejá-la agora
produziria trabalho para descartar.

---

## Executado em 2026-09-05

Todas as seis tarefas concluídas. Resultado medido:

```
.git         147.171.205 B  ->  287.710 B      511x menor
commits      38 -> 40       (os 2 desta fase, nenhum perdido)
tag          upstream/1.0.2-h1
binarios     sha256 identicos, no disco, ignorados
suite        9/9
git fsck     silencioso
build W=1    exit=0, 0 warnings, 0 errors
```

### O que a execução revelou e o texto não previa

Quatro lacunas, todas descobertas por rodar e nenhuma por reler:

1. **A contagem de commits envelhecia sozinha.** O plano dizia 35 porque foi
   medido antes de o próprio plano ser comitado; virou 36, depois 38. A
   verificação passou a ser relativa, registrada no instante da reescrita.
2. **`.git-backup` aparece como não rastreado** e fazia duas verificações
   acusarem sujeira onde não havia.
3. **`original/DAMX-Daemon/` deixou de existir** após o expurgo — o
   diretório só continha o binário. O Step 3 da Task 4 precisou de um
   `mkdir -p` que o plano não tinha.
4. **`git filter-repo --version` responde um hash de commit**, não um
   número de versão como o Step 2 da Task 1 esperava.

Nenhuma quebraria a operação, mas as três primeiras produziriam **alarme
falso durante a fase destrutiva** — exatamente quando a verificação precisa
ser confiável.

### Nota de método

A checagem de build da Task 6 foi refeita: a primeira usava `tail -4`, e
warnings de compilação saem antes do fim da saída. A afirmação "compila
limpo" teria sido feita a partir de um trecho onde warnings nem apareceriam.
Refeita com contagem explícita de `warning:` e `error:`.
