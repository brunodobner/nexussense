#!/bin/bash

# Nexus Sense -- instalador
#
# Copyright (C) 2026  Bruno Dobner <contato@brunodobner.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Instala, desinstala e atualiza o Nexus Sense em laptops Acer Nitro e
# Predator. Componentes: o driver nexus_sense e o app (janela, bandeja e
# agente de energia).
#
# As referencias a DAMX que sobram abaixo sao caminhos de instalacoes
# ANTIGAS (/opt/DAMX, DAMX-Daemon.service, /etc/DAMX_Daemon). Elas ficam
# de proposito: e por esses nomes que a limpeza encontra e remove uma
# instalacao anterior. Renomea-las deixaria rastro orfao -- ver
# docs/armadilhas.md, armadilha 8.

# Constants
#
# A versao e a do PROJETO, nao a do modulo. O driver tem a sua propria em
# DRIVER_VERSION (nexus_sense.c), que alimenta o pacote DKMS -- sao dois
# espacos de numeracao de proposito. Ver docs/decisoes.md secao 7.
SCRIPT_VERSION="1.0.0"
# Caminhos de instalacoes ANTIGAS, mantidos so para a limpeza encontra-los.
# Nada deste projeto e instalado neles: o pacote vai para
# /usr/lib/nexus-sense e os lancadores para /usr/bin. Ver docs/decisoes.md
# secao 3.
INSTALL_DIR="/opt/damx"
BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
DAEMON_SERVICE_NAME="damx-daemon.service"
DESKTOP_FILE_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/256x256/apps"

# Raiz do repositorio. Este script vive nela, e todo caminho do projeto
# deriva daqui -- nunca do diretorio corrente. Rodar "sudo /caminho/para/
# setup.sh" de qualquer lugar tem de funcionar igual.
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_DIR="${RAIZ}/driver"

# Legacy paths for cleanup (uppercase naming convention)
LEGACY_INSTALL_DIR="/opt/DAMX"
LEGACY_DAEMON_SERVICE_NAME="DAMX-Daemon.service"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to pause script execution
pause() {
  echo -e "${BLUE}Press any key to continue...${NC}"
  read -n 1 -s -r
}

# Function to check and elevate privileges
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script requires root privileges.${NC}"

    # Check if sudo is available
    if command -v sudo &> /dev/null; then
      echo -e "${BLUE}Attempting to run with sudo...${NC}"
      exec sudo "$0" "$@"
      exit $?
    else
      echo -e "${RED}Error: sudo not found. Please run this script as root.${NC}"
      pause
      exit 1
    fi
  fi
}

print_banner() {
  clear
  echo -e "${BLUE}==========================================${NC}"
  echo -e "${BLUE}      Nexus Sense Installer v${SCRIPT_VERSION}       ${NC}"
  echo -e "${BLUE}    Acer Laptop WMI Controls for Linux  ${NC}"
  echo -e "${BLUE}==========================================${NC}"
  echo ""
}

# Refresh the desktop entry database so removed launchers stop showing
# up in the application menu. Harmless when the tool is absent.
refresh_desktop_database() {
  if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "${DESKTOP_FILE_DIR}" &> /dev/null || true
  fi
  if command -v gtk-update-icon-cache &> /dev/null; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor &> /dev/null || true
  fi
}

# Function to detect and clean up legacy installations
cleanup_legacy_installation() {
  echo -e "${YELLOW}Checking for legacy installations...${NC}"
  local cleanup_performed=false

  # Check for legacy service file (uppercase naming)
  if [ -f "${SYSTEMD_DIR}/${LEGACY_DAEMON_SERVICE_NAME}" ]; then
    echo -e "${BLUE}Found legacy service file: ${LEGACY_DAEMON_SERVICE_NAME}${NC}"

    # Stop the legacy service if it's running
    if systemctl is-active --quiet ${LEGACY_DAEMON_SERVICE_NAME} 2>/dev/null; then
      echo "Stopping legacy service..."
      systemctl stop ${LEGACY_DAEMON_SERVICE_NAME}
    fi

    # Disable the legacy service if it's enabled
    if systemctl is-enabled --quiet ${LEGACY_DAEMON_SERVICE_NAME} 2>/dev/null; then
      echo "Disabling legacy service..."
      systemctl disable ${LEGACY_DAEMON_SERVICE_NAME}
    fi

    # Remove the legacy service file
    echo "Removing legacy service file..."
    rm -f "${SYSTEMD_DIR}/${LEGACY_DAEMON_SERVICE_NAME}"
    cleanup_performed=true
  fi

  # Check for legacy installation directory (uppercase naming)
  if [ -d "${LEGACY_INSTALL_DIR}" ]; then
    echo -e "${BLUE}Found legacy installation directory: ${LEGACY_INSTALL_DIR}${NC}"
    echo "Removing legacy installation directory..."
    rm -rf "${LEGACY_INSTALL_DIR}"
    cleanup_performed=true
  fi

  # Check for other potential legacy artifacts.
  # The damx-gui.* entries come from community/personal installers that
  # used different names than this script: they point at
  # /usr/local/bin/damx-gui, which no longer exists, so they survive an
  # uninstall as a dead entry in the application menu.
  local legacy_artifacts=(
    "/usr/local/bin/DAMX-Daemon"
    "/usr/share/applications/DAMX.desktop"
    "/usr/share/icons/hicolor/256x256/apps/DAMX.png"
    "/usr/local/bin/damx-gui"
    "/usr/local/bin/damx-daemon"
    "/usr/share/applications/damx-gui.desktop"
    "/usr/share/icons/hicolor/256x256/apps/damx-gui.png"
    "/usr/share/pixmaps/damx-gui.png"
  )

  for artifact in "${legacy_artifacts[@]}"; do
    if [ -f "$artifact" ] || [ -d "$artifact" ]; then
      echo "Removing legacy artifact: $artifact"
      rm -rf "$artifact"
      cleanup_performed=true
    fi
  done

  # Reload systemd daemon if any service changes were made
  if [ "$cleanup_performed" = true ]; then
    echo "Reloading systemd daemon configuration..."
    systemctl daemon-reload
    refresh_desktop_database
    echo -e "${GREEN}Legacy installation cleanup completed.${NC}"
  else
    echo -e "${GREEN}No legacy installations found.${NC}"
  fi

  return 0
}

