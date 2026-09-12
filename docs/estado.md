# Estado do projeto

Mapa de onde o trabalho está. As specs descrevem cada projeto; este arquivo
diz qual é a vez de qual, e o que ficou pendente.

**Última atualização:** 2026-09-12 (poda completa, log silenciado, roteiro sem pendências)

---

## Onde estamos

| | |
|---|---|
| base | partiu do DAMX `1.0.2-h1` (commit `1f88341`) e seguiu sozinho; não rastreia mais o upstream |
| driver | **um modelo só**: 1 entrada DMI, 2 quirks, 1 interface WMI, 2 parâmetros, 2912 linhas (eram 5167) |
| versão | **v1.1.9** — `master` em github.com/brunodobner/nexussense (privado) |
| layout | reorganizado em 2026-09-10: só `setup.sh` executável na raiz |
| histórico | resetado na v1.0.0; a razão dos 111 commits foi para [decisoes.md](decisoes.md) e [armadilhas.md](armadilhas.md) |
| suíte shell | 18 testes: 16 passam, 2 pulam, 0 falham — **com e sem root** |
| suíte Python | 333 passaram (`python3 -m pytest -q`), incluindo DBus privado |
| build | `W=1` limpo sob Clang |

---

## Roteiro

```
[x] Port ANV15-52                    spec 2026-09-04, concluido
[x] Fase A -- expurgo do historico   plano 2026-09-05, concluido
[x] Spec da GUI + agente             spec 2026-09-05, escrita
[x] Plano 1 -- nucleo e agente       plano 2026-09-05, escrito
[x] Icones                           gerados e commitados
[x] Executar o plano 1               10 de 10 tarefas, mesclado em master
[x] Plano 2 -- GUI e bandeja         plano 2026-09-05, escrito
[x] Executar o plano 2               concluido: 12 de 12, virada verificada
[x] Renomeacao do driver             carregamento e permissoes verificados apos boot
[x] Reparo da bandeja                menu confirmado pelo usuario apos reinicio
[x] Ajustes visuais e de resposta    Diagnóstico, ventoinhas e cliques sem atraso
[x] Instalador da aplicação          dependências de execução verificadas e instalação reaplicada
[x] Modo Desempenho máximo           quinto modo do app; validado e instalado
[x] Poda para um modelo so           v1.1.0: 32 entradas DMI -> 1, bitmask identico
[x] Parametros inertes fora          v1.1.3: bitmask identico, verificado na maquina
[x] Classificar a poda               docs/poda-subsistemas.md: camadas A/B/C/D e o portao
[x] Executar a camada A              v1.1.4: -641 linhas, bitmask identico
[x] Executar a camada B              v1.1.5: -1077 linhas, bitmask identico
[x] Enxugar o log do kernel          v1.1.6: ~50 linhas/minuto -> zero em repouso
[x] Camada D, caso a caso            v1.1.8: ec_raw_mode, THREEG e o poll fora
[x] Entender o rfkill do wireless    nao havia defeito; armadilha 25 retratada
[ ] Gatilho por programa aberto      bloco na tela Desempenho; precisa de plano proprio
[ ] Levar os atributos ao mainline   o caminho que encerraria o fork; sem data
```

### Concluído

**Port do ANV15-52** (2026-09-04) — driver reconhecendo o modelo, DKMS,
instalador multi-distro, botão N vinculável.

**Fase A — expurgo do histórico** (2026-09-05) — `.git` de 147.171.205 para
~290.000 bytes. Removidos do histórico os dois binários do upstream e a
pasta `versaopessoal/` inteira. Tag renomeada de `upstream/1.0.2` para
`upstream/1.0.2-h1`, porque o commit `1f88341` é o hotfix, não a `1.0.2`
(que é `c1a4292`) — essa tag foi removida na v1.0.0, junto com o histórico
de desenvolvimento. Ver
o expurgo da fase A.

**Spec da GUI e do agente** (2026-09-05) — brainstorm concluído e spec
escrita em
a spec da GUI e do agente.

O resultado principal veio de medição: **o daemon não é necessário.** `sysfs`
honra permissão de grupo, e escrita como uid 1000 nos seis atributos passou
sem root. O desenho perde o daemon, o socket e o processo root permanente;
ganha um agente sem interface (serviço de usuário) e uma GUI PySide6 com
bandeja `StatusNotifierItem`.

Outras medições que mudaram o desenho: o driver recusa três perfis na bateria
(`-EOPNOTSUPP`, medido); quem derruba o perfil ao tirar o cabo é o daemon, não
o driver; e `nvidia-smi` acorda a dGPU adormecida, o que proíbe sondá-la em
laço.

