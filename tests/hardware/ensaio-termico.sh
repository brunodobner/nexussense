#!/bin/bash
# Ensaio termico da ventoinha manual -- docs/plano-termico.md.
#
# ESTE ROTEIRO ESCREVE EM fan_speed NA MAQUINA DE VERDADE. Nao faz parte da
# suite: quem o roda e uma pessoa, com o combinado da secao 9 do plano feito
# antes. O que a suite roda e tests/shell/test-ensaio-termico.sh, que exercita
# esta mesma logica contra uma arvore de mentira (ENSAIO_RAIZ).
#
# Uso:   tests/hardware/ensaio-termico.sh e2 [saida.tsv]
#        tests/hardware/ensaio-termico.sh e3 [saida.tsv]
#
#   e2   o mapa de porcentagem para rotacao, em repouso. Antes dele, dois
#        exercicios: o vigia (o roteiro leva kill -9 e outro processo devolve
#        a ventoinha) e o aborto (um limite rebaixado encerra na primeira
#        amostra). Nao esquenta a maquina.
#
#   e3   manual baixo com carga de CPU: ESQUENTA A MAQUINA DE PROPOSITO, ate
#        os limites da secao 7 do plano. Tres estagios -- automatico (o
#        controle positivo), manual a 30% e manual a 1% -- com a descida
#        gravada depois de cada um. Um estagio so roda se o anterior nao
#        abortou. A carga sao processos em laco, cada um debaixo de timeout:
#        a fonte de calor morre sozinha no prazo, com ou sem roteiro.
#
# O automatico nao tem uma rotacao de repouso: medido em 2026-10-10, ele vai
# de 2200 a 3800 rpm com a maquina parada, conforme o modo maximo e o que ela
# fez no minuto anterior. Por isso nada aqui cobra "a rotacao voltou a X". O
# que se cobra e a rotacao ter SAIDO do valor manual -- e os exercicios usam
# uma porcentagem alta, para a saida ter sentido conhecido (cai) e para o
# pior desfecho de um exercicio que falhe ser barulho, e nao calor.
#
# Quem devolve a ventoinha, em camadas (secao 8 do plano):
#   1. o trap deste roteiro, em EXIT, INT, TERM e HUP;
#   2. o vigia, em sessao propria (setsid), no ar antes da primeira escrita:
#      cobre kill -9, roteiro travado e prazo vencido;
#   3. no E3, o timeout de cada processo de carga: sem roteiro e sem vigia
#      a ventoinha fica em manual, mas o calor para sozinho;
#   4. voce: Ctrl-C, ou "Automatico" na janela. Se fan_speed aparecer com um
#      valor que o roteiro nao escreveu, ele para e NAO escreve por cima.
#
# Saidas:
#    0  terminou (no E3: nenhum estagio abortou num limite)
#    3  alvo ausente: sensor ou atributo que o ensaio exige
#   10  aborto por limite de temperatura (secao 7 do plano)
#   11  encerrado por condicao -- pessoa, bateria, tempo. A medicao nao conta
#   12  recusou comecar: a condicao de partida nao vale
#   13  controle positivo falhou: a rotacao nao acompanha a escrita
#   14  um dos dois exercicios falhou
#   15  nao conseguiu devolver 0,0 e deixou a ventoinha em 100,100
set -u

COD_ALVO=3; COD_LIMITE=10; COD_CONDICAO=11; COD_RECUSA=12
COD_CONTROLE=13; COD_EXERCICIO=14; COD_DEVOLUCAO=15

EU=$(readlink -f "$0")
R=${ENSAIO_RAIZ:-}                       # vazio na maquina; um tmpdir no teste

PASSO=${ENSAIO_PASSO:-1}                 # segundos entre amostras
ASSENTA=${ENSAIO_ASSENTA:-20}            # amostras de espera apos cada escrita
LEITURAS=${ENSAIO_LEITURAS:-5}           # amostras que contam, depois de assentar
PRAZO=${ENSAIO_PRAZO:-900}               # segundos; passou disso, encerra
PASSO_VIGIA=${ENSAIO_PASSO_VIGIA:-1}
FOLGA_VIGIA=${ENSAIO_FOLGA_VIGIA:-5}     # o prazo do vigia vem este tanto depois
VIGIA_MAX=${ENSAIO_VIGIA_MAX:-3}         # segundos para o vigia devolver
DRILL_P=${ENSAIO_DRILL_P:-95}            # porcentagem dos dois exercicios
QUEDA_RPM=${ENSAIO_QUEDA_RPM:-500}       # "a rotacao saiu do manual": cai isto
CONTROLE_RPM=${ENSAIO_CONTROLE_RPM:-500} # 100% tem de girar isto acima de 50%
PORCENTAGENS=${ENSAIO_PORCENTAGENS:-100 80 60 50 40 30 20 15 10 5 1}
JOGOS=${ENSAIO_JOGOS:-GameThread|wineserver}
CFG=${ENSAIO_CONFIG:-$HOME/.config/nexus-sense/config.toml}

# Limites de aborto, em milesimos de grau. Sao os da secao 7 do plano, fixados
# antes de medir; as variaveis existem para o exercicio do aborto e o teste.
LIM_PACOTE=${ENSAIO_LIM_PACOTE:-98000}                  # tres amostras seguidas
LIM_PACOTE_REPOUSO=${ENSAIO_LIM_PACOTE_REPOUSO:-85000}  # idem, so no E2
LIM_EC_CPU=${ENSAIO_LIM_EC_CPU:-99000}
LIM_EC_GPU=${ENSAIO_LIM_EC_GPU:-85000}
LIM_SEN2=${ENSAIO_LIM_SEN2:-81000}
LIM_SEN3=${ENSAIO_LIM_SEN3:-77000}
LIM_SEN4=${ENSAIO_LIM_SEN4:-91000}
LIM_SEN5=${ENSAIO_LIM_SEN5:-81000}
LIM_NVME=${ENSAIO_LIM_NVME:-75000}
LIM_CARGA=${ENSAIO_LIM_CARGA:-50}             # % da bateria, durante
PARTIDA_CARGA=${ENSAIO_PARTIDA_CARGA:-60}     # % da bateria, para comecar
PARTIDA_PACOTE=${ENSAIO_PARTIDA_PACOTE:-70000}
PARTIDA_LOAD=${ENSAIO_PARTIDA_LOAD:-4}