# Function to perform comprehensive cleanup for uninstall/reinstall
comprehensive_cleanup() {
  echo -e "${YELLOW}Performing comprehensive cleanup...${NC}"

  # Stop and disable current daemon service
  if systemctl is-active --quiet ${DAEMON_SERVICE_NAME} 2>/dev/null; then
    echo "Stopping current DAMX-Daemon service..."
    systemctl stop ${DAEMON_SERVICE_NAME}
  fi

  if systemctl is-enabled --quiet ${DAEMON_SERVICE_NAME} 2>/dev/null; then
    echo "Disabling current DAMX-Daemon service..."
    systemctl disable ${DAEMON_SERVICE_NAME}
  fi

  # Remove current service file
  if [ -f "${SYSTEMD_DIR}/${DAEMON_SERVICE_NAME}" ]; then
    echo "Removing current service file..."
    rm -f "${SYSTEMD_DIR}/${DAEMON_SERVICE_NAME}"
  fi

  # Clean up nitro key detection service
  cleanup_nitro_service

  # Clean up legacy installations
  cleanup_legacy_installation

  # Remove current installed files
  echo "Removing current installation files..."
  rm -rf ${INSTALL_DIR}
  rm -f ${BIN_DIR}/DAMX
  rm -f ${DESKTOP_FILE_DIR}/damx.desktop
  rm -f ${ICON_DIR}/damx.png

  # A virada: o daemon root e a GUI binaria saem de vez. Ver spec, D2.
  #
  # O socket em /var/run/DAMX.sock era modo 666, sem autenticacao:
  # qualquer processo da maquina podia recarregar o driver por ele. Some
  # junto e nao volta -- o Nexus Sense nao tem socket nenhum.
  rm -f /var/run/DAMX.sock /run/DAMX.sock
  rm -f /etc/xdg/autostart/nexus-sense-autostart.desktop
  rm -rf /opt/DAMX
  refresh_desktop_database

  # Remove the driver. Under DKMS 'make uninstall' is not enough: it drops
  # the .ko but leaves the registration, so DKMS keeps rebuilding a module
  # the user asked to remove on every kernel upgrade.
  # A renomeacao deixa um pacote DKMS orfao com o nome antigo, registrado
  # para todos os kernels com headers. Se ele ficar, dois modulos
  # disputam o mesmo dispositivo WMI e qual carrega e indeterminado.
  #
  # Roda antes do novo ser registrado, e por isso vive na limpeza.
  for antigo in linuwu_sense; do
    if dkms status 2> /dev/null | grep -q "^${antigo}"; then
      echo "Removendo o pacote DKMS antigo: ${antigo}"
      for v in $(dkms status 2> /dev/null | grep "^${antigo}" \
                 | sed -E "s|^${antigo}[/,] *([^,]+).*|\\1|" | sort -u); do
        dkms remove -m "${antigo}" -v "${v}" --all &> /dev/null || true
      done
    fi
    rm -rf "/usr/src/${antigo}-"*
    rm -f "/etc/modules-load.d/${antigo}.conf"
    if [ -f "${SYSTEMD_DIR}/${antigo}.service" ]; then
      systemctl disable --now "${antigo}.service" &> /dev/null || true
      rm -f "${SYSTEMD_DIR}/${antigo}.service"
    fi
    modprobe -r "${antigo}" &> /dev/null || true
    find /lib/modules -name "${antigo}.ko*" -delete &> /dev/null || true
  done

  if [ -d "$DRIVER_DIR" ]; then
    echo "Uninstalling drivers..."

    if command -v dkms &> /dev/null; then
      local ver v registered
      ver=$(driver_version 2>/dev/null || true)

      # Remove whatever versions are registered, not just the current
      # source's -- an older install may carry a different version.
      # "nexus_sense/25.701, 7.2.2-1-cachyos, x86_64: installed" -> "25.701"
      # The [/,] alternative also covers dkms builds that print
      # "nexus_sense, 25.701, ...".
      registered=$(dkms status 2>/dev/null | grep '^nexus_sense' \
                   | sed -E 's|^nexus_sense[/,] *([^,]+).*|\1|' | sort -u)
      for v in $registered $ver; do
        [ -n "$v" ] || continue
        echo "Removing DKMS registration nexus_sense/${v}..."
        dkms remove -m nexus_sense -v "$v" --all &> /dev/null || true
        rm -rf "/usr/src/nexus_sense-${v}"
      done
      rm -rf /var/lib/dkms/nexus_sense
    fi

    ( cd "$DRIVER_DIR" && [ -f Makefile ] && make uninstall ) &> /dev/null || true
  fi

  # Remove the module's own systemd units. 'make uninstall' used to do
  # this; the DKMS-era Makefile no longer touches services, so cleanup
  # owns it -- otherwise a uninstall leaves enabled units pointing at a
  # module that no longer exists.
  for unit in nexus_sense.service nexus_sense.target; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      systemctl stop "$unit" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      systemctl disable "$unit" 2>/dev/null || true
    fi
    rm -f "${SYSTEMD_DIR}/${unit}"
  done

  # Stop loading the module at boot and let acer_wmi come back.
  rm -f /etc/modules-load.d/nexus_sense.conf
  rm -f /etc/modprobe.d/blacklist-acer_wmi.conf
  rmmod nexus_sense 2>/dev/null || true
  modprobe acer_wmi 2>/dev/null || true
  depmod -a

  # Remove nitro key configuration
  rm -rf /etc/damx

  unbind_button_from_nexus

  # Remove the button keycode remap and reapply, so the key returns to its
  # firmware default.
  if [ -f /etc/udev/hwdb.d/61-damx-nitro-key.hwdb ]; then
    rm -f /etc/udev/hwdb.d/61-damx-nitro-key.hwdb
    systemd-hwdb update &> /dev/null || true
    udevadm trigger --subsystem-match=input --action=change &> /dev/null || true
  fi

  # Daemon configuration and driver state files. The daemon writes
  # /etc/DAMX_Daemon/config.ini; the module itself writes the state files
  # it reloads on probe. Leaving them behind means a later reinstall
  # silently inherits settings from an installation the user removed.
  rm -rf /etc/DAMX_Daemon
  rm -f /etc/predator_state
  rm -f /etc/four_zone_kb_state

  # Final systemd daemon reload
  systemctl daemon-reload

  echo -e "${GREEN}Comprehensive cleanup completed.${NC}"
  return 0
}

# Undo what bind_button_to_nexus wrote.
#
# Only removes the exact value this installer writes. A user who picked
# their own shortcut for DAMX keeps it -- their choice is not ours to
# discard, even on uninstall.
#
# This exists because the alternative is worse: leaving the binding behind
# points a live shortcut at a .desktop the uninstall just deleted, which is
# the dead-menu-entry problem in another guise.
unbind_button_from_nexus() {
  local user home current

  user=$(detect_desktop_user)
  [ -n "$user" ] && id -u "$user" &> /dev/null || return 0
  command -v kreadconfig6 &> /dev/null || return 0

  home=$(getent passwd "$user" | cut -d: -f6)
  [ -f "${home}/.config/kglobalshortcutsrc" ] || return 0

  current=$(runuser -u "$user" -- env HOME="$home" kreadconfig6 --file kglobalshortcutsrc \
              --group services --group nexus-sense.desktop --key _launch 2>/dev/null)

  if [ "$current" = "Launch (1)" ]; then
    # kwriteconfig6 has no --delete-group: keys go one at a time.
    echo "Removing the Nexus Sense button shortcut..."
    local key
    for key in _launch _k_friendly_name; do
      runuser -u "$user" -- env HOME="$home" kwriteconfig6 --file kglobalshortcutsrc \
        --group services --group nexus-sense.desktop --key "$key" --delete &> /dev/null || true
    done
  elif [ -n "$current" ]; then
    echo "Keeping the custom Nexus Sense shortcut '${current}' (not set by this installer)."
  fi
}

