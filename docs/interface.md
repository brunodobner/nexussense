# Interface do Nexus Sense

O sistema visual da janela e da bandeja. Aprovado em 2026-09-06.

**Mockup navegável:** https://claude.ai/code/artifact/5eea8390-bb17-4997-afa6-3db7abd662af

Ele tem as cinco telas com dados reais desta máquina, e dois alternadores
que valem mais que descrição: pele clara/escura, e fonte de energia — este
último demonstra o requisito das posições fixas na tela Desempenho.

Este arquivo é a fonte da verdade quando o mockup e o código divergirem.
A spec da GUI descreve **o que** vai em cada tela; este documento descreve
**como se parece**, e registra os dois pontos em que ele **substitui** a
spec (seção "Onde isto substitui a spec").

---

## 1. Direção

Instrumento de precisão, não painel gamer. O aparelho é um laptop de jogos,
mas a interface é lida enquanto números mudam a cada décimo de segundo — a
prioridade é leitura rápida e hierarquia estável, não impacto.

Consequências práticas: nenhum gradiente decorativo, nenhum neon, um acento
só, e densidade controlada. O que chama atenção é o estado anormal, nunca a
moldura.

---

## 2. Cor

O acento **não é novo**: é o índigo já escolhido para os ícones em
`packaging/icons/README.md`, por medição de contraste nos dois temas (3,79
no claro, 3,93 no escuro). Estendê-lo à interface evita uma segunda paleta
competindo com a marca.

| papel | valor | onde |
|---|---|---|
| **índigo** | `#4A78C8` | o acento, e o único: perfil marcado, traço do gráfico, foco, botão primário |
| índigo (texto, escuro) | `#7FA5E6` | o mesmo acento como texto sobre fundo escuro |
| índigo (texto, claro) | `#35619F` | idem, sobre fundo claro |

**Neutros com viés de azul.** Cinza puro pareceria acidental; o desvio para
o azul faz o neutro parecer escolhido e conversa com o acento.

| papel | escuro | claro |
|---|---|---|
| fundo | `#10141B` | `#EFF2F7` |
| painel (lateral, barra de título) | `#171D27` | `#FFFFFF` |
| cartão | `#1B222E` | `#FFFFFF` |
| superfície elevada | `#222A38` | `#F4F6FA` |
| linha | `#29323F` | `#E0E5EE` |
| linha forte | `#364152` | `#CBD3E0` |
| texto | `#E5EAF2` | `#171C25` |
| texto secundário | `#98A4B6` | `#57626F` |
| texto terciário | `#6B7789` | `#838E9D` |

**Semânticas reservadas.** Verde, âmbar e vermelho significam estado e nunca
decoram. Só um degrau de separação entre fundo e cartão — mais viraria ruído.

| estado | escuro | claro | uso real |
|---|---|---|---|
| bom | `#4FB287` | `#23795A` | verificação passou, agente de pé |
| atenção | `#D3A05A` | `#91601D` | perfil barrado na bateria, aviso da calibração, relogar |
| falha | `#E0736B` | `#A73B34` | agente fora do ar, módulo não carregado |

**Séries do gráfico.** Duas, e as duas no mesmo eixo — ambas são °C, então
dividem a escala. Nunca dois eixos.

| série | escuro | claro |
|---|---|---|
| CPU | `#4A78C8` (o próprio índigo) | `#4A78C8` |
| GPU | `#D2688F` | `#C25680` |

O rosa foi **escolhido por validação, não por gosto**. Contra o índigo ele
passa nos cinco testes: banda de luminosidade, piso de croma, separação sob
daltonismo (ΔE 9,8 em protanopia), piso de visão normal (ΔE 21,9) e
contraste com a superfície. Violeta, ciano e verde-azulado foram testados e
reprovaram — violeta dá ΔE 2,9 em protanopia, indistinguível.

**Ressalva registrada:** o rosa fica perto do vermelho semântico (ΔE 7,0).
Nenhuma cor separa bem do índigo **e** do vermelho ao mesmo tempo — rosa,
magenta e vermelho ocupam vizinhança de matiz. Aceito porque os dois nunca
aparecem juntos: o vermelho semântico vive no Diagnóstico, sempre com ícone
e rótulo, e nunca como linha de gráfico.

**Regra que não se quebra:** cor nunca vem sozinha. Toda linha de estado
carrega ícone e rótulo em texto; quem não distingue as cores lê a mesma
informação. No gráfico isso é triplo: legenda no cabeçalho, rótulo direto
na ponta de cada linha, e ponto colorido no título do cartão
correspondente.

---

## 3. Tipografia

