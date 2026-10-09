# Estado do projeto

Mapa de onde o trabalho está. As specs descrevem cada projeto; este arquivo
diz qual é a vez de qual, e o que ficou pendente.

**Última atualização:** 2026-10-09 (melhorias, etapa 3: v1.2.3 em `master`, portão passado, **falta conferir a partida a frio**; etapa 4 aberta)

---

## Onde estamos

| | |
|---|---|
| base | partiu do DAMX `1.0.2-h1` (commit `1f88341`) e seguiu sozinho; não rastreia mais o upstream |
| driver | **um modelo só**: 1 entrada DMI, 2 quirks, 1 interface WMI, 2 parâmetros, 3032 linhas (eram 5167) |
| versão | **v1.2.3** — `master` em github.com/brunodobner/nexussense (privado) |
| layout | reorganizado em 2026-09-10: só `setup.sh` executável na raiz |
| histórico | resetado na v1.0.0; a razão dos 111 commits foi para [decisoes.md](decisoes.md) e [armadilhas.md](armadilhas.md) |
| suíte shell | 20 testes: 18 passam, 2 pulam, 0 falham — **com e sem root** |
| suíte Python | 362 passaram (`python3 -m pytest -q`), incluindo DBus privado |
| build | `W=1` limpo sob Clang 23, nos dois kernels instalados |

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
[x] Reparo da bandeja                menu confirmado pelo usuario apos reinicio
[x] Aviso de DKMS no pacman          v1.1.9: falha de build grita em vez de silenciar
[-] Levar os atributos ao mainline   ABANDONADO em 2026-09-12; ver decisoes 21
[ ] Gatilho por programa aberto      bloco na tela Desempenho; precisa de plano proprio
[x] Melhorias, etapa 1 -- Python     v1.2.0: agente de 7,85% para 0,45% de um nucleo
[x] Melhorias, etapa 2 -- driver     v1.2.2: bitmask identico, partida a frio conferida
[ ] Melhorias, etapa 3 -- instalador v1.2.3 em master, portao passado; so falta a partida a frio
[ ] Melhorias, etapa 4 -- sobras     CI e hipoteses a medir; itens independentes
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
grupo nexus_sense (gid 948 desde 2026-10-09; era 950), com brunodobner dentro
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

## Melhorias de 2026-10, etapa 1 — e onde a etapa 2 começa

Uma avaliação do projeto inteiro em 2026-10-09 virou
[plano-melhorias.md](plano-melhorias.md): quatro etapas, uma por sessão. A
primeira, só Python, fechou na mesma sessão. **v1.1.9 → v1.2.0.**

O que ela entregou, medido na máquina:

| | antes | depois |
|---|---|---|
| agente, modo máximo, na tomada | 7,85% de um núcleo | **0,45%** (2,17 s em 481 s) |
| janela aberta, 30 s | 44,6% de um núcleo | **5,3%** |
| checagem do Diagnóstico | ~270 ms | 12 ms |
| suíte Python | 333 | 362 |
| suíte shell | 16 passam, 2 pulam | idêntica, linha a linha |

De onde vinha o custo: o agente perguntava o perfil ao `powerprofilesctl` a
cada passada — um script Python de 135 ms — e a janela chamava o `nvidia-smi`
dez vezes por segundo. Um virou `busctl` (3,9 ms), a outra passou a sondar uma
vez por segundo, por escolha do usuário.

E seis consertos de comportamento, cada um com teste que falhou primeiro:

- **sem o driver o agente espera** em vez de sair — sair virava laço, a unit o
  reabria a cada 3 s para sempre (reproduzido: 8 reinícios em 26 s);
- **`config.toml` gravado por troca atômica** — quem lia no meio da gravação
  recebia os padrões, sem erro;
- **religar o cabo abaixo de ~40% não perde o perfil guardado** — armadilha 27;
- **na bateria o perfil de CPU é devolvido uma vez**, não reimposto a cada 2 s;
- **falha persistente avisa uma vez**, não 43 200 vezes por dia;
- **uma releitura por clique**, e o cursor de ventoinha escreve quando para.

**O ensaio do cabo, registrado por um observador num comando só:**

```
 10,7s  cabo sai
 12,3s  perfil -> balanced            (guardado: balanced-performance)
 19,4s  usuario escolhe power-saver
        ... 40 s na bateria, e o power-saver FICA
 59,8s  cabo volta
 60,9s  perfil -> balanced-performance, ppd -> performance, GPU confirmada
```

### Quatro coisas que só apareceram medindo

