#!/bin/bash
# O aviso de DKMS: gancho do pacman que grita quando o modulo nao foi
# construido para um kernel novo.
#
# O defeito que este teste guarda: com 'blacklist acer_wmi' no lugar, uma
# falha de construcao deixa o boot seguinte sem driver Acer nenhum, e a
# mensagem do DKMS se perde no meio de uma atualizacao grande.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/packaging/scripts/verificar-dkms.sh"
H="$RAIZ/packaging/pacman/90-nexus-sense-dkms-check.hook"
I="$RAIZ/setup.sh"
falhas=0

for alvo in "$S" "$H" "$I"; do
  [ -f "$alvo" ] || { echo "ERRO alvo ausente: $alvo"; exit 3; }
done

# --- o script roda, e roda em sh puro (o gancho nao garante bash)
if sh -n "$S" 2>/dev/null; then
  echo "  OK   verificar-dkms.sh passa no sh -n"
else
  echo "  FALHA verificar-dkms.sh tem erro de sintaxe em sh"; falhas=$((falhas + 1))
fi

[ -x "$S" ] && echo "  OK   verificar-dkms.sh e executavel" \
            || { echo "  FALHA verificar-dkms.sh sem bit de execucao"; falhas=$((falhas + 1)); }

# --- nunca derruba a transacao do pacman
if grep -q '^exit 0' "$S" && ! grep -qE '^\s*(set -e|exit [1-9])' "$S"; then
  echo "  OK   o script sai 0 e nao aborta a atualizacao"
else
  echo "  FALHA o script pode falhar a transacao do pacman"; falhas=$((falhas + 1))
fi

# --- armadilha 6: 'dkms status' sai 0 ate para pacote inexistente
if grep -q 'grep -q installed' "$S"; then
  echo "  OK   procura a palavra 'installed', nao o codigo de saida"
else
  echo "  FALHA confia no exit code do dkms status (armadilha 6)"; falhas=$((falhas + 1))
fi

# --- armadilha 22: nenhuma versao de kernel cravada
if grep -qE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-cachyos' "$S"; then
  echo "  FALHA versao de kernel cravada no script (armadilha 22)"; falhas=$((falhas + 1))
else
  echo "  OK   nenhuma versao de kernel cravada"
fi

# --- vmlinuz como discriminador de kernel bootavel
if grep -q 'vmlinuz' "$S"; then
  echo "  OK   usa vmlinuz para separar kernel bootavel de headers orfaos"
else
  echo "  FALHA sem vmlinuz: contaria headers sem kernel"; falhas=$((falhas + 1))
fi

# --- o socorro precisa estar na mensagem, nao so na documentacao
if grep -q 'blacklist-acer_wmi.conf' "$S"; then
  echo "  OK   a mensagem carrega a linha do socorro"
else
  echo "  FALHA o aviso nao diz como recuperar a maquina"; falhas=$((falhas + 1))
fi

# --- o gancho roda DEPOIS dos do DKMS (pacman ordena por nome)
nome=$(basename "$H")
if [ "${nome%%-*}" -gt 70 ] 2>/dev/null; then
  echo "  OK   ${nome} roda depois dos ganchos 70-dkms-*"
else
  echo "  FALHA ${nome} pode rodar antes do DKMS reconstruir"; falhas=$((falhas + 1))
fi

# --- o gancho dispara em kernel, e depois da transacao
grep -q 'Target *= *usr/lib/modules/\*/vmlinuz' "$H" \
  && echo "  OK   dispara em instalacao de kernel" \
  || { echo "  FALHA gatilho do gancho nao e o kernel"; falhas=$((falhas + 1)); }
grep -q 'When *= *PostTransaction' "$H" \
  && echo "  OK   roda depois da transacao" \
  || { echo "  FALHA o gancho nao e PostTransaction"; falhas=$((falhas + 1)); }
grep -q 'Exec *= */usr/lib/nexus-sense/verificar-dkms.sh' "$H" \
  && echo "  OK   aponta para o caminho instalado" \
  || { echo "  FALHA o Exec do gancho nao bate com o caminho instalado"; falhas=$((falhas + 1)); }