# Function to clean up nitro key detection service
cleanup_nitro_service() {
  echo -e "${YELLOW}Cleaning up Nitro Key Detection Service...${NC}"
  
  NITRO_SERVICE_NAME="nitro-key-detection.service"
  
  # Stop the service if it's running
  if systemctl is-active --quiet ${NITRO_SERVICE_NAME} 2>/dev/null; then
    echo "Stopping ${NITRO_SERVICE_NAME}..."
    systemctl stop ${NITRO_SERVICE_NAME}
  fi
  
  # Disable the service if it's enabled
  if systemctl is-enabled --quiet ${NITRO_SERVICE_NAME} 2>/dev/null; then
    echo "Disabling ${NITRO_SERVICE_NAME}..."
    systemctl disable ${NITRO_SERVICE_NAME}
  fi
  
  # Remove the service file
  if [ -f "${SYSTEMD_DIR}/${NITRO_SERVICE_NAME}" ]; then
    echo "Removing ${NITRO_SERVICE_NAME} file..."
    rm -f "${SYSTEMD_DIR}/${NITRO_SERVICE_NAME}"
  fi
  
  # Remove the nitro key detection script
  if [ -f "/usr/local/bin/nitro-key-detection.sh" ]; then
    echo "Removing nitro-key-detection.sh script..."
    rm -f "/usr/local/bin/nitro-key-detection.sh"
  fi
  
  # Remove nitro key configuration
  if [ -f "/etc/damx/nitro_key.conf" ]; then
    echo "Removing nitro_key.conf configuration..."
    rm -f "/etc/damx/nitro_key.conf"
  fi
  
  echo -e "${GREEN}Nitro Key Detection Service cleanup completed.${NC}"
}

# Detect the compiler used to build the running kernel.
is_llvm_kernel() {
  local kernel_release
  local kernel_build
  local config_file

  kernel_release=$(uname -r)
  kernel_build="/lib/modules/${kernel_release}/build"

  for config_file in "/boot/config-${kernel_release}" "${kernel_build}/.config"; do
    if [ -r "$config_file" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "$config_file"; then
      return 0
    fi
  done

  if command -v zgrep &> /dev/null &&
     [ -r /proc/config.gz ] &&
     zgrep -q '^CONFIG_CC_IS_CLANG=y' /proc/config.gz; then
    return 0
  fi

  if grep -qsiE 'clang|llvm' /proc/version 2>/dev/null; then
    return 0
  fi

  if [ -r "${kernel_build}/include/generated/compile.h" ] &&
     grep -qsiE 'clang|llvm' "${kernel_build}/include/generated/compile.h"; then
    return 0
  fi

  # CachyOS kernels are LLVM-built by default. Keep this fallback for
  # installations where the running kernel does not expose its build config.
  if [ -r /etc/os-release ] && grep -qi 'cachyos' /etc/os-release; then
    return 0
  fi

  return 1
}

# Install build dependencies based on distribution.
# Kernel headers are required for any module build; DKMS is required for
# the module to survive kernel upgrades. Neither base-devel nor
# build-essential includes headers, so they are requested explicitly.
install_build_deps() {
  if command -v pacman &> /dev/null; then
    # Arch-based (including CachyOS, Manjaro, EndeavourOS).
    # linux-headers covers the stock kernel; other kernels (linux-lts,
    # linux-cachyos, ...) need their own -headers package, which
    # check_kernel_headers reports on.
    pacman -S --needed --noconfirm base-devel linux-headers dkms
    if is_llvm_kernel; then
      pacman -S --needed --noconfirm clang llvm lld
    fi
  elif command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y build-essential dkms "linux-headers-$(uname -r)"
  elif command -v dnf &> /dev/null; then
    dnf install -y gcc make kernel-devel dkms
  elif command -v zypper &> /dev/null; then
    zypper install -y gcc make kernel-devel dkms
  else
    echo -e "${YELLOW}Unknown package manager. Install build tools, kernel headers and dkms manually.${NC}"
    return 1
  fi
}

# Dependências de execução da janela, bandeja e agente. O pacote Python é
# copiado para /usr/lib, então estes módulos precisam vir do gerenciador da
# distribuição, no mesmo Python usado por /usr/bin/nexus-sense.
runtime_dependencies_ok() {
  python3 -c 'import PySide6, dbus, tomli_w' &> /dev/null &&
    command -v powerprofilesctl &> /dev/null &&
    command -v nvidia-settings &> /dev/null
}

install_runtime_deps() {
  runtime_dependencies_ok && return 0

  echo -e "${YELLOW}Installing Nexus Sense runtime dependencies...${NC}"
  if command -v pacman &> /dev/null; then
    pacman -S --needed --noconfirm pyside6 python-dbus python-tomli-w \
      power-profiles-daemon nvidia-settings
  elif command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y python3-pyside6.qtcore python3-pyside6.qtgui \
      python3-pyside6.qtwidgets python3-pyside6.qtdbus python3-dbus python3-tomli-w \
      power-profiles-daemon nvidia-settings
  elif command -v dnf &> /dev/null; then
    dnf install -y python3-pyside6 python3-dbus python3-tomli-w \
      power-profiles-daemon nvidia-settings
  elif command -v zypper &> /dev/null; then
    zypper install -y python3-PySide6 python3-dbus-python python3-tomli-w \
      power-profiles-daemon nvidia-settings
  else
    echo -e "${RED}Unknown package manager. Install PySide6, dbus-python, tomli-w, powerprofilesctl and nvidia-settings.${NC}"
    return 1
  fi

  if ! runtime_dependencies_ok; then
    echo -e "${RED}Error: Python runtime dependencies are still unavailable.${NC}"
    return 1
  fi
}

# Report which installed kernels have usable headers.
# DKMS builds for every kernel it finds, so a kernel without headers is a
# build failure waiting to happen -- worth naming up front rather than
# hitting mid-install.
check_kernel_headers() {
  local kver missing=0
  echo -e "${BLUE}Checking kernel headers...${NC}"
  for kver in $(ls /lib/modules); do
    if [ -d "/lib/modules/${kver}/build" ]; then
      echo -e "  ${GREEN}OK${NC}      ${kver}"
    else
      echo -e "  ${YELLOW}MISSING${NC} ${kver}"
      missing=$((missing + 1))
    fi
  done

  if [ "$missing" -gt 0 ]; then
    echo -e "${YELLOW}${missing} kernel(s) without headers. DKMS will skip them.${NC}"
    echo -e "${YELLOW}Install the matching headers package (e.g. linux-lts-headers) to cover them.${NC}"
  fi

  # Only the running kernel is fatal -- it is the one we must load into now.
  if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo -e "${RED}Error: no headers for the running kernel ($(uname -r)).${NC}"
    return 1
  fi
  return 0
}

# Read the driver version from the source of truth.
# Hardcoding it means a future upstream bump silently makes the installer
# operate on the wrong DKMS package.
driver_version() {
  grep -oP '#define DRIVER_VERSION "\K[^"]+' "$DRIVER_DIR/src/nexus_sense.c"
}

# acer_wmi claims the same WMI GUIDs as nexus_sense. Without the
# blacklist it wins the race at boot and nexus_sense loads but never
# binds, leaving sysfs empty.
configure_acer_wmi_conflict() {
  echo -e "${YELLOW}Resolving acer_wmi conflict...${NC}"

  cat > /etc/modprobe.d/blacklist-acer_wmi.conf << 'EOL'
# Installed by Nexus Sense setup.sh
# acer_wmi claims the same WMI GUIDs as nexus_sense.
blacklist acer_wmi
EOL

  # The blacklist only takes effect at next boot; unload now as well.
  if lsmod | grep -q '^acer_wmi'; then
    modprobe -r acer_wmi 2>/dev/null \
      || echo -e "${YELLOW}Could not unload acer_wmi; reboot to complete.${NC}"
  fi

  echo "nexus_sense" > /etc/modules-load.d/nexus_sense.conf
  depmod -a

  # Replace any running instance with the freshly installed one.
  rmmod nexus_sense 2>/dev/null || true
  modprobe nexus_sense 2>/dev/null \
    || echo -e "${YELLOW}Could not load nexus_sense; reboot to complete.${NC}"

  if [ -d /sys/devices/platform/acer-wmi/nitro_sense ] \
     || [ -d /sys/devices/platform/acer-wmi/predator_sense ]; then
    echo -e "${GREEN}Driver bound; sysfs populated.${NC}"
  else
    echo -e "${YELLOW}sysfs not populated yet; reboot to complete.${NC}"
  fi
}

# Make the Nitro/PredatorSense button bindable as a normal shortcut.
#
# On models systemd's hwdb does not list, the button arrives as
# KEY_PRESENTATION (425). Its keysym, XF86Presentation, has no Qt name, so
# KDE silently blanks any shortcut assigned to it -- and other desktops
# have similar gaps. systemd's own convention for Acer gaming laptops is
# to map scancode 0xf5 to prog1, which becomes XF86Launch1: a key every
# desktop can bind. This installs that same rule for models still missing
# from the upstream list.
#
# No daemon, no root service reading the keyboard: just a keycode remap.
install_nitro_key_hwdb() {
  local product pattern dmi
  product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
  [ -n "$product" ] || return 0

  # Only Acer gaming models use the 0xf5 button.
  case "$product" in
    Nitro*|Predator*) ;;
    *) return 0 ;;
  esac

  # Ask whether the button ALREADY produces a bindable keycode -- not
  # merely whether some mapping exists. systemd's generic Acer entry maps
  # 0xf5 to "presentation" on every Acer laptop, so testing for the bare
  # presence of KEYBOARD_KEY_f5 would skip on every machine and make this
  # function a no-op. Only prog1 means the work is already done.
  #
  # A pergunta vai para o BANCO hwdb, recompilado agora, e nao para a
  # propriedade do device (`udevadm info`). A propriedade e cache do
  # ultimo evento: numa reinstalacao, comprehensive_cleanup acabou de
  # apagar o nosso arquivo e ela AINDA responde prog1, resquicio de antes
  # da remocao. Confiar nela fazia esta funcao concluir "trabalho ja
  # feito" e nunca reescrever o arquivo -- e o botao voltava a
  # KEY_PRESENTATION no reboot seguinte, sem nada no log. Ver armadilha 23.
  #
  # O `systemd-hwdb update` antes da consulta e o que elimina a
  # possibilidade de ler banco velho: depois dele o banco reflete os
  # arquivos em disco, seja o nosso ou o do systemd.
  systemd-hwdb update &> /dev/null || true
  dmi=$(cat /sys/class/dmi/id/modalias 2>/dev/null)
  if [ -n "$dmi" ] && systemd-hwdb query "evdev:atkbd:${dmi}" 2>/dev/null \
       | grep -q '^KEYBOARD_KEY_f5=prog1$'; then
    # Ja mapeado em disco por algum arquivo -- o nosso, numa reinstalacao
    # que nao limpou, ou o 60-keyboard.hwdb do systemd nos modelos que ele
    # cobre. Ainda assim e preciso vincular o atalho: ele mora na config
    # do usuario e pode nao existir mesmo com a regra hwdb no lugar.
    echo -e "${GREEN}Nitro button already maps to prog1.${NC}"
    bind_button_to_nexus
    return 0
  fi

  # "Nitro ANV15-52" -> "Nitro*ANV15-52", matching hwdb's own style.
  pattern=$(printf '%s' "$product" | sed 's/ /*/g')

  echo -e "${YELLOW}Mapping the Nitro/PredatorSense button for ${product}...${NC}"
  mkdir -p /etc/udev/hwdb.d
  cat > /etc/udev/hwdb.d/61-damx-nitro-key.hwdb <<EOL
