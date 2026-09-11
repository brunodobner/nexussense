#!/bin/bash
# Verifica que install_build_deps cobre headers de kernel e dkms em todas
# as familias de distro, sem executar nenhuma instalacao.
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
S="$ROOT/setup.sh"
exigir "$S"
fail=0

trecho=$(sed -n '/^install_build_deps() {/,/^}/p' "$S")
runtime=$(sed -n '/^runtime_dependencies_ok() {/,/^# Report/p' "$S")

checar() {
  local padrao="$1" descricao="$2"
  if printf '%s' "$trecho" | grep -qE "$padrao"; then
    printf '  OK   %s\n' "$descricao"
  else
    printf '  FALHA %s (padrao: %s)\n' "$descricao" "$padrao"
    fail=1
  fi
}

checar 'linux-headers'                 'Arch instala linux-headers'
checar 'linux-headers-\$\(uname -r\)'  'Debian instala headers do kernel corrente'
checar 'kernel-devel'                  'Fedora/openSUSE instalam kernel-devel'
checar 'pacman.*dkms'                  'Arch instala dkms'
checar 'apt-get.*dkms'                 'Debian instala dkms'
checar 'dnf.*dkms'                     'Fedora instala dkms'
checar 'zypper.*dkms'                  'openSUSE instala dkms'

checar_runtime() {
  local padrao="$1" descricao="$2"
  if printf '%s' "$runtime" | grep -qE "$padrao"; then
    printf '  OK   %s\n' "$descricao"
  else
    printf '  FALHA %s (padrao: %s)\n' "$descricao" "$padrao"
    fail=1
  fi
}

checar_runtime 'pacman.*pyside6.*python-dbus.*python-tomli-w' 'Arch instala dependencias da interface'
checar_runtime 'python3-pyside6.qtwidgets.*python3-pyside6.qtdbus' 'Debian instala modulos PySide6 usados'
checar_runtime 'dnf.*python3-pyside6.*python3-dbus' 'Fedora instala dependencias da interface'
checar_runtime 'zypper.*python3-PySide6.*python3-dbus-python' 'openSUSE instala dependencias da interface'
checar_runtime 'import PySide6, dbus, tomli_w' 'instalador verifica imports depois da instalacao'

if grep -q '^check_kernel_headers() {' "$S"; then
  echo "  OK   check_kernel_headers existe"
else
  echo "  FALHA check_kernel_headers ausente"
  fail=1
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S error "$S" >/dev/null 2>&1; then
    echo "  OK   shellcheck sem erros"
  else
    echo "  FALHA shellcheck reportou erro"; fail=1
  fi
else
  echo "  PULADO shellcheck nao instalado"
fi

exit $fail
