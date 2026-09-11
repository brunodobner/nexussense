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

# O par que importa: proteger sem excecao trancaria o proprio agente.
if grep -q '^ProtectHome=read-only' "$U" && ! grep -q '^ReadWritePaths=' "$U"; then
    echo "  FALHA ProtectHome sem ReadWritePaths: o agente nao grava a configuracao"
    falhas=$((falhas + 1))
fi

if command -v systemd-analyze > /dev/null 2>&1; then
    if systemd-analyze verify --user "$U" 2>&1 | grep -qi 'error\|invalid'; then
        echo "  FALHA systemd-analyze reclamou da unit"
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
