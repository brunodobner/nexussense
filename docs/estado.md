# Estado do projeto

Mapa de onde o trabalho está. As specs descrevem cada projeto; este arquivo
diz qual é a vez de qual, e o que ficou pendente.

**Última atualização:** 2026-10-17 (a curva própria é o Automático, juntada, enviada e instalada; os ensaios a pausam; o README revisto)

---

## Feito: a curva própria da ventoinha (2026-10-15 a 2026-10-17)

**No `master`, no GitHub e instalada.** A curva é o Automático neste modelo
desde 2026-10-16; para voltar ao firmware, `fan_curve = false` no
`config.toml`. O que segue é o registro, na ordem em que aconteceu: as
primeiras linhas falam de um ramo ainda não juntado, e cada uma vale para o
seu momento.

- **Feito e verificado:** os modos de ensaio E-C2, E-C3 e E-C5 em
  `tests/hardware/ensaio-termico.sh` (commit `bd67182`, suíte verde); a curva
  aprovada pelo usuário, com as duas tabelas, em
  [plano-curva.md](plano-curva.md), seção 11 (`ba10573`).
- **O guarda, feito e verificado** (plano-curva, seção 8, no fim):
  `packaging/scripts/guarda-ventoinha.sh` (ExecStopPost),
  `src/nexus_sense/guarda.py` (sd_notify e o registro), a unit com
  `Type=notify`, `WatchdogSec=6`, `WatchdogSignal=SIGKILL` e
  `RuntimeDirectory`, e o `setup.sh` instalando o guarda. Suítes de depois:
  pytest 513 (501 + 12 novos); shell igual à baseline — a única diferença,
  `test-perfil-bateria.sh`, pula na tomada e roda na bateria.
- **A curva, versão curta, escrita e testada** ([plano-curva.md](plano-curva.md),
  seção 11, no fim): `src/nexus_sense/curva.py`, ligada no agente por
  `fan_curve = true` no `config.toml`, sem botão na janela por enquanto.
- **Na máquina:** a primeira rodada achou o sobe-desce (a CPU pelo EC pula com
  carga em rajadas), corrigido com a mediana de 10 s e a descida de 4 pontos
  por passada (`49f5320`). Na segunda, dois minutos com carga: subiu a ~7.100
  rpm, desceu a ~2.700 em 30 s sem tranco, ignorou os pulos, e o agente não
  foi morto pelo watchdog nenhuma vez.
- **A janela não sabe da curva:** com ela ligada, mostra Manual com os números
  que a curva escreveu. "Automático" na janela devolve a ventoinha à curva.
- **E-C5 na máquina, duas tentativas** ([plano-curva.md](plano-curva.md),
  seção 11, no fim): achou que o watchdog mata o agente a cada suspensão, e
  que na volta da suspensão o firmware larga o manual e troca o perfil para
  `balanced`, com o `fan_speed` ainda dizendo o manual.
- **A bandeja de antes da instalação apagava `fan_curve`** ao gravar o
  `config.toml` (o processo antigo não conhecia o campo). Reiniciada às
  07:28 de 2026-10-16. Corrigido nas duas pontas (armadilha 44): o
  `config.save` preserva as chaves que não conhece, e o `setup.sh` faz
  `try-restart` do agente e da bandeja ao instalar.
- **Os ajustes da suspensão, escritos** (plano-curva, seção 11, no fim):
  o agente alarga o watchdog antes de dormir, devolve o perfil e reescreve o
  manual ao acordar, e o E-C5 registra a troca em vez de parar.
- **O E-C5 na máquina, menos o reinício:** só a suspensão faz o firmware
  largar o manual (cabo e perfil não); o agente atravessa a suspensão vivo e
  devolve o perfil; o guarda devolve `0,0` em 105 ms no `kill -9` e em 5,0 s
  com o agente travado. O defeito do aviso de dormir era o buffer do
  `busctl` num pipe (`stdbuf -oL`, `5d682c6`).
- **O reinício do E-C5:** com o manual registrado como o da curva, o guarda o
  devolveu no desligamento no mesmo segundo em que o driver gravou o estado,
  e a partida voltou no automático. O E-C5 está completo.
- **A curva ficou ligada** depois do reinício (`fan_curve = true`).
- **Juntado ao `master`** (`2b1ea62`) e enviado ao GitHub.
- **As armadilhas da curva escritas** em [armadilhas.md](armadilhas.md),
  41 a 44: o `busctl` num pipe, o watchdog que conta o sono, o firmware que
  larga o manual ao acordar, e o processo antigo que apaga campo novo.
- **Decidido pelo usuário (2026-10-16): a curva vira o próprio
  Automático**, sem botão novo. Ligada desde a instalação; a janela mostra
  Automático enquanto ela manda; o automático do firmware fica para a
  bateria, os perfis silencioso e econômico, e o agente parado (o guarda).
- **Implementada no ramo `curva/padrao`** (de `curva/armadilhas`), não
  juntada nem instalada ([plano-curva.md](plano-curva.md), seção 11, no fim):
  sem `fan_curve` no config a curva vale no `Nitro ANV15-52` e só nele; a
  janela mostra Automático enquanto ela manda e diz quem decide; Manual sem
  mexer nos cursores vale, porque a janela apaga o registro da curva.
- **Juntados ao `master`** (`d0a2d08`), enviados ao GitHub e instalados em
  2026-10-17; o instalador reiniciou o agente e a bandeja sozinho.
- **Achado na conferência:** o cartão Ventoinhas do Painel dizia "manual"
  com a curva mandando. Corrigido no ramo `curva/painel`.
- **`curva/painel` juntado** (`23cdf53`), enviado e instalado. Na
  conferência o usuário viu tudo funcionando e pediu só texto: o cartão
  Ventoinhas do Painel diz o nome do modo, sem explicar, e mostra "máximo"
  no `100,100` (ramo `curva/painel-texto`), juntado (`933a856`), enviado e
  instalado.
- **O README instalado** (ramo `inst/readme-doc`): o instalador o copia
  para `/usr/share/doc/nexus-sense`, a desinstalação o apaga, e as duas units
  apontam para ele — a do agente apontava para um arquivo que nunca era
  copiado, e a do driver para o repositório do DAMX.
- **Os ensaios pausam a curva** (ramo `curva/ensaio-pausa`): todo modo de
  `ensaio-termico.sh` que começa no `0,0` grava `fan_curve = false` antes da
  partida e devolve a linha como estava no fim; no ec5, quem devolve é o
  `ec5-volta`. Não roda nada na máquina.

---

## Onde estamos

| | |
|---|---|
| base | partiu do DAMX `1.0.2-h1` (commit `1f88341`) e seguiu sozinho; não rastreia mais o upstream |
| driver | **um modelo só**: 1 entrada DMI, 2 quirks, 1 interface WMI, 1 parâmetro, 2864 linhas (eram 5167) |
| versão | **v1.2.9** — `master` em github.com/brunodobner/nexussense (privado) |
| layout | reorganizado em 2026-09-10: só `setup.sh` executável na raiz |
| histórico | resetado na v1.0.0; a razão dos 111 commits foi para [decisoes.md](decisoes.md) e [armadilhas.md](armadilhas.md) |
| suíte shell | 28 testes: 26 passam, 2 pulam, 0 falham — sem root e sob `LC_ALL=C`; num worktree, `test-arvore.sh` falha pelo `.git`, que lá é arquivo |
| suíte Python | 618 passam (`python3 -m pytest -q`), incluindo DBus privado |
| ventoinha | a curva própria é o Automático desde 2026-10-16, com o guarda na unit — [plano-curva.md](plano-curva.md), seção 11 |
| build | `W=1` limpo nos dois kernels instalados, medido na 4e — um é Clang 23 e o outro GCC 16 |
| CI | **não há**, desde 2026-10-11, por decisão do usuário: os fluxos saíram do repositório. O shellcheck e a suíte em máquina limpa saíram junto — [decisoes.md](decisoes.md), seção 22 |

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
[x] Melhorias, etapa 3 -- instalador v1.2.3: desinstala o que instala, partida a frio conferida
[x] Melhorias, etapa 4a -- CI        suites e shellcheck por push, modulo semanal
[x] Melhorias, etapa 4b -- GPU       v1.2.4: a janela deixa a dGPU dormir; temperatura fica no nvidia-smi
[x] Melhorias, etapa 4c -- bandeja   v1.2.5: o item volta com o watcher; sem ele, ou sem barramento, cai na reserva
[x] Melhorias, etapa 4d -- instalador v1.2.6: seis sobras; a desinstalacao executada num namespace
[x] Melhorias, etapa 4e -- botao N   v1.2.7: o evento WMI nao chega e o caminho saiu; partida a frio conferida
[x] Melhorias, etapa 4f -- termica   plano escrito e passado pelo grill: docs/plano-termico.md
[x] Rede termica, sessao 1 -- medicao  piso em ~2000 rpm, o EC nao socorre; com jogo a GPU bate no limite em 7 s (R3)
[x] Rede termica, sessao 2 -- a rede   v1.2.9: no agente, pelos tracos; devolveu o automatico na maquina nos dois modos
[x] CI desligado                     2026-10-11, decisao do usuario: os fluxos sairam; ver decisoes 22
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

## Melhorias de 2026-10, etapa 3 — fechada, e onde a etapa 4 começa

A etapa do instalador, no ramo `melhorias/3-instalador`. **v1.2.2 → v1.2.3.**
Foi ao hardware antes do merge, e a partida a frio foi conferida no mesmo dia —
o resultado está no fim desta seção. O baseline capturado antes da primeira edição conferiu com o esperado: 362 na
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

### A partida a frio, que fecha a etapa

Conferida em 2026-10-09 às 20:02, três minutos depois do reinício das 19:59.

```
capability bitmask: 0x00002c26 [WIRELESS BLUETOOTH SET_FUNCTION_MODE
                                PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE]
srcversion  F9236711C6E76401FD38B7A   <- o mesmo: driver intocado
perfis      low-power quiet balanced balanced-performance
perfil      balanced-performance      <- restaurado do estado salvo
estado      "Thermal states saved successfully" 19:59:06, no desligamento
            "Thermal states loaded" 19:59:27, na partida
atributos   os seis, 664 root:nexus_sense, gid 948; version 444 root:root
sessao      id mostra 948(nexus_sense); o 950 e o 1001 soltos sumiram
erro WMI    zero "Failed to get profile"; 18 linhas do driver, todas de carga
agente      ativo desde 19:59:39; "python3 -P -m nexus_sense"
bandeja     subiu sozinha as 19:59:39, filha do systemd do usuario, com -P
hwdb        banco responde f5=prog1; teclado (event3) ja com prog1 de partida
atalho      "Launch (1)" em nexus-sense.desktop; nenhuma linha damx
suites      362 Python; shell 18 passam, 2 pulam -- sem root e sob LC_ALL=C
```

**O gesto humano:** o usuário apertou o botão N e a janela abriu. O journal do
usuário registrou `Started Nexus Sense - Controle do laptop` às 20:02:57 e às
20:03:03, com uma instância só da interface no ar. Nenhum comando verifica que
a janela desenha na tela; por isso a linha só fechou com olho humano.

Três coisas que o reinício resolveu, como previsto: agente e bandeja, parados
de propósito desde 19:25, voltaram sozinhos; a sessão nova carrega o gid 948 e
`test-permissoes.sh` voltou a passar, com escrita sem root confirmada; e o
perfil, devolvido à mão antes de desligar, atravessou o desligamento pelo
arquivo de estado.

**A aposta do atalho ganhou.** O `damx.desktop` tinha sido apagado do
`kglobalshortcutsrc` com o `kglobalacceld` rodando, e havia o risco de o daemon
regravar o arquivo ao sair. Não regravou: depois do reinício o arquivo segue
sem nenhuma linha `damx`.

### Onde a etapa 4 começa

Numa **sessão nova**. Seção 6 de [plano-melhorias.md](plano-melhorias.md):
itens independentes, cada um recusável sozinho. O CI entra primeiro — pytest e
shellcheck a cada push pegariam o item 6 da lista de cima antes do commit. O
que esta etapa viu e deixou está em "Visto e não consertado", acima.

**Ponto de partida:** `master` em v1.2.3. O baseline esperado é 362 na suíte
Python e, na shell, 18 passam e 2 pulam — sem root, com root e sob `LC_ALL=C`.

---

## Melhorias de 2026-10, etapa 4a — fechada, e onde a 4b começa

A etapa 4 virou seis sub-etapas, uma por sessão: o usuário decidiu que entram
todos os quinze itens — os cinco da seção 6 de
[plano-melhorias.md](plano-melhorias.md) e o que as etapas 1 a 3 deixaram em
"Visto e não consertado". A primeira, o CI, fechou na mesma sessão, no ramo
`melhorias/4a-ci`.

**Não há versão nova.** Nada do que se instala mudou: `src/`, `packaging/` e
`driver/` estão idênticos a `master` de antes, e o pacote instalado segue
igual ao fonte. Subir a versão deixaria o instalado diferente de `master` por
uma linha — a lição 7 da etapa 3. O `setup.sh` mudou, e ele não se instala.

O baseline capturado antes da primeira edição conferiu com o esperado: 362 na
suíte Python; shell 18 passam e 2 pulam, idêntico sob `LC_ALL=C`.

O que entrou, cada item com teste que falhou primeiro:

| | o quê | prova |
|---|---|---|
| suíte | não chama mais o `nvidia-smi` de verdade | isca na frente do `PATH`: 35 chamadas por rodada, depois 0 |
| suíte | não fala mais com o barramento de sessão de verdade | barramento isca com monitor: 1 conexão por rodada, depois 0 |
| `test-aviso-dkms.sh` | o aviso é exercitado numa árvore plantada, não em `/lib/modules` | reprovava onde não há kernel bootável; e reprova o script sem a guarda do `vmlinuz` |
| quatro testes | pulam fora desta máquina em vez de reprovar | quatro combinações simuladas, 0 falhas; três mutações provam que o pulo não esconde reprovação |
| `ci.yml` | pytest, suíte shell como usuário e como root, shellcheck — a cada push | verde na quarta rodada |
| `modulo.yml` | o módulo contra os headers do Arch, toda segunda e quando `driver/` muda | verde na segunda rodada |
| shellcheck | 3 erros e 7 avisos consertados | 0 e 0 no CI; ficam 62 notas de info e estilo |
| `test-ci.sh` | guarda o que deixaria o CI verde e inútil | nove mutações dos workflows, nove reprovações |

**Os números, nesta máquina e no CI:**

```
                       aqui                 container do CI
pytest                 364 passam, 1 xfail  364 passam, 1 xfail
shell, sem root        19 passam, 2 pulam   13 passam, 8 pulam
shell, como root       nao rodada           14 passam, 7 pulam
shellcheck 0.11.0      nao instalado        0 erros, 0 avisos, 62 notas
modulo, make W=1       --                   6.18.55-1-lts e 7.2.9-arch1-1,
                                            GCC 16.2.1, 0 avisos
modulo, dkms 3.4.4     --                   add e build nos dois kernels
duracao                --                   cerca de 1 min por workflow
```

Os que pulam no CI são os que leem esta máquina: `test-arvore` (a seção que
compila; as outras sete rodam antes e reprovariam), `test-dkms`,
`test-install-drivers`, `test-perfil-bateria`, `test-permissoes`,
`test-quirk-anv15-52`, `test-usb-charging` e, sem root, `test-toolchain`. A
lista vai para o resumo do job, e **um teste fora dela que pule reprova o
job**: pulou porque perdeu uma dependência, e a cobertura sumiria calada.

### Oito coisas que só apareceram executando

1. **O CI achou dois defeitos de produção na bandeja**, e o teste que os
   escondia. `test_build_tray_diz_qual_bandeja_subiu` diz "sem host SNI no
   barramento de teste" e nunca houve barramento de teste: ele falava com o da
   sessão de quem rodava a suíte, achava o watcher do Plasma e registrava um
   item de verdade. Passava por isso. Fora desse caso, reproduzido com um
   roteiro de vinte linhas:

   ```
   sem barramento de sessao     register() levanta DBusException: publish()
                                abre a conexao fora do try
   barramento sem watcher SNI   register() devolve False e o PROCESSO sai com
                                1 no laco de eventos, ao fechar a conexao
                                privada -- a libdbus encerra quem a perde
   ```

   Nos dois a reserva (`QSystemTrayIcon`, ou nenhuma) nunca é alcançada: num
   desktop sem watcher a bandeja morre calada. O conserto mexe no registro SNI
   e ficou com a sub-etapa 4c; o teste ganhou um `xfail` estrito, que reprova no
   dia em que o defeito sumir e a marca ficar. Armadilha 30.
