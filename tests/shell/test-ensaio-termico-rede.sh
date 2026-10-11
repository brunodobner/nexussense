#!/bin/bash
# O modo `rede` do ensaio termico -- a prova da rede da ventoinha manual, com
# um jogo aberto -- numa arvore de mentira, antes de encostar na maquina.
#
# O que tests/shell/test-ensaio-termico.sh ja guarda (limites, sinais, o
# vigia) vale aqui sem repetir: e a mesma verifica(). O que este teste guarda
# e o que so este modo tem:
#   - nos dois controles -- automatico, e manual acima do equivalente --
#     fan_speed nao pode mudar; se voltar a 0,0 ali, a prova falha;
#   - no piso, fan_speed TEM de voltar a 0,0 por outra mao, a do agente. E o
#     contrario do resto do roteiro, onde outra mao encerra a medicao;
#   - se a rede nao age, quem devolve a ventoinha e o roteiro: no primeiro
#     limite, ou no fim do prazo do piso;
#   - fan_speed em 0,0 nao basta: a rotacao tem de sair do valor manual;
#   - depois de agir, a rede nao devolve o manual.
#
# A rede aqui e de mentira: um laco que ve um valor em fan_speed e escreve
# 0,0 por cima. A de verdade tem os testes dela em tests/python/.
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/tests/hardware/ensaio-termico.sh"

# shellcheck source=tests/shell/lib-arvore-termica.sh
source "$RAIZ/tests/shell/lib-arvore-termica.sh"

# Os tempos, encolhidos: a 0,05 s por amostra cada controle dura um segundo
# de relogio, e o piso espera a rede por ate 2 s. Cada fase dura tempo de
# relogio, e uma amostra custa o passo mais a leitura: num segundo cabem
# umas seis.
caso() {     # $1 = nome, $2 = temperamento do EC -> arvore em $D, comando em P
    nova "$1" "${2:-normal}"
    P=(env ENSAIO_REDE_AUTO=20 ENSAIO_REDE_ACIMA=20 ENSAIO_REDE_PISO=40 ENSAIO_REDE_DEPOIS=10
       "$S" rede "$D/rede.tsv")
}

abre_jogo() {    # e espera o EC de mentira esquentar: pacote e SEN4 no patamar
    local i
    poe "$D/processos" GameThread
    for ((i = 0; i < 50; i++)); do
        [ "$(cat "$D/sys/class/thermal/thermal_zone2/temp" 2> /dev/null)" = 87050 ] && return 0
        sleep 0.1
    done
    falha "o jogo de mentira nao esquentou a arvore"
}

# A rede de mentira. $1 = arvore, $2 = o fan_speed que a faz agir, $3 = quanto
# espera antes de escrever 0,0, $4 = devolve: reescreve o manual logo depois,
# que e o que a rede de verdade nunca pode fazer.
rede_falsa() {
    local f v
    f=$(FAN_DE "$1")
    while [ -d "$1" ]; do
        v=
        read -r v < "$f"
        if [ "$v" = "$2" ]; then
            sleep "$3"
            poe "$f" "0,0"
            if [ "${4:-}" = devolve ]; then sleep 0.2; poe "$f" "$2"; fi
            return 0
        fi
        sleep 0.02
    done 2> /dev/null
}
com_rede() { rede_falsa "$D" "$@" & ECS+=("$!"); }

fases() { cut -f3 "$D/rede.tsv" 2> /dev/null | sort -u | tr '\n' ' '; }
tem_fases() {    # $1 = descricao, o resto = as fases; sem isto as ausencias seriam vacuas
    local d=$1 f
    shift
    for f in "$@"; do
        cut -f3 "$D/rede.tsv" 2> /dev/null | grep -qxF "$f" || { falha "$d: o traco nao tem a fase $f ($(fases))"; return 1; }
    done
}
resumo_diz() {   # $1 = descricao, $2 = padrao
    if grep -q -- "$2" "$D/rede.resumo.txt" 2> /dev/null; then ok "$1"
    else falha "$1 -- o resumo diz: $(cat "$D/rede.resumo.txt" 2> /dev/null | tr '\n' '|')"; fi
}

# ─── 1. a condicao de partida ───────────────────────────────────────
echo "--- a condicao de partida"
caso rede-sem-jogo
roda "$D" "${P[@]}"
confere "sem jogo aberto recusa comecar" "$?" 12 "0,0"

caso rede-em-manual
abre_jogo
poe "$(FAN_DE "$D")" "40,40"
roda "$D" "${P[@]}"
confere "com a ventoinha ja em manual recusa comecar, e nao a toca" "$?" 12 "40,40"

caso rede-ja-no-limite
abre_jogo
poe "$D/sys/class/hwmon/hwmon7/temp2_input" 85000
roda "$D" "${P[@]}"
confere "com um sensor ja no limite em automatico recusa comecar" "$?" 12 "0,0"

