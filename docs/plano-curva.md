# Plano da curva própria — estudo, antes de qualquer código

Aberto em 2026-10-15. **Nada aqui foi implementado.** O que existe é medição,
leitura de código e os ensaios que faltam, cada um com a pergunta que responde.
Nenhum ensaio roda sem o seu OK. A regra que decide se haverá código está
escrita antes de medir, na seção 7.

"Curva própria" quer dizer: o agente escreve em `fan_speed` uma porcentagem
manual que depende da temperatura, passada a passada. Hoje ninguém faz isso.
O automático é do EC, e o Nexus Sense só escolhe entre automático, máximo e
manual fixo.

---

## 1. O que motivou

Na manhã de 2026-10-15, com um jogo aberto, você viu a temperatura alta e a
ventoinha sem subir na mesma medida. Passou para Manual a 100%. O que se leu
às 09:29, já em `100,100`, com o jogo ainda aberto:

```
ventoinhas        7646 / 7163 rpm
pacote (coretemp) 93 C       CPU pelo EC 84 C       GPU pelo EC 65 C
```

O estado da máquina naquela manhã, lido depois:

| | valor | desde |
|---|---|---|
| `fan_speed` na partida | `0,0` (automático) | `/etc/predator_state`, gravado no último desligamento |
| modo máximo | desligado | 2026-10-14 21:37 (`config.toml`) |
| perfil de energia (`power-profiles-daemon`) | `performance` | 2026-10-14 21:18 (`state.ini`) |
| EPP da CPU | `performance` | segue o perfil de energia |
| perfil térmico | `balanced-performance` | — |
| agente | no ar desde 06:39, **nenhuma linha** no journal | — |

**O que não se sabe:** quanto a ventoinha girava antes do clique. Nenhum
observador estava no ar.

**O que se mediu depois, no mesmo estado.** Às 09:51 você voltou para
Automático, com o jogo já fechado. O observador de M4 estava no ar:

```
09:51:14   6823 / 6398 rpm   descendo dos 100%
09:51:58   2175 / 1918       CPU pelo EC a 45 C
09:52:43   2255 / 2003       CPU pelo EC a 48 C   (assentou em 2160 a 2260)
```

É o repouso da **curva baixa**. A alta, a 50 °C, gira de 3350 a 3560 rpm
(seção 2.1). Então, com o modo máximo desligado e o perfil de energia em
`performance`, o EC estava hoje na curva baixa. O mais provável é que a
queixa da manhã tenha sido o teto dela, ~4500 rpm. Foi o que disse a primeira
resposta no chat. No meio desta sessão o plano chegou a dizer o contrário,
com base na noite de 2026-10-10/11. A seção 2.4 explica por que aquela noite
não prova o que parecia provar.

Repouso é evidência fraca: o automático não tem ponto de repouso fixo
(armadilha 37). Mas 2200 contra 3400 rpm, na mesma temperatura, é uma
distância grande. O teto com carga, em E-C2, fecha a questão.

---

## 2. O que já se sabe

### 2.1 A curva do EC tem teto — as duas

Medido em 2026-10-15 **sem esquentar nada**: os três traços passivos de
2026-10-10/11 (`~/.local/state/nexus-sense/passivo-20261010-*.tsv`),
deduplicados por segundo, só as amostras em automático e na tomada. São 5897
amostras. "Alta" é o modo máximo ligado; "baixa" é ele desligado, com o
perfil de energia presumido em `balanced`. A janela de 23:58 a 00:08:47, em
que o modo estava desligado e o perfil de energia ainda em `performance`,
entrou à parte: 153 amostras, todas entre 6514 e 6594 rpm.

```
rotacao da ventoinha da CPU (mediana) pela CPU pelo EC

CPU pelo EC     curva alta            curva baixa
  50-54 C       3558 rpm  (n=794)     3636  (n=6)
  60-64         4400      (n=313)     4667  (n=466)
  70-74         6073      (n=351)     5097  (n=137)
  80-84         6553      (n=166)     4455  (n=164)
  90-94         6573      (n=439)     4501  (n=908)
```

- **A curva alta sobe de ~3500 a ~6550 rpm entre 50 e 75 °C, e para ali.** De
  75 a 99 °C não passa de 6594.
- **A curva baixa para em ~4500 rpm a partir dos 80 °C.** Com a CPU a 90–94 °C
  ela girou 4501 rpm, em mediana, em 908 amostras.
- **Nenhuma das duas usa a ventoinha inteira.** O máximo do firmware gira 7539
  rpm (E2). Pelo mapa de E2, os tetos equivalem a um manual de ~54% (baixa) e
  ~85% (alta).
- A corcova da curva baixa entre 65 e 74 °C (5000 a 5100 rpm) é, muito
  provavelmente, transição: as amostras logo depois de 00:08:47, quando a
  rotação descia de 6553. Não é traço da curva, e não pesa em nada adiante.

**Que sensor o EC segue, os traços não separam.** Na curva alta, a faixa de
2 °C de quase qualquer sensor explica 80 a 89% da variância da rotação (CPU
pelo EC com 10 s de atraso: 0,89; `SEN2`: 0,87; GPU pelo EC: 0,85). Eles
sobem juntos, e o passivo não tem como desatar. Na baixa, nenhum explica mais
que 0,41 — porque ela é quase plana, e plano não tem variância para explicar.

### 2.2 O que o driver faz com uma escrita em `fan_speed`

Lido em `driver/src/nexus_sense.c`, em `acer_set_fan_speed`:

- **`100,100` não é "manual a 100%".** O driver manda ao firmware o
  comportamento de máximo (`0x820009`), um modo à parte. O manual vai de 1 a
  99, por ventoinha, com passo de 1%. Os 7539 rpm de E2 eram esse máximo; o
  manual a 95% girou 7139.
- **Suspensão e retomada não tocam na ventoinha.** `acer_suspend` não faz nada
  e `acer_resume` só reinicia o acelerômetro. Se o EC guarda o manual através
  de uma suspensão, ninguém mediu.
