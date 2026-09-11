# Nexus Sense — GUI e agente em fonte própria

**Data:** 2026-09-05
**Estado:** aprovado para implementação
**Base:** `1f88341` = tag upstream `1.0.2-h1`
**Antecedente:** §12 de `2026-09-05-melhorias-e-reforma-design.md`

---

## 1. Problema

O fork distribui dois binários do upstream que somam ~121 MB e não dão para
ler, comparar nem revisar:

| | tamanho | o que é |
|---|---|---|
| `DivAcerManagerMax` | 104.500.108 B | .NET 9 self-contained: runtime, Skia, HarfBuzz e Avalonia embutidos |
| `DAMX-Daemon` | 16,8 MB | Python empacotado com PyInstaller |

Eles já saíram do histórico do git na fase A. Ficam no disco, e o
`setup.sh` os instala. Esta spec os substitui por fonte própria.

O objetivo não é economizar disco. É poder ler o que roda como root na
própria máquina, e poder corrigi-lo.

---

## 2. O que foi medido

Tudo nesta seção foi verificado nesta máquina — um Nitro ANV15-52, kernel
7.2.2, Plasma sobre Wayland — e não inferido do código.

### 2.1 O daemon é recuperável

O bundle PyInstaller abre. Dentro há `DAMX-Daemon.py` compilado para Python
3.11 e um módulo `PowerSourceDetection`. Nomes, docstrings, caminhos e
mensagens de erro são legíveis.

A superfície real do socket tem **20 comandos**, não os dois registrados na
§12 da spec anterior:

```
get_all_settings  get_supported_features  get_version
get/set_thermal_profile   get_thermal_profile_choices
get/set_backlight_timeout   get/set_battery_calibration
get/set_battery_limiter   get/set_boot_animation_sound
get/set_fan_speed   get/set_lcd_override   get/set_usb_charging
get/set_per_zone_mode   get/set_four_zone_mode
force_nitro_model   force_predator_model   force_enable_all
set_modprobe_parameter_{nitro,predator,enable_all}
remove_modprobe_parameter
restart_daemon   restart_drivers_and_daemon
```

`get_all_settings` devolve tudo de uma vez, e é o que a GUI usa na abertura.

### 2.2 O daemon faz mais do que ler e escrever sysfs

Reescreve `/etc/modprobe.d/linuwu-sense.conf`; executa `rmmod`, `modprobe` e
`systemctl restart` de si mesmo; mantém contador de tentativas de reinício em
`/tmp/damx_restart_attempts`; e fala HID cru com um teclado RGB ENEK5130 via
`ioctl(HIDIOCSFEATURE)`, com mapa de efeitos obtido por tentativa e erro.

O `PowerSourceDetector` sonda a fonte de energia e troca o perfil térmico
sozinho quando o cabo sai.

### 2.3 O socket é gravável por qualquer processo da máquina

```
srw-rw-rw-  /var/run/DAMX.sock
```

Modo 666, sem autenticação. Qualquer processo de qualquer usuário pode
mandar `restart_drivers_and_daemon` ou zerar as ventoinhas.

### 2.4 A GUI é um painel de controle **e** um monitor de hardware

Além dos controles, o binário .NET traz `GetCpuTemperature`, `GetCpuUsage`,
`GetCpuName`, `GetNvidiaGpuMetrics`, `GetAmdGpuMetrics`,
`GetGpuDriverVersion` e `InitializeTemperatureGraph`. São cinco telas:
Dashboard, Power & Performance, Battery Controls, Keyboard Lighting e
System Settings.

### 2.5 A telemetria não passa pelo socket

`get_fan_speed` devolve o **setpoint**, não a rotação:

```json
{"cpu": "0", "gpu": "0"}      // 0 = automático
```

A rotação real e as temperaturas estão no hwmon `acer`, legível sem
privilégio:

```
fan1_input = 2079    fan2_input = 1870
temp1 = 25 °C        temp2 = 43 °C        temp3 = 43 °C
```

### 2.6 Os atributos graváveis cabem sob um dispositivo só