# Installed by Nexus Sense setup.sh
# Maps the NitroSense/PredatorSense button (scancode 0xf5) to prog1, the
# same mapping systemd's 60-keyboard.hwdb already uses for AN515-47,
# AN515-58, PHN16-71 and others. Without it the button reports
# KEY_PRESENTATION, whose keysym no desktop toolkit can bind.
evdev:atkbd:dmi:bvn*:bvr*:bd*:svnAcer*:pn${pattern}:pvr*
 KEYBOARD_KEY_f5=prog1
EOL

  if systemd-hwdb update && udevadm trigger --subsystem-match=input --action=change; then
    echo -e "${GREEN}Button mapped to XF86Launch1.${NC}"
    bind_button_to_nexus
  else
    echo -e "${YELLOW}hwdb update failed; the button keeps its default mapping.${NC}"
  fi
}

# Bind the remapped button to Nexus Sense in the desktop's shortcut store.
#
# Only KDE Plasma is handled automatically: its format was verified here
# (the button arrives as Qt's "Launch (1)"), and guessing at other
# desktops' stores from a root installer would be worse than printing
# instructions. Everyone else gets the instructions.
#
# An existing binding is never overwritten -- if the user already chose a
# shortcut for DAMX, that choice wins.
bind_button_to_nexus() {
  local user home rc current

  # Lido por configure_nitro_button logo depois: com o botao ja vinculado,
  # o servico de deteccao vira alternativa, nao necessidade.
  NITRO_KEY_BOUND=0

  print_shortcut_instructions() {
    echo -e "${BLUE}To open Nexus Sense with the button: your desktop's keyboard${NC}"
    echo -e "${BLUE}settings -> Shortcuts -> add the Nexus Sense application, and${NC}"
    echo -e "${BLUE}press the button when asked for the key combination.${NC}"
  }

  user=$(detect_desktop_user)
  if [ -z "$user" ] || ! id -u "$user" &> /dev/null; then
    print_shortcut_instructions
    return 0
  fi

  home=$(getent passwd "$user" | cut -d: -f6)
  rc="${home}/.config/kglobalshortcutsrc"

  if [ ! -f "$rc" ] || ! command -v kwriteconfig6 &> /dev/null; then
    print_shortcut_instructions
    return 0
  fi

  current=$(runuser -u "$user" -- env HOME="$home" kreadconfig6 --file kglobalshortcutsrc \
              --group services --group nexus-sense.desktop --key _launch 2>/dev/null)
  if [ -n "$current" ]; then
    echo -e "${GREEN}Nexus Sense already has the shortcut '${current}'; leaving it alone.${NC}"
    NITRO_KEY_BOUND=1
    return 0
  fi

  # "Launch (1)" is Qt's portable name for XF86Launch1, which is what
  # prog1 becomes. Writing the keysym name instead makes KWin silently
  # blank the entry -- Qt has no name for XF86Presentation.
  if runuser -u "$user" -- env HOME="$home" kwriteconfig6 --file kglobalshortcutsrc \
       --group services --group nexus-sense.desktop --key _launch "Launch (1)" 2>/dev/null &&
     runuser -u "$user" -- env HOME="$home" kwriteconfig6 --file kglobalshortcutsrc \
       --group services --group nexus-sense.desktop --key _k_friendly_name "Nexus Sense" 2>/dev/null; then
    NITRO_KEY_BOUND=1
    echo -e "${GREEN}Button bound to Nexus Sense for user ${user}.${NC}"
    echo -e "${YELLOW}KWin reads shortcut bindings at login: log out and back in${NC}"
    echo -e "${YELLOW}to activate it.${NC}"
  else
    echo -e "${YELLOW}Could not write the shortcut.${NC}"
    print_shortcut_instructions
  fi
}

