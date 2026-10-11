#!/bin/bash
# O observador passivo da medicao termica -- docs/plano-termico.md, secao 13.
#
# So le, sem root, e nao chama o nvidia-smi (armadilha 20). Uma linha por
# amostra num TSV: bateria, perfil, fan_speed, as duas rotacoes, as
# temperaturas do EC, o pacote, as zonas SEN*, o throttle, a frequencia, o
# estado da dGPU, se ha jogo aberto e se o modo maximo esta pedido.
#
# Uso:   tests/hardware/observador.sh <arquivo.tsv> [intervalo_s] [duracao_s]
#
# E o que se poe no ar ANTES de qualquer ensaio, e de qualquer leitura
# longa: o que a maquina fez enquanto ninguem olhava nao se mede depois.
# Grave fora do tmpfs -- ~/.local/state/nexus-sense/ -- e num arquivo so
# desta rodada: ele SOBRESCREVE o que houver no caminho dado.
#
# Tres avisos de quem ja o usou:
#   - o nome do arquivo nao e a condicao. Um observador que segue no ar
#     atravessa ensaios, trocas de modo e o fim do jogo; a condicao esta nas
#     colunas, linha a linha (tests/hardware/recorta-tracos.py);
#   - a coluna jogo conta processos com o nome em OBS_JOGO. O padrao e o do
#     jogo de 2026-10-10; outro jogo pode ter outro nome, e a coluna vira
#     zero calada;
#   - a bateria se le por charge_now. O status diz Charging com a carga
#     caindo (armadilha 36).
#
# Vivia no scratchpad, que e tmpfs, e sumiu com um reinicio em 2026-10-10.
set -u

[ $# -ge 1 ] || { sed -n '2,11p' "$0"; exit 2; }
out=$1; passo=${2:-5}; dur=${3:-3600}
JOGO=${OBS_JOGO:-GameThread}

acha_hwmon() {            # armadilha 19: pelo nome, na hora de usar
    local d
    for d in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && { echo "$d"; return; }
    done
}
acha_pacote() {
    local l
    for l in "$1"/temp*_label; do
        [ "$(cat "$l" 2>/dev/null)" = "Package id 0" ] && { echo "${l%_label}_input"; return; }
    done
}
acha_dgpu() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
        case "$(cat "$d/class" 2>/dev/null)" in 0x03*) echo "$d"; return ;; esac
    done
}
zona() {
    local z
    for z in /sys/class/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { cat "$z/temp" 2>/dev/null; return; }
    done
    echo NA
}
le() { cat "$1" 2>/dev/null || echo NA; }
freq_media() {
    awk '{s+=$1; n++} END {if (n) printf "%d", s/n/1000; else print "NA"}' \
        /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null
}

NS=/sys/devices/platform/acer-wmi/nitro_sense
TT=/sys/devices/system/cpu/cpu0/thermal_throttle
BAT=/sys/class/power_supply/BAT1
CFG=${XDG_CONFIG_HOME:-$HOME/.config}/nexus-sense/config.toml

printf 'epoch\thora\tcap\tstatus\tacad\tcorrente_uA\tcharge_now\ttensao_uV\tperfil\tfan_speed\trpm_cpu\trpm_gpu\tec_cpu\tec_gpu\tec_ext2\tpacote\tsen2\tsen3\tsen4\tsen5\tacpitz\tthr_n\tthr_ms\tmhz\tdgpu\tload1\tjogo\tmaximo\n' > "$out" || exit 1
fim=$(( $(date +%s) + dur ))
while [ "$(date +%s)" -lt "$fim" ]; do
    acer=$(acha_hwmon acer); core=$(acha_hwmon coretemp)
    pac=$(acha_pacote "$core"); gpu=$(acha_dgpu)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date +%s)" "$(date +%T)" \
        "$(le "$BAT/capacity")" "$(le "$BAT/status")" \
        "$(le /sys/class/power_supply/ACAD/online)" \
        "$(le "$BAT/current_now")" "$(le "$BAT/charge_now")" "$(le "$BAT/voltage_now")" \
        "$(le /sys/firmware/acpi/platform_profile)" \
        "$(le "$NS/fan_speed")" \
        "$(le "$acer/fan1_input")" "$(le "$acer/fan2_input")" \
        "$(le "$acer/temp1_input")" "$(le "$acer/temp2_input")" "$(le "$acer/temp3_input")" \
        "$(le "$pac")" \
        "$(zona SEN2)" "$(zona SEN3)" "$(zona SEN4)" "$(zona SEN5)" "$(zona acpitz)" \
        "$(le "$TT/package_throttle_count")" "$(le "$TT/package_throttle_total_time_ms")" \
        "$(freq_media)" \
        "$(le "$gpu/power/runtime_status")" \
        "$(cut -d' ' -f1 /proc/loadavg)" \
        "$(ps -eo comm --no-headers | grep -cE "^(${JOGO})$")" \
        "$(grep -m1 '^maximum_mode' "$CFG" 2>/dev/null | tr -d ' ' | cut -d= -f2)" >> "$out"
    sleep "$passo"
done