```
/sys/devices/platform/acer-wmi/nitro_sense/fan_speed
/sys/devices/platform/acer-wmi/nitro_sense/battery_limiter
/sys/devices/platform/acer-wmi/nitro_sense/usb_charging
/sys/devices/platform/acer-wmi/nitro_sense/backlight_timeout
/sys/devices/platform/acer-wmi/nitro_sense/battery_calibration
/sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile
```

Seis arquivos, `root:root 644`. O caminho `/sys/firmware/acpi/platform_profile`
é apelido legado do sexto; o dispositivo real está sob `acer-wmi` e o udev o
enxerga:

```
KERNEL=="platform-profile-0"
SUBSYSTEM=="platform-profile"
ATTR{choices}=="low-power quiet balanced balanced-performance"
```

### 2.7 Permissão de grupo funciona em sysfs — medido

Aplicando `chgrp` + `chmod g+w` nos seis e escrevendo como uid 1000, sem root:

```
backlight_timeout   0 → 1 → 0                    aceito
profile             balanced → quiet → balanced  aceito
```

sysfs honra a permissão de grupo. **Este é o resultado que dispensa o daemon.**

### 2.8 Na bateria o driver recusa três perfis

`linuwu_sense.c:2317` barra `performance`, `balanced-performance` e `quiet`
quando não há energia da tomada. Medido na máquina, com o cabo fora:

```
quiet       → write error: operação sem suporte   (-EOPNOTSUPP)
balanced    → aceito
low-power   → aceito
```

O alcance permitido na bateria **não é contíguo**: passam `Econômico` e
`Equilibrado`, mas o `Silencioso`, que fica entre os dois e é mais econômico
que o `Equilibrado`, é recusado.

### 2.9 O perfil não cai sozinho — quem o derruba é o daemon

Com o perfil em `balanced-performance` e o cabo retirado, o log do daemon
registrou, no mesmo segundo:

```
2026-09-05 05:29:53,803 - Switched to battery power
2026-09-05 05:29:53,803 - Auto-switching to balanced mode for battery power
```

O driver não tem notificador de fonte de energia — `grep` por
`power_supply_notifier`, `notifier_block` e afins em `linuwu_sense.c` volta
vazio. Ele apenas barra escritas; nunca reage.

**Consequência:** sem o `PowerSourceDetector`, a máquina permanece em
`balanced-performance` na bateria por tempo indefinido — um estado que ela
recusaria assumir se pedido. A correção automática não é conveniência; é a
única coisa no sistema que corrige essa assimetria.

### 2.10 O firmware anuncia quatro perfis, não cinco

```
choices: low-power quiet balanced balanced-performance
```

Falta `performance`. O driver pergunta ao firmware
(`WMID_gaming_get_misc_setting(SUPPORTED_PROFILES)`) e aceita a resposta; só
com `nitro_v4`, `predator_v4` ou `enable_all` ele força os cinco
(`linuwu_sense.c:2372-2381`).

### 2.11 O power-profiles-daemon está ativo e não disputa o perfil

```
$ powerprofilesctl get
performance
$ powerprofilesctl list
  balanced:   CpuDriver: intel_pstate   PlatformDriver: placeholder
```

O ppd 0.30 não se ligou ao `platform_profile` — dirige apenas o
`intel_pstate`. Por isso ele diz `performance` enquanto o `platform_profile`
diz `balanced`, sem conflito. **Hipótese não verificada:** recusou por faltar
um perfil da classe `performance` nas escolhas do firmware. O teste é
carregar o módulo com `nitro_v4` e ver se ele passa a se ligar. Fica
registrado como ponto a vigiar, não como defeito.

### 2.12 Sondar a GPU custa 80× mais que ler o hwmon

```
nvidia-smi                     18 ms     e acorda a dGPU se ela estiver dormindo
2 leituras de hwmon             0,23 ms  e não acorda nada
```

A dGPU está com `power/control = auto`: adormece quando ociosa. Um laço de
2 s chamando `nvidia-smi` a manteria acesa permanentemente.

### 2.13 O nome `linuwu` não existe no código do driver

