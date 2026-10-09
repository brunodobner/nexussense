#!/bin/bash
# detect_desktop_user tem de devolver a PESSOA na frente da maquina.
#
# O instalador roda como root e precisa saber de quem e o desktop: e essa
# conta que entra no grupo nexus_sense e e no home dela que o atalho do
# botao N e escrito. Ate 2026-10-09 a funcao so conhecia SUDO_USER; sob
# pkexec -- que e como este projeto pede root -- ela caia no loginctl e
# devolvia o primeiro usuario que nao fosse "root" nem "gdm". Com sddm ou
# lightdm o primeiro da lista e a conta do greeter.
#
# O ensaio troca as fontes de informacao por funcoes: nada aqui depende de
# quem esta logado, e ele roda igual como root.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ_TESTE="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ_TESTE/setup.sh"
falhas=0

[ -e "$S" ] || { echo "ERRO: alvo ausente: $S"; exit 3; }

# Importar nao abre o menu: o setup.sh so chama main_menu quando executado.
# shellcheck source=/dev/null
source "$S"
declare -F detect_desktop_user > /dev/null || {
    echo "ERRO: alvo ausente: detect_desktop_user"; exit 3; }

# ─── o mundo de mentira ─────────────────────────────────────────────
# alice e bob sao pessoas; sddm e a conta do greeter.
id() {
    case "$*" in
        "-u root")   echo 0 ;;
        "-u sddm")   echo 964 ;;
        "-u alice")  echo 1001 ;;
        "-u bob")    echo 1002 ;;
        "-u nobody") echo 65534 ;;
        "-nu 0")     echo root ;;
        "-nu 964")   echo sddm ;;
        "-nu 1001")  echo alice ;;
        "-nu 1002")  echo bob ;;
        *) return 1 ;;
    esac
}

loginctl() { [ -n "$SESSOES" ] && printf '%s\n' "$SESSOES"; }

getent() {
    [ "$*" = "passwd" ] || return 2
    cat << 'EOL'
root:x:0:0::/root:/usr/bin/bash
sddm:x:964:964:SDDM Greeter Account:/var/lib/sddm:/usr/bin/nologin
nobody:x:65534:65534:Kernel Overflow User:/:/usr/bin/nologin
alice:x:1001:1001::/home/alice:/usr/bin/bash
bob:x:1002:1002::/home/bob:/usr/bin/bash
EOL
}

# O formato real, medido nesta maquina: SESSION UID USER SEAT LEADER ...
GREETER='c1 964 sddm seat0 880 greeter tty1 no -'
DO_BOB='3 1002 bob seat0 1009 user tty2 no -'
GREETER_E_BOB="$GREETER
$DO_BOB"

caso() {  # $1=descricao  $2=esperado  $3=sessoes  resto: VAR=valor
    local desc="$1" esperado="$2" obtido par
    SESSOES="$3"
    shift 3
    obtido=$(
        unset SUDO_USER PKEXEC_UID
        for par in "$@"; do export "${par?}"; done
        detect_desktop_user
    )
    if [ "$obtido" = "$esperado" ]; then
        echo "  OK   $desc: $obtido"
    else
        echo "  FALHA $desc: esperado '$esperado', veio '$obtido'"
        falhas=$((falhas + 1))
    fi
}

# ─── quem chamou ────────────────────────────────────────────────────
caso "sudo: vale SUDO_USER"              alice "$GREETER_E_BOB" SUDO_USER=alice
caso "pkexec: vale PKEXEC_UID"           alice "$GREETER_E_BOB" PKEXEC_UID=1001
caso "sudo dentro de pkexec"             alice "$GREETER_E_BOB" SUDO_USER=root PKEXEC_UID=1001