1. **A primeira medição do agente valia por 40 segundos de 300.** O usuário
   desligou o modo máximo no meio dela, para abrir um jogo, e o número saiu
   bonito — 0,31% — medindo outra coisa. Só apareceu porque uma linha do
   journal não fechava com o resto. A medição seguinte confere a condição a
   cada 10 s e só conta o trecho em que ela se manteve. É a armadilha 25 por
   outro ângulo: havia uma pessoa na máquina, e ela não estava no modelo.
2. **O roteiro do limiar de 40% reportou "ACEITA" para uma escrita recusada.**
   `open().write()` só falha no `flush`, fora do `try`. Está na armadilha 27.
3. **O limiar de 40% não é o número do kernel.** O firmware recusou a 39% e
   aceitou 30 s depois, com o `capacity` ainda em 39.
4. **A tarefa 1.10 perdeu o objeto no meio do caminho.** Ela existia por causa
   dos 270 ms do Diagnóstico; depois da 1.1 eram 12. Saiu do plano.

### O que ficou visto e não consertado

- **A suíte chama o `nvidia-smi` de verdade 35 vezes por rodada**, medido com
  um comando-isca no `PATH`. Rodar os testes com a dGPU adormecida a acorda.
  Nenhum teste depende da resposta — os 362 passam com a isca. Está na etapa 4.
- **O caminho de abaixo de 40% não foi exercitado no hardware de ponta a
  ponta.** A recusa foi medida e a lógica está coberta por teste, mas no ensaio
  do cabo a bateria estava em 44%.
- **`maximum_saved_ppd` desta máquina vale `performance`.** Na bateria, com o
  modo máximo suspenso, é para esse valor que a CPU volta — é o que estava em
  vigor quando o modo foi ligado. Para mudar: desligar o modo, escolher o
  perfil de CPU desejado, religar.

### Onde a etapa 2 começou

Numa sessão nova, pelo driver. O que ela fez está na seção seguinte.

---

## Melhorias de 2026-10, etapa 2 — fechada, e onde a etapa 3 começa

A etapa do driver, no ramo `melhorias/2-driver`. **v1.2.0 → v1.2.1**, e na
mesma noite **v1.2.2**, com o que tinha ficado para depois. Tudo foi
ao hardware antes do merge, e a partida a frio foi conferida no mesmo dia — o
resultado está no fim desta seção.

O que entrou, cada item com teste que falhou primeiro:

| | conserto | prova na máquina |
|---|---|---|
| 2.1 | objeto nulo testado sozinho, antes da mensagem que lê dele | não há como provocar; o teste reprova o padrão |
| 2.2 | os quatro `_store` de um byte usam `kstrtou8` | `256` devolve `EINVAL` nos quatro e o valor fica; valor válido continua aceito |
| 2.3 | ventoinha e botão N sob `acer_op_lock`; o aviso ao núcleo sai fora da trava | 8 escritores, 480 escritas de ventoinha e perfil em 5 s: zero recusadas, par final inteiro, zero erro no kernel |
| 2.4 | o arquivo de estado é lido para um temporário e conferido antes de valer | três arquivos plantados — 12 bytes, ventoinha −5, perfil não anunciado — caem nos padrões e o log diz o motivo |
| 2.5 | rótulos no hwmon, `sysfs_emit`, log da ventoinha em `pr_debug`, 53 linhas comentadas fora | bitmask idêntico |
| extra | o botão N só avisa o núcleo se o perfil chegou a registrar | — ver o primeiro item abaixo |

**O portão**, medido em 2026-10-09 às 03:33, na tomada, bateria em 47%:

```
capability bitmask: 0x00002c26     identico nas 6 cargas do ensaio
perfis      low-power quiet balanced balanced-performance
atributos   os seis, 664 root:nexus_sense; version 444 root:root
rfkill      bluetooth bloqueia (1) e desbloqueia (0); wireless intocado
hwmon       presente, com rotulos: CPU, GPU, External 2 / CPU, GPU
estado      sobrevive a recarga: balanced-performance, ventoinha 0,0
estresse    16 leitores x 200 leituras, zero "Failed to get profile"
W=1         limpo sob Clang 23, em 7.2.9-1-cachyos e 6.18.55-1-cachyos-lts
suites      362 Python; shell 16 passam, 2 pulam -- identicas ao baseline
```

O módulo desse portão tinha `srcversion` `B530962B6CE5FDBCF23F2E9`. **O que
está carregado hoje é o da etapa 2b, `F9236711C6E76401FD38B7A`** — ver abaixo.