```
$ grep -c linuwu original/Linuwu-Sense/src/linuwu_sense.c
0
```

O nome do módulo vem do arquivo, via `obj-m := src/linuwu_sense.o`, e chega
ao código só como `KBUILD_MODNAME` no prefixo dos logs (`linuwu_sense.c:25`).
Já `nitro_sense` e `predator_sense` **estão** fixados no `.c`
(linhas 4052-4068): nomeiam a família do laptop, não o projeto.

---

## 3. Decisões

| # | decisão | por quê |
|---|---|---|
| D1 | Escopo: painel de controle **+ monitor de hardware**. RGB fora. | Paridade com o que a GUI atual entrega neste laptop. O ENEK5130 não pode ser testado aqui (`has_four_zone_kb: false`) e viraria código morto. |
| D2 | **Sem daemon.** | §2.7 provou que a escrita por grupo funciona. O papel insubstituível do daemon era segurar root; some. |
| D3 | Escrita diária por **grupo via udev**; `modprobe` e recarga do módulo por **pkexec**. | Reescrever `/etc/modprobe.d` e rodar `rmmod` não viram permissão de grupo. São raros, e pedir senha é o comportamento certo. |
| D4 | **Dois processos**: agente sem interface + GUI. | A correção de perfil não pode depender de a bandeja existir. Sway e GNOME puro não têm bandeja sem extensão. |
| D5 | Agente e GUI **não conversam**. | O sysfs é o estado compartilhado. Sem socket, sem DBus entre eles, sem IPC. |
| D6 | Bandeja por **StatusNotifierItem próprio**, não `QSystemTrayIcon`. | §7.1 — é a única forma de ter scroll. |
| D7 | Os quatro perfis ficam **sempre nas mesmas posições**. | §6.2 — hoje a tela troca de forma e nada fica no lugar. |
| D8 | Renomear tudo para **`nexus_sense`**, driver incluído, em **fase separada**. | §12. |

---

## 4. Arquitetura

```
       sem daemon · sem socket · sem processo root permanente

  nexus-sense-agent      Python puro, sem Qt.
                         Serviço de usuário, Restart=always.
                         Sonda ACAD/online a cada 2 s.
                         Corrige o perfil na troca de fonte.

  nexus-sense            PySide6. Bandeja (SNI) + janela.
                         Aberto por você, pela bandeja ou pelo botão N.

  nexus-sense-helper     ~80 linhas. Root por pkexec.
                         SÓ modprobe + recarga do módulo.

  60-nexus-sense.rules   udev: chgrp nexus_sense + g+w nos 6 atributos.
```

### 4.1 O contrato é o sysfs

Agente e GUI leem e escrevem os mesmos seis arquivos. O kernel é a fonte da
verdade; nenhum dos dois precisa do outro para funcionar. Se a GUI muda o
perfil, o agente vê na leitura seguinte, e vice-versa.

O que o sysfs não guarda é **preferência**, e isso vai para um arquivo:

```
~/.config/nexus-sense/config.toml     a GUI escreve, o agente relê a cada ciclo
```

Ele guarda: qual perfil usar na bateria, se a correção automática está
ligada, e em que perfil você estava na tomada — para **devolver** ao religar.
Isso conserta um defeito do daemon atual, que derruba ao desconectar e nunca
restaura.

### 4.2 Detecção de fonte

Sondagem de `ACAD/online` a cada 2 s: um arquivo de 4 bytes, modo 444. As
alternativas — netlink do udev, UPower via DBus — são mais elegantes e mais
frágeis, e trazem dependência. Ficam registradas como caminho futuro.

### 4.3 Camada de acesso

Nenhum componente abre caminho absoluto. Tudo passa por uma camada que
recebe uma raiz:

```python
Sysfs("/")                       # produção
Sysfs("/tmp/fixture-anv15")      # teste
```

É essa decisão que torna quase toda a suíte executável sem hardware, sem root
e sem laptop Acer (§11).

---

## 5. Privilégio e segurança

### 5.1 A regra udev

