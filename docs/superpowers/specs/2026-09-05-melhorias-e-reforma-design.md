# Melhorias, otimizações e reforma estrutural do fork DAMX

**Data:** 2026-09-05
**Estado:** aprovado para implementação
**Base:** `1f88341` = tag upstream **`1.0.2-h1`** (não `1.0.2`, ver §7)

---

## 1. Problema

O port do ANV15-52 (2026-09-04) entregou um fork funcional. Esta spec trata
do que a varredura seguinte encontrou: dois defeitos capazes de derrubar o
kernel, um instalador que continua após erro sem avisar, um serviço que lê
todas as teclas do teclado como root, e 142 MB de `.git` que crescem ~120 MB
a cada release do upstream.

### O que foi medido, não suposto

Antes de propor qualquer coisa, o estado de partida foi verificado:

```
suíte de testes         9/9 verdes (com sudo -A; 8/9 sem root)
build W=1 sob Clang     zero warnings
DKMS                    compila nos dois kernels (Arch/GCC e CachyOS/Clang)
ruído no journal        26 linhas neste boot
working tree            limpa
```

Duas hipóteses iniciais **foram refutadas pela medição** e por isso não
geraram trabalho: não havia warnings de compilação a corrigir, e o volume
de `pr_info` no journal é modesto, não o dilúvio que a contagem de 60
chamadas sugeria.

### Divergência atual por arquivo

O número que orienta todas as decisões de estrutura desta spec:

```
setup.sh          1159 linhas  | +408  -45  | ~35% já divergente
linuwu_sense.c    5117 linhas  | +153  -22  | ~3%  já divergente
Makefile            75 linhas  | +60   -72  | ~80% já divergente
```

Instalador e build **já perderam** a propriedade de dar merge limpo com o
upstream. O driver não: 153 linhas em 5117, e é nele que mora o valor das
releases futuras (modelo novo, função WMI nova, adaptação a mudança de API
do kernel).

---

## 2. Decisão que orienta tudo

O projeto assume divergência do upstream **por camada**:

| camada | postura | consequência na próxima release |
|---|---|---|
| driver (`linuwu_sense.c`) | **enxugado para o ANV15-52**, ver §4.4 | leitura manual do diff, como o instalador |
| instalador e build | este repositório é o principal | ler o diff do upstream à procura de ideias, trabalho manual |
| binários | não versionados, baixados à mão | substituir os arquivos e atualizar o manifesto |

Para instalador e build isto não é mudança de rumo: é o reconhecimento de um
estado que os números acima já descrevem.

**Para o driver, é.** Ele está hoje em 3% de divergência e o enxugamento o
leva a ~60%. A propriedade de reaplicar patches mecanicamente **acaba**, e
puxar melhoria do upstream vira comparação manual de dois arquivos de 5000
linhas.

Isto foi levantado como objeção e decidido assim mesmo, com conhecimento do
custo: **este projeto existe para um notebook só**, e o valor de ler um
driver que descreve o hardware da máquina supera o de acompanhar o upstream
de perto.

---

## 3. Ordem das operações

O expurgo do histórico vem **primeiro**, antes de qualquer código novo.

`git-filter-repo` reescreve todo commit existente. Melhorias feitas antes
seriam reescritas junto, deixando dois conjuntos de hashes mortos em vez de
um. Purgando primeiro, todo trabalho seguinte nasce sobre o histórico
definitivo.

```
1. cp -a .git .git-backup                  rede de segurança da operação
2. copiar os binários para fora do repo    ver §6
3. instalar git-filter-repo
4. expurgar os 2 binarios de original/ e a pasta versaopessoal/ inteira
5. recriar a tag como upstream/1.0.2-h1
6. devolver os binários, agora ignorados
7. rodar a suíte -- tem de continuar 9/9
8. só então começar o código
```

O passo 1 é rede de segurança da operação destrutiva, não preservação dos
binários de julho/2025 — esses foram descartados por decisão explícita. A
cópia `.git-backup` é apagada após confirmação do resultado.

