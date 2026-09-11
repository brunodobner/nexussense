# Renomeação do driver para `nexus_sense` — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Renomear o módulo do kernel de `linuwu_sense` para `nexus_sense`, e trocar o módulo instalado nesta máquina sem deixar dois disputando o mesmo dispositivo.

**Architecture:** O nome do módulo vem do nome do arquivo (`obj-m := src/<nome>.o`), não de nada dentro do `.c`. Renomear é, portanto: mover um arquivo, ajustar quatro declarações no `Makefile` e no `dkms.conf`, e acertar os nomes que o instalador e os testes escrevem. O lado Python já aceita os dois nomes desde o plano 1 e não precisa mudar para funcionar. A parte perigosa não é o código — é a **troca na máquina**, que exige remover o DKMS antigo dos três kernels antes de registrar o novo.

**Tech Stack:** DKMS 3.x, `make`, systemd, udev, Bash. Sem dependência nova.

**Spec:** `docs/superpowers/specs/2026-09-05-nexus-sense-gui-agente-design.md` §12

**Plano antecessor:** `docs/superpowers/plans/2026-09-05-nexus-sense-gui-e-bandeja.md`, concluído e mesclado em `master`.

---

## Global Constraints

- **Underscore do lado do kernel, hífen do lado do usuário.** O nome do módulo tem de casar com o `.ko`, então `nexus_sense`; o app e o agente continuam `nexus-sense` e `nexus-sense-agent`. Spec §12.1.
- **Os grupos sysfs não mudam.** `nitro_sense` e `predator_sense` estão fixados em `linuwu_sense.c:4052-4068` e nomeiam **a família do laptop**, não o projeto. Renomeá-los quebraria o driver. Spec §12.1.
- **A atribuição aos autores originais não se toca.** `MODULE_AUTHOR` credita Carlos Corbacho, E.M. Smith, `0x7375646F` (Linuwu-Sense) e Div Sharp. Isso é crédito, não marca do fork: **fica como está**. Só o banner do `pr_info` e a descrição do próprio fork mudam.
- **Ordem obrigatória na troca:** remover o antigo **antes** de registrar o novo. Dois pacotes DKMS com módulos diferentes para o mesmo dispositivo WMI produzem carregamento indeterminado.
- **Nunca deixar a máquina sem driver por engano.** O módulo novo é **compilado e verificado** antes de qualquer remoção. Se ele não compilar, nada é removido.
- **O `.ko` antigo existe em três kernels** (`6.18.48-1-cachyos-lts`, `7.2.2-1-cachyos`, `7.2.2-arch1-1`). `dkms remove --all` cobre os três de uma vez; conferir depois.
- Os testes de shell seguem o contrato do `tests/run-all.sh`: saída `0` passou, `2` pulou, `3` alvo ausente, qualquer outra falhou.
- **Suítes verdes antes e depois de cada tarefa:** `python3 -m pytest -q` e `./tests/run-all.sh`.

---

## O que está instalado hoje, e que a troca precisa desfazer

Medido em 2026-09-06, nesta máquina:

```
/usr/src/linuwu_sense-25.701/                      fonte do DKMS
/lib/modules/7.2.2-1-cachyos/updates/dkms/linuwu_sense.ko.zst
/lib/modules/7.2.2-arch1-1/updates/dkms/linuwu_sense.ko
/lib/modules/6.18.48-1-cachyos-lts/updates/dkms/linuwu_sense.ko.zst
/etc/modules-load.d/linuwu_sense.conf              conteudo: "linuwu_sense"
/etc/systemd/system/linuwu_sense.service           descarrega no desligamento
/etc/predator_state                                estado salvo pelo driver
```

O `/etc/predator_state` é escrito pelo próprio driver e **não é renomeado**: o nome vem do firmware Acer, como os grupos sysfs.

---

## Estrutura de arquivos

