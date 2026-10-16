#!/bin/bash
# Os ensaios da curva propria -- E-C2, E-C3 e E-C5 de docs/plano-curva.md,
# secao 6 -- numa arvore de mentira, antes de encostarem na maquina.
#
# O que tests/shell/test-ensaio-termico.sh ja guarda (limites, sinais, o
# vigia, a outra mao) vale aqui sem repetir: e a mesma verifica(). O que este
# teste guarda e o que so os ensaios da curva tem:
#   - os gestos da pessoa -- o modo maximo na bandeja, o jogo, a tampa, o
#     cabo, o perfil -- sao esperados e conferidos pelo efeito, e o gesto que
#     nao vem encerra sem deixar nada fora do lugar;
#   - o perfil de energia, que o E-C2 troca, volta ao da partida pelo trap e
#     pelo vigia, como a ventoinha;
#   - o controle do E-C2 (o manual que o mapa de E2 diz girar o teto do
#     automatico) para o ensaio quando o mapa nao vale;
#   - o aborto de cada modo novo: um limite estourado no meio encerra com 10
#     e devolve a ventoinha -- o controle positivo do caminho de aborto;
#   - a regra da secao 7 do plano, com numeros, e o mapa de E2;
#   - no E-C5, o guarda (ExecStopPost e WatchdogSec da unit do agente) contra
#     um systemd de mentira, e o reinicio de proposito com o manual a 95%.
#
# A pessoa e a bandeja sao um processo de mentira (`usuario`), que le as
# linhas GESTO do roteiro e faz o que elas pedem na arvore. O agente e o
# systemd tambem (`systemd_falso`). Nada fala com o barramento nem com o
# gerenciador de verdade: busctl e systemctl sao os da arvore.
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/tests/hardware/ensaio-termico.sh"

# shellcheck source=tests/shell/lib-arvore-termica.sh
source "$RAIZ/tests/shell/lib-arvore-termica.sh"
for c in timeout ps grep sed cut; do
    command -v "$c" > /dev/null 2>&1 || { echo "ERRO alvo ausente: $c"; exit 3; }
done
GUARDA="$RAIZ/packaging/scripts/guarda-ventoinha.sh"
[ -x "$GUARDA" ] || { echo "ERRO alvo ausente: $GUARDA executavel"; exit 3; }

# O mapa de E2 do EC de mentira: o manual gira 600 + 50 por ponto na CPU e
# 500 + 45 na GPU. Com ele, o teto da curva alta (5300 / 4781 rpm, pacote a
# 93 C) vira o manual 94,95, que gira 5300 / 4775.
MAPA_FALSO=(ENSAIO_MAPA_CPU="100:5600 80:4600 60:3600 50:3100 40:2600 30:2100 20:1600"
            ENSAIO_MAPA_GPU="100:5000 80:4100 60:3200 50:2750 40:2300 30:1850 20:1400")

fases_de() { cut -f3 "$1" 2> /dev/null | sort -u | tr '\n' ' '; }

carga_viva() {       # quantos processos da carga de mentira deste caso existem
    ps -eo comm,args --no-headers \
        | awk -v d="$D/bin/carga-falsa" '$1 != "awk" && index($0, d) { n++ } END { print n + 0 }'
}

sem_carga() {        # $1 = descricao
    local i
    for ((i = 0; i < 30; i++)); do
        [ -e "$D/carga_ligada" ] || [ "$(carga_viva)" != 0 ] || { ok "$1: a fonte de calor morreu"; return; }
        sleep 0.1
    done
    falha "$1: sobrou carga ($(carga_viva) processo(s))"
}

ppd() { cat "$D/ppd" 2> /dev/null; }

confere_ppd() {      # $1 = descricao, $2 = perfil de energia esperado
    [ "$(ppd)" = "$2" ] && ok "$1" || falha "$1: o perfil de energia e '$(ppd)' (esperado '$2')"
}

# ─── a pessoa e a bandeja de mentira ────────────────────────────────
# Le cada linha GESTO da saida do roteiro e faz o que ela pede, como a bandeja
# faria: o modo maximo grava o config.toml e so depois troca o perfil de
# energia (src/nexus_sense/maximum.py), pelo mesmo busctl. Jeitos:
#   normal          faz o que se pede
#   ausente         nao faz nada
#   sem_ppd         liga o modo, e a bandeja nao poe o perfil em performance
#   larga_e_volta   ao suspender, o EC larga o manual e volta a ele em 0,3 s
#   perfil_preso    ao acordar, o perfil fica no balanced: o agente nao o devolve
#   larga_na_suspensao  como a maquina em 2026-10-16: ao acordar o EC larga o
#                   manual e so o retoma quando fan_speed e escrito de novo
# No jeito normal, ao acordar o perfil vai a balanced e volta em 0,3 s, como
# na maquina: o firmware o troca, e o agente o devolve.
usuario() {   # $1 = arvore, $2 = jeito
    local d=$1 n=0 visto linha s
    while [ -d "$d" ]; do
        visto=$(grep -c '^GESTO' "$d/saida.txt" 2> /dev/null)
        while [ "$n" -lt "${visto:-0}" ]; do
            n=$(( n + 1 ))
            linha=$(grep '^GESTO' "$d/saida.txt" | sed -n "${n}p")
            echo "$n $linha" >> "$d/gestos.log"
            [ "$2" = ausente ] && continue
            sleep 0.1
            case "$linha" in
                *"desligue o modo maximo"*)
                    poe "$d/config.toml" "maximum_mode = false"
                    "$d/bin/busctl" --system set-property x x x ActiveProfile s "$(cat "$d/ppd_salvo")" ;;
                *"ligue o modo maximo"*)
                    cp "$d/ppd" "$d/ppd_salvo"
                    poe "$d/config.toml" "maximum_mode = true"
                    [ "$2" = sem_ppd ] \
                        || "$d/bin/busctl" --system set-property x x x ActiveProfile s performance ;;
                *"abra o jogo"*)
                    poe "$d/processos" GameThread ;;
                *"suspenda"*)
                    [ "$2" = larga_e_volta ] && : > "$d/ec_larga"
                    [ "$2" = larga_na_suspensao ] && : > "$d/ec_larga"
                    # Como a maquina: o firmware troca o perfil ao acordar, e
                    # o agente o devolve logo depois. Com perfil_preso, nao.
                    [ "$2" = perfil_preso ] || [ "$2" = larga_e_volta ] \
                        || poe "$d/sys/firmware/acpi/platform_profile" balanced
                    [ "$2" = perfil_preso ] && poe "$d/sys/firmware/acpi/platform_profile" balanced
                    s=$(cat "$d/sys/power/suspend_stats/success")
                    poe "$d/sys/power/suspend_stats/success" $(( s + 1 ))
                    [ "$2" = larga_e_volta ] && { sleep 0.3; rm -f "$d/ec_larga"; }
                    case "$2" in
                        normal|larga_na_suspensao)
                            sleep 0.3; poe "$d/sys/firmware/acpi/platform_profile" balanced-performance ;;
                    esac ;;
                *"tire o cabo"*)
                    poe "$d/sys/class/power_supply/ACAD/online" 0
                    sleep 0.2      # o agente: na bateria, um perfil que ela aceita
                    poe "$d/sys/firmware/acpi/platform_profile" balanced ;;
                *"ponha o cabo"*)
                    poe "$d/sys/class/power_supply/ACAD/online" 1
                    sleep 0.2      # o agente devolve o perfil da tomada
                    poe "$d/sys/firmware/acpi/platform_profile" balanced-performance ;;
                *"troque o perfil termico para balanced"*)
                    poe "$d/sys/firmware/acpi/platform_profile" balanced ;;
                *"volte o perfil termico"*)
                    poe "$d/sys/firmware/acpi/platform_profile" balanced-performance ;;
            esac
        done
        sleep 0.05
    done 2> /dev/null
}