- **`quiet` e `low-power` escrevem `0,0`** na troca de perfil.
- **O manual atravessa o reinício.** O estado se grava no `rmmod` do
  desligamento, separado por fonte de energia, e volta na partida, antes de o
  agente subir.
- **O EC obedece ao manual até o fim.** E3: dez minutos no piso, com a CPU a
  91–94 °C, sem tomar a ventoinha de volta. E3b: a GPU no limite em sete
  segundos, com um jogo. A única rede é a do agente (`fan_guard.py`).

### 2.3 O que a rotação compra, até onde se mediu

Só um ensaio variou a rotação com tudo o mais parado: E3, carga só de CPU,
perfil de energia em `balanced`.

```
rotacao          2056 rpm    2623      4455 (automatico)
frequencia       2965 MHz    3286      3634      (no ultimo minuto de carga)
```

De 2056 para 2623 rpm a frequência subiu 566 MHz por mil rpm. De 2623 para
4455, 190 MHz por mil rpm. **O retorno cai depressa.** Acima de 4455 rpm,
com o perfil de energia fixo, não há medida nenhuma.

O jogo com e sem o modo máximo (plano térmico, seção 2) não serve para isso.
Com o modo ligado a ventoinha girava 1900 rpm a mais, a frequência média era
12% maior e o throttle caiu de 18% para 8,9%. Mas o modo também troca o perfil
de energia da CPU e o PowerMizer da GPU, e os três efeitos estão misturados.

### 2.4 Quem troca de curva — não se sabe

A armadilha 37 aponta o perfil de energia, com uma noite de evidência. Duas
coisas, medidas hoje, enfraquecem essa leitura:

- **Hoje o perfil de energia está em `performance` e o EC está na curva
  baixa** (seção 1). Sozinho, o perfil não basta.
- **A queda daquela noite cabe dentro da curva alta.** Com o perfil passado a
  `balanced`, a rotação foi de 6550 a ~4500 rpm e o pacote de ~90 a 65–69 °C.
  Na curva alta, 65–69 °C dão 4991 rpm em mediana (seção 2.1). A queda pode
  ter sido a CPU esfriando, com menos potência, e não uma troca de curva.

O daemon aqui tem `PlatformDriver=placeholder` no `state.ini`. Ele não mexe
no perfil térmico, **só no EPP da CPU**. O EC não lê o perfil de energia.

**Os suspeitos que sobram** estão no que o modo máximo faz ao ligar: a
escrita do perfil térmico pelo WMI e o PowerMizer da GPU. E na noite de
10/11 a curva alta seguiu oito minutos depois de o modo desligar. Então algo
liga a curva alta e ela fica até outro evento a desligar. Um reinício, por
exemplo, pois hoje a máquina partiu com o modo já desligado. O caminho dentro
do EC é fechado. E-C2 testa cada alavanca separada (seção 6).

---

## 3. As duas formas de curva

| | o que faz | o que você ouve | se o agente morrer |
|---|---|---|---|
| **A — reforço** | abaixo de um limiar, `0,0`: o EC decide; acima, manual, do teto do EC até 99% ou o máximo | nada muda no uso leve; com calor, a ventoinha passa do teto do EC | a ventoinha fica alta: **barulho, não calor** |
| **B — curva inteira** | o agente decide em toda a faixa, inclusive abaixo do EC | dá para ter repouso mais silencioso: o piso gira ~2000 rpm, e o EC em repouso gira de 2240 a 3550 | a ventoinha pode ficar baixa com um jogo aberto. E a rede morre junto, porque mora no mesmo processo |

A forma A só sobe acima do EC. Ela nunca deixa a máquina mais quente do que o
automático, e por isso não precisa de rede própria. A forma B é o caso que a
rede existe para cobrir (E3b), e precisaria de um guarda fora do agente.

**Qual das duas é preferência sua.** A pergunta é o que incomoda mais: o
ruído em repouso ou a ventoinha que não sobe com calor. Em 2026-10-10 você
disse que a ventoinha "mantém uma faixa superior" mesmo com a máquina quase
parada. Hoje, que ela não subiu com o calor. As duas queixas existem.

**O que já foi decidido e continua valendo.** A rede "não inventa curva — a
do fabricante é a que ele validou" (`fan_guard.py`). Isso é sobre a rede: ela
devolve o automático, e nada aqui a muda. A curva seria uma escolha sua, ao
lado da rede, e nunca no lugar dela.

**Onde a forma A poderia morar.** Num modo novo da janela ou dentro do modo
máximo. A intenção do modo máximo é "extrair 100% da máquina para jogos, sem
se importar com o custo" (decisões, seção 19). Hoje ele deixa a ventoinha no
automático, que para em ~85%. Fica para depois da seção 7.

---

## 4. As perguntas, em ordem de dependência

| | pergunta | quem responde | depende de |
|---|---|---|---|
| C1 | o que escolhe a curva do EC: o perfil de energia, o modo máximo ou outra coisa? E ela fica presa depois? | M4 (passivo) e os estágios em automático de E-C2 | — |
| C2 | quanto a rotação **acima do teto da curva alta** compra em frequência e temperatura? | E-C2 | — (o ensaio mede o teto na hora, e o controle acusa se a curva for outra) |
| C3 | que rotação incomoda, jogando e trabalhando? | E-C3 — **preferência sua** | — |
| C4 | uma escrita a cada passada se ouve como degrau? quanto custa? | E-C3, de carona; o custo vem da leitura | — |
| C5 | o firmware larga o manual na suspensão, na troca de fonte ou na troca de perfil? | E-C5 | só se for a forma B |
| C6 | quem devolve a ventoinha se o agente morrer? | leitura da unit e o exercício do vigia | a forma escolhida |

---

## 5. O que já foi medido nesta sessão (2026-10-15)

- **M1 — a curva do EC, dos traços.** A seção 2.1. Não esquentou nem escreveu
  nada.
