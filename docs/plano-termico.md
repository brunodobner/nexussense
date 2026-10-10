# Plano térmico — a rede de segurança da ventoinha manual

**Estado: escrito em 2026-10-10, na sub-etapa 4f de
[plano-melhorias.md](plano-melhorias.md), passado pelo grill e aprovado pelo
usuário no mesmo dia.** O que este arquivo afirma está marcado: **lido** (do
sysfs, do código ou do kernel, sem provocar nada) ou **medido** (observado
acontecendo). O que cada ensaio deu, conforme for rodando, vai para
[estado.md](estado.md).

Antes de executar, ler [armadilhas.md](armadilhas.md) — em especial as 3b, 14,
19, 20, 25, 27, 31, 33, 35 e 36 — e as seções 1 e 19 de
[decisoes.md](decisoes.md).

---

## 1. O problema, e o que ele não é

A tela Desempenho deixa escolher a velocidade de cada ventoinha, de 0 a 100%.
Quem deixa em 20% para ter silêncio e depois abre um jogo fica com a máquina
quente e a ventoinha baixa. O setpoint ainda atravessa o reinício: o driver o
grava em `/etc/predator_state` no desligamento e o devolve na partida (lido em
`acer_predator_state_save` e `_restore`).

**Não se sabe o que o EC faz nessa hora.** Ele pode obedecer ao manual até o
fim, pode ter um piso, pode tomar a ventoinha de volta acima de alguma
temperatura. É a primeira pergunta, e as outras dependem dela.

O que **já se sabe**, e muda o tamanho do problema: nenhuma das proteções de
silício depende da ventoinha.

| camada | o que faz | onde age | de onde vem |
|---|---|---|---|
| CPU, circuito térmico (TCC) | corta frequência | a partir de ~92 °C: TjMax 100, deslocamento 8 | lido: `coretemp` `crit`=100 e o dispositivo `TCC Offset` em 8; medido: o contador de throttle andando com o pacote entre 85 e 96 °C |
| kernel, zonas `acpitz` e `TCPU` | desligamento ordenado | 110 °C | lido: o ponto `critical` das duas zonas, e `acpi_thermal_zone_device_critical` no kernel |
| kernel, zonas `SEN2` a `SEN5` | **nada** | declaram `passive` 65, `hot` 75, `critical` 80 °C | lido: nenhuma zona tem dispositivo de resfriamento ligado, o `thermald` está inativo, e o callback dessas zonas (`int340x_thermal_critical`) existe para trocar o desligamento por uma linha de debug; medido: `SEN4` passou 24 minutos acima de 80 °C, em automático, sem consequência |
| GPU | reduz o clock, depois desliga | alvo 87 °C; redução 2 °C acima do limite, desligamento 12 °C acima | lido: `nvidia-smi -q -d TEMPERATURE`, com a placa já `active` |
| NVMe | limites próprios | 85,85 / 92,85 °C num, 99,85 / 109,85 °C no outro | lido: `temp1_max` e `temp1_crit` dos dois `hwmon` de nome `nvme` |
| EC | curva automática; **em manual, não se sabe** | — | a primeira pergunta |

Então a rede não é para impedir a CPU de queimar: ela se protege sozinha, e a
GPU também. O que sobra para uma rede fazer:

1. **Desempenho que some sem explicação.** Com a ventoinha baixa a CPU passa o
   tempo cortando frequência, e quem está jogando não liga a queda a um cursor
   esquecido.
2. **Calor em quem não se protege.** Placa, SSD e bateria não cortam nada: só
   esquentam. As zonas `SEN*` são o que há para vê-los.
3. **O setpoint que sobrevive ao reinício.** A escolha de ontem vale hoje, sem
   ninguém lembrar dela.

Se isso justifica código é a pergunta da seção 10 — e parte da resposta é sua.

---

## 2. A linha de base: automático, com um jogo e depois dele

**Medido em 2026-10-10**, por um observador passivo — só leitura, sem root, sem
`nvidia-smi`, a cada 5 s. O usuário abriu um jogo (Steam/Proton, processo
`GameThread`) por conta própria às 08:37 e o fechou às 09:06; ninguém pediu.
Ventoinhas em automático (`fan_speed` = `0,0`), perfil `balanced-performance`,
modo máximo desligado, na tomada. Nenhuma das 635 amostras saiu dessa
condição.

```
COM O JOGO   08:40:20 a 09:06:05 -- 300 amostras, 1545 s

                         minimo   media   maximo
ventoinha CPU, rpm         4037    4414     4464
ventoinha GPU, rpm         3685    4003     4037
pacote (coretemp), C         73      84       96
CPU pelo EC (temp1), C       73      84       91      igual a zona acpitz
GPU pelo EC (temp2), C       62      78       81
SEN2, C                      70      76       79
SEN3 (= temp3), C            60      72       75
SEN4, C                      72      86       89
SEN5, C                      65      76       79

throttle da CPU      277,6 s cortando em 1545 s -- 18,0% do tempo
frequencia media     2931 MHz
bateria              80% -> 77%, com status "Charging" em todas as amostras

DEPOIS DO JOGO   automatico, repouso -- 335 amostras ate 09:34

tempo desde     ventoinhas     pacote   SEN2  SEN3  SEN4  SEN5
o fim do jogo   CPU / GPU
     0 min      4427 / 4030      90      77    75    87    78
     1 min      3007 / 2688      61      66    70    68    69
     2 min      2719 / 2566      56      59    64    59    62
     3 min      2513 / 2321      56      55    59    55    58
     6 min      2331 / 2077      51      51    53    50    52
    18 min      2178 / 1930      44      45    45    45    46

throttle        0,3% do tempo, e so no primeiro minuto
bateria         77% -> 80% em tres minutos, a 2,43 A (~40 W); depois corrente zero
```