com_usuario() {   # $1 = jeito. Depois de `nova`: a pessoa entra junto com o EC
    usuario "$D" "${1:-normal}" &
    ECS+=("$!")
}

# ─── o agente e o systemd de mentira ────────────────────────────────
# O systemd cria o RuntimeDirectory (run/nexus-sense) e sobe o agente. Quando
# ele morre, roda o ExecStopPost -- o guarda de verdade,
# packaging/scripts/guarda-ventoinha.sh, que devolve o manual registrado ali
# --, apaga a pasta e sobe o agente de novo 0,3 s depois. Com o WatchdogSec (1 s), mata o
# agente parado (estado T) ha mais de 1 s: e o agente que deixou de avisar.
# Pelo estado e nao por um relogio de batidas: com a maquina ocupada, um laco
# de batidas atrasa mais de 1 s sozinho, e o watchdog de mentira mataria um
# agente vivo -- o roteiro veria 0,0 de outra mao e pararia. Guardas:
#   completo   ExecStopPost, WatchdogSec e RuntimeDirectory
#   sem        nenhum dos tres: a unit de antes do guarda
#   quebrado   os tres declarados, e o ExecStopPost nao roda nada
#   surdo      os tres declarados, e o watchdog nunca mata ninguem
systemd_falso() {   # $1 = arvore, $2 = guarda
    local d=$1 pid st parado
    case "$2" in
        sem) : > "$d/unit.execstoppost"; echo 0 > "$d/unit.watchdog"; : > "$d/unit.runtimedirectory" ;;
        *)   echo "{ path=/usr/lib/nexus-sense/guarda-ventoinha.sh ; argv[]=/usr/lib/nexus-sense/guarda-ventoinha.sh ; }" \
                 > "$d/unit.execstoppost"
             echo 1s > "$d/unit.watchdog"; echo nexus-sense > "$d/unit.runtimedirectory" ;;
    esac
    while [ -d "$d" ]; do
        [ "$2" = sem ] || mkdir -p "$d/run/nexus-sense"
        ( while [ -d "$d" ]; do sleep 0.05; done ) &
        pid=$!
        poe "$d/agente.pid" "$pid"
        parado=
        while kill -0 "$pid" 2> /dev/null; do
            st=$(cut -d' ' -f3 "/proc/$pid/stat" 2> /dev/null)
            if [ "$st" != T ]; then
                parado=
            elif [ -z "$parado" ]; then
                parado=${EPOCHREALTIME/[.,]/}
            elif [ "$2" != sem ] && [ "$2" != surdo ] \
                 && [ $(( ${EPOCHREALTIME/[.,]/} - parado )) -gt 1000000 ]; then
                kill -KILL "$pid"
            fi
            sleep 0.05
        done
        wait "$pid" 2> /dev/null
        poe "$d/agente.pid" 0
        case "$2" in
            completo|surdo)
                GUARDA_RAIZ="$d" RUNTIME_DIRECTORY="$d/run/nexus-sense" "$GUARDA" >> "$d/guarda.log" 2>&1 ;;
        esac
        rm -rf "$d/run/nexus-sense"
        sleep 0.3
    done 2> /dev/null
}

com_systemd() {   # $1 = guarda
    systemd_falso "$D" "$1" &
    ECS+=("$!")
    local i
    for ((i = 0; i < 30; i++)); do
        [ "$(cat "$D/agente.pid" 2> /dev/null || echo 0)" != 0 ] && return 0
        sleep 0.1
    done
    falha "o systemd de mentira nao subiu o agente"
}

# ─── 0. o mapa de E2 e a regra, com numeros ─────────────────────────
echo "--- o mapa de E2 e a regra da secao 7"
MC="100:7539 80:6250 60:4911 50:4170 40:3411 30:2582 20:2009"
MG="100:7069 80:5891 60:4647 50:3970 40:3252 30:2469 20:1675"
mapa_da() {   # $1 = rpm, $2 = mapa, $3 = esperado, $4 = descricao
    local r
    r=$("$S" _mapa "$1" "$2")
    [ "$r" = "$3" ] && ok "mapa: $4" || falha "mapa: $4: deu '$r', esperado $3"
}
# Os tetos medidos (docs/plano-curva.md, secao 2.1): a curva alta para em
# ~6550 rpm, um manual de ~85%; a baixa em ~4500, ~54%.
mapa_da 6550 "$MC" 85 "o teto da curva alta, 6550 rpm na CPU, e o manual 85"
mapa_da 4500 "$MC" 54 "o teto da curva baixa, 4500 rpm na CPU, e o manual 54"
mapa_da 5891 "$MG" 80 "um ponto do mapa da GPU devolve a propria porcentagem"
mapa_da 1500 "$MC" 20 "abaixo do piso fica no menor ponto do mapa"
mapa_da 9000 "$MC" 99 "acima do topo fica em 99: 100,100 nao e manual"