- **M2 — o driver.** A seção 2.2.
- **M3 — o estado da manhã.** A seção 1.
- **M4 — um observador passivo no ar**, de 09:38 até ~21:38, a cada 5 s:
  `tests/hardware/observador.sh` gravando em
  `~/.local/state/nexus-sense/passivo-20261015.tsv`. Ao lado, um registro do
  perfil de energia e do EPP (`ppd-20261015.tsv`), porque o observador não tem
  essa coluna. Os dois só leem: sem root e sem `nvidia-smi`. Às 09:51 ele já
  gravou o repouso da seção 1. Se você jogar hoje em automático, ele grava o
  cenário da queixa: em que curva o EC está, onde ela para, e com que
  temperatura.

O que M4 **não** grava: a potência da CPU. O `energy_uj` do RAPL é `0400 root`
neste kernel.

---

## 6. Os ensaios que faltam

Valem as regras do plano térmico, seção 5: um comando só, a condição medida a
cada amostra, o sensor achado pelo nome, nada de `nvidia-smi`, a bateria por
`charge_now`, os limites de aborto da seção 7 de lá, e o traço gravado em
`~/.local/state/nexus-sense/`. O combinado da seção 9 de lá também vale. Duas
colunas novas entram no traço: o perfil de energia e o EPP.

**Nenhum estágio de E-C2 gira abaixo do automático.** Ou é o próprio
automático, ou é um manual acima do teto dele. Então nenhum estágio esquenta
mais do que a máquina esquenta sozinha, e o pior desfecho de uma falha é
barulho. Os limites de aborto vigiam assim mesmo.

Os ensaios pedem modos novos em `tests/hardware/ensaio-termico.sh`, testados
contra a árvore falsa antes de encostar na máquina. **Isso é código de teste,
e fica para depois da aprovação deste plano.**

### E-C2 — qual curva, e o que a rotação acima do teto compra

Uma rodada só responde C1 e C2. A primeira versão deste plano tinha dois
ensaios: E-C1 só com automático e E-C2 com a escada de manuais. Os estágios em
automático de E-C2 já medem o teto de cada estado, então E-C1 virou parte
dele.

A segunda versão trocava só o perfil de energia. A medida das 09:51 (seção 1)
derrubou isso: o perfil sozinho não pôs o EC na curva alta. Agora o ensaio
mexe numa alavanca de cada vez, inclusive no modo máximo.

| | |
|---|---|
| pergunta | C1 e C2 |
| condição | sem jogo, na tomada, bateria a partir de 60%, `fan_speed` em `0,0`, perfil térmico `balanced-performance` |
| carga | 8 processos de CPU, cada um debaixo de `timeout`, por 180 s em cada estágio. Entre dois estágios, descida até o pacote voltar a 60 °C ou 120 s |
| estágios | todos com a mesma carga. **1** automático no estado de hoje: modo máximo desligado, perfil de energia `performance`. **2** automático com o perfil em `balanced`. **3** automático com o modo máximo **ligado**. **4** manual que gira o teto medido no 3 (o controle). **5** manual a 92%. **6** máximo do firmware (`100,100`). **7** automático com o modo ligado, de novo. **8** automático logo depois de desligar o modo. **9** automático com o perfil em `balanced`. **10** automático com o perfil em `performance`, sem o modo. No fim, o modo máximo e o perfil de energia voltam ao que estavam |
| o modo máximo | ligado e desligado por você, na bandeja. É a mesma via do uso, com o PowerMizer e o perfil térmico que só ela aciona. O roteiro espera o `config.toml` mudar e confere |
| por que esses manuais | o estágio 4 é o teto da curva alta, medido na hora e traduzido pelo mapa de E2: é o controle. 92% fica no meio do caminho até o máximo. O máximo do firmware é o topo que existe. 99% saiu: gira ~90 rpm abaixo do máximo, e não decide nada |
| controle | o estágio 4 tem de girar como o teto do estágio 3, a ±300 rpm. Se não girar, o mapa de E2 não vale sob carga, e o ensaio para |
| o que mede | no último minuto de cada estágio: frequência média, tempo em throttle, pacote, CPU e GPU pelo EC, `SEN2` a `SEN5` |
| C1 | o teto de cada estágio em automático diz qual alavanca escolhe a curva. Se 1, 2, 9 e 10 ficarem na baixa e 3 e 7 na alta, é o modo máximo, por algo além do perfil de energia. O estágio 8 diz se a curva alta fica presa depois de o modo desligar, como na noite de 10/11. Se 10 ficar na alta e 1 não, ela fica presa até um reinício. Se nada disso fechar, o DSDT (E1 do plano térmico) volta à mesa |
| o ruído da medida | os estágios 3 e 7 são o mesmo automático, com o mesmo modo. A diferença entre eles é o quanto a medida varia sozinha. A regra da seção 7 usa esse número |
| opcional, com root | a potência do pacote pelo RAPL, para ver se o EC segue potência e não temperatura. Pede `pkexec`, e por isso é opcional |
| com o jogo | depois da parte de CPU, sempre, com o modo máximo ligado: três minutos em cada um de automático, máximo do firmware e automático de novo, com o jogo de sempre numa cena parada. A queixa nasceu num jogo, e a GPU é quem tem o limite mais apertado. O gesto é seu |
| o que pede de você | autorização para o roteiro trocar o perfil de energia e devolvê-lo no fim; os gestos do modo máximo e do jogo |
| duração | ~45 min a parte de CPU; ~10 min a do jogo |

### E-C3 — o ouvido

| | |
|---|---|
| pergunta | C3 e C4 — **preferência sua** |
| condição | repouso, sem jogo |
| o que faz | a ventoinha passa por 30, 45, 55, 65, 75, 85, 92 e 99% e pelo máximo, 15 s em cada. Você diz até onde aceita jogando e até onde aceita trabalhando. Depois, degraus de 5% em torno do limite: você diz se ouve a troca |
| duração | ~5 min |

### E-C5 — o que larga o manual (só para a forma B)