### Cinco coisas que só apareceram executando

1. **`W=1` não estava limpo em `master`.** O Clang 23 passou a acusar variável
   global escrita e nunca lida, e `platform_profile_support` era uma. Atrás do
   aviso havia defeito: se o registro do perfil falhasse, o botão N entregava um
   `ERR_PTR` a `platform_profile_notify`. Virou a guarda que faltava. O "`W=1`
   limpo" deste arquivo era de um compilador anterior — a afirmação envelhece
   com o toolchain, e o baseline da etapa tem de incluir o build.
2. **O portão reprovou duas vezes, e as duas eram do roteiro.** O índice do
   rfkill muda a cada recarga (armadilha 19b), e uma lista ordenada comparada
   com texto fixo depende do locale (armadilha 28). O segundo defeito era de
   `test-arvore.sh` e foi consertado: um CI tropeçaria igual.
3. **O diálogo de senha ficou 70 minutos aberto.** Nesse intervalo a bateria
   foi de 60% a 43% com o cabo ligado, e a guarda do roteiro — tomada, acima de
   45% — abortou antes de tocar em qualquer coisa. A condição se mede na hora de
   rodar, não na hora de pedir.
4. **Um comentário reprovou o teste que o protegia.** A explicação do conserto
   2.1 citava o padrão proibido entre aspas, e o `grep` o achou. Teste de
   `grep` sobre o fonte lê comentário também.
5. **O botão N não chega ao driver.** É a de baixo, e merece seção própria.

### O botão N: o que foi medido, e o que este arquivo dizia

A tarefa 2.3 mexeu no caminho do botão N — `acer_thermal_profile_change` — e a
única forma de exercitá-lo é o dedo. Três ensaios, 16 apertos ao todo, cada
aperto confirmado pelo KDE no journal (`Started Nexus Sense - Controle do
laptop`):

```
5 apertos, com um escritor regravando o perfil     nenhum travamento, ~200 escritas/s
3 apertos, ninguem escrevendo                      o perfil nao mudou
8 apertos, com o pr_debug do driver ligado         0 linhas "botao N: key_num"
```

O terceiro fecha a questão. A sonda foi provada antes — ler `usb_charging`
produziu o `pr_debug` esperado, então o silêncio não é teste por vácuo
(armadilha 14). **O evento WMI não chega: nesta máquina, hoje, o botão N só
existe como tecla** (`0xf5` → `prog1` → atalho do KDE).

Isso contradiz a seção 19 de [decisoes.md](decisoes.md) e o comentário no
tratador de eventos do driver, que dizem que o botão dispara
`WMID_GAMING_TURBO_KEY_EVENT` e percorre os perfis. O BIOS é o mesmo desde
antes (V1.52, de 2025-12-26). **Não se sabe se o evento algum dia chegou neste
modelo ou se a afirmação foi inferência** — o journal desta máquina só guarda o
boot corrente, e não há como conferir o de setembro.

Consequências:

- **não é regressão desta etapa.** O ponto por onde o evento entraria,
  `acer_wmi_notify`, não foi tocado, e é lá que fica o `pr_debug` que não
  apareceu;
- **a ordem de travas do botão N está provada por leitura e pelo teste
  estático, não por hardware.** Não há como prová-la aqui: o caminho não roda;
- `cycle_gaming_thermal_profile` e a decisão de mantê-lo ("botão em uso", em
  [poda-subsistemas.md](poda-subsistemas.md)) ficam sem objeto se o evento de
  fato nunca chega. **Não mexer por isso sozinho:** é hipótese a fechar na
  etapa 4, com o `pr_debug` ligado na bateria e na tomada, antes de podar.

Uma coisa para não repetir: no segundo ensaio o perfil foi a `low-power` e
voltou, e por alguns minutos isso pareceu o botão funcionando. Era o app —
`config.toml` foi gravado no mesmo décimo de segundo. É a armadilha 25 de novo:
havia uma pessoa clicando na janela que o próprio aperto abre.

### Etapa 2b, na mesma noite — os três que tinham ficado para depois

A primeira versão desta seção listava três defeitos vistos e não consertados. O
usuário perguntou como consertá-los e mandou fazer antes do reinício: assim uma
partida a frio confere tudo. Ramo `melhorias/2b-driver`, **v1.2.1 → v1.2.2**.