Quatro consequências, e todas mudam o desenho:

1. **"CPU quente" não distingue nada.** Em automático, com as ventoinhas a
   4400 rpm, o pacote vai a 96 °C e a CPU corta frequência em quase um quinto
   do tempo. Na 4b, quatro processos de CPU levaram `temp1` a 91 °C em 90 s,
   também em automático. Um gatilho "pacote acima de 90 °C" dispararia em uso
   normal. A rede precisa de outra pergunta: **o manual está abaixo do que o
   automático faria agora?**
2. **Os limites declarados das zonas `SEN*` não são limites.** `SEN4` foi a
   89 °C, nove acima do `critical` dela. O que serve de régua é este envelope:
   o que o EC, com a curva dele, deixa acontecer.
3. **O automático nunca para** — e, com o modo máximo desligado, foi de
   ~2200 / ~1950 rpm em repouso a ~4400 / ~4000 rpm quente.
4. **A máquina esfria depressa em automático.** Três minutos depois do jogo,
   toda zona de placa estava abaixo de 60 °C.

### O automático não tem um repouso fixo

A consequência 3 valeu por uma hora. O usuário avisou que a ventoinha fica
numa faixa mais alta do que este plano supunha, mesmo com a máquina quase
parada — e o mesmo observador, que seguiu no ar, confirma. **Medido das 09:08
às 10:12**, sem jogo, sempre em automático e em `balanced-performance`:

```
                       modo maximo desligado      modo maximo ligado
parada, EC a ~50 C     2240 / 1990 rpm            3350 / 2890 rpm
uso leve, EC a ~55 C   2700 / 2500 rpm            3650 / 3330 rpm
carga, EC a 64-73 C    --                         5000 a 6196 rpm
jogo, EC a 73-91 C     4037 a 4464 rpm            --
```

Na mesma temperatura do EC a ventoinha da CPU girou de 2241 a 3558 rpm
(50 °C), e de 2715 a 4707 (60 °C). São pelo menos duas curvas, e o que troca
de uma para a outra é o modo máximo: mesmo perfil térmico, GPU na mesma
temperatura (48 a 50 °C). O que o modo liga que o EC enxerga não foi apurado
— o pedido de PowerMizer que o agente segura é o suspeito, e o
`nvidia-powerd` está no ar.

Três coisas mudam com isso:

- **4400 rpm não é o teto.** Com o modo máximo ligado o automático foi a
  6196 rpm, a 68 °C. O "automático quente" da linha de base é o do modo
  desligado.
- **Nenhum ensaio pode cobrar "a rotação voltou a X".** O automático volta do
  manual onde quiser. A primeira versão do roteiro de E2 cobrava isso, e teria
  reprovado na máquina no primeiro exercício.
- **"Abaixo do que o automático faria" tem duas respostas**, uma por modo. A
  pergunta P3 e o gatilho da rede (seção 11) dependem disso.

---

## 3. O que o código faz hoje

Lido, nada medido:

- **`fan_speed` é o setpoint, em dois números.** `0,0` é automático, `100,100`
  é máximo, o resto é manual; `0` num lado só deixa aquela ventoinha em
  automático (`acer_set_fan_speed`).
- **Ler `fan_speed` devolve a memória do driver, não o firmware.**
  `predator_fan_speed_show` imprime duas variáveis. Se o EC tomar a ventoinha
  de volta por conta própria, o atributo continua dizendo o manual. **A
  verdade é a rotação**: `fan1_input` e `fan2_input` do `hwmon` de nome `acer`.
  O driver não implementa a leitura do modo de ventoinha do firmware.
- **Trocar para `quiet` ou `low-power` devolve o automático** — é o driver que
  faz, dentro do `profile_set`. Para os outros perfis ele não mexe.
- **O agente não escreve na ventoinha.** Só `MaximumMode.enable` escreve, e
  quem a chama é a janela ou a bandeja, ao ligar o modo. O laço de 2 s não lê
  temperatura nenhuma.
- **A interface aceita qualquer valor de 0 a 100** em cada cursor, sem piso e
  sem aviso.
- **A escrita não pede root**: `fan_speed` é `664 root:nexus_sense`. Uma rede
  no agente cabe na decisão 1 de [decisoes.md](decisoes.md).

---

## 4. As perguntas, em ordem de dependência

