#!/bin/bash
# A desinstalacao, EXECUTADA -- num namespace, sobre uma copia de /etc/group.
#
# uninstall e comprehensive_cleanup nao se rodam numa maquina de uso para
# conferir coisa alguma: apagar e recriar o grupo troca o gid, e a sessao
# aberta perde a escrita nos atributos ate relogar (armadilha 29). Por isso
# a fiacao da desinstalacao so tinha prova estatica -- um grep dizendo que
# uninstall cita cleanup_nexus_group.
#
# Aqui as duas funcoes rodam de verdade, e nao alcancam nada:
#   - namespace de usuario, de PID, de rede e de IPC (bwrap --unshare-all):
#     o "root" de dentro e quem roda o teste, so enxerga os processos que o
#     teste criou e nao acha socket de barramento nenhum;
#   - a raiz inteira montada somente-leitura, /run vazio, e um /etc proprio
#     com a copia de /etc/group e um gshadow sintetico;
#   - PATH so com o que o teste poe: systemctl, runuser, dkms, modprobe e
#     companhia sao dublês que anotam a chamada.
# O que as duas escrevem de verdade e o /etc de mentira e os processos-isca.
#
# De carona, install_nexus_sense roda no mesmo cercado: e a unica forma de
# executar a fiacao dela -- quem ela avisa, e que nao mexe no grupo nem nos
# processos -- sem reinstalar a maquina de quem testa.
#
# Como root este teste PULA: sem privilegio, um erro neste roteiro nao tem
# como desinstalar nada; com privilegio, a montagem somente-leitura seria a
# unica barreira.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente   1 falhou
set -u

RAIZ_TESTE="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ_TESTE/setup.sh"
falhas=0

[ -e "$S" ] || { echo "ERRO: alvo ausente: $S"; exit 3; }
[ -x /usr/bin/python3 ] || { echo "ERRO: alvo ausente: /usr/bin/python3"; exit 3; }

if [ "$(id -u)" -eq 0 ]; then
    echo "PULOU: como root um erro neste roteiro desinstalaria de verdade; ele roda sem root"
    exit 2
fi
if ! command -v bwrap > /dev/null 2>&1; then
    echo "PULOU: sem bwrap nao ha namespace onde rodar a desinstalacao"
    exit 2
fi
if ! bwrap --unshare-all --uid 0 --gid 0 --ro-bind / / true 2> /dev/null; then
    echo "PULOU: esta maquina nao deixa criar namespace de usuario"
    exit 2
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# ─── a maquina de verdade, antes ────────────────────────────────────
# Lida de novo no fim: o que este teste promete e nao tocar em nada disto.
INSTALADO="/usr/bin/nexus-sense /usr/bin/nexus-sense-agent /usr/lib/nexus-sense
/usr/lib/systemd/user/nexus-sense-agent.service /etc/udev/rules.d/60-nexus-sense.rules
/etc/xdg/autostart/nexus-sense-autostart.desktop /etc/modules-load.d/nexus_sense.conf
/etc/modprobe.d/blacklist-acer_wmi.conf /etc/group"
retrato() {
    getent group nexus_sense
    bash -c "source '$S'; nexus_sense_pids" 2> /dev/null | sort -n | tr '\n' ' '
    echo
    # shellcheck disable=SC2086
    stat -c '%n %i %Y %s' $INSTALADO 2>&1
}
ANTES=$(retrato)

# ─── o PATH de dentro ───────────────────────────────────────────────
BIN="$T/bin"
mkdir -p "$BIN"
for c in bash cat sort grep awk sed tr cut basename dirname rm find getent groupdel id env sleep mkdir \
         install cp chmod; do
    real=$(command -v "$c") || { echo "ERRO: alvo ausente: $c"; exit 3; }
    ln -s "$real" "$BIN/$c"
