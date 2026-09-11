#!/bin/bash
# Gera os icones do Nexus Sense a partir dos originais em src/.
#
# Por que este script existe: cada decisao aqui foi medida, e varias sao
# contra-intuitivas. Sem o script, a proxima pessoa a mexer nos icones
# refaria as mesmas tentativas erradas. Ver README.md ao lado.
#
# Requer: imagemagick, potrace, librsvg (rsvg-convert).
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")" && pwd)"
SRC="$RAIZ/src"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Azul do app. Escolhido medindo contraste WCAG contra os dois temas:
# 3,79 no escuro e 3,93 no claro -- o mais equilibrado dos candidatos, e
# o unico "profundo e quente" que nao troca um tema pelo outro. O ciano
# original tinha 7,46 no escuro mas so 1,99 no claro, abaixo do minimo.
AZUL='#4A78C8'

TAM_APP="16 22 24 32 48 64 128 256"
TAM_STATUS="16 22 24 32"

echo "==> preparando os mestres"

# Quadra os originais em 512, centralizado, sem esticar. Os arquivos que
# vieram do desenho nao eram exatamente quadrados (500x499 e 498x501).
magick "$SRC/marca-original.png" -background none -gravity center \
    -resize 512x512 -extent 512x512 "$TMP/marca.png"

# ---------------------------------------------------------------------
# Icone do app: a marca inteira -- hexagono, hastes e rede --, com o
# contorno engrossado para aguentar 48 px, chapada no azul.
#
# O engrossamento (Disk:3) nao e enfeite: sem ele a rede vira ruido
# abaixo de 48 px. Foi medido.
# ---------------------------------------------------------------------
echo "==> icone do app"

magick "$TMP/marca.png" -background white -flatten -colorspace gray \
    -threshold 88% -negate "$TMP/tinta.png"
magick "$TMP/tinta.png" -morphology Dilate Disk:3 "$TMP/tinta-grossa.png"
magick "$TMP/tinta-grossa.png" -negate "$TMP/app.pbm"

# --alphamax 0 preserva as esquinas em vez de arredonda-las, e ainda
# resulta em arquivo menor. Comparado lado a lado com o padrao: a 256 px
# os dois sao iguais a olho nu, mas o duro e mais fiel onde ha canto vivo.
potrace "$TMP/app.pbm" -s -o "$TMP/app.svg" \
    --turdsize 2 --alphamax 0 --opttolerance 0.05

install -d "$RAIZ/scalable/apps"
sed "s/fill=\"#000000\"/fill=\"$AZUL\"/" "$TMP/app.svg" \
    > "$RAIZ/scalable/apps/nexus-sense.svg"

for n in $TAM_APP; do
    install -d "$RAIZ/${n}x${n}/apps"
    rsvg-convert -w "$n" -h "$n" "$RAIZ/scalable/apps/nexus-sense.svg" \
        -o "$RAIZ/${n}x${n}/apps/nexus-sense.png"
done

# ---------------------------------------------------------------------
# Icone da bandeja: so o N, sem hexagono, com os nos virando saliencias
# na borda do traco.
#
# O hexagono NAO sai por limiar -- as hastes tem a mesma densidade das
# arestas do N e sobrevivem, virando quatro setas ao redor. Sai por
# componente conexo: o N e uma estrutura conectada unica, as hastes sao
# componentes separados.
#
# A 22 px, que e o tamanho da bandeja, a rede inteira vira ruido
# cinza -- em PNG e em SVG igualmente. So o N preenchido le.
# ---------------------------------------------------------------------
echo "==> icone da bandeja"

magick "$TMP/marca.png" -background white -flatten -colorspace gray \
    -threshold 60% -negate "$TMP/bin.png"