| | pergunta | quem responde | depende de |
|---|---|---|---|
| P1 | com o manual baixo e a máquina quente, o EC toma a ventoinha de volta? | E3 | P2 |
| P2 | quanto gira cada porcentagem? Há piso? Há porcentagem que para a ventoinha? | E2 | — |
| P3 | qual porcentagem equivale ao automático quente? São duas respostas: ~4400 / ~4000 rpm com o modo máximo desligado, e pelo menos 6196 com ele ligado | E0 + E2 | P2 |
| P4 | se o EC obedece, em quanto tempo e por qual sensor a coisa passa do envelope? | E3 | P1 |
| P5 | que limiar e que tempo de sustentação a rede usaria? | os traços de E0 e E3, sem ensaio novo | P1, P4 |
| P6 | por que a bateria descarrega com o cabo ligado? | o observador passivo, e E3 de carona | — |

---

## 5. O que vale para todo ensaio

- **Um comando só.** Ação, leitura e conferência no mesmo laço, a 1 Hz
  (armadilha 25). Entre duas chamadas de ferramenta há uma pessoa.
- **A condição se mede a cada amostra**, e a amostra fora dela não conta: cabo,
  carga, perfil, modo máximo, jogo aberto, e `fan_speed` lido de volta igual ao
  que o roteiro escreveu.
- **Sensor se acha pelo nome, na hora de usar** (armadilha 19): `hwmon` por
  `name`, canal por `label`, zona térmica por `type`, a dGPU por `vendor`.
- **Nenhum roteiro chama o `nvidia-smi`.** A temperatura da GPU vem do canal
  `GPU` do `hwmon` do acer, que lê igual ou até 6 °C acima (4b): erra para o
  lado seguro, e vale zero com a placa dormindo.
- **A bateria se lê por `charge_now`, não por `status`** (armadilha 36).
- **O roteiro só começa com `fan_speed` em `0,0`.** Assim "devolver" tem um
  sentido só: automático. Se você estiver em manual, ele se recusa a começar.
- **"Devolvida" se prova pela rotação ter saído do valor manual**, nunca por
  ter chegado a um número: o automático não tem repouso fixo (seção 2).
- **O modo máximo fica como estava do começo ao fim** de cada ensaio, e é
  gravado: ele troca a curva do automático. E2 e E3 rodam com ele
  **desligado**, que é a condição da linha de base e dos limites da seção 7.
- **O limite de aborto é o da seção 7**, igual para todos, e está escrito antes
  de qualquer medição.
- **O roteiro mora no repositório**, não no scratchpad:
  `tests/hardware/ensaio-termico.sh`, com a raiz do sysfs como parâmetro
  (`ENSAIO_RAIZ`). A lógica de aborto e de devolução é testada contra uma
  árvore falsa antes de encostar na máquina, em
  `tests/shell/test-ensaio-termico.sh` — é o controle positivo do caminho de
  aborto, sem calor. O traço de cada ensaio vai para
  `~/.local/state/nexus-sense/`, que não é tmpfs.
- **O que for medido vai para [estado.md](estado.md) antes de qualquer
  reinício.** O scratchpad é tmpfs.

---

## 6. Os ensaios

### E0 — linha de base passiva (feito; não esquenta, não escreve)

| | |
|---|---|
| pergunta | o que o EC faz em automático: rotação contra temperatura, envelope de cada sensor, taxa de throttle, e a descida depois da carga |
| instrumento | o observador da seção 13, a cada 5 s |
| controle positivo | o próprio traço: a rotação acompanhou a temperatura nos dois sentidos (3963 → 4400 rpm em 20 s ao esquentar, 4427 → 3007 em um minuto ao esfriar) e o contador de throttle andou. O instrumento enxerga as duas coisas |
| resultado | a seção 2. Faltou só o que ele não gravava: `charge_now` e os dois NVMe |
| limite de aborto | não se aplica: ninguém provoca nada |

### E1 — o DSDT (opcional; root só para ler)

O firmware ACPI mostra o que os métodos de ventoinha mandam ao EC, e se há
política térmica em AML. **Não entra no caminho crítico**: o que decide é o
comportamento, e o código do EC é fechado. Só se E3 der resultado ambíguo.
Custa um `pacman -S acpica` e uma leitura de `/sys/firmware/acpi/tables/DSDT`,
os dois com root. Controle positivo: o AML decompilado tem de conter o método
14 que o driver chama; senão é a tabela errada.

### E2 — o mapa de porcentagem para rotação, em repouso (escreve em `fan_speed`; não esquenta)

| | |
|---|---|
| pergunta | P2 e P3 |
| condição | sem jogo, `load1` abaixo de 4, pacote abaixo de 70 °C, na tomada, bateria a partir de 60%, `fan_speed` em `0,0`, modo máximo desligado. A primeira versão pedia `load1` abaixo de 2 e pacote abaixo de 65 °C: com o aplicativo desta conversa aberto a máquina passa disso sem estar ocupada |
| o que faz | para cada porcentagem em 100, 80, 60, 50, 40, 30, 20, 15, 10, 5, 1: escreve `p,p`, espera 20 s, lê as duas rotações cinco vezes. Depois `0,0`, e lê a rotação do automático em repouso |
| controle positivo | a rotação a 100% tem de ficar pelo menos 500 rpm acima da de 50%, e `fan_speed` lido tem de ser o escrito. Se a rotação não acompanha a escrita, o modo manual não é o que se supõe e o plano para aqui |
| limite de aborto | os da seção 7, mais um próprio: pacote a 85 °C ou mais por três amostras. Em repouso isso não devia acontecer; se acontecer com a ventoinha baixa, é achado — a porcentagem não segura nem o repouso |
| quem roda | você, por um bloco de comando no terminal do aplicativo |
| duração | ~6 min |