done
duble() {  # $1=nome  $2=corpo; toda chamada fica em $CHAMADAS
    printf '#!%s\necho "%s $*" >> "$CHAMADAS"\n%s\n' "$BIN/bash" "$1" "$2" > "$BIN/$1"
    chmod +x "$BIN/$1"
}
# is-active e is-enabled dizem "nao": nada esta de pe aqui dentro.
duble systemctl 'case "$1" in is-active|is-enabled) exit 1 ;; esac'
for c in runuser loginctl udevadm depmod modprobe rmmod dkms make systemd-hwdb \
         update-desktop-database gtk-update-icon-cache groupadd usermod; do
    duble "$c" ''
done
# As dependencias de execucao, dadas por satisfeitas: o ensaio e da fiacao
# de install_nexus_sense, e nenhum gerenciador de pacotes entra no PATH.
duble python3 ''
duble busctl 'echo "org.freedesktop.UPower.PowerProfiles - - - (activatable) - - -"'

# ─── o /etc de dentro ───────────────────────────────────────────────
BASE="$T/etc.base"
mkdir -p "$BASE"
for f in group passwd nsswitch.conf login.defs; do
    [ -r "/etc/$f" ] && cp "/etc/$f" "$BASE/$f"
done
[ -s "$BASE/group" ] || { echo "ERRO: alvo ausente: /etc/group"; exit 3; }
# Onde o grupo nao existe o ensaio o cria na copia: o que se prova e a
# remocao, nao a instalacao desta maquina.
grep -q '^nexus_sense:' "$BASE/group" || echo 'nexus_sense:x:948:' >> "$BASE/group"
# O gshadow de verdade so o root le. O sintetico tem uma linha por grupo,
# como o de verdade, para o groupdel percorrer o mesmo caminho.
awk -F: '{ print $1 ":!::" $4 }' "$BASE/group" > "$BASE/gshadow"
chmod 600 "$BASE/gshadow"
LINHA=$(grep '^nexus_sense:' "$BASE/group")

# O que a limpeza tem de tirar, e dois vizinhos que tem de ficar.
SAEM="modules-load.d/nexus_sense.conf modprobe.d/blacklist-acer_wmi.conf
udev/rules.d/60-nexus-sense.rules xdg/autostart/nexus-sense-autostart.desktop
pacman.d/hooks/90-nexus-sense-dkms-check.hook systemd/system/nexus_sense.service
predator_state"
FICAM="udev/rules.d/99-de-outro.rules modprobe.d/de-outro.conf"
for f in $SAEM $FICAM; do
    mkdir -p "$BASE/$(dirname "$f")"
    echo plantado > "$BASE/$f"
done

# ─── os processos-isca ──────────────────────────────────────────────
# Modulos de mentira com os nomes de verdade: com o PYTHONPATH apontando
# para ca, "/usr/bin/python3 -P -m nexus_sense" tem o argv exato do
# lancador instalado e nao roda uma linha do aplicativo.
mkdir -p "$T/stub/nexus_sense/gui" "$T/stub/outro_modulo"
ISCA='import os, time
open(os.environ["PRONTO"], "w").close()
time.sleep(60)'
: > "$T/stub/nexus_sense/__init__.py"
: > "$T/stub/nexus_sense/gui/__init__.py"
printf '%s\n' "$ISCA" > "$T/stub/nexus_sense/__main__.py"
printf '%s\n' "$ISCA" > "$T/stub/nexus_sense/gui/app.py"
printf '%s\n' "$ISCA" > "$T/stub/outro_modulo/__main__.py"

UID_ALVO=$(id -u)
NOME_ALVO=$(id -un)

cat > "$T/dentro.sh" << 'EOL'
# Roda DENTRO do namespace. $1 = limpeza | desinstala | instala
modo="$1"
# shellcheck source=/dev/null
source "$S"

# Um usuario com gerenciador no ar: e por aqui que o agente e parado.
mkdir -p "/run/user/$UID_ALVO"