# Install the module's shutdown unit.
# The module itself is loaded by /etc/modules-load.d/nexus_sense.conf,
# earlier than any unit could. This unit exists for the unload: systemd
# does not remove modules at shutdown, so without it the driver's remove
# path -- and with it acer_predator_state_save() -- never runs.
install_module_service() {
  local unit="${RAIZ}/packaging/systemd/nexus_sense.service"
  [ -f "$unit" ] || { echo -e "${YELLOW}nexus_sense.service not found; skipping.${NC}"; return 0; }

  install -m 644 "$unit" "${SYSTEMD_DIR}/nexus_sense.service"
  systemctl daemon-reload
  systemctl enable nexus_sense.service &> /dev/null
  systemctl start nexus_sense.service &> /dev/null
  echo -e "${GREEN}nexus_sense.service installed (saves state at shutdown).${NC}"
}

install_drivers() {
  echo -e "${YELLOW}Installing Nexus Sense drivers...${NC}"

  if [ ! -d "$DRIVER_DIR" ]; then
    echo -e "${RED}Error: driver directory not found at ${DRIVER_DIR}!${NC}"
    echo "The repository layout is broken: setup.sh expects driver/ beside it."
    pause
    return 1
  fi

  if ! command -v make &> /dev/null || ! command -v dkms &> /dev/null; then
    echo -e "${YELLOW}Installing build tools...${NC}"
    install_build_deps || { pause; return 1; }
  fi

  check_kernel_headers || { pause; return 1; }

  local ver
  ver=$(driver_version)
  if [ -z "$ver" ]; then
    echo -e "${RED}Error: could not read DRIVER_VERSION from the source.${NC}"
    pause
    return 1
  fi
  echo -e "${BLUE}Driver version (from source): ${ver}${NC}"

  if ! command -v dkms &> /dev/null; then
    echo -e "${YELLOW}DKMS unavailable; falling back to a single-kernel build.${NC}"
    echo -e "${YELLOW}The module will NOT survive kernel upgrades.${NC}"
    ( cd "$DRIVER_DIR" && make clean && make && make install ) || {
      echo -e "${RED}Error: Failed to build Nexus Sense drivers${NC}"
      pause
      return 1
    }
    configure_acer_wmi_conflict
    install_module_service
    return 0
  fi

  # Remove any previous registration. DKMS state lives in /var/lib/dkms,
  # not /usr/src -- deleting only /usr/src leaves an orphan record and the
  # next 'dkms add' fails.
  echo -e "${BLUE}Clearing previous DKMS registration...${NC}"
  dkms remove -m nexus_sense -v "$ver" --all &> /dev/null || true
  rm -rf "/usr/src/nexus_sense-${ver}"
  rm -rf "/var/lib/dkms/nexus_sense/${ver}"

  echo -e "${BLUE}Staging source in /usr/src/nexus_sense-${ver}...${NC}"
  mkdir -p "/usr/src/nexus_sense-${ver}"
  cp -r "$DRIVER_DIR/src" "$DRIVER_DIR/Makefile" "/usr/src/nexus_sense-${ver}/"
  sed "s/^PACKAGE_VERSION=.*/PACKAGE_VERSION=\"${ver}\"/" \
      "$DRIVER_DIR/dkms.conf" > "/usr/src/nexus_sense-${ver}/dkms.conf"

  if ! dkms add -m nexus_sense -v "$ver"; then
    echo -e "${RED}Error: dkms add failed${NC}"
    pause
    return 1
  fi

  # Build for every BOOTABLE kernel that has headers, not just the running
  # one -- que e o proposito do DKMS.
  #
  # "tem headers" nao basta como criterio. Um `linux-headers` sem o pacote
  # `linux` correspondente -- situacao comum no Arch, onde algo puxa os
  # headers como dependencia -- cria /lib/modules/<ver>/build sem kernel
  # nenhum: sem vmlinuz, sem modules.dep, impossivel de bootar. Construir
  # para ele gasta minutos e, pior, faz a verificacao de "compilado para
  # todos os kernels" cobrar um modulo que nunca vai ser carregado.
  #
  # vmlinuz e o discriminador: so o pacote do kernel o instala.
  local kver built=0 pulados=0
  for kver in $(ls /lib/modules); do
    [ -d "/lib/modules/${kver}/build" ] || continue
    if [ ! -e "/lib/modules/${kver}/vmlinuz" ]; then
      echo -e "  ${YELLOW}PULADO${NC} ${kver} (headers sem kernel bootavel)"
      pulados=$((pulados + 1))
      continue
    fi
    echo -e "${BLUE}Building for ${kver}...${NC}"
    if dkms install -m nexus_sense -v "$ver" -k "$kver" &> /dev/null; then
      echo -e "  ${GREEN}OK${NC} ${kver}"
      built=$((built + 1))
    else
      echo -e "  ${YELLOW}FAILED${NC} ${kver} (continuing)"
    fi
  done

  if [ "$built" -eq 0 ]; then
    echo -e "${RED}Error: the module built for no kernel at all.${NC}"
    echo -e "${YELLOW}Diagnostics: dkms install -m nexus_sense -v ${ver} -k $(uname -r)${NC}"
    pause
    return 1
  fi

  # 'dkms status' exits 0 even for a package that does not exist, so the
  # test must look for the word, not the exit code.
  if ! dkms status "nexus_sense/${ver}" | grep -q installed; then
    echo -e "${RED}Error: DKMS reports no installed module for nexus_sense/${ver}${NC}"
    pause
    return 1
  fi

  configure_acer_wmi_conflict
  install_module_service

  echo -e "${GREEN}Nexus Sense installed via DKMS for ${built} kernel(s).${NC}"
  [ "$pulados" -gt 0 ] && echo -e "${BLUE}${pulados} kernel(s) com headers mas sem imagem bootavel foram pulados.${NC}"
  return 0
}

