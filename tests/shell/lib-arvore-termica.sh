#!/bin/bash
# Apoio dos testes do ensaio termico: a arvore de mentira, o "EC" que faz a
# rotacao seguir o fan_speed, e as funcoes que lancam o roteiro contra ela.
#
# Nao e um teste -- o run-all so roda test-*.sh. Quem o usa o importa com
# `source`, depois de definir S (o roteiro) e antes de qualquer caso:
#     tests/shell/test-ensaio-termico.sh       o E2 e as protecoes comuns
#     tests/shell/test-ensaio-termico-e3.sh    o E3
#     tests/shell/test-ensaio-termico-curva.sh os ensaios da curva (E-C2, E-C3, E-C5)
#
# Nada aqui toca em /sys: o roteiro recebe ENSAIO_RAIZ. Os indices de hwmon e
# de zona termica sao embaralhados de proposito: o roteiro tem de achar tudo
# pelo nome (armadilha 19).
#
# O que fica para quem importa: $T (o tmpdir, apagado na saida), $D (a arvore
# do caso corrente, posta por `nova`), $PID (o roteiro lancado por `lanca`),
# $fail, ok e falha.

[ -f "$S" ] || { echo "ERRO alvo ausente: $S"; exit 3; }
[ -x "$S" ] || { echo "ERRO alvo ausente: $S nao e executavel"; exit 3; }
for c in setsid awk sort mktemp env; do
    command -v "$c" > /dev/null 2>&1 || { echo "ERRO alvo ausente: $c"; exit 3; }
done
# O caso do SIGINT precisa devolver o sinal ao padrao: um processo lancado
# em segundo plano por um shell sem controle de jobs nasce com ele ignorado.
env --default-signal=INT true 2> /dev/null \
    || { echo "ERRO alvo ausente: env --default-signal (coreutils 8.31 ou mais novo)"; exit 3; }

T=$(mktemp -d)
ECS=()
limpa() {
    local p
    for p in "${ECS[@]}"; do kill "$p" 2> /dev/null; done
    rm -rf "$T"
}
trap limpa EXIT

# fail e lido por quem importa este arquivo; daqui o shellcheck nao ve o uso.
# shellcheck disable=SC2034
fail=0
ok()    { echo "  OK    $1"; }
# shellcheck disable=SC2034
falha() { echo "  FALHA $1"; fail=1; }

# ─── a arvore de mentira ────────────────────────────────────────────
poe() {      # troca atomica: quem le nunca pega o arquivo vazio
    printf '%s\n' "$2" > "$1.novo" && mv "$1.novo" "$1"
}