Dois exercícios entram aqui, antes de qualquer calor:

- **O vigia.** Com `95,95` escrito, o roteiro principal leva um `kill -9`. O
  vigia tem de devolver `0,0` em até 3 s, e a rotação tem de **cair pelo menos
  500 rpm** em relação ao que girava a 95%.
- **O aborto.** O roteiro roda com o limite da CPU pelo EC rebaixado para 5 °C
  abaixo da leitura corrente. Tem de abortar na primeira amostra, devolver
  `0,0` e sair com o código de aborto. (O limite rebaixado é o do EC e não o
  do pacote porque o do pacote, por regra, pede três amostras seguidas.)

Nenhum dos dois é teste por vácuo de si mesmo: os dois conferem o efeito
(`fan_speed` e rotação), não o código de saída sozinho (armadilha 11).

**Por que 95%, e por que "cair" em vez de "voltar".** `fan_speed` é a memória
do driver; quem diz que o EC largou o manual é a rotação. A primeira versão
escrevia `60,60` e cobrava a rotação de volta a ±500 rpm da medida na partida
— e o automático não volta para onde estava (seção 2). A alternativa não
precisa saber onde o automático vai parar:

- a 95% a ventoinha gira bem acima de qualquer automático em repouso, então a
  volta tem sentido conhecido: **cai**;
- se a 95% ela não girar pelo menos 1000 rpm acima do automático da partida,
  o exercício não tem como ver volta nenhuma e **diz isso**, em vez de passar:
  ou o manual não muda a rotação, ou a máquina não está em repouso;
- e se um exercício falhar de verdade, a máquina fica com a ventoinha alta —
  barulho, não calor.

### E3 — manual baixo com carga de CPU (escreve em `fan_speed` e **esquenta**)

| | |
|---|---|
| pergunta | P1 e P4 |
| condição de partida | a de E2, e mais: toda zona `SEN*` pelo menos 15 °C abaixo do limite dela na seção 7, pacote abaixo de 60 °C. Em automático a máquina chega lá em três minutos (seção 2) |
| carga | 8 processos em laço ocupado, cada um debaixo de `timeout`: a fonte de calor morre sozinha no prazo, com ou sem roteiro |
| estágio 0 | **automático**, 120 s de carga. É o controle positivo: a rotação tem de subir com a temperatura, pelo mesmo `fanN_input`. Sem isso, "a rotação não subiu em manual" não quer dizer nada (armadilha 35). Dois minutos bastam: na 4b a CPU foi a 91 °C em 90 s, e na seção 2 a rotação respondeu em 20 s |
| estágio 1 | manual a 30%, até 180 s de carga. É o degrau antes do pior caso, e só isso: a CPU chega ao corte em ~90 s |
| estágio 2 | manual na porcentagem mais baixa que E2 mostrar — **inclusive a que para a ventoinha, se houver** (decidido no grill) — até **600 s** de carga. É o estágio que decide a primeira pergunta, e as zonas de placa são lentas: com o jogo, `SEN3` ainda subia aos nove minutos |
| em cada estágio manual | 30 s frio na porcentagem, para medir a rotação de referência **na hora**; a carga; carga fora, `0,0`, e a descida gravada até o pacote voltar a 60 °C ou 300 s — três minutos, pela seção 2 |
| um estágio só roda | se o anterior terminou sem aborto |
| instrumento | rotação das duas ventoinhas, pacote, `temp1`/`temp2`/`temp3` do acer, `SEN2` a `SEN5`, os dois NVMe, contador e tempo de throttle, frequência média, bateria (`charge_now`, corrente), cabo, perfil, `fan_speed` |
| "o EC tomou de volta" | rotação acima da referência do estágio por mais de `max(300 rpm, 3 × a variação vista naquela porcentagem em E2)`, em cinco amostras seguidas, com `fan_speed` ainda dizendo o manual. Visto isso, o estágio segue mais 60 s para ver onde a rotação assenta, e termina |
| limite de aborto | os da seção 7 |
| quem roda | você, por um bloco de comando no terminal do aplicativo: o `Ctrl-C` fica na sua mão e o ensaio não depende de esta conversa estar viva. Eu acompanho lendo o arquivo que ele grava |
| duração | ~25 min com os três estágios: 15 de carga, o resto é descida |

O que saiu, e por quê: uma primeira versão tinha quatro estágios de 300 s e
dava ~40 min. O estágio a 50% não decidia nada — a porcentagem que equivale ao
automático sai de E2 — e os 300 s do automático e do degrau eram folga, não
medição. **O que não encolhe são os 600 s do mais baixo**: com três minutos,
"o EC não tomou a ventoinha" seria silêncio de zona lenta.

### E3b — manual com um jogo (condicional; o gesto é seu)

Só roda se as três coisas valerem: E3 não viu o EC tomar a ventoinha, o
estágio mais baixo de E3 terminou sem aborto, e você autorizar **depois de ver
os números de E3** (decidido no grill). A carga de CPU não esquenta a GPU, e o
cenário de verdade é um jogo — 60 W a mais no mesmo dissipador. O gesto é
abrir o jogo de sempre por cinco minutos, com o manual na porcentagem que E3
acabou de provar, o roteiro vigiando os mesmos limites e devolvendo o
automático no primeiro que estourar. Se E3 abortou em algum estágio, E3b não
roda: a rede já está justificada e o limiar sai de E3.

