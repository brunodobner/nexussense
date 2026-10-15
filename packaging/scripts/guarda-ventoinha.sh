#!/bin/sh
# O guarda da ventoinha -- docs/plano-curva.md, secao 8.
#
# Roda como ExecStopPost da unit do agente. O systemd o chama em toda parada
# do agente: saida normal, logout, kill -9, falta de memoria, e o agente
# travado que o WatchdogSec mata. Devolve a ventoinha ao automatico (0,0) se
# ela ainda estiver num manual que o PROPRIO agente escreveu: o agente
# registra, antes de cada escrita, o valor em $RUNTIME_DIRECTORY/ventoinha.
#
# Um manual escolhido na janela nao e do agente e fica como esta -- como hoje,
# ele atravessa reinicios. Quem o protege com o agente vivo e a rede
# (fan_guard.py); com o agente morto, ninguem, e isso nao mudou aqui.
#
# fan_speed e a memoria do driver, e e o que o registro guarda; o EC segue o
# que o driver escreve (E3: dez minutos no piso sem tomar a ventoinha de
# volta). Se o 0,0 for recusado tres vezes, escreve 100,100: a ventoinha no
# maximo e o erro que nao machuca.
#
# Sai sempre com 0: o que aconteceu vai em uma linha para o journal, e a unit
# nao fica "failed" num logout por causa do guarda.
#
# GUARDA_RAIZ e a raiz do sysfs, vazia na maquina; os testes plantam uma
# arvore de mentira (tests/shell/test-guarda-ventoinha.sh).
set -u

R=${GUARDA_RAIZ:-}
[ -n "${RUNTIME_DIRECTORY:-}" ] || exit 0
registro=$RUNTIME_DIRECTORY/ventoinha
[ -s "$registro" ] || exit 0

devolve() {   # $1 = fan_speed. 0 se o 0,0 pegou
    for _ in 1 2 3; do
        printf '0,0\n' 2> /dev/null > "$1" && [ "$(cat "$1" 2> /dev/null)" = "0,0" ] && return 0
        sleep 0.2
    done
    printf '100,100\n' 2> /dev/null > "$1"
    return 1
}

for d in nitro_sense predator_sense; do
    f=$R/sys/devices/platform/acer-wmi/$d/fan_speed
    [ -e "$f" ] || continue
    atual=$(cat "$f" 2> /dev/null)
    if [ "$atual" = "0,0" ]; then
        :
    elif [ -n "$atual" ] && grep -qxF -- "$atual" "$registro"; then
        if devolve "$f"; then
            echo "guarda: o agente parou com a ventoinha em $atual, que ele escreveu; devolvida ao automatico"
        else
            echo "guarda: ERRO, 0,0 recusado tres vezes; ventoinha em $(cat "$f" 2> /dev/null)"
        fi
    else
        echo "guarda: fan_speed e '$atual', que o agente nao escreveu: fica como esta"
    fi
    rm -f "$registro"
    exit 0
done
echo "guarda: nenhum fan_speed em $R/sys/devices/platform/acer-wmi: nada a devolver"
exit 0
