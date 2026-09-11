#!/bin/bash
# O contrato do atributo usb_charging e: 0 (desligado) ou 10/20/30 (ligado
# naquele limiar de bateria). -1 significa que o driver nao soube decodificar
# o que o firmware devolveu -- nunca deveria chegar ao usuario.
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
ATTR=/sys/devices/platform/acer-wmi/nitro_sense/usb_charging
fail=0

[ -e "$ATTR" ] || { echo "  PULADO usb_charging nao exposto neste modelo"; exit 2; }

valor=$(cat "$ATTR" 2>/dev/null)
echo "  valor lido: $valor"

case "$valor" in
  0|10|20|30) echo "  OK   valor dentro do contrato (0/10/20/30)" ;;
  -1) echo "  FALHA driver devolveu -1: nao decodificou a resposta do firmware"; fail=1 ;;
  *)  echo "  FALHA valor inesperado: $valor"; fail=1 ;;
esac

# A decodificacao tem de tratar limiar e flag como campos separados, nao
# como uma lista de valores inteiros conhecidos.
S="$DRV/src/nexus_sense.c"
exigir "$S"
fn=$(sed -n '/^static ssize_t predator_usb_charging_show/,/^}/p' "$S")

if printf '%s' "$fn" | grep -q '663296'; then
  echo "  FALHA show() ainda compara contra valores inteiros crus"
  fail=1
else
  echo "  OK   show() nao depende de tabela de valores crus"
fi

exit $fail