```
# 60-nexus-sense.rules
SUBSYSTEM=="platform", KERNEL=="acer-wmi", \
  RUN+="/bin/sh -c 'chgrp nexus_sense /sys/devices/platform/acer-wmi/nitro_sense/* \
                    /sys/devices/platform/acer-wmi/platform-profile/*/profile; \
                    chmod g+w ...'"
```

A forma final é trabalho da implementação; o que a spec fixa é: grupo
`nexus_sense`, modo `664`, exatamente os seis atributos, e nada mais.
`version` continua `444`.

### 5.2 O que muda no risco

**Estreita.** Hoje o socket em modo 666 aceita comandos de qualquer processo
da máquina, sem autenticação, incluindo recarregar o driver. Depois, só
membros de `nexus_sense` escrevem, e recarregar o driver exige senha.

**A permissão nova, dita em voz alta:** quem estiver no grupo pode alterar as
ventoinhas e o perfil térmico sem senha. O driver clampa 0-100 e 0 significa
automático, então o pior caso é modesto — mas é uma permissão que hoje não
existe, e o instalador tem de dizer isso ao criar o grupo.

### 5.3 O helper

`nexus-sense-helper` é invocado por `pkexec`. Ele aceita um conjunto fechado
de operações — definir ou remover o parâmetro do módulo, e recarregar o
módulo — e nada mais. Sem passar caminho, sem passar comando. Uma regra
polkit acompanha, exigindo autenticação de administrador.

---

## 6. A janela

Barra lateral com cinco seções e grade de cartões — a mesma forma da GUI
atual, que foi capturada e reproduzida. Em português do Brasil.

```
Painel   Desempenho   Bateria   Teclado   Diagnóstico
```

### 6.1 Painel

Cartões de Processador, Gráficos e Ventoinhas na linha de cima; Temperatura
(gráfico) e Bateria embaixo.

Aprimoramentos sobre a GUI atual:

- **Sai o cabeçalho** com o mascote e o título "Div Acer Manager MAX"
  espaçado; vira barra de título comum, e a tela ganha ~60 px úteis.
- **O gráfico ganha eixo com escala em °C.** Hoje as linhas flutuam sem
  referência.
- **Alinhamento de colunas é requisito**, não acabamento: os cartões da
  linha superior têm mesma altura, mesma linha de base e mesma ordem de
  campos. Hoje não têm.
- A barra lateral ganha um rodapé dizendo se o **agente** está de pé — a
  informação que passa a importar quando não há mais daemon.

### 6.2 Desempenho — o comportamento por fonte

Os quatro perfis ocupam **sempre as mesmas quatro posições**. O que muda com
a fonte é o estado, não a forma:

```
na tomada    Econômico   Silencioso   [Equilibrado]   Desempenho
na bateria   Econômico   ///////////  [Equilibrado]   //////////
```

O indisponível fica hachurado, com o motivo escrito. Nenhum botão muda de
lugar quando o cabo sai.

Isso substitui o comportamento atual, em que o conjunto **muda de tamanho e
de conteúdo** — três botões na tomada (`Quiet`, `Balanced`, `Performance`),
dois na bateria (`Eco`, `Balanced`). Hoje o `Econômico` some quando você
pluga, sem explicação, e a posição do `Equilibrado` depende do cabo.

Nomes: `Econômico`, `Silencioso`, `Equilibrado`, `Desempenho`, com o nome
técnico do sysfs em texto secundário.

### 6.3 Bateria

Os três cartões de hoje viram três linhas de uma lista: limite de carga,
carregamento USB, calibração. O aviso "não tire da tomada durante a
calibração" deixa de ser parágrafo solto e vira o subtítulo da linha a que
pertence.

### 6.4 Teclado

Um controle só: apagar a iluminação após inatividade (`backlight_timeout`,
30 s quando ligado). É o único recurso de teclado que este firmware anuncia —
o RGB de quatro zonas está fora de escopo (§14).

Sai o aviso "This Section Requires Testing" que a GUI atual mostra em laranja:
é nota de desenvolvimento vazando para a interface.

**A seção só aparece na barra lateral se o recurso existir no firmware.** Numa
máquina sem `backlight_timeout`, ela não é exibida vazia — some. A mesma regra
vale para qualquer outra seção que fique sem nenhum controle.