| | conserto | prova na máquina |
|---|---|---|
| leitor do par | `predator_fan_speed_show` sob `acer_op_lock` | 753 leituras de `fan_speed` no meio de 8 escritores: zero pares misturados |
| estado | `acer_predator_state_load` e `_save` sob a mesma trava | oito cargas do módulo sem travar; os três arquivos plantados de novo |
| bateria | `battery_health_set` trata `uReturn != 0` como recusa, sem pedir ajuda ao byte reservado | a amostra abaixo |

**A trava no `probe` não contradiz a armadilha 24.** O que ela proíbe é travar o
`probe` inteiro: os registros de rfkill, platform_profile e hwmon chamam o
driver de volta. A restauração de estado fica depois deles e só fala com o
firmware e com o arquivo.

**A condição da bateria foi trocada com amostra, não por leitura** (armadilha
3b). Um `pr_debug` novo imprime os quatro bytes crus do retorno; a regra foi
escrita antes de medir — só trocar se toda escrita que vale devolver `uReturn`
zero:

```
battery_limiter     <- 1   aceito, lido 1   retorno 00 00 00 00
battery_limiter     <- 0   aceito, lido 0   retorno 00 00 00 00
battery_limiter     <- 1   aceito, lido 1   retorno 00 00 00 00
battery_calibration <- 0   aceito, lido 0   retorno 00 00 00 00
```

Repetido depois da troca, com o mesmo resultado: nenhuma escrita válida virou
recusa. **Não há amostra de recusa** — pelo sysfs só chegam 0 e 1, e o firmware
aceita os dois. Se um dia aparecer `Failed to set battery health status: 0x..`
no log, o código que vier ali é a amostra que falta.

Dois portões: o completo sobre o build com as travas (**65 OK, 0 FALHA**, suíte
shell como root 16 passam e 2 pulam, já com `LC_ALL=C`), e um curto sobre o
build final, que só difere daquele por essa condição (**34 OK, 0 FALHA**).

### Visto e não consertado

- **`dkms status | grep -q`** no instalador e nos testes deixa `echo: write
  error: Broken pipe` na saída. Ruído, não defeito; é assunto da etapa 3.
- **O que `temp3` mede não foi apurado.** O rótulo é o nome que o firmware dá
  ao sensor, `External 2`.
- **A ordem de travas do botão N continua sem prova de hardware**, pelo motivo
  da seção acima: o evento não chega.

### A partida a frio, que fecha a etapa

Conferida em 2026-10-09 às 19:01, onze minutos depois de um reinício. E não foi
uma só: o módulo final já tinha passado por **três** partidas do zero — 04:44,
16:53 e 18:50 — e as três dizem a mesma coisa.

```
capability bitmask: 0x00002c26 [WIRELESS BLUETOOTH SET_FUNCTION_MODE
                                PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE]
srcversion  F9236711C6E76401FD38B7A   <- o do build final
perfis      low-power quiet balanced balanced-performance
perfil      balanced-performance      <- restaurado do estado salvo
estado      "Thermal states loaded" nas tres; nenhum "Invalid" nem "Incomplete"
atributos   os seis, 664 root:nexus_sense; version 444 root:root
hwmon       acer: CPU, GPU, External 2 / ventoinhas CPU, GPU
rfkill      acer-wireless, acer-bluetooth  (de volta aos indices 0 e 1)
erro WMI    zero "Failed to get profile"
agente      ativo
bandeja     subiu sozinha, filha do systemd do usuario, 12 s depois do boot
botao N     hwdb com f5=prog1 e autostart no lugar
```

**O par que fecha a 2.4 e a 2b de uma vez:** `Thermal states saved successfully`
às 18:50:19, no desligamento, e `Thermal states loaded` às 18:50:37, na partida.
É o validador lendo um arquivo gravado por um desligamento de verdade — e a
gravação e a leitura já rodando sob `acer_op_lock`, sem travar nenhuma das duas.

Dezesseis linhas do driver no boot inteiro, todas de carga. Uma delas contém a
palavra `failed` e não é defeito: `module verification failed: signature and/or
required key missing` é o kernel avisando que o módulo não é assinado, como
todo módulo de DKMS. Já estava no boot de 2026-10-08, com o driver antigo.

De passagem, o número da etapa 1 se manteve em campo: no boot das 04:44 o agente
gastou 2 min 29 s de CPU em 12 h 08 min — **0,34% de um núcleo**.

### Onde a etapa 3 começa

Numa **sessão nova**, pelo instalador: seção 5 de
[plano-melhorias.md](plano-melhorias.md). Nada pendente da etapa 2 a bloqueia.