# --- o instalador instala E o desinstalador remove
grep -q 'install_dkms_check_hook' "$I" \
  && echo "  OK   setup.sh tem a funcao de instalacao" \
  || { echo "  FALHA setup.sh nao instala o gancho"; falhas=$((falhas + 1)); }
grep -q 'install_dkms_check_hook' <(sed -n '/^install_drivers()/,/^}/p' "$I") \
  && echo "  OK   install_drivers chama a funcao" \
  || { echo "  FALHA a funcao existe mas ninguem a chama"; falhas=$((falhas + 1)); }
grep -q 'rm -f /etc/pacman.d/hooks/90-nexus-sense-dkms-check.hook' "$I" \
  && echo "  OK   a limpeza remove o gancho" \
  || { echo "  FALHA desinstalar deixaria o gancho orfao"; falhas=$((falhas + 1)); }
grep -q 'rm -f /usr/lib/nexus-sense/verificar-dkms.sh' "$I" \
  && echo "  OK   a limpeza remove o script" \
  || { echo "  FALHA desinstalar deixaria o script orfao"; falhas=$((falhas + 1)); }

# --- so no Arch: o instalador atende varias distros
grep -q 'command -v pacman' <(sed -n '/^install_dkms_check_hook()/,/^}/p' "$I") \
  && echo "  OK   nao instala onde nao ha pacman" \
  || { echo "  FALHA instalaria gancho de pacman em distro sem pacman"; falhas=$((falhas + 1)); }

# --- o caminho do AVISO, exercitado de verdade
#
# Os greps acima provam forma; este prova comportamento. Um dkms falso
# diz que o pacote existe mas nao esta construido para kernel nenhum, e o
# script tem de gritar -- com o kernel citado, o comando de diagnostico e
# a linha do socorro -- e ainda assim sair 0.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/dkms" <<'FALSO'
#!/bin/sh
case "$*" in
  "status nexus_sense") echo "nexus_sense/9.9.9, fake-kernel, x86_64: installed"; exit 0 ;;
  *) exit 0 ;;
esac
FALSO
chmod +x "$tmp/dkms"

saida=$(PATH="$tmp:$PATH" sh "$S" 2>&1); st=$?

[ "$st" -eq 0 ] \
  && echo "  OK   sai 0 mesmo quando ha kernel faltando" \
  || { echo "  FALHA saiu $st com kernel faltando: derrubaria o pacman"; falhas=$((falhas + 1)); }

printf '%s' "$saida" | grep -q "ATENCAO" \
  && echo "  OK   grita quando o modulo nao foi construido" \
  || { echo "  FALHA nao avisou com kernel faltando (teste por vacuo?)"; falhas=$((falhas + 1)); }

printf '%s' "$saida" | grep -q "dkms install -m nexus_sense -v 9.9.9" \
  && echo "  OK   o diagnostico usa a versao real, nao uma cravada" \
  || { echo "  FALHA o comando de diagnostico nao leva a versao detectada"; falhas=$((falhas + 1)); }

printf '%s' "$saida" | grep -q "rm /etc/modprobe.d/blacklist-acer_wmi.conf" \
  && echo "  OK   o aviso entrega a linha do socorro" \
  || { echo "  FALHA o aviso nao diz como recuperar"; falhas=$((falhas + 1)); }

# E o contrario: com tudo construido, nao pode gritar.
cat > "$tmp/dkms" <<'FALSO'
#!/bin/sh
case "$*" in
  "status nexus_sense") echo "nexus_sense/9.9.9, fake, x86_64: installed"; exit 0 ;;
  *) echo "nexus_sense/9.9.9: installed"; exit 0 ;;
esac
FALSO
chmod +x "$tmp/dkms"
if PATH="$tmp:$PATH" sh "$S" 2>&1 | grep -q "ATENCAO"; then
  echo "  FALHA gritou com tudo construido: alarme falso"; falhas=$((falhas + 1))
else
  echo "  OK   fica quieto quando esta tudo construido"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "  aviso de DKMS: tudo certo"; exit 0
else echo "  aviso de DKMS: $falhas falha(s)"; exit 1; fi