2. **O `setup.sh` tinha três erros de shellcheck desde sempre.**
   `test-setup-deps.sh` roda `shellcheck -S error` e dizia "PULADO shellcheck
   não instalado" a cada rodada. Um pulo dentro de um teste que passa não
   aparece em lugar nenhum.
3. **O `pytest-qt` do Arch importa `typing_extensions` e não o declara.** Num
   container limpo o pytest morria antes de coletar. Nesta máquina o módulo já
   tinha vindo por outro pacote.
4. **Comando ausente lido como resultado.** A imagem mínima do Arch não traz o
   `diffutils`; sem `cmp`, `test-arvore.sh` dizia "LICENSE da raiz difere de
   driver/LICENSE". O teste agora exige o `cmp` antes de usá-lo.
5. **Os workflows reprovavam a suíte que rodavam.** Gravavam o log do build e a
   saída do `run-all` na raiz do checkout, e `test-arvore.sh` cobra a raiz. O
   `make` e o `dkms build` tinham passado. Tudo vai para `RUNNER_TEMP`.
6. **O `command -v` do bash devolve arquivo não executável** quando não acha
   outro. Na simulação, montar `/dev/null` por cima do `pacman` não o escondeu,
   e `test-setup-deps.sh` reprovou por um defeito do roteiro. Esconder um
   binário é tirá-lo do `PATH`.
7. **O roteiro de medição do barramento morreu duas vezes.** Na primeira saiu
   com código 144 sem imprimir o resto. A limpeza usava `pkill -f`, e o padrão
   estava também na linha de comando do shell que chamava o roteiro — a
   armadilha 10. Não foi apurado além disso; refeito com limpeza por PID, não
   repetiu. Na segunda o pytest saiu com 1 no teste 347, sem mensagem: era o
   segundo defeito do item 1 se mostrando, antes de eu saber que existia.
8. **A simulação previu o CI.** Antes do primeiro push, a suíte shell rodou num
   `bwrap` sem sysfs, sem DKMS, sem pacman e sem o grupo. Deu 13 e 8 como
   usuário, 14 e 7 como root falso — os mesmos números e os mesmos nomes que o
   container devolveu depois. O que ela não previu foi o que dependia de
   pacote instalado: os itens 3 e 4.

**Como refazer a simulação** (o roteiro vivia no scratchpad, que é tmpfs):

```bash
# PATH so com links de /usr/bin, menos dkms, pacman, nvidia-smi, kwriteconfig6
bwrap --ro-bind / / --dev /dev --proc /proc --bind /tmp /tmp --bind "$PWD" "$PWD" \
      --tmpfs /sys --tmpfs /var/lib/dkms --tmpfs /usr/src --tmpfs /boot \
      --tmpfs /usr/lib/modules --ro-bind group-sem-nexus_sense /etc/group \
      --setenv PATH "$BIN" --setenv LC_ALL C \
      ./tests/run-all.sh          # com --unshare-user --uid 0 --gid 0: root falso
```

### Visto e não consertado

- **Os dois defeitos da bandeja do item 1.** Sub-etapa 4c.
- **62 notas de shellcheck**, que o CI mostra sem reprovar: 35 são o
  `A && ok || falha` dos testes (SC2015), 10 são funções-dublê que o shellcheck
  não vê serem chamadas (SC2329), 7 são `printf` com cor no formato em
  `verificar-dkms.sh` (SC2059).
- **O CI não cobre o Clang.** Os kernels do Arch são GCC; os desta máquina,
  CachyOS com Clang. Quebra de API aparece nos dois; a que é só do Clang, só no
  portão local.
- **As mudanças mecânicas no `setup.sh` não foram ao hardware**: os laços de
  `install_drivers` e de `check_kernel_headers` e a limpeza do nome antigo. A
  lista de kernels e a saída de `check_kernel_headers` foram comparadas antes e
  depois, idênticas; o resto roda na reinstalação da sub-etapa 4d.
- **A suíte shell como root não foi rodada nesta máquina.** A etapa não usou
  root. Rodou como root no container, e como root falso na simulação.
- **`actions/checkout` está preso à etiqueta `v5`**, não a um commit.

### Onde a 4b começa

Numa **sessão nova**. Sub-etapa 4b de
[plano-melhorias.md](plano-melhorias.md): a GPU sem o `nvidia-smi`. Três
medições antes de qualquer código, sem root, com o modo máximo desligado pelo
usuário.

**Ponto de partida:** `master` em v1.2.3, com o CI verde. O baseline esperado é
364 passam e 1 xfail na suíte Python e, na shell, 19 passam e 2 pulam — sem
root e sob `LC_ALL=C`.

---

## Melhorias de 2026-10, etapa 4b — fechada, e onde a 4c começa

Sub-etapa de medição: as três perguntas da seção 6 de
[plano-melhorias.md](plano-melhorias.md), respondidas em 2026-10-10 entre 02:45
e 03:34, antes de qualquer linha de código. Uma delas mandou consertar a
janela, e o conserto foi ao hardware no mesmo dia. Ramo `melhorias/4b-gpu`,
**v1.2.3 → v1.2.4.**

O baseline capturado antes de tudo conferiu com o esperado: 364 passam e 1
xfail na suíte Python; shell 19 passam e 2 pulam, idêntico sob `LC_ALL=C`.

**A condição, conferida a cada amostra:** na tomada (bateria em 79–80%), modo
máximo desligado pelo usuário às 02:44 e o agente sem nenhum descritor da NVML,
perfil `balanced-performance`, ventoinhas no automático. Nenhuma amostra saiu
dela. Cada fase foi um comando só, e os sensores foram achados pelo nome ou
pelo rótulo.

A regra do plano não mudou. O que se fixou antes do primeiro número foi como
ler cada termo dela: "cabe em 5 °C" é toda amostra, não a média; carga é uso de
GPU a partir de 50%, repouso é até 10%; "não acorda" é `runtime_active_time`
sem andar um milissegundo, e só vale se um `nvidia-smi` no fim mostrar que o
instrumento enxerga um despertar.

| | pergunta | resposta | o que decide |
|---|---|---|---|
| 1a | ler `temp2` acorda a placa? | **não**, nem atrasa o sono | — |
| 1b | o que ele devolve com a placa `suspended`? | **zero** | — |
| 1c | a diferença contra o `nvidia-smi` cabe em 5 °C? | no repouso sim; **na carga não** | a temperatura **fica no `nvidia-smi`** |
| 2 | a janela impede a dGPU de dormir? | **sim** | conserto na janela — "O conserto", abaixo |
| 3 | o que `temp3` mede? | é o `SEN3` do ACPI; o que o `SEN3` mede, o firmware não diz | só este registro |

### Pergunta 1 — `temp2` contra o `nvidia-smi`

```
                          amostras   EC - nvidia-smi          pior
carga   (AION2, uso >=97%)   35      +0 a +6, media +3,9       6    <- tres amostras em +6
repouso (uso 0%)             36      +1 a +2, media +1,9       2
```

O EC lê sempre igual ou acima. Reprovou por um grau, em três de 35 amostras, e
a regra estava escrita antes: do `temp2` não sai código.

Com a placa `suspended`: 60 leituras em 60 s — 30 só do rótulo `GPU`, 30 dos
cinco canais do hwmon do acer — e o status ficou `suspended` em todas, com
`runtime_active_time` parado. O `nvidia-smi` do fim acordou a placa, então o
silêncio não era vácuo (armadilha 14). O valor lido nas 60 foi `0`. Lendo a
1 Hz através do adormecer, ele vale a temperatura até o segundo em que a placa
dorme e zero no seguinte — e a placa dormiu nos mesmos 21 s de quando ninguém
lê.

### Pergunta 2 — a janela e o sono da placa

Um `nvidia-smi` do próprio roteiro serve de despertar em t=0:

```
janela fechada                    dorme 21,0 s depois       4 de 4
janela aberta, placa dormindo     60 s, nao acordou         a guarda de read_gpu vale no hardware
janela aberta, placa acordada     4 min 12 s sem dormir     limite da regra: 63 s
   ... e a janela e fechada       dorme ~7 s depois
```

Com a janela aberta e a placa acordada, o processo da interface colheu um
filho `nvidia-smi` em 45 de 45 conferências de 2 s, nas duas rodadas de 90 s. É
o que o plano supunha: `read_gpu` só chama o `nvidia-smi` com a placa `active`,
mas cada chamada renova o prazo, e ela nunca chega a `suspended`. **A janela
não acorda a placa; não a deixa dormir.**

São dois prazos, não um: 21,0 s depois de acordar de `suspended`, e 7 a 10 s
quando ela já estava acordada havia tempo (7 ao fechar a janela, 10 ao parar o
`coolercontrold`).

### Pergunta 3 — `temp3` é o `SEN3`

```
                  jogo     repouso   so CPU (4 processos, 90 s)
temp3 (Ext. 2)   70-71     52-54     49-51
SEN3             70-71     52-54     49-51     identico em 172 de 172 amostras
temp1 (CPU)      68-90     51-72     49-91
nvidia-smi       60-69     45-46     44-47
```

Não é a CPU: ela foi a 91 °C por 90 s e ele não saiu de 51. Não é o chip da
GPU: em repouso fica 7 a 9 °C acima. Sobe com carga de GPU e leva minutos para
descer. É a zona térmica `SEN3`, um sensor do próprio EC
(`\_SB_.PC00.LPCB.EC0_.SEN3`, dispositivo `INTC10A1:01`) que o firmware não
descreve — um sensor de placa do lado da GPU, e mais do que isso não dá para
afirmar. O rótulo `External 2` fica. De carona: `temp1` do acer é idêntico à zona `TCPU`,
também em 172 de 172.

### Quem segura a placa acordada nesta máquina

A medição parou na terceira fase. Com o jogo, o Steam e a janela fechados e o
modo máximo desligado, nenhum processo legível tinha `/dev/nvidia*` aberto — e
a placa não dormiu em 120 s. `runtime_suspended_time` valia **zero em 6 h 15 de
boot**. A regra para esse caso estava escrita: achar o dono antes de seguir.

```
coolercontrold rodando, nada mais    0 ms suspended em 120 s
parado (03:13:49)                    suspended 10 s depois
religado (03:32:30)                  active na hora, e 75 s sem dormir
```

O `coolercontrold` (CoolerControl 5.0.1, serviço de root) inicia a NVML na
partida — `NVML found and initialized`, no journal — e registra a RTX 4050 com
carga, potência e temperatura; a taxa de sondagem padrão dele é de um segundo.
É o mecanismo da pergunta 2, vindo de outro programa, o dia inteiro.
Ele não controla nada nesta máquina: o hwmon do acer não tem `pwm`.

**Consequência:** hoje a dGPU não dorme com nem sem o Nexus Sense, e o conserto
da janela só aparece se o CoolerControl deixar de vigiar a GPU. Isso é
configuração do usuário — o dispositivo se desabilita nas configurações dele —
e este projeto não mexe nela. Acordada e ociosa, a placa gasta 2 a 3 W pelo
`nvidia-smi`.

Mais dois que apareceram no caminho:

- **`nvidia-smi dmon -d 2`, filho do `ksystemstats` do KDE**, vivo enquanto o
  Steam esteve aberto, sem Monitor do Sistema na tela nem widget de GPU no
  painel. Saiu sozinho 13 s depois do Steam.
- **`kwin_wayland`** é o único cliente que o `nvidia-smi` lista, com 7 MiB, e
  era o suspeito à vista. Inocente: com ele no lugar a placa dorme.

### O que a medição refutou

1. **"`temp2` serve de temperatura da GPU."** Na carga passa de 5 °C, e com a
   placa dormindo vale zero.
2. **"Fora do modo máximo a placa dorme."** Era a condição que o plano dava
   como suficiente. Nesta máquina não basta: há um serviço de root na NVML.
3. **"`nvidia-smi`: 18 ms, e acorda"** (armadilha 20). Os 18 ms são com a placa
   já acordada — hoje, 20. Acordando, leva 2,0 s (1,97 a 2,12, cinco vezes).
4. **"`read_gpu` nunca acorda, logo a janela não custa bateria."** Metade: não
   acorda, e não deixa dormir.
5. **O suspeito visível.** `kwin_wayland` aparecia na lista e era inocente; o
   culpado não aparece em lista nenhuma (armadilha 31).
6. **A fase de carga de CPU com a placa dormindo perdeu o objeto**, como a
   tarefa 1.10 da etapa 1: existia para separar "último valor" de "temperatura
   de verdade", e a resposta foi zero. A carga rodou com a placa acordada, para
   a pergunta 3.

### Três desvios do roteiro combinado

- A fase de repouso veio depois da primeira tentativa de dormir: o usuário
  fechou o jogo e o Steam antes do pedido, e a placa parada era a observação
  que não se repetiria.
- A janela foi aberta pelo D-Bus (`Show`, o caminho da tecla N) no mesmo
  comando da leitura, em vez de por gesto — ação e leitura juntas, armadilha 25.
  Fechar foi gesto do usuário, com o leitor já rodando: o instante aparece na
  CPU do processo.
- O `coolercontrold` ficou parado de 03:13:49 a 03:32:30, com root e
  autorização, num `pkexec` só que o religava por bandeira ou em 45 minutos.

### Como refazer (o roteiro vivia no scratchpad, que é tmpfs)

```bash
# Os tres arquivos que dizem se a placa dorme. Le-los nao a acorda.
d=/sys/bus/pci/devices/0000:01:00.0/power      # o BDF se acha por vendor 0x10de
cat $d/runtime_status $d/runtime_active_time $d/runtime_suspended_time

# Abrir a janela sem gesto, no mesmo comando da leitura:
busctl --user call com.nexussense.NexusSense /com/nexussense/NexusSense \
       com.nexussense.NexusSense Show
```

- **Janela aberta ou fechada** se confere pela CPU do processo da interface, em
  `/proc/<pid>/stat`: `utime+stime` anda 0 a 2 ticks a cada 2 s com ela
  fechada e 11 a 32 com ela aberta. `cutime+cstime` anda 1 a 4 ticks a cada 2 s
  quando ela chama o `nvidia-smi`, e zero quando não chama.
- **Dono de `/dev/nvidia*`** se acha por `readlink` em `/proc/*/fd`. Processo de
  root é ilegível, e `kwin_wayland` também: armadilha 31.
- **Controle positivo no fim de toda fase que conclui "não acordou"**: um
  `nvidia-smi`, e o status tem de ir a `active`.

### O conserto: a janela se cala quando a placa para

A janela não tem como perguntar quem mais segura a placa — processo de root é
ilegível, cliente NVML não aparece em lista (armadilha 31). Então ela testa.
`GpuProbe`, em `telemetry.py`, guarda estado entre as passadas do poller:

```
uso 0% por 10 leituras seguidas     para de chamar o nvidia-smi; le so runtime_status
a placa dorme em ate 30 s           era so a janela: cai no "adormecida" de sempre
continua active depois de 30 s      outro programa a segura: volta a sondar
   e so repete o teste              depois de 5 min parada, ou assim que a GPU
                                    trabalhar e parar de novo
qualquer uso acima de 0%            zera a contagem: jogo rodando nunca e pausado
```

Durante a pausa o cartão GPU mantém o último valor lido, com o selo **ociosa**,
e a linha do gráfico segue reta. Último valor em vez de travessão foi escolha
do usuário — com o `coolercontrold` no ar a pausa volta a cada cinco minutos.

| commit | o quê | teste que falhou primeiro |
|---|---|---|
| `78a93f3` | `GpuProbe`, e o poller passa a usá-la | 40 passadas com uso 0%, isca contadora no `PATH`: `assert 40 == 10` |
| `8e778da` | selo "ociosa" no cartão | o selo não aparecia |
| `1a369c8` | versão nos três lugares, antes do portão | — |

Oito mutações da sonda, oito reprovações. Suíte Python de 364 para 380, com o
mesmo xfail; shell 19 passam e 2 pulam, mesmos nomes do baseline, idêntica sob
`LC_ALL=C` — rodadas antes de cada commit.

### O portão

Em 2026-10-10, de 03:46 a 03:57, na tomada, bateria em 80%, modo máximo
desligado. Uma chamada de root: `install_nexus_sense` e a parada do
`coolercontrold`, religado por bandeira 193 s depois.