**Ícones** (2026-09-05) — `packaging/icons/`, commit `3416110`. O ícone do
app é a marca completa vetorizada em `#4A78C8`; o da bandeja é só o N
preenchido, recolorido pelo tema. O `gerar.sh` reproduz tudo a partir de
`src/`, e o `README.md` ao lado registra por que cada decisão — várias são
contra-intuitivas e foram medidas. **Concluído:** quatro níveis verticais no
próprio N, com duas polaridades para o tema; ver `docs/interface.md`.

**Plano 1 — núcleo e agente** (2026-09-05) — as dez tarefas executadas e
mescladas em `master`. Ver
o plano 1.

```
[x] Task 1  camada Sysfs                 13 testes   0b3e0a3
[x] Task 2  escada de perfis             14 testes   5a612d8
[x] Task 3  validacao dos controles      15 testes   dc07cf1
[x] Task 4  telemetria: hwmon por nome   12 testes   a4f0d1f
[x] Task 5  telemetria: GPU sem acordar   9 testes   8cbb466
[x] Task 6  configuracao em TOML          9 testes   93d740a
[x] Task 7  a decisao do agente          11 testes   190071a
[x] Task 8  o laco, o executavel, a unit  8 testes   6e1e50e
[x] Task 9  regra udev e permissoes      hardware    bbee2d9
[x] Task 10 recusa na bateria            hardware    58fad04
```

Nada saiu do script: cada tarefa falhou primeiro pelo motivo previsto,
passou depois, e nenhuma exigiu correção fora do plano. Dois desvios foram
de mecanismo, não do que se verificou:

- **`sg` não existe nesta máquina.** O CachyOS instala `newgrp`, que é
  interativo, mas não o link `sg` que o plano usa para rodar um teste
  dentro do grupo. O substituto não-interativo é
  `sudo -A -u "$USER" -g nexus_sense <comando>` — roda como uid 1000, que
  é o que importa provar.
- **As armadilhas 19 e 20 entraram antes da seção de verificação**, não no
  fim do arquivo como o plano dizia: o fim de `docs/armadilhas.md` é a
  seção "Verificação rápida do conjunto", que não é uma armadilha.

As duas medições de hardware confirmaram o que o modelo assumia por
leitura do `.c`: escrita sem root passa nos seis atributos, e na bateria o
driver recusa `quiet` e `balanced-performance` e aceita `balanced` e
`low-power`.

**Plano 2 — GUI e bandeja** (2026-09-05, escrito) — doze tarefas em
o plano 2.

A ordem é uma fatia vertical, não camadas: a Task 3 já entrega uma janela
que abre com uma página real dentro, e cada tarefa seguinte registra a sua
página em `build_pages`. Dá para ver a coisa funcionando desde a terceira.

### Concluído: o plano 2

```
[x] Task 1  instantaneo do aparelho       11 testes   816ba5a
[x] Task 2  os seis controles e o erro    10 testes   681580e
[x] Task 3  janela, barra e Desempenho    20 testes   c06bd07
[x] Task 4  telemetria e grafico          16 testes   01ea025
[x] Task 5  o Painel                      20 testes   f1dde74
[x] Task 6  Bateria e Teclado             13 testes   432d1e0
[x] Task 7  Diagnostico                   19 testes   785f771
[-] Task 8  CANCELADA -- helper com pkexec
[x] Task 9  StatusNotifierItem            22 testes   95b3810
[x] Task 10 bandeja, fallback e icones    15 testes   6aa5a82
[x] Task 5b Painel revisado e estilo      27 testes   8b755ff
[x] Task 11 empacotamento e instalacao    shell       513d022
[x] Task 12 a virada                      hardware
```

**A virada foi verificada na maquina**, com o cabo na mao:

```
INFO perfil -> balanced (na bateria: balanced-performance nao e permitido...)
INFO perfil -> balanced-performance (de volta na tomada: devolvendo ...)
```

O passo de volta e o que o damx-daemon nunca fez.

Cinco defeitos que so a execucao de verdade mostrou, cada um com teste
proprio agora:

- **o app.py nao chamava main()** -- faltava a guarda `__main__`, e rodar
  como modulo saia 0 calado;
- **registerObject usava ExportAllContents**, que nao inclui adaptadores:
  o item subia sem a interface org.kde.StatusNotifierItem;
- **o eixo do grafico era invisivel** -- pegava cor de palette().mid(),
  que no Breeze escuro e quase o fundo do cartao;
- **reabrir o app duplicava o icone** na bandeja: o nome do servico leva
  o PID e ninguem checava se ja havia instancia;
- **a unit trancava o proprio agente** (`ProtectHome=read-only` sem
  excecao), e o agente nao tinha memoria propria -- entao a falha de
  gravacao desligava a restauracao inteira deixando so um aviso.

Tres coisas que o plano nao previa e entraram: o ajuste de ventoinhas na
tela Desempenho (automatico, maximo e manual), o autostart da bandeja, e
as duas polaridades do icone -- `currentColor` nao e repintado quando o
SVG vem do hicolor, entao o icone ficava preto no painel escuro.