**Ponto de partida:** `master` em v1.2.2. O baseline esperado é 362 na suíte
Python e, na shell, 16 passam e 2 pulam — sem root, com root e sob `LC_ALL=C`.
Se o capturado no começo da sessão for outro, a diferença é notícia.

**O que a etapa 2 viu no instalador e deixou para a 3**, lido no `setup.sh`:

- **`dkms status ... | grep -q installed`** em `install_drivers` e em
  `test-install-drivers.sh`. O `grep -q` sai no primeiro acerto e o `dkms`
  reclama: `echo: write error: Broken pipe`. Com `grep installed > /dev/null`
  some — foi assim no portão curto da 2b.
- **`install_nexus_sense` diz "Usuário … adicionado ao grupo" toda vez**, e "o
  grupo só vale depois de relogar", mesmo com o usuário já dentro: o `usermod
  -aG` e a mensagem não perguntam antes. A 3.4 mexe em `detect_desktop_user`,
  que alimenta esse trecho.
- **O grupo é criado com `groupadd -r`, sem gid fixo.** Hoje é 950. A decisão D5
  manda a desinstalação apagá-lo, e o portão da etapa 3 desinstala e reinstala
  na mesma chamada: se o gid recriado for outro, a sessão em curso — agente e
  bandeja inclusive — fica sem poder escrever nos atributos até relogar. **Medir
  o gid antes e depois**, e não contar com escrita sem root entre a reinstalação
  e o reinício.

**O que vale para o roteiro do portão**, e custou duas reprovações falsas na
etapa 2:

- índice de `rfkill` e de `hwmon` se procura pelo nome, na hora de usar
  (armadilhas 19 e 19b) — a 3.6 recarrega o módulo dez vezes;
- `LC_ALL=C` só na frente do comando que precisa, não em `export` (armadilha 28);
- a condição que o roteiro exige se mede quando ele roda, não quando se pede a
  senha: o diálogo do `pkexec` já ficou 70 minutos aberto;
- o scratchpad é tmpfs e a etapa termina em reinício: o que o portão mediu vai
  para este arquivo **antes** de reiniciar;
- dizer no chat quando um diálogo de senha ou um gesto está sendo esperado. Uma
  notificação sozinha passou despercebida.

**Para a 3.3**, que tira o serviço root de tecla: o caminho que fica foi
exercitado 16 vezes na etapa 2 — o botão N chega como tecla, o hwdb a traduz em
`prog1` e o atalho do KDE abre o app. Cada aperto aparece no journal do usuário
como `Started Nexus Sense - Controle do laptop`, o que serve de sonda sem root.

---

## Melhorias de 2026-10, etapa 3 — portão passado, falta a partida a frio

A etapa do instalador, no ramo `melhorias/3-instalador`. **v1.2.2 → v1.2.3.**
O baseline capturado antes da primeira edição conferiu com o esperado: 362 na
suíte Python; shell 16 passam e 2 pulam, idêntico sob `LC_ALL=C`.

O que entrou, cada item com teste que falhou primeiro:

| | conserto | prova |
|---|---|---|
| 3.1 | lançadores com `python3 -P` | medido antes: os dois importavam um `tomli_w.py` plantado no diretório corrente. Depois, os lançadores **instalados**, rodados como usuário de dentro do diretório plantado, respondem `1.2.3` e não o importam |
| 3.2 | `cleanup_nexus_sense` desfaz `install_nexus_sense` item por item | varredura depois da limpeza: nada. `~/.config/nexus-sense` ficou |
| 3.3 | saem `configure_nitro_button`, `install_nitro_service` e o `nitro-key-detection.sh` | −338 linhas; a limpeza do serviço antigo ficou |
| 3.4 | `detect_desktop_user` consulta `PKEXEC_UID` e recusa uid abaixo de 1000 | com as fontes trocadas por funções, a versão antiga devolvia `sddm` em 10 de 11 casos; sob o `pkexec` do portão devolveu `brunodobner` |
| 3.5 | sai `nvidia-settings`; no Arch, headers pelo `pkgbase` de cada kernel bootável | nesta máquina deriva `linux-cachyos-headers` e `linux-cachyos-lts-headers`, e os dois existem no repositório |
| 3.6 | a regra udev do dispositivo dispara também em `bind` | ver abaixo |
| extra | "adicionado ao grupo" e "só vale depois de relogar" só quando acontece | no portão completo o grupo foi recriado e ele disse; no curto o usuário já estava dentro e ele disse isso |
| extra | `dkms status` lido até o fim, sem `grep -q` | como root: forma antiga 20 de 20 com `Broken pipe`, forma nova 0 de 20 |
| extra | a reinstalação preserva o grupo; sai o atalho morto do `damx.desktop` | achados do portão — ver abaixo |

**Dois portões**, os dois na tomada, bateria em 80%, agente e bandeja parados
antes. O completo (19:25:52 a 19:26:53) desinstalou tudo e reinstalou na mesma
chamada de root, como o plano manda. O curto (19:31:39 a 19:32:03) refez só o
caminho de reinstalação, depois dos dois consertos que o primeiro motivou.

```
portao completo   57 OK, 1 FALHA, 3 NOTA   sobre a73fc58
portao curto      40 OK, 0 FALHA, 0 NOTA   sobre c0ba977
```

O que os dois mediram:

```
limpeza       varredura estendida: nenhum arquivo; nenhuma unit de sistema nem
              de usuario; grupos nexus_sense e linuwu_sense removidos; atalho
              removido; acer_wmi nativo assumiu; DKMS sem registro