export PYTHONPATH="$T/stub"
PRONTO="$T/pronto.agente"  /usr/bin/python3 -P -m nexus_sense &
agente=$!
PRONTO="$T/pronto.bandeja" /usr/bin/python3 -P -m nexus_sense.gui.app --tray-only &
bandeja=$!
PRONTO="$T/pronto.outro"   /usr/bin/python3 -P -m outro_modulo &
outro=$!
# O shell cuja linha de comando CONTEM a do agente: a armadilha 10.
bash -c 'sleep 60; : /usr/bin/python3 -P -m nexus_sense' &
shell=$!
unset PYTHONPATH

# Entre o fork e o exec o filho ainda tem o argv do pai: so vale varrer
# depois que os tres disserem que subiram.
for ((i = 0; i < 100; i++)); do
    [ -e "$T/pronto.agente" ] && [ -e "$T/pronto.bandeja" ] && [ -e "$T/pronto.outro" ] && break
    sleep 0.1
done
[ "$i" -lt 100 ] || echo "as iscas nao subiram" >&2

case "$modo" in
    limpeza)    comprehensive_cleanup ;;
    desinstala) uninstall ;;
    instala)    install_nexus_sense ;;
esac > "$T/saida.$modo" 2>&1 < /dev/null
rc=$?

sleep 0.5
estado() {  # zumbi e processo morto: o pai aqui nao recolhe ninguem
    local st
    st=$(awk '{ print $3 }' "/proc/$1/stat" 2> /dev/null)
    case "$st" in ''|Z|X) echo morto ;; *) echo vivo ;; esac
}
{
    echo "rc=$rc"
    echo "visiveis=$(nexus_sense_pids | sort -n | tr '\n' ' ')"
    echo "agente=$(estado "$agente")"
    echo "bandeja=$(estado "$bandeja")"
    echo "outro=$(estado "$outro")"
    echo "shell=$(estado "$shell")"
    echo "grupo=$(getent group nexus_sense)"
} > "$T/resultado.$modo"
EOL

ensaio() {  # $1=modo -- cada um com o seu /etc e o seu registro
    cp -r "$BASE" "$T/etc.$1"
    if [ "$1" = instala ]; then
        local f
        for f in $SAEM; do rm -f "$T/etc.$1/$f"; done
    fi
    rm -f "$T"/pronto.*
    bwrap --unshare-all --uid 0 --gid 0 --die-with-parent \
          --ro-bind / / --dev /dev --proc /proc --tmpfs /run \
          --bind "$T/etc.$1" /etc --bind "$T" "$T" \
          --clearenv --setenv PATH "$BIN" --setenv HOME /nonexistent --setenv LC_ALL C \
          --setenv S "$S" --setenv T "$T" --setenv UID_ALVO "$UID_ALVO" \
          --setenv CHAMADAS "$T/chamadas.$1" \
          "$BIN/bash" "$T/dentro.sh" "$1" < /dev/null > "$T/bwrap.$1" 2>&1
}

campo() { sed -n "s/^$2=//p" "$T/resultado.$1" 2> /dev/null; }

confere() {  # $1=descricao  $2=esperado  $3=obtido
    if [ "$2" = "$3" ]; then
        echo "  OK   $1"
    else
        echo "  FALHA $1"
        echo "        esperado: $2"
        echo "        veio:     $3"
        falhas=$((falhas + 1))
    fi
}

sobram() {  # $1=modo -> os plantados que continuam no /etc daquele ensaio
    local f
    for f in $SAEM $FICAM; do
        [ -e "$T/etc.$1/$f" ] && printf '%s ' "$f"
    done
}

PARA_AGENTE="runuser -u $NOME_ALVO -- env XDG_RUNTIME_DIR=/run/user/$UID_ALVO systemctl --user stop nexus-sense-agent.service"

# ─── 1. a limpeza que antecede uma reinstalacao ─────────────────────
ensaio limpeza
[ -s "$T/resultado.limpeza" ] || {
    echo "ERRO: o ensaio da limpeza nao chegou ao fim:"; sed 's/^/    /' "$T/bwrap.limpeza"; exit 1; }