| arquivo | o que muda |
|---|---|
| `original/Linuwu-Sense/src/linuwu_sense.c` | **renomeado** para `nexus_sense.c`; dentro, só o banner do `pr_info` |
| `original/Linuwu-Sense/Makefile` | `obj-m` e `MODNAME` |
| `original/Linuwu-Sense/dkms.conf` | `PACKAGE_NAME` e `BUILT_MODULE_NAME` |
| `original/Linuwu-Sense/linuwu_sense.service` | **renomeado** para `nexus_sense.service`; `ExecStop` e `SyslogIdentifier` |
| `original/setup.sh` | 38 ocorrências: caminhos, nomes de unit, `modules-load.d`, mensagens |
| `tests/test-install-drivers.sh` | 11 ocorrências |
| `tests/test-dkms.sh` | 5 |
| `tests/test-uninstall.sh` | 5 |
| `tests/test-perfil-bateria.sh`, `test-usb-charging.sh`, `test-correcoes.sh` | 1 cada |
| `tests/test-renomeacao.sh` | **novo**: guarda o que não pode voltar |
| `src/nexus_sense/sysfs.py` | comentário do `MODULE_NAMES` |
| `docs/ESTADO.md`, `docs/ARMADILHAS.md` | registro |

---

### Task 1: Renomear o fonte do driver e provar que ele compila

O nome do módulo vem de `obj-m := src/<nome>.o`. Esta tarefa faz a
renomeação e **prova a compilação antes de qualquer coisa tocar o
sistema** — se ela falhar, nada foi removido e a máquina segue intacta.

**Files:**
- Rename: `original/Linuwu-Sense/src/linuwu_sense.c` → `nexus_sense.c`
- Modify: `original/Linuwu-Sense/Makefile`
- Modify: `original/Linuwu-Sense/dkms.conf`

**Interfaces:**
- Produces: um módulo cujo `.ko` se chama `nexus_sense.ko`.

- [ ] **Step 1: Mover o arquivo com o git, para o histórico seguir**

```bash
cd /home/brunodobner/Claude/Nitrosense
git mv original/Linuwu-Sense/src/linuwu_sense.c \
       original/Linuwu-Sense/src/nexus_sense.c
```

- [ ] **Step 2: Ajustar o `Makefile`**

Em `original/Linuwu-Sense/Makefile`, as duas primeiras linhas:

```make
obj-m := src/nexus_sense.o

MODNAME := nexus_sense
```

Nada mais no `Makefile` muda: as demais referências usam `$(MODNAME)`.

- [ ] **Step 3: Ajustar o `dkms.conf`**

Em `original/Linuwu-Sense/dkms.conf`, três linhas. O comentário do topo
também cita o nome do fonte:

```
# Configuracao DKMS do nexus_sense.
#
# PACKAGE_VERSION deve acompanhar DRIVER_VERSION em src/nexus_sense.c.
```

```
PACKAGE_NAME="nexus_sense"
BUILT_MODULE_NAME[0]="nexus_sense"
```

`PACKAGE_VERSION`, `MAKE`, `BUILT_MODULE_LOCATION`, `DEST_MODULE_LOCATION`
e `AUTOINSTALL` **não mudam**.

- [ ] **Step 4: Trocar só o banner dentro do `.c`**

Uma linha, e apenas ela. Em `original/Linuwu-Sense/src/nexus_sense.c`,
a chamada perto da linha 4913:

```c
    pr_info("Initializing Nexus Sense - Version %s\n", DRIVER_VERSION);
```

**Não toque no `MODULE_AUTHOR`.** Ele credita os autores originais e o
Linuwu-Sense; apagar isso seria apagar crédito, não renomear um fork. Os
comentários de cabeçalho que descrevem a linhagem (`Linuwu Sense Fork`,
`Div-Linuwu-Sense Fork`) também ficam: são história do arquivo.

- [ ] **Step 5: Compilar fora do sistema, sem instalar nada**

```bash
cd /home/brunodobner/Claude/Nitrosense/original/Linuwu-Sense
make clean 2>/dev/null; make 2>&1 | tail -20
ls -l src/nexus_sense.ko
```

Esperado: compila sem erro e o `.ko` aparece com o nome novo. **Se não
compilar, pare aqui** — o sistema não foi tocado e não deve ser.