# ─── conta de sistema nunca e a resposta ────────────────────────────
caso "SUDO_USER de sistema e recusado"   bob   "$GREETER_E_BOB" SUDO_USER=sddm
caso "PKEXEC_UID de sistema e recusado"  bob   "$GREETER_E_BOB" PKEXEC_UID=964
caso "PKEXEC_UID do root e recusado"     bob   "$GREETER_E_BOB" PKEXEC_UID=0
caso "PKEXEC_UID que nao e numero"       bob   "$GREETER_E_BOB" PKEXEC_UID=sddm
caso "PKEXEC_UID sem conta"              bob   "$GREETER_E_BOB" PKEXEC_UID=4242

# ─── sem ninguem para perguntar ─────────────────────────────────────
caso "loginctl pula a sessao do greeter" bob   "$GREETER_E_BOB"
caso "so o greeter logado: cai no passwd" alice "$GREETER"
caso "nenhuma sessao: cai no passwd"     alice ""

# ─── o grupo: o instalador so diz o que fez ─────────────────────────
# Toda reinstalacao anunciava "Usuario adicionado ao grupo" e "o grupo so
# vale depois de relogar", com o usuario ja dentro: o usermod e a mensagem
# nao perguntavam antes. Quem le isso reloga sem precisar -- ou aprende a
# ignorar o aviso, que e pior no dia em que ele for verdade.
declare -F ensure_nexus_group > /dev/null || {
    echo "ERRO: alvo ausente: ensure_nexus_group"; exit 3; }

REGISTRO=$(mktemp)
trap 'rm -f "$REGISTRO"' EXIT

groupadd() { echo "groupadd $*" >> "$REGISTRO"; }
usermod()  { echo "usermod $*" >> "$REGISTRO"; }
getent()   { [ "$*" = "group nexus_sense" ] && [ "$GRUPO_EXISTE" = 1 ]; }
id() {
    [ "$*" = "-nG alice" ] || return 1
    [ "$NO_GRUPO" = 1 ] && echo "alice wheel nexus_sense" || echo "alice wheel"
}
detect_desktop_user() { echo "$USUARIO"; }

grupo() {  # $1=descricao  $2=GRUPO_EXISTE  $3=NO_GRUPO  $4=USUARIO  $5=comandos esperados
    local desc="$1" feito
    GRUPO_EXISTE="$2"; NO_GRUPO="$3"; USUARIO="$4"
    : > "$REGISTRO"
    SAIDA=$(ensure_nexus_group 2>&1)
    feito=$(tr '\n' ';' < "$REGISTRO")
    if [ "$feito" = "$5" ]; then
        echo "  OK   $desc: ${feito:-nenhum comando}"
    else
        echo "  FALHA $desc: esperado '$5', rodou '$feito'"
        falhas=$((falhas + 1))
    fi
}

diz() {  # $1=sim|nao  $2=padrao  -- sobre a SAIDA do ultimo grupo()
    if printf '%s' "$SAIDA" | grep -q -- "$2"; then tem=sim; else tem=nao; fi
    if [ "$tem" = "$1" ]; then
        echo "  OK   ... e $([ "$1" = sim ] && echo diz || echo "nao diz") '$2'"
    else
        echo "  FALHA ... e $([ "$1" = sim ] && echo "nao diz" || echo diz) '$2'"
        falhas=$((falhas + 1))
    fi
}

grupo "usuario ja no grupo" 1 1 alice ""
diz sim 'já está no grupo'
diz nao 'adicionado'
diz nao 'relogar'

grupo "usuario fora do grupo" 1 0 alice "usermod -aG nexus_sense alice;"
diz sim 'adicionado'
diz sim 'relogar'
diz sim 'ventoinhas e o perfil'

grupo "grupo ausente" 0 0 alice "groupadd -r nexus_sense;usermod -aG nexus_sense alice;"
diz sim 'criado'
diz sim 'relogar'
diz sim 'ventoinhas e o perfil'

grupo "sem usuario de desktop" 1 0 "" ""
diz nao 'adicionado'

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: detect_desktop_user devolve uma pessoa, e o grupo so anuncia o que mudou"
exit 0
