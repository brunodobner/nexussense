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

# --- a poda de 2026-09-11: um modelo so
#
# O driver atende o ANV15-52 e mais nada. Estas asserções existem para
# que ninguem reintroduza modelo sem decisao -- e, principalmente, para
# separar a poda SEGURA (tabela DMI) da PERIGOSA (subsistemas).
#
# Capabilities vem de tres fontes, e so uma delas e a tabela: o descritor
# AA do firmware liga WIRELESS e BLUETOOTH em tempo de execucao. Por isso
# o criterio de regressao nao e a tabela, e sim o bitmask medido --
# 0x2c26 nesta maquina -- e os dois rfkill do Acer continuarem
# registrados. Ver docs/decisoes.md secao 6.
C="$DRV/src/nexus_sense.c"

n_dmi=$(grep -c 'DMI_MATCH(DMI_SYS_VENDOR' "$C" || true)
if [ "$n_dmi" -eq 1 ]; then
  echo "  OK   uma entrada DMI so"
else
  echo "  FALHA $n_dmi entradas DMI (esperado 1: o ANV15-52)"; fail=1
fi

n_quirk=$(grep -c '^static struct quirk_entry quirk_' "$C" || true)
if [ "$n_quirk" -eq 2 ]; then
  echo "  OK   dois quirks: o do modelo e o quirk_unknown"
else
  echo "  FALHA $n_quirk structs de quirk (esperado 2)"; fail=1
fi

for sumido in non_acer_quirks acer_blacklist amw0_whitelist; do
  if grep -q "^static const struct dmi_system_id $sumido" "$C"; then
    echo "  FALHA $sumido voltou"; fail=1
  else
    echo "  OK   $sumido continua removida"
  fi
done

# O quirk do modelo tem de ser nitro_sense, nunca nitro_v4: este ultimo
# seta ACER_CAP_PREDATOR_SENSE, e trocar levaria junto a persistencia do
# perfil termico entre reinicios. Ver docs/decisoes.md secao 5.
if grep -A2 '^static struct quirk_entry quirk_acer_anv15_52' "$C" | grep -q '\.nitro_sense = 1'; then
  echo "  OK   o quirk do modelo usa nitro_sense"
else
  echo "  FALHA o quirk do ANV15-52 nao usa nitro_sense"; fail=1
fi

# A instrumentacao do bitmask e o que torna qualquer poda futura
# verificavel. Sem ela, o corte volta a ser opinativo.
if grep -q 'acer_dump_capabilities' "$C"; then
  echo "  OK   a medicao do bitmask continua no driver"
else
  echo "  FALHA acer_dump_capabilities sumiu: a poda perde o criterio"; fail=1
fi

exit $fail