echo "A limpeza que antecede uma reinstalacao (comprehensive_cleanup):"
confere "o roteiro de dentro nao tropecou em nada" "" "$(cat "$T/bwrap.limpeza")"
confere "rodou ate o fim" 0 "$(campo limpeza rc)"
confere "tirou do /etc o que e do instalador, e so isso" "$(printf '%s ' $FICAM)" "$(sobram limpeza)"
confere "o grupo fica, com o mesmo gid" "$LINHA" "$(campo limpeza grupo)"
confere "/etc/group sai igual ao que entrou" "" "$(diff "$BASE/group" "$T/etc.limpeza/group")"
confere "agente segue rodando"  vivo "$(campo limpeza agente)"
confere "bandeja segue rodando" vivo "$(campo limpeza bandeja)"
if grep -qE 'systemctl --user stop|groupdel' "$T/chamadas.limpeza"; then
    echo "  FALHA mandou parar o agente ou apagar o grupo:"
    grep -E 'systemctl --user stop|groupdel' "$T/chamadas.limpeza" | sed 's/^/        /'
    falhas=$((falhas + 1))
else
    echo "  OK   nao mandou parar a unit do agente"
fi

# ─── 2. a desinstalacao ─────────────────────────────────────────────
ensaio desinstala
[ -s "$T/resultado.desinstala" ] || {
    echo "ERRO: o ensaio da desinstalacao nao chegou ao fim:"; sed 's/^/    /' "$T/bwrap.desinstala"; exit 1; }

echo "A desinstalacao (uninstall):"
confere "o roteiro de dentro nao tropecou em nada" "" "$(cat "$T/bwrap.desinstala")"
confere "rodou ate o fim" 0 "$(campo desinstala rc)"
grep -q 'uninstalled successfully' "$T/saida.desinstala" \
    && echo "  OK   anunciou o fim" \
    || { echo "  FALHA nao anunciou o fim"; falhas=$((falhas + 1)); }
confere "tirou do /etc o que e do instalador, e so isso" "$(printf '%s ' $FICAM)" "$(sobram desinstala)"

confere "o grupo saiu" "" "$(campo desinstala grupo)"
confere "/etc/group perdeu a linha do grupo, e so ela" "< $LINHA" \
    "$(diff "$BASE/group" "$T/etc.desinstala/group" | grep '^[<>]')"
confere "o gshadow perdeu a linha do grupo, e so ela" "< $(grep '^nexus_sense:' "$BASE/gshadow")" \
    "$(diff "$BASE/gshadow" "$T/etc.desinstala/gshadow" | grep '^[<>]')"

confere "agente encerrado"  morto "$(campo desinstala agente)"
confere "bandeja encerrada" morto "$(campo desinstala bandeja)"
confere "o processo de outro modulo segue rodando" vivo "$(campo desinstala outro)"
confere "o shell que cita o agente na linha de comando segue rodando" vivo "$(campo desinstala shell)"
confere "nenhum processo dos lancadores sobrou" "" "$(campo desinstala visiveis)"

# A unit e parada pelo gerenciador do usuario, e antes de a limpeza
# desabilita-la e apagar o arquivo.
parou=$(grep -nxF "$PARA_AGENTE" "$T/chamadas.desinstala" | cut -d: -f1 | head -1)
limpou=$(grep -nF 'systemctl --global disable nexus-sense-agent.service' "$T/chamadas.desinstala" | cut -d: -f1 | head -1)
if [ -n "$parou" ] && [ -n "$limpou" ] && [ "$parou" -lt "$limpou" ]; then
    echo "  OK   parou a unit do agente no gerenciador do usuario, antes da limpeza"
else
    echo "  FALHA a unit do agente nao foi parada antes da limpeza (parou: ${parou:-nunca}, limpou: ${limpou:-nunca})"
    sed 's/^/        /' "$T/chamadas.desinstala"
    falhas=$((falhas + 1))
fi

# ─── 3. a instalacao do aplicativo ──────────────────────────────────
# O /etc deste ensaio entra sem os arquivos plantados: quem os poe e ela.
ensaio instala
[ -s "$T/resultado.instala" ] || {
    echo "ERRO: o ensaio da instalacao nao chegou ao fim:"; sed 's/^/    /' "$T/bwrap.instala"; exit 1; }

