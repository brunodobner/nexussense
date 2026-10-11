# Nexus Sense

Controle e monitoramento para o **Acer Nitro ANV15-52** no Linux: perfis
térmicos, ventoinhas, limitador de bateria e o botão Nitro, numa janela e numa
bandeja — sem daemon, sem socket e **sem processo root permanente**.

O módulo sobrevive a atualizações de kernel via DKMS, e o instalador funciona
em Arch, Debian, Fedora e openSUSE.

**Este driver atende um modelo só.** Em 2026-09-11 a tabela de quirks herdada
foi podada de 32 entradas DMI para **uma**, e de 14 quirks para dois. Num Acer
diferente o driver não vincula e nenhum grupo `sysfs` é criado.

A poda foi guiada por medição, não por leitura de código: as capabilities vêm
de **três** fontes, e a tabela de quirks é só uma delas — o `rfkill` do wifi e
do bluetooth vem do descritor `AA` do firmware, em tempo de execução. Cortar
pela tabela sem medir teria arrancado o controle do wifi sem que nada
acusasse. O bitmask antes e depois é idêntico (`0x2c26`). Ver
[docs/decisoes.md](docs/decisoes.md), seção 6.

```bash
sudo ./setup.sh
```

---

## Layout

| | o que é | vai junto numa instalação |
|---|---|---|
| `setup.sh` | o instalador — único executável na raiz | ✅ |
| `driver/` | o módulo do kernel (`nexus_sense`) | ✅ |
| `src/` | o Nexus Sense: janela, bandeja e agente | ✅ |
| `packaging/` | ícones, units, regra udev, lançadores e scripts | ✅ |
| `tests/` | suíte de verificação do port | ❌ ferramenta de manutenção |
| `docs/` | interface, estado, armadilhas e histórico | ❌ idem |

O instalador precisa de `setup.sh`, `driver/`, `src/` e `packaging/`. Copiar os
quatro para outra máquina e rodar `setup.sh` funciona — de qualquer diretório,
porque todo caminho deriva da posição do próprio script. Os testes dependem do
layout do repositório e não fazem sentido soltos.

Dentro de `packaging/`, cada tipo de artefato tem seu lugar: `desktop/` para os
lançadores, `systemd/` para as duas units, `udev/` para a regra de permissão,
`scripts/` para os helpers e `icons/` para o conjunto gerado.

---

## Instalar

```bash
sudo ./setup.sh
```

O menu traz instalar, instalar sem drivers, desinstalar, reinstalar e status.
A instalação completa:

- compila e registra o módulo no **DKMS**, para todos os kernels com headers
- instala dependências conforme a distro (`pacman`/`apt`/`dnf`/`zypper`)
- neutraliza o `acer_wmi`, que disputa os mesmos GUIDs WMI
- instala o Nexus Sense: a janela, a bandeja e o agente de energia
- mapeia o botão Nitro para um keycode vinculável e cria o atalho no KDE

A GUI usa PySide6 e `dbus-python` (no Arch/CachyOS: `pyside6` e
`python-dbus`). O extra Python `gui` declara essas dependências. A bandeja
com scroll requer Qt com dispatcher GLib; sem ele, usa `QSystemTrayIcon`.
O instalador também obtém o `power-profiles-daemon`, usado pelo modo
**Desempenho máximo**, e confirma as dependências antes de copiar o app.

## Componentes

| componente | o que é |
|---|---|
| `nexus_sense` | o driver, um módulo do kernel |
| `nexus-sense` | a interface: janela e bandeja, PySide6 |
| `nexus-sense-agent` | serviço de usuário que acompanha a fonte e mantém o modo máximo |

Não há daemon, não há socket e **não há processo root permanente** — nem
sequer um helper sob demanda. A escrita diária passa por permissão de
grupo em `sysfs`, aplicada por uma regra udev.

## Verificar

```bash
python3 -m pytest -q        # inclui DBus privado; requer dbus-daemon/dbus-run-session
./tests/run-all.sh          # os que rodam sem privilégio
sudo ./tests/run-all.sh     # inclui o de DKMS
```

Distingue quatro desfechos: passou, pulou por falta de root, **alvo ausente**
(código 3) e falhou. O terceiro existe porque teste que não acha o alvo
aprova por vácuo — ver armadilha 14.

---

## Atualizar para uma nova release do upstream

