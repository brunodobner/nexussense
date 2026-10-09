#!/bin/bash
# Os dois lancadores nao podem importar modulo do diretorio corrente.
#
# `python3 -m pacote` poe o diretorio corrente na frente do sys.path. O
# agente e a bandeja sobem com a sessao, em $HOME: um tomli_w.py largado
# ali -- por engano ou de proposito -- era executado no lugar do
# verdadeiro, com os privilegios de quem esta no grupo nexus_sense.
# Medido em 2026-10-09: os dois lancadores importavam o modulo plantado.
#
# Como o resto da suite este teste nao instala nada: extrai o texto dos
# lancadores do setup.sh, aponta o pacote para src/ e os executa de dentro
# de um diretorio com o modulo plantado.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/setup.sh"
falhas=0

exigir() {
    [ -e "$1" ] || { echo "ERRO: alvo ausente: $1"; exit 3; }
}

exigir "$S"
exigir "$RAIZ/src/nexus_sense/__main__.py"
exigir "$RAIZ/src/nexus_sense/gui/app.py"

# Sem as dependencias o --version falha no import, plantado ou nao, e o
# teste nao teria como distinguir uma coisa da outra.
/usr/bin/python3 -c 'import PySide6, dbus, tomli_w' > /dev/null 2>&1 || {
    echo "PULOU: dependencias de execucao ausentes"; exit 2; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/bin" "$T/plantado"
MARCA="$T/marca"
export MARCA

cat > "$T/plantado/tomli_w.py" << 'EOL'
import os
open(os.environ["MARCA"], "a").write("importado\n")
raise ImportError("modulo plantado no diretorio corrente")
EOL

# Controle: o modulo plantado tem de ser alcancavel. Se um dia o pacote
# deixar de importar tomli_w, a marca nunca apareceria e o teste passaria
# por vacuo -- ver armadilha 14.
for modulo in nexus_sense nexus_sense.gui.app; do
    rm -f "$MARCA"
    ( cd "$T/plantado" && PYTHONPATH="$RAIZ/src" /usr/bin/python3 -m "$modulo" --version ) \
        > /dev/null 2>&1
    [ -s "$MARCA" ] || {
        echo "ERRO: $modulo nao importa tomli_w; o teste perdeu o alvo"; exit 3; }
done

for nome in nexus-sense nexus-sense-agent; do
    # O corpo do heredoc, sem a linha do cat e sem o terminador.
    sed -n "/^  cat > \/usr\/bin\/${nome} << 'EOL'\$/,/^EOL\$/p" "$S" \
        | sed '1d;$d' > "$T/bin/$nome"
    [ -s "$T/bin/$nome" ] || {
        echo "ERRO: lancador $nome nao encontrado no setup.sh"; exit 3; }
    grep -q '/usr/lib/nexus-sense' "$T/bin/$nome" || {
        echo "ERRO: lancador $nome nao aponta para /usr/lib/nexus-sense"; exit 3; }

    sed -i "s|/usr/lib/nexus-sense|$RAIZ/src|" "$T/bin/$nome"
    chmod +x "$T/bin/$nome"

    rm -f "$MARCA"
    saida=$(cd "$T/plantado" && "$T/bin/$nome" --version 2>&1)
    st=$?

    if [ -s "$MARCA" ]; then
        echo "  FALHA $nome importou o modulo plantado no diretorio corrente"
        falhas=$((falhas + 1))
    else
        echo "  OK   $nome ignora o modulo plantado"
    fi

    if [ "$st" -eq 0 ] && printf '%s' "$saida" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "  OK   $nome ainda acha o pacote: $saida"
    else
        echo "  FALHA $nome --version saiu $st: $(printf '%s' "$saida" | tail -1)"
        falhas=$((falhas + 1))
    fi
done

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: os lancadores nao importam do diretorio corrente"
exit 0