Execução **inline**, com ponto de conferência a cada bloco — como no plano
1. Blocos sugeridos: 1-2, 3-5, 6-8, 9-10, 11-12.

#### Duas mudanças de escopo, decididas em 2026-09-06

**A Task 8 foi cancelada.** Ela existia inteira para uma ação do
Diagnóstico — forçar o quinto perfil de outro firmware via `nitro_v4`,
com `pkexec`. Este ANV15-52 anuncia quatro perfis. A ação saiu do desenho,
então o helper, a regra polkit, o `privileged.py` e o roteiro manual
perderam o objeto: nada chamaria as três operações.

O ganho da ação era um perfil que **este firmware não anuncia** (bitmap
`0x53`, sem o bit do Turbo — medido no log do kernel), e o custo era
trocar o conjunto de quirks inteiro, com efeito em capabilities e na
persistência de estado (armadilha 4). Com o cancelamento, **o projeto não
tem nenhum código rodando como root**, e some a dependência de `polkit`.

**Entra a Task 5b, o Painel revisado.** O desenho aprovado em
`docs/interface.md` mudou o Painel depois que a Task 5 já estava feita:

```
cartoes "Processador"/"Graficos"  ->  "CPU"/"GPU"
GPU: linha "Estado"               ->  linha "Modelo", lida do PCI
GPU adormecida                    ->  selo no titulo, valores em travessao
grafico: uma serie                ->  duas, com legenda e rotulo direto
```

Toca `telemetry.py` (nome da GPU pelo `pci.ids`), `dashboard.py` e
`graph.py`, com testes. **Não é estilo, é comportamento** — por isso é
tarefa própria e não entra na folha de estilo. Fica **depois da Task 10**,
junto com a estilização, para não reestilizar duas vezes.

#### O que a próxima sessão precisa saber antes de começar

**Uma dependência a instalar, no primeiro passo da Task 3:**

```bash
sudo -A pacman -S --needed --noconfirm python-pytest-qt
```

O `pyside6` e o `qt6-base` **já estão** instalados. Medido ao escrever o
plano: PySide6 6.11.2 e Qt 6.11.2, com `QDBusAbstractAdaptor` e
`ClassInfo` disponíveis, e o `org.kde.StatusNotifierWatcher` vivo nesta
sessão (kded6, com host no plasmashell). O SNI da spec é verificável aqui.

**A suíte roda offscreen.** `QT_QPA_PLATFORM=offscreen` entra no topo do
`conftest.py`, antes de qualquer import de Qt — o QPA é escolhido na
primeira carga do Qt e não muda depois.

**Três tarefas encostam no sistema e devem ser anunciadas antes:**

- **Task 8** instala nada, mas o roteiro manual pede um `pkexec` de
  verdade, com diálogo de senha;
- **Task 11** instala o Nexus Sense na máquina — sem remover nada;
- **Task 12 é a virada**, e é a única que desliga coisas. **A ordem dentro
  dela importa:** o `damx-daemon` sai no passo 5, o agente entra no passo
  6. Inverter põe os dois disputando o perfil térmico. O passo 7 precisa
  do cabo na mão: tirar, conferir que caiu para `balanced`, religar e
  conferir que **voltou** ao anterior.

**O ícone da bandeja usa quatro níveis:** o próprio N enche verticalmente,
de baixo para cima, com o contorno sempre visível. Ele tem a mesma altura
visual do Bluetooth. Há versões para tema claro e escuro.

O modo composto **Desempenho máximo** não acrescenta perfil ao firmware:
mantém `balanced-performance`, coloca o PPD em `performance`, mantém
`GPUPowerMizerMode=1`, inicia as ventoinhas no automático e permite trocar para
Máximo ou Manual sem o agente desfazer a escolha. O Dynamic Boost não é alterado.
Na bateria ele fica suspenso e volta quando a tomada é reconectada. O
ícone usa o N cheio em dourado suave, com variantes para os dois temas.

#### O que está instalado na máquina

Depois da virada, o estado é este:

```
/usr/bin/nexus-sense                    a interface
/usr/bin/nexus-sense-agent              o agente
/usr/lib/nexus-sense/nexus_sense/       o pacote Python
/usr/lib/nexus-sense/apply-perms.sh     chamado pela regra udev
/usr/lib/nexus-sense/verificar-dkms.sh  chamado pelo gancho do pacman
/etc/pacman.d/hooks/90-nexus-sense-dkms-check.hook
/usr/lib/systemd/user/nexus-sense-agent.service
/etc/xdg/autostart/nexus-sense-autostart.desktop
/usr/share/applications/nexus-sense.desktop
/usr/share/icons/hicolor/…              app + 4 níveis × 2 polaridades + máximo dourado
/etc/udev/rules.d/60-nexus-sense.rules
grupo nexus_sense (gid 950), com brunodobner dentro
/usr/src/nexus_sense-25.701
/etc/modules-load.d/nexus_sense.conf
/etc/systemd/system/nexus_sense.service
```