regra_da() {  # $1 = descricao, $2 = veredito esperado, $3... = os seis numeros
    local d=$1 v=$2 r
    shift 2
    r=$("$S" _regra "$@" | grep '^veredito')
    case "$r" in
        "veredito: $v "*) ok "regra: $d" ;;
        *) falha "regra: $d: '$r' (esperado $v)" ;;
    esac
}
regra_da "ganho de 6,5% acima do ruido: R1"          R1 3000 3200 3010 NA NA NA
regra_da "ganho de 4,8%, sem jogo: incompleto"       incompleto 3000 3145 3000 NA NA NA
regra_da "ganho de 4,8% e GPU 2 C mais fria: R0"     R0 3000 3145 3000 80000 78000 80000
regra_da "GPU 3 C mais fria basta, sem a CPU: R1"    R1 NA NA NA 80000 77000 80000
# 6,7% de ganho, mas 3 e 7 diferem em 10%: o ganho nao sai do ruido.
regra_da "ganho de 6,7% abaixo do ruido de 10%: R0"  R0 2850 3200 3150 80000 79000 80000
"$S" _regra 3000 3145 3000 80000 78000 80000 | grep -q 'ganho de 4.8%; ruido (3 contra 7) de 0.0%' \
    && ok "regra: a linha da CPU diz o ganho e o ruido" \
    || falha "regra: a linha da CPU nao diz o ganho e o ruido: $("$S" _regra 3000 3145 3000 80000 78000 80000 | head -1)"

# ─── 1. o E-C2 inteiro ──────────────────────────────────────────────
# Os tempos, encolhidos: a 0,05 s por amostra cada estagio dura 1 s de
# relogio, e conta a mediana das ultimas cinco amostras.
c2() {   # $1 = nome, $2 = temperamento do EC, $3 = jeito da pessoa -> arvore em $D, comando em C2
    nova "$1" "${2:-curvas}"
    com_usuario "${3:-normal}"
    C2=(env "${MAPA_FALSO[@]}" ENSAIO_C2_CARGA=20 ENSAIO_C2_JANELA=5 ENSAIO_C2_DESCIDA=40
        ENSAIO_C2_JOGO=20 ENSAIO_C2_LIMIAR_CURVA=4950 ENSAIO_GESTO_PRAZO=200 ENSAIO_GESTO_ACOMODA=10
        ENSAIO_CARGA_N=2 ENSAIO_FOLGA_CARGA=30 ENSAIO_CARGA_CMD="exec $D/bin/carga-falsa"
        "$S" ec2 "$D/ec2.tsv")
}
col() {   # $1 = fase, $2 = coluna -> os valores distintos dela nessa fase
    awk -F'\t' -v f="$1" -v c="$2" '$3 == f { print $c }' "$D/ec2.tsv" | sort -u | tr '\n' ' '
}

echo "--- o E-C2 inteiro"
c2 ec2-inteiro
roda "$D" "${C2[@]}"
confere "E-C2 completo termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
sem_carga "no fim do E-C2"
falta=0
for f in 1 2 3 4 5 6 7 8 9 10 j1 j2 j3; do
    cut -f3 "$D/ec2.tsv" | grep -qxF "c2:$f" || { falha "o traco nao tem o estagio $f (tem: $(fases_de "$D/ec2.tsv"))"; falta=1; }
done
[ "$falta" = 0 ] && ok "o traco tem os dez estagios e os tres trechos com o jogo"
awk -F'\t' 'NF != 31 { r = 1 } END { exit r }' "$D/ec2.tsv" \
    && ok "toda linha do traco tem as 31 colunas, com ppd e epp no fim" \
    || falha "ha linha do traco sem as 31 colunas"
head -1 "$D/ec2.tsv" | grep -q $'\tload1\tppd\tepp$' \
    && ok "o cabecalho termina em ppd e epp" || falha "o cabecalho nao termina em ppd e epp"
# Uma alavanca de cada vez: coluna 27 e o modo maximo, 30 o perfil de energia,
# 31 o EPP, 4 o que o roteiro escreveu.
alavanca() {   # $1 = estagio, $2 = modo maximo, $3 = perfil de energia, $4 = fan_speed
    local m p e
    m=$(col "c2:$1" 27); p=$(col "c2:$1" 30); e=$(col "c2:$1" 4)
    if [ "$m" = "$2 " ] && [ "$p" = "$3 " ] && [ "$e" = "$4 " ]; then
        ok "estagio $1: modo maximo $2, perfil de energia $3, fan_speed $4"
    else
        falha "estagio $1: modo maximo '$m', perfil de energia '$p', fan_speed '$e' (esperado $2, $3, $4)"
    fi
}
alavanca 1 false performance 0,0
alavanca 2 false balanced 0,0
# Pedido com o perfil em balanced, o modo o poe em performance: e o efeito
# conferido. Desligado, devolve o balanced, e o roteiro poe o performance do
# estagio 8. A ordem das trocas do roteiro e dos gestos, uma linha cada:
ordem=$(grep -E '^(  perfil de energia: |GESTO )' "$D/saida.txt" \
    | sed -E 's/^GESTO ([0-9]+):.*/G\1/; s/^  perfil de energia: //' | tr '\n' '|')
[ "$ordem" = "balanced -> performance|performance -> balanced|G1|G2|balanced -> performance|performance -> balanced|balanced -> performance|G3|G4|G5|" ] \
    && ok "o roteiro troca o perfil de energia so com o modo desligado, e antes do 3 quem o troca e o modo" \
    || falha "a ordem das trocas e dos gestos: $ordem"
