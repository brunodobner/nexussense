#!/bin/bash
# O roteiro do ensaio termico devolve a ventoinha -- provado numa arvore de
# mentira, antes de ele encostar na maquina.
#
# tests/hardware/ensaio-termico.sh escreve em fan_speed de verdade. O que
# este teste guarda e o que nao pode falhar la: todo limite da secao 7 de
# docs/plano-termico.md encerra o ensaio e devolve 0,0; todo sinal devolve;
# um kill -9 e coberto pelo vigia; e uma escrita de outra mao NAO e desfeita.
#
# Nada aqui toca em /sys: o roteiro recebe ENSAIO_RAIZ, uma arvore plantada
# num tmpdir, com um "EC" de mentira que faz a rotacao seguir o fan_speed. Os
# indices de hwmon e de zona termica sao embaralhados de proposito: o roteiro
# tem de achar tudo pelo nome (armadilha 19).
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/tests/hardware/ensaio-termico.sh"

# shellcheck source=tests/shell/lib-arvore-termica.sh
source "$RAIZ/tests/shell/lib-arvore-termica.sh"

# ─── 1. todo limite e toda condicao encerram e devolvem ─────────────
# O roteiro escreve 40,40 e fica amostrando; a provocacao vem com ele ja no
# ar. Limite de temperatura sai com 10; pessoa, bateria e sensor que some
# saem com 11. Nos dois a ventoinha volta a 0,0 -- menos quando foi outra
# mao que escreveu nela.
provoca() {
    local h="$D/sys/class/hwmon" z="$D/sys/class/thermal" b="$D/sys/class/power_supply"
    case "$1" in
        pacote)      poe "$h/hwmon11/temp4_input" 98500 ;;
        crit_alarm)  poe "$h/hwmon11/temp4_crit_alarm" 1 ;;
        ec_cpu)      poe "$h/hwmon7/temp1_input" 99000 ;;
        ec_gpu)      poe "$h/hwmon7/temp2_input" 85000 ;;
        sen2)        poe "$z/thermal_zone4/temp" 81050 ;;
        sen3)        poe "$z/thermal_zone9/temp" 77050 ;;
        sen4)        poe "$z/thermal_zone2/temp" 91050 ;;
        sen5)        poe "$z/thermal_zone6/temp" 81050 ;;
        nvme1)       poe "$h/hwmon3/temp1_input" 75000 ;;
        nvme2)       poe "$h/hwmon40/temp1_input" 75000 ;;
        cabo)        poe "$b/ACAD/online" 0 ;;
        carga)       poe "$b/BAT1/charge_now" 1700000 ;;
        perfil)      poe "$D/sys/firmware/acpi/platform_profile" balanced ;;
        maximo)      poe "$D/config.toml" "maximum_mode = true" ;;
        jogo)        poe "$D/processos" GameThread ;;
        sensor_some) rm -f "$z/thermal_zone2/temp" ;;
        outra_mao)   poe "$(FAN_DE "$D")" "33,33" ;;
        automatico)  poe "$(FAN_DE "$D")" "0,0" ;;
    esac
}

caso() {     # $1 = provocacao, $2 = rc esperado, $3 = fan_speed esperado
    local rc
    nova "limite-$1"
    lanca "$D" env ENSAIO_SEGURA=40 "$S" _segura
    if ! espera_fan "$D" "40,40" 50; then
        falha "$1: o roteiro nao chegou a escrever 40,40"
        kill "$PID" 2> /dev/null
        return
    fi
    provoca "$1"
    wait "$PID"; rc=$?
    confere "$1 encerra com $2 e deixa fan_speed em $3" "$rc" "$2" "$3"
}

echo "--- limites de temperatura"
for l in pacote crit_alarm ec_cpu ec_gpu sen2 sen3 sen4 sen5 nvme1 nvme2; do
    caso "$l" 10 "0,0"
done

echo "--- pessoa, bateria e sensor que some"
for l in cabo carga perfil maximo jogo sensor_some; do
    caso "$l" 11 "0,0"
done