- [ ] **Step 6: Conferir que o módulo se anuncia com o nome certo**

```bash
cd /home/brunodobner/Claude/Nitrosense/original/Linuwu-Sense
modinfo src/nexus_sense.ko | head -6
```

Esperado: `filename` terminando em `nexus_sense.ko`, e o `author`
**ainda citando Linuwu-Sense** — é a checagem de que o crédito ficou.

- [ ] **Step 7: Limpar o resultado da compilação**

```bash
cd /home/brunodobner/Claude/Nitrosense/original/Linuwu-Sense && make clean
git status --short original/Linuwu-Sense/
```

Esperado: só o arquivo renomeado e os dois editados.

- [ ] **Step 8: Commit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add original/Linuwu-Sense/
git commit -m "refactor: o modulo do kernel passa a se chamar nexus_sense

O nome vem do arquivo, via obj-m -- nao de nada dentro do .c. Entao
renomear e mover o fonte e acertar quatro declaracoes.

O MODULE_AUTHOR nao muda: ele credita Carlos Corbacho, E.M. Smith, o
Linuwu-Sense e o DAMX. Isso e credito aos autores, nao marca do fork, e
os comentarios de linhagem ficam pela mesma razao. So o banner do
pr_info passa a dizer Nexus Sense.

Compilado e verificado com modinfo antes de qualquer mudanca no sistema.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: A unit do módulo e o `modules-load.d`

**Files:**
- Rename: `original/Linuwu-Sense/linuwu_sense.service` → `nexus_sense.service`
- Modify: o conteúdo da unit

**Interfaces:**
- Consumes: o módulo `nexus_sense` da Task 1.
- Produces: `nexus_sense.service`, que descarrega o módulo no desligamento.

- [ ] **Step 1: Mover a unit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git mv original/Linuwu-Sense/linuwu_sense.service \
       original/Linuwu-Sense/nexus_sense.service