# O E3. Os tempos sao em amostras -- segundos, com o passo padrao.
E3_PRE=${ENSAIO_E3_PRE:-30}              # frio na porcentagem, antes da carga
E3_CARGA0=${ENSAIO_E3_CARGA0:-120}       # estagio 0, automatico
E3_CARGA1=${ENSAIO_E3_CARGA1:-180}       # estagio 1
E3_CARGA2=${ENSAIO_E3_CARGA2:-600}       # estagio 2, o que decide
E3_P1=${ENSAIO_E3_P1:-30}
E3_P2=${ENSAIO_E3_P2:-1}                 # o piso que o E2 mediu
E3_DESCIDA=${ENSAIO_E3_DESCIDA:-300}     # teto da descida depois de cada estagio
E3_EXTRA=${ENSAIO_E3_EXTRA:-60}          # quanto segue depois de ver a retomada
E3_ECO=${ENSAIO_E3_ECO:-30}              # uma linha no terminal a cada tantas
RETOMA_RPM=${ENSAIO_RETOMA_RPM:-300}     # "o EC tomou de volta": isto acima do frio
RETOMA_N=${ENSAIO_RETOMA_N:-5}           # ... por tantas amostras seguidas
CONTROLE_AUTO=${ENSAIO_CONTROLE_AUTO:-500}   # o automatico tem de subir isto
CARGA_N=${ENSAIO_CARGA_N:-8}
CARGA_CMD=${ENSAIO_CARGA_CMD:-while :; do :; done}
FOLGA_CARGA=${ENSAIO_FOLGA_CARGA:-15}    # segundos alem do estagio ate a carga morrer so
PARTIDA_PACOTE_E3=${ENSAIO_PARTIDA_PACOTE_E3:-60000}
PARTIDA_FOLGA_SEN=${ENSAIO_PARTIDA_FOLGA_SEN:-15000}   # cada SEN* isto abaixo do limite

FAN="$R/sys/devices/platform/acer-wmi/nitro_sense/fan_speed"
PERFIL="$R/sys/firmware/acpi/platform_profile"
BAT="$R/sys/class/power_supply/BAT1"
ACAD="$R/sys/class/power_supply/ACAD/online"
TT="$R/sys/devices/system/cpu/cpu0/thermal_throttle"

RUN=; VIGIA_PID=; SAIDA=
ULTIMO="0,0"          # o que este roteiro espera ler em fan_speed
DEVOLVIDO=0; FALHOU_DEVOLVER=0
REPOUSO=0             # 1 no E2: vale o limite de pacote mais baixo
N_PAC=0; MOTIVO=
PERFIL0=; MAX0=; FIM=0
REF1=; REF2=          # rotacao do automatico na partida: informa, nao julga
DRILL_PID=; DRILL_VALOR=
DRILL_RPM1=; DRILL_RPM2=   # o que a porcentagem dos exercicios gira
RESUMO=; ABORTOU=0; RETOMOU_NO_ULTIMO=0

le() { cat "$1" 2>/dev/null || echo NA; }
eh_num() { case "$1" in ''|*[!0-9-]*) return 1 ;; esac; return 0; }
acima() { eh_num "$1" && [ "$1" -ge "$2" ]; }
agora_ms() { local t=${EPOCHREALTIME/[.,]/}; echo "${t:0:13}"; }

# ---------------------------------------------------------------- sensores
# Tudo se acha pelo nome, na hora de usar (armadilha 19): o indice do hwmon e
# o da zona termica mudam entre boots e a cada recarga do modulo.

canal() {     # $1 = hwmon, $2 = temp|fan, $3 = rotulo -> caminho do _input
    local l
    [ -n "$1" ] || return 1
    for l in "$1"/"$2"*_label; do
        [ "$(cat "$l" 2>/dev/null)" = "$3" ] && { echo "${l%_label}_input"; return 0; }
    done
    return 1
}

zona() {      # $1 = tipo da zona termica -> temperatura
    local z
    for z in "$R"/sys/class/thermal/thermal_zone*; do
        [ "$(cat "$z/type" 2>/dev/null)" = "$1" ] && { le "$z/temp"; return 0; }
    done
    echo NA
}

localiza() {
    local d
    H_ACER=; H_CORE=; H_NVME=()
    for d in "$R"/sys/class/hwmon/hwmon*; do
        case "$(cat "$d/name" 2>/dev/null)" in
            acer) H_ACER=$d ;;
            coretemp) H_CORE=$d ;;
            nvme) H_NVME+=("$d") ;;
        esac
    done
    F_PACOTE=$(canal "$H_CORE" temp "Package id 0")
    F_ECCPU=$(canal "$H_ACER" temp CPU)
    F_ECGPU=$(canal "$H_ACER" temp GPU)
    F_EXT2=$(canal "$H_ACER" temp "External 2")
    F_RPM1=$(canal "$H_ACER" fan CPU)
    F_RPM2=$(canal "$H_ACER" fan GPU)
    F_NV1=; F_NV2=
    [ "${#H_NVME[@]}" -ge 1 ] && F_NV1=$(canal "${H_NVME[0]}" temp Composite)
    [ "${#H_NVME[@]}" -ge 2 ] && F_NV2=$(canal "${H_NVME[1]}" temp Composite)
}

amostra() {   # $1 = rotulo da fase. Le tudo uma vez; verifica() julga o lido.
    FASE=$1
    localiza
    V_FAN=$(le "$FAN")
    V_RPM1=$(le "$F_RPM1"); V_RPM2=$(le "$F_RPM2")
    V_PAC=$(le "$F_PACOTE"); V_ALARM=$(le "${F_PACOTE%_input}_crit_alarm")
    V_ECCPU=$(le "$F_ECCPU"); V_ECGPU=$(le "$F_ECGPU"); V_EXT2=$(le "$F_EXT2")
    V_SEN2=$(zona SEN2); V_SEN3=$(zona SEN3); V_SEN4=$(zona SEN4); V_SEN5=$(zona SEN5)
    V_NV1=$(le "$F_NV1"); V_NV2=$(le "$F_NV2")
    V_THRN=$(le "$TT/package_throttle_count")
    V_THRMS=$(le "$TT/package_throttle_total_time_ms")
    V_MHZ=$(awk '{s+=$1; n++} END {if (n) printf "%d", s/n/1000; else print "NA"}' \
        "$R"/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)
    V_CHARGE=$(le "$BAT/charge_now"); V_CHEIA=$(le "$BAT/charge_full")
    V_CORR=$(le "$BAT/current_now")
    V_ACAD=$(le "$ACAD")
    V_PERFIL=$(le "$PERFIL")
    V_MAX=$(grep -m1 '^maximum_mode' "$CFG" 2>/dev/null | tr -d ' ' | cut -d= -f2)
    V_JOGO=$(ps -eo comm --no-headers 2>/dev/null | grep -cE "^(${JOGOS})$")
    V_LOAD=$(cut -d' ' -f1 "$R/proc/loadavg" 2>/dev/null || echo NA)
    # A bateria se le pela carga, nao pelo status (armadilha 36).
    V_PCT=NA
    if eh_num "$V_CHARGE" && eh_num "$V_CHEIA" && [ "$V_CHEIA" -gt 0 ]; then
        V_PCT=$(( V_CHARGE * 100 / V_CHEIA ))
    fi
}

