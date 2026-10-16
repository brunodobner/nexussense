#!/bin/bash
# O ensaio termico pausa a curva propria do agente, e a devolve como estava.
#
# Desde 2026-10-17 a curva e o Automatico neste modelo: sem fan_curve no
# config, ou com true, o agente toma o 0,0 em 2 s e grava o par dela. Os
# ensaios comecam no 0,0 e medem o automatico do firmware: com a curva
# valendo, recusariam a partida, ou mediriam a curva. O roteiro grava
# fan_curve = false antes da partida e devolve a linha no fim -- pelo trap e,
# num kill -9, pelo vigia. Aqui, contra a arvore de mentira, com uma curva
# falsa no ar (lib-arvore-termica.sh, curva_falsa).
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/tests/hardware/ensaio-termico.sh"

# shellcheck source=tests/shell/lib-arvore-termica.sh
source "$RAIZ/tests/shell/lib-arvore-termica.sh"

E2=(env ENSAIO_PORCENTAGENS="100 50 10" "$S" e2)

caso() {   # $1 = nome, $2 = o config da partida -> arvore em $D, com a curva no ar
    nova "$1"
    printf '%s\n' "$2" > "$D/config.toml"
    cp "$D/config.toml" "$D/config.antes"
    com_curva 25,24
    # Com a curva valendo, ela toma o 0,0 antes de o roteiro comecar.
    case "$2" in *"fan_curve = false"*) ;; *) espera_fan "$D" "25,24" 30 ;; esac
}

config_igual() {   # $1 = descricao
    if cmp -s "$D/config.toml" "$D/config.antes"; then
        ok "$1"
    else
        falha "$1: o config ficou '$(tr '\n' '|' < "$D/config.toml")', era '$(tr '\n' '|' < "$D/config.antes")'"
    fi
}

curva_retoma() {   # $1 = descricao
    if espera_fan "$D" "25,24" 30; then ok "$1"; else falha "$1: fan_speed ficou '$(fan "$D")'"; fi
}

echo "--- o E2, com a curva valendo"
caso padrao "maximum_mode = false"
fan "$D" | grep -qx "25,24" && ok "a curva falsa toma o 0,0 (o controle do teste)" \
    || falha "a curva falsa nao tomou o 0,0: '$(fan "$D")'"
roda "$D" "${E2[@]}" "$D/e2.tsv"
rc=$?
[ "$rc" = 0 ] && ok "sem fan_curve no config, o E2 pausa a curva e termina" \
    || falha "o E2 saiu com $rc: $(grep -m3 'RECUSA\|ENCERRADO\|ERRO' "$D/saida.txt" | tr '\n' '|')"
grep -q '^curva propria pausada (fan_curve = false, era ausente)' "$D/saida.txt" \
    && ok "diz que pausou, e o que era" || falha "nao disse que pausou"
config_igual "no fim a linha sai do config, e o arquivo volta byte a byte"
curva_retoma "com a linha fora, a curva retoma a ventoinha"

caso ligada "$(printf 'maximum_mode = false\nfan_curve = true\nbattery_profile = "balanced"')"
roda "$D" "${E2[@]}" "$D/e2.tsv"
rc=$?
[ "$rc" = 0 ] && ok "com fan_curve = true, o E2 pausa e termina" || falha "o E2 saiu com $rc"
config_igual "no fim fan_curve = true volta no mesmo lugar"
curva_retoma "e a curva retoma"

caso desligada "$(printf 'fan_curve = false\nmaximum_mode = false')"
roda "$D" "${E2[@]}" "$D/e2.tsv"
rc=$?
[ "$rc" = 0 ] && ok "com fan_curve = false, o E2 roda sem pausar" || falha "o E2 saiu com $rc"
grep -q 'curva propria' "$D/saida.txt" \
    && falha "com a curva ja desligada, o roteiro mexeu nela" || ok "com a curva ja desligada, nada a pausar"
config_igual "o config fica como estava"

echo "--- a saida antes da partida"
caso recusa "maximum_mode = false"
poe "$D/sys/class/power_supply/BAT1/charge_now" 1000000
roda "$D" "${E2[@]}" "$D/e2.tsv"
rc=$?
[ "$rc" = 12 ] && ok "bateria baixa: recusa a partida (12)" || falha "a recusa saiu com $rc"
config_igual "recusado antes dos traps do modo, a linha volta mesmo assim"
curva_retoma "e a curva retoma"

caso sinal "maximum_mode = false"
PASSO=0.3 lanca "$D" "${E2[@]}" "$D/e2.tsv"
for ((i = 0; i < 100; i++)); do
    grep -q 'fan_curve = false' "$D/config.toml" && break
    sleep 0.05
done
kill -TERM "$PID"
wait "$PID"
config_igual "um SIGTERM logo depois da pausa devolve a linha"

echo "--- o kill -9, com o vigia no ar"
caso kill9 "maximum_mode = false"
PASSO=0.3 lanca "$D" "${E2[@]}" "$D/e2.tsv"
espera_fan "$D" "100,100" 600 || falha "o E2 nao chegou ao mapa: $(tail -3 "$D/saida.txt" | tr '\n' '|')"
grep -q 'fan_curve = false' "$D/config.toml" \
    && ok "no meio do mapa a curva esta pausada" || falha "no meio do mapa a curva nao estava pausada"
{ kill -KILL "$PID"; wait "$PID"; } 2> /dev/null
for ((i = 0; i < 60; i++)); do
    cmp -s "$D/config.toml" "$D/config.antes" && break
    sleep 0.1
done
config_igual "depois de um kill -9 o vigia devolve a linha"
curva_retoma "e a curva retoma a ventoinha que o vigia devolveu"

echo "--- todo modo que comeca no automatico pausa antes da partida"
# Em cada modo, pausa_curva vem antes da primeira amostra da partida. O
# _segura e o --vigia sao filhos de um modo; o ec5-volta devolve a pausa do ec5.
for m in modo_e2 modo_e3 modo_e3b modo_rede modo_ec2 modo_ec3 modo_ec5; do
    awk -v f="$m() {" '
        index($0, f) == 1 { dentro = 1; next }
        dentro && /^}/ { exit }
        dentro && /^    pausa_curva$/ { pausa = NR }
        dentro && /amostra partida/ && !visto { visto = NR }
        END { exit !(pausa && visto && pausa < visto) }
    ' "$S" && ok "$m pausa a curva antes da partida" || falha "$m nao pausa a curva antes da partida"
done

exit "$fail"