instalacao    perform_install devolveu 0; pacote identico ao fonte; regra udev,
              unit, .desktop, autostart, gancho do pacman e scripts identicos
              ao repositorio; 75 icones; enable global do agente no lugar
driver        srcversion F9236711C6E76401FD38B7A (o mesmo: driver intocado)
              DKMS installed em 7.2.9-1-cachyos e 6.18.55-1-cachyos-lts
              bitmask 0x00002c26 nas 32 cargas do completo e nas 4 do curto
              zero mensagem de erro do kernel nos dois
permissoes    os seis 664 root:nexus_sense; version 444 root:root
rfkill        acer-wireless=0 acer-bluetooth=0 antes, com o nativo, e depois
suite root    master: 16 passam, 2 pulam. Ramo: 18 passam, 2 pulam -- a
              diferenca sao os dois testes novos. Identica sob LC_ALL=C
```

**A tarefa 3.6, medida.** A ordem dos eventos numa recarga, vista do kernel:

```
2160.547403  add   /devices/platform/acer-wmi                    (platform)
2160.561275  add   .../platform-profile/platform-profile-0       (platform-profile)
2160.576431  bind  /devices/platform/acer-wmi                    (platform)
```

O `bind` sai 29 ms depois do `add`, e é nesse intervalo que o `probe` cria os
atributos. Três séries de dez recargas, cada uma com uma regra só instalada:

```
A  so add     10 de 10 com permissao certa
B  so bind    10 de 10
C  final      10 de 10     (add|change|bind)
```

**A corrida nunca perdeu nesta máquina** — a série A deu dez de dez. O plano
dizia "ganha por margem" e a medição confirma a margem, não uma falha. O `bind`
é robustez: é o evento que vem depois do `probe` por construção, e a série B
prova que ele basta sozinho.

**O que a armadilha 21 manda, conferido antes do reinício** (19:32, estado
final, depois do portão curto):

```
autostart     /etc/xdg/autostart/nexus-sense-autostart.desktop identico ao do
              repositorio
botao N       banco hwdb recompilado responde KEYBOARD_KEY_f5=prog1; teclado
              (event3) com prog1 depois de reaplicar o udev; atalho do KDE
              "Launch (1)" em [services][nexus-sense.desktop]