**O `damx-daemon` não existe mais**: parado, desabilitado, unit removida,
`/opt/damx` e o socket apagados. O agente está **ativo** com
`auto_switch = true`, e o botão N abre o `nexus-sense`.

Os cinco atributos graváveis de `nitro_sense` e o perfil térmico ficam em `664 root:nexus_sense` a cada
`add|change` do udev; `version` continua `444 root:root`.

**Não há mais nenhum processo root permanente, nem helper sob demanda.**

#### Verificações e correção do registro anterior

As chamadas DBus de scroll e clique do meio foram exercitadas. Isso não
comprova os gestos físicos nem o menu visível: o usuário informou que o
clique direito não mostra opções. A afirmação anterior de que esse menu
estava verificado foi incorreta.

Após o reboot da renomeação, somente o agente estava rodando. A entrada
`/etc/xdg/autostart/nexus-sense-autostart.desktop` havia sido removida por
`comprehensive_cleanup`. Foi restaurada da versão do repositório e a
bandeja foi iniciada manualmente. A configuração foi reparada; ainda falta
comprovar o início automático em uma nova sessão.

A correção do menu está instalada na máquina: SNI anuncia `/MenuBar`,
`GetLayout` responde com `u(ia{sv}av)` e o watcher registra um único Nexus
Sense. Os testes em sessão privada verificam ações repetidas, IDs estáveis
na bateria, fan auto/máximo, scroll, clique do meio e instância única.

**O início automático foi confirmado em 2026-09-12.** A bandeja do login de
2026-09-11 18:45 tem `systemd --user` como pai, foi iniciada às 18:45:46 — não
à mão — e detém `com.nexussense.NexusSense` no barramento de sessão, instância
única. A entrada `/etc/xdg/autostart/nexus-sense-autostart.desktop` está no
lugar.

**O gesto humano foi feito em 2026-09-12**, após reinício: o usuário clicou com
o botão direito no ícone e o menu abriu. Isso nenhum comando verifica — as
chamadas DBus provam que o menu está exportado, não que ele desenha na tela. Uma
afirmação anterior de que esse menu estava verificado foi incorreta, e por isso
a pendência só fechou com olho humano, não por dedução.

**A pendência está encerrada.**

O boot confirmou `nexus_sense`, banner 25.701 e modelo ANV15-52. DKMS
registra apenas o nome novo nos três kernels instalados. Unit e
`modules-load.d` usam o nome novo; permissões estão em `664 root:nexus_sense`.
As instruções de carregamento na GUI também foram corrigidas para
`sudo modprobe nexus_sense`.

**O buraco da escada, na bateria:**

```
low-power  --roda para cima-->  balanced      (pulou o quiet)
balanced   --roda para cima-->  balanced      (bal.-perf. barrado)
balanced   --roda para baixo->  low-power     (pulou o quiet)
```

E o pulo não é teimosia da interface: escrever `quiet` à força no sysfs,
com o cabo fora, devolve `EOPNOTSUPP` — "Operação sem suporte". É a
recusa do driver da spec §2.8, medida.

### Renomeação verificada; depois, fases B-G

A **renomeação para `nexus_sense`**, verificada após o reboot, está definida na §12 da spec da GUI:
módulo, grupo, instalador, unit e cinco testes. É fase própria porque toca
instalador e testes, não a GUI — os caminhos que a GUI usa passam por
`/sys/devices/platform/acer-wmi/` e são imunes ao nome do módulo.

As fases B-G estão na §3 da spec de melhorias. **Não têm plano escrito de
propósito.**

```
B. correcoes do driver           spec 4.1-4.3
C. reforma do instalador         spec 5
D. binarios e manifesto          spec 6   <- CANCELADA, ver abaixo
E. testes, shellcheck e CI       spec 8
F. enxugamento do driver         spec 4.4 <- por ultimo, com CI verde
G. documentacao                  spec 9
```

A **fase D perdeu o objeto**: não haverá binário a versionar nem manifesto a
manter. Ela é substituída pela spec da GUI e pela renomeação.

---

## A sessão de 2026-09-11/12, e onde ela parou

Catorze commits, `v1.1.2` → **`v1.1.6`**. Entrou por três pendências que o
`estado.md` listava e terminou com o driver a **36% menos linhas**.

```
driver         4734  ->  2912 linhas
pr_info          57  ->  33   (mais 11 pr_debug)
GUIDs             7  ->  4
interfaces        4  ->  1
parametros        9  ->  2
```

**Cada mudança de código foi ao hardware antes de ir para `master`:** ramo,
reinstalação por DKMS, recarga do módulo, portão medido, e só então merge. O
portão é o `capability bitmask` — `0x00002c26` do começo ao fim das quatro
mudanças — mais perfis, atributos, rfkill, hwmon e persistência de estado.

