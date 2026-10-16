# Nexus Sense

Controle e monitoramento para o **Acer Nitro ANV15-52** no Linux: perfis
térmicos, uma curva própria para as ventoinhas, limitador de bateria e o botão
Nitro, numa janela e numa bandeja — sem daemon, sem socket e **sem processo
root permanente**.

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
| `docs/` | interface, estado, planos, armadilhas e histórico | ❌ idem |

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
- instala o guarda da ventoinha, que devolve o automático se o agente parar
- reinicia o agente e a bandeja que estiverem rodando, para que subam com o
  código novo; o que estava parado fica parado
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
| `nexus-sense-agent` | serviço de usuário: acompanha a fonte de energia, mantém o modo máximo e comanda a curva da ventoinha |

Não há daemon, não há socket e **não há processo root permanente** — nem
sequer um helper sob demanda. A escrita diária passa por permissão de
grupo em `sysfs`, aplicada por uma regra udev.

As preferências moram em `~/.config/nexus-sense/config.toml`. O agente o relê
a cada 2 s, e quem grava preserva as chaves que não conhece: uma versão
antiga ainda no ar não apaga um campo novo.

## A ventoinha

A janela (aba **Desempenho**) tem três modos; a bandeja, os dois primeiros:

| modo | quem decide |
|---|---|
| **Automático** | na tomada, a **curva do Nexus Sense**, pela temperatura; na bateria e nos perfis silencioso e econômico, o firmware |
| **Máximo** | as duas ventoinhas a 100%, o comportamento de máximo do firmware |
| **Manual** | você, para cada ventoinha; a curva espera o Automático voltar |

**A curva**, desde 2026-10-16, é o Automático deste modelo. Cada ventoinha
segue a própria temperatura, como o EC a informa:

| CPU pelo EC | ventoinha da CPU | GPU pelo EC | ventoinha da GPU |
|---|---|---|---|
| até 50 °C | 25% · 2.300 rpm | até 55 °C | 24% · 2.000 rpm |
| 60 °C | 35% · 3.000 rpm | 65 °C | 37% · 3.000 rpm |
| 70 °C | 50% · 4.200 rpm | 70 °C | 53% · 4.200 rpm |
| 80 °C | 73% · 5.800 rpm | 76 °C | 82% · 6.000 rpm |
| 88 °C ou mais | 99% · 7.450 rpm | 80 °C ou mais | 99% · 6.980 rpm |

- Entre dois pontos, a porcentagem anda em linha reta. As rotações são as do
  mapa medido em repouso.
- Vale a temperatura dos últimos 10 s, e não a do instante: um pico curto não
  faz a ventoinha subir e descer.
- Sobe na hora. Desce só depois de a temperatura cair 3 °C, e no máximo 4
  pontos a cada 2 s: de 99% a 35% em ~30 s.
- Com a GPU a 76 °C ou mais, as duas ficam no mínimo em 81% e 82%: o que o
  automático do firmware gira com um jogo aberto e o modo máximo ligado.

**O que a protege.** O firmware obedece a um manual até o fim: com a ventoinha
no piso e um jogo aberto, a GPU subiu um grau por segundo e bateu no limite em
sete; noutra medida, o EC não tomou a ventoinha de volta em dez minutos a
94 °C (2026-10-10). Por isso:

- **a rede térmica** do agente devolve o automático a um manual baixo com a
  GPU quente — inclusive o da janela;
- **o guarda** (`ExecStopPost` da unit, com `WatchdogSec`) devolve o
  automático se o agente morrer ou travar, mas só o manual que o próprio
  agente registrou ter escrito. Medido: 105 ms depois de um `kill -9`, 5 s com
  o agente travado. No desligamento medido ele chegou antes de o driver
  gravar o estado, e a partida voltou no automático — o que se viu, não uma
  ordem garantida;
- **na suspensão**, o agente avisa o systemd antes de dormir, e o watchdog
  não o mata ao acordar. Ao acordar de S3 o firmware larga o manual e troca o
  perfil térmico para `balanced`, com o driver ainda dizendo o valor de antes:
  o agente devolve o perfil e reescreve o manual.

**Para voltar ao automático do firmware**, ponha `fan_curve = false` no
`config.toml`; `fan_curve = true` a liga de volta. Sem a linha, vale o padrão:
ligada, porque as tabelas foram medidas neste notebook. O desenho, as medidas
e o que cada ensaio respondeu estão em [docs/plano-curva.md](docs/plano-curva.md),
seção 11.

## Verificar

```bash
python3 -m pytest -q        # inclui DBus privado; requer dbus-daemon/dbus-run-session
./tests/run-all.sh          # os que rodam sem privilégio
sudo ./tests/run-all.sh     # inclui o de DKMS
```

Distingue quatro desfechos: passou, pulou por falta de root, **alvo ausente**
(código 3) e falhou. O terceiro existe porque teste que não acha o alvo
aprova por vácuo — ver armadilha 14.

`tests/hardware/` guarda os ensaios térmicos, que **escrevem na ventoinha de
verdade** e alguns esquentam a máquina de propósito
(`tests/hardware/ensaio-termico.sh`). Não fazem parte da suíte: quem os roda
é uma pessoa, com o plano em mãos. Enquanto rodam, pausam a curva do agente e
a devolvem no fim. A suíte prova as proteções deles numa árvore de mentira, e
`tests/hardware/mutacoes-ensaio.py` prova que esses testes reprovam uma
proteção estragada.

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
| velocidade das ventoinhas | ✅ com piso: de 20% para baixo o firmware gira o mesmo, ~2000 rpm, e não devolve o automático sozinho — quem devolve, com um jogo aberto, é o agente ([docs/plano-termico.md](docs/plano-termico.md)). `100,100` não é manual a 100%, é o máximo do firmware. Ao acordar de S3 o firmware larga o manual sem avisar ([docs/plano-curva.md](docs/plano-curva.md)) |
| limitador de bateria | ✅ |
| calibração de bateria | ✅ |
| timeout do backlight | ✅ |
| carregamento USB desligado | ⚠️ exposto, mas o firmware devolve valor que a tabela do driver não cobre |
| `lcd_override` | ❌ firmware responde `0xFF` — função não implementada |
| teclado RGB por zonas | ❌ o modelo tem LED de cor única |