```

### Sete coisas que só apareceram executando

1. **O gid do grupo mudou: 950 → 948.** Eu tinha previsto 950 — "951 a 999
   estão ocupados" — supondo que o `groupadd -r` pegasse o primeiro livre. Ele
   pega o menor em uso e desce um (949 é o `seat`). A sessão em curso ficou com
   o 950 solto e sem escrita nos atributos. E não era acidente do portão: a
   limpeza roda antes de **toda** reinstalação, então cada uma trocaria o gid.
   O grupo agora só sai em `uninstall`. Armadilha 29.
2. **O roteiro reprovou uma instalação certa.** Ele cobrava o arquivo
   `61-damx-nitro-key.hwdb`. O systemd 262 passou a trazer `pnNitro*ANV*15-52`
   no `60-keyboard.hwdb` dele; o instalador achou `prog1` no banco recompilado
   e, com razão, não gravou nada. `/etc/udev/hwdb.d/` está vazio e vai
   continuar. A conferência é pelo banco — armadilhas 21 e 23, atualizadas.
3. **Havia um atalho morto no KDE.** `[services][damx.desktop]` com
   `_launch=Launch (1)`, do instalador da linhagem antiga: mesma tecla do
   atalho vivo, apontando para um `.desktop` que não existe. O
   `unbind_button_from_nexus` passou a tratar as duas entradas.
4. **A varredura da armadilha 8 era cega para este projeto.** Procura `damx`,
   `linuwu` e `divacer`, e o `-maxdepth 4` não desce até os ícones. Teria
   voltado vazia com o aplicativo inteiro no disco. E grupo não é arquivo: o
   `linuwu_sense` (gid 1001) sobreviveu um mês à renomeação, com o usuário
   dentro. A armadilha ganhou a varredura estendida.
5. **O `Broken pipe` só existe como root.** Sem root, 0 de 40 tentativas; como
   root, 20 de 20. O conserto entrou antes da prova e a prova veio no portão —
   se ela tivesse dado zero também como root, o commit descreveria um defeito
   que eu não vi.
6. **Dois commits entraram sem a suíte inteira rodada.** `9c42cf4` e `79238b6`
   deixaram `test-instalacao-nexus.sh` vermelho: o comentário novo citava o
   `pkexec` e a guarda contra polkit lia comentário. Consertado em `0a82767`,
   e a guarda agora lê só código. É a lição 4 da etapa 2, de novo — e a regra
   que ficou: a suíte inteira antes de cada commit, não só o teste da tarefa.
7. **A versão subiu antes do portão, não no merge.** `__version__` viaja dentro
   do pacote instalado; subir no merge deixaria o instalado diferente de
   `master` por uma linha.

### Visto e não consertado

- **A desinstalação não encerra o agente nem a bandeja que estiverem
  rodando.** São processos da sessão; o `--global disable` só impede que voltem
  na próxima. Encerrá-los na limpeza os tiraria também de quem reinstala.
- **A fiação nova da remoção do grupo não foi ao hardware.** O `groupdel` rodou
  no portão completo, de dentro da limpeza. Depois ele mudou de lugar —
  `cleanup_nexus_group`, chamada por `uninstall` — e isso está provado por
  teste estático. Rodar `uninstall` de novo trocaria o gid outra vez.
- **`runtime_dependencies_ok` ainda pergunta por `powerprofilesctl`**, que o
  código não chama desde a etapa 1 (é `busctl`). Hoje serve de indício de que o
  daemon está instalado; numa distro em que outro pacote fornece a mesma
  interface DBus, o indício falha.
- **`install_build_deps` só roda quando falta `make` ou `dkms`.** Com as
  ferramentas presentes e os headers de um kernel faltando, ninguém os instala:
  `check_kernel_headers` avisa e segue. A 3.5 consertou *quais* headers pedir,
  não *quando*.
- **`is_llvm_kernel` olha o kernel em execução** para decidir se instala
  `clang` — a armadilha 2, no instalador. O build em si já decide por
  kernel-alvo; isto só afeta quais pacotes são pedidos.
- **`shellcheck` não está instalado nesta máquina**, e `test-setup-deps.sh`
  pula essa parte. O CI da etapa 4 é quem vai rodar.

### O estado da máquina, e a partida a frio que falta

**A máquina está com a v1.2.3 instalada**, do commit `c0ba977` — o que veio
depois dele em `master` é só documentação. Três coisas estão diferentes do
normal, e as três se resolvem no reinício:

- **agente e bandeja estão parados**, de propósito, desde 19:25;
- **a sessão aberta antes do portão não escreve nos atributos**: ela carrega o
  gid 950 e o grupo agora é 948. Sem root a suíte dá 17 passam e 3 pulam —
  `test-permissoes.sh` pula com "sessão fora do grupo";
- **o perfil térmico foi devolvido à mão** para `balanced-performance`: a
  limpeza apaga `/etc/predator_state`.

A etapa só se dá por fechada depois disto, conferido na **sessão seguinte**:

```
modulo       nexus_sense carregado; srcversion F9236711C6E76401FD38B7A;
             capability bitmask 0x00002c26
estado       "Thermal states loaded"; perfil balanced-performance
permissoes   os seis 664 root:nexus_sense, gid 948; version 444 root:root
sessao       id mostra 948(nexus_sense), sem 950 nem 1001 soltos
agente       ativo; linha de comando com "python3 -P -m nexus_sense"
bandeja      subiu sozinha, filha do systemd do usuario; tambem com -P
botao N      systemd-hwdb query responde f5=prog1; um aperto aparece no
             journal do usuario como "Started Nexus Sense - Controle do laptop"