# Instala o Nexus Sense: o pacote Python, os dois lancadores, os icones,
# a regra udev com o grupo e a unit de usuario do agente.
#
# O pacote vai inteiro para /usr/lib/nexus-sense e os lancadores apontam
# PYTHONPATH para la. Instalar por pip dentro de /usr brigaria com o
# gerenciador de pacotes pelos mesmos caminhos.
#
# Nao instala helper nem regra polkit: nao ha codigo privilegiado neste
# projeto. Ver docs/INTERFACE.md secao 6.1.
install_nexus_sense() {
  echo -e "${YELLOW}Installing Nexus Sense...${NC}"

  install_runtime_deps || return 1

  local pacote
  pacote="${RAIZ}/src/nexus_sense"

  if [ ! -d "$pacote" ]; then
    echo -e "${RED}Error: src/nexus_sense not found at ${pacote}${NC}"
    return 1
  fi

  # --- o pacote
  install -d /usr/lib/nexus-sense
  rm -rf /usr/lib/nexus-sense/nexus_sense
  cp -r "$pacote" /usr/lib/nexus-sense/nexus_sense
  find /usr/lib/nexus-sense/nexus_sense -name '__pycache__' -type d -exec rm -rf {} +
  install -m 755 "${RAIZ}/packaging/scripts/apply-perms.sh" /usr/lib/nexus-sense/apply-perms.sh

  # --- os dois lancadores
  cat > /usr/bin/nexus-sense << 'EOL'
#!/bin/sh
PYTHONPATH=/usr/lib/nexus-sense exec /usr/bin/python3 -m nexus_sense.gui.app "$@"
EOL
  cat > /usr/bin/nexus-sense-agent << 'EOL'
#!/bin/sh
PYTHONPATH=/usr/lib/nexus-sense exec /usr/bin/python3 -m nexus_sense "$@"
EOL
  chmod +x /usr/bin/nexus-sense /usr/bin/nexus-sense-agent

  # --- icones e lancador do desktop
  # Limpa somente variantes de bandeja pertencentes ao Nexus Sense. Isso
  # remove níveis e modos de versões anteriores antes de copiar o conjunto
  # gerado atualmente.
  find /usr/share/icons/hicolor -type f \
    -path '*/status/nexus-sense-tray*' -delete 2>/dev/null || true
  cp -r "${RAIZ}/packaging/icons/"*x*/ /usr/share/icons/hicolor/ 2>/dev/null || true
  install -d /usr/share/icons/hicolor/scalable/apps /usr/share/icons/hicolor/scalable/status
  cp "${RAIZ}/packaging/icons/scalable/apps/"*.svg /usr/share/icons/hicolor/scalable/apps/
  cp "${RAIZ}/packaging/icons/scalable/status/"*.svg /usr/share/icons/hicolor/scalable/status/
  install -m 644 "${RAIZ}/packaging/desktop/nexus-sense.desktop" \
    "${DESKTOP_FILE_DIR}/nexus-sense.desktop"

  # A bandeja sobe com a sessao. Sem isto o icone so aparece se alguem
  # abrir o app a mao, e um icone de bandeja que exige ser invocado nao
  # serve para o que existe.
  install -d /etc/xdg/autostart
  install -m 644 "${RAIZ}/packaging/desktop/nexus-sense-autostart.desktop" \
    /etc/xdg/autostart/nexus-sense-autostart.desktop

  # --- o grupo, e o aviso que ele exige
  if ! getent group nexus_sense > /dev/null; then
    groupadd -r nexus_sense
    echo -e "${YELLOW}Grupo nexus_sense criado.${NC}"
  fi
  local alvo
  alvo=$(detect_desktop_user)
  if [ -n "$alvo" ]; then
    usermod -aG nexus_sense "$alvo"
    echo -e "${BLUE}Usuário ${alvo} adicionado ao grupo nexus_sense.${NC}"
  fi
  # A spec exige que o instalador diga isto em voz alta ao criar o grupo.
  echo -e "${YELLOW}Atenção: quem estiver no grupo nexus_sense pode alterar${NC}"
  echo -e "${YELLOW}as ventoinhas e o perfil térmico sem senha. O driver limita${NC}"
  echo -e "${YELLOW}a ventoinha a 0-100 e 0 significa automático, então o pior${NC}"
  echo -e "${YELLOW}caso é modesto -- mas é uma permissão que antes não existia.${NC}"
  echo -e "${YELLOW}O grupo só vale depois de relogar.${NC}"

  # --- a regra udev que aplica o grupo aos seis atributos
  install -m 644 "${RAIZ}/packaging/udev/60-nexus-sense.rules" \
    /etc/udev/rules.d/60-nexus-sense.rules
  udevadm control --reload
  udevadm trigger --subsystem-match=platform --action=change
  udevadm trigger --subsystem-match=platform-profile --action=change

  # --- a unit de usuario do agente
  install -d /usr/lib/systemd/user
  install -m 644 "${RAIZ}/packaging/systemd/nexus-sense-agent.service" \
    /usr/lib/systemd/user/nexus-sense-agent.service
  systemctl daemon-reload
  # --global habilita para todo usuario sem precisar de sessao ativa.
  systemctl --global enable nexus-sense-agent.service

  refresh_desktop_database
  echo -e "${GREEN}Nexus Sense instalado.${NC}"
  return 0
}

