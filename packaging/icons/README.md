# Ícones do Nexus Sense

Tudo aqui é gerado por `gerar.sh` a partir de `src/`. Não edite os PNGs
nem os SVGs à mão — rode o script.

```bash
bash packaging/icons/gerar.sh
```

Requer `imagemagick`, `potrace` e `librsvg`.

## O que existe

| arquivo | onde é usado |
|---|---|
| `scalable/apps/nexus-sense.svg` | ícone do app: `.desktop`, menu, barra de título, alt-tab |
| `NxN/apps/nexus-sense.png` | reserva para ambientes que não rasterizam SVG |
| `scalable/status/nexus-sense-tray.svg` | ícone da bandeja, recolorido pelo tema |
| `NxN/status/nexus-sense-tray-{claro,escuro}.png` | reserva, nas duas polaridades |
| `src/marca-original.png` | a marca monocromática, como desenhada |
| `src/app-colorido-original.png` | a versão colorida original, preservada para referência |

## Por que cada decisão

Todas foram medidas. Várias são contra-intuitivas, e é por isso que estão
escritas — sem elas, a próxima pessoa refaz as mesmas tentativas erradas.

### O ícone da bandeja não é a marca

A marca é uma rede de ~20 nós e ~40 arestas dentro de um hexágono. A
bandeja desenha em **22 px**. Nesse tamanho cada aresta ocupa menos de um
pixel, e o resultado não é o desenho reduzido: é cinza embaralhado.

Foram testados quatro candidatos, em PNG e em SVG, todos ampliados e
comparados a 22 px:

| candidato | peso do SVG | legível a 22 px |
|---|---|---|
| marca completa | 17,0 KB | não |
| rede sem hexágono | 25,5 KB | não |
| rede engrossada | 15,9 KB | não |
| **N preenchido** | **3,4 KB** | **sim** |

O peso do SVG mede quanto contorno o desenho carrega, e a ordem é
exatamente a mesma da ilegibilidade. Vinte e cinco mil bytes de contorno
não cabem em 484 pixels.

O N preenchido não joga a marca fora: ao preencher o contorno da rede, os
nós que ficavam na borda viram **saliências no traço**. A 22 px elas ainda
se veem, e são o que distingue este N de um N qualquer de fonte.

### O hexágono não sai por limiar

As hastes do hexágono têm a mesma densidade das arestas do N. Qualquer
limiar que mantenha a rede mantém as hastes também, e elas sobram como
quatro setas ao redor do N.

Sai por **componente conexo**: o N é uma estrutura conectada única; as
hastes são componentes separados. É o que `gerar.sh` faz.

### O tamanho da tinta importa

Os ícones do painel do Plasma não preenchem a caixa. Medidos nesta
máquina, numa caixa de 22×22: wi-fi `16×14`, bluetooth `11×16`, bateria
`10×14` — entre 64% e 73% da altura.

A primeira versão do nosso tinha `20×22` e destoava dos vizinhos por
parecer maior. O script reduz para 73%, resultando em `16×16`.

### O azul foi escolhido por contraste, não por gosto

Contraste WCAG do preenchimento contra o fundo dos dois temas (mínimo 3,0
para elemento gráfico):

| tom | escuro | claro |
|---|---|---|
| `#5FBAD6` ciano original | 7,46 | **1,99** ✗ |
| `#4E93C9` azul aço | 4,99 | 2,98 ✗ |
| `#3E8FD9` azul médio | 4,83 | 3,08 |
| `#2F7FD1` azul profundo | 4,00 | 3,73 |
| **`#4A78C8` índigo — o escolhido** | **3,79** | **3,93** |
| `#3E5FC4` índigo forte | 2,86 ✗ | 5,20 |

O ciano do desenho original reprova no tema claro. O `#4A78C8` é o mais
equilibrado: comporta-se praticamente igual nos dois temas.

### O app não vira SVG a partir do colorido

A versão colorida original tem **19.074 cores distintas** — degradê,
brilho e textura. Vetor guarda contorno, não pixel; traçar aquilo exigiria
milhares de regiões de cor chapada, resultando em arquivo maior e desenho
pior. Ela fica preservada em `src/` como referência.

O ícone do app aqui é a **marca monocromática chapada no azul**, que é
contorno puro e portanto vetorizável sem perda.

### Por que o contorno é engrossado

O app renderiza a marca completa, com hexágono e rede. Sem engrossar
(`Dilate Disk:3`), a rede vira ruído abaixo de 48 px. Com o engrossamento,
ela aguenta até 48 e degrada de forma limpa daí para baixo.

### `--alphamax 0` no potrace

Preserva as esquinas em vez de arredondá-las, e resulta em arquivo menor.
Comparados lado a lado a 256 px, o traçado duro e o suave são iguais a
olho nu — mas o duro é mais fiel onde há canto vivo.

## Quatro níveis no próprio N

O ANV15-52 anuncia quatro perfis. Cada perfil usa uma variante do N:
`v2-nivel1` a `v2-nivel4`. O preenchimento sobe de baixo para cima dentro da
silhueta. A parte vazia fica em 30% da cor e mantém o N completo como a
borda do indicador.

Não existe barra separada. O N ocupa 16 px quando o painel pede 22 px: a
mesma altura visual medida no Bluetooth. Um contorno vazado perdia as
hastes finas nessa resolução; a silhueta em baixa intensidade preserva a
forma. O nível 1 preenche o quarto inferior; o nível 4 preenche toda a marca.

O componente `v2` no nome é intencional. O Plasma mantém ícones do tema em
memória e continuou exibindo o desenho anterior mesmo depois de o arquivo e
o processo da bandeja serem substituídos. Um nome novo força nova resolução.

O modo **Desempenho máximo** é composto pelo app e não é um quinto perfil do
firmware. Ele reutiliza o N completamente cheio em dourado suave, nos arquivos
`v2-max-claro` e `v2-max-escuro`. A geometria e a altura permanecem iguais às
dos quatro níveis; somente a cor comunica que CPU e GPU estão priorizadas.

Cada nível tem variantes `-claro` e `-escuro`. As duas usam a mesma
geometria; só a cor explícita muda, porque o host da bandeja não recolore
de forma confiável SVGs encontrados no tema `hicolor`.