```

- [ ] **Step 2: Ajustar o conteúdo**

Em `original/Linuwu-Sense/nexus_sense.service`, quatro trocas. O
comentário longo do meio explica **por que a unit não carrega o módulo**
e continua valendo — só o nome do arquivo citado nele muda:

```ini
Description=Save Nexus Sense state and unload the module at shutdown
```

```ini
# /etc/modules-load.d/nexus_sense.conf, earlier than any unit ordered
```

```ini
ExecStop=/sbin/modprobe -r nexus_sense
SyslogIdentifier=nexus_sense
```

A linha `Documentation=` aponta para o repositório do PXDiv. **Deixe como
está**: é a origem do arquivo, e este fork não tem URL própria ainda.

- [ ] **Step 3: Conferir a sintaxe da unit**

```bash
systemd-analyze verify /home/brunodobner/Claude/Nitrosense/original/Linuwu-Sense/nexus_sense.service 2>&1 | head
```

Esperado: nenhuma linha de `error`. Um aviso sobre `Documentation=` sem
esquema conhecido é aceitável.

- [ ] **Step 4: Commit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add original/Linuwu-Sense/
git commit -m "refactor: a unit do modulo acompanha o nome novo

O comentario que explica por que esta unit NAO carrega o modulo --
quem carrega e o systemd-modules-load, mais cedo -- continua valendo
palavra por palavra; so o caminho citado nele muda.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: O instalador aprende o nome novo

São 38 ocorrências no `setup.sh`, mas elas são de três tipos só:
caminhos de fonte DKMS, nomes de unit e de `modules-load.d`, e mensagens
ao usuário.

**Files:**
- Modify: `original/setup.sh`

**Interfaces:**
- Consumes: `nexus_sense.service` e o `dkms.conf` renomeado.
- Produces: um instalador que registra `nexus_sense` no DKMS.

- [ ] **Step 1: Ver o que precisa mudar, antes de mudar**

```bash
cd /home/brunodobner/Claude/Nitrosense
grep -n "linuwu" original/setup.sh
```

Guarde a contagem: `grep -c linuwu original/setup.sh` — deve ser 38.

- [ ] **Step 2: Trocar as ocorrências**

```bash
cd /home/brunodobner/Claude/Nitrosense
sed -i 's/linuwu_sense/nexus_sense/g; s/Linuwu-Sense/Nexus Sense/g; s/Linuwu Sense/Nexus Sense/g' original/setup.sh
grep -c "linuwu\|Linuwu" original/setup.sh
```

Esperado: `0`.

- [ ] **Step 3: Conferir o que o `sed` fez a caminhos de diretório**

O fonte do driver mora em `original/Linuwu-Sense/`, e **essa pasta não
foi renomeada** — o `sed` acima pode ter quebrado o caminho. Confira e
restaure:

```bash
cd /home/brunodobner/Claude/Nitrosense
grep -n "Nexus Sense/" original/setup.sh
```

Toda ocorrência de `Nexus Sense/` que seja um **caminho** tem de voltar a
`Linuwu-Sense/`:

```bash
sed -i 's|Nexus Sense/|Linuwu-Sense/|g' original/setup.sh
grep -n "Linuwu-Sense/" original/setup.sh
```

> A pasta do fonte fica com o nome antigo de propósito: ela é o
> diretório do upstream, e renomeá-la faria toda release nova conflitar
> na extração. O que importa é o nome do **módulo**.

- [ ] **Step 4: Conferir a sintaxe**

```bash
cd /home/brunodobner/Claude/Nitrosense && bash -n original/setup.sh && echo "sintaxe ok"
```

- [ ] **Step 5: Conferir que a unit certa é instalada**

```bash
cd /home/brunodobner/Claude/Nitrosense
grep -n "nexus_sense.service\|modules-load.d" original/setup.sh
```

Esperado: as referências apontam para `nexus_sense.service` e
`/etc/modules-load.d/nexus_sense.conf`.

- [ ] **Step 6: Commit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add original/setup.sh
git commit -m "refactor: o instalador registra nexus_sense no DKMS

A pasta original/Linuwu-Sense/ fica com o nome antigo de proposito: ela
e o diretorio do upstream, e renomea-la faria toda release nova
conflitar na extracao. O que muda e o nome do modulo.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: A desinstalação tem de remover os dois nomes

Esta é a tarefa que impede o pior desfecho: um `linuwu_sense` órfão no
DKMS, ainda registrado para três kernels, disputando o dispositivo com o
`nexus_sense`.

**Files:**
- Modify: `original/setup.sh` (a função `comprehensive_cleanup`)
- Test: `tests/test-renomeacao.sh` (novo)

**Interfaces:**
- Produces: limpeza que cobre o nome antigo **e** o novo.

- [ ] **Step 1: Escrever o teste que falha**

`tests/test-renomeacao.sh`:

```bash
#!/bin/bash
# A renomeacao nao pode deixar rastro do nome antigo onde ele faca mal,
# nem apagar o credito aos autores originais.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="$RAIZ/original/setup.sh"
C="$RAIZ/original/Linuwu-Sense/src/nexus_sense.c"
M="$RAIZ/original/Linuwu-Sense/Makefile"
D="$RAIZ/original/Linuwu-Sense/dkms.conf"
U="$RAIZ/original/Linuwu-Sense/nexus_sense.service"
falhas=0

for alvo in "$S" "$C" "$M" "$D" "$U"; do
    [ -e "$alvo" ] || { echo "ERRO: alvo ausente: $alvo"; exit 3; }
done

ok()    { echo "  OK   $1"; }
falha() { echo "  FALHA $1"; falhas=$((falhas + 1)); }

# --- o nome novo esta onde precisa estar
grep -q '^obj-m := src/nexus_sense.o' "$M" && ok "Makefile compila nexus_sense" \
    || falha "Makefile ainda aponta para o fonte antigo"
grep -q '^PACKAGE_NAME="nexus_sense"' "$D" && ok "dkms.conf registra nexus_sense" \
    || falha "dkms.conf com o nome antigo"
grep -q 'modprobe -r nexus_sense' "$U" && ok "a unit descarrega nexus_sense" \
    || falha "a unit descarrega o modulo errado"