### 6.5 Diagnóstico

Substitui "System Settings". Os botões "Check for Updates" e
"Issue/Feedback" saem: apontam para as releases e o GitHub do PXDiv, que não
são mais a base deste fork.

A tela passa a responder **"por que aquele botão está cinza?"**:

- **Sistema** — modelo, tipo, versão do driver, parâmetro do módulo em vigor,
  recursos que o firmware anuncia.
- **Verificações** — módulo carregado; permissão de grupo aplicada e você
  dentro do grupo; agente ativo; `power-profiles-daemon` presente e se está
  ou não disputando o perfil.
- **Uma ação**, a última linha: o firmware anuncia quatro perfis e existe um
  quinto atrás de `nitro_v4`. Forçar pede senha por `pkexec` e recarrega o
  driver. O antigo "Internals Manager" deixa de ser porta sem placa e vira a
  resposta a um fato mostrado ali mesmo.

---

## 7. A bandeja

### 7.1 Por que StatusNotifierItem

`QSystemTrayIcon` do Qt expõe quatro eventos — `Trigger`, `DoubleClick`,
`MiddleClick`, `Context` — e **nenhum de roda**. O ícone de energia do Plasma
tem scroll porque é um StatusNotifierItem, e o host chama um método DBus.
Introspecção de um item vivo desta sessão:

```
.Activate            method  ii
.ContextMenu         method  ii
.SecondaryActivate   method  ii
.Scroll              method  is      ← (delta, orientação)
```

O `QtDBus` do PySide6 está disponível. O custo é implementar o SNI à mão e
registrar no `org.kde.StatusNotifierWatcher` — cerca de 150 linhas, a parte
mais chata do projeto.

### 7.2 Gestos

```
roda para cima    perfil mais agressivo
roda para baixo   perfil mais econômico

  Econômico  <  Silencioso  <  Equilibrado  <  Desempenho
```

**O buraco na escala.** Na bateria o `Silencioso` é recusado pelo driver
(§2.8), embora fique entre dois permitidos. O scroll **pula o indisponível e
segue para o próximo válido** — nunca para num degrau que falharia. Na
bateria, girar para cima a partir do `Econômico` leva direto ao
`Equilibrado`; girar mais para cima não faz nada, porque o `Desempenho`
também está barrado. O scroll bate no limite e para, sem erro e sem escrita
que falha.

```
clique esquerdo   abre a janela
clique direito    menu: perfis disponíveis, ventoinha auto/máx, abrir, sair
clique do meio    alterna entre o perfil atual e o anterior
tooltip           perfil, rotação das duas ventoinhas, temperatura
ícone             muda conforme o perfil
```

### 7.3 Degradação

Sem `StatusNotifierWatcher` no barramento, o app cai para `QSystemTrayIcon`:
bandeja com menu, sem scroll. Sem nem isso, abre a janela direto. Em nenhum
caso a correção de perfil é afetada — ela mora no agente, que não sabe o que
é Qt.

**Risco com saída conhecida:** falta confirmar se o Plasma chama
`ContextMenu()` quando o item não exporta um menu DBus. Se chamar, o menu é
um `QMenu` comum. Se não, é preciso implementar `com.canonical.dbusmenu` —
mais trabalho, mesmo resultado.

---

## 8. O agente

`nexus-sense-agent` roda como serviço de usuário:

```ini
[Unit]
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/nexus-sense-agent
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
```

Comportamento:

- ao **desconectar**: guarda o perfil corrente em `config.toml` e escreve o
  perfil de bateria configurado. O padrão é `balanced` — o único, junto de
  `low-power`, que o driver aceita na bateria (§2.8). Se o valor configurado
  for recusado, recua para `balanced` e registra o motivo;
- ao **reconectar**: devolve o perfil guardado;
- se a correção automática estiver desligada na configuração, não faz nada.