---

## 7. Limites de aborto

Escritos antes de medir. Qualquer um encerra o estágio: carga fora, `0,0`,
conferência de que a rotação voltou. Avaliados a cada amostra, no mesmo laço
que lê.

| sensor | aborta em | por quê esse número |
|---|---|---|
| pacote da CPU (`coretemp`, rótulo `Package id 0`) | 98 °C em três amostras seguidas, ou `crit_alarm` = 1 | TjMax é 100. O automático com jogo foi a 96; o TCC devia segurar ali. Três amostras a 98 dizem que ele não está segurando |
| CPU pelo EC (`temp1` do acer, igual à zona `TCPU`) | 99 °C | o kernel desliga a máquina em 110. Onze graus de folga; o automático foi a 91 |
| GPU pelo EC (`temp2` do acer) | 85 °C | o alvo da NVIDIA é 87, e o EC lê até 6 °C acima do chip; o automático foi a 81 |
| `SEN2`, `SEN3`, `SEN4`, `SEN5` | 81, 77, 91 e 81 °C | o máximo de cada zona em 26 minutos de jogo em automático (79, 75, 89, 79), mais 2 °C. Não se leva a placa além do que o EC, sozinho, já deixa |
| NVMe (`Composite` de cada um) | 75 °C | dez graus abaixo do `max` do mais sensível |
| bateria | cabo fora; ou carga abaixo de 50% | não é perigo, é confusão: abaixo de ~40% o firmware se diz fora da tomada (armadilha 27) e o ensaio passa a medir outra máquina. A carga se lê por `charge_now`: o `status` não avisa (armadilha 36) |
| pessoa | jogo aberto; perfil mudou; modo máximo mudou; `fan_speed` lido diferente do escrito | alguém mais está na máquina (armadilha 25). **Se `fan_speed` mudou por outra mão, o roteiro tira a carga e não escreve na ventoinha**: a escolha é de quem a fez |
| tempo | 120 s de carga no automático, 180 s no degrau, 600 s no mais baixo; 35 min no total | prazo do vigia |

O throttle **não** é limite: é o mecanismo de proteção funcionando, e é o que
se quer medir.

Os números das zonas `SEN*` saem da captura passiva e **congelam na
aprovação**: depois dela, nenhuma medição os move.

---

## 8. Quem devolve a ventoinha

Em camadas, da mais próxima para a mais distante. Cada uma cobre a morte da
anterior.

1. **O `trap` do roteiro**, em `EXIT`, `INT`, `TERM` e `HUP`: mata a carga pelo
   grupo de processos, escreve `0,0`, lê de volta e confere a rotação. Se a
   escrita de `0,0` falhar três vezes, escreve `100,100` e avisa no terminal:
   ventoinha no máximo é o erro que não machuca.
2. **O vigia**, processo à parte (`setsid`), no ar antes da primeira escrita:
   a cada segundo confere se o roteiro está vivo e se o prazo passou. Se o
   roteiro sumiu — `kill -9`, falta de memória, terminal fechado — ele mata a
   carga e escreve `0,0`. É a camada que o `trap` não cobre, e por isso é
   exercitada em E2.
3. **O `timeout` de cada processo de carga**: sem roteiro e sem vigia, o calor
   para sozinho no prazo. A ventoinha fica em manual, mas sem fonte de calor.
4. **Você**: `Ctrl-C` no terminal, ou "Automático" na janela ou na bandeja. O
   roteiro vê a escrita de outra mão, tira a carga e sai.
5. **Se a máquina desligar no meio.** Corte seco não grava estado: a partida
   seguinte devolve o `0,0` do último desligamento ordenado. Desligamento
   ordenado **grava o manual baixo**, e ele volta na partida. Depois de
   qualquer reinício que este plano não previu, a primeira coisa é ler
   `fan_speed` e, se não for `0,0`, clicar em "Automático".

---

## 9. O combinado com quem está na máquina

Vale durante E2, E3 e E3b, e se combina no chat antes do comando — com o
observador já no ar e um tempo limite.

- **Você pode**: usar a máquina de leve (navegador, texto), deixar a janela do
  Nexus Sense aberta.
- **Você não faz**: abrir jogo, mexer em ventoinha, perfil ou modo máximo,
  tirar o cabo, fechar a tampa. Qualquer um desses encerra o estágio — sem
  dano, mas a medição se perde.
- **Para parar**: `Ctrl-C`, ou "Automático".
- **O agente e a bandeja ficam no ar.** Nenhum dos dois escreve na ventoinha
  por conta própria (lido), e tirá-los mediria outra máquina.
- **Bloco de comando no chat leva a ação inteira e só ela.** Gesto se pede em
  prosa.

---

## 10. A regra, escrita antes de medir

