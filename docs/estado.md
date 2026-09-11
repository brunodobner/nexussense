# Estado do projeto

Mapa de onde o trabalho está. As specs descrevem cada projeto; este arquivo
diz qual é a vez de qual, e o que ficou pendente.

**Última atualização:** 2026-09-11 (v1.0.0: identidade própria, histórico resetado, remoto publicado)

---

## Onde estamos

| | |
|---|---|
| base | partiu do DAMX `1.0.2-h1` (commit `1f88341`) e seguiu sozinho; não rastreia mais o upstream |
| driver | funcional no ANV15-52; ~200 linhas divergentes da base do DAMX |
| versão | **v1.0.0** — primeira estável; `master` em github.com/brunodobner/nexussense (privado) |
| layout | reorganizado em 2026-09-10: só `setup.sh` executável na raiz |
| histórico | resetado na v1.0.0; a razão dos 111 commits foi para [decisoes.md](decisoes.md) e [armadilhas.md](armadilhas.md) |
| suíte shell | 17 testes: 15 passam, 2 pulam, 0 falham — **com e sem root** |
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
[~] Reparo da bandeja                instalado; falta gesto humano e novo login
[x] Ajustes visuais e de resposta    Diagnóstico, ventoinhas e cliques sem atraso
[x] Instalador da aplicação          dependências de execução verificadas e instalação reaplicada
[x] Modo Desempenho máximo           quinto modo do app; validado e instalado
[ ] Fases B-G das melhorias          spec 2026-09-05, secoes 4-9 (menos a 6)
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
A confirmação visual do usuário está pendente. Não se pediu novo reboot
antes dessa confirmação.

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

## Pendências conhecidas

Coisas verdadeiras hoje que alguém pode estranhar:

- **`SCRIPT_VERSION` e `release.txt` ainda dizem `1.0.2`.** A base é
  `1.0.2-h1`. O README já foi corrigido; estes dois são trabalho da fase G
  (spec §7).
- **As armadilhas 15 a 18 não estão escritas** em `docs/armadilhas.md`. Os
  textos estão na §9 da spec de melhorias, prontos para transcrever na fase
  G. A 18 é a mais importante: a tabela de quirks **não** diz o que o modelo
  usa, e enxugar por ela removeria o rfkill do wifi.
- **O bitmask de capabilities nunca foi medido.** É o passo zero da fase F
  (spec §4.4) e nada pode ser removido do driver antes dele.
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