```
instalacao    18 OK, 0 FALHA: pacote identico ao fonte, --version 1.2.4, gid 948
              antes e depois, os seis atributos 664 root:nexus_sense, agente e
              bandeja reiniciados, uma instancia, item SNI no watcher

janela aberta, coolercontrold parado, um nvidia-smi em t=0
   antes do conserto     4 min 12 s sem dormir
   depois                suspended em 21,0 s, 2 de 2 -- igual a janela fechada
                         a janela sondou ~12 s e calou; 60 s seguintes dormindo

janela aberta, coolercontrold rodando, 400 s
   sondou 12 s, pausa de 30 s, voltou a sondar
   segunda pausa 5 min 02 s depois da retomada, de novo 30 s
   placa active o tempo todo: quem a segura e ele
```

**O gesto humano:** com a janela aberta no primeiro ensaio, o usuário viu no
cartão GPU o selo "ociosa" e depois "adormecida". Nenhum comando confere o que
desenha na tela, e por isso a linha só fechou com olho humano.

**A leitura mais simples que fecha com todos os números** — interpretação, não
medição: o driver põe a placa para dormir depois de 7 a 10 s sem consulta, mas
nunca antes de 21 s acordada. Por isso ela dormiu em 21,0 s com o conserto, e
não 10 s mais tarde: a última consulta da janela foi por volta do segundo 11.

### Cinco coisas que só apareceram executando

1. **A condição do plano não bastava.** "Modo máximo desligado" não faz a placa
   dormir nesta máquina; a terceira fase parou até achar o `coolercontrold`.
   Está em "Quem segura a placa acordada", acima, e na armadilha 31.
2. **O suspeito à vista era inocente.** O `nvidia-smi` listava só o
   `kwin_wayland`. A prova veio de parar o serviço e religá-lo, não da lista.
3. **Um bloco de comando com marcador foi executado.** O pedido do portão
   trazia `<espera bandeira, limite 30 min>` dentro de um bloco que o aplicativo
   mostra com botão de rodar. O usuário rodou, o bash recusou a linha inteira e
   nada foi executado — conferido antes de seguir. Bloco executável leva comando
   completo; o que ainda é esboço vai em prosa.
4. **A CPU do processo só diz "janela aberta" com a janela à vista.** No portão
   ela caiu de ~20 ticks a cada 2 s para 1 a 5, por 12 s, com a sondagem
   seguindo normalmente. Não foi apurado o que cobriu a janela. Os filhos
   colhidos são o indicador que não depende disso.
5. **A carga de CPU com a placa dormindo perdeu o objeto** antes de rodar:
   `temp2` vale zero dormindo, e não havia "último valor" a separar de
   "temperatura de verdade".

### Visto e não consertado

- **O `coolercontrold` segura a dGPU acordada o dia inteiro.** Configuração do
  usuário; ver acima.
- **O hwmon do acer devolve `0` para a GPU dormindo**, como se fosse leitura:
  quem lista sensores vê "0 °C". O driver repassa o que o EC diz. Trocar por
  erro de leitura é mudança de driver, com DKMS e reinício — fora desta
  sub-etapa.
- **A janela de verdade custa mais do que o arnês da etapa 1 mediu.** Processo
  real, janela aberta: 7,4% de um núcleo com a GPU dormindo e 9,5 a 10,8% com
  ela acordada, sem contar os filhos. O arnês fora da tela tinha dado 5,3%
  com os filhos. Não foi apurado onde vai a diferença.
- **O caminho de abaixo de 40%** segue sem ensaio de ponta a ponta: a bateria
  esteve em 79–80%. É da 4e.
- **O uso da GPU continua vindo do `nvidia-smi`**, um processo por segundo
  enquanto a placa trabalha. O EC não dá uso, e a NVML em processo é o que o
  agente já faz no modo máximo — com a placa presa acordada. Fica como está.

### Onde a 4c começa

Numa **sessão nova**. Sub-etapa 4c de [plano-melhorias.md](plano-melhorias.md):
a bandeja sobrevive ao watcher — três defeitos no registro SNI.

**Ponto de partida:** `master` em v1.2.4, com o CI verde. O baseline esperado é
380 passam e 1 xfail na suíte Python e, na shell, 19 passam e 2 pulam — sem
root e sob `LC_ALL=C`. O xfail é `test_build_tray_diz_qual_bandeja_subiu`, e é
a 4c que o tira.

**O que vale para o portão dela**, e apareceu neste:

- a bandeja se reinicia com `systemctl --user restart
  'app-nexus\x2dsense\x2dautostart@autostart.service'`; o processo novo aparece
  no barramento em um segundo, e o item SNI se confere em
  `RegisteredStatusNotifierItems` do `org.kde.StatusNotifierWatcher`;
- a janela se abre sem gesto por `busctl --user call com.nexussense.NexusSense
  /com/nexussense/NexusSense com.nexussense.NexusSense Show`;
- se algum ensaio depender de a dGPU dormir, o `coolercontrold` tem de estar
  parado (armadilha 31);
- pedido de root vai em prosa até o comando estar completo.

---

## Melhorias de 2026-10, etapa 4c — fechada, e onde a 4d começa

Os três defeitos do registro SNI da seção 6 de
[plano-melhorias.md](plano-melhorias.md), e mais dois que a execução achou.
Ramo `melhorias/4c-bandeja`, em 2026-10-10, **v1.2.4 → v1.2.5.**

O baseline capturado antes da primeira edição conferiu com o esperado: 380
passam e 1 xfail na suíte Python; shell 19 passam e 2 pulam, idêntico sob
`LC_ALL=C`.

### A reprodução, antes de mexer

Fora da suíte, com o roteiro do plano — `QApplication`,
`register(StatusNotifierItem())`, 700 ms de laço, uma linha depois dele — e
cada caso com o seu barramento:

```
                                  antes (e56738b)                    depois (a087869)
caso 2  sem barramento            register LEVANTA DBusException     devolve False, a linha de
                                  (FileNotFound)                     depois sai, codigo 0
caso 3  barramento sem watcher    devolve False; traceback de        devolve False, a linha de
                                  BusName.__del__; a linha de        depois sai, codigo 0,
                                  depois NUNCA sai; codigo 1         stderr limpo
controle, com watcher falso       devolve True, a linha sai, 0       igual
```

O controle é o que impede o caso 3 de ser lido por vácuo (armadilha 14): no
mesmo roteiro, com um watcher no barramento, a linha de depois do laço sai.

E o que o plano não mandava medir — o aplicativo inteiro, `gui.app
--tray-only`, nos mesmos cenários:

```
caso 2   "já havia uma instância: pedi para ela aparecer", codigo 0     vivo, "bandeja: nenhuma"
caso 3   traceback, codigo 1                                           vivo, "bandeja: nenhuma"
```

### O que entrou

| commit | o quê | teste que falhou primeiro |
|---|---|---|
| `9731adf` | caso 2: `publish()` abre a conexão dentro do `try`. O `xfail` de `test_build_tray_diz_qual_bandeja_subiu` sai no mesmo commit, e a asserção aperta: sem barramento o modo é uma das duas reservas, nunca `sni` | o próprio xfail estrito, com `XPASS(strict)` |
| `d0551fc` | caso 3: o desmonte avisa a libdbus de que quem fecha é o código (`set_exit_on_disconnect`) e solta o nome antes de fechar a conexão | subprocesso em barramento próprio: `assert 1 == 0` |
| `d2e463c` | caso 1: `publish()` escuta `NameOwnerChanged` do nome do watcher e chama `RegisterStatusNotifierItem` cada vez que ele ganha dono | três, com um watcher falso que anota quem se registrou — todos na espera pelo segundo registro |
| `5d0c271` | **fora do plano:** sem barramento, `main()` não disputa o nome da instância única (`bus_available`, em `gui/single.py`) | subprocesso com o aplicativo inteiro: "já havia uma instância" |
| `73af430` | versão nos três lugares, antes do portão | — |
| `a087869` | **fora do plano, achado no portão:** `flush` na linha `bandeja: <modo>` | o teste do aplicativo, sem o `PYTHONUNBUFFERED` que escondia o defeito |

Nove mutações dos consertos, nove reprovações. Suíte Python de 380 e 1 xfail
para **387, sem xfail**; shell 19 passam e 2 pulam, mesmos nomes do baseline,
idêntica sob `LC_ALL=C` — rodadas antes de cada commit.

**Como o caso 1 ficou.** A pergunta é "o nome tem dono?", não "o dono mudou?":
um watcher pode soltar o nome e pedi-lo de novo sem morrer, e volta com o
mesmo nome único. A chamada não espera a resposta — quem a faz é o laço de
eventos da interface. A recusa vira uma linha no stderr (`bandeja: o watcher
voltou e recusou o registro: ...`) e não derruba nada. Os três testes: o
watcher morre e outro sobe; o mesmo processo solta e retoma o nome; o que
volta recusa.

**Por que o achado do `claim` entrou.** `claim()` devolve `False` para "o nome
já é de outro" e para "não há barramento", e `main()` lia os dois como o
primeiro. Sem ele, o conserto do caso 2 nunca rodaria no aplicativo: ele saía
antes de `build_tray`.

### O portão

Em 2026-10-10, de 04:30 a 04:38. Duas reinstalações com root
(`install_nexus_sense`, por `pkexec`): a segunda porque o próprio portão achou
o defeito do `flush`. Antes de tudo o roteiro rodou contra o pacote **antigo**,
para provar que reprova — 6 OK e 7 FALHA, nos lugares certos.

```
reinstalacao, nas duas    13 OK, 0 FALHA: pacote identico ao fonte, --version 1.2.5,
                          gid 948 antes e depois, os seis atributos 664 root:nexus_sense
   o pacote INSTALADO, rodando de /, em barramento proprio, com isca de nvidia-smi
      caso 2              vivo, "bandeja: nenhuma"
      caso 3              vivo, "bandeja: nenhuma", sem traceback
      caso 1              o watcher falso cai, outro sobe e recebe o item de novo, uma vez

reinicio de agente e bandeja
   na primeira            6 OK, 1 FALHA: o journal nao trazia "bandeja: sni"
   depois do flush        7 OK, 0 FALHA: pids novos, uma instancia, um item SNI,
                          item no watcher da sessao, journal "bandeja: sni"

o gesto: systemctl --user restart plasma-kded6.service, as 04:37:46,9
   kded6 de volta         0,3 s depois; pid 1565 -> 542251
   dono do nome           :1.20 -> :1.583
   item do Nexus Sense    registrado de novo em ate 0,2 s, no MESMO processo (pid 540498)
   3 s depois             4 itens no watcher, os quatro que havia: Nexus Sense,
                          arch-update-tray, fcitx5, Claude desktop
   journal da bandeja     nada recusado, nenhum traceback
```

**O gesto humano:** o reinício durou 0,3 s, rápido demais para acompanhar — o
usuário viu ícones sumindo e aparecendo, sem distinguir quais. O que o olho
dele confirmou foi o estado final: perguntado depois, com a bandeja parada, o
ícone do Nexus Sense estava lá. Dos outros três a prova é só a lista do
watcher.

O gesto não era este. O primeiro foi outro, e estragou — é o item 1 da lista
abaixo e a armadilha 33.

### O que a execução refutou

1. **"Descarregar o módulo do watcher solta o nome."** Era a premissa do gesto
   "mais contido" — `unloadModule` e `loadModule` de `statusnotifierwatcher`
   no `kded6`, em vez de reiniciá-lo. Não solta: o dono continuou `:1.20`, o
   módulo novo nasceu com a lista vazia e ninguém foi avisado. Das 04:35:07 às
   04:37:47 o watcher da sessão ficou com **zero itens**, com os quatro vivos
   no barramento. Quem consertou foi o gesto do plano. Armadilha 33.
2. **"Consertar `publish()` conserta o caso 2."** No aplicativo ele nem
   chegava lá: `claim()` falhava antes, e a falha era lida como "já há outra
   instância".
3. **"A linha `bandeja: <modo>` está no journal."** O roteiro do portão a
   cobrava, e [verificacao-manual.md](verificacao-manual.md) mandava "confirmar
   no terminal". Sob a unit não há terminal: zero linhas `bandeja:` no boot
   inteiro, treze linhas no total, todas do systemd.
4. **"No caso 3 o processo sai com 1, e é só."** Sai, e antes disso despeja um
   traceback de `BusName.__del__`: o nome era solto numa conexão já fechada.
5. **"Há teste para o caso sem host."**
   `test_sem_host_ou_sem_glib_nao_deixa_sni_parcial` chama `register()`, confere
   o `False` e termina — sem rodar o laço, que é onde o processo morria. Passou
   por meses com o defeito no lugar. Armadilha 32.

### Oito coisas que só apareceram executando

1. **O usuário rodou o comando de contingência.** O pedido do gesto trazia, num
   bloco com botão de rodar, só o comando de *retorno*, com o rótulo "se minha
   sessão cair". Foi o que ele apertou. Era inofensivo (`loadModule` de módulo
   já carregado não recarrega — conferido), mas é a lição 3 da 4b outra vez, do
   outro lado: bloco executável leva **a ação pedida**, e só ela. Os dois gestos
   seguintes foram assim, e ele os disparou na hora em que estava olhando.
2. **O ramo "a premissa falhou" do roteiro era o estrago.** Ele imprimiu
   `REFUTADO` e recarregou o módulo, como desenhado — e recarregar é que zerou
   a lista. Eu tinha descrito esse ramo ao usuário como neutro.
3. **O gesto foi rápido demais para o olho.** O `kded6` ficou fora 0,3 s. O
   usuário viu ícones sumindo e aparecendo, sem conseguir dizer quais.
4. **Duas mutações "reprovaram" pelo motivo errado.** Uma deixou erro de
   sintaxe no arquivo mutado; outra passou dois arquivos de teste como um
   caminho só, e o pytest não rodou nada. O roteiro de mutação passou a conferir
   a sintaxe e a exigir que a troca case exatamente uma vez. Refeitas, as nove
   reprovam pelo motivo certo. É a armadilha 14 dentro do instrumento.
5. **O endereço "que não existe" não pode ser longo.** No primeiro roteiro ele
   ficava no scratchpad, passou dos 108 bytes de um caminho de socket, e o erro
   foi `BadAddress: Socket name too long` — outro erro, da mesma classe, por
   acaso. Para reproduzir "sem barramento" o caminho tem de ser curto.
6. **`$NOME_PID` de um `coproc { ...; }` é o do subshell**, não o do
   `dbus-daemon` dentro dele. Matar esse PID deixou dois daemons órfãos, e o
   `tee` do roteiro ficou esperando por eles até o tempo limite. Daemon em
   segundo plano com `&`, `$!`, e o endereço por `--print-address=3` num
   arquivo. Os órfãos saíram por PID (armadilha 10).
7. **Um roteiro avulso rodou o aplicativo sem a isca do `nvidia-smi`.** Em
   modo `nenhuma` a janela abre e sonda: foram uns 8 s de chamadas de verdade.
   A placa já estava `active`, segurada pelo `coolercontrold`, e o estado não
   mudou — mas é a armadilha 30. Os roteiros do portão levam a isca, e
   conferem no ambiente do processo que ela está na frente.
8. **`busctl list` num barramento recém-subido mostra meia centena de nomes.**
   São os ativáveis, lidos dos arquivos de serviço da máquina. "Sem ninguém
   dentro" se confere com `--acquired`.

### Visto e não consertado

- **Watcher que chega depois não promove a reserva.** Sem watcher na partida a
  bandeja cai em `qsystemtrayicon` ou `nenhuma` e fica lá até o aplicativo
  reiniciar, mesmo que o watcher suba um segundo depois. Na sessão do Plasma o
  `kded6` sobe antes do autostart; a janela em que isso morde é a de um
  `kded6` caído.