### O que fechou

| | |
|---|---|
| parâmetros inertes | `enable_all`, `predator_v4`, `nitro_v4` e os dois campos de quirk |
| classificação da poda | [poda-subsistemas.md](poda-subsistemas.md), camadas A/B/C/D |
| camada A | −641 linhas, prova de firmware (GUIDs ausentes) |
| camada B | −1077 linhas, prova de construção (quirk único) |
| log do kernel | ~50 linhas/minuto → zero em repouso |
| camada D | `ec_raw_mode`, `THREEG` e o poll de rfkill fora; `force_caps` mascarado |
| razão do modo máximo | [decisões 19](decisoes.md) |
| erro WMI | conta fechada em campo: 4h04, zero ocorrências |
| armadilha 25 | o bloqueio do wifi não gruda, e não é defeito nosso |

### Cinco coisas que só apareceram medindo

Vale mais do que a contagem de linhas, porque cada uma teria virado defeito:

1. **`acer_predator_state_load/save()` parecia morta pelo nome** e está viva
   pelo ramo `NITRO_SENSE` — é ela que preserva perfil e ventoinhas entre
   reinícios. Nome de função não é prova (armadilha 4).
2. **O turbo não morre pela capability apagada.** A chamada no tratador de
   eventos só olha `key_num`; o que a mata é a guarda *dentro* de
   `WMID_gaming_get_u64`. Guarda no sítio de chamada e guarda dentro da função
   provam coisas diferentes.
3. **`WMID_gaming_get_sys_info` quase foi junto**, por estar entre duas funções
   mortas. O `hwmon` a usa. O build apontou — como apontou as três dependências
   da camada A.
4. **`WMID_gaming_set_fan_mode()` parece o caminho das ventoinhas e não é.**
   Quem funciona é `acer_set_fan_speed()`, que chama `WMI_gaming_execute_u64`
   direto, sem checar capability.
5. **As duas estimativas de poda erraram por baixo** — A previa ~290 e saíram
   641; B previa ~765 e saíram 1077. Numa poda a estimativa é piso, não teto.

### A partida a frio, que fecha a conta

O reinício de **2026-09-12 04:11** foi a primeira partida do zero com toda a
poda aplicada. Tudo no lugar:

```
capability bitmask: 0x00002c26 [WIRELESS BLUETOOTH SET_FUNCTION_MODE
                                PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE]
perfis      low-power quiet balanced balanced-performance
perfil      balanced-performance      <- restaurado do estado salvo
atributos   os seis
rfkill      acer-wireless, acer-bluetooth
hwmon       presente
agente      ativo
bandeja     subiu sozinha; menu do botao direito confirmado pelo usuario
```

E o número que fecha a etapa do log: **20 linhas de kernel no boot inteiro** —
só o registro de carga, zero ruído. Antes seriam ~150 nos mesmos três minutos.

### Onde o próximo trabalho começa

**O roteiro não tem mais pendências.** As duas frentes abaixo são projetos
novos, independentes entre si, e nenhuma continua trabalho interrompido.

- **Gatilho por programa aberto** — pedido nesta sessão. **Começa por
  brainstorm**, não por código: o agente hoje não observa processos, decide só
  por fonte de energia num laço de 2 s. As seis perguntas de desenho em aberto
  estão na seção "Projeto futuro" deste arquivo, e duas delas são espinhosas: o
  que casar (um jogo por Proton aparece como `wine` ou `reaper`, não pelo nome) e
  quem ganha quando o usuário desliga à mão com o jogo ainda aberto.
- **Mainline** — o caminho que encerraria o fork. A poda ajudou: 2912 linhas,
  uma interface WMI, dois parâmetros, log limpo. A ordem sugerida e o que
  provavelmente não passa estão na seção "Projeto futuro: levar os atributos
  para o mainline". Sem data.

**O `rfkill` do wireless saiu desta lista.** Chegou a figurar como frente
aberta, com a armadilha 25 afirmando que o bloqueio se desfazia sozinho. Não
havia defeito: o que desfazia era o usuário religando o wifi à mão entre uma
medição e outra. Medido de novo em condição limpa — ciclo inteiro num comando
só, com o usuário fora do caminho — os dois sentidos funcionam e grudam. A
armadilha foi retratada.

### Uma coisa a não repetir

**Não rode `rfkill block` no `acer-wireless` desta máquina.** Não pelo driver —
ele está correto, e o bloqueio segura. É operacional: nas duas tentativas a
sessão do Claude Code caiu junto, **mesmo com rede cabeada como rota padrão**,
e foi preciso religar o wifi à mão para retomar a conversa.

Esse religar manual, entre uma medição e outra, foi o que criou a armadilha 25
inteira — um "fenômeno" que não existia. Ver a retratação lá.

