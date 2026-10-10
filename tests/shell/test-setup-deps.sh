#!/bin/bash
# Verifica que install_build_deps cobre headers de kernel e dkms em todas
# as familias de distro, sem executar nenhuma instalacao.
set -u

# Localiza os alvos a partir da raiz do repositorio: estes testes vivem
# fora de driver/, para sobreviverem a sobrescrita da pasta na proxima
# release do upstream -- que e exatamente quando eles sao mais necessarios.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

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

checar 'pacman.*\$headers'             'Arch instala os headers derivados do pkgbase'
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

# O "linux-headers" generico so serve a quem roda o kernel "linux". Numa
# maquina so com linux-cachyos ele instala headers de um kernel que nao
# existe -- o diretorio so-headers da armadilha 22b -- e deixa sem headers
# o kernel que da boot.
if printf '%s' "$trecho" | grep -v '^\s*#' | grep -qE 'pacman.* linux-headers( |$)'; then
  echo "  FALHA Arch ainda pede o linux-headers generico"; fail=1
else
  echo "  OK   Arch nao pede o linux-headers generico"
fi

# A derivacao, sobre uma arvore plantada: nada aqui depende dos kernels
# desta maquina (armadilha 22a).
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
planta() {  # $1=versao  $2=pkgbase ou ""  $3=vmlinuz sim|nao
  mkdir -p "$T/$1/build"
  [ -n "$2" ] && echo "$2" > "$T/$1/pkgbase"
  [ "$3" = sim ] && : > "$T/$1/vmlinuz"
}
planta 7.0.1-1-cachyos      linux-cachyos sim
planta 7.0.2-1-cachyos      linux-cachyos sim   # o mesmo pacote, a meio de uma atualizacao
planta 6.18.9-1-lts         linux-lts     sim
planta 7.0.0-arch1-1        ""            nao   # so headers: nao da boot
planta 6.12.1-zen1-1        linux-zen     nao   # resto de kernel removido

obtido=$(bash -c "source '$S'; arch_header_packages '$T'" 2>&1 | tr '\n' ' ')
if [ "$obtido" = "linux-cachyos-headers linux-lts-headers " ]; then
  echo "  OK   headers pelo pkgbase de cada kernel bootavel: $obtido"
else
  echo "  FALHA headers derivados errados: '$obtido'"; fail=1
fi

# E nesta maquina, quando e Arch: o nome derivado tem de ser pacote de
# verdade. "pacman -Si" consulta o banco local, sem root e sem rede.
if command -v pacman > /dev/null 2>&1 && ls /lib/modules/*/pkgbase > /dev/null 2>&1; then
  reais=$(bash -c "source '$S'; arch_header_packages" 2>/dev/null)
  if [ -z "$reais" ]; then
    echo "  FALHA nenhum pacote de headers derivado dos kernels desta maquina"; fail=1
  fi
  for pkg in $reais; do
    if pacman -Si "$pkg" > /dev/null 2>&1; then
      echo "  OK   $pkg existe no repositorio"
    else
      echo "  FALHA $pkg nao e um pacote conhecido do pacman"; fail=1
    fi
  done
else
  echo "  PULADO sem pacman ou sem pkgbase: derivacao so conferida na arvore plantada"
fi

# nvidia-settings saiu: o PowerMizer fala com a NVML direto desde
# 2026-09-07 e nada mais no codigo chama o binario.
if printf '%s' "$runtime" | grep -v '^\s*#' | grep -q 'nvidia-settings'; then
  echo "  FALHA o instalador ainda exige nvidia-settings"; fail=1
else
  echo "  OK   o instalador nao exige nvidia-settings"
fi

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