# --- o credito NAO pode ter sido renomeado
if grep -q 'Linuwu-Sense' "$C"; then
    ok "o credito aos autores originais ficou"
else
    falha "o MODULE_AUTHOR perdeu o credito ao Linuwu-Sense"
fi

# --- a limpeza cobre o nome antigo: sem isso sobra DKMS orfao
for padrao in 'dkms remove' 'linuwu_sense'; do
    if grep -q -- "$padrao" "$S"; then
        ok "a desinstalacao conhece: $padrao"
    else
        falha "a desinstalacao nao trata: $padrao"
    fi
done

# --- e os grupos sysfs NAO podem ter sido renomeados: sao do firmware
for grupo in nitro_sense predator_sense; do
    if grep -q "$grupo" "$C"; then
        ok "grupo sysfs $grupo intacto"
    else
        falha "grupo sysfs $grupo foi renomeado -- quebra o driver"
    fi
done

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: a renomeacao esta completa e nao apagou o que nao devia"
exit 0
```

```bash
cd /home/brunodobner/Claude/Nitrosense
chmod +x tests/test-renomeacao.sh
./tests/test-renomeacao.sh; echo "saida=$?"
```

Esperado: falha em "a desinstalacao nao trata: linuwu_sense", porque a
Task 3 apagou todas as ocorrências do `setup.sh` — inclusive as da
limpeza, que precisam voltar.

- [ ] **Step 2: Fazer a limpeza tratar o nome antigo**

Em `original/setup.sh`, dentro de `comprehensive_cleanup`, ao lado da
remoção do DKMS que já existe:

```bash
  # A renomeacao deixa um pacote DKMS orfao com o nome antigo, registrado
  # para todos os kernels com headers. Se ele ficar, dois modulos
  # disputam o mesmo dispositivo WMI e qual carrega e indeterminado.
  #
  # Roda antes do novo ser registrado, e por isso vive na limpeza.
  for antigo in linuwu_sense; do
    if dkms status 2> /dev/null | grep -q "^${antigo}"; then
      echo "Removendo o pacote DKMS antigo: ${antigo}"
      for v in $(dkms status 2> /dev/null | grep "^${antigo}" \
                 | sed 's|^[^/]*/\([^,]*\).*|\1|' | sort -u); do
        dkms remove -m "${antigo}" -v "${v}" --all 2> /dev/null || true
      done
    fi
    rm -rf "/usr/src/${antigo}-"*
    rm -f /etc/modules-load.d/${antigo}.conf
    if [ -f "${SYSTEMD_DIR}/${antigo}.service" ]; then
      systemctl disable --now "${antigo}.service" 2> /dev/null || true
      rm -f "${SYSTEMD_DIR}/${antigo}.service"
    fi
    modprobe -r "${antigo}" 2> /dev/null || true
    find /lib/modules -name "${antigo}.ko*" -delete 2> /dev/null || true
  done
```

- [ ] **Step 3: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense
bash -n original/setup.sh && ./tests/test-renomeacao.sh; echo "saida=$?"
```

Esperado: `OK: a renomeacao esta completa e nao apagou o que nao devia`,
saída `0`.

- [ ] **Step 4: Commit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add original/setup.sh tests/test-renomeacao.sh
git commit -m "fix: a desinstalacao remove o pacote DKMS antigo

Sem isto a renomeacao deixa um linuwu_sense orfao registrado para todos
os kernels com headers, e dois modulos passam a disputar o mesmo
dispositivo WMI -- qual carrega vira sorteio.

O teste novo tambem guarda o que NAO pode mudar: o credito aos autores
no MODULE_AUTHOR, e os grupos sysfs nitro_sense/predator_sense, que
nomeiam a familia do laptop e estao fixados no .c.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Os testes de shell acompanham

**Files:**
- Modify: `tests/test-install-drivers.sh`, `tests/test-dkms.sh`,
  `tests/test-uninstall.sh`, `tests/test-perfil-bateria.sh`,
  `tests/test-usb-charging.sh`, `tests/test-correcoes.sh`

- [ ] **Step 1: Ver o alcance**

```bash
cd /home/brunodobner/Claude/Nitrosense
grep -rc linuwu tests/*.sh | grep -v ':0'
```

