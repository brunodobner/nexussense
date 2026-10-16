#!/bin/bash
# Verifica que o instalador coloca o Nexus Sense no lugar certo.
#
# Como o resto da suite, este teste le o fonte do instalador em vez de
# rodar a instalacao: rodar exigiria root e mudaria a maquina. O que ele
# garante e que a proxima release do upstream, ao sobrescrever setup.sh,
# nao leve embora o que foi acrescentado.
#
# Nao ha helper nem regra polkit a verificar: a acao que os justificava
# foi cancelada, e o projeto nao tem mais codigo rodando como root.
# Ver docs/INTERFACE.md secao 6.1.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/setup.sh"
falhas=0

exigir() {
    [ -e "$1" ] || { echo "ERRO: alvo ausente: $1"; exit 3; }
}

exigir "$S"
exigir "$RAIZ/packaging/desktop/nexus-sense.desktop"
exigir "$RAIZ/packaging/systemd/nexus-sense-agent.service"
exigir "$RAIZ/packaging/udev/60-nexus-sense.rules"
exigir "$RAIZ/packaging/scripts/apply-perms.sh"
exigir "$RAIZ/packaging/scripts/guarda-ventoinha.sh"

confere() {  # $1=descricao  $2=padrao
    if grep -q -- "$2" "$S"; then
        echo "  OK   $1"
    else
        echo "  FALHA $1"
        falhas=$((falhas + 1))
    fi
}

confere "tem a funcao de instalacao"        '^install_nexus_sense() {'
confere "chamada em perform_install"        'install_nexus_sense'
confere "instala dependencias da interface" 'install_runtime_deps'
confere "pode importar sem abrir o menu"      'BASH_SOURCE\[0\].*==.*\$0'
confere "instala o pacote Python"           '/usr/lib/nexus-sense'
confere "instala o guarda da ventoinha"     'install -m 755 .*guarda-ventoinha\.sh.* /usr/lib/nexus-sense/guarda-ventoinha\.sh$'
confere "instala o lancador da GUI"         '/usr/bin/nexus-sense'
confere "instala o lancador do agente"      'nexus-sense-agent'
confere "instala o lancador do desktop"     'nexus-sense.desktop'
confere "instala a regra udev"              '60-nexus-sense.rules'
confere "instala a unit de usuario"         'systemd/user'
confere "cria o grupo"                      'groupadd'
confere "avisa sobre a permissao nova"      'ventoinhas e o perfil'
confere "recarrega o udev"                  'udevadm control'
confere "remove variantes antigas do tray"  "status/nexus-sense-tray\*"
confere "instala controle do perfil da CPU" 'power-profiles-daemon'

# A unit do agente e carregada pelo systemd de cada USUARIO; o
# "systemctl daemon-reload" do root nao chega nele. A execucao disto esta
# em test-desinstalacao-namespace.sh.
if sed -n '/^install_nexus_sense() {/,/^}/p' "$S" | grep -v '^\s*#' \
     | grep -qE '^\s*each_user_manager daemon-reload\s*$'; then
    echo "  OK   recarrega o systemd de cada usuario"
else
    echo "  FALHA nao recarrega o systemd de cada usuario"
    falhas=$((falhas + 1))
fi

# Nenhum arquivo privilegiado deve reaparecer sem decisao: se alguem
# ressuscitar o helper, este teste acusa.
#
# Le o codigo, nao os comentarios: detect_desktop_user consulta PKEXEC_UID
# para saber quem chamou, e o comentario que explica isso cita o pkexec
# sem que o instalador o execute.
if grep -v '^\s*#' "$S" | grep -q 'pkexec\|polkit-1/actions'; then
    echo "  FALHA o instalador voltou a mexer com polkit/pkexec"
    falhas=$((falhas + 1))
else
    echo "  OK   nao instala nada privilegiado"
fi

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: o instalador coloca o Nexus Sense no lugar"
exit 0