echo "A instalacao do aplicativo (install_nexus_sense):"
confere "o roteiro de dentro nao tropecou em nada" "" "$(cat "$T/bwrap.instala")"
confere "rodou ate o fim" 0 "$(campo instala rc)"
for f in udev/rules.d/60-nexus-sense.rules xdg/autostart/nexus-sense-autostart.desktop; do
    case "$f" in
        udev/*) fonte="$RAIZ_TESTE/packaging/udev/$(basename "$f")" ;;
        *)      fonte="$RAIZ_TESTE/packaging/desktop/$(basename "$f")" ;;
    esac
    if cmp -s "$fonte" "$T/etc.instala/$f"; then
        echo "  OK   pos $f, identico ao do repositorio"
    else
        echo "  FALHA nao pos $f, ou pos diferente"; falhas=$((falhas + 1))
    fi
done

# O "systemctl daemon-reload" do instalador fala com o systemd do sistema.
# Quem carrega a unit do agente, e a que o gerador cria a partir do
# autostart, e o de cada usuario: sem aviso ele fica com a definicao antiga
# na memoria. Medido em 2026-10-10, depois da reinstalacao das 04:32:
# NeedDaemonReload=yes nas duas units, ate alguem recarregar ou relogar.
RECARREGA="runuser -u $NOME_ALVO -- env XDG_RUNTIME_DIR=/run/user/$UID_ALVO systemctl --user daemon-reload"
if grep -qxF "$RECARREGA" "$T/chamadas.instala"; then
    echo "  OK   recarrega o gerenciador de cada usuario com sessao"
else
    echo "  FALHA nao recarrega o gerenciador do usuario; chamadas ao systemctl:"
    grep -E 'systemctl' "$T/chamadas.instala" | sed 's/^/        /'
    falhas=$((falhas + 1))
fi

confere "o grupo fica, com o mesmo gid" "$LINHA" "$(campo instala grupo)"
confere "/etc/group sai igual ao que entrou" "" "$(diff "$BASE/group" "$T/etc.instala/group")"
if grep -qE '^(groupadd|groupdel) ' "$T/chamadas.instala"; then
    echo "  FALHA criou ou apagou grupo numa reinstalacao"; falhas=$((falhas + 1))
else
    echo "  OK   nao cria nem apaga grupo quando ele ja existe"
fi
confere "agente segue rodando"  vivo "$(campo instala agente)"
confere "bandeja segue rodando" vivo "$(campo instala bandeja)"
if grep -qE 'systemctl --user (stop|restart|kill)' "$T/chamadas.instala"; then
    echo "  FALHA parou algo na sessao do usuario"; falhas=$((falhas + 1))
else
    echo "  OK   nao para nada na sessao do usuario"
fi
# O que estava rodando sobe com o codigo novo: sem isto a bandeja de antes da
# instalacao seguia no ar e, em 2026-10-16, apagou o campo novo do config.
REINICIA="runuser -u $NOME_ALVO -- env XDG_RUNTIME_DIR=/run/user/$UID_ALVO systemctl --user try-restart nexus-sense-agent.service app-nexus\x2dsense\x2dautostart@autostart.service"
if grep -qxF "$REINICIA" "$T/chamadas.instala"; then
    echo "  OK   reinicia o agente e a bandeja que estiverem no ar, e so eles"
else
    echo "  FALHA nao reinicia o agente e a bandeja com try-restart; chamadas ao systemctl:"
    grep -E 'systemctl' "$T/chamadas.instala" | sed 's/^/        /'
    falhas=$((falhas + 1))
fi

# ─── 4. a maquina de verdade, depois ────────────────────────────────
confere "nada desta maquina foi tocado: grupo, processos e arquivos instalados" "$ANTES" "$(retrato)"

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: a desinstalacao remove o grupo e encerra o aplicativo; a reinstalacao preserva os dois"
exit 0