echo "--- outra mao na ventoinha: o roteiro para e NAO escreve por cima"
caso outra_mao 11 "33,33"
caso automatico 11 "0,0"
grep -q 'nao escreveu' "$T/limite-outra_mao/saida.txt" \
    && ok "o roteiro diz que deixou a ventoinha como a outra mao escreveu" \
    || falha "faltou a linha dizendo que a ventoinha ficou como estava"

# Um degrau abaixo de cada limite nao encerra: senao o teste acima passaria
# com um roteiro que aborta por qualquer coisa.
nova folga
poe "$D/sys/class/hwmon/hwmon11/temp4_input" 84000
poe "$D/sys/class/hwmon/hwmon7/temp1_input" 98000
poe "$D/sys/class/hwmon/hwmon7/temp2_input" 84000
poe "$D/sys/class/thermal/thermal_zone2/temp" 90050
poe "$D/sys/class/hwmon/hwmon3/temp1_input" 74000
roda "$D" env ENSAIO_SEGURA=40 ENSAIO_SEGURA_N=6 "$S" _segura
confere "logo abaixo dos limites o roteiro vai ate o fim" "$?" 0 "0,0"

# O pacote pede tres amostras seguidas: duas nao bastam.
nova pacote-duas
PASSO=0.2 lanca "$D" env ENSAIO_SEGURA=40 ENSAIO_SEGURA_N=12 "$S" _segura
espera_fan "$D" "40,40" 50 || falha "pacote por duas amostras: o roteiro nao escreveu 40,40"
poe "$D/sys/class/hwmon/hwmon11/temp4_input" 99000
sleep 0.3
poe "$D/sys/class/hwmon/hwmon11/temp4_input" 60000
wait "$PID"
confere "pacote acima do limite por menos de tres amostras nao encerra" "$?" 0 "0,0"

# ─── 2. sinais ──────────────────────────────────────────────────────
echo "--- sinais"
sinal() {    # $1 = nome, $2 = rc esperado
    nova "sinal-$1"
    lanca "$D" env --default-signal=INT env ENSAIO_SEGURA=40 "$S" _segura
    if ! espera_fan "$D" "40,40" 50; then
        falha "SIG$1: o roteiro nao chegou a escrever 40,40"; kill "$PID" 2> /dev/null; return
    fi
    kill "-$1" "$PID"
    wait "$PID"
    confere "SIG$1 devolve a ventoinha" "$?" "$2" "0,0"
}
sinal TERM 143
sinal INT 130
sinal HUP 129

# ─── 3. o vigia ─────────────────────────────────────────────────────
echo "--- o vigia"
nova vigia-kill9
lanca "$D" env ENSAIO_SEGURA=40 "$S" _segura
espera_fan "$D" "40,40" 50 || falha "kill -9: o roteiro nao chegou a escrever 40,40"
kill -KILL "$PID"
wait "$PID" 2> /dev/null
if espera_fan "$D" "0,0" 30; then
    ok "depois de um kill -9 o vigia devolve 0,0"
else
    falha "3 s depois do kill -9, fan_speed ainda e '$(fan "$D")'"
fi

# O vigia tambem respeita a outra mao: roteiro morto, valor que ele nao
# escreveu, e a ventoinha fica.
nova vigia-outra-mao
PASSO=5 lanca "$D" env ENSAIO_SEGURA=40 "$S" _segura
espera_fan "$D" "40,40" 50 || falha "vigia e outra mao: o roteiro nao escreveu 40,40"
poe "$(FAN_DE "$D")" "77,77"
kill -KILL "$PID"
wait "$PID" 2> /dev/null
sleep 0.6
[ "$(fan "$D")" = "77,77" ] \
    && ok "o vigia nao desfaz o que outra mao escreveu" \
    || falha "o vigia escreveu por cima da outra mao: fan_speed '$(fan "$D")'"

# Roteiro travado (SIGSTOP) e prazo vencido: o vigia o acorda e o encerra.
# O prazo e de 2 s e nao de 1: ele se conta em segundos inteiros, e com 1 o
# roteiro podia vencer o proprio prazo e devolver a ventoinha antes de este
# teste chegar a ver o 40,40 -- reprovava sob carga, por um defeito do teste.
nova vigia-prazo
lanca "$D" env ENSAIO_SEGURA=40 ENSAIO_PRAZO=2 ENSAIO_FOLGA_VIGIA=0 "$S" _segura
espera_fan "$D" "40,40" 50 || falha "prazo: o roteiro nao chegou a escrever 40,40"
kill -STOP "$PID"
if espera_fan "$D" "0,0" 60; then
    ok "roteiro travado: vencido o prazo, o vigia faz a ventoinha voltar"
