#!/bin/bash
# O guarda da ventoinha -- o ExecStopPost da unit do agente -- numa arvore de
# mentira.
#
# packaging/scripts/guarda-ventoinha.sh roda quando o agente para, de
# qualquer jeito que pare. O que este teste guarda:
#   - devolve 0,0 so se fan_speed esta num valor que o agente registrou;
#   - um manual que o agente nao escreveu -- o da janela -- fica como esta;
#   - fora da unit (sem RUNTIME_DIRECTORY) e sem registro, nao faz nada;
#   - o registro sai depois de lido: o proximo agente comeca do zero;
#   - sai sempre com 0, e diz numa linha o que fez.
#
# Nada aqui toca em /sys: o guarda recebe GUARDA_RAIZ. A parte do systemd
# -- quem chama o guarda, e quando -- foi provada com units descartaveis em
# 2026-10-15 (docs/plano-curva.md, secao 8).
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
G="$RAIZ/packaging/scripts/guarda-ventoinha.sh"
[ -x "$G" ] || { echo "ERRO alvo ausente: $G executavel"; exit 3; }

T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2> /dev/null; rm -rf "$T"' EXIT
fail=0
ok()    { echo "  OK    $1"; }
falha() { echo "  FALHA $1"; fail=1; }

caso() {   # $1 = nome, $2 = fan_speed, $3 = registro ("-" para nenhum), $4 = pasta do sensor
    D="$T/$1"
    F="$D/sys/devices/platform/acer-wmi/${4:-nitro_sense}/fan_speed"
    mkdir -p "$(dirname "$F")" "$D/run"
    printf '%s\n' "$2" > "$F"
    [ "$3" = - ] || printf '%b' "$3" > "$D/run/ventoinha"
}
roda() {   # o guarda, como o systemd o chama
    GUARDA_RAIZ="$D" RUNTIME_DIRECTORY="$D/run" "$G" > "$D/saida.txt" 2>&1
}
confere() {   # $1 = descricao, $2 = rc, $3 = fan_speed esperado
    if [ "$2" = 0 ] && [ "$(cat "$F")" = "$3" ]; then
        ok "$1"
    else
        falha "$1: saiu com $2, fan_speed '$(cat "$F")' (esperado 0 e '$3'): $(cat "$D/saida.txt")"
    fi
}

echo "--- o que o agente escreveu volta ao automatico"
caso novo "25,24" '0,0\n25,24\n'
roda; confere "o valor novo do registro e devolvido" "$?" "0,0"
grep -q 'devolvida ao automatico' "$D/saida.txt" \
    && ok "e diz isso numa linha" || falha "nao disse que devolveu: $(cat "$D/saida.txt")"
[ ! -e "$D/run/ventoinha" ] \
    && ok "o registro sai depois de lido" || falha "o registro ficou"

# O agente grava o registro antes de escrever: um kill -9 entre as duas
# coisas deixa em fan_speed o valor de antes, que tambem e dele.
caso anterior "25,24" '25,24\n35,37\n'
roda; confere "o valor de antes do registro tambem e devolvido" "$?" "0,0"

caso predator "40,40" '0,0\n40,40\n' predator_sense
roda; confere "o sensor em predator_sense tambem" "$?" "0,0"

echo "--- o que nao e do agente fica"
caso janela "60,60" '0,0\n25,24\n'
roda; confere "um manual que o agente nao escreveu fica como esta" "$?" "60,60"
grep -q 'que o agente nao escreveu' "$D/saida.txt" \
    && ok "e diz por que nao mexeu" || falha "nao disse por que nao mexeu: $(cat "$D/saida.txt")"

caso sem-registro "25,24" -
roda; confere "sem registro, nada muda" "$?" "25,24"

caso automatico "0,0" '0,0\n25,24\n'
roda; confere "ja no automatico, nada muda" "$?" "0,0"

caso fora-da-unit "25,24" '0,0\n25,24\n'
GUARDA_RAIZ="$D" "$G" > "$D/saida.txt" 2>&1
confere "sem RUNTIME_DIRECTORY -- fora da unit -- nada muda" "$?" "25,24"

# O registro com uma linha so, e um valor que contem o outro: grep -x, e
# nao um pedaco da linha.
caso parecido "5,5" '0,0\n25,25\n'
roda; confere "um valor que so aparece dentro de outro nao conta" "$?" "5,5"

echo "--- a escrita recusada"
# Como root o chmod nao recusa nada, e a recusa nao se simula.
if [ "$(id -u)" = 0 ]; then
    echo "  --    como root a recusa nao se simula"
else
    caso recusa "25,24" '0,0\n25,24\n'
    chmod a-w "$F"
    roda; rc=$?
    [ "$rc" = 0 ] && grep -q 'ERRO, 0,0 recusado' "$D/saida.txt" \
        && ok "0,0 recusado: sai com 0 e diz o erro" \
        || falha "0,0 recusado: saiu com $rc: $(cat "$D/saida.txt")"
fi

echo
[ "$fail" -eq 0 ] && echo "PASSOU" || echo "FALHOU"
exit "$fail"