| o que E3 mostrar | o que se faz |
|---|---|
| **R1.** No estágio mais baixo o EC toma a ventoinha de volta, e o estágio termina dentro dos limites | o EC já tem a rede. **Nenhum código no agente.** O registro ganha o ponto em que ele age |
| **R2.** O EC obedece ao manual nos dois estágios, e nenhum aborta | a máquina sobrevive cortando frequência — pelo tempo do ensaio, que são dez minutos de CPU a pleno e nenhum de GPU. Não é caso de segurança provado: é desempenho e conforto, e **você decide com os números na mão** (decidido no grill) — quanta frequência se perde em cada porcentagem |
| **R3.** Algum estágio aborta num limite de temperatura — o EC obedecendo ao manual, ou subindo a ventoinha sem dar conta | a rede se justifica. Desenho da seção 11, com os limiares tirados dos traços |

Um quarto desfecho, para não ser lido como um dos três: se o roteiro abortar
por pessoa, bateria ou tempo, o estágio **não conta** e se repete.

---

## 11. O desenho da rede, se a regra mandar

Vale para R3, e para R2 se você quiser. É desenho, não código: os números
marcados *provisório* saem dos traços de E0 e E3. Duas escolhas do grill
deixaram a rede bem menor do que a primeira versão deste plano: ela **não
devolve o manual** e **só fala no journal**.

**Onde mora.** No agente, que já roda a cada 2 s como o usuário, sem root. Uma
função pura, como `decide`: recebe setpoint, rotações e temperaturas, devolve
o que escrever. Testável sem hardware e sem relógio.

**Quando arma.** Só com o setpoint em manual **e abaixo do que o automático
faria quente** — a porcentagem de P3, que E2 mede. **Em aberto desde a seção
2:** o automático quente gira ~4400 rpm com o modo máximo desligado e mais de
6000 com ele ligado, então P3 são duas porcentagens. O agente sabe em qual
modo está (é ele quem o mantém); o desenho escolhe entre usar a de cada modo
ou só a mais alta, com o mapa de E2 na mão. Em automático, em máximo,
ou em manual a 90%, a rede não lê temperatura nenhuma: o custo no caso comum é
uma leitura de `fan_speed`, que não chama o firmware. Armada, lê o pacote pelo
`coretemp` (sem WMI) e a GPU pelo `temp2` do acer (uma chamada WMI por
passada).

**Quando dispara.** Armada, e quente por tempo sustentado: média do pacote em
30 s a 85 °C ou mais, ou GPU pelo EC a 80 °C ou mais por 30 s — *provisório*.
Como só arma com o manual abaixo do automático, o limiar pode ser sensível sem
disparar em uso normal. E só dispara se a rotação estiver de fato abaixo da do
automático quente: se o EC já subiu a ventoinha por conta própria, não há o
que fazer.

**O que faz.** Escreve `0,0`: devolve a ventoinha ao EC, que é a curva que o
fabricante validou. Não inventa curva própria e não força o máximo.

**Quando devolve o manual.** **Nunca sozinha** — decisão sua, no grill. A
ventoinha fica em automático até você escolher manual de novo. Com isso a rede
não guarda setpoint, não tem limiar de volta e não tem como ficar subindo e
descendo: depois de agir ela está desarmada, porque o modo já é automático. Se
você escolher o manual baixo de novo com a máquina ainda quente, ela dispara
outra vez depois dos 30 s.

**Como você fica sabendo.** Uma linha no journal do agente, com o manual que
havia, a temperatura e a rotação — e **nada na interface**, decisão sua. A
consequência a conhecer: a janela vai mostrar "Automático" onde você tinha
deixado "Manual", sem dizer por quê.

**Como os limiares se fixam** — critério técnico, verificável sem esquentar de
novo: os traços de E0 e de E3 viram entrada da função pura, num teste.

- nos traços em automático, e nos estágios de manual a partir da porcentagem de
  P3, a rede **não dispara nenhuma vez**;
- em todo estágio de manual abaixo dela, dispara em até 60 s do começo da
  carga, e pelo menos 30 s antes do instante em que o estágio abortou.

**O que ela não faz.** Não protege silício — isso é do hardware (seção 1). Não
roda sem sessão: o agente é serviço de usuário. Não sabe o modo de verdade da
ventoinha, só o que o driver lembra; por isso confere a rotação antes de agir.

**Alternativas, e por que ficaram de fora:**

| | o quê | por que não |
|---|---|---|
| devolver o manual ao esfriar | guardar o setpoint e reescrevê-lo depois de uns minutos frio | era a recomendação; **você escolheu que fique em automático**. Mais simples, e sem vaivém |
| linha na janela, ou notificação | dizer na tela Desempenho que foi a rede | era a recomendação; **você escolheu só o journal** |
| piso no cursor | a interface não deixa escolher abaixo de N% | impede em vez de socorrer, e tira uma escolha que em repouso é legítima. **Você decide depois de ver E2**, se houver porcentagem que para a ventoinha |
| forçar o máximo | `100,100` em vez de `0,0` | mais barulho que o necessário; o automático já sobe |
| no driver | trabalho periódico no kernel | robusto sem sessão, mas é política dentro do kernel, DKMS e reinício para cada ajuste de limiar |

---

## 12. A bateria que descarrega com o cabo ligado

**O que se sabia.** Duas vezes registradas, as duas com `ACAD/online` em 1 e
sem o agente ver troca de fonte: 60% → 43% em 70 min (etapa 2) e 54% → 31% em
55 min (4e, confirmado pelo usuário). São 8 a 14 W saindo da bateria, em
média. A carga da máquina nesses intervalos não tinha sido anotada.