- **Sob `--tray-only`, o modo `nenhuma` abre a janela.** É o desenho ("nem
  isso: o app abre a janela direto"), e agora é alcançável: um login sem
  watcher abre a janela sozinho.
- **O registro de novo não tem segunda tentativa.** Um watcher que ganhe o
  nome antes de exportar o objeto recusaria a chamada, e fica a linha no
  stderr. O do `kded6` exporta antes; é o que `KStatusNotifierItem` também
  supõe.
- **A conexão do item continua com `exit_on_disconnect`** enquanto registrada:
  se o barramento de sessão cair, a libdbus encerra o processo com 1. Só o
  desmonte deliberado foi tratado.
- **`install_nexus_sense` regrava as units e recarrega só o systemd do
  sistema.** O gerenciador do usuário fica com `NeedDaemonReload=yes` e avisa a
  cada `restart`. O conteúdo é idêntico, sem efeito hoje. É da 4d.
- **O teste do "mesmo dono retoma o nome" ficou sem exemplo real.** Foi
  escrito pensando no `kded6`, que não faz isso. A regra do D-Bus continua
  sendo a que ele cobra.
- **Depois do reinício do `kded6`, 24 módulos carregados em vez de 25.** Falta
  o `desktopnotifier`, 15 s depois. Não foi apurado se ele carrega sob demanda.
- **O que o `kded6` faz ao recarregar um módulo** — manter o nome e zerar a
  lista — não é deste projeto, e nenhum cliente SNI tem como perceber.

### Onde a 4d começa

Numa **sessão nova**. Sub-etapa 4d de [plano-melhorias.md](plano-melhorias.md):
cinco sobras do instalador, todas em `setup.sh`, com teste em shell antes.

**Ponto de partida:** `master` em v1.2.5, com o CI verde. O baseline esperado é
387 passam na suíte Python, sem xfail e, na shell, 19 passam e 2 pulam — sem
root e sob `LC_ALL=C`.

**O que vale para o portão dela**, e apareceu neste:

- o roteiro do portão roda primeiro contra o que está instalado, e tem de
  reprovar; só depois a reinstalação;
- a reinstalação é `pkexec /bin/bash -c "cd /home/brunodobner/Claude/Nitrosense;
  source ./setup.sh; install_nexus_sense"`, e leva 4 s; o gid se mede antes e
  depois (948), no mesmo comando;
- depois dela o `systemctl --user` avisa `NeedDaemonReload=yes` nas duas units:
  é um dos achados acima, e cabe na 4d;
- o que se confere pelo journal da bandeja agora existe: `bandeja: sni`;
- bloco com botão de rodar leva a ação pedida, e só ela; contingência vai em
  prosa;
- **nunca `uninstall`** (armadilha 29), e nunca `unloadModule` no `kded6`
  (armadilha 33).

---

## Melhorias de 2026-10, etapa 4d — fechada, e onde a 4e começa

As cinco sobras do instalador da seção 6 de
[plano-melhorias.md](plano-melhorias.md), e uma sexta que a medição mandou
entrar. Ramo `melhorias/4d-instalador`, em 2026-10-10, **v1.2.5 → v1.2.6.**
Só o `setup.sh` e os testes mudaram; em `src/` mudou a linha da versão.

O baseline capturado antes da primeira edição conferiu com o esperado: 387
passam na suíte Python, sem xfail; shell 19 passam e 2 pulam, idêntico sob
`LC_ALL=C`.

### O que entrou

| commit | o quê | teste que falhou primeiro |
|---|---|---|
| `8d0cfb8` | `runtime_dependencies_ok` pergunta pelo `busctl` e pelo nome `org.freedesktop.UPower.PowerProfiles` no barramento de sistema, com dono ou ativável | a função sob um `PATH` só de dublês: serviço no barramento sem o `powerprofilesctl` era recusado, binário sem o serviço era aceito — seis pontos |
| `1cb324c` | `kernels_missing_headers` e `build_deps_missing`: kernel bootável sem headers basta para chamar `install_build_deps` | `install_drivers` executada com três travas: com headers faltando, o passo dado era `check_kernel_headers` |
| `9a21662` | `target_kernels_use_llvm` lê a config de cada kernel bootável; `is_llvm_kernel` sai | `install_build_deps` com `pacman` dublê e uma árvore só GCC: o `clang` era pedido |
| `a1b9081` | `uninstall` chama `stop_nexus_sense`: o agente pelo gerenciador do usuário, a bandeja pelo processo | alvo ausente, e a fiação estática de `test-uninstall.sh` |
| `0f74b4d` | teste: `uninstall` e `comprehensive_cleanup` executadas num namespace | não havia código a mudar; a prova de que o teste reprova são seis mutações |
| `37c4133` | **o sexto:** `install_nexus_sense` recarrega o systemd de cada usuário | `install_nexus_sense` no mesmo namespace: as únicas chamadas eram `daemon-reload` do sistema e `--global enable` |
| `0028a47` | teste endurecido contra a mutação que passou | — |
| `41f9f3b` | versão nos três lugares, antes do portão | — |
| `b1e1b62` | `build_deps_missing` recebe a raiz como as vizinhas | o shellcheck do CI, SC2120 |

Suíte Python em 387; shell de 19 e 2 para **21 passam e 2 pulam**, mesmos
nomes do baseline mais os dois testes novos, idêntica sob `LC_ALL=C` —
rodadas inteiras antes de cada commit.

### O sexto candidato: medido antes de entrar

A 4c tinha visto `NeedDaemonReload=yes` depois da reinstalação e deixado para
cá. A regra, antes de medir: entra se o gerenciador do usuário ficar de fato
com a definição antiga depois de uma reinstalação. Só com leitura, antes da
primeira edição:

```
nexus-sense-agent.service                            NeedDaemonReload=yes
app-nexus\x2dsense\x2dautostart@autostart.service    NeedDaemonReload=yes
os dois arquivos de origem regravados as 04:32:32 -- a reinstalacao da 4c
```

Entrou, como tarefa própria. **O que não foi medido:** que um restart sobe a
unit velha quando o conteúdo muda. É o comportamento documentado do systemd, e
medi-lo exigiria alterar uma unit instalada. Com conteúdo idêntico o efeito de
hoje era um aviso a cada restart. Armadilha 34.

### Como a desinstalação foi provada sem desinstalar

Três cercados, do mais leve ao mais fechado:

```
tarefas 1 a 3    PATH so com dublês (pacman, busctl, make, dkms) e arvores de
                 kernel plantadas; install_drivers com tres travas
tarefa 4         /proc e /run/user plantados; runuser, systemctl e kill como
                 funcoes que anotam; PIDs acima do pid_max; iscas no PATH
tarefas 4 a 6    bwrap --unshare-all: uninstall, comprehensive_cleanup e
                 install_nexus_sense INTEIRAS, com a raiz somente-leitura, /run
                 vazio, um /etc com a copia de /etc/group e um gshadow
                 sintetico, e processos-isca com o argv dos lancadores
```

O que o terceiro mostrou, executando — `test-desinstalacao-namespace.sh`, 2,5 s:

```
limpeza da reinstalacao   o grupo fica com o mesmo gid; /etc/group sai igual;
                          agente e bandeja seguem rodando
desinstalacao             a linha do grupo sai de group e de gshadow, e so ela;
                          agente e bandeja encerrados; o processo de outro
                          modulo e o shell que cita o agente seguem rodando; a
                          unit e parada no gerenciador do usuario antes de a
                          limpeza desabilita-la
instalacao do aplicativo  recarrega o gerenciador do usuario; nao cria nem
                          apaga grupo; nao para nada
a maquina de verdade      grupo, processos e arquivos instalados lidos antes e
                          depois: iguais
```

O teste pula como root — sem privilégio um erro do roteiro não tem como
desinstalar nada — e onde não há `bwrap`. Por isso entrou na lista de pulos do
`ci.yml`.

**Mutações.** 29 pares de mutação e teste sobre uma **cópia** do repositório —
27 mutações distintas do `setup.sh`, duas conferidas por dois testes. Na
primeira rodada uma passou; o teste foi consertado e hoje as 29 reprovam.

### O CI

```
                       simulacao (bwrap)    container, 1o push    2o push
pytest                 --                   387 passam            387 passam
shell, sem root        14 passam, 9 pulam   14 passam, 9 pulam    igual
shell, como root       15 passam, 8 pulam   15 passam, 8 pulam    igual
shellcheck             nao ha como          1 aviso (SC2120)      0 erros, 0 avisos
```

A simulação previu de novo os números e os nomes. O que ela não tem como
prever é o shellcheck, que não está instalado aqui: foi um push a mais. Ficam
72 notas de info e estilo (eram 62): 36 SC2015, 14 SC2329, 7 SC2059, 7 SC2016.

Para refazer a simulação vale a receita da seção da 4a, tirando também o
`bwrap` do `PATH` — senão o teste novo roda onde no container pularia.

### O portão

Em 2026-10-10, de 06:38:25 a 06:38:33, na tomada, bateria em 54%. Antes, às
05:11, o roteiro rodou contra o pacote **antigo** e o `setup.sh` de `master`:
19 OK e 11 FALHA — a versão, o pacote, o `NeedDaemonReload` das duas units, a
versão que a bandeja tinha carregado e as seis conferências das funções novas.

```
reinstalacao     uma chamada de root (pkexec): gid 948 antes e depois, no mesmo
                 comando; "Usuário brunodobner já está no grupo nexus_sense."
systemd          o do sistema recarregou em 266 ms; o do usuario, 0,35 s
                 depois, em 136 ms. NeedDaemonReload yes -> no nas duas units,
                 sem ninguem recarregar a mao
reinicio         restart das duas units: codigo 0 e stderr vazio -- sem o aviso
                 agente 540503 -> 670940, bandeja 540498 -> 670936
                 journal: "agente encerrado", "agente no ar", "bandeja: sni"
instalado        --version 1.2.6; pacote identico ao fonte; unit, autostart,
                 .desktop, regra udev e apply-perms identicos ao repositorio
permissoes       os seis 664 root:nexus_sense; version 444 root:root
watcher          um item do Nexus Sense, com o pid da bandeja nova
funcoes novas    contra esta maquina, so leitura: nenhum kernel sem headers,
                 nada a instalar, um alvo Clang; nexus_sense_pids devolve os
                 dois MainPID do systemd e so eles

                 30 OK, 0 FALHA
```

Não houve gesto humano neste portão: o ícone de volta depois do reinício está
provado pela lista do watcher, não por olho.

**As tarefas 2 e 3 não foram ao hardware.** O portão é `install_nexus_sense`,
que não passa por `install_drivers` nem por `install_build_deps`: o `pacman` de
verdade nunca foi chamado pelo critério novo. As tarefas 4 e 5 também não, por
decisão — é o que o namespace existe para evitar.

### O que a execução refutou

1. **"Os kernels desta máquina são todos Clang."** Este arquivo dizia isso em
   mais de um lugar, e era a última reserva de `is_llvm_kernel` ("CachyOS, logo
   Clang"). Medido: `6.18.55-1-cachyos-lts` é GCC 16.2.1, `7.2.9-1-cachyos` é
   Clang 23.1.1. O `test-toolchain.sh` já cobria os dois ramos aqui, sem root,
   e ninguém tinha lido a saída dele assim.
2. **"`is_llvm_kernel` olha o kernel em execução."** Olhava quatro coisas, e
   todas eram do sistema em execução: `uname -r`, `/proc/config.gz`,
   `/proc/version` e o nome da distro. Com o `uname` fora do `PATH` do ensaio
   ela ainda respondia Clang, por `/proc/version`.
3. **"O resto roda na reinstalação da sub-etapa 4d"** — a nota da 4a sobre as
   mudanças mecânicas em `install_drivers` e `check_kernel_headers`. O portão
   da 4d não passa por lá. `comprehensive_cleanup` rodou, mas no namespace e
   com dublês. Continuam sem hardware.
4. **"O ensaio em namespace passou."** Na primeira rodada, 18 de 19 — com
   `mkdir` e `seq` faltando no `PATH` de dentro. O laço que esperava os
   processos-isca rodou zero vezes e eles estavam de pé por sorte. O teste
   agora cobra que a saída de erro de dentro venha vazia. Armadilha 30.
5. **"As mutações reprovam."** Uma passou: `grep -qxF` trocado por `grep -qF`
   na busca do nome no barramento. O barramento de mentira não tinha nenhum
   nome que um casamento frouxo aceitasse.
6. **"A simulação previu o CI."** Previu as suítes. O shellcheck reprovou no
   primeiro push.

### Cinco coisas que só apareceram executando

1. **A busca por texto achou o meu próprio shell.** A primeira medição dos
   processos casava `-m nexus_sense` na linha de comando e devolveu três: o
   agente, a bandeja e o shell da busca. É a armadilha 10, e foi o que decidiu
   o desenho de `nexus_sense_pids` — argv comparado elemento a elemento.
2. **O `runuser` abre sessão PAM nesta máquina.** `/etc/pam.d/runuser` inclui
   `system-login`. No portão a sessão abriu e fechou em 0,2 s e não sobrou nada
   no `loginctl`.
3. **O `groupdel` funciona como root de mentira.** Num namespace de usuário,
   sobre um `/etc` próprio, ele edita `group` e `gshadow` e sai com 0. O `/etc`
   de dentro é um diretório inteiro, não o arquivo montado por cima como na
   simulação da 4a — por leitura, não por medição: o `groupdel` grava ao lado e
   renomeia.
4. **Um push a mais do que o combinado.** O shellcheck só roda no CI. Quem
   mexe em shell conta com dois pushes do ramo.
5. **A mensagem de `0028a47` conta errado.** Diz "29 mutações"; naquele momento
   eram 28 pares em 29 rodadas, com uma repetida. O 29º par entrou depois, com
   o conserto do shellcheck.

### Visto e não consertado

- **`install_drivers` e `install_build_deps` não foram ao hardware** com o
  critério novo. Ver "O portão".
- **`pacman -S --needed` com o banco de pacotes à frente do kernel instalado**
  traria headers de outra versão. O "quando" novo aciona o "quais" da 3.5 mais
  vezes. Lido, não medido.
- **No Debian o `vmlinuz` mora em `/boot`.** O discriminador de "bootável" é
  `/lib/modules/<versão>/vmlinuz`, que lá não existe: `kernels_missing_headers`
  volta sempre vazia e `install_drivers` não constrói para kernel nenhum. É
  anterior a esta sub-etapa. Lido, não medido.
- **Onde só existe o nome legado `net.hadess.PowerProfiles`** (power-profiles-
  daemon anterior à 0.20) o instalador agora recusa. Antes instalava, e a parte
  do perfil de CPU falhava calada. Não há máquina assim para medir.
- **`each_user_manager` cala os erros.** Se o gerenciador de um usuário não
  responder, o agente dele só recebe o sinal — e o systemd o reabre em 3 s
  sobre um lançador que a limpeza apagou. Não exercitado.
- **`stop_nexus_sense` não espera os processos saírem** nem insiste com
  `SIGKILL`.
- **A desinstalação não recarrega o systemd do usuário.** A unit que o gerador
  criou a partir do autostart fica na memória, inativa, até relogar.
- **A desinstalação executada só roda em máquina de desenvolvimento:** o teste
  pula no CI (sem `bwrap`) e como root.

### Onde a 4e começa

Numa **sessão nova**. Sub-etapa 4e de [plano-melhorias.md](plano-melhorias.md):
o botão N — o evento WMI chega? — e o caminho de abaixo de 40%.

**Ponto de partida:** `master` em v1.2.6, com o CI verde. O baseline esperado é
387 passam na suíte Python, sem xfail e, na shell, 21 passam e 2 pulam — sem
root e sob `LC_ALL=C`. Como root, `test-desinstalacao-namespace.sh` pula por
desenho.

**O que vale para o portão dela**, e apareceu neste:

- depois de `install_nexus_sense` o `systemctl --user restart` não avisa mais
  nada; se avisar `changed on disk`, a tarefa 6 regrediu;
- agente e bandeja se acham por `nexus_sense_pids` (depois de `source
  ./setup.sh`) ou pelo `MainPID` das duas units — nunca por texto na linha de
  comando;
- se a 4e podar o driver, agente e bandeja param antes da recarga do módulo e
  voltam depois, como na etapa 2;
- quem mexe em shell conta com dois pushes do ramo: o shellcheck só roda no CI;
- `uninstall` e `comprehensive_cleanup` continuam fora desta máquina. O que
  for delas se executa em `test-desinstalacao-namespace.sh`.

---

## Melhorias de 2026-10, etapa 4e — fechada, e onde a 4f começa

A sub-etapa 4e da seção 6 de [plano-melhorias.md](plano-melhorias.md): o
evento WMI do botão N chega ao driver? Ramo `melhorias/4e-botao-n`, em
2026-10-10, **v1.2.6 → v1.2.7.** Não chega, e o caminho saiu: 168 linhas do
driver, bitmask idêntico. A partida a frio foi conferida no mesmo dia — o
resultado está no fim desta seção.

O baseline capturado antes da primeira edição conferiu com o esperado: 387
passam na suíte Python, sem xfail; shell 21 passam e 2 pulam, idêntico sob
`LC_ALL=C`; `W=1` limpo em `6.18.55-1-cachyos-lts` (GCC 16.2.1) e em
`7.2.9-1-cachyos` (Clang 23.1.1); bitmask `0x00002c26`; `srcversion` carregado
`F9236711C6E76401FD38B7A`, igual ao do build de `master`.

### A medição

Um `pkexec` só, de 07:45:26 a 07:46:25, com marcos em `/dev/kmsg` a cada
aperto e a cada mudança de cabo, carga ou perfil. Dois instrumentos: o
`pr_debug` do driver, que é o da regra, e um kprobe na entrada de
`acer_wmi_notify`, acrescentado nesta sessão — o porquê está na armadilha 35.

```
dynamic debug achado      18 pontos do nexus_sense, 0 com p
sonda, desligado          3 leituras de usb_charging -> 0 linhas
sonda, ligado             3 leituras -> 3 linhas; o ponto "botao N: key_num"
                          aparece no controle com =p
kprobe                    armado em acer_wmi_notify, em instancia propria

8 apertos na tomada       07:45:39 a 07:45:44   cabo=1  49%  balanced-performance
                          "botao N: key_num" 0     entradas no tratador 0
cabo fora                 07:45:51              2 entradas: ev=0x9 e ev=0x8
8 apertos na bateria      07:45:59 a 07:46:15   cabo=0  49-48%  balanced
                          "botao N: key_num" 0     entradas no tratador 0 novas

Unknown function number   0        Unknown key number   0        device state  0
dynamic debug devolvido   0 pontos com p, relido no mesmo comando; kprobe e
                          instancia removidos
```

Cada aperto conferido pelo journal do usuário: dezesseis linhas `Started Nexus
Sense - Controle do laptop` na janela da medição, cada uma classificada pelo
cabo no instante em que apareceu. Das 190 linhas do kernel entre os marcos, 155
são do driver e todas são as três leituras de sondagem — a janela do aplicativo
estava aberta e lendo.

**O cabo é o controle positivo.** As duas entradas chegam 4 ms uma da outra,
no segundo em que `ACAD/online` vira 0: funções `0x9` (`WMID_BATTERY_BOOST_EVENT`)
e `0x8` (`WMID_AC_EVENT`), os dois ramos mudos do tratador. O tratador recebe
eventos e o instrumento os vê; os zeros dos apertos querem dizer que o botão
não manda nenhum.

**Conferido depois, sem root:** três leituras de `usb_charging` às 07:47:16 e
zero linhas novas no `journalctl -k`. O `pr_debug` voltou a desligado.

**O que veio de quem.** Duas trocas de perfil na rodada, as duas do agente, com
linha no journal dele e o `config.toml` gravado no mesmo instante: `balanced`
às 07:45:53,43, ao sair o cabo, e `balanced-performance` às 07:46:35,62, ao
voltar. Nenhuma troca sem dono.

**Os apertos foram mais rápidos que o combinado, e a janela foi fechada.** Na
tomada, 0,67 a 0,88 s entre um e outro, contra os ~3 s pedidos; na bateria,
1,7 a 3,7 s. O usuário perguntou se precisava refazer. Não precisou: os
dezesseis estão no journal; pressa poderia fundir eventos, não sumir com todos
— e o primeiro da série veio depois de horas sem aperto nenhum; e fechar a
janela não muda perfil.

### A regra, e o que ela mandou

Escrita antes, no plano: zero eventos nas duas condições, e
`cycle_gaming_thermal_profile` e o ramo do tratador saem. Zero nas duas.

| commit | o quê | teste que falhou primeiro |
|---|---|---|
| `2fcc2a6` | sai o ramo do evento `0x7`, `acer_thermal_profile_change`, `acer_thermal_profile_cycle` e o parâmetro; por dependência `platform_profile_support`, e `platform_profile_device` vira local do registro | `test-correcoes.sh` reescrito: seis falhas — o parâmetro, as duas funções, a bandeira, o ramo, e a chamada ao núcleo do `platform_profile` |
| `8d2f413` | saem `last_non_turbo_profile` e `acer_predator_v4_max_perf`, que só o botão N lia, e a linha de log que as imprimia | duas falhas, uma por variável |
| `666622f` | versão nos três lugares, antes do portão | — |

`W=1` limpo nos dois kernels depois de cada estágio, numa cópia fora do
repositório. **3032 → 2864 linhas.** `srcversion` novo:
`C68C01808749B047940186D`.

O que fica no tratador: as teclas de função (`WMID_HOTKEY_EVENT`), o
acelerômetro, os três ramos mudos e o aviso de função desconhecida. O número
`0x7` ficou no `enum`. Um firmware que passe a mandá-lo escreve `Unknown
function number - 7` no journal, sem ninguém ligar debug.

O teste novo também reprova qualquer chamada a `platform_profile_notify`: o
único que avisava o núcleo era o botão N, e a ordem de travas desse aviso
(armadilha 24) nunca teve prova de hardware. Quem voltar a avisar prova de
novo.

### "Mas o botão N abre a janela"

Foi o que o usuário disse ao ver a poda começar, e a dúvida era dos documentos:
`poda-subsistemas.md` punha "o botão N abre o app" como a prova de vida do
tratador de eventos. São dois caminhos, e só um existe nesta máquina:

```
fica   atkbd (/dev/input/event3) -> hwdb f5=prog1 -> atalho do KDE "Launch (1)"
       -> nexus-sense.desktop                           abre a janela
saiu   evento WMI 0x7 -> acer_wmi_notify -> trocaria o perfil dentro do kernel
                                                        nunca rodou
```

Os três elos do primeiro foram lidos na hora. E a medição já dizia: a janela
abriu dezesseis vezes com zero entradas no tratador.

### O portão

Em 2026-10-10, de 08:11:35 a 08:12:50, na tomada, bateria em 76%. Um `pkexec`
para a parte de root; o resto como o usuário.

```
condicao        medida depois da senha: tomada, 76%, balanced-performance
agente/bandeja  parados pelo systemd do usuario antes da recarga, nenhum
                processo de pe; religados por trap: codigo 0
DKMS            install_drivers: installed nos dois kernels; fonte encenado
                identico ao repositorio
srcversion      C68C01808749B047940186D no modulo instalado para cada kernel
                e no CARREGADO (antes: F9236711C6E76401FD38B7A)
bitmask         0x00002c26 [WIRELESS BLUETOOTH SET_FUNCTION_MODE
                PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE] -- identico
parametros      so force_caps
carga           14 linhas; "Max performance profile" nao aparece mais;
                "Thermal states loaded" e "restored successfully"; zero aviso
                ou erro do driver
estado          sobrevive a recarga: balanced-performance, ventoinha 0,0, e os
                outros quatro atributos iguais
perfis          low-power quiet balanced balanced-performance
atributos       os cinco 664 root:nexus_sense; version 444 root:root; profile
                664 root:nexus_sense; gid 948 antes e depois
hwmon           presente: CPU, GPU / CPU, GPU, External 2
rfkill          os dois presentes; bluetooth bloqueia (1) e desbloqueia (0),
                achado pelo nome na hora; wireless intocado
aplicativo      install_nexus_sense: pacote identico ao fonte, --version 1.2.7
                nos dois lancadores; NeedDaemonReload no nas duas units;
                journal "agente no ar" e "bandeja: sni"
botao N         hwdb com f5=prog1; autostart no lugar
escrita         os quatro perfis escritos sem root e lidos de volta; o de antes
                devolvido; ventoinha 0,0
estresse        16 leitores x 200 leituras: zero "Failed to get profile"
suites          387 Python; shell 21 passam, 2 pulam, identica sob LC_ALL=C

                65 OK, 0 FALHA  (42 na parte de root, 23 sem root)
```

A escrita dos quatro perfis entrou porque a poda mexeu na saída do
`profile_set`: ele devolve direto o resultado da chamada WMI.

**`install_drivers` foi ao hardware pela primeira vez com o critério da 4d** —
`build_deps_missing` respondeu que nada faltava e o passo seguinte foi a
conferência dos headers, nos dois kernels. `install_build_deps` continua sem
hardware: o `pacman` não foi chamado.

**O CI**, no primeiro push do ramo (`666622f`): pytest e suíte shell, shellcheck
e o módulo contra o kernel do Arch, os três verdes. O shellcheck não pediu
segundo push.

**O gesto humano**, com o módulo podado carregado: um aperto no botão N às
08:17:56, na tomada, a 80%. O journal do usuário registrou a abertura, o
usuário confirmou que a janela abriu, e o kernel ficou calado — zero aviso do
driver, zero `Unknown function number`. Esta última contagem é a medição de
novo, agora sem debug: se o evento `0x7` chegasse, o módulo novo o acusaria.

### O caminho de abaixo de 40%: não deu

A condição existia quando a sessão abriu e deixou de existir antes de o cabo
sair:

```
07:33      cabo ligado, 31%, carregando, balanced-performance em vigor
07:36:20   35%   observador sem root no ar (cabo, carga, perfil, guardado)
07:39:06   40%   -- o roteiro da medicao ainda estava sendo escrito
07:45:52   49%   cabo fora; o agente vai a balanced e guarda balanced-performance
07:46:35   48%   cabo de volta; o firmware aceita na primeira escrita
```

De 35% a 49% em 9 min 15 s. O pedido para tirar o cabo foi ao chat aos 35%, no
meio de um turno longo, e não foi visto a tempo. O que se viu de ponta a ponta
foi o caminho **normal**: guardar ao sair, devolver ao voltar, o `config.toml`
gravado no mesmo instante da troca. O ramo "recusado, fica pendente" segue sem
hardware.

Uma linha a favor da armadilha 27, de passagem: às 07:33 a máquina estava a
31% no cabo com `balanced-performance` em vigor. O firmware não derruba perfil
já em vigor.

### O que a execução refutou

1. **"O botão N dispara `WMID_GAMING_TURBO_KEY_EVENT` e percorre os perfis"** —
   a seção 19 de `decisoes.md` e o comentário no tratador. Zero em dezesseis,
   nas duas condições, com o caminho de eventos provado vivo na mesma rodada.
2. **"O tratador de eventos está vivo porque o botão N abre o app"** — a camada
   C de `poda-subsistemas.md`. O tratador está vivo; quem o prova é o cabo. O
   botão não passa por ele.
3. **"`cycle_gaming_thermal_profile` fica: botão em uso"** — a camada D. O botão
   está em uso como tecla. O parâmetro governava um evento que não vem.
4. **"O terceiro ensaio fecha a questão"** — este arquivo, na seção da etapa 2.
   Ele deixava três leituras para o mesmo silêncio; o `pr_debug` não separa "o
   evento não vem" de "o ramo é mudo" nem de "o tratador é surdo". Armadilha 35.
5. **"Saem o parâmetro e o ramo do tratador"** — o plano. Saíram 168 linhas.
   Terceira estimativa de poda que erra por baixo.
6. **"A suíte inteira antes de cada commit, igual ao baseline"** — numa
   sub-etapa de driver não fica igual: entre o primeiro commit e o portão,
   `test-install-drivers.sh` reprova com `fonte em /usr/src difere do
   repositório`. É o teste fazendo o que promete. Foram 20 passam, 1 falha e 2
   pulam nos três commits, e 21 e 2 depois do portão.
7. **"Dezesseis linhas do driver no boot"** — a seção da etapa 2. São
   catorze. E a conta de quinze, escrita aqui antes do reinício, também errou:
   ver a partida a frio, abaixo.

### Cinco coisas que só apareceram executando

1. **Uma condição com prazo se agarra primeiro.** A janela de abaixo de 40%
   durou seis minutos depois de notada. O observador sem root subiu em três;
   o pedido de gesto é que chegou tarde. Numa próxima: observador e pedido
   antes de ler o resto.
2. **Cada commit de driver tem de sair limpo sozinho.** Tirar só o ramo e as
   duas funções deixaria `platform_profile_support` escrita e nunca lida — o
   aviso do Clang 23 que a etapa 2 consertou. Saiu no mesmo commit.
3. **O marco de `/dev/kmsg` leva prioridade explícita** quando vai ser
   procurado num fluxo filtrado por prioridade, e o roteiro cobra que ele
   esteja lá. O portão cobrou: uma vez no journal do kernel, uma vez no fluxo
   de avisos.
4. **Uma tabela sem cabeçalho em `poda-subsistemas.md`**, sobra do rascunho da
   camada D, estava no ponto onde a seção nova entrou. Ganhou título e
   cabeçalho.
5. **Um arquivo apareceu modificado no `git status` durante a suíte e sumiu.**
   Visto uma vez, com a suíte shell rodando dentro do portão. Algum teste mexe
   na árvore e desfaz. Não apurado.

### Como refazer (os roteiros viviam no scratchpad, que é tmpfs)

A medição, como root, num comando só:

1. guardar quais pontos do `nexus_sense` já têm `p` em
   `/sys/kernel/debug/dynamic_debug/control`; `trap` que devolve exatamente
   isso e relê;
2. marco, três leituras de `usb_charging`, contar: zero com o debug desligado;
   ligar (`module nexus_sense +p`), marco, três leituras, contar: três;
3. armar o kprobe da armadilha 35;
4. laço de 0,3 s: a cada mudança de `ACAD/online`, carga, estado ou perfil, um
   marco com o mtime do `config.toml`; a cada linha nova `Started Nexus Sense -
   Controle do laptop` em `journalctl _UID=<uid> --since @<início>`, um marco
   com a condição e a contagem do kprobe; fim 10 s depois de oito em cada
   condição, ou por tempo limite;
5. contar depois do marco de início: `botao N: key_num` (hoje, com o ramo fora,
   a linha a procurar é `Unknown function number`), `Unknown key number`,
   `device state:`, e ler o trace.

O portão: uma parte de root que mede a condição, para as duas units pelo
systemd do usuário (`runuser` com `XDG_RUNTIME_DIR`), roda `install_drivers` e
`install_nexus_sense` com a entrada em `/dev/null`, confere e religa por
`trap`; e uma parte sem root com as escritas, o estresse e as suítes. O
`srcversion` esperado sai de um build `W=1` feito antes, numa cópia.

### Visto e não consertado

- **O caminho de abaixo de 40% continua sem ponta a ponta.** Ver acima.
- **A máquina descarrega com o cabo ligado.** A carga caiu de 54% para 31%
  entre 06:38 e 07:33, o agente não registrou troca de fonte, e o usuário
  confirmou: o cabo ficou ligado o tempo todo. Na etapa 2 ela já tinha ido de
  60% a 43% em 70 minutos, também na tomada. Às 07:33 estava carregando de
  novo, a 32 W. **A causa não foi apurada** — nem a carga da máquina nesse
  intervalo, nem o que o firmware fazia. É por aí que se chega abaixo de 40%
  sem tirar o cabo, que é a condição que a carona da armadilha 27 precisa.
- **O ramo das teclas de função do tratador** (`WMID_HOTKEY_EVENT`) nunca foi
  exercitado: zero linhas `device state:`. A tecla que o dispararia é a de modo
  avião, e ela derruba a sessão (armadilha 25).
- **Os eventos `0x9` e `0x8` chegam ao tirar o cabo e o driver os ignora.** O
  agente descobre a troca de fonte sondando `ACAD/online` a cada 2 s. Não é
  defeito; é um canal que existe e ninguém usa.
- **Um comentário órfão no driver**: `Switch series keyboard dock status`, em
  cima de `acer_rfkill_set`. Sobra da camada B.
- **`install_build_deps` continua sem hardware.**
- **O arquivo que aparece modificado durante a suíte.** Item 5 acima.

### A partida a frio, que fecha a sub-etapa

Conferida em 2026-10-10 às 08:33, um minuto e meio depois do boot das
08:32:25 — na mesma conversa, que sobreviveu ao reinício.

```
capability bitmask: 0x00002c26 [WIRELESS BLUETOOTH SET_FUNCTION_MODE
                                PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE]
srcversion  C68C01808749B047940186D   <- o do build podado
parametros  so force_caps
linhas      catorze do driver, todas de carga; nenhuma "Max performance
            profile"
perfis      low-power quiet balanced balanced-performance
perfil      balanced-performance      <- restaurado do estado salvo
estado      "Thermal states saved successfully" as 08:32:08, no desligamento;
            "Thermal states loaded" e "restored successfully" as 08:32:30;
            nenhum "Invalid" nem "Incomplete"
atributos   os cinco 664 root:nexus_sense; version 444 root:root; profile 664
            root:nexus_sense; gid 948
hwmon       acer: CPU, GPU, External 2 / ventoinhas CPU, GPU
rfkill      acer-wireless, acer-bluetooth  (indices 0 e 1)
erro WMI    zero "Failed to get profile"; zero "Unknown function number"; zero
            aviso do driver
DKMS        installed nos dois kernels
agente      ativo desde 08:32:41; --version 1.2.7
bandeja     subiu sozinha, filha do systemd do usuario, 16 s depois do boot;
            "bandeja: sni"
botao N     f5=prog1 no banco hwdb e no teclado (event3, atkbd); atalho
            "Launch (1)"; autostart no lugar
```

**A previsão de quinze linhas estava errada.** Contava as catorze de carga
mais `module verification failed`, que no boot anterior saiu em nome do
`nexus_sense`. Esse aviso o kernel dá uma vez por boot, ao primeiro módulo sem
assinatura que carregar — e neste boot foi o `v4l2loopback`, 53 ms antes. O
número de linhas do driver num boot depende de quem ganha essa corrida: catorze
ou quinze, e nenhum dos dois é notícia.

**O gesto humano:** o usuário apertou o botão N às 08:34:18, na tomada, a 80%,
e a janela abriu. O journal do usuário registrou a abertura e o kernel ficou
calado: zero aviso do driver, zero `Unknown function number` no boot inteiro.

### Onde a 4f começa

Numa **sessão nova**. Sub-etapa 4f de [plano-melhorias.md](plano-melhorias.md):
a rede de segurança térmica — brainstorm e plano próprio, não código.

Nada pendente da 4e a bloqueia: a partida a frio já foi conferida.

**Ponto de partida:** `master` em v1.2.7, com o CI verde. O baseline esperado é
387 passam na suíte Python, sem xfail e, na shell, 21 passam e 2 pulam — sem
root e sob `LC_ALL=C`.

**O que vale para ela**, e apareceu nesta:

- condição com prazo — carga, temperatura — se agarra antes de qualquer
  leitura longa: observador sem root no ar e pedido de gesto no chat, primeiro;
- silêncio só vale com controle positivo pelo mesmo caminho (armadilha 35);
- a 4f põe a máquina quente de propósito: o limite de aborto se escreve antes
  de medir, e a temperatura se lê do hwmon achado pelo nome (armadilha 19);
- esta máquina descarrega com o cabo ligado — duas vezes registradas, a
  segunda confirmada pelo usuário. Num ensaio longo sob carga, a bateria se
  mede a cada amostra, junto com a temperatura; e a causa é pergunta para o
  brainstorm.

---

## Melhorias de 2026-10, etapa 4f — o plano térmico, e onde a medição começa

A sub-etapa 4f da seção 6 de [plano-melhorias.md](plano-melhorias.md): a rede
de segurança térmica. Era brainstorm e plano, não código, e foi isso: em
2026-10-10 saiu [plano-termico.md](plano-termico.md), passado pelo grill antes
de ir à aprovação. **Sem ramo, sem versão nova, sem root.** Nada do que se
instala mudou, nenhum ensaio esquentou a máquina e ninguém escreveu em
`fan_speed`.

As suítes, rodadas com os documentos novos já na árvore, conferem com o
esperado: 387 passam na suíte Python, sem xfail; shell 21 passam e 2 pulam,
idêntica sob `LC_ALL=C`.

**O plano foi aprovado em 2026-10-10**, na mesma conversa, e o usuário mandou
rodar E2 em seguida. E3 esquenta a máquina e se combina no chat antes do
comando, como a seção 9 do plano manda.

### O que o brainstorm decidiu

1. **A rede não é para salvar silício.** A CPU corta frequência sozinha a
   partir de ~92 °C, o kernel desliga a máquina em 110, a GPU tem alvo próprio
   em 87. Nada disso depende da ventoinha. O que sobra para uma rede:
   desempenho que some por um cursor esquecido, calor em placa, SSD e bateria,
   e o setpoint manual que atravessa o reinício pelo `/etc/predator_state`.
2. **A primeira pergunta é o que o EC faz sozinho** com o manual baixo e a
   máquina quente. Só o ensaio responde, e as outras dependem dela.
3. **Três ensaios, em ordem.** E2 mapeia porcentagem para rotação em repouso,
   sem calor, e exercita o vigia e o aborto. E3 põe carga de CPU com o manual
   a 30% e no mais baixo — com um estágio em automático na frente, que é o
   controle positivo. São ~25 min, 15 de carga; a primeira versão dava 40 e o
   usuário perguntou por quê: um estágio não decidia nada e dois tinham folga.
   Só os 600 s do mais baixo não encolhem. E3b, com um jogo, é condicional.
4. **Os limites de aborto estão escritos**, e os das zonas de placa saem do
   envelope que o próprio EC permite em automático: o máximo de cada zona em
   26 minutos de jogo, mais 2 °C.
5. **Cinco camadas devolvem a ventoinha**: o `trap`, um vigia em processo à
   parte, o `timeout` de cada processo de carga, o usuário, e o que fazer se a
   máquina desligar no meio.
6. **Uma regra de três desfechos, escrita antes**: o EC toma a ventoinha de
   volta (nenhum código); obedece e nada estoura (o usuário decide, com os
   números); algum limite estoura (a rede entra).
7. **A rede, se entrar, é pequena.** No agente, função pura. Só arma com o
   manual abaixo do que o automático faria quente. Disparada, escreve `0,0` e
   registra no journal.

### O que o usuário decidiu, no grill

Sete perguntas, uma por vez. Duas respostas foram contra a recomendação, e as
duas encolheram o desenho.

| | pergunta | resposta |
|---|---|---|
| 1 | até onde E3 desce | até a porcentagem mais baixa, inclusive com a ventoinha parada |
| 2 | E3b, o ensaio com jogo | decide depois de ver E3 |
| 3 | se a máquina aguenta e só fica lenta, quer a rede? | decide com os números |
| 4 | disparada a rede, o manual volta sozinho? | **não: fica em automático** até ele escolher de novo |
| 5 | como fica sabendo | **só o journal**, nada na interface |
| 6 | piso no cursor, se houver porcentagem que para a ventoinha | decide depois de ver E2 |
| 7 | potência da fonte | 135 W, lido da etiqueta |

Com a 4 e a 5, a rede não guarda setpoint, não tem limiar de volta, não tem
como oscilar, e a sessão de código não toca na janela.

### O que foi lido, sem provocar nada

```
coretemp        Package id 0: crit 100 C, crit_alarm 0
TCC Offset      8  (corte de frequencia a partir de ~92 C)
acpitz, TCPU    critical 110 C -- o kernel desliga
SEN2..SEN5      passive 65, hot 75, critical 80,05 C -- e o kernel nao age:
                nenhuma zona com dispositivo de resfriamento, thermald inativo
GPU             alvo 87 C; reducao 2 C acima do limite, desligamento 12 C acima
NVMe            max 85,85 / crit 92,85 num; 99,85 / 109,85 no outro
CPU             i5-13420H; limite de potencia 55 W sustentados, 115 W de pico
bateria         battery_limiter 1, battery_calibration 0
```

E do código: `fan_speed` lido é a memória do driver, não o firmware — se o EC
tomar a ventoinha, o atributo continua dizendo o manual, e a verdade é a
rotação. O agente não escreve na ventoinha. O cursor aceita de 0 a 100, sem
piso.

### O que foi medido: automático, com um jogo e depois dele

O usuário abriu um jogo por conta própria às 08:37, um minuto antes da
primeira leitura desta sessão. O observador sem root subiu às 08:38:50, antes
da leitura longa dos documentos, e pegou 26 minutos de jogo e a descida — a
linha de base do que o EC faz sozinho, de graça.

```
                      com o jogo (26 min)        18 min depois
ventoinhas, rpm       4414 / 4003 em media       2178 / 1930
pacote, C             73 a 96, media 84          44
SEN4, C               72 a 89, media 86          45
throttle da CPU       18,0% do tempo             zero
bateria               80% -> 77%                 80%, corrente zero
```

Os números inteiros, a descida minuto a minuto e o observador estão em
[plano-termico.md](plano-termico.md), seções 2 e 13.

### O que a medição refutou

1. **"Ventoinha manual baixa com CPU quente"** — a frase do plano. CPU quente
   não distingue nada: em automático, a 4400 rpm, o pacote vai a 96 °C e a CPU
   corta frequência em quase um quinto do tempo. A pergunta que serve é se o
   manual está abaixo do que o automático faria.
2. **Os pontos `critical` das zonas `SEN*` como limite.** `SEN4` passou 24
   minutos acima do dela, sem consequência. A régua é o envelope do automático.
3. **"A bateria se vigia pelo `status`."** Ele disse `Charging` em 635
   amostras, com a carga caindo três pontos, subindo e parada. Armadilha 36.
4. **"A causa não foi apurada"** — a seção da 4e, sobre a máquina que
   descarrega com o cabo ligado. Segue hipótese, mas com um dado a favor: com
   o jogo a bateria cedeu ~5 W, e fechado o jogo recebeu 40 W na amostra
   seguinte. CPU a 55 W, GPU a 60–75 W e o resto encostam nos 135 W da fonte.
   E o usuário disse o que faltava: **nas duas quedas antigas ele estava
   jogando**, com o cabo sempre ligado. São três de três. A queda de hoje foi
   de 0,12 ponto por minuto; a da 4e, de 0,42 — falta ver uma carga mais
   pesada dar a taxa maior.
5. **As duas recomendações de desenho** — devolver o manual ao esfriar, e uma
   linha na janela. O usuário escolheu o contrário nas duas.
6. **As ferramentas do grill.** O extrator e o gerador de perguntas acharam
   zero ramos: os padrões são em inglês. A árvore foi montada à mão.

### Quatro coisas que só apareceram executando

1. **A condição com prazo desta sessão era um jogo, e ninguém a previu.** O
   observador subiu antes da leitura longa, como a 4e mandava, e foi isso que
   a pegou. A primeira versão não gravava as zonas `SEN*` nem o throttle; a
   segunda entrou um minuto e meio depois, com o jogo já quente.
2. **O observador não gravava `charge_now`.** Só `capacity`, `status` e
   corrente — e o `status` não diz nada. A queda apareceu no `capacity`, de
   ponto em ponto.
3. **A corrente máxima "com o jogo" era 2,4 A**, e a primeira versão do plano
   dizia "de 0 a 0,9 A". Eram dois picos, no começo e no fim. Conferir a frase
   contra o traço inteiro, não contra as linhas que passaram na tela.
4. **Um comando de `awk` foi barrado** por uma checagem que procura remoção de
   arquivos: não havia remoção nenhuma. O resumo virou um arquivo `.awk`.

### Visto e não consertado

- **`BAT1/status` diz `Charging` sempre que o cabo está ligado.** É do
  firmware; o agente não depende dele. Armadilha 36.
- **O evento `0x9` ("battery boost") chega ao driver e é ignorado** — já
  estava na lista da 4e. Se a hipótese da fonte se confirmar, é ele o aviso de
  que a bateria entrou no circuito.
- **O traço bruto da linha de base ficou no scratchpad**, que é tmpfs. O
  resumo e o observador estão no repositório; o traço, não — são
  centenas de kB num repositório que já foi expurgado por tamanho. Se a sessão
  2 quiser um traço em automático como teste, grava outro.
- **"São 17 armadilhas"**, em "Como trabalhar aqui", mais abaixo. São 36.

### Onde a medição começa

Aprovado o plano, pela sessão 1 de
[plano-termico.md](plano-termico.md): o roteiro de ensaio em `tests/hardware/`,
com a lógica de aborto testada contra uma árvore falsa, e depois E2 e E3.
Ramo `termica/1-medicao`.

**Ponto de partida:** `master` em v1.2.7. O baseline esperado é 387 passam na
suíte Python, sem xfail e, na shell, 21 passam e 2 pulam — sem root e sob
`LC_ALL=C`.

**O que vale para ela:**

- os limites de aborto são os da seção 7 do plano, e não se mexe neles depois
  da aprovação;
- o roteiro só começa com `fan_speed` em `0,0`, na tomada, com a bateria a
  partir de 60% — medido na hora de rodar, não na hora de pedir;
- a bateria se lê por `charge_now` (armadilha 36);
- E2 e E3 são blocos que o usuário roda no terminal do aplicativo: o que ele
  faz e não faz durante o ensaio se combina antes, em prosa (seção 9 do
  plano);
- depois de qualquer reinício que o plano não previu, ler `fan_speed` antes de
  tudo: desligamento ordenado grava o manual baixo, e ele volta na partida.

---

## Rede térmica, sessão 1 — fechada, e onde a sessão 2 começa

Ramo `termica/1-medicao`, em 2026-10-10, na mesma conversa em que o plano foi
aprovado. O que existe:

| | |
|---|---|
| `tests/hardware/ensaio-termico.sh` | o roteiro de E2: os dois exercícios e o mapa. Escreve na máquina de verdade; não faz parte da suíte |
| `tests/shell/test-ensaio-termico.sh` | a mesma lógica contra uma árvore plantada, com um EC de mentira e os índices embaralhados: 51 conferências |
| suítes, nesse ponto | 387 na Python; shell 22 passam e 2 pulam, idêntica sob `LC_ALL=C` |

**O roteiro foi escrito antes do teste, e o teste passou de primeira** — o
contrário do que a seção 1 de [plano-melhorias.md](plano-melhorias.md) manda.
O que prova que o teste morde são 23 mutações, uma proteção estragada por
vez, numa cópia: 23 reprovações. O que veio depois já entrou na ordem certa.

### O que o usuário viu antes de o E2 rodar

Com o comando pronto, ele interrompeu: a ventoinha fica numa faixa mais alta
do que o plano supunha, mesmo com a máquina quase parada. O traço do
observador confirmou, e o roteiro teria reprovado na máquina no primeiro
exercício.

```
                       modo maximo desligado      modo maximo ligado
parada, EC a ~50 C     2240 / 1990 rpm            3350 / 2890 rpm
carga, EC a 64-73 C    --                         5000 a 6196 rpm
jogo, EC a 73-91 C     4037 a 4464 rpm            --
```

O automático não tem repouso fixo: são pelo menos duas curvas, e quem troca
de uma para a outra é o modo máximo — mesmo perfil térmico, GPU na mesma
temperatura. O plano tinha medido uma só, a do modo desligado, e a chamado de
"o automático".

O que mudou no roteiro, cada item com teste que falhou primeiro:

- **a volta se prova pela rotação ter saído do manual**, e não por ter
  chegado à rotação da partida. Os exercícios escrevem `95,95` em vez de
  `60,60`: a volta tem sentido conhecido (cai), e um exercício que falhe deixa
  barulho, não calor;
- **se a 95% a rotação não se distingue do automático, o exercício diz** — e
  o E2 para no controle positivo, em vez de passar por vácuo;
- **a condição de partida afrouxou onde não media nada** (`load1` abaixo de 4,
  pacote abaixo de 70 °C: o aplicativo desta conversa sozinho passava dos
  limites antigos) **e apertou onde media**: modo máximo desligado.

### O que a execução refutou

1. **"O automático vai de ~2200 em repouso a ~4400 quente"** — a seção 2 do
   plano, uma hora depois de escrita. Vale para o modo máximo desligado. Com
   ele ligado: 3350 parada, 6196 sob carga.
2. **"A rotação tem de voltar à do automático"** — o plano e o roteiro. O
   automático não volta para onde estava.
3. **"Sem carga: `load1` abaixo de 2"** — a condição de E2. Com o aplicativo
   do Claude aberto e mais nada, `load1` andou de 0,6 a 2,1.
4. **"O teste do prazo passa"** — passava, e reprovava sob carga: com prazo de
   1 s, contado em segundos inteiros, o roteiro vencia o próprio prazo antes
   de o teste ver a escrita. Apareceu rodando as mutações quatro por vez.

### Visto e não consertado

- **Por que o modo máximo troca a curva da ventoinha** não foi apurado. O
  suspeito é o pedido de PowerMizer que o agente segura; o `nvidia-powerd`
  está no ar. Importa para a rede: "abaixo do que o automático faria" passa a
  ter duas respostas (seção 11 do plano).
- **A linha de base e os limites de aborto são do modo desligado.** Um jogo
  com o modo máximo ligado não foi medido: a ventoinha gira mais, e o envelope
  deve ser outro.
- **O shellcheck não roda nesta máquina**: os dois arquivos novos só passam
  por ele no CI, no primeiro push.
- **A sessão do Claude reiniciou no meio** e levou o observador passivo junto;
  ele foi religado. O traço da manhã ficou no scratchpad antigo.

### E2 rodou: há piso, e a ventoinha não para

Rodado pelo usuário em 2026-10-10, de 10:40:35 a 10:46:27, por um bloco no
terminal. Modo máximo desligado, na tomada, 79%, sem jogo: 316 amostras,
nenhuma fora da condição, throttle zero.

```
vigia     95% girou 7139 / 6696 rpm; kill -9 no roteiro; fan_speed em 0,0
          819 ms depois; rotacao 700 rpm abaixo na leitura seguinte
aborto    limite rebaixado: saiu com 10 na primeira amostra, 0,0 devolvido

  %     100    80    60    50    40    30    20    15    10     5     1
CPU    7539  6250  4911  4170  3411  2582  2009  2005  2003  2000  2000
GPU    7069  5891  4647  3970  3252  2469  1675  1667  1663  1668  1663
```

- **De 20% para baixo nada muda**: ~2000 / ~1665 rpm. A ventoinha não para em
  porcentagem nenhuma. O pior "manual baixo" possível é pouco abaixo do
  automático parado e menos da metade do automático quente.
- **O automático quente equivale a 53% / 50% de manual** com o modo máximo
  desligado, e a 79% / 77% com ele ligado.
- **100% gira 7539 rpm**; o automático nunca passou de 6196.
- O traço está em `~/.local/state/nexus-sense/ensaio-e2-20261010-104034.tsv`,
  fora do repositório e fora do tmpfs.

**O que E2 refutou:** "inclusive com a ventoinha parada" — a resposta 1 do
grill. Não existe ventoinha parada: o firmware segura um piso. E o cursor tem
uma faixa morta, de 1% a 20%, que este projeto oferecia sem saber.

**Duas coisas que só apareceram executando:**

1. **O painel de terminal do aplicativo perdeu a linha de comando, duas
   vezes.** A aba abriu, o fish esperou 10 s por uma resposta do terminal, e o
   comando não chegou a ser digitado. Conferido antes de seguir: nenhum
   processo, `fan_speed` em `0,0`, nenhum traço. Rodou pelo bloco, como o
   plano mandava desde o começo.
2. **A ventoinha responde em um segundo.** Eu esperava que a conferência da
   rotação no exercício do aborto valesse pouco — o alvo aborta um segundo
   depois de escrever. Valeu: nessa amostra ela já girava 7260 rpm, e caiu
   depois. Os 20 s de espera por degrau, no mapa, são folga.

### O roteiro do E3: pronto, provado, por rodar

O mesmo `tests/hardware/ensaio-termico.sh` ganhou o modo `e3`: três estágios
(automático por 120 s, manual a 30% por 180 s, manual a 1% por 600 s), cada
um com 30 s frio na frente para medir a rotação de referência e com a descida
gravada depois. A carga são 8 processos em laço, cada um em grupo próprio e
debaixo de `timeout`. No fim ele escreve o veredito pela regra da seção 10
do plano.

`tests/shell/test-ensaio-termico-e3.sh` o exercita na árvore de mentira, com
um EC que esquenta enquanto houver carga: 36 conferências. O apoio comum aos
dois testes foi para `tests/shell/lib-arvore-termica.sh`. Suíte shell: 23
passam, 2 pulam, idêntica sob `LC_ALL=C`. Python: 387.

**35 mutações, 35 reprovações** — 23 das proteções comuns e 12 do E3. Não foi
de primeira: ver o item 2 abaixo.

Três coisas que só apareceram executando:

1. **O estágio contava amostras, não segundos.** Cada amostra custa o passo
   mais a leitura, e a carga morre pelo relógio: na máquina, o estágio de 600
   amostras teria uns 35 s finais sem carga nenhuma. Apareceu lendo o traço da
   árvore de mentira — o pacote já frio na última amostra de um estágio "sob
   carga". O estágio passou a durar tempo de relógio, e o teste cobra o pacote
   quente no fim.
2. **Uma mutação escapou: `mata_carga` que não mata nada.** O teste esperava
   até 3 s para ver a carga morta, e com folga de 1 s ela morria sozinha pelo
   `timeout` dentro dessa janela. A proteção mais importante do E3 — a fonte
   de calor morre com o roteiro — estava coberta pelo relógio, não por ela.
   A folga dos casos subiu para 30 s; só o caso "sem roteiro e sem vigia" usa
   a curta, porque é o relógio que ele mede.
3. **Um `grep -c` contou a linha do veredito.** "O EC obedeceu ao manual"
   aparece nos dois estágios e também na frase do veredito R2. O teste
   reprovava um roteiro certo.

### E3 rodou: o EC não toma a ventoinha de volta, e nada estoura — R2

Rodado pelo usuário em 2026-10-10, de 18:53:54 a 19:12:34, por um bloco no
terminal, depois de um reinício da máquina. Modo máximo desligado, na tomada,
79%, sem jogo: 1012 amostras, nenhuma fora da condição. Carga só de CPU.

```
                         automatico     manual 30%     manual 1% (o piso)
ventoinha, rpm           4455 / 4030    2623 / 2504    2056 / 1715
o EC tomou de volta?     --             nao            nao
pacote, maximo           93 C           93             94
SEN2 (limite 81)         62             68             74
SEN4 (limite 91)         54             61             68
frequencia, ult. minuto  3634 MHz       3286 (-10%)    2965 (-18%)
```

- **O EC obedece ao manual até o fim**: dez minutos com o pacote a 91–94 °C e
  a rotação parada em ~2050 rpm. O controle positivo vale — em automático, na
  mesma carga, ela foi de 2338 a 4482.
- **Com carga só de CPU nada passa do envelope**, e as zonas de placa param de
  subir no sexto minuto. Quem segura é o TCC.
- **O custo é desempenho**: 18% de frequência a menos no piso.
- **Veredito do roteiro: R2.** A decisão é do usuário, com os números.
- A fonte de calor morreu com cada estágio, a ventoinha voltou a `0,0`, nada
  sobrou em `/run/user`. `charge_now` não se mexeu: CPU sozinha não puxa da
  bateria.
- O traço está em `~/.local/state/nexus-sense/ensaio-e3-20261010-185354.tsv`.

**O que E3 não responde:** o jogo. Em automático, com jogo, `SEN4` foi a 89 °C
com a ventoinha a 4400 rpm. A 2050 rpm, com os mesmos 60 W de GPU, não se
sabe — é E3b, que o usuário decide agora que viu E3.

### E3b rodou: com um jogo, a GPU bate no limite em sete segundos — R3

O usuário disse sim ao E3b, e disse também que costuma jogar com o modo
máximo ligado. O roteiro ganhou o modo `e3b` (o jogo tem de estar aberto, do
começo ao fim; nenhuma carga própria), com teste antes: o do E3 passou a 57
conferências. Rodado em 2026-10-10, de 19:44:48 a 19:48:58, com o modo máximo
desligado.

```
com jogo, em automatico     4492 / 4083 rpm; GPU pelo EC 80 C, SEN4 87
com jogo, manual a 1%       ~2075 / ~1727 rpm; GPU pelo EC 79 80 81 82 84 85
                            ABORTO aos 7 s, no limite da GPU pelo EC (85 C)
de volta ao automatico      4436 rpm em 20 s; GPU pelo EC a 74
```

- **Pela regra escrita antes de medir, a rede entra.**
- O limite que estourou é o da GPU, que se protege sozinha: não é dano, é
  desempenho que some em segundos. As zonas de placa não tiveram tempo de se
  mexer, e onde iriam parar este ensaio não diz.
- O roteiro abortou na amostra em que o limite apareceu e devolveu o
  automático. Nenhuma camada além do próprio `trap` precisou agir.
- O traço está em `~/.local/state/nexus-sense/ensaio-e3b-20261010-194448.tsv`.

**O que a execução refutou:** "o estágio do piso por até 300 s" — durou sete.
E os 30 s de espera antes de a rede agir, do desenho provisório: a GPU sobe
um grau por segundo.

**Três coisas que só apareceram executando:**

1. **O corredor de mutações sumiu duas vezes**, com dois reinícios: vivia no
   scratchpad. Antes do E3b rodou uma versão refeita, com as 13 críticas: 12
   reprovaram, e a que passou é equivalente — sem a recusa de "sem jogo", a
   conferência seguinte recusa igual, com o mesmo código.
2. **O resumo dizia "rotação de ? / ?"**: o aborto veio antes de a referência
   do manual assentar. Consertado, com teste que falhou primeiro.
3. **As minhas mutações esquentaram a máquina com o usuário jogando**: de
   19:38 a 19:43 a ventoinha foi a 5600 rpm, com o modo máximo desligado. O
   automático passa dos 4400 também nesse modo, se a carga for maior que a
   do jogo.

### O fechamento da sessão 1

**Sem versão nova**, como a 4a: nada do que se instala mudou. `src/`,
`packaging/` e `driver/` estão idênticos a `master` de antes; entraram um
roteiro que ninguém instala, os testes dele e documentos.

As três camadas da seção 1 de [plano-melhorias.md](plano-melhorias.md):

| camada | o que deu |
|---|---|
| estática | `bash -n` em todo `.sh`, links dos documentos resolvendo, raiz intacta — `test-arvore.sh` |
| suítes contra o baseline | Python: 387, igual. Shell: de 21 para **23 passam**, 2 pulam, os mesmos dois — a diferença são os dois testes novos. Idêntica sob `LC_ALL=C` |
| ensaio na máquina | E2, E3 e E3b, acima |
| CI, no ramo | no primeiro push o shellcheck reprovou: 4 avisos, todos em `lib-arvore-termica.sh` (uma variável lida só por quem importa o arquivo, e três `var=` vazias). Consertado; no segundo push, shellcheck, pytest e a suíte shell — como usuário e como root — verdes, com os testes novos rodando no container |

E uma quarta, que esta sessão acrescentou: **43 mutações do roteiro, 42
reprovadas e uma equivalente.** O corredor agora mora no repositório,
`tests/hardware/mutacoes-ensaio.py`, depois de sumir duas vezes do scratchpad.

O que o usuário decidiu no caminho, além do que está na seção da 4f:

- **o cursor de manual segue de 0 a 100 na tela e vale 20 a 100 no
  firmware** (`firmware = 20 + barra × 0,8`): a faixa morta some, e some o "0
  num lado só". Entra na sessão 2;
- **ele costuma jogar com o modo máximo ligado.** O E3b foi com ele
  desligado, que é o que tinha linha de base.

### Visto e não consertado

- **O jogo com o modo máximo ligado foi medido depois do merge**, das 21:26
  às 21:52 do mesmo dia, pelo observador passivo: ventoinha a 6318 / 5984
  rpm, contra 4414 / 4003 com o modo desligado; GPU pelo EC a 71 °C em vez de
  78; throttle em 8,9% do tempo em vez de 18%. Com o modo ligado a máquina
  joga mais fria e mais rápida. A tabela está na seção 2 do plano. **O E3b
  com o modo ligado não foi feito**: a ventoinha no piso, com esse modo, fica
  ainda mais longe do que o automático faria.
- **Onde as zonas de placa iriam parar com um jogo e a ventoinha no piso** o
  E3b não diz: abortou aos 7 s, pela GPU.
- **Por que o modo máximo troca a curva da ventoinha** não foi apurado.
- **O painel de terminal do aplicativo perde a linha de comando** na partida
  do fish. Os três ensaios rodaram por bloco.
- **Os traços dos ensaios estão fora do repositório**, em
  `~/.local/state/nexus-sense/`. Não é tmpfs, mas também não é o git.
- **O job das suítes no CI passou de ~1 para ~7 minutos.** Os dois testes do
  ensaio rodam duas vezes lá, como usuário e como root, num container lento.

### Onde a sessão 2 começa

Numa **sessão nova**, ramo `termica/2-rede`: a rede, no agente. O desenho está
na seção 11 de [plano-termico.md](plano-termico.md), e o que a medição mandou
mudar nele, no fim da seção 15.

**Ponto de partida:** `master` com a sessão 1 mesclada, ainda em v1.2.7. O
baseline esperado é 387 passam na suíte Python, sem xfail e, na shell, 23
passam e 2 pulam — sem root e sob `LC_ALL=C`.

**O que vale para ela:**

- a rede só arma com o manual abaixo do que o automático faria, e isso são
  duas porcentagens — ~53% com o modo máximo desligado, ~81% com ele ligado;
- age em segundos: com jogo e a ventoinha no piso a GPU sobe um grau por
  segundo;
- disparada, escreve `0,0`, **fica em automático** e avisa **só no journal** —
  decisões do usuário;
- o cursor de 0 a 100 valendo 20 a 100 entra junto, com teste próprio;
- esta sessão muda `src/`: a versão sobe antes do portão, e o portão
  reinstala o pacote, com root.

---

## Rede térmica, sessão 2 — fechada

Ramo `termica/2-rede`, em 2026-10-10 e na madrugada de 11, numa sessão nova.
**v1.2.7 → v1.2.8.** A rede está no agente, e na máquina devolveu o
automático com um jogo aberto, nos dois modos; o portão está mais abaixo, com
o que ele refutou.
O que existe:

| | |
|---|---|
| `src/nexus_sense/fan_guard.py` | a rede, como função pura: `armada` e `decide` |
| `agent.py`, `_guarda_ventoinha` | o que o agente faz em volta dela, no fim de cada passada |
| `telemetry.acer_gpu_temp` | a GPU pelo EC, do canal que o driver rotula `GPU` |
| `model.fan_bar_to_firmware`, `fan_firmware_to_bar` | o cursor de 0 a 100 na tela, 20 a 100 no firmware |
| `tests/python/tracos/` | os cinco traços da medição, recortados por `tests/hardware/recorta-tracos.py` |
| `tests/hardware/ensaio-termico.sh rede` | a prova na máquina: dois controles e o piso, com os limites da seção 7 |
| `tests/hardware/observador.sh` | o observador passivo, que vivia no scratchpad |
| `tests/hardware/mutacoes-rede.py` | o corredor de mutações da rede |

O desenho que entrou, e onde ele difere do provisório, está no fim da seção
11 de [plano-termico.md](plano-termico.md).

### Os limiares, tirados dos traços

A rede só arma com o manual abaixo do equivalente do modo corrente (53% /
50% com o modo máximo desligado, 81% / 82% com ele ligado) e dispara com a
GPU pelo EC a **76 °C ou mais**, a rotação abaixo da do automático, em **duas
passadas seguidas** de 2 s.

```
                                         GPU pelo EC, C
                                         p5   media   p95   maximo
E3, piso, so CPU, 10 min                 --    --     --     69
jogo em automatico, modo maximo ligado   59   71,3    74     75      422 amostras
jogo em automatico, modo desligado       74   79,6    82     84     1113 amostras
E3b, manual no piso                      79 80 81 82 84 85  -> aborto aos 7 s
```

- **Acima de 69**: com carga só de CPU a rede não dispara. É o caso R2 da
  regra, que ficou com o usuário e ele não decidiu.
- **Acima de 75**: com o modo máximo ligado, um manual que gire como o
  automático não dispara — a GPU nem chega lá.
- **Abaixo de 79**: no traço do E3b a rede dispara 2 a 3 s depois da escrita
  do manual, 2 a 3 s antes do aborto, nas duas fases possíveis do relógio do
  agente.
- Com o modo desligado, o automático com jogo passa de 76 °C em 94% das
  amostras. Ali quem cala a rede é **não estar armada**, e há teste dizendo
  isso: o mesmo traço, com a ventoinha no piso, dispara.

### O que a execução refutou

1. **"O passivo da noite é o jogo com o modo máximo desligado."** O arquivo
   foi ligado assim às 19:31 e gravou três horas: dentro dele estão o E3b
   (duas amostras em `1,1`), cinco minutos das minhas mutações, a virada para
   o modo máximo às 21:26 e o fim do jogo. A janela que vale é das 19:50 às
   21:25 — armadilha 39.
2. **"Em automático, com jogo, a GPU pelo EC vai a 81"** — a seção 7 do
   plano, de uma linha de base de 26 minutos. Em 95 minutos foi a **84**. O
   limite de aborto, 85, está a um grau do que o automático faz sozinho.
3. **"Cada leitura do grupo sense custa uma chamada WMI"** — a premissa de
   `test_leituras_wmi.py`, que cobrava que o agente não lesse nenhum dos
   cinco. `fan_speed` não custa: 5 a 15 µs por leitura, contra 4,3 ms de
   `battery_limiter` e 6,2 de `usb_charging`. O teste passou a dizer isso, e
   a cobrar que é o único.
4. **"30 s de calor sustentado, pacote ou GPU"** — o desenho provisório da
   seção 11. Ficaram duas passadas, e só a GPU.
5. **"O canal da GPU do acer é uma chamada WMI cara."** 79 µs; cada rotação,
   95. O que custa milissegundos são os atributos do grupo sense.

### Sete coisas que só apareceram executando

1. **Um commit entrou com um teste vermelho.** A suíte ia por um `tail`, e o
   `&&` decidia pelo `tail`. Visto na saída, na hora, e emendado antes de
   seguir — armadilha 13b. Dali em diante a suíte roda por um roteiro que
   guarda o status de cada uma.
2. **Os dois observadores da sessão 1 seguiam vivos**, anexando linhas aos
   traços que esta sessão ia recortar. O recorte passou a ser por época.
3. **O modo novo do ensaio quebrou duas âncoras do corredor de mutações**: o
   trecho copiado do E3b passou a existir duas vezes no roteiro, e a mutação
   diria "o trecho aparece 2 vezes".
4. **Listar as mutações achou uma camada escondendo outra**: no fim do prazo
   do piso o modo `rede` escrevia `0,0` e saía — e o `trap` de saída
   escreveria igual. Sem a linha, o roteiro faz o mesmo; ela saiu (armadilha
   38).
5. **O piso não pode partir de qualquer temperatura.** A rede leva de 2 a 4 s
   e no piso a GPU sobe um grau por segundo; com o modo desligado o
   automático já a deixa em 80 a 84 °C. Partindo dali, o aborto aos 85 chega
   antes da rede, e a prova mediria o ponto de partida. O modo `rede` só
   escreve o piso com a GPU a seis graus ou mais do limite — de onde o E3b
   partiu; senão a prova não conta.
6. **Entrar em manual e mexer num cursor só põe o outro no piso.** Antes o
   outro ficava em zero, que era automático; com a barra valendo 20 a 100,
   zero é 20%. É o que a decisão do cursor pede, e a rede cobre.
7. **Uma mutação do modo `rede` escapou: "o limite no piso não encerra".**
   Sem a parada, o roteiro saía com o mesmo código 10 — só que depois de
   ficar no piso, acima do limite, até o prazo acabar. O teste olhava o
   código e o estado final, não **quando**. Passou a cobrar que o piso
   encerra na amostra em que o limite aparece. É a armadilha 38 de novo: o
   prazo cobria o buraco do limite.

### As mutações

| corredor | o que estraga | resultado |
|---|---|---|
| `tests/hardware/mutacoes-ensaio.py` | as proteções do roteiro de ensaio, 15 delas do modo `rede` | 58: **56 reprovadas, 2 equivalentes** (as duas "começa sem jogo aberto": a conferência seguinte recusa igual). As 43 de E2, E3 e E3b rodaram antes da última mudança do roteiro, que só toca o modo `rede`; as 15 dele, depois |
| `tests/hardware/mutacoes-rede.py` | o limiar, as passadas, o armar, a rotação, o que o agente lê e escreve | **27 de 27 reprovadas** |

### O portão — 2026-10-10, 23:36, a 2026-10-11, 01:11

Na tomada, `balanced-performance`, o jogo de sempre aberto pelo usuário. O
instrumento é `tests/hardware/ensaio-termico.sh rede`, rodado por bloco: um
minuto em automático, um em manual acima do equivalente, depois o piso
(20%), com os limites da seção 7 do plano vigiando.

```
                                        automatico        manual acima        piso, 20%
23:36  1.2.7, sem rede, modo ligado     6594 rpm, GPU 75  90%: 6978, GPU 72   GPU 73 -> 85 em 22 s; o roteiro
                                                                              abortou (codigo 10) e devolveu
23:44  1.2.8, modo ligado               6553 rpm, GPU 72  90%: 6955, GPU 72   a rede devolveu em 10,9 s, 3 s
                                                                              depois de cruzar 76; GPU ate 80
00:03  1.2.8, modo desligado,           6573 rpm, GPU 73  60%: 5014, GPU 78   a rede devolveu em 3,6 s;
       perfil de energia performance                      (>= 76 em 40 de 53) GPU de 78 a 79
00:19  1.2.8, modo desligado,           4520 rpm, GPU 65  60%: 4956, GPU 62   31 s, GPU de 62 a 74: a rede nao
       perfil de energia balanced                                             agiu, e nao devia (codigo 16)
```

- **A rodada "antes" reprovou, como devia**: o instrumento acusa a falta da
  rede na máquina de verdade. E mediu o que faltava — o piso com o modo
  máximo ligado: 0,55 °C por segundo, não um grau.
- **Em nenhum controle a rede agiu**: `fan_speed` não saiu de `0,0` nem do
  manual escrito, nas quatro rodadas.
- **Uma linha no journal por disparo**, e só elas:

  ```
  23:46:31 WARNING rede térmica: ventoinha em manual a 20,20 (2103 / 1751 rpm) com a GPU a 80 °C; devolvida ao automático
  00:05:26 WARNING rede térmica: ventoinha em manual a 20,20 (2077 / 1719 rpm) com a GPU a 79 °C; devolvida ao automático
  ```

- **Depois de agir ela não devolveu o manual**: 31 s em automático nas duas
  rodadas, e a rotação saiu do piso (2103 → 6534 rpm em 13 s).
- **O cursor**, pela mão do usuário, com um vigia de leitura: CPU em 50 e GPU
  no começo da barra escreveram `60,20`; os dois em zero, `20,20`, com a
  rotação a 2061 / 1707; "Automático", `0,0`.
- **A reinstalação**, duas vezes, por `pkexec`, com `install_nexus_sense` e a
  entrada em `/dev/null`: gid 948 antes e depois, instalado idêntico ao fonte
  (zero diferenças), `--version` 1.2.8, `NeedDaemonReload` em `no` nas duas
  units, agente e bandeja reiniciados pelo systemd do usuário (`agente no
  ar`, `bandeja: sni`). A segunda foi para entregar o conserto do Manual, que
  o próprio portão achou.

De carona, para a seção 12 do plano: com o modo máximo ligado e o jogo, a
bateria cedeu 7,9 pontos em 33 minutos com o cabo ligado (0,24 por minuto);
com o modo desligado, recarregou com o jogo aberto.

### O que o portão refutou

1. **"Modo máximo desligado quer dizer a curva baixa da ventoinha."** O
   usuário desligou o modo às 23:58 e, oito minutos depois, o automático
   seguia a 6550 rpm. O PowerMizer tinha sido liberado no mesmo segundo — o
   suspeito da sessão 1 está inocentado. O que sobrou ligado era o perfil de
   energia do sistema (`power-profiles-daemon`) em `performance`; passado a
   `balanced` às 00:08:47, a ventoinha foi a ~4500 / 4150 rpm em 90 s, e o
   pacote de ~90 para 65 a 69 °C. **A curva acompanha o perfil de energia,
   não o modo** — o modo só o liga. Um experimento, uma noite: o caminho
   dentro do EC continua sem apurar.
2. **"No modo desligado o controle a 60% está acima do automático."** Na
   rodada das 00:03 o automático girava 6573 rpm, e 60% são 5014: o controle
   rodou **abaixo** do automático real, e a GPU subiu de 73 para 78 °C nesse
   minuto. A rede não armou — pela tabela, modo desligado é equivalente de
   53% — e isso é a regra como foi escrita. O que a rodada prova é "desarmada
   e quente, não dispara"; não prova que a tabela descreve a máquina.
3. **"Com o modo desligado o piso parte de 80 a 84 °C."** Com o perfil de
   energia em `balanced` a mesma máquina, no mesmo jogo, roda a 63 °C de GPU;
   em 31 s de piso foi a 74. O regime do traço da noite — automático a ~4400
   rpm com a GPU a 80 — **não apareceu no portão**: ou a curva estava alta,
   ou a máquina estava fria. Ele está coberto pelo traço do E3b, não por uma
   rodada com a rede instalada.
4. **"Escolher Manual e depois mexer no cursor."** A janela repinta pelo
   firmware a cada passada da bandeja; com `fan_speed` ainda em `0,0`,
   remarcava Automático e escondia os cursores. Quem não mexia num cursor em
   cinco segundos perdia a escolha — o usuário viu duas vezes. O defeito é
   anterior a esta sessão; consertado, com teste que falhou primeiro.
5. **"O veredito do roteiro diz se a rede funciona."** Na rodada das 00:19
   ele disse `FALHOU`: a rede não agiu em 30 s. Não agiu porque a GPU não
   passou de 74 °C. O roteiro não conhece o limiar de propósito; quem lê o
   resumo confere o máximo da GPU antes de concluir.

### Três coisas que só apareceram no portão

1. **Um diálogo de senha que não era deste projeto.** Às 22:53 o usuário
   digitou a senha num pedido do polkit achando que era o da reinstalação,
   que ainda não tinha sido pedida. Era outro programa — o journal mostra o
   `systemd-resolved` limpando o cache no mesmo segundo. Nada instalado
   mudou. O pedido de root deste projeto vem depois do aviso no chat, e o
   diálogo mostra o comando.
2. **O teste do modo `rede` oscilou com um jogo aberto**, e a oscilação
   apontava um buraco de verdade: se o manual reaparecesse enquanto o roteiro
   ainda conferia a rotação, ele saía com 16 e deixava a ventoinha no piso.
   O roteiro passou a devolvê-la, e o teste ganhou folga para duas ou três
   amostras por segundo.
3. **A suíte de shell mede tempo, e a máquina ocupada muda o resultado.** Com
   o jogo rodando o `load1` passava de 15. O critério de aceite é a suíte na
   máquina em repouso; o que oscilar sob carga é teste a endurecer.

### Visto e não consertado

- **Com calor só de CPU a rede não age.** Manual no piso e uma compilação
  pesada: o pacote vai a 93 °C e a frequência cai 18%, como no E3. Decisão do
  usuário, ainda não tomada; se for sim, é um limiar de pacote a mais em
  `fan_guard.decide`, e o traço do E3 já está no repositório para fixá-lo.
- **Os dois equivalentes são de `balanced-performance`, na tomada.** Noutro
  perfil, e na bateria, vale o do modo desligado — sem medição.
- **A rede age em 2 a 4 s, e de 82 °C para cima isso pode não bastar** para
  chegar antes dos 85 do aborto. Não é dano. Passar o agente a 1 s enquanto
  armado encurtaria para 1 a 3 s; não entrou.
- **Zero num lado só ainda existe no firmware**: quem escrever `0,60` à mão
  deixa a ventoinha da CPU em automático. A tela mostra 0 e segue em manual.
- **Se o firmware larga o manual sozinho** (troca de perfil, suspensão) sem o
  driver saber, a rede vê a rotação alta e não age — o lado seguro. Não foi
  medido.
- **O shellcheck não roda nesta máquina**: `observador.sh`, o teste novo e o
  modo `rede` só passam por ele no CI, no primeiro push.
- **A tabela da rede é por modo, e a curva segue o perfil de energia.** Com o
  modo máximo desligado e o perfil em `performance`, o automático gira 6550
  rpm e a rede usa o equivalente de 53%: manual entre 53% e 80% fica
  desarmado, abaixo do automático real. Erra para o lado de não mexer, com a
  ventoinha acima do que a curva baixa gira. O conserto certo é o agente
  perguntar ao `power-profiles-daemon` em vez de ler o próprio modo — depois
  de medir a troca de curva nas duas direções, e mais de uma vez.
- **Desligar o modo máximo deixou o perfil de energia em `performance`.** Não
  foi apurado se o modo devolveu o que tinha guardado ou se não devolveu
  nada.
- **O regime "curva baixa e GPU a 80 °C" não rodou com a rede instalada.**
  Está no traço do E3b, que é teste.
- **Entrar em Manual a partir do Automático leva a ventoinha ao piso no
  clique.** É a decisão do usuário, e a rede cobre o jogo aberto; quem quer
  manual alto ouve a ventoinha cair por um instante antes de arrastar.

### Depois do merge, na mesma madrugada — v1.2.9

O usuário conferiu o conserto do Manual: ficou. E viu o que ele não
resolvia: *"não foi pro ponto que já estava marcado, que era o mínimo; tive
que subir e baixar pra baixar"*. Entrar em manual não escrevia — regra antiga
da tela — e, com a barra valendo 20 a 100, os cursores no começo mostravam um
piso que a máquina não estava fazendo. Perguntado, pelo efeito: **Manual
aplica na hora o que os cursores mostram.** Ramo `termica/2b-manual-aplica`,
teste que falhou primeiro.

De carona saiu um defeito mais antigo: arrastar os dois cursores a 100
escrevia `100,100`, a repintura lia "máximo" e escondia os cursores de quem
acabara de arrastá-los. A tela passou a lembrar o par que ela mesma escreveu.

**O CI da v1.2.8**, no primeiro push (`e655c6d`): verde. O shellcheck passou
nos três scripts novos, e pytest e a suíte shell passaram como usuário e como
root, em 9 min 40 s.

**O portão da v1.2.9**, em 2026-10-11, 02:08: terceira reinstalação por
`pkexec` (gid 948 antes e depois, instalado idêntico ao fonte, `--version`
1.2.9, `NeedDaemonReload` em `no`), agente e bandeja reiniciados. Com um
vigia de leitura no ar, o usuário clicou em Manual a partir do Automático:

```
02:08:45.443   fan_speed 0,0 -> 20,20     no clique, sem tocar em cursor
02:08:49.116   fan_speed 20,20 -> 0,0     o clique em Automatico; a rotacao ja estava em 2071 / 1718
```

O caminho a partir do Máximo foi conferido pelo usuário depois, à mão: entrou
em Manual vindo do Máximo e os cursores apareceram no fim da barra, e
ficaram.

**O CI da v1.2.9**, no push de `baf6fef`: verde. Shellcheck, e pytest e a
suíte shell como usuário e como root, em 9 min. O push que traz esta linha
dispara mais uma rodada, sobre uma árvore que só difere dela neste arquivo.

**Essa rodada foi cancelada, e foi a última.** O usuário perguntou o que era
"rodada de CI", ouviu, e respondeu: *"não quero isso não. qual
necessidade?"*. Nenhuma obrigatória. Desligado de vez no mesmo dia, ramo
`sem-ci`, sem versão nova — nada do que se instala mudou. O que se perdeu e
como voltar estão em [decisoes.md](decisoes.md), seção 22.

**E a rede disparou sozinha, no uso, sem roteiro nenhum.** Às 01:52, enquanto
o usuário conferia o Manual da v1.2.8 com o jogo aberto, ele levou os
cursores ao mínimo pela janela, e o journal tem a linha:

```
01:52:41 WARNING rede térmica: ventoinha em manual a 20,20 (2071 / 1727 rpm) com a GPU a 77 °C; devolvida ao automático
```

É o gesto do portão como a seção 15 do plano o descrevia — manual no piso
pela mão dele, com um jogo — e ninguém o pediu.

### Onde o próximo trabalho começa

`master` em v1.2.9, com a sessão 2 mesclada e o CI desligado. O baseline
esperado é 501 passam na suíte Python, sem xfail e, na shell, 23 passam e 2
pulam — sem root, sob `LC_ALL=C`, **e com a máquina em repouso**. Não há mais
rodada no GitHub: push é só push.

O que a medição deixou pedindo trabalho, em ordem de quanto pesa:

1. o que troca a curva da ventoinha — o perfil de energia é o suspeito, com
   uma noite de evidência — e, confirmado, a rede passar a perguntar por ele;
2. se desligar o modo máximo deve devolver o perfil de energia;
3. a decisão do caso R2: a rede age com calor que é só de CPU?

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

## Abandonado: brilho do teclado pelo slider do Plasma

**Medido em 2026-10-14 e decidido não fazer.** O `Brilho nan%` da linha
"Iluminação do teclado" no widget "Brilho e cor" é do UPower e do Plasma, não
nosso. Registrar um LED `acer::kbd_backlight` no driver faria o slider
funcionar, mas o firmware não deixa: o método 21 responde "não suportado" nos
três níveis, e o EC só guarda "acesa ou apagada" (bit 1 de `0x48`). O nível 1
ou 2 do Fn+F11 não aparece em lugar nenhum que o Linux leia. O método 20, de
gravação, ficou sem testar. A medição inteira e como refazer estão em
[decisões 23](decisoes.md).

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
  teste cai nos kernels reais da máquina e
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