**Regressão registrada:** hoje a correção é uma unit de sistema e roda
sempre, inclusive antes do login. Passa a depender de sessão gráfica. O
autostart resolve na prática, e a alternativa — manter uma unit de sistema só
para isso — foi considerada e recusada, porque reintroduziria o processo root
permanente que D2 elimina.

---

## 9. Erro e estados degradados

Nenhum estado degradado vira exceção na tela. Cada um tem lugar fixo e uma
frase que diz o que fazer.

| o que quebra | como se percebe | o que aparece |
|---|---|---|
| módulo não carregado | `/sys/module/nexus_sense` ausente | tela única com o comando para carregar |
| permissão não aplicada | os seis não estão `664` com grupo, ou você fora do grupo | Diagnóstico acusa; controles em somente-leitura, com o comando de correção |
| entrou no grupo agora | grupo em `/etc/group`, ausente na sessão | frase específica: precisa relogar — sintoma idêntico ao de cima, causa diferente |
| driver recusa a escrita | `OSError` com `EOPNOTSUPP` | corrida entre o clique e a retirada do cabo: relê o estado e corrige a tela, sem diálogo |
| agente fora do ar | `systemctl --user is-active` | rodapé da barra lateral e linha no Diagnóstico |
| driver recarregado | caminhos somem e voltam | o app repara e reabre; permissões voltam a `644` até o udev reagir |

---

## 10. Armadilhas novas

Entram em `docs/ARMADILHAS.md` junto das 14 existentes.

### 10.1 O índice do hwmon não é estável

Hoje o sensor `acer` é `hwmon5`, mas a numeração depende da ordem de carga
dos módulos e muda entre boots. Ler `/sys/class/hwmon/hwmon5` é bomba-relógio.

```
certo:  /sys/devices/platform/acer-wmi/hwmon/hwmon*/   ancorado no dispositivo
errado: /sys/class/hwmon/hwmon5/                        ancorado no índice
```

Para o `coretemp` e outros, a regra é a mesma: achar pelo conteúdo de `name`,
nunca pelo número.

### 10.2 Sondar a dGPU a acorda

`nvidia-smi` custa 18 ms e **acorda** a GPU adormecida (§2.12). A regra:

1. ler `power/runtime_status` — um arquivo, custo desprezível;
2. se disser `suspended`, o cartão mostra **"adormecida"** e nenhum
   `nvidia-smi` é chamado;
3. se disser `active`, sondar normalmente.

O painel nunca pode ser o motivo de a GPU estar acordada. E a telemetria só
roda com a janela aberta: fechou, para. A bandeja usa apenas o hwmon, que é
barato; o agente não lê sensor nenhum.

---

## 11. Testes

A suíte atual é 9/9 e quase toda `grep` sobre o fonte — adequada para
detectar o que o upstream sobrescreveu, insuficiente para verificar
comportamento. Este código é nosso e pode ser testado de verdade, graças
à camada de §4.3.

**Sem hardware, sem root** (`pytest` contra árvore de mentira):

- disponibilidade dos perfis dada a fonte e a lista do firmware, incluindo o
  buraco do `Silencioso`;
- o agente: dada uma sequência de estados de `ACAD/online`, quais escritas
  emite — e que **devolve** o perfil ao religar;
- validação: ventoinha 0-100, `usb_charging` ∈ {0, 10, 20, 30};
- achar o sensor `acer` por nome, com os índices de hwmon embaralhados de
  propósito na árvore de teste;
- GUI com `pytest-qt`: a janela abre contra a árvore, os widgets refletem o
  estado, clicar num perfil emite a escrita certa.

**Com hardware** (entram na suíte existente):

- os seis atributos existem e estão graváveis pelo grupo;
- escrever e ler de volta cada um, restaurando o valor original;
- `quiet` na bateria devolve `EOPNOTSUPP` — só roda na bateria, e se pula
  sozinho na tomada.

**Verificação manual documentada**, por não ser automatizável: o SNI na
bandeja (precisa de sessão gráfica com host SNI) e o `pkexec`. Roteiro curto
em `docs/`, com o que clicar e o que esperar.

---

## 12. Renomeação para `nexus_sense`

Decidida nesta sessão. **Fase separada**, não parte da implementação da GUI.