configure_nitro_button() {
  echo -e "${YELLOW}Configuring Nitro/PredatorSense Button Hardware Code...${NC}"

  # Ask user if they want to setup the key with 10 second timeout.
  # Default to No so installs/updates do not silently add a keyboard hook service.
  # Predator machines have the same dedicated button (the PredatorSense key) —
  # it even sends the same code as the Nitro key on the models tested so far.
  #
  # install_nitro_key_hwdb runs before this and usually already makes the
  # button open DAMX, without any daemon. When it did, say so: this service
  # would duplicate working behaviour at a real cost -- it runs as root and
  # reads every key on the keyboard, passwords included. It stays available
  # for environments with no global shortcuts, but nobody should install it
  # by accident.
  if [ "${NITRO_KEY_BOUND:-0}" = "1" ]; then
    echo -e "${GREEN}The button already opens Nexus Sense through a desktop shortcut.${NC}"
    echo -e "${BLUE}The detection service below is an alternative for desktops${NC}"
    echo -e "${BLUE}without global shortcuts. It runs as root and watches every${NC}"
    echo -e "${BLUE}key on the keyboard, so install it only if the shortcut did${NC}"
    echo -e "${BLUE}not work for you.${NC}"
    echo -e "${YELLOW}Install the key detection service anyway? (y/N) - Waiting 10 seconds...${NC}"
  else
    echo -e "${YELLOW}Do you want to setup your Nitro/PredatorSense Key? (y/N) - Waiting 10 seconds...${NC}"
  fi
  read -t 10 -n 1 -r response
  
  # Default to No if timeout or empty response
  if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
    echo -e "\n${BLUE}No response detected. Skipping Nitro button setup.${NC}"
    response="N"
  fi

  # Check if user wants to skip
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Skipping button configuration. You can run setup again later to enable it.${NC}"
    return 0
  fi

  if ! command -v evtest &> /dev/null; then
    echo -e "${BLUE}Installing evtest for hardware detection...${NC}"
    if command -v apt-get &> /dev/null; then
      apt-get update && apt-get install -y evtest
    elif command -v dnf &> /dev/null; then
      dnf install -y evtest
    elif command -v pacman &> /dev/null; then
      pacman -S --noconfirm --needed evtest
    else
      echo -e "${RED}Could not install evtest automatically. Install it with your package manager and re-run setup.${NC}"
      return 1
    fi
  fi

  DEVICE=$(grep -A 5 -B 5 "AT Translated Set 2 keyboard" /proc/bus/input/devices | grep -m 1 "event" | sed 's/.*event\([0-9]\+\).*/\/dev\/input\/event\1/')

  # Codigo de reserva, usado quando a captura falha. Depende do
  # mapeamento em vigor: com a regra hwdb deste instalador o botao emite
  # prog1 (148); sem ela, a entrada generica Acer do systemd o entrega
  # como presentation (425). Cravar um dos dois daria o errado na metade
  # dos casos.
  FALLBACK_KEY=425
  if [ -n "$DEVICE" ] && udevadm info "$DEVICE" 2>/dev/null | grep -q 'KEYBOARD_KEY_f5=prog1'; then
    FALLBACK_KEY=148
  fi

  mkdir -p /etc/damx

  if [ -z "$DEVICE" ]; then
    echo -e "${RED}Error: Keyboard hardware not found! Using fallback code ${FALLBACK_KEY}.${NC}"
    echo "NITRO_KEY=$FALLBACK_KEY" > /etc/damx/nitro_key.conf
    return 1
  fi

  echo -e "${GREEN}Keyboard detected at: $DEVICE${NC}"
  echo -e "${YELLOW}>>> PLEASE PRESS YOUR NITRO / PREDATORSENSE BUTTON NOW (Waiting 30 seconds)... <<<${NC}"

  # On both Nitro and Predator EC keyboards the button arrives as scancode
  # 0xf5, which the kernel maps to keycode 425 unless an hwdb quirk remaps
  # it (some models get prog1/148). Capturing beats hardcoding either one.
  CAPTURED_CODE=$(timeout 30 evtest "$DEVICE" | grep -m 1 "type 1 (EV_KEY).*value 1" | sed -n 's/.*code \([0-9]*\).*/\1/p')

  if [ -n "$CAPTURED_CODE" ]; then
    echo -e "${GREEN}Success! Button code captured: ${CAPTURED_CODE}${NC}"
    echo "NITRO_KEY=$CAPTURED_CODE" > /etc/damx/nitro_key.conf
  else
    echo -e "${RED}Timeout or no key detected. Falling back to code ${FALLBACK_KEY}.${NC}"
    echo -e "${YELLOW}If you DID press the button: key remappers like keyd or kmonad grab the${NC}"
    echo -e "${YELLOW}keyboard exclusively, so this capture (and the detection service) never${NC}"
    echo -e "${YELLOW}sees the key. Stop the remapper and re-run setup, or bind the key in the${NC}"
    echo -e "${YELLOW}remapper's own config instead.${NC}"
    echo "NITRO_KEY=$FALLBACK_KEY" > /etc/damx/nitro_key.conf
  fi
  
  # Install NitroKeyDetection.sh as a service
  install_nitro_service
}

detect_desktop_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "$SUDO_USER"
    return 0
  fi

  if command -v loginctl >/dev/null 2>&1; then
    local session_user
    session_user=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3 != "root" && $3 != "gdm" { print $3; exit }')
    if [ -n "$session_user" ] && id -u "$session_user" >/dev/null 2>&1; then
      echo "$session_user"
      return 0
    fi
  fi

  awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" { print $1; exit }' /etc/passwd
}

install_nitro_service() {
  echo -e "${YELLOW}Installing Nitro Key Detection Service...${NC}"

  NITRO_SCRIPT="${RAIZ}/packaging/scripts/nitro-key-detection.sh"
  TARGET_USER=$(detect_desktop_user)

  if [ -z "$TARGET_USER" ] || ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo -e "${RED}Error: Could not determine desktop user for Nitro key launcher.${NC}"
    return 1
  fi

  echo -e "${BLUE}The button will launch Nexus Sense for user: ${TARGET_USER}${NC}"
  
  # Check if NitroKeyDetection.sh exists
  if [ ! -f "$NITRO_SCRIPT" ]; then
    echo -e "${RED}Error: nitro-key-detection.sh not found at ${NITRO_SCRIPT}${NC}"
    return 1
  fi
  
  # Make the script executable
  chmod +x "$NITRO_SCRIPT"
  
  # Copy script to /usr/local/bin
  cp "$NITRO_SCRIPT" /usr/local/bin/
  chmod +x "/usr/local/bin/nitro-key-detection.sh"
  
  # Create systemd service file
  cat > /etc/systemd/system/nitro-key-detection.service << EOF
[Unit]
Description=Nitro/PredatorSense Key Detection Service
After=multi-user.target
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nitro-key-detection.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
User=root
Environment=DAMX_TARGET_USER=${TARGET_USER}

[Install]
WantedBy=multi-user.target
EOF

  # Reload systemd, enable and start the service
  systemctl daemon-reload
  systemctl enable nitro-key-detection.service
  systemctl start nitro-key-detection.service
  
  # Check if service is running
  if systemctl is-active --quiet nitro-key-detection.service; then
    echo -e "${GREEN}✓ Nitro Key Detection Service installed and running successfully!${NC}"
    echo -e "${GREEN}Service status: $(systemctl status nitro-key-detection.service --no-pager | grep Active)${NC}"
  else
    echo -e "${RED}✗ Service installation failed. Checking logs...${NC}"
    journalctl -u nitro-key-detection.service -n 10 --no-pager
    return 1
  fi
  
  echo -e "${BLUE}Service commands:${NC}"
  echo -e "  Start: systemctl start nitro-key-detection.service"
  echo -e "  Stop:  systemctl stop nitro-key-detection.service"
  echo -e "  Status: systemctl status nitro-key-detection.service"
  echo -e "  Logs:  journalctl -u nitro-key-detection.service -f"
}