Com o manual a 95% (alto, para uma falha ser barulho): suspender e retomar,
tirar e pôr o cabo, trocar o perfil térmico, e reiniciar a máquina. Em cada
um, o roteiro lê a rotação e o `fan_speed`. O reinício diz o que volta na
partida antes do login. São gestos seus. ~10 min.

**O exercício do guarda**, na mesma rodada e também a 95%: o agente leva um
`kill -9`, e depois um `SIGSTOP` (travado, mas vivo). Nos dois casos a
ventoinha tem de voltar a `0,0` sem ninguém tocar nela, e a rotação tem de
sair do manual, no prazo que o desenho da seção 8 fixar. Mede-se o efeito,
nunca só o código de saída (armadilha 11).

---

## 7. A regra, escrita antes de medir

"Ganho" é o máximo do firmware contra o automático, os dois com o modo
máximo ligado, que é a resposta que já existe para o calor. Na parte de CPU,
é o estágio 6 contra a média dos estágios 3 e 7. No jogo, é o máximo contra a
média dos dois automáticos.

| o que E-C2 mostrar | o que se faz |
|---|---|
| **R0.** Na CPU, ganho de frequência **abaixo de 5%** ou abaixo do ruído da medida; e no jogo, GPU pelo EC menos de **3 °C** mais fria | a ventoinha acima do teto da curva alta não compensa. **A forma A não se faz**: no calor, a curva devolve a ventoinha ao EC. O conselho para o calor fica sendo jogar com o modo máximo ligado. Se ajudar, a janela passa a mostrar em que curva o EC está |
| **R1.** Na CPU, ganho de 5% ou mais **e** acima do ruído; ou, no jogo, 3 °C ou mais | a forma A se justifica. Os limiares saem dos traços de E-C2 e o teto de ruído sai de E-C3 |

O ganho contra a curva baixa não entra na regra. Ele deve ser maior, mas para
esse caso já existe conserto: ligar o modo máximo.

**A forma B não passa por esta regra.** Você a quis (seção 10), e ela não
depende de ganho de desempenho: é silêncio em repouso. Ela depende de E-C5 e
do exercício do guarda, na seção 6. Se E-C5 mostrar que o firmware larga o
manual sem avisar e volta a ele em seguida, ou que o reinício devolve um
manual baixo sem ninguém por perto, a forma B espera um desenho que cubra
isso.

**Por que 5% e 3 °C.** A troca inteira do modo máximo subiu a frequência em
12% e cortou o throttle pela metade (plano térmico, seção 2). Um ganho de
menos da metade disso, só pela ventoinha, não paga o barulho. E num jogo de 95
minutos em automático a GPU pelo EC variou 2 °C entre o p95 e o máximo (82 e
84, plano térmico, seção 7): uma diferença de 2 °C entre duas rodadas de jogo
pode ser só o jogo. Os dois números ficam fixados nesta revisão. Depois dela
nenhuma medição os move.

---

## 8. O desenho — esboço, não código

A parte de cima da curva (forma A) depende da regra da seção 7. O resto vale
de qualquer jeito, porque a forma B foi pedida.

- **Onde mora.** No agente, que já passa a cada 2 s. Uma função pura num
  módulo próprio, como `fan_guard.py`, testada com os traços passada a
  passada.
- **O que lê.** Decidido por E-C2: o sensor que acompanhar o ganho. Candidatos:
  o pacote pelo `coretemp` (sem WMI), a GPU pelo EC (uma chamada WMI) ou o
  maior dos dois. Uma curva por ventoinha só se E-C2 mostrar que vale.
- **Como anda.** Sobe depressa, porque a GPU ganha um grau por segundo
  (E3b). Desce devagar, com histerese, para a ventoinha não pulsar. O passo
  sai de E-C3.
- **Quando escreve.** Só quando a porcentagem muda. Cada escrita custa de uma a
  três chamadas WMI. Uma chamada mediu 4,3 a 6,2 ms em `battery_limiter` e
  `usb_charging`; a escrita em si não foi medida.
- **Onde aparece.** Num quarto modo da janela e da bandeja, "Curva", ao lado
  de Automático, Máximo e Manual. Com a forma B a curva manda também no
  repouso, e isso não cabe no modo máximo, que é desempenho.
- **Com o que convive.**
  - **A rede.** As duas moram no agente. Se a curva escrevesse abaixo do
    equivalente do automático com a GPU quente, a rede escreveria `0,0` e a
    curva reescreveria o manual na passada seguinte: vaivém. Então a função
    da curva tem de cumprir o invariante da rede: com a GPU pelo EC a 76 °C
    ou mais, nunca abaixo do equivalente. Os traços da rede viram teste da
    curva. A rede fica no ar como checagem independente. Se ela disparar com
    a curva ativa, é defeito da curva: o modo volta a Automático, como já
    acontece com o Manual, e a linha no journal diz isso.
  - O modo máximo escreve `0,0` ao ligar.
  - `quiet` e `low-power` escrevem `0,0`: a curva fica desligada nesses perfis.
  - Na bateria a curva não age.
- **Sem sessão não há curva.** O agente é serviço de usuário. Antes do login,
  e depois do logout, a ventoinha fica no que o driver tiver. No desligamento
  o driver grava o manual que estiver valendo, e ele volta na partida antes
  do agente. A unit do driver (`nexus_sense.service`) não tem ordem garantida
  contra a sessão do usuário, então não dá para contar com o agente
  devolvendo `0,0` antes da gravação. Com a forma B, isso pode deixar um
  manual baixo na tela de login. Sem jogo e sem sessão, é o caso R2 do plano
  térmico: a máquina se sustenta cortando frequência. E-C5 mede o que volta.