alavanca 3 true performance 0,0
alavanca 4 true performance 94,95
alavanca 5 true performance 92,92
alavanca 6 true performance 100,100
alavanca 7 true performance 0,0
alavanca 8 false performance 0,0
alavanca 9 false balanced 0,0
alavanca 10 false performance 0,0
alavanca j1 true performance 0,0
alavanca j2 true performance 100,100
alavanca j3 true performance 0,0
[ "$(col c2:2 31)" = "balance_performance " ] && [ "$(col c2:1 31)" = "performance " ] \
    && ok "a coluna do EPP segue o perfil de energia" \
    || falha "a coluna do EPP nao segue o perfil de energia: '$(col c2:1 31)' e '$(col c2:2 31)'"
awk -F'\t' '$3 ~ /^c2:j[0-9]$/ && $28 == 0 { r = 1 } $3 ~ /^c2:[0-9]+$/ && $28 != 0 { r = 1 } END { exit r }' "$D/ec2.tsv" \
    && ok "o jogo aberto nos tres trechos dele, e em nenhum estagio de CPU" \
    || falha "o jogo nao esteve onde devia"
grep -q '^controle: o estagio 4 girou o teto do 3' "$D/ec2.resumo.txt" \
    && ok "o controle do estagio 4 passou" || falha "o resumo nao traz o controle do estagio 4"
grep -q 'C1 -- .* 1:baixa 2:baixa 3:alta 7:alta 8:baixa 9:baixa 10:baixa' "$D/ec2.resumo.txt" \
    && ok "C1: a curva de cada estagio em automatico" \
    || falha "C1 errado: $(grep 'C1 --' "$D/ec2.resumo.txt")"
grep -q 'quem escolhe e o modo maximo' "$D/ec2.resumo.txt" \
    && ok "C1: o padrao do modo maximo e reconhecido" || falha "C1: o padrao do modo maximo nao foi dito"
# Os numeros do EC de mentira: 2530 MHz no automatico da curva alta, 2560 no
# maximo do firmware; a GPU pelo EC a 79,4 C contra 78,8.
grep -q 'a 2560 MHz contra 2530, a media de 3 e 7: ganho de 1.2%; ruido (3 contra 7) de 0.0%' "$D/ec2.resumo.txt" \
    && ok "a regra le os estagios 3, 6 e 7" \
    || falha "a linha da CPU nao traz os numeros esperados: $(grep '^CPU:' "$D/ec2.resumo.txt")"
grep -q 'GPU pelo EC a 78.8 C no maximo do firmware contra 79.4 C, a media dos automaticos: 0.6 C' "$D/ec2.resumo.txt" \
    && ok "a regra le os tres trechos com o jogo" \
    || falha "a linha do jogo nao traz os numeros esperados: $(grep '^jogo:' "$D/ec2.resumo.txt")"
grep -q '^veredito: R0' "$D/ec2.resumo.txt" \
    && ok "veredito R0" || falha "veredito errado: $(grep '^veredito' "$D/ec2.resumo.txt")"
confere_ppd "no fim, o perfil de energia volta ao da partida" balanced
grep -q '^maximum_mode = false' "$D/config.toml" \
    && ok "no fim, o modo maximo foi desligado a pedido do roteiro" || falha "o modo maximo ficou ligado"
[ "$(grep -c '^GESTO' "$D/saida.txt")" -eq 5 ] \
    && ok "cinco gestos: liga, desliga, liga para o jogo, abre o jogo, desliga" \
    || falha "gestos pedidos: $(grep -c '^GESTO' "$D/saida.txt") (esperado 5)"
[ -z "$(ls -A "$D/run")" ] && ok "nenhum diretorio de trabalho sobrou" || falha "sobrou em run/: $(ls -A "$D/run")"

# O EC em que a rotacao compra mais: o mesmo roteiro chega a R1.
echo "--- o E-C2 com ganho"
c2 ec2-ganho ganho
roda "$D" "${C2[@]}"
confere "E-C2 com ganho termina com 0" "$?" 0 "0,0"
grep -q '^veredito: R1' "$D/ec2.resumo.txt" \
    && ok "com ganho, veredito R1" || falha "veredito errado: $(grep '^veredito' "$D/ec2.resumo.txt")"

# A curva alta que fica presa depois de o modo desligar.
echo "--- o E-C2 com a curva presa"
c2 ec2-presa presa
roda "$D" "${C2[@]}"
confere "E-C2 com a curva presa termina com 0" "$?" 0 "0,0"
grep -q '8 na alta: a curva alta fica presa' "$D/ec2.resumo.txt" \
    && grep -q '10 na alta e 1 na baixa' "$D/ec2.resumo.txt" \
    && ok "C1: a curva presa e reconhecida" \
    || falha "C1 nao reconhece a curva presa: $(grep -A4 'C1 --' "$D/ec2.resumo.txt")"

# ─── 2. o controle do E-C2 ──────────────────────────────────────────
# O mapa de verdade num EC de mentira: o manual que ele aponta nao gira o
# teto. E o caso "o mapa de E2 nao vale sob carga": o ensaio para.
echo "--- o controle do estagio 4"
c2 ec2-controle
C2=("${C2[@]/ENSAIO_MAPA_CPU=*/ENSAIO_MAPA_CPU=$MC}")
C2=("${C2[@]/ENSAIO_MAPA_GPU=*/ENSAIO_MAPA_GPU=$MG}")
roda "$D" "${C2[@]}"
confere "mapa que nao vale: o E-C2 para no controle" "$?" 13 "0,0"
grep -q '^controle: FALHOU' "$D/ec2.resumo.txt" \
    && ok "o resumo diz que o controle falhou" || falha "o resumo nao diz que o controle falhou"
if ! cut -f3 "$D/ec2.tsv" | grep -qxF c2:4; then
    falha "o traco nao tem o estagio 4: nao ha como afirmar que o 5 nao rodou"
elif cut -f3 "$D/ec2.tsv" | grep -qxF c2:5; then
    falha "o estagio 5 rodou depois de o controle falhar"
else
    ok "o estagio 5 nao roda depois de o controle falhar"
fi
grep -q 'o modo maximo segue ligado' "$D/saida.txt" \
    && ok "parado com o modo ligado, o roteiro pede para desliga-lo" \
    || falha "parado com o modo ligado, o roteiro nao disse nada do modo"
sem_carga "depois do controle"