else
    falha "roteiro travado: 6 s depois, fan_speed ainda e '$(fan "$D")'"
fi
kill -CONT "$PID" 2> /dev/null
wait "$PID" 2> /dev/null

# ─── 4. o automatico recusado vira maximo ───────────────────────────
echo "--- 0,0 recusado tres vezes"
nova recusa-zero
lanca "$D" env ENSAIO_SEGURA=40 ENSAIO_ESCRITOR="$D/bin/recusa-zero" "$S" _segura
espera_fan "$D" "40,40" 50 || falha "recusa: o roteiro nao chegou a escrever 40,40"
kill -TERM "$PID"
wait "$PID"
confere "sem conseguir 0,0, o roteiro deixa 100,100 e sai com 15" "$?" 15 "100,100"

nova recusa-zero-vigia
lanca "$D" env ENSAIO_SEGURA=40 ENSAIO_ESCRITOR="$D/bin/recusa-zero" "$S" _segura
espera_fan "$D" "40,40" 50 || falha "recusa pelo vigia: o roteiro nao escreveu 40,40"
kill -KILL "$PID"
wait "$PID" 2> /dev/null
espera_fan "$D" "100,100" 30 \
    && ok "sem conseguir 0,0, o vigia tambem deixa 100,100" \
    || falha "vigia com 0,0 recusado: fan_speed '$(fan "$D")'"

# ─── 5. a condicao de partida ───────────────────────────────────────
echo "--- a condicao de partida do E2"
recusa() {   # $1 = caso, $2 = descricao, $3 = arquivo na arvore, $4 = valor, $5 = fan esperado
    nova "partida-$1"
    poe "$D/$3" "$4"
    roda "$D" "$S" e2 "$D/e2.tsv"
    confere "E2 recusa comecar: $2" "$?" 12 "$5"
}
recusa manual  "ventoinha em manual"   sys/devices/platform/acer-wmi/nitro_sense/fan_speed "30,30" "30,30"
recusa cabo    "fora da tomada"        sys/class/power_supply/ACAD/online 0 "0,0"
recusa carga   "bateria abaixo de 60%" sys/class/power_supply/BAT1/charge_now 2000000 "0,0"
recusa pacote  "pacote quente"         sys/class/hwmon/hwmon11/temp4_input 71000 "0,0"
recusa jogo    "jogo aberto"           processos wineserver "0,0"
recusa ocupada "maquina ocupada"       proc/loadavg "5.50 1.00 0.50 1/100 1" "0,0"
# O modo maximo troca a curva do automatico (docs/plano-termico.md, secao 2):
# a linha de base e os limites sao os do modo desligado.
recusa maximo  "modo maximo ligado"    config.toml "maximum_mode = true" "0,0"

nova partida-sem-sensor
rm -f "$D/sys/class/thermal/thermal_zone2/temp"
roda "$D" "$S" e2 "$D/e2.tsv"
confere "E2 sem a zona SEN4 sai com alvo ausente" "$?" 3 "0,0"

# ─── 6. o E2 inteiro ────────────────────────────────────────────────
echo "--- o E2 inteiro"
nova e2
roda "$D" "$S" e2 "$D/e2.tsv"
confere "E2 completo termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
[ "$(grep -c '  OK$' "$D/saida.txt")" -eq 2 ] \
    && ok "os dois exercicios passaram antes do mapa" \
    || falha "os dois exercicios nao passaram: $(grep -c '  OK$' "$D/saida.txt") de 2"
faltam=0
for p in 100 80 60 50 40 30 20 15 10 5 1; do
    # coluna 3 e a fase, coluna 4 o que o roteiro escreveu, 5 o que leu
    awk -F'\t' -v p="$p" '$3 == "p=" p && $4 == p "," p && $5 == p "," p { n++ } END { exit !(n >= 4) }' \
        "$D/e2.tsv" || { falha "o traco nao tem as amostras de $p%"; faltam=1; }