**Para exercitar a escrita do rfkill, use o bluetooth.** Mesmo `set_u32`, mesmo
ramo — o `cap` é parâmetro —, e não derruba nem o fone conectado.

---

## Projeto futuro: gatilho por programa aberto

**Pedido em 2026-09-11. Precisa de plano próprio — não foi desenhado.**

Um bloco novo na tela **Desempenho**, onde o usuário registra programas que,
ao serem abertos, ativam o Desempenho máximo sozinhos. O modo passa a ter duas
formas de ligar: **manual**, como hoje, e **por gatilho**.

O que o pedido diz, literalmente:

- um bloco na tela Desempenho para registrar programas;
- o modo pode ser ativado manualmente **ou** por gatilho de programa aberto;
- o bloco precisa permitir **localizar o executável** e adicioná-lo à lista.

Isso encaixa na razão do modo (seção 19 de [decisoes.md](decisoes.md)): se ele
existe para jogos, ligar sozinho quando o jogo abre é o passo seguinte óbvio.

**Por que é plano próprio, e não um bloco de interface:** o agente hoje não
observa processos. Ele decide por fonte de energia, num laço de 2 segundos.
Detectar programa aberto é um subsistema novo, e as perguntas de desenho são
reais, não formalidade:

- **como detectar** — varrer `/proc` no mesmo laço de 2 s, ou algo com aviso
  (`cgroups`, `fanotify`)? Varrer `/proc` a cada 2 s é o caminho mais simples e
  o que já cabe no laço existente;
- **o que casar** — caminho absoluto do executável, nome do binário, ou linha
  de comando? Jogos por Steam e por Proton complicam: o binário visível pode
  ser `reaper` ou `wine`, não o jogo;
- **desligar quando fecha?** O pedido não diz. Ligar sozinho e não desligar
  sozinho é uma armadilha de uso; desligar sozinho pode cortar o modo no meio
  de um alt-tab;
- **quem ganha** quando o usuário desliga à mão com o jogo ainda aberto — a
  escolha manual tem de vencer o gatilho, senão o agente a desfaz em 2 s. É o
  mesmo problema que o setpoint de ventoinha já teve;
- **a regra da bateria continua acima de tudo:** na tomada o gatilho vale, na
  bateria o modo fica suspenso, gatilho ou não;
- **o seletor de executável** é `QFileDialog`, mas a lista precisa de formato
  no TOML, de remoção, e de decidir o que mostrar quando o caminho registrado
  deixa de existir.

Nada disso está decidido. **Chamar numa sessão nova**, começando por
brainstorm.

---

## Projeto futuro: levar os atributos para o mainline

**O caminho que encerraria o fork.** Decidido investir tempo nisso em
2026-09-11, sem data.

O `acer_wmi` do kernel já entrega perfis térmicos, leitura de ventoinha e
temperatura, rfkill e backlight. O que falta nele são os **atributos de
controle** — e é só por eles que este fork existe:

| | o nativo tem? |
|---|---|
| `fan_speed` (definir, não só ler) | ❌ |
| `battery_limiter` | ❌ |
| `usb_charging` | ❌ |
| `backlight_timeout` | ❌ |
| `battery_calibration` | ❌ |
| entrada DMI do ANV15-52 | ❌ |

Enviar esses para o mainline faria o driver deixar de ser manutenção sua: o
kernel passaria a carregá-lo sozinho, sem DKMS, sem blacklist, sem recompilar a
cada atualização de kernel. Ver [decisoes.md](decisoes.md) seção 6b para a
medição que sustenta este quadro.

**O que o trabalho envolve, sem romantizar:**

- é a lista `platform-driver-x86@vger.kernel.org`, com revisão pública e
  provavelmente várias rodadas
- o estilo do código teria de virar o do kernel (o fonte atual tem chaves em
  linha própria, comentários em português e `pr_info` em excesso)
- a decodificação por campos das armadilhas 3 e 3b é a parte mais defensável:
  conserta defeito real e vale para qualquer Acer, não só para este modelo
- o mesmo para as armadilhas 15 (`filp_open` devolve `ERR_PTR`) e 24
  (chamadas WMI sem serialização) — são bugs do upstream, não nossos
- o que provavelmente **não** passa como está: a entrada DMI de um modelo só,
  e o `predator_sense`/`nitro_sense` como grupo sysfs próprio em vez das
  interfaces padrão do kernel (`power_supply` para o limitador de bateria,
  `hwmon` `pwm*` para as ventoinhas)

**Ordem sugerida, do mais fácil de aceitar para o mais difícil:** primeiro as
correções de bug (15, 24, 3, 3b) como patches isolados contra o `acer-wmi`
atual; depois a entrada DMI do modelo; e só então os atributos de controle,
já traduzidos para as interfaces padrão.

---

## O erro WMI: o que está provado e o que não está