# ─── 3. o aborto, o kill -9 e o gesto que nao vem ───────────────────
echo "--- o E-C2 interrompido"
no_estagio() {   # $1 = estagio. Espera ele aparecer no traco, com a carga no ar
    local i
    for ((i = 0; i < 100; i++)); do
        cut -f3 "$D/ec2.tsv" 2> /dev/null | grep -qxF "c2:$1" && [ -e "$D/carga_ligada" ] && return 0
        sleep 0.1
    done
    falha "o E-C2 nao chegou ao estagio $1 com carga"
    return 1
}

# O controle positivo do aborto: um limite estourado no estagio 1, com o
# perfil de energia ja trocado pelo roteiro.
c2 ec2-aborto
C2=("${C2[@]/ENSAIO_C2_CARGA=20/ENSAIO_C2_CARGA=200}")
lanca "$D" "${C2[@]}"
if no_estagio 1; then
    poe "$D/sys/class/hwmon/hwmon7/temp2_input" 85000
    wait "$PID"
    confere "limite estourado no estagio 1: sai com 10 e devolve a ventoinha" "$?" 10 "0,0"
    sem_carga "depois do aborto"
    confere_ppd "depois do aborto, o perfil de energia volta ao da partida" balanced
    grep -q 'aborto .*temp GPU do acer em 85000' "$D/ec2.resumo.txt" \
        && ok "o resumo diz qual limite estourou" || falha "o resumo nao diz o limite"
    cut -f3 "$D/ec2.tsv" | grep -qxF c2:2 \
        && falha "o estagio 2 rodou depois do aborto" || ok "nada roda depois do aborto"
fi

c2 ec2-kill9
C2=("${C2[@]/ENSAIO_C2_CARGA=20/ENSAIO_C2_CARGA=200}")
lanca "$D" "${C2[@]}"
if no_estagio 1; then
    kill -KILL "$PID"
    wait "$PID" 2> /dev/null
    espera_fan "$D" "0,0" 30 \
        && ok "kill -9 no estagio 1: o vigia devolve 0,0" \
        || falha "kill -9 no estagio 1: fan_speed ficou em '$(fan "$D")'"
    for ((i = 0; i < 30; i++)); do [ "$(ppd)" = balanced ] && break; sleep 0.1; done
    confere_ppd "kill -9 no estagio 1: o vigia devolve o perfil de energia" balanced
    sem_carga "kill -9 no estagio 1"
fi

c2 ec2-sem-gesto curvas ausente
C2=("${C2[@]/ENSAIO_GESTO_PRAZO=200/ENSAIO_GESTO_PRAZO=15}")
roda "$D" "${C2[@]}"
confere "o modo maximo nao e ligado no prazo: sai com 11" "$?" 11 "0,0"
grep -q 'o gesto 1 nao veio no prazo' "$D/saida.txt" \
    && ok "e diz que o gesto nao veio" || falha "nao disse que o gesto nao veio"
confere_ppd "sem o gesto, o perfil de energia volta ao da partida" balanced

# O modo liga e o perfil de energia nao vai a performance: o gesto nao teve
# o efeito que tem na bandeja, e a medicao nao conta.
c2 ec2-sem-ppd curvas sem_ppd
roda "$D" "${C2[@]}"
confere "o modo maximo liga e o perfil de energia nao vai a performance: sai com 11" "$?" 11 "0,0"
grep -q 'nao foi a performance' "$D/saida.txt" \
    && ok "e diz que o efeito do gesto nao apareceu" || falha "nao disse que o efeito nao apareceu"

# ─── 4. a partida do E-C2 ───────────────────────────────────────────
echo "--- a partida do E-C2"
recusa_c2() {   # $1 = caso, $2 = descricao, $3 = arquivo, $4 = valor
    local rc
    c2 "ec2-partida-$1"
    poe "$D/$3" "$4"
    roda "$D" "${C2[@]}"; rc=$?
    confere "E-C2 recusa comecar: $2" "$rc" 12 "0,0"
    [ -s "$D/busctl.log" ] && grep -q set-property "$D/busctl.log" \
        && falha "E-C2 recusou e mesmo assim mexeu no perfil de energia" || true
}
recusa_c2 maximo "modo maximo ligado"  config.toml "maximum_mode = true"
recusa_c2 perfil "perfil balanced"     sys/firmware/acpi/platform_profile balanced
recusa_c2 quente "pacote a 60 C"       sys/class/hwmon/hwmon11/temp4_input 61000
recusa_c2 jogo   "jogo aberto"         processos GameThread
c2 ec2-partida-manual
poe "$(FAN_DE "$D")" "30,30"
roda "$D" "${C2[@]}"
confere "E-C2 recusa comecar: ventoinha em manual" "$?" 12 "30,30"

# Numa arvore de mentira o barramento e o da maquina de verdade: sem um
# busctl dado de proposito o roteiro nao fala com ninguem -- e o E-C2, que
# precisa do perfil de energia, sai com alvo ausente.
c2 ec2-sem-busctl
roda "$D" env ENSAIO_BUSCTL= "${C2[@]}"
confere "sem busctl, o E-C2 sai com alvo ausente" "$?" 3 "0,0"
[ ! -e "$D/busctl.log" ] \
    && ok "e nenhum busctl foi chamado, nem pelo nome" \
    || falha "um busctl foi chamado: $(head -1 "$D/busctl.log")"

# ─── 5. so a parte com o jogo ───────────────────────────────────────
echo "--- o E-C2, so a parte com o jogo"
c2 ec2-jogo
C2=("${C2[@]/%ec2/ec2-jogo}")
roda "$D" "${C2[@]}"
confere "a parte com o jogo sozinha termina com 0" "$?" 0 "0,0"
fases=$(fases_de "$D/ec2.tsv")
case "$fases" in
    *"c2:1 "*) falha "a parte com o jogo rodou estagio de CPU: $fases" ;;
    *"c2:j3 "*) ok "so os tres trechos com o jogo" ;;
    *) falha "faltam os trechos com o jogo: $fases" ;;
esac
grep -q '^veredito: incompleto' "$D/ec2.resumo.txt" \
    && ok "sem a parte de CPU, o veredito diz que esta incompleto" \
    || falha "veredito errado: $(grep '^veredito' "$D/ec2.resumo.txt")"