monta() {    # $1 = raiz da arvore
    local d=$1 h=$1/sys/class/hwmon z=$1/sys/class/thermal n
    mkdir -p "$h"/hwmon{2,3,7,11,40} "$z"/thermal_zone{0,2,4,6,9} \
        "$d/sys/class/power_supply/BAT1" "$d/sys/class/power_supply/ACAD" \
        "$d/sys/devices/platform/acer-wmi/nitro_sense" "$d/sys/firmware/acpi" \
        "$d/sys/devices/system/cpu/cpu0/thermal_throttle" \
        "$d/sys/devices/system/cpu/cpu0/cpufreq" "$d/proc" "$d/bin" "$d/run" "$d/state"

    echo BAT1 > "$h/hwmon2/name"
    echo acer > "$h/hwmon7/name"
    n=1
    for par in "CPU:48000" "GPU:47000" "External 2:46000"; do
        echo "${par%%:*}" > "$h/hwmon7/temp${n}_label"
        echo "${par##*:}" > "$h/hwmon7/temp${n}_input"
        n=$((n + 1))
    done
    echo CPU > "$h/hwmon7/fan1_label"; echo 2300 > "$h/hwmon7/fan1_input"
    echo GPU > "$h/hwmon7/fan2_label"; echo 2000 > "$h/hwmon7/fan2_input"

    echo coretemp > "$h/hwmon11/name"
    # O pacote NAO e o temp1: o roteiro tem de ir pelo rotulo.
    echo "Core 0" > "$h/hwmon11/temp1_label";       echo 44000 > "$h/hwmon11/temp1_input"
    echo "Package id 0" > "$h/hwmon11/temp4_label"; echo 45000 > "$h/hwmon11/temp4_input"
    echo 0 > "$h/hwmon11/temp4_crit_alarm"

    for n in 3 40; do
        echo nvme > "$h/hwmon$n/name"
        echo Composite > "$h/hwmon$n/temp1_label"; echo 42000 > "$h/hwmon$n/temp1_input"
    done

    echo acpitz > "$z/thermal_zone0/type"; echo 48000 > "$z/thermal_zone0/temp"
    echo SEN4 > "$z/thermal_zone2/type";   echo 46050 > "$z/thermal_zone2/temp"
    echo SEN2 > "$z/thermal_zone4/type";   echo 46050 > "$z/thermal_zone4/temp"
    echo SEN5 > "$z/thermal_zone6/type";   echo 46050 > "$z/thermal_zone6/temp"
    echo SEN3 > "$z/thermal_zone9/type";   echo 46050 > "$z/thermal_zone9/temp"

    echo 2800000 > "$d/sys/class/power_supply/BAT1/charge_now"
    echo 3500000 > "$d/sys/class/power_supply/BAT1/charge_full"
    echo 0 > "$d/sys/class/power_supply/BAT1/current_now"
    echo 1 > "$d/sys/class/power_supply/ACAD/online"
    echo "0,0" > "$d/sys/devices/platform/acer-wmi/nitro_sense/fan_speed"
    echo balanced-performance > "$d/sys/firmware/acpi/platform_profile"
    echo 0 > "$d/sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count"
    echo 0 > "$d/sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_total_time_ms"
    echo 2400000 > "$d/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    echo "0.50 0.40 0.30 1/100 1" > "$d/proc/loadavg"
    echo "123.45 400.00" > "$d/proc/uptime"
    echo "maximum_mode = false" > "$d/config.toml"
    echo balance_performance > "$d/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"
    echo balanced > "$d/ppd"
    mkdir -p "$d/sys/power/suspend_stats" "$d/proc/sys/kernel/random"
    echo 3 > "$d/sys/power/suspend_stats/success"
    echo 11111111-2222-3333-4444-555555555555 > "$d/proc/sys/kernel/random/boot_id"

    # O busctl de mentira: o perfil de energia mora no arquivo ppd, e a
    # preferencia de energia da CPU o segue, como faz o daemon. Cada chamada
    # fica em busctl.log. Com o arquivo ppd_recusa, a escrita e recusada.
    cat > "$d/bin/busctl" << FIM
#!/bin/bash
echo "\$*" >> "$d/busctl.log"
case "\$*" in
    *" get-property "*" ActiveProfile")
        printf '{"type":"s","data":"%s"}\n' "\$(cat "$d/ppd")" ;;
    *" set-property "*" ActiveProfile s "*)
        [ -e "$d/ppd_recusa" ] && exit 1
        v=\${!#}
        case "\$v" in
            performance) e=performance ;;
            balanced) e=balance_performance ;;
            power-saver) e=power ;;
            *) exit 1 ;;
        esac
        printf '%s\n' "\$v" > "$d/ppd.novo" && mv "$d/ppd.novo" "$d/ppd"
        e_=$d/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
        printf '%s\n' "\$e" > "\$e_.novo" && mv "\$e_.novo" "\$e_" ;;
    *) exit 1 ;;
esac
FIM
    # O systemctl de mentira: so as perguntas que o E-C5 faz a unit do
    # agente. O pid sai de agente.pid; o guarda, de unit.execstoppost,
    # unit.watchdog e unit.runtimedirectory. Sem eles: agente fora do ar e
    # unit sem guarda.
    cat > "$d/bin/systemctl" << FIM
#!/bin/bash
echo "\$*" >> "$d/systemctl.log"
case "\$*" in
    *"-p MainPID "*) cat "$d/agente.pid" 2> /dev/null || echo 0 ;;
    *"-p ExecStopPost "*) cat "$d/unit.execstoppost" 2> /dev/null ;;
    *"-p WatchdogUSec "*) cat "$d/unit.watchdog" 2> /dev/null || echo 0 ;;
    *"-p RuntimeDirectory "*) cat "$d/unit.runtimedirectory" 2> /dev/null ;;
    *) exit 1 ;;
