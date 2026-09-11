#!/bin/bash
# Verifica no hardware o que o modelo assume: na bateria o driver recusa
# quiet, balanced-performance e performance, e aceita balanced e
# low-power. Ver spec secao 2.8 e nexus_sense.c:2317.
#
# Este teste PULA quando a maquina esta na tomada -- nao ha como
# verificar a recusa com o cabo ligado, e desligar o cabo nao e coisa que
# um teste faca.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

BASE=/sys/devices/platform/acer-wmi
PROFILE=$(echo "$BASE"/platform-profile/platform-profile-*/profile)
CHOICES=$(echo "$BASE"/platform-profile/platform-profile-*/choices)

[ -f "$PROFILE" ] || { echo "ERRO: profile ausente"; exit 3; }
[ -f "$CHOICES" ] || { echo "ERRO: choices ausente"; exit 3; }

AC=""
for nome in AC ACAD ADP1 AC0; do
    [ -f "/sys/class/power_supply/$nome/online" ] && AC="/sys/class/power_supply/$nome/online"
done
[ -n "$AC" ] || { echo "PULOU: nenhuma fonte de energia encontrada"; exit 2; }

[ "$(cat "$AC")" = "0" ] || { echo "PULOU: na tomada; este teste so roda na bateria"; exit 2; }
[ -w "$PROFILE" ] || { echo "PULOU: sem permissao de escrita no profile"; exit 2; }

anunciados=$(cat "$CHOICES")
original=$(cat "$PROFILE")
falhas=0

restaura() { echo "$original" > "$PROFILE" 2>/dev/null; }
trap restaura EXIT

# Os que o driver tem de recusar na bateria.
for perfil in quiet balanced-performance performance; do
    case " $anunciados " in *" $perfil "*) ;; *) continue ;; esac
    if echo "$perfil" > "$PROFILE" 2>/dev/null; then
        echo "FALHA: $perfil foi ACEITO na bateria; esperado -EOPNOTSUPP"
        falhas=$((falhas + 1))
        restaura
    fi
done

# Os que o driver tem de aceitar.
for perfil in low-power balanced; do
    case " $anunciados " in *" $perfil "*) ;; *) continue ;; esac
    if echo "$perfil" > "$PROFILE" 2>/dev/null; then
        agora=$(cat "$PROFILE")
        [ "$agora" = "$perfil" ] || {
            echo "FALHA: escreveu $perfil, leu $agora"; falhas=$((falhas + 1)); }
    else
        echo "FALHA: $perfil foi RECUSADO na bateria; esperado aceitar"
        falhas=$((falhas + 1))
    fi
done

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: na bateria o driver recusa quiet e balanced-performance, aceita balanced e low-power"
exit 0
