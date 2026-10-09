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

# A desinstalacao tem de remover o que install_nexus_sense poe. Ate
# 2026-10-09 so o autostart saia: lancadores, pacote, regra udev, unit do
# agente, .desktop, icones e grupo ficavam para tras, e a varredura da
# armadilha 8 nao os via -- ela procura os nomes da linhagem antiga.
app=$(sed -n '/^cleanup_nexus_sense() {/,/^}/p' "$S")
if [ -n "$app" ]; then
  echo "  OK   cleanup_nexus_sense existe"
else
  echo "  FALHA cleanup_nexus_sense ausente"; fail=1
fi

if printf '%s' "$trecho" | grep -qE '^\s*cleanup_nexus_sense\s*$'; then
  echo "  OK   comprehensive_cleanup chama cleanup_nexus_sense"
else
  echo "  FALHA comprehensive_cleanup nao remove o aplicativo"; fail=1
fi

# Padroes ancorados no fim do caminho: "/usr/bin/nexus-sense" e prefixo de
# "/usr/bin/nexus-sense-agent", e um grep solto aprovaria um pelo outro.
remove() {  # $1=descricao  $2=padrao (ERE)
  if printf '%s' "$app" | grep -v '^\s*#' | grep -qE -- "$2"; then
    echo "  OK   remove $1"
  else
    echo "  FALHA nao remove $1"; fail=1
  fi
}

remove 'o lancador da interface'    '/usr/bin/nexus-sense( |$)'
remove 'o lancador do agente'       '/usr/bin/nexus-sense-agent( |$)'
remove 'o pacote Python'            'rm -rf /usr/lib/nexus-sense$'
remove 'a regra udev'               '/etc/udev/rules\.d/60-nexus-sense\.rules$'
remove 'a unit do agente'           '/usr/lib/systemd/user/nexus-sense-agent\.service$'
remove 'o enable global do agente'  '--global disable nexus-sense-agent\.service'
remove 'o lancador do menu'         '/nexus-sense\.desktop"?$'
remove 'o autostart da bandeja'     '/nexus-sense-autostart\.desktop$'
remove 'os icones'                  "hicolor .*-name 'nexus-sense\*' -delete"
remove 'o grupo'                    'groupdel nexus_sense'

# O disable le a secao [Install] da unit: tem de rodar com ela no disco.
ordem=$(printf '%s' "$app" | grep -v '^\s*#' \
        | grep -nE -- '--global disable|rm -f /usr/lib/systemd/user/' | cut -d: -f1 | tr '\n' ' ')
set -- $ordem
if [ "$#" -eq 2 ] && [ "$1" -lt "$2" ]; then
  echo "  OK   desabilita a unit antes de apaga-la"
else
  echo "  FALHA ordem errada entre o disable e o rm da unit: $ordem"; fail=1
fi

# A configuracao e escolha do usuario e fica (decisao D5).
if printf '%s\n%s' "$app" "$trecho" | grep -v '^\s*#' | grep -qF '.config/nexus-sense'; then
  echo "  FALHA a desinstalacao apaga ~/.config/nexus-sense"; fail=1
else
  echo "  OK   ~/.config/nexus-sense fica"
fi

# O grupo do nome antigo sobreviveu a renomeacao do driver.
if printf '%s' "$trecho" | grep -q 'groupdel "${antigo}"'; then
  echo "  OK   remove o grupo do nome antigo"
else
  echo "  FALHA nao remove o grupo linuwu_sense"; fail=1
fi

exit $fail