atalho       grep -n damx ~/.config/kglobalshortcutsrc  -> vazio
suites       362 Python; shell 18 passam, 2 pulam, sem root
```

Uma dessas linhas é aposta e não certeza: **o atalho do `damx.desktop`**. Ele
foi apagado do arquivo com o `kglobalacceld` rodando, que o tinha lido no login.
Se o daemon regravar o arquivo ao sair, a entrada volta — e aí a remoção tem de
passar pelo DBus dele, não pelo `kwriteconfig6`. O atalho vivo não corre esse
risco: foi apagado e reescrito com o mesmo valor.

### Onde a etapa 4 começa

Depois da partida a frio. Seção 6 de [plano-melhorias.md](plano-melhorias.md):
itens independentes, cada um recusável sozinho. O CI entra primeiro — pytest e
shellcheck a cada push pegariam o item 6 acima antes do commit. O que esta etapa
viu e deixou está na lista "Visto e não consertado", logo acima.

---

## A sessão de 2026-09-11/12, e onde ela parou

Vinte e nove commits, `v1.1.2` → **`v1.1.9`**. Entrou por três pendências que o
`estado.md` listava e terminou com o driver a **38% menos linhas**, o roteiro
sem nenhuma pendência e uma decisão de escopo tomada.

```
driver         4734  ->  2912 linhas
pr_info          57  ->  33   (mais 11 pr_debug)
GUIDs             7  ->  4
interfaces        4  ->  1
parametros        9  ->  2
```

**Cada mudança de código foi ao hardware antes de ir para `master`:** ramo,
reinstalação por DKMS, recarga do módulo, portão medido, e só então merge. O
portão é o `capability bitmask` — `0x00002c26` do começo ao fim de **todas** as
mudanças, inclusive na partida a frio do fim — mais perfis, atributos, rfkill,
hwmon e persistência de estado.

### O que fechou

| | |
|---|---|
| parâmetros inertes | `enable_all`, `predator_v4`, `nitro_v4` e os dois campos de quirk |
| classificação da poda | [poda-subsistemas.md](poda-subsistemas.md), camadas A/B/C/D |
| camada A | −641 linhas, prova de firmware (GUIDs ausentes) |
| camada B | −1077 linhas, prova de construção (quirk único) |
| log do kernel | ~50 linhas/minuto → zero em repouso |
| camada D | `ec_raw_mode`, `THREEG` e o poll de rfkill fora; `force_caps` mascarado |
| bandeja | menu do botão direito confirmado após reinício — a última pendência |
| aviso de DKMS | gancho do pacman: falha de build grita em vez de silenciar |
| mainline | **abandonado por decisão**, ver [decisões 21](decisoes.md) |
| razão do modo máximo | [decisões 19](decisoes.md) |
| erro WMI | conta fechada em campo: 4h04, zero ocorrências |
| armadilha 25 | o bloqueio do wifi não gruda, e não é defeito nosso |

### Seis coisas que só apareceram medindo

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
6. **A armadilha 25 descrevia um fenômeno que não existia.** O "bloqueio do wifi
   que não grudava" era o usuário religando o rádio entre uma medição e outra,
   para recuperar a conexão. Três revisões até admitir. Entre a ação e a medição
   havia uma pessoa, e ela não estava no modelo — quando a medição depende de
   duas leituras separadas no tempo, faça tudo num comando só.

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

**O roteiro não tem mais pendências, e sobrou uma única frente** — um projeto
novo, que não continua trabalho interrompido.

- **Gatilho por programa aberto** — pedido nesta sessão. **Começa por
  brainstorm**, não por código: o agente hoje não observa processos, decide só
  por fonte de energia num laço de 2 s. As seis perguntas de desenho em aberto
  estão na seção "Projeto futuro" deste arquivo, e duas delas são espinhosas: o
  que casar (um jogo por Proton aparece como `wine` ou `reaper`, não pelo nome) e
  quem ganha quando o usuário desliga à mão com o jogo ainda aberto.
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

## Abandonado: levar os atributos para o mainline

**Decidido em 2026-09-12 não fazer.** O raciocínio inteiro — o que se ganharia,
o custo real, e por que o arranjo atual já trata a dor que isso curaria — está
em [decisões 21](decisoes.md). O `nexus_sense` continua, e a escolha foi
informada: veio depois de entender por que o fork existe.

A seção 6b de [decisoes.md](decisoes.md) guarda a medição que sustenta o quadro:
o `acer_wmi` nativo entrega perfis térmicos, telemetria, rfkill e backlight, mas
**zero dos nove atributos de controle**, e não reconhece o ANV15-52.

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
