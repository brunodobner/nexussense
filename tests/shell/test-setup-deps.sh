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

# ─── funcoes do instalador, rodadas com um PATH so de dublês ─────────
# O PATH do ensaio tem o que o teste poe la e mais nada. Um dublê que
# faltasse deixaria a funcao alcancar o binario de verdade -- o pacman, como
# root, no CI -- e um binario que "nao existe" tem de nao existir mesmo: o
# command -v do bash devolve ate arquivo nao executavel quando nao acha
# outro (armadilha 30).
BIN="$T/bin"
mkdir -p "$BIN"
for c in bash cat sort grep awk sed tr cut basename dirname; do
  real=$(command -v "$c") || { echo "  ERRO alvo ausente: $c"; exit 3; }
  ln -s "$real" "$BIN/$c"
done
CHAMADAS="$T/chamadas"

duble() {  # $1=nome  $2=corpo; toda chamada fica em $CHAMADAS
  printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$CHAMADAS" "$2" > "$BIN/$1"
  chmod +x "$BIN/$1"
}
sem() { rm -f "$BIN/$1"; }

roda() {  # roda "$1" dentro do setup.sh importado, so com os dublês
  : > "$CHAMADAS"
  PATH="$BIN" "$BIN/bash" -c "source '$S'; $1" > "$T/saida" 2>&1
}

espera() {  # $1=descricao  $2=codigo esperado  $3=o que rodar
  roda "$3"
  local rc=$?
  if [ "$rc" -eq "$2" ]; then
    echo "  OK   $1"
  else
    echo "  FALHA $1 (esperado $2, veio $rc)"; fail=1
  fi
}

# --- runtime_dependencies_ok pergunta pelo que o codigo usa
# O perfil de CPU sai por "busctl --system" para um nome no barramento
# (src/nexus_sense/ppd.py) desde a etapa 1. O instalador perguntava pelo
# powerprofilesctl, que ninguem chama mais: onde outro pacote fornece o
# mesmo nome (tuned-ppd), ele mandava instalar o que ja estava servido.
PPD="$ROOT/src/nexus_sense/ppd.py"
exigir "$PPD"
NOME=$(grep -oP '^SERVICE = "\K[^"]+' "$PPD")
[ -n "$NOME" ] || { echo "  ERRO alvo ausente: SERVICE em ppd.py"; exit 3; }

# O formato e o do busctl desta maquina: NAME PID PROCESS USER CONNECTION ...
OUTROS='org.freedesktop.Accounts - - - (activatable) - - -
org.freedesktop.UPower 827 upowerd root :1.17 upower.service - -
net.hadess.PowerProfiles 1450 power-profiles- root :1.41 power-profiles-daemon.service - -'
barramento() {  # $1=linhas que o "busctl list" devolve
  duble busctl "case \"\$*\" in *list*) cat << 'EOL'
$1
EOL
;; *) exit 1 ;; esac"
}

duble python3 'exit 0'
sem powerprofilesctl

barramento "$OUTROS
$NOME - - - (activatable) - - -"
espera "servico ativavel no barramento, sem powerprofilesctl: serve" 0 runtime_dependencies_ok
if grep -q '^busctl --system .*list' "$CHAMADAS" && ! grep -vE '^(python3|busctl --system .*list)' "$CHAMADAS" | grep -q .; then
  echo "  OK   ... e so listou os nomes: nao ativou o servico para perguntar"
else
  echo "  FALHA ... chamadas inesperadas: $(tr '\n' ';' < "$CHAMADAS")"; fail=1
fi

barramento "$OUTROS
$NOME 1450 power-profiles- root :1.41 power-profiles-daemon.service - -"
espera "servico com dono no barramento: serve" 0 runtime_dependencies_ok

# org.freedesktop.UPower e prefixo do nome procurado, e net.hadess e o
# nome legado, que o codigo nao usa: nenhum dos dois serve.
barramento "$OUTROS"
duble powerprofilesctl 'exit 0'
espera "powerprofilesctl instalado e o nome fora do barramento: nao serve" 1 runtime_dependencies_ok
sem powerprofilesctl

duble busctl 'exit 1'
espera "sem barramento de sistema: nao serve" 1 runtime_dependencies_ok

sem busctl
duble powerprofilesctl 'exit 0'
espera "sem busctl: nao serve, com ou sem powerprofilesctl" 1 runtime_dependencies_ok
sem powerprofilesctl