O procedimento que dá sentido ao desenho do repositório mora em
a seção [Licença e origem](#licença-e-origem), que registra de onde cada
arquivo veio. **Este projeto não rastreia mais o upstream:** partiu daquela
base e seguiu sozinho.

Antes de mexer no driver, no build ou no instalador, leia
[docs/armadilhas.md](docs/armadilhas.md): entradas com sintoma, causa e comando
de verificação. Várias custaram horas.

---

## Licença e origem

**Nexus Sense** — Copyright © 2026 Bruno Dobner <contato@brunodobner.com>,
sob **GPL-3.0-or-later**.

A janela, a bandeja e o agente em `src/` foram escritos do zero para este
projeto. O driver em `driver/` é **trabalho derivado**, e a licença exige que
a linhagem fique registrada — está no cabeçalho de
[`driver/src/nexus_sense.c`](driver/src/nexus_sense.c) e o texto da GPL em
[`driver/LICENSE`](driver/LICENSE):

| origem | quem |
|---|---|
| `acer_wmi` / `acer_acpi`, do kernel Linux | Carlos Corbacho, E. M. Smith |
| [Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense) (fev/2025) | 0x7375646F |
| [Div Acer Manager Max](https://github.com/PXDiv/Div-Acer-Manager-Max) (jun/2025) | Div Sharp |

O ponto de partida foi a release **1.0.2-h1** do DAMX, commit `1f88341` — não
confundir com a `1.0.2`, que é o commit `c1a4292`; as duas distribuem tarballs
de mesmo nome, então a release se identifica pelo commit, nunca pelo número.
Daí para cá o driver divergiu em ~200 linhas, o instalador foi praticamente
reescrito, e a GUI .NET original foi substituída por uma em PySide6.

**Onde cada arquivo do DAMX foi parar:**

| na release 1.0.2-h1 do DAMX | aqui | quanto mudou |
|---|---|---|
| `original/setup.sh` | `setup.sh` | 632+/147− — praticamente reescrito |
| `original/Linuwu-Sense/src/linuwu_sense.c` | `driver/src/nexus_sense.c` | ~200 linhas |
| `original/Linuwu-Sense/Makefile` | `driver/Makefile` | 66+/74− |
| `original/Linuwu-Sense/linuwu_sense.service` | `packaging/systemd/nexus_sense.service` | reescrita |
| `original/nitro-key-detection.sh` | — | removido: era um serviço root lendo o teclado inteiro; o botão abre o app por hwdb e atalho do desktop |
| `original/Linuwu-Sense/LICENSE` | `driver/LICENSE` | intocado |
| — | `driver/dkms.conf` | inteiramente nosso |
| — | `src/` (janela, bandeja, agente) | escrito do zero |

`dkms.conf` não existe no DAMX: o DKMS foi acrescentado aqui. Os binários .NET
e o `release.txt` que a release trazia não são distribuídos por este projeto.

**Este projeto não rastreia mais o upstream.** Ele partiu daquela base em
setembro de 2026 e seguiu sozinho; não há procedimento de merge, e releases
novas do DAMX não são incorporadas.

---

## Histórico

O raciocínio por trás de cada decisão está em
[docs/decisoes.md](docs/decisoes.md), e as armadilhas que custaram tempo em
[docs/armadilhas.md](docs/armadilhas.md).

A pasta `versaopessoal/`, fork local de 2025 que originou este trabalho, foi
**removida do histórico** no expurgo de 2026-09-05, depois que suas
adaptações já haviam sido portadas para o driver e o instalador. Era obsoleta e
respondia por 112 MB dos 142 MB que o repositório tinha.

Os binários do daemon 0.4.x e da GUI de julho/2025 saíram junto e não são
mais recuperáveis por aqui.

---

## O que o hardware suporta

Medido neste ANV15-52, não presumido:

| controle | estado |
|---|---|
| perfis térmicos | ✅ `low-power quiet balanced balanced-performance` |
| velocidade das ventoinhas | ✅ com piso: de 20% para baixo o firmware gira o mesmo, ~2000 rpm, e não devolve o automático sozinho — quem devolve, com um jogo aberto, é o agente ([docs/plano-termico.md](docs/plano-termico.md)) |
| limitador de bateria | ✅ |
| calibração de bateria | ✅ |
| timeout do backlight | ✅ |
| carregamento USB desligado | ⚠️ exposto, mas o firmware devolve valor que a tabela do driver não cobre |
| `lcd_override` | ❌ firmware responde `0xFF` — função não implementada |
| teclado RGB por zonas | ❌ o modelo tem LED de cor única |