| papel | família | tamanho | tratamento |
|---|---|---|---|
| título de tela | Sans | 17 px / 600 | espaçamento −0,01em |
| título de cartão | **Mono** | 10,5 px / 500 | caixa alta, espaçamento 0,13em, cor terciária |
| interface | Sans | 13,5 px / 500-600 | |
| texto explicativo | Sans | 12,5 px / 400 | cor secundária |
| **dado** | **Mono** | 13 px / 500 | `tabular-nums`, alinhado à direita |
| nome de sysfs | **Mono** | 10,5 px | cor terciária |

**IBM Plex Sans** para interface e texto, **IBM Plex Mono** para número,
rótulo de seção e nome de atributo.

Duas razões, as duas funcionais:

- **dígito de largura fixa** — o valor não dança quando `3019` vira `2988`.
  Sem isso, uma coluna de rotação treme a cada décimo de segundo;
- **mono marca o que é do terminal.** `low-power` e `battery_limiter` em
  mono se leem como identificador, não como prosa. É a legenda que liga a
  tela ao Diagnóstico e ao `sysfs`.

No Qt, `tabular-nums` sai de `QFont.setFeature("tnum")` ou de uma família
com dígitos tabulares por padrão — a Plex Mono já os tem.

---

## 4. Leiaute

### 4.1 A grade do Painel — o ponto mais fácil de errar

O Painel é **três colunas e duas linhas, numa grade só**. O gráfico ocupa
duas colunas; a Bateria ocupa a terceira.

```
┌───────────┬───────────┬───────────┐
│    CPU    │    GPU    │ Ventoinhas│
├───────────┴───────────┼───────────┤
│      Temperatura      │  Bateria  │
└───────────────────────┴───────────┘
```

**Duas grades separadas não alinham.** Com vão de 13 px, uma grade de
`repeat(3, 1fr)` dá colunas de `(L − 26) / 3`, e uma segunda grade de
`2fr 1fr` dá `(L − 13) / 3` — diferença de ~4,3 px, suficiente para o olho
perceber que a coluna da direita está torta. No Qt isso é **um
`QGridLayout` só**, com o gráfico em `addWidget(g, 1, 0, 1, 2)`, e nunca
dois layouts irmãos.

A telemetria é lida a cada **0,1 segundo** enquanto a janela está visível.
O gráfico conserva 120 amostras, portanto mostra aproximadamente **12 segundos**
de temperaturas. Entre as leituras, o gráfico interpola o deslocamento e o
último ponto a cada 16 ms, cerca de 60 quadros por segundo. Essa animação não
consulta novamente os sensores. Os rótulos `CPU` e `GPU` ficam presos à borda
direita e acompanham as linhas somente na vertical. A primeira leitura acontece
imediatamente ao abrir.

Verificado por medição no mockup: a Bateria e as Ventoinhas começam e
terminam no mesmo pixel.

### 4.2 Os cartões de cima

Chamam-se **CPU**, **GPU** e **Ventoinhas** — não "Processador" e
"Gráficos". São as siglas que a pessoa que abre este app já usa.

Os dois primeiros têm **os mesmos três campos, na mesma ordem**:

```
Modelo   ·   Uso   ·   Temperatura
```

**De onde sai o modelo da GPU.** Consultado **uma vez, ao abrir o app**, e
guardado enquanto ele roda — como já é feito com o modelo da CPU. Não é
valor fixo no código.

O caminho é o PCI, em dois passos que não tocam no dispositivo:

```
/sys/bus/pci/devices/<bdf>/vendor   ->  0x10de
/sys/bus/pci/devices/<bdf>/device   ->  0x28a1
/usr/share/hwdata/pci.ids           ->  "AD107M [GeForce RTX 4050 Max-Q / Mobile]"
```

Os dois atributos do sysfs vêm da configuração que o kernel leu na
enumeração e mantém em cache — **não há transação no barramento**, e por
isso não acordam a dGPU. É a diferença para o `nvidia-smi`, que abre o
dispositivo do driver e emite comando (spec §10.2, armadilha 20).

Sem `pci.ids` instalado, ou com um ID que ele não conheça, a tela mostra o
identificador cru (`10de:28a1`) em vez de travessão — mesmo princípio do
estado da bateria: o desconhecido continua visível.

**Não há linha "Estado".** Se há temperatura e uso na tela, a placa está
acordada; dizer isso de novo é redundância. O estado só aparece quando é
anormal: com a dGPU adormecida, um selo âmbar **adormecida** surge no
título do cartão, os dois valores viram travessão, e **a linha da GPU some
do gráfico** em vez de cair a zero — porque não sondamos, e zero seria
mentira.