O `platform_profile: Failed to get profile for handler acer-wmi` aparecia
algumas vezes por hora. Diagnosticado e corrigido em 2026-09-11 (v1.1.1 e
v1.1.2), com dois mutexes — um para as chamadas, outro para as sequências.

**A evidência forte é o teste de estresse**, porque isola a variável:

| | leituras | erros |
|---|---|---|
| 200 sequenciais, antes | 200 | 0 |
| 8 leitores paralelos, antes | 2.400 | **2** |
| 8 paralelos, depois | 2.400 | 0 |
| 16 paralelos, depois | 6.400 | 0 |

Sequencial não reproduzir foi o que descartou "firmware instável" e apontou
concorrência.

**A conta foi fechada em campo.** A primeira observação, de 5 minutos, não
concluía nada — ficava abaixo do intervalo médio entre erros. Às 22:49 do mesmo
dia, com **4 horas e 4 minutos** de uso contínuo no mesmo boot:

```
$ journalctl -k -b | grep -c 'Failed to get profile'
0
```

Na taxa anterior (~4 por hora) seriam ~16 erros esperados nesse intervalo.
Zero. Somado ao teste de estresse, a correção está confirmada nas duas frentes.

Se o erro voltar algum dia, o próximo passo seria instrumentar
`WMID_gaming_get_misc_setting` para registrar qual dos dois caminhos de falha
disparou (erro da chamada, ou valor fora das cinco constantes).

---

## Pendências conhecidas

Coisas verdadeiras hoje que alguém pode estranhar:

- **As armadilhas 15 a 18 foram escritas em 2026-09-11**, recuperadas da spec
  de melhorias antes de ela ser apagada. A 15 documenta **um defeito vivo** no
  driver: guarda contra `NULL` depois de `filp_open`, mais um `filp_close`
  duplicado no mesmo bloco. **Corrigido em 2026-09-11**, com teste que
  reprova as duas regressões.
- **`SCRIPT_VERSION` e as versões foram alinhadas em `1.0.0`** e o
  `release.txt` do upstream foi removido — a pendência antiga sobre eles
  deixou de existir.
- **O bitmask de capabilities foi medido em 2026-09-11:** `0x2c26`
  (`WIRELESS BLUETOOTH SET_FUNCTION_MODE PLATFORM_PROFILE FAN_SPEED_READ
  NITRO_SENSE`). `acer_dump_capabilities()` o imprime no carregamento, e é o
  critério de regressão de qualquer poda futura. A pendência antiga — que
  bloqueava a fase F — deixou de existir, e a poda da tabela foi feita.
- **Os parâmetros `enable_all`, `predator_v4` e `nitro_v4` saíram em
  2026-09-11**, junto com os campos `predator_v4` e `nitro_v4` do
  `struct quirk_entry`. Com eles, `ACER_CAP_PREDATOR_SENSE` e
  `ACER_CAP_NITRO_SENSE_V4` viraram inalcançáveis por construção. **Atenção:**
  `acer_predator_state_load/save()` **não** morreu com isso — o caminho
  `nitro_sense` puro também a chama, e é ela que preserva perfil térmico e
  curvas de ventoinha entre reinícios (armadilha 4).
- **O log do kernel foi silenciado em 2026-09-12.** Em repouso o driver agora
  não escreve nada; antes eram ~50 linhas por minuto. A medição que guiou o
  corte: num boot de 8h44, **978 das ~1100 linhas** eram as três leituras de
  sondagem (`battery health query`, `backlight_timeout get status`,
  `usb charging get status`). Elas e as demais mensagens por-operação viraram
  `pr_debug`; tudo que é por-carga do módulo ficou em `pr_info`, inclusive o
  bitmask, que é o instrumento do portão da poda.

  **Para trazê-las de volta quando precisar** (`CONFIG_DYNAMIC_DEBUG=y` nesta
  máquina, conferido):

  ```bash
  sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null
  echo 'module nexus_sense +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
  # para desligar de novo: troque +p por -p
  ```
- **Os testes em shell são quase todos `grep` sobre o fonte.** É adequado ao
  propósito declarado — detectar o que a próxima release do upstream
  sobrescreveu — mas não verifica comportamento. A suíte Python nova, em
  `tests/python/`, é que verifica comportamento; ela roda sem hardware, sem
  root e sem laptop Acer.
- **As armadilhas 19 e 20 já estão escritas** — o índice instável do
  `hwmon` e o `nvidia-smi` que acorda a dGPU. As de número 15 a 18
  continuam reservadas pela fase G, e por isso a numeração salta.
- **Os quatro níveis do ícone foram redesenhados**, em duas polaridades.
  O N tem contorno completo e enche verticalmente; `balanced-performance`
  corresponde ao nível 4, totalmente preenchido.