- [ ] **Step 2: Trocar, preservando os caminhos de pasta**

```bash
cd /home/brunodobner/Claude/Nitrosense
sed -i 's/linuwu_sense/nexus_sense/g' tests/*.sh
sed -i 's|Linuwu-Sense|Linuwu-Sense|g' tests/*.sh   # a pasta nao muda
grep -rn "linuwu_sense" tests/*.sh || echo "nenhuma ocorrencia do modulo antigo"
```

> O `test-renomeacao.sh` cita `linuwu_sense` de propósito, ao verificar
> que a limpeza o trata. Se o `sed` o tiver alterado, restaure aquela
> linha — o teste tem de continuar procurando o **nome antigo**.

- [ ] **Step 3: Rodar a suíte de shell**

```bash
cd /home/brunodobner/Claude/Nitrosense && ./tests/run-all.sh
```

Esperado: nenhuma falha. Alguns testes que tocam o hardware vão **pular**
enquanto o módulo novo não estiver instalado — isso é o contrato de saída
`2`, e não é falha.

- [ ] **Step 4: Commit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add tests/
git commit -m "test: a suite de shell procura o modulo pelo nome novo

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: O lado Python, que quase não muda

O `MODULE_NAMES` já aceita os dois nomes desde o plano 1, justamente para
a GUI não quebrar no meio desta troca. Nada precisa mudar para funcionar
— o que muda é o comentário, que hoje descreve uma fase que terminou.

**Files:**
- Modify: `src/nexus_sense/sysfs.py`

- [ ] **Step 1: Atualizar o comentário**

Em `src/nexus_sense/sysfs.py`, o bloco acima de `MODULE_NAMES`:

```python
# Nos dois nomes. O modulo passou a se chamar nexus_sense na fase de
# renomeacao; o nome antigo fica aceito porque uma maquina que ainda nao
# rodou o instalador novo continua com o linuwu_sense carregado, e a
# janela precisa funcionar nela. Ver spec secao 12.
MODULE_NAMES = ("nexus_sense", "linuwu_sense")
```