# ─── 2. a rede age no piso, e so nele ───────────────────────────────
echo "--- a rede age no piso"
caso rede-age
abre_jogo
com_rede "20,20" 0.3
roda "$D" "${P[@]}"
confere "a rede age no piso: termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
if tem_fases "prova completa" r:auto r:acima r:piso r:depois; then
    awk -F'\t' '$3 == "r:auto" && ($4 != "0,0" || $5 != "0,0") { r = 1 } END { exit r }' "$D/rede.tsv" \
        && ok "o primeiro controle roda em automatico" \
        || falha "o primeiro controle escreveu na ventoinha"
    awk -F'\t' '$3 == "r:acima" && $4 == "60,60" && $5 == "60,60" { n++ } END { exit !(n >= 4) }' "$D/rede.tsv" \
        && ok "o segundo controle roda em manual a 60%, acima do equivalente do modo desligado" \
        || falha "o segundo controle nao rodou a 60%"
    awk -F'\t' '$3 == "r:piso" && $4 == "20,20" && $5 == "20,20" { n++ } END { exit !(n >= 2) }' "$D/rede.tsv" \
        && ok "o piso e 20%, o que o cursor novo escreve no comeco da barra" \
        || falha "o piso nao rodou a 20%"
    awk -F'\t' '$3 == "r:depois" && $5 != "0,0" { r = 1 } END { exit r }' "$D/rede.tsv" \
        && ok "depois de a rede agir, tudo em automatico" \
        || falha "ha amostra fora do automatico depois de a rede agir"
    awk -F'\t' 'NR > 1 && $28 == 0 { r = 1 } END { exit r }' "$D/rede.tsv" \
        && ok "o jogo esteve aberto em todas as amostras" \
        || falha "ha amostra sem jogo numa prova que terminou"
fi
resumo_diz "o resumo traz o tempo que a rede levou" '^no piso, manual a 20%: a rede devolveu o automatico em [0-9]* ms'
resumo_diz "o resumo diz que a rotacao saiu do manual" 'a rotacao saiu do manual: de 1600 / 1400'
resumo_diz "o veredito e de prova passada" '^veredito: PASSOU'
grep -q 'modo maximo false' "$D/rede.resumo.txt" \
    && ok "o resumo diz em que modo a prova rodou" || falha "o resumo nao diz o modo"

caso rede-age-maximo
abre_jogo
poe "$D/config.toml" "maximum_mode = true"
com_rede "20,20" 0.3
roda "$D" "${P[@]}"
confere "com o modo maximo ligado a prova roda, e termina com 0" "$?" 0 "0,0"
awk -F'\t' '$3 == "r:acima" && $4 == "90,90" && $5 == "90,90" { n++ } END { exit !(n >= 4) }' "$D/rede.tsv" \
    && ok "com o modo maximo ligado, o controle acima do equivalente e a 90%" \
    || falha "com o modo maximo ligado, o controle nao rodou a 90%"
grep -q 'modo maximo true' "$D/rede.resumo.txt" \
    && ok "o resumo diz que o modo maximo estava ligado" || falha "o resumo nao diz o modo maximo"

# ─── 3. a rede nao age: quem devolve e o roteiro ────────────────────
echo "--- a rede nao age"
caso rede-nao-age
abre_jogo
roda "$D" "${P[@]}"
confere "sem rede e sem limite: sai com 16 no fim do prazo do piso, e devolve a ventoinha" "$?" 16 "0,0"
resumo_diz "o resumo diz que a rede nao agiu" 'a rede NAO agiu'
resumo_diz "o veredito e de prova falhada" '^veredito: FALHOU'

caso rede-nao-age-estoura estoura
abre_jogo
roda "$D" "${P[@]}"
confere "sem rede e com o limite estourando: sai com 10 e devolve a ventoinha" "$?" 10 "0,0"
resumo_diz "o resumo diz qual limite veio antes da rede" 'a rede NAO agiu antes do limite: SEN4'
# O codigo de saida nao diz QUANDO: um roteiro que visse o limite e ficasse no
# piso ate o fim do prazo sairia com o mesmo 10. Foi a mutacao que escapou.
# No traco, o piso tem de acabar na amostra em que o limite aparece.
awk -F'\t' '$3 == "r:piso" && $15 >= 91000 { n++ } END { exit !(n == 1) }' "$D/rede.tsv" \
    && ok "o piso encerra na amostra em que o limite aparece" \
    || falha "o piso seguiu depois do limite: $(awk -F'\t' '$3 == "r:piso" && $15 >= 91000' "$D/rede.tsv" | wc -l) amostra(s) acima dele"
resumo_diz "o veredito e de prova falhada" '^veredito: FALHOU'

caso rede-kill9
abre_jogo
lanca "$D" "${P[@]}"
if espera_fan "$D" "20,20" 100; then
    kill -KILL "$PID"
    wait "$PID" 2> /dev/null
    espera_fan "$D" "0,0" 30 \
        && ok "kill -9 no piso, sem rede: o vigia devolve 0,0" \
        || falha "kill -9 no piso: fan_speed ficou em '$(fan "$D")'"
else
    falha "kill -9 no piso: o roteiro nao chegou a escrever 20,20"
    kill "$PID" 2> /dev/null
