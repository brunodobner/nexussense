#!/bin/sh
# Aplica grupo e permissao nos seis atributos graveis do Nexus Sense.
#
# Chamado pela regra udev 60-nexus-sense.rules. Roda cedo, quando o
# dispositivo aparece; um atributo que ainda nao exista e simplesmente
# pulado, e a regra dispara de novo no 'change' seguinte.
#
# Silencioso de proposito: udev nao e lugar de imprimir.
set -u

GRUPO=nexus_sense
BASE=/sys/devices/platform/acer-wmi

getent group "$GRUPO" >/dev/null 2>&1 || exit 0

for alvo in \
    "$BASE"/nitro_sense/fan_speed \
    "$BASE"/nitro_sense/battery_limiter \
    "$BASE"/nitro_sense/usb_charging \
    "$BASE"/nitro_sense/backlight_timeout \
    "$BASE"/nitro_sense/battery_calibration \
    "$BASE"/predator_sense/fan_speed \
    "$BASE"/predator_sense/battery_limiter \
    "$BASE"/predator_sense/usb_charging \
    "$BASE"/predator_sense/backlight_timeout \
    "$BASE"/predator_sense/battery_calibration \
    "$BASE"/platform-profile/platform-profile-*/profile
do
    [ -f "$alvo" ] || continue
    chgrp "$GRUPO" "$alvo" 2>/dev/null && chmod g+w "$alvo" 2>/dev/null
done

exit 0