**O que o usuário disse, em 2026-10-10:** nas duas quedas ele estava
**jogando**, e o cabo esteve ligado o tempo todo — só saiu quando um ensaio
pediu. E a etiqueta diz 135.

**O que se leu hoje.** `battery_limiter` = 1 (teto de 80%) e
`battery_calibration` = 0: não é calibração em curso. O limite de potência da
CPU é 55 W sustentados e 115 W de pico.

**O que se mediu hoje**, de carona na linha de base (seção 2):

```
26 min de jogo        80% -> 77%, cabo ligado, corrente em torno de 0,3 A
jogo fechado          2,43 A (~40 W) na amostra seguinte
tres minutos depois   80%, e corrente zero dai em diante
```

Com o jogo, a bateria cedeu três pontos; fechado o jogo, 40 W foram para ela
na hora. É o que a hipótese H1 prevê, em escala pequena: ~5 W saindo. **O
sentido da corrente é inferência**: o kernel dá `current_now` sem sinal, e o
`status` disse `Charging` nas 635 amostras — caindo, subindo e parado no teto.
Ele não serve de instrumento aqui (armadilha 36). A conta que sustenta a
inferência: 0,3 A por 25 min são 3,5% desta bateria, e ela perdeu três pontos.

**Hipóteses, e o que separa cada uma:**

| | hipótese | o que se veria | hoje |
|---|---|---|---|
| H1 | o consumo passa do que a fonte entrega, e a bateria completa (o evento `0x9`, "battery boost", existe e chega ao driver) | `charge_now` caindo **só** sob carga alta, e subindo assim que ela cai | **a favor, três de três**: as duas quedas antigas foram jogando, e a de hoje também. 55 W de CPU, 60 a 75 W de GPU, tela e placa encostam nos 135 W |
| H2 | fonte ou conector entregando menos do que devia | queda sem relação com a carga; talvez `ACAD/online` piscando | nada a favor: `ACAD` em 1 nas 635 |
| H3 | o firmware segura a carga de propósito em algum estado | queda em repouso, com padrão que se repete | nada a favor: em repouso a corrente foi zero, no teto |

**O que falta.** A queda de hoje foi de 0,12 ponto por minuto; a da 4e foi de
0,42. A causa está apontada, a taxa não: falta ver uma carga mais pesada dar
a queda maior — modo máximo ligado, por exemplo, que hoje não estava. Não
pede ensaio próprio: o observador, gravando `charge_now`, deixado no ar numa
sessão de jogo com o modo máximo. E3 mede de carona o caso da CPU a pleno sem
GPU.

**O que isso muda no uso.** Jogar na tomada gasta bateria, devagar. Uma sessão
longa pode levar a carga abaixo de ~40%, e aí o firmware se diz fora da tomada
(armadilha 27): é por esse caminho que a máquina chega lá sem ninguém tirar o
cabo.

---

## 13. O observador passivo — como refazer

Vivia no scratchpad. Só leitura, sem root, não chama o `nvidia-smi`.

```bash
#!/bin/bash
# Uso: observador.sh <arquivo.tsv> <intervalo_s> <duracao_s>
out=$1; passo=${2:-5}; dur=${3:-3600}

acha_hwmon() {            # armadilha 19: pelo nome, na hora de usar
    for d in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && { echo "$d"; return; }
    done
}
acha_pacote() {
    for l in "$1"/temp*_label; do
        [ "$(cat "$l" 2>/dev/null)" = "Package id 0" ] && { echo "${l%_label}_input"; return; }
    done
}
acha_dgpu() {
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
        case "$(cat "$d/class" 2>/dev/null)" in 0x03*) echo "$d"; return;; esac
    done
}
zona() {
    for z in /sys/class/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { cat "$z/temp" 2>/dev/null; return; }
    done
    echo NA
}
le() { cat "$1" 2>/dev/null || echo NA; }
freq_media() {
    awk '{s+=$1; n++} END {if (n) printf "%d", s/n/1000; else print "NA"}' \
        /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null
}

NS=/sys/devices/platform/acer-wmi/nitro_sense
TT=/sys/devices/system/cpu/cpu0/thermal_throttle
CFG=$HOME/.config/nexus-sense/config.toml
printf 'epoch\thora\tcap\tstatus\tacad\tcorrente_uA\ttensao_uV\tperfil\tfan_speed\trpm_cpu\trpm_gpu\tec_cpu\tec_gpu\tec_ext2\tpacote\tsen2\tsen3\tsen4\tsen5\tacpitz\tthr_n\tthr_ms\tmhz\tdgpu\tload1\tjogo\tmaximo\n' > "$out"
fim=$(( $(date +%s) + dur ))
while [ "$(date +%s)" -lt "$fim" ]; do
    acer=$(acha_hwmon acer); core=$(acha_hwmon coretemp)
    pac=$(acha_pacote "$core"); gpu=$(acha_dgpu)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date +%s)" "$(date +%T)" \
        "$(le /sys/class/power_supply/BAT1/capacity)" \
        "$(le /sys/class/power_supply/BAT1/status)" \
        "$(le /sys/class/power_supply/ACAD/online)" \
        "$(le /sys/class/power_supply/BAT1/current_now)" \
        "$(le /sys/class/power_supply/BAT1/voltage_now)" \
        "$(le /sys/firmware/acpi/platform_profile)" \
        "$(le $NS/fan_speed)" \
        "$(le "$acer/fan1_input")" "$(le "$acer/fan2_input")" \
        "$(le "$acer/temp1_input")" "$(le "$acer/temp2_input")" "$(le "$acer/temp3_input")" \
        "$(le "$pac")" \
        "$(zona SEN2)" "$(zona SEN3)" "$(zona SEN4)" "$(zona SEN5)" "$(zona acpitz)" \
        "$(le $TT/package_throttle_count)" "$(le $TT/package_throttle_total_time_ms)" \
        "$(freq_media)" \
        "$(le "$gpu/power/runtime_status")" \
        "$(cut -d' ' -f1 /proc/loadavg)" \
        "$(ps -eo comm --no-headers | grep -c '^GameThread$')" \
        "$(grep -m1 '^maximum_mode' "$CFG" 2>/dev/null | tr -d ' ' | cut -d= -f2)" >> "$out"
    sleep "$passo"
done
```