# O componente 8 e o N; os demais sao os vazios internos e as hastes.
COMP=$(magick "$TMP/bin.png" -define connected-components:verbose=true \
    -define connected-components:area-threshold=200 \
    -connected-components 8 null: 2>/dev/null \
    | awk 'NR>1 && $NF ~ /graya\(255/ {print $1; exit}' | tr -d ':')
: "${COMP:=8}"

magick "$TMP/bin.png" -define connected-components:keep="$COMP" \
    -define connected-components:mean-color=true \
    -connected-components 8 "$TMP/n.png"

# 372 de 512 = 73% da altura. Os icones do painel desta maquina ocupam
# entre 64% e 73% da caixa de 22 px (wi-fi 16x14, bluetooth 11x16,
# bateria 10x14). Preenchendo os 512 inteiros, o nosso destoava.
magick "$TMP/n.png" -trim +repage -resize 372x372 \
    -background black -gravity center -extent 512x512 "$TMP/n-menor.png"
magick "$TMP/n-menor.png" -colorspace gray -threshold 50% -negate "$TMP/tray.pbm"
potrace "$TMP/tray.pbm" -s -o "$TMP/tray.svg" \
    --turdsize 2 --alphamax 0 --opttolerance 0.05

install -d "$RAIZ/scalable/status"
# currentColor no mestre, para gerar as duas polaridades a partir de um
# desenho so. NAO conte com o tema para repinta-lo: isso vale para
# icones do proprio Breeze, e um SVG no hicolor resolvido pelo host da
# bandeja fica preto -- some no painel escuro. Quem usa este arquivo e o
# gerador; o app pede sempre as variantes -claro ou -escuro.
sed 's/fill="#000000"/fill="currentColor"/' "$TMP/tray.svg" \
    > "$RAIZ/scalable/status/nexus-sense-tray.svg"

# PNGs de reserva, para ambientes que nao recolorem SVG. Duas polaridades.
for n in $TAM_STATUS; do
    install -d "$RAIZ/${n}x${n}/status"
    sed 's/fill="#000000"/fill="#DCDFE3"/' "$TMP/tray.svg" > "$TMP/tray-claro.svg"
    sed 's/fill="#000000"/fill="#232629"/' "$TMP/tray.svg" > "$TMP/tray-escuro.svg"
    cp "$TMP/tray-claro.svg"  "$RAIZ/scalable/status/nexus-sense-tray-claro.svg"
    cp "$TMP/tray-escuro.svg" "$RAIZ/scalable/status/nexus-sense-tray-escuro.svg"
    rsvg-convert -w "$n" -h "$n" "$TMP/tray-claro.svg" \
        -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-claro.png"
    rsvg-convert -w "$n" -h "$n" "$TMP/tray-escuro.svg" \
        -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-escuro.png"
done

# ---------------------------------------------------------------------
# Variantes por perfil térmico: o próprio N é o indicador. A silhueta em
# baixa intensidade completa a marca e o preenchimento sobe de baixo para
# cima. Em 22 px, um contorno vazado desaparece nas hastes mais finas; a
# silhueta funciona como a borda legível desse recipiente.
#
# Geometria, em unidades do mestre de 512:
#   o N mede 372: 16 px visíveis numa caixa de 22 px, igual ao Bluetooth;
#   preenchimento = i/4 da altura, partindo da base;
#   silhueta vazia = 30% da cor; parte preenchida = 100%.
# ---------------------------------------------------------------------
echo "==> icones de bandeja por perfil"

# So o miolo do SVG da bandeja: o <g> com os paths, sem cabecalho.
sed -n '/<g transform/,/<\/g>/p' \
    "$RAIZ/scalable/status/nexus-sense-tray.svg" > "$TMP/miolo.svg"