### 12.1 Nomes

| | nome |
|---|---|
| módulo do kernel | `nexus_sense` |
| grupo | `nexus_sense` |
| unit do módulo | `nexus_sense.service` |
| `modules-load.d` | `nexus_sense.conf` |
| app | `nexus-sense` |
| agente | `nexus-sense-agent` |
| helper | `nexus-sense-helper` |
| unit de usuário | `nexus-sense-agent.service` |
| regra udev | `60-nexus-sense.rules` |
| `modprobe.d` | `nexus-sense.conf` |
| configuração | `~/.config/nexus-sense/config.toml` |
| `.desktop` | `nexus-sense.desktop`, exibindo **Nexus Sense** |
| grupos sysfs | `nitro_sense` / `predator_sense` — **inalterados** |

Convenção: underscore do lado do kernel, porque o nome do módulo tem de casar
com o `.ko`; hífen do lado do usuário.

### 12.2 Alcance

| onde | ocorrências |
|---|---|
| `setup.sh` | 48 |
| `tests/*.sh` | 28 |
| `Makefile` | 2 |
| `dkms.conf` | 4 |
| `linuwu_sense.service` | 4 |
| `src/linuwu_sense.c` | **0** — só o nome do arquivo |
| `docs/` | ~190, histórico, não se reescreve |

### 12.3 Por que fase separada

A renomeação do módulo quase não toca a GUI: os caminhos de §2.6 passam por
`/sys/devices/platform/acer-wmi/`, imunes ao nome do módulo. Muda apenas a
verificação "o módulo está carregado", de `/sys/module/linuwu_sense` para
`/sys/module/nexus_sense` — uma linha.

O que ela **toca** é o instalador e cinco testes, e exige desinstalação limpa
antes: pacote DKMS antigo, `modules-load.d` antigo e unit antiga precisam sair,
senão sobram dois módulos disputando o mesmo dispositivo.

São dois trabalhos de natureza diferente. A spec da GUI já usa os nomes
novos, para que nada nasça provisório; a renomeação do driver acontece na sua
própria fase, com seu próprio plano.

---

## 13. Ordem do trabalho

```
[x] fase A — expurgo do histórico
[ ] esta spec — GUI e agente             ← usa os nomes novos desde o início
[ ] renomeação do módulo para nexus_sense
[ ] fases B-G da spec de melhorias
```

A §6 da spec de melhorias — "binários e manifesto" — perde o objeto: não
haverá binário a versionar nem manifesto a manter. Ela é substituída por esta
spec e pela renomeação.

---

## 14. Fora de escopo

- **Teclado RGB de quatro zonas** (`per_zone_mode`, `four_zone_mode`, HID
  ENEK5130). Este laptop não o tem (`has_four_zone_kb: false`) e o código
  seria escrito sem poder ser verificado.
- **`lcd_override` e `boot_animation_sound`**: existem no protocolo do daemon
  e não constam dos recursos que este firmware anuncia.
- **Compatibilidade com o protocolo do socket.** Não há socket. Trocar um
  lado de cada vez deixou de ser possível — e deixou de ser necessário, já que
  os dois lados saem juntos.
- **Empacotamento para outras distribuições.** O app exige `pyside6` e
  `qt6-base` presentes; empacotar por distro é trabalho posterior.

---

## 15. Riscos em aberto

| risco | saída |
|---|---|
| Plasma pode não chamar `ContextMenu()` sem menu DBus exportado | implementar `com.canonical.dbusmenu`; mais trabalho, mesmo resultado |
| a regra udev pode não disparar na ordem certa em todo boot | verificar no boot; alternativa é aplicar no `ExecStart` da unit do módulo |
| o ppd pode passar a disputar o `platform_profile` numa versão futura | Diagnóstico já mostra o estado; a hipótese de §2.11 fica para medir |
| reimplementar o monitor de hardware pode ficar pior que o atual antes de ficar melhor | é a parte mais longa; sem atalho |
| a distribuição regride: o binário atual roda sem instalar nada | aceito e registrado; o código ganha portabilidade, a distribuição perde |