fi

# ─── 4. a rede age onde nao devia ───────────────────────────────────
echo "--- os controles"
caso rede-age-no-controle
abre_jogo
com_rede "60,60" 0.1
roda "$D" "${P[@]}"
confere "fan_speed volta a 0,0 no controle acima do equivalente: sai com 16" "$?" 16 "0,0"
resumo_diz "o resumo diz que foi no controle" 'no controle, com o manual a 60%, fan_speed voltou a 0,0'
tem_fases "controle falhado" r:acima \
    && { cut -f3 "$D/rede.tsv" | grep -qxF r:piso && falha "a prova seguiu para o piso depois de o controle falhar" \
         || ok "controle falhado, o piso nao roda"; }

caso rede-limite-no-automatico
abre_jogo
P=(env ENSAIO_REDE_AUTO=80 ENSAIO_REDE_ACIMA=10 ENSAIO_REDE_PISO=40 ENSAIO_REDE_DEPOIS=10 "$S" rede "$D/rede.tsv")
lanca "$D" "${P[@]}"
for ((i = 0; i < 100; i++)); do
    cut -f3 "$D/rede.tsv" 2> /dev/null | grep -qxF r:auto && break
    sleep 0.05
done
poe "$D/sys/class/hwmon/hwmon7/temp2_input" 85000
wait "$PID"
confere "limite que estoura ainda em automatico: a prova nao conta, sai com 11" "$?" 11 "0,0"

# O piso so parte com folga do limite: a rede leva de 2 a 4 s, e mais perto
# que isso quem chega primeiro e o aborto. A prova nao conta -- e o piso nem
# chega a ser escrito.
caso rede-sem-folga
abre_jogo
com_rede "20,20" 0.3
lanca "$D" "${P[@]}"
if espera_fan "$D" "60,60" 100; then
    poe "$D/sys/class/hwmon/hwmon7/temp2_input" 80000
    wait "$PID"
    confere "GPU a cinco graus do limite antes do piso: a prova nao conta, sai com 11" "$?" 11 "0,0"
    cut -f3 "$D/rede.tsv" | grep -qxF r:piso \
        && falha "o piso foi escrito com a GPU a cinco graus do limite" \
        || ok "sem folga, o piso nao e escrito"
else
    falha "sem folga: o roteiro nao chegou a escrever 60,60"
    kill "$PID" 2> /dev/null
fi

caso rede-com-folga
abre_jogo
poe "$D/sys/class/hwmon/hwmon7/temp2_input" 79000
com_rede "20,20" 0.3
roda "$D" "${P[@]}"
confere "GPU a seis graus do limite antes do piso: a prova roda" "$?" 0 "0,0"

# ─── 5. fan_speed em 0,0 nao basta ──────────────────────────────────
echo "--- a rotacao, e nao so fan_speed"
caso rede-gruda gruda
abre_jogo
com_rede "20,20" 0.3
roda "$D" "${P[@]}"
confere "fan_speed volta a 0,0 e a rotacao fica no piso: sai com 16" "$?" 16 "0,0"
resumo_diz "o resumo diz que a rotacao nao saiu do manual" 'a rotacao NAO saiu do manual'

# ─── 6. depois de agir, a rede nao devolve o manual ─────────────────
echo "--- depois de agir"
caso rede-devolve-o-manual
abre_jogo
com_rede "20,20" 0.3 devolve
roda "$D" "${P[@]}"
confere "o manual do piso reaparece depois de a rede agir: sai com 16, e o roteiro devolve" "$?" 16 "0,0"
resumo_diz "o resumo diz que o manual voltou" 'depois de a rede agir, fan_speed voltou a 20,20'

# ─── 7. a pessoa ────────────────────────────────────────────────────
echo "--- a pessoa"
caso rede-jogo-fecha
abre_jogo
lanca "$D" "${P[@]}"
if espera_fan "$D" "60,60" 100; then
    poe "$D/processos" ""
    wait "$PID"
    confere "o jogo fecha no meio do controle: encerra com 11 e devolve a ventoinha" "$?" 11 "0,0"
else
    falha "jogo que fecha: o roteiro nao chegou a escrever 60,60"
    kill "$PID" 2> /dev/null
fi

caso rede-outra-mao
abre_jogo
lanca "$D" "${P[@]}"
if espera_fan "$D" "20,20" 100; then
    poe "$(FAN_DE "$D")" "45,45"
    wait "$PID"
    confere "outro valor aparece no piso: encerra com 11 e nao escreve por cima" "$?" 11 "45,45"
    awk -F'\t' '$3 == "r:piso" && $5 == "45,45" { n++ } END { exit !(n == 1) }' "$D/rede.tsv" \
        && ok "o piso encerra na amostra em que a outra mao aparece" \
        || falha "o piso seguiu amostrando depois de ver a outra mao"
else
    falha "outra mao: o roteiro nao chegou a escrever 20,20"
    kill "$PID" 2> /dev/null
fi

echo
[ "$fail" -eq 0 ] && echo "PASSOU" || echo "FALHOU"
exit "$fail"