perform_install() {
  local skip_drivers=$1
  local is_update=$2

  # If this is an update/reinstall, perform cleanup first
  if [ "$is_update" = true ]; then
    echo -e "${BLUE}Performing cleanup before installation...${NC}"
    comprehensive_cleanup
    echo ""
  else
    # For fresh installs, still check for legacy installations
    cleanup_legacy_installation
    echo ""
  fi

  # Install components
  if [ "$skip_drivers" = false ]; then
    install_drivers
    DRIVER_RESULT=$?
    if [ $DRIVER_RESULT -ne 0 ]; then
      echo -e "${RED}Driver installation failed; daemon and GUI installation were not attempted.${NC}"
      return $DRIVER_RESULT
    fi
  else
    echo -e "${YELLOW}Skipping driver installation as requested.${NC}"
    DRIVER_RESULT=0
  fi

  install_nexus_sense
  NEXUS_RESULT=$?

  # O remap de keycode e do teclado, nao do driver: precisa rodar mesmo
  # quando a instalacao pula os drivers (opcao 2 do menu), e antes da
  # captura em configure_nitro_button -- senao ela grava o keycode antigo.
  install_nitro_key_hwdb

  #Setup NitroButton shortcut
  configure_nitro_button

  # Check if all installations were successful
  if [ $DRIVER_RESULT -eq 0 ] && [ $NEXUS_RESULT -eq 0 ]; then
    echo -e "${GREEN}Nexus Sense installation completed successfully!${NC}"
    echo -e "You can now run the GUI using the ${BLUE}nexus-sense${NC} command or from your application launcher."

    # O agente e servico de usuario: nao ha status de sistema a mostrar.
    echo ""
    echo -e "${BLUE}Agent status:${NC}"
    systemctl --user status nexus-sense-agent.service --no-pager -l 2>/dev/null || \
      echo "o agente é serviço de usuário: confira com 'systemctl --user status nexus-sense-agent'"
    pause
    return 0
  else
    echo -e "${RED}Some components failed to install. Please check the errors above.${NC}"
    pause
    return 1
  fi
}

uninstall() {
  echo -e "${YELLOW}Uninstalling Nexus Sense...${NC}"
  comprehensive_cleanup
  echo -e "${GREEN}Nexus Sense uninstalled successfully!${NC}"
  pause
  return 0
}

# Function to check system compatibility
check_system() {
  echo -e "${BLUE}Checking system compatibility...${NC}"

  # Check if systemd is available
  if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}Error: systemd is required but not found on this system.${NC}"
    return 1
  fi

  # Check if we're on a supported distribution
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Detected OS: $PRETTY_NAME"
  fi

  echo -e "${GREEN}System compatibility check passed.${NC}"
  return 0
}

# Relata o que este projeto instala.
#
# Ate 2026-09-11 esta opcao procurava damx-daemon.service, que saiu do
# projeto na virada para o agente proprio. Ela respondia "nao instalado"
# para quem tinha tudo funcionando -- pior que nao existir, porque mandava
# reinstalar sem motivo.
print_status() {
  local ok="${GREEN}sim${NC}" nao="${RED}nao${NC}"

  # O modulo e o sysfs: se o driver nao vinculou, nada mais importa.
  if lsmod | grep -q '^nexus_sense'; then
    echo -e "  modulo nexus_sense carregado ............. $ok"
  else
    echo -e "  modulo nexus_sense carregado ............. $nao"
  fi
  if [ -d /sys/devices/platform/acer-wmi/nitro_sense ] \
     || [ -d /sys/devices/platform/acer-wmi/predator_sense ]; then
    echo -e "  sysfs populado ........................... $ok"
  else
    echo -e "  sysfs populado ........................... $nao"
  fi

  # DKMS: e o que faz o modulo sobreviver a atualizacao de kernel.
  local ver registrados
  ver=$(driver_version 2>/dev/null || true)
  if [ -n "$ver" ]; then
    registrados=$(dkms status "nexus_sense/${ver}" 2>/dev/null | grep -c installed)
    echo -e "  DKMS nexus_sense/${ver} ................ ${registrados} kernel(s)"
  fi

  # A unit de sistema so descarrega o modulo no desligamento.
  if systemctl is-enabled --quiet nexus_sense.service 2>/dev/null; then
    echo -e "  nexus_sense.service (desligamento) ....... $ok"
  else
    echo -e "  nexus_sense.service (desligamento) ....... $nao"
  fi

  # O agente e servico de USUARIO: consultar como root nao o enxerga.
  local u uid
  u=$(detect_desktop_user)
  if [ -n "$u" ] && uid=$(id -u "$u" 2>/dev/null); then
    if runuser -u "$u" -- env XDG_RUNTIME_DIR="/run/user/${uid}" \
         systemctl --user is-active --quiet nexus-sense-agent.service 2>/dev/null; then
      echo -e "  nexus-sense-agent (usuario ${u}) ..... $ok"
    else
      echo -e "  nexus-sense-agent (usuario ${u}) ..... $nao"
    fi
  fi

  # Os dois lancadores.
  [ -x /usr/bin/nexus-sense ] \
    && echo -e "  /usr/bin/nexus-sense ..................... $ok" \
    || echo -e "  /usr/bin/nexus-sense ..................... $nao"
}

main_menu() {
  # Perform initial system check
  if ! check_system; then
    echo -e "${RED}System compatibility check failed. Exiting.${NC}"
    pause
    exit 1
  fi

  while true; do
    print_banner

    echo -e "Please select an option:"
    echo -e "  ${GREEN}1${NC}) Install Nexus Sense (complete)"
    echo -e "  ${GREEN}2${NC}) Install Nexus Sense (without drivers)"
    echo -e "  ${GREEN}3${NC}) Uninstall Nexus Sense"
    echo -e "  ${GREEN}4${NC}) Reinstall/Update Nexus Sense (recommended for upgrades)"
    echo -e "  ${GREEN}5${NC}) Check service status"
    echo -e "  ${GREEN}q${NC}) Quit"
    echo ""

    read -p "Enter your choice [1-5 or q]: " choice

    case $choice in
      1)
        print_banner
        echo -e "${BLUE}Starting complete installation...${NC}"
        perform_install false false
        ;;
      2)
        print_banner
        echo -e "${BLUE}Starting installation without drivers...${NC}"
        perform_install true false
        ;;
      3)
        print_banner
        echo -e "${BLUE}Starting uninstallation...${NC}"
        uninstall
        ;;
      4)
        print_banner
        echo -e "${BLUE}Starting reinstallation/update...${NC}"
        echo -e "${YELLOW}This will completely remove the existing installation before installing the new version.${NC}"
        perform_install false true
        ;;
      5)
        print_banner
        echo -e "${BLUE}Checking Nexus Sense status...${NC}"
        echo ""
        print_status
        echo ""
        pause
        ;;
      q|Q)
        echo -e "${BLUE}Exiting installer. Goodbye!${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        sleep 2
        ;;
    esac
  done
}

# Executar abre o menu; importar expõe as funções para atualização e testes
# sem iniciar uma interface interativa.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  check_root "$@"
  main_menu
  exit 0
fi
