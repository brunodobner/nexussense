#!/bin/bash
# A unit do agente: endurecida, mas nao a ponto de se impedir de
# trabalhar.
#
# O defeito que este teste guarda apareceu na virada: com
# ProtectHome=read-only e sem excecao, o agente nao gravava o perfil da
# tomada, e depois de um reinicio nao havia para onde voltar.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
U="$RAIZ/packaging/systemd/nexus-sense-agent.service"
falhas=0

[ -e "$U" ] || { echo "ERRO: alvo ausente: $U"; exit 3; }

confere() {  # $1=descricao  $2=padrao
    if grep -q -- "$2" "$U"; then
        echo "  OK   $1"
    else
        echo "  FALHA $1"
        falhas=$((falhas + 1))
    fi
}

confere "protege o home"                 '^ProtectHome=read-only'
confere "protege o sistema"              '^ProtectSystem=strict'
confere "abre o config para escrita"     '^ReadWritePaths=.*\.config'
confere "e servico de usuario"           'graphical-session.target'

# O guarda da ventoinha (docs/plano-curva.md, secao 8). Type=notify sem o
# agente avisar faria o systemd matar o agente na partida; o aviso esta
# provado em tests/python/test_guarda.py.
confere "avisa o systemd que subiu"      '^Type=notify$'
confere "tem watchdog"                   '^WatchdogSec=[0-9]'
confere "o watchdog mata sem core dump"  '^WatchdogSignal=SIGKILL$'
confere "chama o guarda ao parar"        '^ExecStopPost=/usr/lib/nexus-sense/guarda-ventoinha.sh$'
confere "da ao guarda onde registrar"    '^RuntimeDirectory=nexus-sense$'
G="$RAIZ/packaging/scripts/guarda-ventoinha.sh"
if [ -x "$G" ]; then
    echo "  OK   o guarda existe e e executavel"
else
    echo "  FALHA o guarda $G nao existe ou nao e executavel"
    falhas=$((falhas + 1))
fi
# O watchdog tem de ficar acima de uma passada do agente, com folga: com
# menos, o systemd mataria um agente sadio.
w=$(sed -n 's/^WatchdogSec=\([0-9]*\)$/\1/p' "$U")
p=$(grep -oP '^DEFAULT_INTERVAL = \K[0-9.]+' "$RAIZ/src/nexus_sense/agent.py")
if [ -n "$w" ] && [ -n "$p" ] && awk -v w="$w" -v p="$p" 'BEGIN { exit !(w >= 2 * p) }'; then
    echo "  OK   WatchdogSec ($w s) e pelo menos duas passadas ($p s)"
else
    echo "  FALHA WatchdogSec '$w' contra a passada de '$p' s"
    falhas=$((falhas + 1))
fi

# O par que importa: proteger sem excecao trancaria o proprio agente.
if grep -q '^ProtectHome=read-only' "$U" && ! grep -q '^ReadWritePaths=' "$U"; then
    echo "  FALHA ProtectHome sem ReadWritePaths: o agente nao grava a configuracao"
    falhas=$((falhas + 1))
fi

if command -v systemd-analyze > /dev/null 2>&1; then
    # Verificada uma copia que aponta o guarda para o do repositorio: o de
    # /usr/lib so existe depois de instalar. So contam as linhas desta unit
    # -- o verify le tambem a configuracao de quem roda, e reclama dela --, e
    # em ingles, para o grep achar o que procura (armadilha 28).
    V=$(mktemp -d)
    sed "s|/usr/lib/nexus-sense/guarda-ventoinha.sh|$G|" "$U" > "$V/nexus-sense-agent.service"
    queixa=$(LC_ALL=C systemd-analyze verify --user "$V/nexus-sense-agent.service" 2>&1 \
        | grep 'nexus-sense-agent' | grep -iE 'error|invalid|not executable|unknown')
    rm -rf "$V"
    if [ -n "$queixa" ]; then
        echo "  FALHA systemd-analyze reclamou da unit: $queixa"
        falhas=$((falhas + 1))
    else
        echo "  OK   systemd-analyze aceita a unit"
    fi
else
    echo "  --   systemd-analyze ausente, sintaxe nao verificada"
fi

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: a unit do agente esta endurecida e consegue trabalhar"
exit 0