### O enxugamento vai no fim

Simetricamente, o corte do driver (§4.4) é a **última** fase do trabalho, não
a primeira. As fases, em ordem:

```
A. expurgo do histórico          (§3)   -- antes de todo o resto
B. correções do driver           (§4.1-4.3)
C. reforma do instalador         (§5)
D. binários e manifesto          (§6)
E. testes, shellcheck e CI       (§8)
F. enxugamento do driver         (§4.4) -- por último, com CI ja verde
G. documentação                  (§9)
```

A razão de F vir depois de E: o enxugamento é a mudança com maior chance de
quebrar algo em silêncio, e chegar nele com a suíte e o CI já funcionando
significa ter um detector pronto antes de mexer.

---

## 4. Driver

O driver recebe dois tipos de trabalho, deliberadamente separados no tempo:

- **§4.1 a §4.3 — cirúrgico.** Três commits pequenos, nenhuma
  reestruturação. Vêm **antes** do enxugamento (fase B), enquanto o arquivo
  ainda é o do upstream, para que continuem legíveis e reaplicáveis
  isoladamente.
- **§4.4 — enxugamento.** A remoção de tudo que não é deste modelo. Vem por
  último (fase F), depois de o CI estar verde.

### 4.1 `filp_open` devolve `ERR_PTR`, nunca `NULL`

`acer_predator_state_save()` (~3862) e `four_zone_kb_state_save()` (~4489):

```c
file = filp_open(STATE_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
if (!file)                    /* ERRADO: erro chega como ERR_PTR */
```

`/etc` read-only, ou qualquer falha de abertura, passa reto e entrega um
`ERR_PTR` ao `kernel_write` → oops no desligamento, exatamente quando o
estado deveria ser salvo. Os caminhos de *load* já usam `IS_ERR()`
corretamente; a assimetria é a prova de que é descuido.

No mesmo ramo, o erro de escrita chama `filp_close()` e cai no
`filp_close()` incondicional logo abaixo: **fecha duas vezes**.

Correção: `IS_ERR()` nos dois pontos, e um único `filp_close`.

### 4.2 `sysfs_emit()` no lugar de `sprintf()`

Dez handlers `show()` usam `sprintf(buf, ...)`. A convenção do kernel é
`sysfs_emit()`, que conhece o `PAGE_SIZE` do buffer de sysfs. Substituição
mecânica, sem mudança de comportamento observável.

### 4.3 `pr_debug` nos handlers de leitura

Quatro `pr_info` disparam a cada leitura de atributo. Medido: 26 linhas
neste boot — **higiene, não urgência**. Vai por último e é o primeiro item
a ser descartado se atrapalhar.

### 4.4 Enxugamento para o ANV15-52

Este projeto atende **um** notebook. Tudo que não é deste modelo sai do
driver.

#### O critério NÃO é a tabela de quirks

Uma primeira versão desta seção definia o corte pelo que `set_quirks()`
liga: `quirk_acer_nitro` declara só `.nitro_sense = 1`, o que dá três
capabilities, e as outras doze seriam código morto.

**A medição refutou isso, e o erro teria sido grave.** Capabilities vêm de
**quatro** fontes, não de uma:

```
473-499    set_quirks()                 a tabela DMI
1244-1304  deteccao WMI em tempo real
1641-1694  descritor "AA" de hotkeys    o FIRMWARE declara wireless/bt/3g
4973-5011  acer_wmi_init()
5022       force_caps (parametro)
```

Este notebook tem `rfkill/acer-wireless` e `rfkill/acer-bluetooth`
registrados **apesar de o quirk não os ligar** — quem os liga é o descritor
AA do firmware, em tempo de execução. Cortar pelo critério original teria
arrancado o rfkill do wifi e do bluetooth da máquina.

Registrado como Armadilha 18 (§9).

#### O inventário medido

O que está vivo neste ANV15-52, verificado no sistema em execução:

| subsistema | estado | evidência |
|---|---|---|
| `PLATFORM_PROFILE` | **vivo** | 4 perfis em `platform_profile_choices` |
| `FAN_SPEED_READ` | **vivo** | hwmon `fan1/fan2` = 2077/1862 rpm, `temp1/2/3` |
| `NITRO_SENSE` | **vivo** | 6 atributos em `nitro_sense/` |
| `WIRELESS` | **vivo** | `rfkill/acer-wireless`, input "Acer Wireless Radio Control" |
| `BLUETOOTH` | **vivo** | `rfkill/acer-bluetooth` |
| hotkeys WMI | **vivo** | input "Acer WMI hotkeys" |
| `THREEG` | ausente | nenhum rfkill `wwan` |
| `MAILLED` | ausente | nenhum LED acer em `/sys/class/leds` |
| `BRIGHTNESS` | ausente | só `intel_backlight`, que é do i915 |
| `KBD_DOCK` | ausente | nenhum `SW_TABLET_MODE` |
| `TURBO_*` | ausente | sem atributo `turbo` |
| `four_zone_kb` | ausente | sem diretório `four_zoned_kb` |
| `PREDATOR_SENSE` | ausente | sem diretório `predator_sense` |
| `NITRO_SENSE_V4` | ausente | idem |

#### Passo zero: medir o bitmask antes de remover qualquer coisa

O driver **nunca imprime** `interface->capability`. Sem esse número, o
inventário acima é inferência a partir de efeitos observáveis — bom, mas não
definitivo: uma capability pode estar ligada sem manifestar nada visível.

Então a fase F começa por instrumentação temporária:

```c
/* TEMPORARIO -- remover apos a medicao */
pr_info("capability bitmask = 0x%08x\n", interface->capability);
```

ao final do probe. Compilar, `rmmod`/`modprobe`, ler o journal, **anotar o
número na spec**, reverter a instrumentação. Só depois disso começa qualquer
remoção, e o bitmask medido — não esta tabela — é a autoridade.

#### O que sai

Sujeito à confirmação do bitmask acima:

1. **Tabelas** — 38 das 39 entradas DMI e 13 dos 14 quirks. O driver passa a
   carregar apenas no ANV15-52.
2. **Subsistemas ausentes** — RGB de quatro zonas, turbo, mailled, threeg,
   kbd_dock, backlight, e os grupos `predator_sense` e `nitro_sense_v4`.
3. **Parâmetros de módulo** que reintroduziriam o removido: `enable_all`,
   `force_caps`, `force_series`, `predator_v4`, `nitro_v4`.
4. **`predator_boot_animation_sound_*()`** — vive no grupo Predator e nunca
   foi exposto neste modelo. Sai com o resto, o que também encerra a questão
   da decodificação por valor cru `0x100`: sem código, sem pendência.

#### O que NÃO sai, apesar de o quirk não ligar

**`WIRELESS`, `BLUETOOTH`, o descritor AA de hotkeys e o input device.**
Estão vivos nesta máquina. Remover quebraria o rfkill do wifi e do
bluetooth — e é exatamente o erro que o critério original teria cometido.

#### Como fazer isso sem quebrar o que funciona

Esta é a mudança mais arriscada da spec, e a mitigação é a ordem:

- **Vai por último.** Só começa depois que driver, instalador, testes e CI
  estiverem verdes. Assim, se algo quebrar, a causa é inequívoca.
- **Uma tag antes** (`pre-enxugamento`), para reverter ou bissectar.
- **Um commit por subsistema**, nunca um commit grande. Depois de cada um:
  recompilar, `rmmod`/`modprobe`, e conferir o efeito.
- **A verificação é sempre a mesma**, e é de comportamento, não de leitura:

```bash
N=/sys/devices/platform/acer-wmi/nitro_sense
ls $N                                             # os 6 atributos
cat $N/usb_charging                               # dentro de 0/10/20/30
cat $N/fan_speed
cat /sys/firmware/acpi/platform_profile_choices    # os 4 perfis
grep -c 'acer-wireless\|acer-bluetooth' \
  /sys/class/rfkill/*/name                         # tem de continuar 2
grep -c 'Acer WMI hotkeys' /proc/bus/input/devices # tem de continuar 1
cat /sys/devices/platform/acer-wmi/hwmon/hwmon*/fan1_input  # rpm plausivel
```

As três últimas linhas existem por causa do erro descrito acima: sem elas,
arrancar o rfkill passaria despercebido — os seis atributos continuariam
lá, e o wifi teria perdido o controle por hardware em silêncio.

Qualquer commit que altere essa saída é revertido, não consertado.

---

## 5. Instalador

### 5.1 Estrutura

`setup.sh` vira despachante fino sobre módulos:

```
original/setup.sh          menu, flags, orquestração
original/lib/comum.sh      cores, log, detecção de distro e de usuário
original/lib/drivers.sh    DKMS, headers, toolchain, acer_wmi
original/lib/daemon.sh     daemon + unit
original/lib/gui.sh        GUI, ícone, .desktop
original/lib/tecla.sh      hwdb + atalho do KDE
original/lib/remover.sh    desinstalação
original/lib/verificar.sh  presença e sha256 dos binários (§6)
```

Cada módulo tem uma responsabilidade, é lido isoladamente e pode ser testado
sozinho. `original/` continua autossuficiente: `lib/` viaja junto.

### 5.2 Erro deixa de ser silencioso

`set -euo pipefail` e um `trap ERR` que reporta arquivo e linha. Hoje um
`cp` ou `mkdir` que falha não interrompe nada — a instalação segue e
reporta sucesso.

Ressalva de implementação: `set -e` muda o comportamento de funções que
hoje dependem de retorno não-zero (`systemctl is-active`, `grep` de teste,
`dkms status`). Cada uma precisa de `|| true` explícito ou de ser
reescrita como condicional. É a parte mais delicada da reforma e exige
rodar a suíte a cada módulo convertido.

### 5.3 Modo não-interativo

Flags `--install`, `--sem-drivers`, `--remover`, `--reinstalar`,
`--status`, `--sim`, `--help`. Sem argumentos, cai no menu atual — quem já
usa não percebe diferença.

Isto não é conveniência: é o que **destrava a Seção 8**. Sem modo
não-interativo, nenhum teste consegue executar o instalador.

### 5.4 Tecla N: keylogger sai, só KDE fica

`lib/tecla.sh` cobre **apenas o KDE**, que é o desktop desta máquina. O
caminho GNOME (`gsettings custom-keybindings`) foi considerado e
**descartado**: este projeto atende um notebook, esse notebook roda KDE, e
seria código que eu não teria como verificar — não há GNOME aqui.

A regra dos dois lados continua valendo no KDE: na instalação, vínculo
existente do usuário é preservado; na remoção, só apaga se o valor for
exatamente o que o instalador escreveu (`Launch (1)`).

Saem do projeto:

- `original/nitro-key-detection.sh`
- a unit `nitro-key-detection.service`
- toda a captura por `evtest` em `configure_nitro_button()`
- a dependência de `evtest`

Motivo: o serviço roda como root e lê **todas** as teclas do teclado,
senhas incluídas, para detectar um botão. A regra hwdb faz o mesmo trabalho
sem processo nenhum.

Quem usar outro desktop recebe as instruções manuais que o instalador já
imprime hoje — mesmo comportamento que já havia para não-KDE.

`lib/remover.sh` **continua removendo** o serviço antigo, para quem já o
tem instalado de uma versão anterior.

Isto também elimina, por remoção, dois defeitos herdados: o
`pgrep -f "/opt/damx/gui/DivAcerManagerMax"` (Armadilha 10, ainda presente
no script publicado) e o `sudo -u` dentro de uma unit que já roda como root.

### 5.5 `is_llvm_kernel()` decide pelo kernel errado