# O v2 invalida o cache em memória do Plasma após o redesenho. Apaga tanto
# os nomes anteriores quanto uma geração v2 antiga antes de recriar tudo.
rm -f "$RAIZ/scalable/status/nexus-sense-tray-nivel"*.svg
rm -f "$RAIZ/scalable/status/nexus-sense-tray-v2-nivel"*.svg
for n in $TAM_STATUS; do
    rm -f "$RAIZ/${n}x${n}/status/nexus-sense-tray-nivel"*.png
    rm -f "$RAIZ/${n}x${n}/status/nexus-sense-tray-v2-nivel"*.png
done

# Quatro níveis, um para cada perfil anunciado pelo ANV15-52.
for i in 1 2 3 4; do
    perfil="nivel$i"
    cheio=$((372 * i / 4))
    topo=$((442 - cheio))
    {
        echo '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">'
        echo '<g opacity="0.30">'
        cat "$TMP/miolo.svg"
        echo '</g>'
        # Um SVG interno recorta a segunda cópia do N sem redimensioná-la.
        # Esse recorte é suportado pelo librsvg usado para os PNGs do hicolor.
        echo "<svg x=\"0\" y=\"$topo\" width=\"512\" height=\"$cheio\" viewBox=\"0 $topo 512 $cheio\" overflow=\"hidden\">"
        cat "$TMP/miolo.svg"
        echo '</svg>'
        echo '</svg>'
    } > "$RAIZ/scalable/status/nexus-sense-tray-v2-$perfil.svg"

    # Duas polaridades com cor explicita. O currentColor so e repintado
    # por temas que o processam -- um SVG no hicolor, resolvido pelo host
    # da bandeja, fica preto e some no painel escuro. Medido.
    sed 's/currentColor/#DCDFE3/g' "$RAIZ/scalable/status/nexus-sense-tray-v2-$perfil.svg" \
        > "$TMP/v-claro.svg"
    sed 's/currentColor/#232629/g' "$RAIZ/scalable/status/nexus-sense-tray-v2-$perfil.svg" \
        > "$TMP/v-escuro.svg"
    cp "$TMP/v-claro.svg"  "$RAIZ/scalable/status/nexus-sense-tray-v2-$perfil-claro.svg"
    cp "$TMP/v-escuro.svg" "$RAIZ/scalable/status/nexus-sense-tray-v2-$perfil-escuro.svg"
    for n in $TAM_STATUS; do
        install -d "$RAIZ/${n}x${n}/status"
        rsvg-convert -w "$n" -h "$n" "$TMP/v-claro.svg" \
            -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-v2-$perfil-claro.png"
        rsvg-convert -w "$n" -h "$n" "$TMP/v-escuro.svg" \
            -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-v2-$perfil-escuro.png"
    done
done

# Modo composto: N cheio em dourado, com contraste próprio para cada painel.
# Os nomes claro/escuro continuam descrevendo o destino visual do desenho.
cp "$RAIZ/scalable/status/nexus-sense-tray-v2-nivel4.svg" \
   "$RAIZ/scalable/status/nexus-sense-tray-v2-max.svg"
sed 's/currentColor/#D3A05A/g' \
    "$RAIZ/scalable/status/nexus-sense-tray-v2-max.svg" \
    > "$RAIZ/scalable/status/nexus-sense-tray-v2-max-claro.svg"
sed 's/currentColor/#91601D/g' \
    "$RAIZ/scalable/status/nexus-sense-tray-v2-max.svg" \
    > "$RAIZ/scalable/status/nexus-sense-tray-v2-max-escuro.svg"
for n in $TAM_STATUS; do
    rsvg-convert -w "$n" -h "$n" \
        "$RAIZ/scalable/status/nexus-sense-tray-v2-max-claro.svg" \
        -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-v2-max-claro.png"
    rsvg-convert -w "$n" -h "$n" \
        "$RAIZ/scalable/status/nexus-sense-tray-v2-max-escuro.svg" \
        -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-v2-max-escuro.png"
done

echo "==> pronto"
find "$RAIZ" -name '*.png' -o -name '*.svg' | grep -v '/src/' | sort | sed "s|$RAIZ/|  |"
