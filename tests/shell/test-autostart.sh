#!/bin/bash
# A bandeja tem de subir com a sessao.
#
# Sem esta entrada o icone so aparece se alguem abrir o app a mao -- e um
# icone de bandeja que exige ser invocado nao serve para o que existe.
# A opcao --tray-only foi criada na Task 10 e ficou sem quem a usasse.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
D="$RAIZ/packaging/desktop/nexus-sense-autostart.desktop"
S="$RAIZ/setup.sh"
falhas=0

for alvo in "$D" "$S"; do
    [ -e "$alvo" ] || { echo "ERRO: alvo ausente: $alvo"; exit 3; }
done

confere() {  # $1=descricao  $2=arquivo  $3=padrao
    if grep -q -- "$3" "$2"; then
        echo "  OK   $1"
    else
        echo "  FALHA $1"
        falhas=$((falhas + 1))
    fi
}

confere "comeca so na bandeja"        "$D" '^Exec=.*--tray-only'
confere "nao duplica no menu"         "$D" '^NoDisplay=true'
confere "o instalador a coloca"       "$S" 'xdg/autostart'
confere "a desinstalacao a remove"    "$S" 'nexus-sense-autostart.desktop'

# A entrada nao pode apontar para um executavel que nao existe.
alvo_exec=$(grep '^Exec=' "$D" | sed 's/^Exec=//' | awk '{print $1}')
confere "aponta para o lancador instalado" "$S" "$(basename "$alvo_exec")"

if command -v desktop-file-validate > /dev/null 2>&1; then
    if desktop-file-validate "$D" > /dev/null 2>&1; then
        echo "  OK   desktop-file-validate aceita a entrada"
    else
        echo "  FALHA desktop-file-validate reclamou"
        desktop-file-validate "$D" 2>&1 | sed 's/^/       /'
        falhas=$((falhas + 1))
    fi
else
    echo "  --   desktop-file-validate ausente"
fi

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: a bandeja sobe com a sessao"
exit 0
