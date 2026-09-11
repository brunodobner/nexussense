#!/bin/bash
# Verifica que o ANV15-52 e classificado como Nitro (nao Predator) e expoe
# exatamente os atributos que o hardware suporta.
set -u

# Localiza os alvos a partir da raiz do repositorio: estes testes vivem
# fora de driver/, para sobreviverem a sobrescrita da pasta na proxima
# release do upstream -- que e exatamente quando eles sao mais necessarios.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DRV="$ROOT/driver"

# Sem isto um alvo ausente faria as asserções de ausencia passarem por
# vacuo: grep num arquivo inexistente falha, e "falhou" era lido como
# "padrao ausente". Alvo sumido tem de ser erro alto, nao aprovacao.
exigir() {
  [ -e "$1" ] || { echo "  ERRO alvo ausente: $1"; exit 3; }
}
BASE=/sys/devices/platform/acer-wmi
ESPERADO="backlight_timeout battery_calibration battery_limiter fan_speed usb_charging version"
fail=0

modelo=$(cat /sys/class/dmi/id/product_name)
if [ "$modelo" != "Nitro ANV15-52" ]; then
  echo "  PULADO: este teste exige um Nitro ANV15-52 (achei: $modelo)"; exit 2
fi

if [ -d "$BASE/nitro_sense" ]; then
  echo "  OK   nitro_sense/ existe"
else
  echo "  FALHA nitro_sense/ ausente -- quirk nao casou"; exit 1
fi

if [ -d "$BASE/predator_sense" ]; then
  echo "  FALHA predator_sense/ existe -- classificado como Predator"; fail=1
else
  echo "  OK   predator_sense/ ausente"
fi

obtido=$(ls "$BASE/nitro_sense" | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$obtido" = "$ESPERADO" ]; then
  echo "  OK   atributos exatos: $obtido"
else
  echo "  FALHA atributos"
  echo "        esperava: $ESPERADO"
  echo "        obteve:   $obtido"
  fail=1
fi

for fantasma in lcd_override boot_animation_sound; do
  if [ -e "$BASE/nitro_sense/$fantasma" ]; then
    echo "  FALHA $fantasma presente -- le -1, nao deveria aparecer no painel"
    fail=1
  else
    echo "  OK   $fantasma ausente"
  fi
done

exit $fail