esac
FIM

    # O ps de mentira: os "processos" sao as linhas de um arquivo.
    : > "$d/processos"
    printf '#!/bin/bash\ncat "%s/processos"\n' "$d" > "$d/bin/ps"
    # Um escritor que recusa o automatico, para o caso do 100,100.
    printf '#!/bin/bash\n[ "$1" = "0,0" ] && exit 1\nprintf "%%s\\n" "$1" > "$2"\n' > "$d/bin/recusa-zero"
    # A carga de mentira do E3: nao queima CPU, so levanta a bandeira que o
    # EC de mentira le para esquentar. Sai com o sinal, e abaixa a bandeira.
    cat > "$d/bin/carga-falsa" << FIM
#!/bin/bash
: > "$d/carga_ligada"
trap 'rm -f "$d/carga_ligada"; exit 0' TERM INT EXIT
while :; do sleep 0.05; done
FIM
    chmod +x "$d/bin/ps" "$d/bin/recusa-zero" "$d/bin/carga-falsa" "$d/bin/busctl" "$d/bin/systemctl"
}

FAN_DE() { echo "$1/sys/devices/platform/acer-wmi/nitro_sense/fan_speed"; }

# O "EC": faz a rotacao seguir o fan_speed -- e, quando ha carga de mentira no
# ar, esquenta. $1 = arvore, $2 = o temperamento:
#   normal       automatico em 2300/2000 frio, subindo com o pacote; manual
#                gira 600 + 50 por ponto, e o EC obedece ate o fim
#   surdo        ignora o manual: a rotacao nao sai do automatico
#   alto         depois de um manual, o automatico volta 1400 rpm acima de
#                antes -- e o que a maquina de verdade faz: o automatico nao
#                tem um repouso fixo (medido em 2026-10-10: 2200 a 3800 rpm)
#   teto         de 50% para cima gira tudo igual
#   gruda        obedece ao manual e nao larga: fan_speed volta a 0,0 e a
#                rotacao fica onde o manual a deixou
#   retoma       quente, passa por cima do manual: a rotacao vai para a
#                curva do automatico com fan_speed ainda dizendo o manual
#   estoura      manual fraco com carga: a zona SEN4 sobe ate passar do limite
#   auto_parado  o automatico nao sobe com a temperatura
#   curvas       o automatico tem duas curvas, como a maquina (docs/plano-curva.md,
#                secao 2.1): com o modo maximo ligado ele gira 600 rpm acima.
#                Com carga ou jogo a frequencia e a GPU pelo EC seguem a
#                rotacao -- pouco: o maximo do firmware compra 1,2% e 0,6 C
#   ganho        o mesmo, e a rotacao compra mais: 5,7% e 3 C
#   presa        como curvas, mas a curva alta fica depois de o modo desligar
# Em qualquer temperamento, com o arquivo ec_larga o EC larga o manual: a
# rotacao vai para o automatico com fan_speed ainda dizendo o manual. Uma
# escrita nova em fan_speed (mais nova que o ec_larga) o reaplica.
# A carga de mentira e bin/carga-falsa: enquanto existir o arquivo
# carga_ligada, o pacote sobe ate 92 C; sem ele, desce ate 45.
# Um "jogo" (uma linha no arquivo processos) esquenta igual, e esquenta
# tambem a zona SEN4, que e a do lado da GPU: ate 87 C com a ventoinha alta,
# ate 89 com ela baixa -- e sem parar de subir, no temperamento estoura.
ec_falso() {
    local f h hc z v c g x fs='' manual=0 r1 r2 a1 a2 pac=45000 s4=46050 jogo carga alvo
    local u1='' u2='' up=45000 us=46050 alta=0 presa=0 cfg hz uh='' gpu ug='' passo
    f=$(FAN_DE "$1"); h="$1/sys/class/hwmon/hwmon7"
    hc="$1/sys/class/hwmon/hwmon11"; z="$1/sys/class/thermal/thermal_zone2"
    while [ -d "$h" ]; do
        v=
        read -r v < "$f"
        case "$v" in *,*) fs=$v ;; esac    # pego no meio de uma escrita: fica o de antes
        if [ -z "$fs" ]; then sleep 0.02; continue; fi
        c=${fs%,*}; g=${fs#*,}

        jogo=0; carga=0
        [ -s "$1/processos" ] && jogo=1
        [ -e "$1/carga_ligada" ] && carga=1
        # Nos temperamentos da curva o pacote anda tres vezes mais depressa:
        # o estagio do E-C2 mede um patamar, e ele tem de chegar logo.
        passo=4000
        case "$2" in curvas|ganho|presa) passo=12000 ;; esac
        if [ "$jogo" = 1 ] || [ "$carga" = 1 ]; then
            [ "$pac" -lt 92000 ] && pac=$((pac + passo))
        else
            [ "$pac" -gt 45000 ] && pac=$((pac - passo))
            [ "$pac" -lt 45000 ] && pac=45000
        fi

        a1=$((2300 + (pac - 45000) / 20)); a2=$((2000 + (pac - 45000) / 22))
        if [ "$2" = auto_parado ]; then a1=2300; a2=2000; fi
        case "$2" in
            curvas|ganho|presa)
                cfg=; read -r cfg < "$1/config.toml"
                alta=0
                [ "$cfg" = "maximum_mode = true" ] && { alta=1; presa=1; }
                [ "$2" = presa ] && [ "$presa" = 1 ] && alta=1
                [ "$alta" = 1 ] && { a1=$((a1 + 600)); a2=$((a2 + 600)); } ;;
        esac
        if [ "$2" = surdo ]; then
            r1=$a1; r2=$a2
        elif [ "$fs" = "0,0" ]; then
            r1=$a1; r2=$a2
            if [ "$manual" = 1 ]; then
                [ "$2" = alto ] && { r1=$((a1 + 1400)); r2=$((a2 + 1300)); }
                [ "$2" = gruda ] && { r1=$u1; r2=$u2; }
            fi
        else
            manual=1
            x=$c; [ "$2" = teto ] && [ "$x" -ge 50 ] && x=95
            r1=$((600 + x * 50))
            x=$g; [ "$2" = teto ] && [ "$x" -ge 50 ] && x=95
            r2=$((500 + x * 45))
            # Quente, o EC larga o manual e volta para a curva dele.
            [ "$2" = retoma ] && [ "$pac" -ge 88000 ] && { r1=$a1; r2=$a2; }
        fi
        # Escrever fan_speed de novo, mesmo com o mesmo valor, reaplica o
        # manual -- como o firmware de verdade depois da suspensao.
        [ -e "$1/ec_larga" ] && [ "$f" -nt "$1/ec_larga" ] && rm -f "$1/ec_larga"
        [ -e "$1/ec_larga" ] && { r1=$a1; r2=$a2; }

        # SEN4 anda 3 C por volta ate o alvo. "Fraca" e a ventoinha em manual
        # abaixo de 2600 rpm.
        alvo=46050
        x=0; [ "$fs" != "0,0" ] && [ "$r1" -lt 2600 ] && x=1
        if [ "$jogo" = 1 ]; then
            alvo=87050
            [ "$x" = 1 ] && alvo=89050
        fi
        if [ "$2" = estoura ] && [ "$x" = 1 ] && { [ "$jogo" = 1 ] || [ "$carga" = 1 ]; }; then
            alvo=120050
        fi
        if [ "$s4" -lt "$alvo" ]; then
            s4=$((s4 + 3000)); [ "$s4" -gt "$alvo" ] && s4=$alvo
        elif [ "$s4" -gt "$alvo" ]; then
            s4=$((s4 - 3000)); [ "$s4" -lt "$alvo" ] && s4=$alvo
        fi

        # So escreve o que mudou: parado, o EC de mentira nao gasta um fork,
        # e nao desfaz a temperatura que um caso do teste plantou a mao.
        if [ "$r1" != "$u1" ]; then poe "$h/fan1_input" "$r1"; u1=$r1; fi
        if [ "$r2" != "$u2" ]; then poe "$h/fan2_input" "$r2"; u2=$r2; fi
        if [ "$pac" != "$up" ]; then
            poe "$hc/temp4_input" "$pac"; poe "$h/temp1_input" $((pac - 1000)); up=$pac
        fi
        if [ "$s4" != "$us" ]; then poe "$z/temp" "$s4"; us=$s4; fi
        # Nos temperamentos da curva, a frequencia (com carga ou jogo) e a GPU
        # pelo EC (com jogo) seguem a rotacao da CPU.
        case "$2" in
            curvas|ganho|presa)
                hz=2400000; gpu=47000
                if [ "$jogo" = 1 ] || [ "$carga" = 1 ]; then
                    if [ "$2" = ganho ]; then hz=$((r1 * 600)); else hz=$((2000000 + r1 * 100)); fi
                fi
                if [ "$jogo" = 1 ]; then
                    if [ "$2" = ganho ]; then gpu=$((120000 - r1 * 10)); else gpu=$((90000 - r1 * 2)); fi
                fi
                if [ "$hz" != "$uh" ]; then poe "$1/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" "$hz"; uh=$hz; fi
                if [ "$gpu" != "$ug" ]; then poe "$h/temp2_input" "$gpu"; ug=$gpu; fi ;;
        esac
        sleep 0.02
    done 2> /dev/null
}