- **Se o agente morrer ou travar.** Duas camadas do systemd, as duas sem
  root, porque a unit é de usuário e a escrita passa pelo grupo:
  - `ExecStopPost` escreve `0,0`. O systemd o roda em toda parada, inclusive
    depois de `kill -9`, falta de memória e logout. A unit já tem
    `Restart=always` e `RestartSec=3`: o agente volta e retoma a curva.
  - `WatchdogSec`, com o laço avisando o systemd a cada passada (`sd_notify`
    pelo `$NOTIFY_SOCKET`, sem dependência nova). Um agente travado para de
    avisar, o systemd o mata, e o `ExecStopPost` devolve `0,0`.

  **O mecanismo, conferido em 2026-10-15** com duas units de usuário
  descartáveis (`systemd-run --user`), sem tocar na ventoinha. Uma levou
  `kill -9`, e o `ExecStopPost` rodou no mesmo segundo. A outra, com
  `Type=notify` e `WatchdogSec=3`, avisou uma vez e parou de avisar. O
  systemd a encerrou com resultado `watchdog` e o `ExecStopPost` rodou ~3 s
  depois do último aviso. Falta a prova com a ventoinha: o exercício do
  guarda (seção 6, E-C5).

  **O guarda, implementado em 2026-10-15** (ramo `curva/guarda`; não
  instalado). Três decisões a mais do que este esboço dizia:

  - **Só o que o agente escreveu.** O esboço mandava o `ExecStopPost`
    escrever `0,0` sempre. Isso faria todo logout e todo reinício perder o
    Manual escolhido na janela, que hoje atravessa os dois. Então o agente
    registra, antes de cada escrita, o valor de antes e o novo em
    `$RUNTIME_DIRECTORY/ventoinha` (`guarda.py`), e o `ExecStopPost`
    (`packaging/scripts/guarda-ventoinha.sh`) só devolve o automático se
    `fan_speed` for um desses dois. Um Manual da janela fica como está: com
    o agente morto ninguém o protege, como hoje.
  - **`WatchdogSignal=SIGKILL`.** O padrão é `SIGABRT`, que faz core dump, e
    o `systemd-coredump` atrasaria o `ExecStopPost`.
  - **`WatchdogSec=6`:** três passadas.

  Medido com units descartáveis, `ProtectSystem=strict` como a do agente, o
  guarda de verdade e um `fan_speed` de mentira: com `kill -9`, o `0,0`
  chegou em 54 ms; com `SIGSTOP`, em 5,8 s. O `RuntimeDirectory` fica
  gravável sob `ProtectSystem=strict`, o `ExecStopPost` recebe o
  `$RUNTIME_DIRECTORY`, e a pasta só some depois dele.

  O E-C5 registra pelo agente o manual que escreve: sem isso o guarda o
  trataria como um Manual da janela, e não o devolveria.

---

## 9. O que fica de fora

- **Mexer na curva do EC.** O código do EC é fechado. O DSDT só se lê, e só
  se E-C2 deixar dúvida sobre C1.
- **Curva no driver.** É política dentro do kernel: cada ajuste pediria DKMS e
  reinício. A decisão 1 de [decisoes.md](decisoes.md) pôs a política no
  espaço de usuário.
- **Chamar o `nvidia-smi`** para ler a GPU (armadilha 20).

---

## 10. A revisão do plano — 2026-10-15

Feita logo depois de escrito, ramo a ramo. Os ramos técnicos se fecharam pelo
código e pelos traços. Só gosto e autorização foram ao usuário.

**Fechado sem perguntar:**

- **E-C1 entrou em E-C2.** Os estágios em automático de E-C2 já medem o teto
  de cada estado. Uma rodada só.
- **E-C2 mexe numa alavanca de cada vez, inclusive no modo máximo.** O
  repouso das 09:51 mostrou o EC na curva baixa com o perfil de energia em
  `performance`. A versão que só trocava o perfil não teria achado o gatilho.
- **A escada é o teto medido, 92% e o máximo do firmware.** 99% saiu: gira ~90 rpm
  abaixo do máximo e não decide nada.
- **A regra compara o ganho com o ruído da própria rodada**, medido entre os
  estágios 3 e 7, além dos limiares fixos.
- **5% e 3 °C ficaram fixados**, com a origem de cada um na seção 7.
- **A parte com o jogo não é mais opcional.** A queixa nasceu num jogo, e a
  GPU tem o limite mais apertado.

**Perguntado ao usuário:**

- **A forma: as duas.** A pergunta foi o que incomoda mais, a ventoinha que
  não sobe com calor ou o barulho com a máquina parada. A recomendação era só
  a forma A, que responde à queixa do dia. A resposta foi **as duas coisas**.

**Fechado em consequência:**

- **A curva é um modo próprio, "Curva".** Com a forma B ela manda no repouso,
  e isso não cabe no modo máximo.
- **E-C5 passa a rodar**, com o reinício e o exercício do guarda.
- **O guarda fora do agente** é `ExecStopPost` com `0,0` mais `WatchdogSec`
  (seção 8).
- **A curva cumpre o invariante da rede**, e a rede disparando com a curva
  ativa desliga a curva (seção 8).
- **R0 não cancela a curva inteira**, só a parte de cima (seção 7).

**Em aberto, e de quem depende:**

| | o quê | depende de |
|---|---|---|
| o teto de ruído | até que rotação se aceita jogando e trabalhando | E-C3, preferência do usuário |
| a autorização de E-C2 | trocar o perfil de energia, esquentar a CPU por ~45 min, e os gestos do modo máximo | o roteiro pronto e testado |
| os gestos de E-C5 | suspender, tirar o cabo, reiniciar | o roteiro pronto e testado |
| a parte de cima da curva | se existe | R0 ou R1, depois de E-C2 |

---

## 11. A curva aprovada — 2026-10-15

Desenhada na conversa com o usuário a partir do que já estava medido: os tetos
da seção 2.1 e o mapa de E2 (plano térmico, seção 6). Ele a aprovou sem esperar
E-C2 e E-C3: a forma da curva é preferência dele (seção 3), e ele a escolheu.
Nada foi implementado.

**O que muda no resto do plano:**

- **Uma curva só.** Ela vale com o modo máximo ligado ou desligado; não há uma
  curva alta à parte. O modo máximo segue fazendo o resto (perfil de energia,
  PowerMizer). Como os dois convivem na janela e na bandeja fica para o
  desenho.
