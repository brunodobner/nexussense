#!/bin/bash
# Verifica o resultado da instalacao via DKMS: registro presente, modulo
# compilado para todos os kernels com headers, acer_wmi neutralizado e
# sysfs populado.
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
fail=0
S="$ROOT/setup.sh"
exigir "$S"
exigir "$DRV/src/nexus_sense.c"

VER=$(grep -oP '#define DRIVER_VERSION "\K[^"]+' \
      "$DRV/src/nexus_sense.c")
echo "  versao derivada do fonte: $VER"

if grep -q '^driver_version() {' "$S"; then
  echo "  OK   driver_version existe"
else
  echo "  FALHA driver_version ausente"; fail=1
fi

if sed -n '/^install_drivers() {/,/^}/p' "$S" | grep -qE '25\.701'; then
  echo "  FALHA versao cravada em install_drivers"; fail=1
else
  echo "  OK   nenhuma versao cravada em install_drivers"
fi

# "dkms status | grep -q" deixa "echo: write error: Broken pipe" na saida:
# o grep sai no primeiro acerto e o dkms, que imprime uma linha por kernel,
# escreve a seguinte num cano fechado. Visto no portao da etapa 2, como
# root. Quem le a saida inteira nao fecha o cano antes da hora.
ruidosos=$(grep -nE 'dkms status[^|#]*\| *grep -q' "$S" "$ROOT"/tests/shell/*.sh \
           "$ROOT"/packaging/scripts/*.sh 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*#')
if [ -z "$ruidosos" ]; then
  echo "  OK   nenhum dkms status lido por grep -q"
else
  echo "  FALHA grep -q fecha o cano na cara do dkms status:"
  printf '%s\n' "$ruidosos" | sed "s|$ROOT/||; s/^/        /"
  fail=1
fi

# Daqui para baixo o teste le o que a instalacao deixou NESTA maquina.
# Onde ela nunca rodou -- outra maquina, um CI -- nao ha o que conferir, e
# cobrar daria uma lista de falhas que nao e defeito de ninguem. Pula, e
# pular sai como PULOU no run-all.
#
# O criterio e RASTRO de instalacao, nao o estado dela: o fonte encenado
# ou o registro do DKMS. Com um dos dois no disco e o resto quebrado, o
# teste segue adiante e reprova -- que e o caso que ele existe para pegar.
if [ ! -d "/usr/src/nexus_sense-${VER}" ] && [ ! -d "/var/lib/dkms/nexus_sense/${VER}" ]; then
  echo "  PULOU conferencia da instalacao: nexus_sense/$VER nao esta instalado nesta maquina"
  [ "$fail" -eq 0 ] && exit 2 || exit 1
fi

if dkms status "nexus_sense/$VER" 2>/dev/null | grep installed > /dev/null; then
  echo "  OK   dkms registra nexus_sense/$VER como installed"
else
  echo "  FALHA dkms nao tem nexus_sense/$VER installed"; fail=1
fi

# So cobra o modulo onde ele pode ser CARREGADO.
#
# "tem headers" era o criterio antigo, e cobrava build para pacote
# linux-headers sem o linux correspondente -- comum no Arch, quando algo
# puxa os headers como dependencia. Esse diretorio tem build/ mas nao tem
# vmlinuz nem modules.dep: nao da boot, e o modulo ali nunca seria
# carregado. O teste ficava vermelho por um modulo que ninguem quer.
# Ver armadilha 22.
achou_bootavel=0
for kdir in /lib/modules/*/; do
  [ -d "$kdir" ] || continue
  kver=$(basename "$kdir")
  [ -d "/lib/modules/${kver}/build" ] || continue
  if [ ! -e "/lib/modules/${kver}/vmlinuz" ]; then
    printf '  NOTA %s tem headers sem kernel bootavel; nao se exige modulo\n' "$kver"
    continue
  fi
  achou_bootavel=1
  if dkms status "nexus_sense/$VER" -k "$kver" 2>/dev/null | grep installed > /dev/null; then
    printf '  OK   compilado para %s\n' "$kver"
  else
    printf '  FALHA nao compilado para %s\n' "$kver"; fail=1
  fi
done

# Nenhum kernel bootavel com headers seria um laco que nao asserta nada.
if [ "$achou_bootavel" -eq 0 ]; then
  echo "  ERRO alvo ausente: nenhum kernel bootavel com headers"
  exit 3
fi

# Discriminador. Sem ele o teste passaria com a instalacao ANTERIOR, que
# carrega a mesma versao 25.701 e ate a mesma string "Nitro ANV15-52"
# (a versao pessoal tambem adicionava o modelo, so que como nitro_v4).
# A prova de que o instalado e ESTE repositorio e o fonte encenado ser
# identico ao nosso, byte a byte.
if diff -r "$DRV/src" \
           "/usr/src/nexus_sense-${VER}/src" >/dev/null 2>&1; then
  echo "  OK   fonte encenado e identico ao do repositorio"
else
  echo "  FALHA fonte em /usr/src difere do repositorio -- instalacao antiga"
  fail=1
fi

# O -51 tem de continuar apontando para quirk_acer_nitro. A versao pessoal
# o reclassificava para nitro_v4; se isso reaparecer, o fonte nao e nosso.
if grep -A6 '"Acer Nitro ANV15-51"' \
     "/usr/src/nexus_sense-${VER}/src/nexus_sense.c" 2>/dev/null \
     | grep -q 'quirk_acer_nitro_v4'; then
  echo "  FALHA ANV15-51 reclassificado para nitro_v4 -- fonte antigo"
  fail=1
else
  echo "  OK   ANV15-51 aponta para quirk_acer_nitro"
fi

if [ -f /etc/modprobe.d/blacklist-acer_wmi.conf ]; then
  echo "  OK   acer_wmi na blacklist"
else
  echo "  FALHA blacklist de acer_wmi ausente"; fail=1
fi

if lsmod | grep -q '^nexus_sense'; then
  echo "  OK   nexus_sense carregado"
else
  echo "  FALHA nexus_sense nao carregado"; fail=1
fi

if [ -d /sys/devices/platform/acer-wmi/nitro_sense ]; then
  echo "  OK   sysfs populado"
else
  echo "  FALHA sysfs sem nitro_sense -- driver nao vinculou"; fail=1
fi

exit $fail