Há um segundo selo, **ociosa**, desde 2026-10-10. Com a placa acordada e o
uso em 0% por dez leituras seguidas, a janela para de perguntar ao
`nvidia-smi` para a placa poder dormir — perguntar a cada segundo a mantinha
acesa (medido: 4 min 12 s com a janela aberta, 21 s com ela fechada). Nesse
intervalo, de até 30 s, o cartão **mantém o último valor lido** e a linha do
gráfico segue reta. Se a placa dorme, o selo vira **adormecida**; se outro
programa a segura, os valores voltam a andar. Último valor em vez de
travessão foi escolha do usuário: com outro programa segurando a placa a
pausa volta a cada cinco minutos, e apagar os números toda vez chamaria mais
atenção que o motivo.

Os três cartões têm **mesma quantidade de linhas, mesma ordem de campos e
mesma altura**. Rótulo à esquerda, valor à direita. Cartão com menos
informação preenche com travessão em vez de encolher.

Isto é requisito, não acabamento: é o que permite varrer a coluna com o
olho. Há teste automatizado para as três alturas.

### 4.3 Campo sem valor

Travessão `—`, nunca zero. Zero é um número, e número errado engana.

### 4.4 Posições fixas

Os perfis ocupam sempre as mesmas posições. O que muda com a fonte de
energia é o estado de cada botão, nunca a quantidade nem a ordem. O
indisponível fica **hachurado a 45°, apagado, com o motivo escrito
embaixo** em âmbar.

No Qt o hachurado é pintado à mão no `paintEvent` — QSS não tem gradiente
repetido.

Os quatro primeiros botões são os perfis anunciados pelo firmware. O quinto,
**Desempenho máximo**, é um modo composto do Nexus Sense e aparece em dourado:

```
perfil térmico  balanced-performance
CPU             power-profiles-daemon em performance
GPU             GPUPowerMizerMode = 1
ventoinhas      começam no automático; Máximo e Manual permanecem disponíveis
Dynamic Boost   permanece sob controle do driver NVIDIA
```

Ao ativar, o app guarda os estados anteriores da CPU, GPU e perfil térmico.
Ao desativar, restaura os três. Na bateria o modo fica suspenso e usa o perfil
de bateria; ao reconectar a tomada, o agente reaplica o conjunto máximo. Essa
regra independe da preferência de troca automática dos perfis comuns.
Enquanto estiver ativo, os controles de ventoinha continuam disponíveis. Ao
selecionar Máximo ou Manual, o agente preserva a escolha até outra alteração.

---

### 4.5 Ventoinhas, na tela Desempenho

Três modos, e não um cursor solto: **Automático**, **Máximo** e
**Manual**. Os dois cursores só aparecem no manual — em automático os
números não querem dizer nada, e mostrá-los convidaria a mexer num valor
que o driver ignora.

**Os três botões escrevem na hora.** Manual aplica o que os cursores
mostram: vindo do automático eles estão no começo da barra, e a ventoinha vai
ao piso no clique. Até a v1.2.8 entrar em manual só revelava os cursores, e
nada era escrito até um deles mudar de valor — regra que fazia sentido quando
o cursor em 0 queria dizer automático. Com a barra valendo 20 a 100 a tela
passou a mostrar Manual, cursores no mínimo, e a ventoinha em automático;
para baixá-la era preciso subir e descer o cursor. Decisão do usuário, em
2026-10-11, depois de ver isso na máquina.

A tela fica em Manual enquanto o firmware disser o par que ela escreveu —
inclusive `100,100`, que é o mesmo par do botão Máximo. Se outra mão
escrever (a rede do agente, a bandeja), ela mostra o que o firmware diz.

**O cursor vai de 0 a 100 na tela e vale 20 a 100 no firmware**
(`firmware = 20 + barra × 0,8`, em `model.fan_bar_to_firmware`). De 20% para
baixo a ventoinha gira o mesmo — ~2000 / ~1665 rpm, medido em 2026-10-10 — e
o cursor antigo oferecia essa faixa como se ela mudasse alguma coisa. Com a
escala nova somem a faixa morta e o "0 num lado só", que deixava aquela
ventoinha em automático: automático é só pelo botão. Na leitura, um valor do
piso para baixo aparece como 0, e o cartão do Painel mostra o mesmo número do
cursor. A repintura só mexe no cursor se a posição dele não valer o que está
gravado — a barra tem 101 posições para 81 degraus.

Um clique no trilho leva o marcador diretamente ao ponto clicado. O avanço
por páginas do `QSlider` padrão foi removido porque parecia uma animação
lenta e obrigava vários cliques para chegar ao valor desejado.