done
[ "$faltam" -eq 0 ] && ok "o traco tem as onze porcentagens, escritas e lidas de volta"
# A rotacao do EC de mentira e 600 + 50 por ponto: 100% da 5600, 1% da 650.
grep -qE '^100 +5600 5600 5600 ' "$D/e2.resumo.txt" && grep -qE '^1 +650 650 650 ' "$D/e2.resumo.txt" \
    && ok "o resumo traz a rotacao de cada porcentagem" \
    || falha "o resumo nao traz as rotacoes esperadas"
[ -z "$(ls -A "$D/run")" ] \
    && ok "nenhum diretorio de trabalho sobrou" \
    || falha "sobrou em run/: $(ls -A "$D/run" | tr '\n' ' ')"

# O automatico nao tem um repouso fixo: na maquina ele volta do manual numa
# rotacao que nao e a de antes. O E2 nao pode reprovar por isso -- quem julga
# a volta e a rotacao ter SAIDO do valor manual, e nao ter chegado a um
# numero combinado.
nova e2-alto alto
roda "$D" env ENSAIO_PORCENTAGENS="100 50 10" "$S" e2 "$D/e2.tsv"
confere "automatico que volta mais alto do que estava: o E2 vai ate o fim" "$?" 0 "0,0"

# O contrario, que e o defeito que a conferencia da rotacao existe para
# pegar: fan_speed diz 0,0 e a ventoinha continua onde o manual a deixou.
nova e2-gruda gruda
roda "$D" env ENSAIO_PORCENTAGENS="100 50 10" "$S" e2 "$D/e2.tsv"
confere "fan_speed em 0,0 com a rotacao presa no manual: o exercicio reprova" "$?" 14 "0,0"

# Um EC que nao obedece: a rotacao nao sai do automatico. O exercicio nao
# teria como ver a volta, e diz isso em vez de passar por vacuo.
nova e2-surdo surdo
roda "$D" env ENSAIO_PORCENTAGENS="100 50 10" "$S" e2 "$D/e2.tsv"
confere "manual que nao muda a rotacao: o E2 para no controle positivo" "$?" 13 "0,0"
grep -q 'nao se distingue' "$D/saida.txt" \
    && ok "e diz que o manual nao se distingue do automatico" \
    || falha "faltou dizer que o manual nao se distingue do automatico"

# Um EC que obedece ate certo ponto: de 50% para cima gira igual. O
# exercicio passa, e quem reprova e o controle positivo do mapa.
nova e2-teto teto
roda "$D" env ENSAIO_PORCENTAGENS="100 50 10" "$S" e2 "$D/e2.tsv"
confere "100% girando igual a 50%: o controle positivo do mapa reprova" "$?" 13 "0,0"
grep -q 'menos de' "$D/saida.txt" \
    && ok "e diz a diferenca que faltou" \
    || falha "faltou dizer a diferenca entre 100% e 50%"

# Um vigia lento demais: o exercicio tem de reprovar, e nao passar calado.
nova e2-vigia-lento
PASSO_VIGIA=8 roda "$D" env ENSAIO_VIGIA_MAX=1 ENSAIO_PORCENTAGENS="100 50 10" "$S" e2 "$D/e2.tsv"
confere "vigia que nao devolve a tempo: o exercicio reprova" "$?" 14 "0,0"

# ─── 7. o roteiro nao sabe o indice de ninguem ──────────────────────
codigo() { grep -v '^[[:space:]]*#' "$S"; }
if codigo | grep -qE 'hwmon[0-9]|thermal_zone[0-9]|rfkill[0-9]'; then
    falha "o roteiro cita um indice de hwmon ou de zona termica"
else
    ok "nenhum indice de hwmon ou de zona termica no roteiro"
fi
if codigo | grep -q 'nvidia-smi'; then
    falha "o roteiro chama o nvidia-smi"
else
    ok "o roteiro nao chama o nvidia-smi"
fi

echo
[ "$fail" -eq 0 ] && echo "PASSOU" || echo "FALHOU"
exit "$fail"
