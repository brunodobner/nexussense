#!/bin/bash
# Garante que o indicador do ANV15-52 tem quatro estados visivelmente distintos.
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$RAIZ/packaging/icons/22x22/status"

for polaridade in claro escuro; do
    arquivos=("$DIR"/nexus-sense-tray-v2-nivel*-"$polaridade".png)
    [ "${#arquivos[@]}" -eq 4 ] || {
        echo "FALHA: $polaridade tem ${#arquivos[@]} variantes, esperado 4"
        exit 1
    }
    distintos=$(sha256sum "${arquivos[@]}" | awk '{print $1}' | sort -u | wc -l)
    [ "$distintos" -eq 4 ] || {
        echo "FALHA: os quatro níveis $polaridade não são distintos"
        exit 1
    }
done

for polaridade in claro escuro; do
    [ -f "$DIR/nexus-sense-tray-v2-max-$polaridade.png" ] || {
        echo "FALHA: falta o ícone dourado $polaridade"
        exit 1
    }
done

if find "$RAIZ/packaging/icons" -type f \
    \( -name 'nexus-sense-tray-nivel*' -o -name '*nivel5*' \) | grep -q .; then
    echo "FALHA: ainda existe uma variante antiga ou nivel5"
    exit 1
fi

echo "OK: quatro níveis distintos nas duas polaridades"