Hoje a função olha `uname -r` para decidir se instala clang — a Armadilha 2
em outra roupa. Numa máquina com kernel GCC em execução e um kernel Clang
instalado ao lado, o clang não é instalado e o build DKMS daquele kernel
falha.

Correção: varrer todos os kernels com headers e instalar clang se
**qualquer um** deles for Clang. As famílias `dnf` e `zypper`, que hoje não
tratam o caso, passam a tratar.

---

## 6. Binários — **provisório**

> **Esta seção tem prazo de validade.** Decidido em 2026-09-05: GUI e daemon
> serão substituídos por fonte própria, num projeto separado que vem logo
> depois da fase A (ver §12). Quando isso acontecer, os 121 MB de binários
> deixam de existir e a §6 inteira perde o objeto.
>
> Ela permanece na spec porque a fase A precisa preservar os binários que
> existem hoje (§6.1) — isso vale independentemente do que vier depois. O
> manifesto (§6.2) e a verificação (§6.3) só são construídos **se** o projeto
> da GUI for adiado ou abandonado.

### 6.1 O que o expurgo faria sem cuidado

`git-filter-repo` termina com reset forte sobre o histórico reescrito. Um
arquivo que não existe mais em commit nenhum **não sobrevive a esse reset** —
o expurgo apagaria os binários do disco.

Solução: copiar para fora antes, devolver depois. Cópia local, sem rede.
Ficam como arquivos não rastreados e entram no `.gitignore`.

Do ponto de vista do usuário nada muda: os arquivos continuam em
`original/DAMX-GUI/` e `original/DAMX-Daemon/`, o `setup.sh` continua
achando, e a instalação continua **offline**.

### 6.2 Manifesto

`original/upstream.conf`, versionado:

```
UPSTREAM_TAG="1.0.2-h1"
UPSTREAM_COMMIT="1f88341d433ed8481a5f98b9ac45b1049b485267"
SHA256_GUI="664f4e27312314d2084938ade0e3c8bd7b8937d14388754d72d3a32097bc51aa"
SHA256_DAEMON="801ccba4b24569fdb72b323124d5d39336265df5922148f54138993ff17ed993"
```

Os dois hashes acima foram calculados dos binários hoje no disco, e servem
de segunda verificação do expurgo: se não baterem depois da §6.1, algo se
perdeu.

Responde a *"que versão eu tenho no disco?"*, que hoje ninguém consegue
responder — `release.txt` diz "1.0.2" e está errado (§7).

### 6.3 Verificação na instalação, sem rede

`lib/verificar.sh` confere presença e sha256 contra o manifesto. Divergência
ou ausência: mensagem clara dizendo o que fazer, e parada. **Nenhuma chamada
de rede no caminho de instalação.**

### 6.4 O que NÃO será feito

Nenhum script de download automático. Quando sair a 1.0.3, o tarball é
baixado à mão do upstream — que publica `DAMX-<v>.tar.xz` e
`DAMX-<v>.tar.xz.sha256` juntos — e o manifesto é atualizado.

Decisão explícita do usuário. Um mecanismo de download serviria o caso
"alguém clona o repositório noutra máquina", que não existe: não há remote,
não há outros clones, é uma máquina só.

---

## 7. A base está com o nome errado

O commit `1f88341` que este repositório usa como baseline é a tag
**`1.0.2-h1`** do upstream (o hotfix, 2026-07-23). A `1.0.2` de verdade é
`c1a4292`, de 2026-07-20.

O código está certo; o rótulo mente. Consequência prática: quem for comparar
com "a 1.0.2" compara com a release errada.

Correção, aproveitando que o `filter-repo` recria as tags de qualquer forma:

- tag local → `upstream/1.0.2-h1`
- `SCRIPT_VERSION` → `1.0.2-h1+anv15-52`
- `release.txt`, `README.md` e a spec do port → corrigidos

---

## 8. Testes e CI

### 8.1 O que os testes atuais são