- [ ] **Step 2: Confirmar que a suíte segue verde**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest -q
```

Esperado: `297 passed`. Nenhum teste muda — é exatamente o ponto de a
camada já aceitar os dois nomes.

- [ ] **Step 3: Commit**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add src/nexus_sense/sysfs.py
git commit -m "docs: MODULE_NAMES explica por que o nome antigo continua aceito

Nenhum teste muda, e esse e o ponto: a camada aceita os dois nomes desde
o plano 1, para a GUI nao quebrar no meio da troca.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: A troca nesta máquina

> Correção registrada em 2026-09-06: `comprehensive_cleanup` também remove
> o autostart e o hwdb do botão N. Após a troca do driver, restaure essas
> integrações antes de pedir reboot. Não repita a limpeza para repará-las.
> `install_drivers` deve rodar com `original/` como diretório corrente.
> Se o módulo antigo continuar em memória depois de seu arquivo ser removido,
> descarregue-o com `rmmod linuwu_sense` antes de carregar o novo.


A única tarefa que mexe no sistema. **A ordem não é negociável.**

Nesta máquina o driver está carregado e controlando o aparelho: descarregá-lo
faz os caminhos de sysfs sumirem, e a janela e o agente entram no estado
"driver ou fonte ausente" — que é previsto e testado. Eles se recuperam
sozinhos quando o módulo novo carregar.

- [ ] **Step 1: Registrar o estado de partida**

```bash
echo "perfil: $(cat /sys/devices/platform/acer-wmi/platform-profile/*/profile)"
echo "fonte:  $(cat /sys/class/power_supply/ACAD/online)"
lsmod | grep sense
dkms status
```

Anote o perfil: ele será conferido no fim.

- [ ] **Step 2: Parar o que usa o driver**

```bash
systemctl --user stop nexus-sense-agent.service
pkill -f "gui.app --tray-only" || true
```

> Parar o agente evita que ele escreva num sysfs que está prestes a sumir
> e registre um erro sem sentido no journal.

- [ ] **Step 3: Remover o antigo, pela função do instalador**

```bash
cd /home/brunodobner/Claude/Nitrosense
export SUDO_ASKPASS=~/.local/bin/claude-askpass
sed '/^# Check and elevate privileges if needed$/,$d' original/setup.sh > original/.funcs-temp.sh
sudo -A bash -c 'source original/.funcs-temp.sh; comprehensive_cleanup'
rm -f original/.funcs-temp.sh
```

- [ ] **Step 4: Confirmar que não sobrou nada do antigo**

```bash
dkms status
lsmod | grep -c sense
ls /usr/src/ | grep sense
ls /etc/modules-load.d/ | grep sense
find /lib/modules -name 'linuwu_sense.ko*' 2>/dev/null
```

Esperado: nenhuma linha `linuwu_sense` em lugar nenhum. **Se sobrar
alguma, pare e limpe antes de seguir** — é exatamente o cenário dos dois
módulos disputando.

- [ ] **Step 5: Instalar o novo**

```bash
cd /home/brunodobner/Claude/Nitrosense
sed '/^# Check and elevate privileges if needed$/,$d' original/setup.sh > original/.funcs-temp.sh
sudo -A bash -c 'source original/.funcs-temp.sh; install_drivers'
rm -f original/.funcs-temp.sh
dkms status
```

Esperado: `nexus_sense/25.701, <kernel>: installed`.

- [ ] **Step 6: Carregar e conferir o aparelho**

```bash
sudo -A modprobe nexus_sense
lsmod | grep nexus_sense
journalctl -k -n 12 --no-pager | grep -i "nexus\|Detected model"
ls /sys/devices/platform/acer-wmi/nitro_sense/
```

Esperado: `Initializing Nexus Sense - Version 25.701`, `Detected model
type: Nitro ANV15-52`, e os seis atributos de volta em `nitro_sense/`.

- [ ] **Step 7: Conferir a permissão de grupo**

```bash
ls -l /sys/devices/platform/acer-wmi/nitro_sense/fan_speed
ls -l /sys/devices/platform/acer-wmi/platform-profile/*/profile
```

Esperado: `664 root:nexus_sense` nos dois. A regra udev dispara no
`add|change` do módulo novo — se sair `644 root:root`, force com
`sudo -A udevadm trigger --subsystem-match=platform --action=change`.

- [ ] **Step 8: Reerguer o app e o agente**

```bash
systemctl --user start nexus-sense-agent.service
systemctl --user is-active nexus-sense-agent.service
PYTHONPATH=/usr/lib/nexus-sense python3 -c "
from nexus_sense.sysfs import Sysfs
from nexus_sense.device import read_state, read_system
e = read_state(Sysfs('/')); s = read_system(Sysfs('/'))
print('modulo carregado:', e.module_loaded, '| driver:', s.driver_version)
print('perfil:', e.profile, '| graveis:', len(e.writable))
"
(setsid /usr/bin/nexus-sense --tray-only &) ; sleep 4
busctl --user list | grep StatusNotifierItem | grep -v arch-update
```

Esperado: `module_loaded: True`, cinco graváveis, e o item na bandeja.

Antes de encerrar o passo 8, restaure e confira as integrações removidas:

```bash
sudo -A install -m 644 packaging/nexus-sense-autostart.desktop /etc/xdg/autostart/nexus-sense-autostart.desktop
sed '/^# Check and elevate privileges if needed$/,$d' original/setup.sh > original/.funcs-temp.sh
sudo -A bash -c 'source original/.funcs-temp.sh; install_nitro_key_hwdb'
rm -f original/.funcs-temp.sh
```

- [ ] **Step 9: Commit do que a máquina ensinou**

Se algum passo exigiu correção no `setup.sh`, commite-a agora, com a
descrição do que a máquina mostrou. Se nada exigiu, pule este passo.

---

### Task 8: Verificação depois do boot, e registro

O que só um boot prova: que o módulo novo carrega sozinho pelo
`modules-load.d`, e que a regra udev aplica o grupo na ordem certa.

- [ ] **Step 1: Pedir o reboot**

Este passo depende de gesto humano. Peça o reinício e espere.

- [ ] **Step 2: Conferir o boot**

```bash
lsmod | grep nexus_sense
journalctl -k -b --no-pager | grep -i "nexus sense\|Detected model\|Supported thermal"
ls -l /sys/devices/platform/acer-wmi/nitro_sense/fan_speed
systemctl --user is-active nexus-sense-agent.service
ps -eo pid,etimes,cmd | grep "gui.app --tray-only" | grep -v grep
```

Esperado: módulo carregado sem intervenção, banner com o nome novo,
`664 root:nexus_sense`, agente ativo e a bandeja de pé pelo autostart.

- [ ] **Step 3: Rodar as duas suítes**

```bash
cd /home/brunodobner/Claude/Nitrosense
python3 -m pytest -q
./tests/run-all.sh
```

Esperado: pytest verde; na suíte de shell, os testes que pulavam por
falta de hardware agora devem **passar**, porque o módulo está no lugar.

- [ ] **Step 4: Atualizar o `ESTADO.md`**

Marque a renomeação como concluída no roteiro, mova-a para "Concluído"
com o resumo, e atualize "O que está instalado na máquina" — os caminhos
do DKMS, do `modules-load.d` e da unit mudaram de nome.

Registre também, em `docs/ARMADILHAS.md`, a armadilha que esta fase
carregava: **renomear um módulo DKMS sem remover o pacote antigo deixa
dois registrados para os mesmos kernels**, e qual carrega é
indeterminado. Com o comando que acusa:

```bash
dkms status | grep sense
```

- [ ] **Step 5: Commit final**

```bash
cd /home/brunodobner/Claude/Nitrosense
git add -A
git commit -m "docs: renomeacao concluida e verificada apos boot

O modulo carrega sozinho como nexus_sense, a regra udev aplica o grupo
na ordem certa, e o agente e a bandeja sobem sem intervencao.

Fica registrada em ARMADILHAS.md a armadilha desta fase: renomear um
pacote DKMS sem remover o antigo deixa dois registrados para os mesmos
kernels, e qual carrega e indeterminado.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## O que este plano entrega

- o módulo do kernel chamado `nexus_sense`, com o `.ko`, o pacote DKMS, a
  unit e o `modules-load.d` acompanhando;
- uma desinstalação que remove o pacote antigo **antes** de o novo entrar,
  fechando a única porta para dois módulos disputando o dispositivo;
- um teste que guarda o que **não** pode mudar: o crédito aos autores
  originais e os grupos sysfs do firmware;
- a GUI e o agente funcionando durante e depois da troca, sem mudança de
  código — porque a camada de acesso já aceitava os dois nomes.

## O que fica de fora, e por quê

- **A pasta `original/Linuwu-Sense/`.** É o diretório do upstream;
  renomeá-la faria toda release nova conflitar na extração.
- **Os grupos sysfs `nitro_sense` e `predator_sense`.** Nomeiam a família
  do laptop, estão fixados no `.c` e são lidos pelo firmware.
- **`/etc/predator_state`.** Escrito pelo próprio driver, com nome vindo
  do firmware Acer.
- **`MODULE_AUTHOR` e os comentários de linhagem.** São crédito e
  história, não marca do fork.

## Riscos que este plano carrega

| risco | onde aparece | saída |
|---|---|---|
| o módulo novo não compila | Task 1, passo 5 | pare: nada foi removido e a máquina segue com o driver antigo |
| sobra pacote DKMS antigo | Task 7, passo 4 | o passo confere explicitamente; se sobrar, limpe antes de seguir |
| a regra udev não dispara para o módulo novo | Task 7, passo 7 | `udevadm trigger` força; se persistir, é armadilha nova e vai para `ARMADILHAS.md` |
| a máquina fica sem driver entre os passos 3 e 6 | Task 7 | previsto: a janela e o agente têm estado "driver ausente" testado, e se recuperam |
| o `sed` do instalador quebra o caminho da pasta | Task 3, passo 3 | um passo próprio confere e restaura |