confere_ppd "a parte com o jogo devolve o perfil de energia" balanced

# O jogo ja aberto na partida, com o modo desligado: o pedido do modo nao
# confunde o jogo aberto com outra pessoa na maquina.
c2 ec2-jogo-aberto
C2=("${C2[@]/%ec2/ec2-jogo}")
poe "$D/processos" GameThread
roda "$D" "${C2[@]}"
confere "a parte com o jogo, com o jogo ja aberto, termina com 0" "$?" 0 "0,0"
[ "$(grep -c '^GESTO' "$D/saida.txt")" -eq 2 ] \
    && ok "so dois gestos: ligar e desligar o modo; o jogo ja estava aberto" \
    || falha "gestos: $(grep '^GESTO' "$D/saida.txt" | cut -c1-40 | tr '\n' '|')"

# ─── 6. o E-C3 ──────────────────────────────────────────────────────
echo "--- o E-C3"
c3() {   # $1 = nome -> arvore em $D, comando em C3
    nova "$1"
    C3=(env ENSAIO_C3_SEGURA=3 ENSAIO_C3_ESTAB=2 ENSAIO_C3_ESCUTA=4 ENSAIO_C3_TROCA=2
        ENSAIO_C3_FALSO=2 ENSAIO_C3_RESPOSTA=40 "$S" ec3 "$D/ec3.tsv")
}
# t ate 45, j ate 75, nada depois. Um "x" no meio, que tem de ser recusado.
printf '%s\n' t t x j j j n n n n s n s n > "$T/respostas-ec3"
c3 ec3-inteiro
roda "$D" "${C3[@]}" < "$T/respostas-ec3"
confere "E-C3 completo termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
grep -q '^aceita trabalhando ate: 45% (2850 / 2525 rpm)' "$D/ec3.resumo.txt" \
    && ok "o limite de trabalho e o fim do que se aceitou trabalhando" \
    || falha "limite de trabalho errado: $(grep 'trabalhando' "$D/ec3.resumo.txt")"
grep -q '^aceita jogando ate: 75%' "$D/ec3.resumo.txt" \
    && ok "o limite de jogo e o fim do que se aceitou jogando" \
    || falha "limite de jogo errado: $(grep 'jogando ate' "$D/ec3.resumo.txt")"
grep -q 'responda com uma destas' "$D/saida.txt" \
    && ok "uma resposta que nao vale e pedida de novo" || falha "a resposta 'x' passou"
awk -F'\t' '$3 == "c3:100" && $4 == "100,100" && $5 == "100,100" { n++ } END { exit !n }' "$D/ec3.tsv" \
    && ok "a varredura passa pelo maximo do firmware" || falha "a varredura nao passou pelo 100,100"
# Os degraus em torno de 45: 35 para 40, o controle parado em 40, 40 para 45,
# 45 para 50. Coluna 4 e o que o roteiro escreveu.
[ "$(awk -F'\t' '$3 == "c3:degrau1:escuta" { print $4 }' "$D/ec3.tsv" | sort -u | tr '\n' ' ')" = "35,35 40,40 " ] \
    && ok "o degrau 1 sobe de 35% para 40% dentro da janela" \
    || falha "o degrau 1 nao subiu de 35 para 40"
[ "$(awk -F'\t' '$3 == "c3:degrau2:escuta" { print $4 }' "$D/ec3.tsv" | sort -u | tr '\n' ' ')" = "40,40 " ] \
    && ok "o degrau de controle nao troca nada" \
    || falha "o degrau de controle trocou a ventoinha"
grep -q '^degrau 2: sem troca, parado em 40% (o controle) -> ouviu: n' "$D/ec3.resumo.txt" \
    && grep -q '^degrau 4: de 45% para 50% -> ouviu: n' "$D/ec3.resumo.txt" \
    && ok "o resumo traz cada degrau e cada resposta" \
    || falha "o resumo dos degraus: $(grep '^degrau' "$D/ec3.resumo.txt" | tr '\n' '|')"

c3 ec3-sem-resposta
printf '%s\n' t t > "$T/respostas-curtas"
roda "$D" "${C3[@]}" < "$T/respostas-curtas"
confere "a entrada acaba sem resposta: sai com 11 e devolve a ventoinha" "$?" 11 "0,0"

c3 ec3-aborto
C3=("${C3[@]/ENSAIO_C3_SEGURA=3/ENSAIO_C3_SEGURA=200}")
lanca "$D" "${C3[@]}" < "$T/respostas-ec3"
for ((i = 0; i < 100; i++)); do
    cut -f3 "$D/ec3.tsv" 2> /dev/null | grep -qxF c3:30 && break
    sleep 0.1
done
poe "$D/sys/class/thermal/thermal_zone4/temp" 81050
wait "$PID"
confere "limite estourado no meio da varredura: sai com 10 e devolve a ventoinha" "$?" 10 "0,0"

c3 ec3-falso-errado
C3=("${C3[@]/ENSAIO_C3_FALSO=2/ENSAIO_C3_FALSO=7}")
roda "$D" "${C3[@]}" < "$T/respostas-ec3"
confere "o degrau de controle fora de 1 a 4: recusa" "$?" 12 "0,0"

# ─── 7. o E-C5 ──────────────────────────────────────────────────────
echo "--- o E-C5"
c5() {   # $1 = nome, $2 = guarda, $3 = jeito da pessoa, $4 = temperamento do EC -> arvore em $D, comando em C5
    nova "$1" "${4:-normal}"
    com_systemd "${2:-completo}"
    com_usuario "${3:-normal}"
    C5=(env ENSAIO_C5_DEPOIS=6 ENSAIO_C5_FORA=4 ENSAIO_GESTO_PRAZO=200
        ENSAIO_GUARDA_PRAZO_KILL=3 ENSAIO_GUARDA_FOLGA=3 ENSAIO_GUARDA_VOLTA=3 "$S" ec5 "$D/ec5.tsv")
}
estado() { echo "$D/state/nexus-sense/ensaio-ec5-reinicio.txt"; }