Oito das nove suítes são `grep` sobre o fonte. Isso é **adequado ao propósito
delas**, que é declarado: detectar o que a próxima release do upstream
sobrescreveu. Continuam onde estão, sem mudança.

O que elas não fazem é verificar comportamento. Nenhuma executa o
`setup.sh` — não havia como, sem modo não-interativo.

### 8.2 Camada nova: comportamento em contêiner

Habilitada pela §5.3. Contêineres de Arch, Debian e Fedora rodam
`setup.sh --install --sim` de verdade e conferem **o efeito**, não o texto:

- unit do daemon ativa
- `.desktop` presente e `update-desktop-database` chamado
- desinstalação não deixa rastro (a varredura da Armadilha 8)
- `--help` e flags inválidas saem com código correto

O que não dá para testar em contêiner — DKMS, sysfs, hwdb — continua sendo
verificado pelas suítes de máquina real.

### 8.3 Análise estática

`shellcheck` em todos os scripts. Hoje são ~1300 linhas de bash com zero
análise estática, e a ferramenta nem está instalada na máquina.

### 8.4 CI

Workflow do GitHub Actions rodando shellcheck, as suítes de fonte e os
testes em contêiner a cada push. Vive em `.github/`, fora de `original/` —
não é atingido pela sobrescrita da próxima release.

---

## 9. Documentação

`README.md`: novo layout com `lib/`, as flags, o fim do serviço de tecla, a
base renomeada, e os binários não versionados.

`docs/ARMADILHAS.md` ganha três entradas, no formato existente (sintoma,
causa, verificação):

- **15.** `filp_open` devolve `ERR_PTR`, nunca `NULL` — `if (!file)` é
  aprovação garantida de um ponteiro de erro
- **16.** Release do upstream se identifica por commit, não por número —
  `1.0.2` e `1.0.2-h1` distribuem tarballs de mesmo nome
- **17.** `set -e` e as funções que dependem de retorno não-zero
- **18.** A tabela de quirks **não** diz o que o modelo usa — capabilities
  vêm também do descritor AA do firmware, em tempo de execução. Este
  notebook tem `rfkill/acer-wireless` e `acer-bluetooth` sem que o quirk os
  ligue. Enxugar pela tabela teria removido o rfkill do wifi. Medir o
  sistema em execução, nunca deduzir da tabela

O `README.md` também precisa dizer, em lugar visível, que **o driver deixou
de ser genérico**: depois da §4.4 ele carrega só no ANV15-52, e copiar
`original/` para um Acer diferente não funciona mais. Hoje o README promete
o contrário.

---

## 10. Critérios de conclusão

1. `.git` abaixo de 5 MB, tag `upstream/1.0.2-h1` presente
2. Binários no disco, não rastreados, hash batendo com o manifesto
3. `./tests/run-all.sh` e `sudo -A ./tests/run-all.sh` verdes
4. `shellcheck` sem achados em todos os scripts
5. Build `W=1` sem warnings sob Clang **e** GCC
6. `setup.sh --install --sim` completo em contêiner nas três distros
7. Instalação real nesta máquina: módulo carregado, sysfs populado, botão N
   abrindo a GUI, e `usb_charging` dentro do contrato `0/10/20/30`
8. Desinstalação sem rastro pela varredura da Armadilha 8
9. Depois do enxugamento (§4.4): os **mesmos seis atributos** em
   `nitro_sense/`, os mesmos quatro perfis térmicos, `fan_speed` e
   `usb_charging` respondendo como antes. O critério é comportamento
   idêntico com menos código — qualquer diferença observável é regressão.
10. Depois do enxugamento, o bitmask medido no passo zero da §4.4 continua
    idêntico, e `rfkill` ainda lista `acer-wireless` e `acer-bluetooth`

---

## 11. Riscos