nova() {     # $1 = nome do caso, $2 = modo do EC -> a arvore fica em $D
    local p
    for p in "${ECS[@]}"; do kill "$p" 2> /dev/null; done
    ECS=()
    D="$T/$1"
    monta "$D"
    ec_falso "$D" "${2:-normal}" &
    ECS+=("$!")
}

roda() {     # $1 = arvore; o resto e o comando. Em primeiro plano.
    local d=$1
    shift
    ENSAIO_RAIZ="$d" ENSAIO_CONFIG="$d/config.toml" PATH="$d/bin:$PATH" \
        ENSAIO_BUSCTL="$d/bin/busctl" ENSAIO_SYSTEMCTL="$d/bin/systemctl" \
        XDG_RUNTIME_DIR="$d/run" XDG_STATE_HOME="$d/state" \
        ENSAIO_PASSO="${PASSO:-0.05}" ENSAIO_PASSO_VIGIA="${PASSO_VIGIA:-0.05}" \
        ENSAIO_ASSENTA=2 ENSAIO_LEITURAS=2 "$@" > "$d/saida.txt" 2>&1
}

lanca() {    # o mesmo, em segundo plano. O exec faz PID ser o do roteiro, e
             # nao o de um subshell: e nele que os sinais tem de chegar.
    local d=$1
    shift
    (
        ENSAIO_RAIZ="$d" ENSAIO_CONFIG="$d/config.toml" PATH="$d/bin:$PATH" \
            ENSAIO_BUSCTL="$d/bin/busctl" ENSAIO_SYSTEMCTL="$d/bin/systemctl" \
            XDG_RUNTIME_DIR="$d/run" XDG_STATE_HOME="$d/state" \
            ENSAIO_PASSO="${PASSO:-0.05}" ENSAIO_PASSO_VIGIA="${PASSO_VIGIA:-0.05}" \
            ENSAIO_ASSENTA=2 ENSAIO_LEITURAS=2 exec "$@"
    ) > "$d/saida.txt" 2>&1 &
    # shellcheck disable=SC2034  # lido por quem importa este arquivo
    PID=$!
}

espera_fan() {   # $1 = arvore, $2 = valor, $3 = decimos de segundo
    local i
    for ((i = 0; i < $3; i++)); do
        [ "$(cat "$(FAN_DE "$1")" 2> /dev/null)" = "$2" ] && return 0
        sleep 0.1
    done
    return 1
}

fan() { cat "$(FAN_DE "$1")" 2> /dev/null; }

confere() {  # $1 = descricao, $2 = rc visto, $3 = rc esperado, $4 = fan esperado
    if [ "$2" = "$3" ] && [ "$(fan "$D")" = "$4" ]; then
        ok "$1"
    else
        falha "$1: saiu com $2 (esperado $3), fan_speed '$(fan "$D")' (esperado '$4') $(grep -h -m1 '^ENCERRADO' "$D/saida.txt" 2> /dev/null)"
    fi
}
