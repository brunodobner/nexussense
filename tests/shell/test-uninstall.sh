#!/bin/bash
# Verifica que a desinstalacao nao deixa registro DKMS para tras.
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

trecho=$(sed -n '/^comprehensive_cleanup() {/,/^}/p' "$S")

if printf '%s' "$trecho" | grep -q 'dkms remove'; then
  echo "  OK   comprehensive_cleanup chama dkms remove"
else
  echo "  FALHA comprehensive_cleanup nao remove o registro DKMS"; fail=1
fi

if printf '%s' "$trecho" | grep -q '/var/lib/dkms/nexus_sense'; then
  echo "  OK   limpa o estado em /var/lib/dkms"
else
  echo "  FALHA nao limpa /var/lib/dkms/nexus_sense"; fail=1
fi

if printf '%s' "$trecho" | grep -q 'modules-load.d/nexus_sense.conf'; then
  echo "  OK   remove modules-load.d"
else
  echo "  FALHA nao remove modules-load.d"; fail=1
fi

if printf '%s' "$trecho" | grep -q 'blacklist-acer_wmi.conf'; then
  echo "  OK   remove a blacklist do acer_wmi"
else
  echo "  FALHA nao remove a blacklist do acer_wmi"; fail=1
fi

# O 'make uninstall' do upstream removia a unit; o Makefile pos-DKMS nao
# toca em servicos, entao a limpeza precisa faze-lo -- senao sobra unit
# habilitada apontando para um modulo que nao existe mais.
if printf '%s' "$trecho" | grep -q 'nexus_sense.target'; then
  echo "  OK   remove as unidades systemd do modulo"
else
  echo "  FALHA nao remove nexus_sense.service/.target"; fail=1
fi

# Atalhos de lanchador criados por instaladores de outra linhagem
# (damx-gui.desktop -> /usr/local/bin/damx-gui) sobreviviam a
# desinstalacao e ficavam no menu como entrada morta.
legacy=$(sed -n '/^cleanup_legacy_installation() {/,/^}/p' "$S")
if printf '%s' "$legacy" | grep -q 'damx-gui.desktop'; then
  echo "  OK   remove damx-gui.desktop orfao"
else
  echo "  FALHA nao remove damx-gui.desktop"; fail=1
fi

if grep -q '^refresh_desktop_database() {' "$S"; then
  echo "  OK   refresh_desktop_database existe"
else
  echo "  FALHA refresh_desktop_database ausente"; fail=1
fi

if printf '%s' "$trecho" | grep -q 'refresh_desktop_database'; then
  echo "  OK   comprehensive_cleanup atualiza o menu"
else
  echo "  FALHA comprehensive_cleanup nao atualiza o menu"; fail=1
fi

# Estado do daemon e do driver. Sem remover, um reinstall herda em
# silencio as configuracoes de uma instalacao que o usuario apagou.
for alvo in '/etc/DAMX_Daemon' '/etc/predator_state'; do
  if printf '%s' "$trecho" | grep -qF "$alvo"; then
    echo "  OK   remove $alvo"
  else
    echo "  FALHA nao remove $alvo"; fail=1
  fi
done

if printf '%s' "$legacy" | grep -q 'damx-daemon'; then
  echo "  OK   remove /usr/local/bin/damx-daemon orfao"
else
  echo "  FALHA nao remove damx-daemon"; fail=1
fi

# O remap de keycode da tecla Nitro e system-wide; a desinstalacao tem de
# devolver a tecla ao comportamento de fabrica.
if printf '%s' "$trecho" | grep -q '61-damx-nitro-key.hwdb'; then
  echo "  OK   remove a regra hwdb da tecla Nitro"
else
  echo "  FALHA nao remove a regra hwdb"; fail=1
fi

exit $fail