- **A regra da seção 7 não decide mais a parte de cima.** Ir ao máximo no
  calor é escolha do usuário. E-C2 continua dizendo quanto isso compra, mas
  deixa de ser portão.
- **E-C3 não é mais preciso para o teto de ruído:** o usuário aceitou o
  máximo jogando e 2.300 / 2.000 rpm em repouso.
- **E-C5 e o guarda seguem obrigatórios.** Entre 50 e 70 °C a curva gira
  abaixo do firmware: é a forma B.

**A ventoinha da CPU**, pela CPU pelo EC (o sensor da tabela da seção 2.1):

| CPU pelo EC | rpm | manual (mapa de E2) | firmware hoje, curva baixa |
|---|---|---|---|
| até 50 °C | 2.300 | 25% | ~2.200 |
| 60 °C | 3.000 | 35% | ~4.650 |
| 70 °C | 4.200 | 50% | — (só transição) |
| 80 °C | 5.800 | 73% | ~4.450 |
| 88 °C ou mais | 7.450 | 99% | ~4.500 |

**A ventoinha da GPU**, pela GPU pelo EC:

| GPU pelo EC | rpm | manual (mapa de E2) | firmware hoje, com jogo |
|---|---|---|---|
| até 55 °C, ou 0 (placa dormindo) | 2.000 | 24% | ~2.000 em repouso |
| 65 °C | 3.000 | 37% | — |
| 70 °C | 4.200 | 53% | — |
| 76 °C | 6.000 | 82% | ~4.000 |
| 80 °C ou mais | 6.980 | 99% | ~4.000 |

Entre dois pontos, a porcentagem anda em linha reta com a temperatura. As
rotações são as do mapa de E2, medido em repouso.

**As regras em volta:**

- **O piso da rede.** Com a GPU pelo EC a 76 °C ou mais, as duas ventoinhas
  ficam no mínimo em 81% e 82%: o equivalente do automático com o modo máximo
  ligado (`fan_guard.AUTOMATICO[True]`), o mais alto dos dois. A rede olha as
  duas ventoinhas, não só a da GPU (conferido em `fan_guard.py`). Sem esse
  piso, um jogo com a CPU a 80 °C poria a ventoinha da CPU a 73%, abaixo dos
  81%. A rede devolveria o automático, e a curva reescreveria o manual na
  passada seguinte: vaivém.
- **Sobe na hora, desce devagar.** A rotação sobe na passada em que a
  temperatura pede. Só desce depois de a temperatura cair 3 °C abaixo do
  ponto que a fez subir. Os 3 °C são provisórios: ajustam-se pelo ouvido.
- **Só escreve quando a porcentagem muda.**
- **Fora dela:** `quiet` e `low-power`, em que o driver escreve `0,0` (o
  que o firmware faz com a ventoinha nesses perfis nunca foi medido: todo
  traço é de `balanced-performance`); e a bateria.
- **Sem o guarda da seção 8 a curva não entra no ar.** Um agente travado a
  25%, com a máquina esquentando depois, ficaria sem ninguém que subisse a
  rotação: a rede mora no mesmo processo.

Esta seção substitui, na tabela "Em aberto" da seção 10, as linhas do teto de
ruído e da parte de cima da curva.

**A versão curta, escrita em 2026-10-15** (ramo `curva/guarda`; não
instalada). O usuário preferiu a curva no ar antes do botão na janela:

- **Liga-se no arquivo**, com `fan_curve = true` em
  `~/.config/nexus-sense/config.toml`. Desligada por padrão.
- **"Automático" na janela passa a querer dizer a curva**, enquanto ela
  estiver ligada: a curva age sempre que `fan_speed` está em `0,0` ou no
  valor que ela mesma escreveu. Isso inclui o modo máximo, que escreve
  `0,0` ao ligar — é a curva única que o usuário pediu.
- **"Manual" na janela a suspende**: um valor em `fan_speed` que ela não
  escreveu é de outra mão, e ela espera o `0,0` voltar.
- **Ao subir o agente, a ventoinha é dela.** Depois de um reinício o driver
  devolve o manual gravado no desligamento, e o agente novo não tem como
  saber de quem era.
- **A CPU pelo EC e a GPU pelo EC**, as duas pelo rótulo do canal
  (`telemetry.acer_cpu_temp`, `acer_gpu_temp`). Uma leitura que falha segura o
  valor de agora; três seguidas devolvem o automático.
- **A rede segue no ar.** Se ela disparar com a curva ativa, é defeito da
  curva: o agente grava `fan_curve = false` e diz isso no journal.
- **Provado contra os traços** (`tests/python/test_curva.py`): em todas as
  passadas gravadas, com a GPU a 76 °C ou mais, as duas ventoinhas ficam no
  piso da rede, e a rede nunca dispara com a curva.

**A primeira rodada na máquina, 2026-10-15 às 22:00**, instalada do ramo,
com a curva ligada por um minuto, sem jogo, com outra sessão rodando Python e
LibreOffice em rajadas. O agente subiu como `Type=notify`, com o watchdog de
6 s, e passou o minuto sem uma morte. A curva escreveu o que a tabela manda,
registrou cada escrita, e devolveu o automático quando foi desligada. Mas a
CPU pelo EC pulava — 54 a 88 °C e de volta em vinte segundos —, e a curva
seguia cada pulo: a ventoinha da CPU foi de 2.770 a 7.460 rpm e voltou em
segundos. Os 3 °C de histerese não seguram pulos assim. A curva foi
desligada na hora, e corrigida:

- **A temperatura que a curva usa é a mediana das últimas cinco passadas**
  (10 s), não a leitura de agora. Um ou dois pulos não movem a ventoinha;
  uma carga que dura a move em ~5 s. O firmware faz parecido: a rotação dele
  acompanha a CPU pelo EC com uns 10 s de atraso (seção 2.1).
- **Desce no máximo 4 pontos por passada:** de 99% a 35% em ~30 s.
- **O piso da GPU quente segue imediato**, pela leitura de agora: é a
  segurança da rede, e a GPU sobe um grau por segundo com um jogo (E3b).

