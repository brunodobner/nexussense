#!/bin/bash
# Verifica que os seis atributos graveis estao com grupo e permissao, e
# que a escrita como usuario comum passa -- que e o resultado que
# dispensa o daemon root. Ver spec secao 2.7.
#
# Saidas, conforme o contrato do run-all.sh:
#   0 passou   2 pulou (sem driver ou fora do grupo)   3 alvo ausente
set -u

BASE=/sys/devices/platform/acer-wmi
GRUPO=nexus_sense

falhas=0

# ─── a regra, lida do repositorio ───────────────────────────────────
# Vem antes de qualquer pulo: nao depende de driver carregado nem de grupo,
# e uma falha aqui nao pode sair como "pulou".
REGRA="$(cd "$(dirname "$0")/../.." && pwd)/packaging/udev/60-nexus-sense.rules"
[ -e "$REGRA" ] || { echo "ERRO: alvo ausente: $REGRA"; exit 3; }

# O 'add' do dispositivo sai ANTES do probe, que e quem cria os atributos:
# a regra corria contra a criacao deles e ganhava por margem. O 'bind' e
# emitido depois que o probe termina, com tudo no lugar.
if grep 'SUBSYSTEM=="platform"' "$REGRA" | grep -qE '^ACTION=="([a-z]+\|)*bind(\|[a-z]+)*"'; then
    echo "  OK   a regra do dispositivo dispara em bind"
else
    echo "FALHA: a regra do acer-wmi nao dispara em bind"
    exit 1
fi

if udevadm verify --help > /dev/null 2>&1; then
    if udevadm verify "$REGRA" > /dev/null 2>&1; then
        echo "  OK   udevadm verify aceita a regra"
    else
        echo "FALHA: udevadm verify recusou a regra"
        udevadm verify "$REGRA" 2>&1 | sed 's/^/       /'
        exit 1
    fi
else
    echo "  --   udevadm verify ausente"
fi

# ─── o estado da maquina ────────────────────────────────────────────
# Sem driver carregado nao ha o que testar.
[ -d "$BASE" ] || { echo "PULOU: acer-wmi ausente"; exit 2; }

SENSE=""
for nome in nitro_sense predator_sense; do
    [ -d "$BASE/$nome" ] && SENSE="$BASE/$nome"
done
[ -n "$SENSE" ] || { echo "ERRO: nem nitro_sense nem predator_sense"; exit 3; }

PROFILE=$(echo "$BASE"/platform-profile/platform-profile-*/profile)
[ -f "$PROFILE" ] || { echo "ERRO: profile ausente"; exit 3; }

# O grupo tem de existir e o usuario tem de estar nele. Se nao estiver,
# o teste pula em vez de falhar: quem acabou de entrar no grupo precisa
# relogar, e isso nao e defeito do codigo.
getent group "$GRUPO" >/dev/null || { echo "PULOU: grupo $GRUPO nao existe"; exit 2; }
id -nG | tr ' ' '\n' | grep -qx "$GRUPO" || {
    echo "PULOU: sessao fora do grupo $GRUPO (relogar?)"; exit 2; }

ALVOS="$SENSE/fan_speed $SENSE/battery_limiter $SENSE/usb_charging \
       $SENSE/backlight_timeout $SENSE/battery_calibration $PROFILE"

for alvo in $ALVOS; do
    [ -f "$alvo" ] || { echo "FALHA: ausente: $alvo"; falhas=$((falhas + 1)); continue; }
    dono=$(stat -c '%G' "$alvo")
    modo=$(stat -c '%a' "$alvo")
    [ "$dono" = "$GRUPO" ] || { echo "FALHA: grupo $dono em $alvo"; falhas=$((falhas + 1)); }
    [ "$modo" = "664" ]    || { echo "FALHA: modo $modo em $alvo"; falhas=$((falhas + 1)); }
done

# version tem de continuar somente-leitura.
if [ -f "$SENSE/version" ]; then
    modo=$(stat -c '%a' "$SENSE/version")
    [ "$modo" = "444" ] || { echo "FALHA: version com modo $modo, esperado 444"; falhas=$((falhas + 1)); }
fi

# A escrita de verdade, como usuario comum. backlight_timeout e o mais
# inocuo dos seis; restaura o valor original em seguida.
alvo="$SENSE/backlight_timeout"
if [ -w "$alvo" ]; then
    antes=$(cat "$alvo")
    outro=$([ "$antes" = "1" ] && echo 0 || echo 1)
    if echo "$outro" > "$alvo" 2>/dev/null; then
        agora=$(cat "$alvo")
        [ "$agora" = "$outro" ] || { echo "FALHA: escreveu $outro, leu $agora"; falhas=$((falhas + 1)); }
        echo "$antes" > "$alvo" 2>/dev/null
    else
        echo "FALHA: escrita como usuario comum recusada em $alvo"
        falhas=$((falhas + 1))
    fi
else
    echo "FALHA: $alvo nao esta gravavel"
    falhas=$((falhas + 1))
fi

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: seis atributos com grupo $GRUPO, escrita sem root confirmada"
exit 0