| risco | mitigação |
|---|---|
| `filter-repo` produz histórico errado | `.git-backup` antes; conferir 9/9 depois |
| `set -e` quebra fluxo hoje tolerante a erro | converter módulo a módulo, suíte a cada passo |
| remoção do serviço regride desktop não-KDE | instruções manuais impressas, como já são hoje. Aceito: a máquina roda KDE |
| **enxugar remove algo que o firmware liga em runtime** | §4.4 passo zero — medir o bitmask antes de tocar em qualquer coisa; verificação de `rfkill`, hotkeys e hwmon após **cada** commit. Este risco já se materializou uma vez, na primeira versão desta spec |
| binários perdidos no expurgo | §6.1 — cópia para fora antes, conferência de hash depois |
| **enxugamento quebra o que funciona** | vai por último; tag `pre-enxugamento`; um commit por subsistema; verificação de comportamento após cada um; commit que muda a saída é revertido, não consertado |
| **driver deixa de dar merge com o upstream** | aceito conscientemente (§2). Mitigação parcial: os três commits da §4.1-4.3 vêm **antes** do enxugamento, então continuam legíveis e reaplicáveis isoladamente se um dia o projeto voltar ao driver completo |

---

## 12. Projeto seguinte: substituir GUI e daemon por fonte própria

Decidido em 2026-09-05, durante a revisão desta spec. **Não faz parte dela** —
terá spec própria — mas está registrado aqui porque altera a ordem do
trabalho e o destino da §6.

### O que a medição encontrou

O daemon escuta em `/var/run/DAMX.sock` (`srw-rw-rw-`, acessível sem root) e
fala **JSON de linha**:

```json
→ {"command": "get_supported_features"}
← {"success": true, "data": {"available_features": ["thermal_profile",
     "backlight_timeout", "usb_charging", "battery_limiter", "fan_speed",
     "battery_calibration"], "laptop_type": "NITRO", "has_four_zone_kb": false}}

→ {"command": "get_thermal_profile"}
← {"success": true, "data": {"current": "balanced",
     "available": ["low-power", "quiet", "balanced", "balanced-performance"]}}
```

A fronteira entre GUI e daemon é um socket, não uma biblioteca. Qualquer
linguagem que fale JSON em socket Unix pode substituir os dois lados,
separadamente ou juntos.

### A economia

| | hoje | proposta |
|---|---|---|
| GUI | 104.500.108 B (.NET 9 self-contained: runtime + Skia + HarfBuzz + Avalonia embutidos) | ~40 KB de fonte PySide6 |
| daemon | 16.8 MB (PyInstaller onefile) | ~300 linhas de Python |
| **total** | **~121 MB de blob opaco** | **~60 KB de fonte legível** |

Nada novo a instalar: `pyside6 6.11.2`, `qt6-base 6.11.2` e Python 3.14.7 já
estão no sistema — o Qt6 porque o Plasma o usa.

### Portabilidade

Qt6 não é tecnologia do KDE. O app roda em GNOME, XFCE, Sway e qualquer
ambiente com servidor gráfico; o KDE apenas dá aparência nativa, por
compartilhar o toolkit. **Não há regressão** frente à GUI Avalonia atual, que
também não é nativa em ambiente nenhum.

### Escopo, e o que ainda não foi decidido

Substituir **os dois**, GUI e daemon. Perguntas de desenho em aberto, para a
spec própria: janela ou ícone de bandeja; o que a tela principal mostra;
comportamento quando o daemon não responde; se há histórico de temperatura;
como o daemon obtém privilégio para escrever em sysfs (unit root, como hoje,
ou helper com polkit); e se o protocolo do socket é mantido igual — o que
permitiria trocar um lado de cada vez.

### Ordem

```
fase A desta spec (expurgo do histórico)
   ↓
brainstorm + spec do projeto da GUI/daemon
   ↓
fases B-G desta spec, já sabendo o destino da §6
```

A razão de a fase A vir antes de tudo é a mesma da §3: o `filter-repo`
reescreve todo commit existente, então qualquer trabalho feito antes dele
seria reescrito junto.