c5 ec5-inteiro
roda "$D" "${C5[@]}"
confere "E-C5 sai com 0 pedindo o reinicio, e deixa o manual de proposito" "$?" 0 "95,95"
for g in suspensao cabo "perfil termico"; do
    grep -q "^$g: manteve o manual" "$D/ec5.resumo.txt" \
        && ok "$g: o EC manteve o manual" \
        || falha "$g: $(grep "^$g:" "$D/ec5.resumo.txt")"
done
grep -q '^    perfis vistos na suspensao: balanced-performance balanced$' "$D/ec5.resumo.txt" \
    && ok "a troca de perfil na suspensao fica registrada, e nao para o ensaio" \
    || falha "perfis na suspensao: $(grep 'perfis vistos' "$D/ec5.resumo.txt")"
grep -q '^    o agente atravessou a suspensao vivo' "$D/ec5.resumo.txt" \
    && ok "diz se o agente atravessou a suspensao" \
    || falha "o agente na suspensao: $(grep 'o agente' "$D/ec5.resumo.txt" | head -2)"
grep -q '^guarda, kill -9: PASSOU' "$D/ec5.resumo.txt" && grep -q '^guarda, SIGSTOP: PASSOU' "$D/ec5.resumo.txt" \
    && ok "o guarda devolve a ventoinha no kill -9 e no SIGSTOP" \
    || falha "o guarda: $(grep '^guarda' "$D/ec5.resumo.txt" | tr '\n' '|')"
[ "$(grep -c 'que ele escreveu; devolvida ao automatico' "$D/guarda.log")" -eq 2 ] \
    && ok "quem devolveu foi o guarda de verdade, pelo registro, nas duas vezes" \
    || falha "o guarda nao devolveu pelo registro: $(tr '\n' '|' < "$D/guarda.log")"
grep -q '^GESTO .*reinicie a maquina agora' "$D/saida.txt" \
    && ok "pede o reinicio por ultimo" || falha "nao pediu o reinicio"
[ -s "$(estado)" ] && ok "a continuacao fica gravada para depois do reinicio" || falha "nao gravou a continuacao"
sleep 0.3
# run/nexus-sense e o RuntimeDirectory do agente de mentira, que segue no ar.
[ -z "$(ls -A "$D/run" | grep -vx nexus-sense)" ] \
    && ok "nem o trap nem o vigia devolveram o manual: o diretorio de trabalho saiu" \
    || falha "sobrou em run/: $(ls -A "$D/run")"
[ "$(fan "$D")" = "95,95" ] && ok "o manual segue de pe para o reinicio" || falha "o manual nao ficou: '$(fan "$D")'"

# O reinicio: outra partida, e o driver devolve o manual que gravou.
poe "$D/proc/sys/kernel/random/boot_id" 99999999-8888-7777-6666-555555555555
roda "$D" "$S" ec5-volta
confere "depois do reinicio, o ec5-volta le e devolve a ventoinha" "$?" 0 "0,0"
[ "$(cat "$D/run/nexus-sense/ventoinha" 2> /dev/null | tail -1)" = "95,95" ] \
    && ok "o manual do reinicio vai registrado como do agente, como o da curva" \
    || falha "o manual do reinicio nao foi registrado: '$(cat "$D/run/nexus-sense/ventoinha" 2> /dev/null)'"
grep -q '^reinicio: o manual 95,95 VOLTOU na partida' "$D/ec5.resumo.txt" \
    && ok "o resumo diz que o manual voltou na partida" \
    || falha "o resumo do reinicio: $(grep '^reinicio:' "$D/ec5.resumo.txt" | tail -1)"
[ ! -e "$(estado)" ] && ok "a continuacao sai depois de lida" || falha "a continuacao ficou"

# Como a maquina: o EC larga o manual na suspensao e so o retoma com uma
# escrita nova. O roteiro reescreve os 95% antes do gesto seguinte, e o cabo e
# o perfil se medem a partir do manual de verdade.
c5 ec5-larga-na-suspensao completo larga_na_suspensao
roda "$D" "${C5[@]}"
confere "suspensao que larga o manual: o E-C5 segue ate o reinicio" "$?" 0 "95,95"
grep -q '^suspensao: LARGOU o manual e nao voltou a ele' "$D/ec5.resumo.txt" \
    && grep -q '^cabo: manteve o manual' "$D/ec5.resumo.txt" \
    && grep -q '^perfil termico: manteve o manual' "$D/ec5.resumo.txt" \
    && ok "depois da suspensao o manual e reescrito, e o cabo e o perfil medem a partir dele" \
    || falha "a suspensao contaminou os gestos seguintes: $(grep -E '^(suspensao|cabo|perfil termico):' "$D/ec5.resumo.txt" | tr '\n' '|')"
roda "$D" "$S" ec5-volta > /dev/null

# So o cabo, sem pedir o reinicio: repetir uma parte nao exige refazer o resto.
c5 ec5-so-o-cabo completo
C5=("${C5[@]/%ec5/ec5}")
roda "$D" env ENSAIO_C5_GESTOS=cabo ENSAIO_C5_REINICIO=0 "${C5[@]}"
confere "so o cabo, sem reinicio: termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
grep -q 'GESTO 1: tire o cabo' "$D/saida.txt" && ! grep -q 'suspenda' "$D/saida.txt" \
    && ok "so o gesto pedido" || falha "gestos: $(grep '^GESTO' "$D/saida.txt" | tr '\n' '|')"
[ ! -e "$(estado)" ] && ok "sem reinicio, sem continuacao gravada" || falha "gravou continuacao sem pedir reinicio"

# Nenhum gesto: so o guarda e o reinicio. Vazio e nenhum, e nao o padrao.
c5 ec5-sem-gestos completo
roda "$D" env ENSAIO_C5_GESTOS= "${C5[@]}"
confere "sem gestos: vai direto ao guarda e ao reinicio" "$?" 0 "95,95"
grep -q '^GESTO 1: reinicie' "$D/saida.txt" \
    && ok "o unico gesto pedido e o reinicio" || falha "gestos: $(grep '^GESTO' "$D/saida.txt" | tr '\n' '|')"
roda "$D" "$S" ec5-volta > /dev/null