- **Os dois testes que pulam, pulam por ambiente, não por defeito.**
  `test-perfil-bateria.sh` só roda na bateria e a máquina costuma estar na
  tomada; `test-permissoes.sh` precisa de um usuário **não**-root no grupo
  `nexus_sense`, então rodar a suíte inteira como root não o resolve — ele
  pula nos dois modos, por motivos opostos.
- **A cobertura do ramo GCC em `test-toolchain.sh` exige root.** Sem ele o
  teste cai nos kernels reais da máquina, que hoje são todos Clang, e
  anuncia a cobertura parcial. Com root, planta configs sintéticas em
  `/boot` e prova os dois ramos. Ver armadilha 22a.
- **`linux-headers` foi removido em 2026-09-10.** Era órfão: headers sem o
  pacote `linux` correspondente. O instalador agora pula kernels sem
  `vmlinuz`, então ele não fazia mal — saiu por higiene. Era também o único
  kernel GCC da máquina, o que motivou as configs sintéticas.

---

## Como trabalhar aqui

- **Ler `docs/armadilhas.md` antes de tocar** no driver, no instalador ou no
  build. São 17 armadilhas com sintoma, causa e comando de verificação;
  várias custaram horas. As mais recentes (22 e 23) saíram de uma
  instalação real: kernel cravado em teste apodrece sozinho num rolling
  release, e checagem de "já está feito" não pode ler cache que o próprio
  passo anterior invalidou.
- **Rodar as duas suítes:**
  ```bash
  python3 -m pytest -q        # inclui contrato DBus em sessao privada
  ./tests/run-all.sh          # sem root: 15 passam, 2 pulam
  sudo ./tests/run-all.sh     # inclui DKMS e os ramos sintéticos
  ```
- **Não editar os ícones à mão.** `bash packaging/icons/gerar.sh` os
  reproduz a partir de `packaging/icons/src/`; o `README.md` ao lado explica
  por que cada decisão, e várias são contra-intuitivas.
- **Medir, não supor.** Quase todo defeito real deste projeto apareceu por
  medição. Nesta sessão, três hipóteses minhas foram refutadas por medir —
  inclusive uma que teria arrancado o rfkill do wifi.
- **Root:** preferir `pkexec`, que abre o diálogo do polkit. Ele **não
  preserva o diretório corrente** — entrar de caminho absoluto:
  `pkexec /bin/bash -c "cd /home/brunodobner/Claude/Nitrosense; exec ./tests/run-all.sh"`.
  O caminho antigo (`SUDO_ASKPASS=~/.local/bin/claude-askpass sudo -A`)
  continua funcionando. Agrupar o trabalho com root em poucas chamadas.
- **Execução inline**, com pontos de conferência visíveis. Não usar
  subagentes sem pedido explícito.


### Correção PowerMizer — 2026-09-07

A implementação original usava subprocessos `nvidia-settings`. No driver
610.57.04, a escrita retornava sucesso, mas o pedido desaparecia ao encerrar
o cliente. NV-CONTROL indisponível no XWayland não prova recusa pela NVML.

O agente agora mantém `libnvidia-ml.so.1` aberta e verifica o pedido `1` pela
mesma conexão a cada passada. Ele restaura seu pedido anterior e encerra a
conexão na bateria, ao desligar o modo ou ao encerrar. GUI e bandeja salvam
somente a intenção para a GPU; a aplicação ocorre em até 2 segundos.

Um comando `nvidia-settings -q` separado continua podendo mostrar `0`, pois
consulta outro cliente. O journal do agente registra a confirmação da conexão
que mantém o pedido. Dynamic Boost continua independente e não foi alterado.
A mudança não promete frequência fixa nem ganho de FPS medido.

Validação instalada: seis leituras na GPU real mantiveram `1` por 12 segundos;
liberação voltou a `0`. Serviço instalado confirmou ativação e liberação no
journal em 2026-09-07 02:41. Código instalado comparado com o fonte, sem
diferenças. Suíte: 327 Python; 14 shell, 2 pulados. Suspensão por cabo foi
verificada com sysfs falso; não houve novo teste físico de desconexão.


### Sincronização bandeja/janela — 2026-09-07

Corrigida a marcação dupla no menu: com modo máximo ativo, o perfil térmico
subjacente não fica marcado. A atualização da bandeja também atualiza a janela,
inclusive após ações do menu, scroll e sondagem; reabrir a janela relê o estado.
Testes cobrem marcação única e sincronização nos dois sentidos: 329 passaram.

O reboot de 2026-09-07 confirmou a persistência do modo: configuração com
`maximum_mode = true`, agente iniciado com a sessão e
`GPUPowerMizerMode=1` confirmado no cliente NVML às 02:46:47.

As ventoinhas deixaram de ser travadas no automático pelo modo composto.
Ativar Desempenho máximo ainda começa em Automático; depois disso, Máximo e
Manual permanecem disponíveis e o agente preserva o setpoint escolhido.