**A segunda rodada, logo depois, com a correção instalada:** dois minutos, a
CPU pelo EC a 80–88 °C nos primeiros 55 s. A ventoinha da CPU subiu a 90–93%
(~7.100 rpm) e ficou; com a carga fora, desceu de 93% a 31% (~2.700 rpm) em
~30 s, sem tranco; um pulo a 90 °C aos 120 s não a moveu. A da GPU, com a GPU
a 45–51 °C, ficou em ~2.000 rpm. Nenhuma morte pelo watchdog. A curva ficou
ligada.

**E-C5 na máquina, 2026-10-15 22:22 e 2026-10-16 07:31.** Duas tentativas, e
nenhuma passou da suspensão:

- **A primeira parou pelo limite de repouso** (pacote a 85 °C por três
  amostras), com a ventoinha a 95%: o Brave e uma verificação de outra sessão
  ocupavam três núcleos. O aborto fez o que devia — devolveu `0,0` e a
  rotação saiu do manual. Foi o controle positivo do aborto, na máquina.
- **A segunda achou duas coisas na volta de uma suspensão de 30 s (S3):**
  - **O watchdog matou o agente ao acordar** (`Failed with result
    'watchdog'`). O systemd contou o tempo dormindo como tempo sem aviso. O
    guarda rodou e fez o certo: o 95% era do roteiro, não do agente, e
    ficou. O agente voltou em 3 s. Isso se repete a cada suspensão.
  - **O firmware largou o manual e trocou o perfil.** Na primeira amostra
    depois de acordar, a rotação era 2.241 / 2.103 rpm com `fan_speed`
    ainda dizendo `95,95`, e o perfil térmico tinha ido de
    `balanced-performance` para `balanced` — com o agente já morto, então
    não foi ele. É a resposta a C5 para a suspensão: o firmware larga o
    manual sem avisar, e a memória do driver fica mentindo. O roteiro parou
    nessa amostra (o perfil mudou), então não se viu se ele volta.

**O que isso pede, antes de rodar o E-C5 de novo:**

- **A curva precisa reescrever o manual depois de uma suspensão.** Ela
  compara o que escreveu com `fan_speed`, e os dois batem: sem reescrever,
  o firmware fica no automático e a curva acha que manda. Hoje quem a salva
  é a morte pelo watchdog — o agente novo escreve de novo assim que a
  temperatura muda a porcentagem —, por acaso.
- **O watchdog não pode matar o agente a cada suspensão.** O caminho limpo é
  o agente segurar um bloqueio de atraso do logind e, no `PrepareForSleep`,
  alargar o `WATCHDOG_USEC` antes de dormir e voltá-lo ao acordar.
- **O E-C5 tem de deixar o perfil livre na suspensão** e registrar a troca
  como achado, em vez de parar; e olhar a rotação por 30 s depois de acordar.
- **O perfil que o firmware troca na suspensão** muda o uso de todo dia, com
  ou sem curva: depois de suspender, a máquina fica em `balanced` até alguém
  notar. Nesta rodada ele foi devolvido à mão.

**Os ajustes, escritos em 2026-10-16** (`src/nexus_sense/sono.py` e
`Agent._depois_de_dormir`):

- **O agente segura um bloqueio de atraso do logind** (`systemd-inhibit
  --what=sleep --mode=delay`) e espera o `PrepareForSleep` (`busctl wait`,
  um processo só, um sinal por linha). Antes de dormir manda
  `WATCHDOG_USEC` de 30 dias e só então solta o bloqueio — o logind espera
  por ele. Ao acordar devolve o `WATCHDOG_USEC` da unit, avisa que está vivo
  e segura um bloqueio novo. Sem dependência nova: o `busctl wait` existe
  desde o systemd 257, e outros programas da sessão já seguram bloqueios
  assim (`systemd-inhibit --list`). Medido aqui: o `wait` não desiste sem
  sinal, e o `--timeout=infinity` o busctl 262 recusa.
- **Na primeira passada depois de acordar,** o agente devolve o perfil que
  estava em vigor antes de dormir, se o firmware o trocou — só na tomada, e
  se o cabo não mudou enquanto a máquina dormia. E a curva reescreve o
  mesmo manual, que é o que o reaplica no firmware.
- **Se o aviso do logind faltar,** o agente percebe o sono pelo relógio: a
  diferença entre o de boot (que conta a suspensão) e o monotônico (que não
  conta) salta. Ele faz o mesmo, e devolve o watchdog da unit.
- **O E-C5 deixa o perfil livre na suspensão,** registra os perfis que viu e
  se o agente atravessou a suspensão vivo, e espera o agente devolver o
  perfil antes de seguir para o cabo.

**A terceira tentativa do E-C5, 2026-10-16 08:01, já com isso instalado:** a
suspensão de novo largou o manual e não voltou (32 de 46 amostras fora, 2.213
rpm com `fan_speed` em `95,95`), e o perfil foi a `balanced`. Mas o agente foi
morto pelo watchdog do mesmo jeito. O journal do logind disse por quê: *"Delay
lock is active (… systemd-inhibit) but inhibitor timeout is reached"* — o
agente nunca soltou o bloqueio, porque nunca recebeu o aviso. **Escrevendo
para um pipe, o `busctl` guarda a saída e só a entrega ao sair**, e com
`--limit-messages` alto ele não sai. Medido logo depois, com os sinais da
bateria: sem `stdbuf -oL`, nenhuma linha em 100 s; com ele, cada uma na hora.
O agente novo, sem saber o perfil de antes, não o devolveu, e o E-C5 parou ali
(código 11), como devia.

Corrigido com `stdbuf -oL` na frente do `busctl`, e o fio do sono passa a
dizer no journal quando a máquina vai dormir e quando acorda.

**O E-C5, completo menos o reinício, 2026-10-16 08:10 e 08:21**, com o
`stdbuf` instalado. Duas rodadas: a primeira até a suspensão (o cabo saiu
contaminado e o roteiro foi corrigido para reescrever o manual antes de cada
gesto), a segunda com `ENSAIO_C5_GESTOS="cabo perfil"`:

| gesto | o firmware | o resto |
|---|---|---|
| suspender e acordar (S3, ~30 s) | **largou o manual e não voltou:** 2.220 rpm com `fan_speed` em `95,95` | o agente atravessou vivo (mesmo pid); o perfil que o firmware trocou foi devolvido antes de o roteiro o ver |
| tirar e pôr o cabo | **manteve o manual:** 0 de 69 amostras fora | — |
| perfil `balanced` e de volta | **manteve o manual:** 0 de 125 amostras fora | — |
| `kill -9` no agente | — | **o guarda devolveu `0,0` em 105 ms**, pelo registro; a rotação saiu do manual; o agente voltou em 3 s |
| `SIGSTOP` no agente | — | **o watchdog o matou, e o guarda devolveu `0,0` em 5,0 s**; a rotação saiu do manual; o agente voltou |

O que isso responde, contra a seção 7:

- **C5: só a suspensão larga o manual**, e sem avisar: a memória do driver
  fica dizendo o manual. O cabo e o perfil não o tocam. A curva já se cobre
  disso: ao acordar ela reescreve o manual, e o agente devolve o perfil.
- **O guarda funciona na máquina**, nas duas mortes, no prazo que a seção 8
  fixou.
- **O reinício, medido às 08:39–08:45**, numa rodada que repetiu também os três
  gestos (o `ENSAIO_C5_GESTOS=""` caiu no padrão; corrigido) e deu o mesmo de
  antes. O manual de 95% foi registrado como do agente, como o da curva. No
  desligamento, às 08:43:31, o guarda o devolveu (*"o agente parou com a
  ventoinha em 95,95, que ele escreveu; devolvida ao automatico"*), e no mesmo
  segundo o driver gravou o estado — já com o `0,0`. Na partida o driver
  restaurou `0,0`, e a ventoinha subiu no automático (2.213 rpm, lido 79 s
  depois da partida). **Com a curva ligada, desligar a máquina deixa a próxima
  partida no automático.** O guarda chegou antes do driver por menos de um
  segundo: é o que se viu, não uma ordem garantida.

**C5 está respondida**, e a forma B não espera mais nada dela: só a suspensão
larga o manual, e a curva o reescreve ao acordar; o guarda cobre o agente
morto e o travado; e o reinício, desta vez, voltou no automático.

O que falta: o botão na janela e na bandeja, e o merge.

**A curva como o próprio Automático, 2026-10-16.** Decisão do usuário: sem
botão novo, a curva é o Automático. O que mudou (ramo `curva/padrao`):

- **Ligada desde a instalação, só no modelo medido.** `fan_curve` no config
  passa a ter três valores: ausente é "ninguém escolheu", e vale o padrão do
  modelo (`curva.ligada`); `true` e `false` são escolhas. O padrão liga a curva
  só no `Nitro ANV15-52` (`curva.MEDIDOS`, pelo `product_name` do DMI): as
  tabelas são porcentagens, e o mapa de porcentagem para rotação (E2) e o piso
  da rede (`fan_guard.AUTOMATICO`) foram medidos neste notebook. Noutro modelo
  ela só liga com `fan_curve = true`. Gravar o config por outro motivo não fixa
  o padrão como escolha: o `None` não vai para o arquivo. O `false` que o
  agente grava quando a rede dispara com a curva ativa segue valendo.
- **A janela mostra Automático enquanto a curva manda.** Ela reconhece o par
  da curva pelo registro do guarda, visto da sessão
  (`$XDG_RUNTIME_DIR/nexus-sense/ventoinha`), e o texto do botão diz quem
  decide: "o Nexus Sense decide pela temperatura" onde a curva age
  (`curva.age`: na tomada, fora de quiet e low-power, com o agente no ar) e
  "o firmware decide pela temperatura" fora disso.
- **Manual sem mexer nos cursores vale.** Ele escreve o mesmo par que a curva
  escreveu, e a curva, que só comparava o par, seguia mandando. Agora a
  janela apaga o registro antes de escrever um manual (`guarda.esquece`); a
  curva cede ao par sem registro, e o guarda o deixa como está.
- **A bandeja não muda:** "Ventoinha automática" grava `0,0`, e a curva
  retoma em até 2 s; ela não mostra o modo da ventoinha.
- **O Painel também** (2026-10-17, ramo `curva/painel`): instalado o
  `d0a2d08`, o usuário viu a tela Desempenho marcar Automático e o cartão
  Ventoinhas do Painel dizer "manual — 6% / 5%" ao mesmo tempo. O cartão
  fazia a conta sozinho. Agora os dois decidem pela mesma função
  (`performance.curva_manda`). No mesmo dia, a pedido do usuário, o cartão
  passou a dizer só o nome do modo — "automático", "máximo" ou "manual — x%
  / y%" —, sem explicar: quem explica é a tela Desempenho. Antes, o `100,100`
  aparecia como "manual — 100% / 100%".
- **Fora da unit, a curva do padrão fica quieta:** o aviso "sem o guarda"
  é só para quem pediu `fan_curve = true`.

O que fica de fora, de propósito:

- **Quem instalou o `2b1ea62` e nunca ligou a curva** tem `fan_curve = false`
  gravado: aquela versão gravava o padrão de então. Para ela ficar desligada
  é escolha; para valer o novo padrão, apagar a linha. Só esta máquina tem a
  instalação, e nela a linha diz `true`.
- **Um corredor pequeno:** se o agente lê o registro na mesma passada em que
  a janela o apaga e escreve o manual, a curva escreve por cima uma vez. Já
  existia com o cursor arrastado.
- **Os ensaios que medem o automático do firmware** (`ensaio-termico.sh`,
  E-C2/E-C3) precisam de `fan_curve = false` no config enquanto rodam: com
  a curva valendo, ela toma o `0,0` em 2 s. Hoje o roteiro não cuida disso.