barramento "$NOME - - - (activatable) - - -"
duble python3 'exit 1'
espera "modulos Python faltando: nao serve" 1 runtime_dependencies_ok
duble python3 'exit 0'

if printf '%s' "$runtime" | grep -v '^\s*#' | grep -q 'command -v powerprofilesctl'; then
  echo "  FALHA o instalador ainda pergunta pelo powerprofilesctl"; fail=1
else
  echo "  OK   o instalador nao pergunta pelo powerprofilesctl"
fi

# --- os headers que faltam sao instalados mesmo com make e dkms presentes
# install_build_deps so rodava quando faltava uma das duas ferramentas. Com
# elas no lugar e um kernel sem headers, check_kernel_headers avisava e a
# instalacao seguia sem construir para ele. A 3.5 consertou QUAIS headers
# pedir; isto e o QUANDO.
H="$T/modulos"
kernel() {  # $1=versao  $2=vmlinuz sim|nao  $3=build sim|nao|pendurado
  mkdir -p "$H/$1"
  [ "$2" = sim ] && : > "$H/$1/vmlinuz"
  case "$3" in
    sim)       mkdir "$H/$1/build" ;;
    pendurado) ln -s "/usr/src/linux-headers-$1" "$H/$1/build" ;;  # o do Debian, sem o pacote
  esac
}
kernel 7.0.1-completo       sim sim
kernel 6.9.9-resto          nao nao
kernel 7.0.0-so-headers     nao sim

duble make 'exit 0'
duble dkms 'exit 0'

roda "kernels_missing_headers '$H'"
if [ ! -s "$T/saida" ]; then
  echo "  OK   kernel bootavel com headers, resto e so-headers: nada falta"
else
  echo "  FALHA acusou falta onde nao ha: $(tr '\n' ' ' < "$T/saida")"; fail=1
fi
espera "... e com make e dkms no lugar, nao ha o que instalar" 1 "build_deps_missing '$H'"

kernel 7.0.2-sem-headers    sim nao
kernel 6.1.0-debian         sim pendurado
roda "kernels_missing_headers '$H'"
obtido=$(tr '\n' ' ' < "$T/saida")
if [ "$obtido" = "6.1.0-debian 7.0.2-sem-headers " ]; then
  echo "  OK   kernels bootaveis sem headers: $obtido"
else
  echo "  FALHA kernels sem headers errados: '$obtido'"; fail=1
fi
espera "... e isso basta para instalar, com make e dkms no lugar" 0 "build_deps_missing '$H'"

rm -rf "$H/7.0.2-sem-headers" "$H/6.1.0-debian"
sem dkms
espera "sem dkms: ha o que instalar" 0 "build_deps_missing '$H'"
duble dkms 'exit 0'
sem make
espera "sem make: ha o que instalar" 0 "build_deps_missing '$H'"
duble make 'exit 0'

# A fiacao, executada: install_drivers com as ferramentas no lugar e um
# kernel sem headers tem de chamar install_build_deps. Tres travas param a
# funcao antes de ela tocar em qualquer coisa: check_kernel_headers devolve
# 1, driver_version devolve vazio, e o PATH so tem dublês.
cat > "$T/fiacao.sh" << EOL
source '$S'
pause()                { :; }
install_build_deps()   { echo install_build_deps >> '$T/passos'; return 1; }
check_kernel_headers() { echo check_kernel_headers >> '$T/passos'; return 1; }
driver_version()       { :; }
kernels_missing_headers() { [ "\$FALTA" = sim ] && echo 7.0.2-sem-headers; return 0; }
install_drivers < /dev/null > /dev/null 2>&1
EOL
fiacao() {  # $1=FALTA  -> os passos que install_drivers deu
  : > "$T/passos"
  FALTA="$1" PATH="$BIN" "$BIN/bash" "$T/fiacao.sh"
  tr '\n' ' ' < "$T/passos"
}
passos=$(fiacao sim)
if [ "$passos" = "install_build_deps " ]; then
  echo "  OK   install_drivers instala os headers que faltam"
else
  echo "  FALHA com headers faltando, install_drivers fez: '${passos}'"; fail=1
fi
passos=$(fiacao nao)
if [ "$passos" = "check_kernel_headers " ]; then
  echo "  OK   ... e nao chama o gerenciador de pacotes quando nada falta"
else
  echo "  FALHA sem nada faltando, install_drivers fez: '${passos}'"; fail=1
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