Três coisas que ele não faz e o roteiro de E3 precisa:

- **não grava `charge_now`**, e devia: `capacity` anda de ponto em ponto e
  `status` não diz nada (armadilha 36);
- não grava os dois NVMe nem o `crit_alarm` do pacote;
- lê a rotação a cada 5 s, não a 1 Hz.

O nome `GameThread` é o do jogo de hoje; outro jogo pode ter outro nome, e a
coluna vira zero calada — conferir antes de confiar.

As leituras avulsas desta sessão, para repetir:

```bash
# zonas termicas, com os pontos de disparo de cada uma
for z in /sys/class/thermal/thermal_zone*; do
    echo "$(cat $z/type) $(cat $z/temp)"
    for t in $z/trip_point_*_type; do
        echo "    $(cat $t) $(cat ${t%_type}_temp)"
    done
done
# quanto a CPU ja cortou por temperatura, neste boot
cat /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count \
    /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_total_time_ms
```

---

## 14. Decisões: as suas e as técnicas

**Fechadas no grill de 2026-10-10:**

| | pergunta | resposta |
|---|---|---|
| 1 | até onde E3 desce | até a porcentagem mais baixa, **inclusive com a ventoinha parada**, se E2 mostrar que existe |
| 2 | E3b, o ensaio com jogo | decide depois de ver E3 |
| 3 | se der R2, quer a rede? | decide com os números de E3 |
| 4 | disparada a rede, o manual volta sozinho? | **não: fica em automático** até você escolher de novo — contra a recomendação |
| 5 | como você fica sabendo | **só o journal** — contra a recomendação, que era uma linha na janela |
| 6 | piso no cursor, se houver porcentagem que para a ventoinha | decide depois de ver E2 |
| 7 | potência da fonte | 135 W, lido da etiqueta |

**Ainda suas** — autorização, e é o que a aprovação deste plano quer dizer:

| | decisão | recomendado |
|---|---|---|
| A1 | autorizar E2: o roteiro mexe nas ventoinhas por ~6 min, com a máquina em repouso. Você ouve a ventoinha subir e descer | sim |
| A2 | autorizar E3: ~25 min, 15 deles com a máquina quente de propósito e a ventoinha baixa, dentro dos limites da seção 7, sem jogo nesse intervalo | sim, depois de E2 |
| A3 | autorizar E1, se E3 for ambíguo: instalar o `acpica` e ler o DSDT, com root | só se precisar |

**Suas, mais adiante**, cada uma com o dado que falta: E3b e o caso R2, depois
de E3; o piso do cursor, depois de E2.

**Técnicas** — se medem, não se perguntam: se a rede é necessária (a regra da
seção 10); o sensor, o limiar e o tempo de sustentação (seção 11, pelos
traços); a porcentagem de P3; o número de processos da carga; onde a função
mora e como é testada; o intervalo de amostragem; os limites de aborto.

---

## 15. Execução

Em sessões novas, pelas regras da seção 1 de
[plano-melhorias.md](plano-melhorias.md): ramo próprio a partir de `master`
limpo, baseline antes da primeira edição, a suíte inteira antes de cada commit.

| sessão | ramo | o que entra | root, gesto |
|---|---|---|---|
| 1 — medição | `termica/1-medicao` | o roteiro em `tests/hardware/`, com teste da lógica de aborto contra sysfs falso; E2, E3; o veredito da regra em [estado.md](estado.md) | sem root. Gesto: rodar dois blocos e não usar a máquina de pesado por ~35 min |
| 2 — a rede | `termica/2-rede` | só se a regra mandar: a função pura, os traços como teste, o agente. Sem mudança na interface. Versão nova, portão com reinstalação | root na reinstalação |

Baseline esperado ao abrir a sessão 1: 387 passam na suíte Python, sem xfail;
shell 21 passam e 2 pulam, sem root e sob `LC_ALL=C`.

**Fora deste plano, de propósito:** se trocar de perfil ou suspender a máquina
desfaz o manual no firmware (o driver não saberia; erra para o lado seguro);
ler o modo de ventoinha do firmware pelo driver; curva de ventoinha própria.