O título e a área dos controles têm fundo transparente, igual ao restante
da página. Selecionar perfil ou modo atualiza a marca imediatamente; a
atualização não consulta serviços externos da sessão.

O `0,0` é automático e não "parada": esse atributo é o setpoint, e zero
significa o driver assumindo o controle.

### 4.6 Diagnóstico

Todos os valores ficam abaixo do respectivo rótulo, inclusive modelo,
família e versão. Essa divisão impede sobreposição e mantém a leitura
vertical consistente na largura padrão.

---

## 5. O ícone da bandeja

Duas coisas que custaram medição, as duas contra-intuitivas.

**A polaridade não vem do tema.** `currentColor` só é repintado por temas
que processam o SVG; um arquivo instalado no `hicolor` e resolvido pelo
host da bandeja fica **preto** — e some no painel escuro. Por isso há
duas variantes explícitas de cada ícone, e o app pede a certa:

| tema | sufixo | glifo |
|---|---|---|
| escuro | `-claro` | claro |
| claro | `-escuro` | escuro |

O sufixo nomeia a **cor do desenho**, não a do painel.

**O próprio N mede a escada deste ANV15-52.** Não existe mais barra separada.
O N mantém sua silhueta em baixa intensidade na área vazia e recebe
preenchimento vertical, de baixo para cima, como um recipiente. Os ícones
são quatro níveis (`-v2-nivel1` a `-v2-nivel4`), um para cada perfil
anunciado por este firmware. O `v2` invalida o cache do Plasma que conserva
a imagem antiga quando o conteúdo muda sem que o nome do ícone mude.

```
low-power 1 · quiet 2 · balanced 3 · balanced-performance 4
```

O nível 4 preenche todo o N. A altura visual é a mesma do Bluetooth medido
no painel. As polaridades clara e escura usam exatamente a mesma geometria.

O modo composto não cria um quinto nível de firmware. Ele usa o mesmo N cheio,
em dourado suave: `-v2-max-claro` no painel escuro e `-v2-max-escuro` no
painel claro. Assim a cor distingue o conjunto CPU + GPU do quarto perfil
térmico, embora os dois usem `balanced-performance` no sysfs.

---

### 5.1. Menu da bandeja no Plasma

O SNI anuncia `Menu` como caminho DBus `/MenuBar`. Nesse caminho,
`com.canonical.dbusmenu` fornece o layout, as propriedades, os eventos
`clicked` e a atualização antes da abertura. O Plasma desenha o menu na
própria sessão; não depende de um `QMenu.exec()` aberto pela aplicação.

O menu reutiliza as mesmas ações do menu local. Cada comando mantém seu
id quando a disponibilidade muda; um clique atrasado em um perfil que
sumiu não pode executar outro comando. O perfil marcado é relido antes
da abertura e depois das ações. Controles sem permissão ficam desabilitados.

A exportação usa `dbus-python`, no dispatcher GLib do Qt, no mesmo thread
da GUI. A dependência faz parte do extra `gui` em `pyproject.toml`.
Sem esse transporte, permanece o fallback `QSystemTrayIcon`, sem scroll.
A instância única continua usando QtDBus e o nome estável abaixo.