# O EC que larga o manual na suspensao e volta a ele. A unit de hoje, sem
# guarda: o exercicio nao roda, e o codigo de saida diz isso.
c5 ec5-larga sem larga_e_volta
roda "$D" "${C5[@]}"
confere "unit sem guarda: sai com 17, o manual de pe para o reinicio" "$?" 17 "95,95"
grep -q '^suspensao: LARGOU o manual e voltou a ele' "$D/ec5.resumo.txt" \
    && ok "a suspensao que larga e volta e reconhecida" \
    || falha "suspensao: $(grep '^suspensao:' "$D/ec5.resumo.txt")"
grep -q 'nao tem ExecStopPost' "$D/ec5.resumo.txt" \
    && ok "o resumo diz que o guarda ainda nao existe" || falha "o resumo nao diz por que o guarda nao rodou"
# Desistiu do reinicio: o mesmo boot_id. O ec5-volta devolve e diz.
roda "$D" "$S" ec5-volta
confere "sem reinicio, o ec5-volta devolve a ventoinha e sai com 11" "$?" 11 "0,0"

# O perfil que o firmware trocou ao acordar nao volta: o agente nao fez a
# parte dele, e o ensaio para antes do cabo -- com o manual devolvido.
c5 ec5-perfil-preso completo perfil_preso
roda "$D" "${C5[@]}"
confere "o perfil nao volta depois da suspensao: sai com 11" "$?" 11 "0,0"
grep -q 'o perfil nao voltou' "$D/saida.txt" \
    && ok "e diz que quem devolve o perfil e o agente" || falha "nao disse do perfil que nao voltou"

c5 ec5-quebrado quebrado
roda "$D" "${C5[@]}"
confere "guarda que nao devolve: sai com 14" "$?" 14 "95,95"
grep -q '^guarda, kill -9: FALHOU' "$D/ec5.resumo.txt" && grep -q '^guarda, SIGSTOP: FALHOU' "$D/ec5.resumo.txt" \
    && ok "as duas metades do guarda reprovam" \
    || falha "o guarda quebrado: $(grep '^guarda' "$D/ec5.resumo.txt" | tr '\n' '|')"
roda "$D" "$S" ec5-volta > /dev/null

# Um EC que fica onde o manual o deixou: fan_speed volta a 0,0 pelo guarda, e
# a rotacao nao sai do manual. O guarda nao passa so por ter escrito.
c5 ec5-gruda completo normal gruda
roda "$D" "${C5[@]}"
confere "fan_speed devolvido e a rotacao presa no manual: sai com 14" "$?" 14 "95,95"
grep -q '^guarda, kill -9: FALHOU -- fan_speed em 0,0, mas a rotacao nao saiu do manual' "$D/ec5.resumo.txt" \
    && ok "o guarda reprova quando so o fan_speed volta" \
    || falha "o guarda com a rotacao presa: $(grep '^guarda' "$D/ec5.resumo.txt" | tr '\n' '|')"
roda "$D" "$S" ec5-volta > /dev/null

# Sem o registro o guarda nao reconhece o manual como do agente, e o deixa:
# e o que faz com um manual escolhido na janela. A pasta some no meio -- a
# unit sem RuntimeDirectory --, e o exercicio diz que nao rodou.
c5 ec5-sem-pasta completo
echo "" > "$D/unit.runtimedirectory"
roda "$D" "${C5[@]}"
confere "unit sem RuntimeDirectory: o guarda nao roda, sai com 17" "$?" 17 "95,95"
grep -q 'nao tem RuntimeDirectory' "$D/ec5.resumo.txt" \
    && ok "e diz que falta a pasta do registro" || falha "nao disse que falta a pasta do registro"
roda "$D" "$S" ec5-volta > /dev/null

# Um watchdog que nunca mata: o agente fica travado ate o roteiro o soltar.
c5 ec5-surdo surdo
roda "$D" "${C5[@]}"
confere "watchdog que nao age: sai com 14" "$?" 14 "95,95"
p=$(cat "$D/agente.pid")
if [ "$p" -gt 0 ] 2> /dev/null && [ "$(cut -d' ' -f3 "/proc/$p/stat" 2> /dev/null)" != T ]; then
    ok "o roteiro solta o agente que deixou sob SIGSTOP"
else
    falha "o agente ficou parado (pid $p)"
    kill -CONT "$p" 2> /dev/null
fi
roda "$D" "$S" ec5-volta > /dev/null

c5 ec5-sem-systemctl
roda "$D" env ENSAIO_SYSTEMCTL= "${C5[@]}"
confere "sem systemctl, o guarda nao roda: sai com 17" "$?" 17 "95,95"
[ ! -e "$D/systemctl.log" ] \
    && ok "e nenhum systemctl foi chamado, nem pelo nome" \
    || falha "um systemctl foi chamado: $(head -1 "$D/systemctl.log")"
roda "$D" "$S" ec5-volta > /dev/null

# O controle positivo do aborto no E-C5: um limite estoura enquanto a
# pessoa nao faz o gesto.
c5 ec5-aborto completo ausente
lanca "$D" "${C5[@]}"
for ((i = 0; i < 100; i++)); do
    grep -q '^GESTO 1' "$D/saida.txt" 2> /dev/null && break
    sleep 0.1
done
poe "$D/sys/class/thermal/thermal_zone6/temp" 81050
wait "$PID"
confere "limite estourado esperando a suspensao: sai com 10 e devolve a ventoinha" "$?" 10 "0,0"
[ ! -e "$(estado)" ] && ok "abortado, nao deixa continuacao de reinicio" || falha "abortado, deixou a continuacao"

c5 ec5-pendente
mkdir -p "$(dirname "$(estado)")"; echo "valor=95,95" > "$(estado)"
roda "$D" "${C5[@]}"
confere "com um reinicio pendente de outra rodada: recusa" "$?" 12 "0,0"

# ─── 8. o roteiro nao sabe o indice de ninguem ──────────────────────
codigo() { grep -v '^[[:space:]]*#' "$S"; }
if codigo | grep -qE 'hwmon[0-9]|thermal_zone[0-9]|rfkill[0-9]'; then
    falha "o roteiro cita um indice de hwmon ou de zona termica"
else
    ok "nenhum indice de hwmon ou de zona termica no roteiro"
fi

echo
[ "$fail" -eq 0 ] && echo "PASSOU" || echo "FALHOU"
exit "$fail"
