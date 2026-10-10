#!/bin/bash
# Verifica que o dkms.conf registra e COMPILA nos dois tipos de toolchain.
# Usa uma versao de teste para nao colidir com a instalacao real.
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
SRC="$DRV"
exigir "$SRC/dkms.conf"
exigir "$SRC/Makefile"
VER_TESTE="0.0.0-test"
DEST="/usr/src/nexus_sense-${VER_TESTE}"
fail=0

if [ "$EUID" -ne 0 ]; then echo "Rode como root: sudo $0"; exit 2; fi
# Root num lugar sem dkms -- o container do CI de cada push -- reprovava
# no 'dkms add' por um defeito que nao e do pacote.
command -v dkms > /dev/null 2>&1 || { echo "PULOU: dkms nao instalado"; exit 2; }

limpar() {
  dkms remove -m nexus_sense -v "$VER_TESTE" --all >/dev/null 2>&1 || true
  rm -rf "$DEST" "/var/lib/dkms/nexus_sense/${VER_TESTE}"
}
trap limpar EXIT
limpar

mkdir -p "$DEST"
cp -r "$SRC/src" "$SRC/Makefile" "$DEST/"
sed "s/^PACKAGE_VERSION=.*/PACKAGE_VERSION=\"${VER_TESTE}\"/" \
    "$SRC/dkms.conf" > "$DEST/dkms.conf"

if dkms add -m nexus_sense -v "$VER_TESTE" >/dev/null 2>&1; then
  echo "  OK   dkms add"
else
  echo "  FALHA dkms add"; exit 1
fi

# Os kernels saem da maquina. Antes eram 7.2.2-arch1-1 e 7.2.2-1-cachyos
# cravados aqui; no Arch/CachyOS o kernel sobe de versao toda semana e os
# dois sumiram, deixando o teste a cobrar builds para kernels que nao
# existiam mais. Ver armadilha 22.
#
# "dkms build" precisa apenas de headers, nao de kernel bootavel, entao o
# criterio aqui e a presenca de build/ -- diferente do instalador, que so
# instala onde o modulo pode ser carregado.
mapfile -t KERNELS < <(
  for b in /lib/modules/*/build; do
    [ -d "$b" ] && basename "$(dirname "$b")"
  done | sort
)

# Zero kernels com headers nao e aprovacao: e teste sem alvo.
if [ "${#KERNELS[@]}" -eq 0 ]; then
  echo "  ERRO alvo ausente: nenhum kernel com headers em /lib/modules"
  exit 3
fi

for k in "${KERNELS[@]}"; do
  if dkms build -m nexus_sense -v "$VER_TESTE" -k "$k" >/dev/null 2>&1; then
    printf '  OK   dkms build %s\n' "$k"
  else
    printf '  FALHA dkms build %s\n' "$k"
    fail=1
  fi
done

exit $fail