CABECALHO='epoch\thora\tfase\tescrito\tfan_speed\trpm_cpu\trpm_gpu\tpacote\tcrit_alarm\tec_cpu\tec_gpu\tec_ext2\tsen2\tsen3\tsen4\tsen5\tnvme1\tnvme2\tthr_n\tthr_ms\tmhz\tcharge_now\tpct\tcorrente_uA\tacad\tperfil\tmaximo\tjogo\tload1\n'

registra() {
    [ -n "$SAIDA" ] || return 0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$EPOCHSECONDS" "$(date +%T)" "$FASE" "$ULTIMO" "$V_FAN" "$V_RPM1" "$V_RPM2" \
        "$V_PAC" "$V_ALARM" "$V_ECCPU" "$V_ECGPU" "$V_EXT2" \
        "$V_SEN2" "$V_SEN3" "$V_SEN4" "$V_SEN5" "$V_NV1" "$V_NV2" \
        "$V_THRN" "$V_THRMS" "$V_MHZ" "$V_CHARGE" "$V_PCT" "$V_CORR" "$V_ACAD" \
        "$V_PERFIL" "$V_MAX" "$V_JOGO" "$V_LOAD" >> "$SAIDA"
}

exige_alvos() {     # sem isto um sensor ausente passaria por "abaixo do limite"
    local falta=0 par nome valor
    for par in "fan_speed:$V_FAN" "rotacao CPU:$V_RPM1" "rotacao GPU:$V_RPM2" \
               "pacote:$V_PAC" "crit_alarm:$V_ALARM" "temp CPU do acer:$V_ECCPU" \
               "temp GPU do acer:$V_ECGPU" "SEN2:$V_SEN2" "SEN3:$V_SEN3" \
               "SEN4:$V_SEN4" "SEN5:$V_SEN5" "NVMe:$V_NV1" "charge_now:$V_CHARGE" \
               "charge_full:$V_CHEIA" "ACAD:$V_ACAD" "perfil:$V_PERFIL"; do
        nome=${par%%:*}; valor=${par#*:}
        if [ "$valor" = NA ] || [ -z "$valor" ]; then
            echo "ERRO alvo ausente: $nome"; falta=1
        fi
    done
    return "$falta"
}

# ------------------------------------------------------------------ limites

verifica() {  # julga a ultima amostra. 0, COD_LIMITE ou COD_CONDICAO; ver MOTIVO
    local par nome valor lim_pac
    MOTIVO=

    # Primeiro a outra mao: se alguem escreveu na ventoinha, a escolha e de
    # quem a fez, e devolve() nao escreve por cima.
    if [ "$V_FAN" != "$ULTIMO" ]; then
        MOTIVO="fan_speed e '$V_FAN' e o roteiro escreveu '$ULTIMO': outra mao"
        return "$COD_CONDICAO"
    fi

    for par in "pacote:$V_PAC" "temp CPU do acer:$V_ECCPU" "temp GPU do acer:$V_ECGPU" \
               "SEN2:$V_SEN2" "SEN3:$V_SEN3" "SEN4:$V_SEN4" "SEN5:$V_SEN5" \
               "NVMe:$V_NV1" "rotacao CPU:$V_RPM1" "rotacao GPU:$V_RPM2" "carga:$V_PCT"; do
        nome=${par%%:*}; valor=${par#*:}
        if ! eh_num "$valor"; then
            MOTIVO="$nome sumiu no meio do ensaio (lido: '$valor')"
            return "$COD_CONDICAO"
        fi
    done

    lim_pac=$LIM_PACOTE
    [ "$REPOUSO" = 1 ] && [ "$LIM_PACOTE_REPOUSO" -lt "$lim_pac" ] && lim_pac=$LIM_PACOTE_REPOUSO
    if acima "$V_PAC" "$lim_pac"; then N_PAC=$((N_PAC + 1)); else N_PAC=0; fi
    if [ "$N_PAC" -ge 3 ]; then
        MOTIVO="pacote em $V_PAC por tres amostras (limite $lim_pac)"; return "$COD_LIMITE"
    fi
    if [ "$V_ALARM" = 1 ]; then
        MOTIVO="crit_alarm do pacote em 1"; return "$COD_LIMITE"
    fi
    for par in "temp CPU do acer:$V_ECCPU:$LIM_EC_CPU" "temp GPU do acer:$V_ECGPU:$LIM_EC_GPU" \
               "SEN2:$V_SEN2:$LIM_SEN2" "SEN3:$V_SEN3:$LIM_SEN3" \
               "SEN4:$V_SEN4:$LIM_SEN4" "SEN5:$V_SEN5:$LIM_SEN5" \
               "NVMe 1:$V_NV1:$LIM_NVME" "NVMe 2:$V_NV2:$LIM_NVME"; do
        nome=${par%%:*}; valor=${par#*:}; valor=${valor%%:*}
        if acima "$valor" "${par##*:}"; then
            MOTIVO="$nome em $valor (limite ${par##*:})"; return "$COD_LIMITE"
        fi
    done

    if [ "$V_ACAD" != 1 ]; then
        MOTIVO="cabo fora (ACAD/online = $V_ACAD)"; return "$COD_CONDICAO"
    fi
    if [ "$V_PCT" -lt "$LIM_CARGA" ]; then
        MOTIVO="bateria em $V_PCT%, abaixo de $LIM_CARGA%"; return "$COD_CONDICAO"
    fi
    if [ "$V_PERFIL" != "$PERFIL0" ]; then
        MOTIVO="o perfil mudou de $PERFIL0 para $V_PERFIL"; return "$COD_CONDICAO"
    fi
    if [ "$V_MAX" != "$MAX0" ]; then
        MOTIVO="o modo maximo mudou de '$MAX0' para '$V_MAX'"; return "$COD_CONDICAO"
    fi
    if [ "$V_JOGO" != 0 ]; then
        MOTIVO="jogo aberto ($V_JOGO processo(s) casando com $JOGOS)"; return "$COD_CONDICAO"
    fi
    if [ "$FIM" -gt 0 ] && [ "$EPOCHSECONDS" -ge "$FIM" ]; then
        MOTIVO="prazo de $PRAZO s vencido"; return "$COD_CONDICAO"
    fi
    return 0
}

# ---------------------------------------------------------- escrita e volta

escreve_cru() {    # $1 = "c,g". Confere lendo de volta: o efeito, nao o comando.
    if [ -n "${ENSAIO_ESCRITOR:-}" ]; then
        "$ENSAIO_ESCRITOR" "$1" "$FAN" || return 1
    else
        printf '%s\n' "$1" 2>/dev/null > "$FAN" || return 1
    fi
    [ "$(le "$FAN")" = "$1" ]
}

escreve() {
    # A intencao vai para o disco ANTES da escrita: o vigia so devolve a
    # ventoinha se achar em fan_speed um valor desta lista. Gravada depois,
    # um kill -9 entre as duas linhas deixaria o manual sem dono.
    printf '%s\n%s\n' "$ULTIMO" "$1" > "$RUN/escrito"
    escreve_cru "$1" || return 1
    ULTIMO=$1
}

mata_carga() {     # cada carga e lider do proprio grupo (setsid): vai o grupo
    local p
    [ -n "$RUN" ] && [ -f "$RUN/carga" ] || return 0
    while read -r p; do
        eh_num "$p" && kill -TERM -- "-$p" 2>/dev/null
    done < "$RUN/carga"
    sleep 0.2
    while read -r p; do
        eh_num "$p" && kill -KILL -- "-$p" 2>/dev/null
    done < "$RUN/carga"
    rm -f "$RUN/carga"
    return 0
}

carga_liga() {     # $1 = amostras que o estagio dura
    local i seg
    # Cada processo debaixo de timeout: se roteiro e vigia sumirem juntos, o
    # calor para sozinho quando o estagio teria acabado, mais a folga.
    seg=$(awk -v n="$1" -v p="$PASSO" -v f="$FOLGA_CARGA" \
        'BEGIN { s = n * p; t = int(s); if (t < s) t++; print t + f }')
    : > "$RUN/carga"
    for ((i = 0; i < CARGA_N; i++)); do
        setsid timeout "$seg" bash -c "$CARGA_CMD" < /dev/null > /dev/null 2>&1 &
        echo "$!" >> "$RUN/carga"
    done
}

volta_ao_automatico() {     # tres tentativas de 0,0; depois 100,100
    local i
    for i in 1 2 3; do
        escreve_cru "0,0" && return 0
        sleep 0.2
    done
    escreve_cru "100,100"
    return 1
}

rotacao_largou() {  # a rotacao saiu do valor manual?
    # $1 = amostras, $2 e $3 = rotacao no manual, $4 = quanto tem de mudar,
    # $5 = queda (tem de cair) | qualquer (basta mudar)
    local i r1=NA r2=NA d1 d2
    eh_num "$2" && eh_num "$3" || return 0
    for ((i = 0; i < $1; i++)); do
        localiza
        r1=$(le "$F_RPM1"); r2=$(le "$F_RPM2")
        if eh_num "$r1" && eh_num "$r2"; then
            d1=$(( $2 - r1 )); d2=$(( $3 - r2 ))
            if [ "$5" = qualquer ]; then d1=${d1#-}; d2=${d2#-}; fi
            if [ "$d1" -ge "$4" ] && [ "$d2" -ge "$4" ]; then
                echo "  a rotacao saiu do manual: de $2 / $3 para $r1 / $r2 rpm"
                return 0
            fi
        fi
        sleep "$PASSO"
    done
    echo "  a rotacao NAO saiu do manual: era $2 / $3 e esta em $r1 / $r2 rpm"
    return 1
}

devolve() {
    local atual
    [ "$DEVOLVIDO" = 1 ] && return 0
    DEVOLVIDO=1
    mata_carga
    atual=$(le "$FAN")
    if [ "$atual" = "0,0" ]; then
        :
    elif [ "$atual" = "$ULTIMO" ]; then
        if volta_ao_automatico; then
            echo "ventoinha devolvida: fan_speed = $(le "$FAN")"
            # So informa. Manual e automatico podem girar parecido, e ai nao
            # ha o que ver: quem prova a volta, com folga, sao os exercicios.
            rotacao_largou 15 "${V_RPM1:-}" "${V_RPM2:-}" 300 qualquer \
                || echo "  (se o manual girava perto do automatico, e o esperado)"
        else
            FALHOU_DEVOLVER=1
            echo "ERRO: nao consegui escrever 0,0 em tres tentativas."
            echo "ERRO: ventoinha deixada em $(le "$FAN"). Escolha Automatico na janela."
        fi
    else
        echo "fan_speed e '$atual', que este roteiro nao escreveu: fica como esta."
    fi
    [ -n "$RUN" ] && [ -d "$RUN" ] && : > "$RUN/devolvido"
    return 0
}

ao_sair() {
    local rc=$?
    trap - EXIT INT TERM HUP
    if [ -n "$DRILL_PID" ] && kill -0 "$DRILL_PID" 2>/dev/null; then
        kill -TERM "$DRILL_PID" 2>/dev/null
        sleep 1
    fi
    # Um exercicio interrompido pode ter deixado o valor dele em fan_speed.
    [ -n "$DRILL_VALOR" ] && [ "$(le "$FAN")" = "$DRILL_VALOR" ] && ULTIMO=$DRILL_VALOR
    devolve
    [ -n "$VIGIA_PID" ] && kill "$VIGIA_PID" 2>/dev/null
    [ -n "$RUN" ] && rm -rf "$RUN"
    [ "$FALHOU_DEVOLVER" = 1 ] && rc=$COD_DEVOLUCAO
    exit "$rc"
}

termina() {      # $1 = codigo. O trap de EXIT devolve a ventoinha.
    echo "ENCERRADO (codigo $1): $MOTIVO"
    exit "$1"
}

prepara() {      # vigia no ar ANTES da primeira escrita, e os traps
    RUN=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/ensaio-termico.XXXXXX") || exit 1
    : > "$RUN/escrito"
    FIM=$(( EPOCHSECONDS + PRAZO ))
    trap ao_sair EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    ENSAIO_TTY=$(tty 2>/dev/null) setsid "$EU" --vigia "$$" "$(( FIM + FOLGA_VIGIA ))" "$RUN" \
        >> "$RUN/vigia.log" 2>&1 &
    VIGIA_PID=$!
    sleep 0.2
    if ! kill -0 "$VIGIA_PID" 2>/dev/null; then
        MOTIVO="o vigia nao subiu; nada foi escrito"
        VIGIA_PID=
        termina "$COD_RECUSA"
    fi
}

# -------------------------------------------------------------------- vigia
# Processo a parte, em sessao propria: o Ctrl-C do terminal nao chega nele.
# Devolve a ventoinha quando o roteiro some sem devolver, e quando o prazo
# vence com o roteiro travado.

avisa() {
    echo "$*"
    case "${ENSAIO_TTY:-}" in
        /dev/*) [ -w "$ENSAIO_TTY" ] && echo "$*" > "$ENSAIO_TTY" ;;
    esac
    return 0
}

vigia_devolve() {
    local atual
    mata_carga
    atual=$(le "$FAN")
    if [ "$atual" = "0,0" ]; then
        avisa "VIGIA: fan_speed ja esta em 0,0."
    elif grep -qxF -- "$atual" "$RUN/escrito" 2>/dev/null; then
        if volta_ao_automatico; then
            avisa "VIGIA: ventoinha devolvida ao automatico (estava em $atual)."
        else
            avisa "VIGIA: ERRO, 0,0 recusado tres vezes; ventoinha em $(le "$FAN")."
        fi
    else
        avisa "VIGIA: fan_speed e '$atual', que o roteiro nao escreveu: fica como esta."
    fi
}

modo_vigia() {   # $1 = pid do roteiro, $2 = prazo (epoch), $3 = RUN
    local pid=$1 fim=$2 i
    RUN=$3
    trap '' INT HUP
    while :; do
        [ -e "$RUN/devolvido" ] && exit 0
        if ! kill -0 "$pid" 2>/dev/null; then
            [ -e "$RUN/devolvido" ] && exit 0
            avisa "VIGIA: o roteiro (pid $pid) sumiu sem devolver a ventoinha."
            vigia_devolve
            rm -rf "$RUN"
            exit 0
        fi
        if [ "$EPOCHSECONDS" -ge "$fim" ]; then
            avisa "VIGIA: prazo vencido; encerrando o roteiro (pid $pid)."
            kill -TERM "$pid" 2>/dev/null
            kill -CONT "$pid" 2>/dev/null
            for ((i = 0; i < 30; i++)); do
                [ -e "$RUN/devolvido" ] && exit 0
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            [ -e "$RUN/devolvido" ] && exit 0
            kill -KILL "$pid" 2>/dev/null
            vigia_devolve
            rm -rf "$RUN"
            exit 0
        fi
        sleep "$PASSO_VIGIA"
    done
}

# ------------------------------------------------------------------- coleta

mediana() { printf '%s\n' "$@" | sort -n | sed -n "$(( ($# + 1) / 2 ))p"; }
minimo()  { printf '%s\n' "$@" | sort -n | head -1; }
maximo()  { printf '%s\n' "$@" | sort -n | tail -1; }

coleta() {    # $1 = fase, $2 = amostras a descartar, $3 = amostras a guardar
    local i rc
    C1=(); C2=()
    for ((i = 0; i < $2 + $3; i++)); do
        sleep "$PASSO"
        amostra "$1"; registra
        verifica; rc=$?
        [ "$rc" -ne 0 ] && return "$rc"
        if [ "$i" -ge "$2" ]; then C1+=("$V_RPM1"); C2+=("$V_RPM2"); fi
    done
    return 0
}

mostra_condicao() {
    echo "  fan_speed $V_FAN   rotacao $V_RPM1 / $V_RPM2 rpm   perfil $V_PERFIL   modo maximo ${V_MAX:-?}"
    echo "  pacote $V_PAC   CPU pelo EC $V_ECCPU   GPU pelo EC $V_ECGPU   SEN2-5 $V_SEN2 $V_SEN3 $V_SEN4 $V_SEN5"
    echo "  cabo $V_ACAD   bateria $V_PCT%   load1 $V_LOAD   jogo $V_JOGO"
}

pode_comecar() {    # a condicao de partida do E2; nada foi escrito ainda
    local nao=0
    recusa() { echo "  RECUSA: $1"; nao=1; }
    [ "$V_FAN" = "0,0" ] || recusa "fan_speed e '$V_FAN'; o ensaio so comeca em 0,0 (automatico)"
    [ "$V_ACAD" = 1 ] || recusa "fora da tomada"
    eh_num "$V_PCT" && [ "$V_PCT" -ge "$PARTIDA_CARGA" ] \
        || recusa "bateria em $V_PCT%, abaixo de $PARTIDA_CARGA%"
    acima "$V_PAC" "$PARTIDA_PACOTE" && recusa "pacote em $V_PAC, a partir de $PARTIDA_PACOTE"
    [ "$V_JOGO" = 0 ] || recusa "jogo aberto ($V_JOGO processo(s) casando com $JOGOS)"
    # O modo maximo troca a curva do automatico; a linha de base e os limites
    # do plano sao os do modo desligado.
    [ "$V_MAX" = true ] && recusa "modo maximo ligado; o ensaio e com ele desligado"
    awk -v l="$V_LOAD" -v m="$PARTIDA_LOAD" 'BEGIN { exit !(l + 0 < m + 0) }' \
        || recusa "load1 em $V_LOAD, a partir de $PARTIDA_LOAD"
    return "$nao"
}

# -------------------------------------------------- o alvo dos exercicios
# Escreve uma porcentagem e fica amostrando. E o processo que o exercicio do
# vigia mata com kill -9 e que o exercicio do aborto faz estourar um limite;
# o teste da suite tambem o usa para provocar cada limite, um a um.

modo_segura() {
    local p=${ENSAIO_SEGURA:?} fase=${ENSAIO_FASE:-segura} n=${ENSAIO_SEGURA_N:-120} i rc
    SAIDA=${ENSAIO_SAIDA:-}
    amostra "$fase"
    exige_alvos || exit "$COD_ALVO"
    if [ "$V_FAN" != "0,0" ]; then
        echo "  RECUSA: fan_speed e '$V_FAN'; so comeca em 0,0"; exit "$COD_RECUSA"
    fi
    PERFIL0=$V_PERFIL; MAX0=$V_MAX
    prepara
    if ! escreve "$p,$p"; then MOTIVO="a escrita de $p,$p foi recusada"; termina "$COD_CONDICAO"; fi
    for ((i = 0; i < n; i++)); do
        sleep "$PASSO"
        amostra "$fase"; registra
        verifica; rc=$?
        [ "$rc" -ne 0 ] && termina "$rc"
    done
    exit 0
}

# ------------------------------------------------------------- exercicios

espera_fan() {   # $1 = valor esperado, $2 = decimos de segundo -> ms ate la
    local i t0
    t0=$(agora_ms)
    for ((i = 0; i < $2; i++)); do
        if [ "$(le "$FAN")" = "$1" ]; then echo $(( $(agora_ms) - t0 )); return 0; fi
        sleep 0.1
    done
    return 1
}

exercicio_vigia() {    # 0 passou, 1 falhou, 2 o manual nao se distingue do automatico
    local ms rpm1 rpm2 v="$DRILL_P,$DRILL_P"
    echo
    echo "EXERCICIO 1 -- o vigia: o roteiro leva kill -9 com a ventoinha em $v"
    DRILL_VALOR=$v
    ENSAIO_SEGURA=$DRILL_P ENSAIO_FASE=vigia ENSAIO_SAIDA=$SAIDA "$EU" _segura &
    DRILL_PID=$!
    disown "$DRILL_PID"
    if ! espera_fan "$v" 100 > /dev/null; then
        echo "  FALHA: o alvo nao chegou a escrever $v"; return 1
    fi
    sleep "$(awk -v p="$PASSO" 'BEGIN { print p * 10 }')"
    localiza; rpm1=$(le "$F_RPM1"); rpm2=$(le "$F_RPM2")
    echo "  em $v: $rpm1 / $rpm2 rpm   (automatico, na partida: $REF1 / $REF2)"
    # Sem distancia entre o manual e o automatico nao ha volta para ver: ou
    # o manual nao muda a rotacao, ou a maquina nao esta em repouso e o
    # automatico ja gira alto. Dizer isso, em vez de passar por vacuo.
    if ! eh_num "$rpm1" || ! eh_num "$rpm2" \
       || [ $(( rpm1 - REF1 )) -lt $(( QUEDA_RPM * 2 )) ] \
       || [ $(( rpm2 - REF2 )) -lt $(( QUEDA_RPM * 2 )) ]; then
        echo "  o manual a $DRILL_P% nao se distingue do automatico: menos de $(( QUEDA_RPM * 2 )) rpm acima"
        kill -TERM "$DRILL_PID" 2>/dev/null
        espera_fan "0,0" 50 > /dev/null
        return 2
    fi
    # Sem isto o exercicio passaria por vacuo: um alvo que ja tivesse saido
    # por conta propria deixa 0,0 no lugar, e o "vigia devolveu" seria dele.
    if ! kill -0 "$DRILL_PID" 2>/dev/null || [ "$(le "$FAN")" != "$v" ]; then
        echo "  FALHA: o alvo saiu antes do kill -9 (fan_speed = '$(le "$FAN")')"; return 1
    fi
    kill -KILL "$DRILL_PID" 2>/dev/null
    if ! ms=$(espera_fan "0,0" $(( VIGIA_MAX * 10 + 20 ))); then
        echo "  FALHA: $(( VIGIA_MAX + 2 )) s depois do kill -9, fan_speed ainda e '$(le "$FAN")'"
        return 1
    fi
    DRILL_PID=; DRILL_VALOR=
    echo "  fan_speed de volta a 0,0 em $ms ms"
    if [ "$ms" -gt $(( VIGIA_MAX * 1000 )) ]; then
        echo "  FALHA: o vigia levou mais de $VIGIA_MAX s"; return 1
    fi
    # fan_speed e a memoria do driver. Quem diz que o EC largou o manual e a
    # rotacao -- e ela tem de cair, nao de chegar a um numero combinado.
    rotacao_largou 30 "$rpm1" "$rpm2" "$QUEDA_RPM" queda || return 1
    DRILL_RPM1=$rpm1; DRILL_RPM2=$rpm2
    echo "  OK"
}

exercicio_aborto() {
    local lim rc v="$DRILL_P,$DRILL_P"
    echo
    echo "EXERCICIO 2 -- o aborto: limite da CPU pelo EC rebaixado para 5 C abaixo da leitura"
    amostra aborto
    lim=$(( V_ECCPU - 5000 ))
    DRILL_VALOR=$v
    ENSAIO_LIM_EC_CPU=$lim ENSAIO_SEGURA=$DRILL_P ENSAIO_FASE=aborto ENSAIO_SAIDA=$SAIDA "$EU" _segura
    rc=$?
    if [ "$rc" -ne "$COD_LIMITE" ]; then
        echo "  FALHA: o alvo saiu com $rc, e o codigo de aborto e $COD_LIMITE"; return 1
    fi
    if [ "$(le "$FAN")" != "0,0" ]; then
        echo "  FALHA: depois do aborto fan_speed e '$(le "$FAN")'"; return 1
    fi
    DRILL_VALOR=
    rotacao_largou 30 "$DRILL_RPM1" "$DRILL_RPM2" "$QUEDA_RPM" queda || return 1
    echo "  OK"
}

# --------------------------------------------------------------------- E2

modo_e2() {
    local p rc resumo linha
    declare -A M1 M2 A1 B1 A2 B2
    REPOUSO=1
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-e2-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    resumo="${SAIDA%.tsv}.resumo.txt"

    echo "E2 -- mapa de porcentagem para rotacao, em repouso"
    echo "saida: $SAIDA"
    amostra partida; registra
    exige_alvos || exit "$COD_ALVO"
    mostra_condicao
    pode_comecar || exit "$COD_RECUSA"
    PERFIL0=$V_PERFIL; MAX0=$V_MAX

    trap ao_sair EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    echo
    echo "o automatico, na partida (so informa: ele nao tem repouso fixo)"
    coleta auto-antes 0 "$LEITURAS" || termina $?
    REF1=$(mediana "${C1[@]}"); REF2=$(mediana "${C2[@]}")
    echo "  $REF1 / $REF2 rpm"

    exercicio_vigia; rc=$?
    if [ "$rc" -eq 2 ]; then
        MOTIVO="o manual a $DRILL_P% nao se distingue do automatico: ou o manual nao muda a rotacao, ou a maquina nao esta em repouso"
        termina "$COD_CONTROLE"
    elif [ "$rc" -ne 0 ]; then
        MOTIVO="o exercicio do vigia falhou"; termina "$COD_EXERCICIO"
    fi
    exercicio_aborto || { MOTIVO="o exercicio do aborto falhou"; termina "$COD_EXERCICIO"; }

    echo
    echo "O MAPA -- cada porcentagem: $ASSENTA amostras para assentar, $LEITURAS que contam"
    prepara
    echo "perfil $PERFIL0, modo maximo ${MAX0:-?}, automatico na partida $REF1 / $REF2 rpm" > "$resumo"
    printf '%-6s %-22s %-22s %s\n' "%" "CPU rpm (min med max)" "GPU rpm (min med max)" "pacote" | tee -a "$resumo"
    for p in $PORCENTAGENS; do
        if ! escreve "$p,$p"; then MOTIVO="a escrita de $p,$p foi recusada"; termina "$COD_CONDICAO"; fi
        coleta "p=$p" "$ASSENTA" "$LEITURAS"; rc=$?
        [ "$rc" -ne 0 ] && termina "$rc"
        M1[$p]=$(mediana "${C1[@]}"); A1[$p]=$(minimo "${C1[@]}"); B1[$p]=$(maximo "${C1[@]}")
        M2[$p]=$(mediana "${C2[@]}"); A2[$p]=$(minimo "${C2[@]}"); B2[$p]=$(maximo "${C2[@]}")
        linha=$(printf '%-6s %-22s %-22s %s' "$p" "${A1[$p]} ${M1[$p]} ${B1[$p]}" \
            "${A2[$p]} ${M2[$p]} ${B2[$p]}" "$V_PAC")
        echo "$linha" | tee -a "$resumo"
        # O controle positivo, assim que houver 100 e 50: se a rotacao nao
        # acompanha a escrita, o modo manual nao e o que se supoe.
        if [ -n "${M1[100]:-}" ] && [ -n "${M1[50]:-}" ] && [ -z "${CONTROLE_OK:-}" ]; then
            if [ $(( M1[100] - M1[50] )) -lt "$CONTROLE_RPM" ] \
               || [ $(( M2[100] - M2[50] )) -lt "$CONTROLE_RPM" ]; then
                MOTIVO="100% gira ${M1[100]} / ${M2[100]} e 50% gira ${M1[50]} / ${M2[50]}: menos de $CONTROLE_RPM rpm de diferenca"
                termina "$COD_CONTROLE"
            fi
            CONTROLE_OK=1
        fi
    done

    if ! escreve "0,0"; then MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"; fi
    coleta auto-depois "$ASSENTA" "$LEITURAS"; rc=$?
    [ "$rc" -ne 0 ] && termina "$rc"
    linha=$(printf '%-6s %-22s %-22s %s' auto "$(minimo "${C1[@]}") $(mediana "${C1[@]}") $(maximo "${C1[@]}")" \
        "$(minimo "${C2[@]}") $(mediana "${C2[@]}") $(maximo "${C2[@]}")" "$V_PAC")
    echo "$linha" | tee -a "$resumo"
    echo
    echo "E2 terminou. Resumo em $resumo"
    exit 0
}

# --------------------------------------------------------------------- E3

maior() {     # $1 = nome da variavel, $2 = valor: guarda o maior dos dois
    local -n _alvo=$1
    eh_num "$2" && [ "$2" -gt "$_alvo" ] && _alvo=$2
    return 0
}

frio_o_bastante() {    # pacote e zonas de placa longe dos limites?
    acima "$1" "$PARTIDA_PACOTE_E3" && return 1
    acima "$V_SEN2" $(( LIM_SEN2 - PARTIDA_FOLGA_SEN + 1 )) && return 1
    acima "$V_SEN3" $(( LIM_SEN3 - PARTIDA_FOLGA_SEN + 1 )) && return 1
    acima "$V_SEN4" $(( LIM_SEN4 - PARTIDA_FOLGA_SEN + 1 )) && return 1
    acima "$V_SEN5" $(( LIM_SEN5 - PARTIDA_FOLGA_SEN + 1 )) && return 1
    return 0
}

descida() {   # $1 = numero do estagio. Carga fora, automatico: grava ate esfriar
    local n=$1 i rc frias=0 t0=$EPOCHSECONDS
    for ((i = 0; i < E3_DESCIDA; i++)); do
        sleep "$PASSO"
        amostra "e$n:descida"; registra
        verifica; rc=$?
        N_PAC=0
        # Limite de temperatura aqui nao e novidade: e o estagio que acabou de
        # abortar, esfriando. Pessoa, bateria e prazo continuam valendo.
        [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"
        if frio_o_bastante "$V_PAC"; then frias=$((frias + 1)); else frias=0; fi
        [ "$frias" -ge 3 ] && break
    done
    DESCIDA_SEG=$(( EPOCHSECONDS - t0 ))
    DESCIDA_OK=1
    [ "$frias" -ge 3 ] || DESCIDA_OK=0
    echo "  descida: $DESCIDA_SEG s ate o pacote ficar abaixo de $PARTIDA_PACOTE_E3; rotacao $V_RPM1 / $V_RPM2 rpm"
}

estagio() {   # $1 = numero, $2 = porcentagem (0 = automatico), $3 = amostras de carga
    local n=$1 p=$2 dur=$3 i=0 rc=0 nome ref1 ref2 cnt=0 retomou=0 resta=0 fim=completo
    local thr0 ch0 t0 t0ms dur_ms seg thr pct="?" mhz=0 nm=0 quando="" ec=""
    local mp=0 me=0 mg=0 m2=0 m3=0 m4=0 m5=0 mr1=0 mr2=0
    if [ "$p" = 0 ]; then nome=automatico; else nome="manual $p%"; fi
    echo
    dur_ms=$(awk -v n="$dur" -v p="$PASSO" 'BEGIN { printf "%d", n * p * 1000 }')
    echo "ESTAGIO $n -- $nome, $(( dur_ms / 1000 )) s de carga"
    if [ "$p" != 0 ]; then
        if ! escreve "$p,$p"; then MOTIVO="a escrita de $p,$p foi recusada"; termina "$COD_CONDICAO"; fi
    fi
    # A rotacao de referencia se mede na hora, fria, nesta porcentagem.
    coleta "e$n:frio" 0 "$E3_PRE" || termina $?
    ref1=$(mediana "${C1[@]}"); ref2=$(mediana "${C2[@]}")
    echo "  frio: $ref1 / $ref2 rpm, pacote $V_PAC"
    thr0=$V_THRMS; ch0=$V_CHARGE; t0=$EPOCHSECONDS

    # O estagio dura tempo de relogio, nao um numero de amostras: cada
    # amostra custa o passo mais a leitura, e a carga morre sozinha pelo
    # relogio (carga_liga). Contando amostras, ela morria antes do estagio.
    t0ms=$(agora_ms)
    carga_liga "$dur"
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        i=$(( i + 1 ))
        amostra "e$n:carga"; registra
        verifica; rc=$?
        maior mp "$V_PAC"; maior me "$V_ECCPU"; maior mg "$V_ECGPU"
        maior m2 "$V_SEN2"; maior m3 "$V_SEN3"; maior m4 "$V_SEN4"; maior m5 "$V_SEN5"
        maior mr1 "$V_RPM1"; maior mr2 "$V_RPM2"
        if eh_num "$V_MHZ"; then mhz=$(( mhz + V_MHZ )); nm=$(( nm + 1 )); fi
        if [ "$rc" -ne 0 ]; then fim="aborto: $MOTIVO"; break; fi
        if [ $(( i % E3_ECO )) -eq 0 ]; then
            echo "  +$i: pacote $V_PAC, rotacao $V_RPM1 / $V_RPM2, SEN2-5 $V_SEN2 $V_SEN3 $V_SEN4 $V_SEN5"
        fi
        [ "$p" = 0 ] && continue
        if [ "$retomou" = 1 ]; then
            resta=$(( resta - 1 ))
            [ "$resta" -le 0 ] && break
        else
            # fan_speed ainda diz o manual -- verifica() acabou de conferir --
            # e a ventoinha gira acima do que essa porcentagem girava fria.
            if [ $(( V_RPM1 - ref1 )) -gt "$RETOMA_RPM" ] || [ $(( V_RPM2 - ref2 )) -gt "$RETOMA_RPM" ]; then
                cnt=$(( cnt + 1 ))
            else
                cnt=0
            fi
            if [ "$cnt" -ge "$RETOMA_N" ]; then
                retomou=1; resta=$E3_EXTRA
                quando="aos $(( EPOCHSECONDS - t0 )) s, com o pacote em $V_PAC e a rotacao em $V_RPM1 / $V_RPM2 rpm"
                echo "  o EC tomou a ventoinha de volta $quando (fan_speed = $V_FAN)"
            fi
        fi
    done
    seg=$(( EPOCHSECONDS - t0 ))
    mata_carga
    [ "$retomou" = 1 ] && [ "$rc" -eq 0 ] && fim=retomada

    # Pessoa, bateria, prazo ou sensor sumido: o estagio nao conta.
    [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"

    if [ "$p" = 0 ] && [ "$rc" -eq 0 ]; then
        # O controle positivo: se o automatico nao sobe com a carga, "a
        # rotacao nao subiu em manual" nao quer dizer nada (armadilha 35).
        if [ $(( mr1 - ref1 )) -lt "$CONTROLE_AUTO" ] || [ $(( mr2 - ref2 )) -lt "$CONTROLE_AUTO" ]; then
            MOTIVO="em automatico a rotacao foi de $ref1 / $ref2 a no maximo $mr1 / $mr2 rpm com a carga: menos de $CONTROLE_AUTO de subida"
            termina "$COD_CONTROLE"
        fi
        ec="a rotacao subiu de $ref1 / $ref2 para ate $mr1 / $mr2 rpm: controle positivo passou"
    elif [ "$p" != 0 ]; then
        if [ "$retomou" = 1 ]; then ec="o EC tomou a ventoinha de volta $quando"
        else ec="o EC obedeceu ao manual: rotacao de $ref1 / $ref2 a no maximo $mr1 / $mr2 rpm"; fi
        if ! escreve "0,0"; then MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"; fi
    fi

    thr=NA
    if eh_num "$thr0" && eh_num "$V_THRMS"; then
        thr=$(( V_THRMS - thr0 ))
        [ "$seg" -gt 0 ] && pct=$(awk -v t="$thr" -v s="$seg" 'BEGIN { printf "%.1f", t / 10 / s }')
    fi
    [ "$nm" -gt 0 ] && mhz=$(( mhz / nm ))
    {
        echo "estagio $n ($nome): carga de $seg s; fim: $fim"
        echo "    $ec"
        echo "    maximos: pacote $mp, CPU pelo EC $me, GPU pelo EC $mg, SEN2-5 $m2 $m3 $m4 $m5"
        echo "    throttle $thr ms ($pct% do tempo); frequencia media $mhz MHz; charge_now de $ch0 a $V_CHARGE"
    } | tee -a "$RESUMO"

    descida "$n"
    echo "    descida: $DESCIDA_SEG s$([ "$DESCIDA_OK" = 1 ] || echo ' (nao esfriou no prazo)')" >> "$RESUMO"

    if [ "$rc" -eq "$COD_LIMITE" ]; then ABORTOU=1; return "$COD_LIMITE"; fi
    RETOMOU_NO_ULTIMO=$retomou
    if [ "$DESCIDA_OK" != 1 ]; then
        MOTIVO="depois do estagio $n a maquina nao esfriou em $E3_DESCIDA amostras"
        termina "$COD_CONDICAO"
    fi
    return 0
}

veredito() {   # a regra da secao 10 do plano, escrita antes de medir
    local v
    if [ "$ABORTOU" = 1 ]; then
        v="R3 -- um estagio abortou num limite de temperatura"
    elif [ "$RETOMOU_NO_ULTIMO" = 1 ]; then
        v="R1 -- no estagio mais baixo o EC tomou a ventoinha de volta, dentro dos limites"
    else
        v="R2 -- o EC obedeceu ao manual e nenhum limite estourou"
    fi
    echo
    echo "veredito: $v" | tee -a "$RESUMO"
}

modo_e3() {
    local i pacs=() med rc
    REPOUSO=0
    [ -n "${ENSAIO_PRAZO:-}" ] || PRAZO=2100
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-e3-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    RESUMO="${SAIDA%.tsv}.resumo.txt"

    echo "E3 -- manual baixo com carga de CPU. ESQUENTA A MAQUINA."
    echo "saida: $SAIDA"
    # Cinco leituras do pacote, e vale a mediana: com a maquina parada ele da
    # picos de uma amostra so, que nao devem recusar nem aprovar a partida.
    for ((i = 0; i < 5; i++)); do
        amostra partida; registra
        eh_num "$V_PAC" && pacs+=("$V_PAC")
        sleep "$PASSO"
    done
    exige_alvos || exit "$COD_ALVO"
    med=$(mediana "${pacs[@]}")
    V_PAC=$med
    mostra_condicao
    pode_comecar || exit "$COD_RECUSA"
    if ! frio_o_bastante "$med"; then
        echo "  RECUSA: a maquina nao esta fria o bastante: pacote $med (pede abaixo de $PARTIDA_PACOTE_E3) e cada SEN* a $PARTIDA_FOLGA_SEN do limite"
        exit "$COD_RECUSA"
    fi
    PERFIL0=$V_PERFIL; MAX0=$V_MAX
    echo "perfil $PERFIL0, modo maximo ${MAX0:-?}; carga: $CARGA_N processos" > "$RESUMO"

    prepara

    estagio 0 0 "$E3_CARGA0"; rc=$?
    if [ "$rc" -eq 0 ]; then estagio 1 "$E3_P1" "$E3_CARGA1"; rc=$?; fi
    if [ "$rc" -eq 0 ]; then estagio 2 "$E3_P2" "$E3_CARGA2"; rc=$?; fi
    veredito
    echo "E3 terminou. Resumo em $RESUMO"
    [ "$ABORTOU" = 1 ] && exit "$COD_LIMITE"
    exit 0
}

case "${1:-}" in
    --vigia)  modo_vigia "$2" "$3" "$4" ;;
    _segura)  modo_segura ;;
    e2)       modo_e2 "${2:-}" ;;
    e3)       modo_e3 "${2:-}" ;;
    *)        sed -n '2,48p' "$0"; exit 2 ;;
esac