Referências: [consumidor do Plasma](https://github.com/KDE/plasma-workspace/blob/master/applets/systemtray/statusnotifieritemsource.cpp)
e [tipos e exportação do dbus-python](https://dbus.freedesktop.org/doc/dbus-python/tutorial.html).

## 6. Uma instância só

Reabrir o app registrava um segundo `StatusNotifierItem` — o nome do
serviço leva o PID — e a bandeja ficava com dois ícones. Pior: o antigo
podia sobreviver ao processo que o criou, virando ícone morto.

A instância dona é quem registra `com.nexussense.NexusSense` no
barramento de sessão. Quem não consegue pede a ela que apareça e sai. Não
há arquivo de trava a limpar: se o processo morre, o barramento libera o
nome.

A bandeja sobe com a sessão por `/etc/xdg/autostart`, com `--tray-only`:
o ícone aparece e a janela não.

---

## 7. Decisões fechadas

Aprovadas em 2026-09-06. Cada uma tem um porquê que não se lê no código.

1. **Segue o tema do sistema**, com as duas peles desenhadas. Nem escuro
   fixo nem Breeze cru: a paleta acima define as duas, e o índigo segura os
   dois fundos.

2. **O estado da bateria é traduzido.** O sysfs devolve `Not charging`; a
   tela mostra "não carregando". Tabela de quatro termos, e o desconhecido
   **cai no valor cru**, não em travessão — o que o driver disser continua
   visível.

3. **O nome técnico fica visível.** `low-power` embaixo de "Econômico", e o
   atributo do sysfs em cada controle — em mono, miúdo e apagado, para
   informar sem competir.

4. **`usb_charging = 0` é "desligado"**, não "0%". Zero significa não
   fornecer energia; chamar de 0% seria enganoso do mesmo jeito que chamar
   ventoinha em `0,0` de "parada".

5. **O indisponível fica hachurado**, com o motivo escrito. Não some e não
   vira botão morto sem explicação.

6. **O Diagnóstico informa e não age.** Nenhum botão que peça senha.

---

## 8. Onde isto substitui a spec

Dois pontos da spec `2026-09-05-nexus-sense-gui-agente-design.md` ficam
**revogados** por esta aprovação:

### 8.1 A ação do Diagnóstico sai (spec §6.5)

A spec previa, como última linha do Diagnóstico, uma ação para forçar o
quinto perfil de outro firmware via `nitro_v4`, com `pkexec`. **Ela não
existe mais.** Este ANV15-52 anuncia e usa quatro perfis.

Razão: o ganho é um perfil que **este firmware não anuncia** — o bitmap
`supported_profiles` é `0x53`, sem o bit do Turbo (`0x05`), medido no log
do kernel. E o custo é alto: `nitro_v4` não liga só perfis, troca o
conjunto de quirks inteiro, com efeito em capabilities e na persistência de
estado entre reinícios (ver `armadilhas.md`, armadilha 4).

O Diagnóstico continua **mostrando** o fato — quantos perfis o firmware
anuncia, e o bitmap. Só não oferece o botão.

**Consequência para o plano 2:** a Task 8 inteira existia para essa ação —
o helper, a regra polkit, o `privileged.py` e o roteiro manual. Ela foi
**cancelada** em 2026-09-06. O projeto passa a não ter nenhum código
rodando como root, e some a dependência de `polkit`. Ver `estado.md`.

Sobre o nome: o quinto perfil é o **Turbo** (`performance`), que **não
aparece na tela** porque este firmware não o anuncia — bitmap `0x53`, sem
o bit `0x05`, e o driver registra `Max performance profile: 4`. Forçá-lo
seria acrescentar um botão novo, não revelar um dos quatro existentes.

### 8.2 O informe do Teclado sai (spec §6.4)

A tela Teclado não exibe mais o parágrafo explicando que o RGB de quatro
zonas não aparece porque o firmware não o anuncia, nem a regra de seções
vazias.

Razão: é nota de desenvolvimento vazando para a interface — exatamente o
defeito que a spec §6.4 aponta na GUI antiga com o aviso laranja "This
Section Requires Testing". O comportamento continua valendo (seção sem
controle algum some da barra lateral, e há teste para isso); ele só não é
narrado ao usuário.

---

## 9. Nomes de objeto para a folha de estilo

Já plantados no código, para a QSS mirar sem depender de hierarquia:

| nome | onde |
|---|---|
| `titulo` | título de tela |
| `cartao_titulo` | título de cartão |
| `painel_cabecalho` | linha de perfil e fonte, no Painel |
| `valor_<campo>` | cada valor de cartão |
| `mensagem` | frase de erro de escrita |
| `agente` | rodapé da barra lateral |
| `driver_missing` | tela única de módulo não carregado |

---

## 10. A folha de estilo

Aplicada em `gui/style.py`, nas duas peles. A pele é escolhida pela
**luminância da paleta**, não pelo nome do tema — nome de tema é texto
livre e quebra na primeira distribuição que renomeie.

Um teste varre a QSS atrás de literal de cor solto: trocar de pele tem de
ser trocar o dicionário, e nada mais.

**O gráfico não usa a paleta do Qt.** No Breeze escuro o papel `Mid` é
`#1c1f21`, praticamente o fundo do cartão — o eixo era desenhado e ficava
invisível. As cores dele vêm dos tokens, e há teste medindo o contraste.


### PowerMizer persistente (2026-09-07)

O pedido GPU do modo máximo pertence ao agente, por uma conexão NVML mantida
aberta. A cada 2 segundos o agente verifica a intenção e confirma `1` nessa
conexão. Desativar o modo ou tirar o cabo libera o pedido na passada seguinte;
encerrar o agente também o libera. O Dynamic Boost permanece independente.

No driver NVIDIA 610.57.04, um `nvidia-settings` separado consulta seu próprio
cliente e pode exibir `0` enquanto o agente confirma `1`. Consulte a confirmação
no journal de `nexus-sense-agent.service`. O valor é uma preferência de desempenho
sujeita aos limites do firmware, e não um bloqueio de clocks.
