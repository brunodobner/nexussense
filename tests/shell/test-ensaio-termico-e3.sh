#!/bin/bash
# O E3 do ensaio termico -- manual baixo com carga de CPU -- numa arvore de
# mentira, antes de esquentar a maquina de verdade.
#
# O que tests/shell/test-ensaio-termico.sh ja guarda (limites, sinais, o
# vigia, a outra mao) vale para o E3 sem repetir: e a mesma verifica(). O que
# este teste guarda e o que so o E3 tem:
#   - a fonte de calor morre com o roteiro, de qualquer jeito que ele morra,
#     e morre sozinha no prazo se roteiro e vigia sumirem juntos;
#   - o estagio em automatico e o controle positivo: se a rotacao nao sobe
#     com a carga, nenhum estagio manual roda;
#   - "o EC tomou a ventoinha de volta" e "o EC obedeceu" saem certos, e o
#     veredito segue a regra da secao 10 de docs/plano-termico.md;
#   - um estagio que aborta num limite encerra o ensaio: o seguinte nao roda.
#
# A carga aqui nao queima CPU: e bin/carga-falsa, que levanta uma bandeira, e
# o EC de mentira esquenta enquanto ela estiver de pe.
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/tests/hardware/ensaio-termico.sh"

# shellcheck source=tests/shell/lib-arvore-termica.sh
source "$RAIZ/tests/shell/lib-arvore-termica.sh"
# Sem o ps de verdade, "nenhum processo de carga" seria lido de um comando
# que nao existe -- zero por vacuo (armadilha 30).
for c in timeout ps; do
    command -v "$c" > /dev/null 2>&1 || { echo "ERRO alvo ausente: $c"; exit 3; }
done

# Os tempos do E3, encolhidos: a 0,05 s por amostra os tres estagios duram
# 1,5 s, 2 s e 3 s de relogio.
#
# FOLGA_CARGA e quanto a carga vive alem do estagio antes de morrer sozinha.
# Aqui ela e LONGA de proposito, 30 s: com 1 s a carga morria pelo relogio
# dentro da janela em que o teste espera ve-la morta, e um roteiro que nao
# matasse carga nenhuma passava -- foi a mutacao que escapou. So o caso
# "sem roteiro e sem vigia" pede a folga curta, porque e o relogio que ele mede.
caso() {     # $1 = nome, $2 = temperamento do EC, $3 = folga -> arvore em $D, comando em E3
    nova "$1" "${2:-normal}"
    E3=(env ENSAIO_E3_PRE=4 ENSAIO_E3_CARGA0=30 ENSAIO_E3_CARGA1=40 ENSAIO_E3_CARGA2=60
        ENSAIO_E3_DESCIDA=80 ENSAIO_E3_EXTRA=3 ENSAIO_CARGA_N=2 ENSAIO_FOLGA_CARGA="${3:-30}"
        ENSAIO_CARGA_CMD="exec $D/bin/carga-falsa" "$S" e3 "$D/e3.tsv")
}

espera_bandeira() {  # $1 = de_pe | no_chao, $2 = decimos de segundo
    local i
    for ((i = 0; i < $2; i++)); do
        if [ "$1" = de_pe ]; then [ -e "$D/carga_ligada" ] && return 0
        else [ -e "$D/carga_ligada" ] || return 0; fi
        sleep 0.1
    done
    return 1
}

carga_viva() {       # quantos processos da carga de mentira deste caso existem
    # O awk tem o caminho procurado na propria linha de comando: sai da conta
    # pelo nome, senao acharia a si mesmo (armadilha 10).
    ps -eo comm,args --no-headers \
        | awk -v d="$D/bin/carga-falsa" '$1 != "awk" && index($0, d) { n++ } END { print n + 0 }'
}

sem_carga() {        # $1 = descricao
    if espera_bandeira no_chao 30 && [ "$(carga_viva)" = 0 ]; then
        ok "$1: a fonte de calor morreu"
    else
        falha "$1: sobrou carga ($(carga_viva) processo(s), bandeira $([ -e "$D/carga_ligada" ] && echo de pe || echo no chao))"
    fi
}

fases() { cut -f3 "$D/e3.tsv" | sort -u | tr '\n' ' '; }

# ─── 1. o EC obedece ao manual, e nada estoura: R2 ──────────────────
echo "--- o EC obedece e nada estoura"
caso e3-obedece
roda "$D" "${E3[@]}"
confere "E3 completo termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
sem_carga "no fim do E3"
falta=0
for f in e0:frio e0:carga e0:descida e1:frio e1:carga e1:descida e2:frio e2:carga e2:descida; do
    cut -f3 "$D/e3.tsv" | grep -qxF "$f" || { falha "o traco nao tem a fase $f (tem: $(fases))"; falta=1; }
done
[ "$falta" -eq 0 ] && ok "o traco tem os tres estagios: frio, carga e descida"
# coluna 4 e o que o roteiro escreveu, 5 o que leu de volta
awk -F'\t' '$3 == "e0:carga" && $4 != "0,0" { r = 1 } END { exit r }' "$D/e3.tsv" \
    && ok "o estagio 0 roda em automatico" || falha "o estagio 0 escreveu na ventoinha"
awk -F'\t' '$3 == "e1:carga" && $4 == "30,30" && $5 == "30,30" { n++ } END { exit !(n >= 6) }' "$D/e3.tsv" \
    && ok "o estagio 1 roda a 30%" || falha "o estagio 1 nao rodou a 30%"
awk -F'\t' '$3 == "e2:carga" && $4 == "1,1" && $5 == "1,1" { n++ } END { exit !(n >= 8) }' "$D/e3.tsv" \
    && ok "o estagio 2 roda a 1%" || falha "o estagio 2 nao rodou a 1%"
# A linha do veredito tambem diz "obedeceu": conta so as linhas de estagio.
# Acabado o estagio, a ventoinha volta ao automatico antes da descida: e a
# descida em automatico que diz quanto a maquina leva para esfriar.
awk -F'\t' '$3 ~ /:descida$/ { n++; if ($4 != "0,0" || $5 != "0,0") r = 1 } END { exit (r || !n) }' "$D/e3.tsv" \
    && ok "toda descida roda em automatico" \
    || falha "ha descida com a ventoinha fora do automatico"
[ "$(grep -c '^    o EC obedeceu ao manual' "$D/e3.resumo.txt")" -eq 2 ] \
    && ok "o resumo diz que o EC obedeceu nos dois estagios manuais" \
    || { falha "o resumo nao diz 'obedeceu' duas vezes:"; sed 's/^/        /' "$D/e3.resumo.txt"; }
# A carga tem de ter durado o estagio inteiro: o pacote ainda quente na
# ultima amostra. Ela morre pelo relogio; um estagio que contasse amostras
# em vez de segundos a veria morrer antes do fim.
awk -F'\t' '$3 == "e2:carga" { p = $8 } END { exit !(p >= 88000) }' "$D/e3.tsv" \
    && ok "a carga dura o estagio inteiro" \
    || falha "no fim do estagio 2 o pacote ja tinha esfriado: a carga morreu antes"
grep -q '^veredito: R2' "$D/e3.resumo.txt" \
    && ok "veredito R2" || falha "veredito errado: $(grep '^veredito' "$D/e3.resumo.txt")"
[ -z "$(ls -A "$D/run")" ] \
    && ok "nenhum diretorio de trabalho sobrou" \
    || falha "sobrou em run/: $(ls -A "$D/run" | tr '\n' ' ')"

# ─── 2. o EC toma a ventoinha de volta: R1 ──────────────────────────
echo "--- o EC toma a ventoinha de volta"
caso e3-retoma retoma
roda "$D" "${E3[@]}"
confere "com o EC passando por cima do manual, o E3 termina com 0" "$?" 0 "0,0"
[ "$(grep -c '^    o EC tomou a ventoinha de volta' "$D/e3.resumo.txt")" -eq 2 ] \
    && ok "o resumo diz que o EC tomou a ventoinha, nos dois estagios manuais" \
    || { falha "o resumo nao acusa a retomada duas vezes:"; sed 's/^/        /' "$D/e3.resumo.txt"; }
grep -q '^veredito: R1' "$D/e3.resumo.txt" \
    && ok "veredito R1" || falha "veredito errado: $(grep '^veredito' "$D/e3.resumo.txt")"
# Vista a retomada, o estagio segue mais um pouco e termina: nao vai ate o fim.
[ "$(grep -c 'fim: retomada' "$D/e3.resumo.txt")" -eq 2 ] \
    && ok "vista a retomada, o estagio termina antes do prazo" \
    || falha "o resumo nao traz 'fim: retomada' nos dois estagios manuais"
sem_carga "depois da retomada"

# ─── 3. um limite estoura: R3, e o estagio seguinte nao roda ────────
echo "--- um limite estoura no estagio 1"
caso e3-estoura estoura
roda "$D" "${E3[@]}"
confere "limite estourado: o E3 sai com 10 e devolve a ventoinha" "$?" 10 "0,0"
sem_carga "depois do aborto"
grep -q '^veredito: R3' "$D/e3.resumo.txt" \
    && ok "veredito R3" || falha "veredito errado: $(grep '^veredito' "$D/e3.resumo.txt")"
grep -q 'aborto: SEN4' "$D/e3.resumo.txt" \
    && ok "o resumo diz qual limite estourou" || falha "o resumo nao diz o limite"
# Ausencia so vale com o traco no lugar: sem ele, "nao achei e2" seria vacuo.
if ! cut -f3 "$D/e3.tsv" 2> /dev/null | grep -qxF 'e1:carga'; then
    falha "o traco nao tem o estagio 1: nao ha como afirmar que o 2 nao rodou"
elif cut -f3 "$D/e3.tsv" | grep -q '^e2:'; then
    falha "o estagio 2 rodou depois de o 1 abortar"
else
    ok "o estagio 2 nao roda depois de o 1 abortar"
fi
cut -f3 "$D/e3.tsv" | grep -qxF 'e1:descida' \
    && ok "a descida do estagio abortado fica gravada" \
    || falha "faltou a descida depois do aborto"

# ─── 4. o controle positivo: automatico que nao sobe com a carga ────
echo "--- o controle positivo"
caso e3-auto-parado auto_parado
roda "$D" "${E3[@]}"
confere "automatico que nao sobe com a carga: o E3 para no controle positivo" "$?" 13 "0,0"
if ! cut -f3 "$D/e3.tsv" 2> /dev/null | grep -qxF 'e0:carga'; then
    falha "o traco nao tem o estagio 0: nao ha como afirmar que nada foi escrito"
elif awk -F'\t' 'NR > 1 && $4 != "0,0" { r = 1 } END { exit r }' "$D/e3.tsv"; then
    ok "sem controle positivo, nenhum estagio manual roda"
else
    falha "o roteiro escreveu na ventoinha sem o controle positivo"
fi
sem_carga "depois do controle reprovado"

# ─── 5. a fonte de calor morre com o roteiro ────────────────────────
echo "--- a carga morre com o roteiro"
no_estagio_1() {     # $1 = nome do caso, $2 = folga. Lanca o E3 e espera o estagio 1 com a carga no ar
    caso "$1" normal "${2:-30}"
    lanca "$D" "${E3[@]}"
    if ! espera_fan "$D" "30,30" 100 || ! espera_bandeira de_pe 50; then
        falha "$1: o E3 nao chegou ao estagio 1 com carga"
        kill "$PID" 2> /dev/null
        return 1
    fi
}

if no_estagio_1 e3-kill9; then
    kill -KILL "$PID"
    wait "$PID" 2> /dev/null
    espera_fan "$D" "0,0" 30 \
        && ok "kill -9 no meio da carga: o vigia devolve 0,0" \
        || falha "kill -9 no meio da carga: fan_speed ficou em '$(fan "$D")'"
    sem_carga "kill -9 no meio da carga"
fi

if no_estagio_1 e3-term; then
    kill -TERM "$PID"
    wait "$PID"
    confere "SIGTERM no meio da carga devolve a ventoinha" "$?" 143 "0,0"
    sem_carga "SIGTERM no meio da carga"
fi

if no_estagio_1 e3-outra-mao; then
    poe "$(FAN_DE "$D")" "44,44"
    wait "$PID"
    confere "outra mao na ventoinha no meio da carga: para e nao escreve por cima" "$?" 11 "44,44"
    sem_carga "outra mao no meio da carga"
fi

# Roteiro e vigia mortos juntos: ninguem devolve a ventoinha, mas o calor
# para sozinho no prazo -- e a terceira camada da secao 8 do plano.
if no_estagio_1 e3-sem-ninguem 1; then
    vigia=$(ps -eo pid,args --no-headers | awk -v p="$PID" '$0 ~ ("--vigia " p " ") { print $1 }')
    if [ -z "$vigia" ]; then
        falha "nao achei o vigia do roteiro $PID"
    else
        kill -KILL "$vigia" "$PID"
        wait "$PID" 2> /dev/null
        if espera_bandeira no_chao 80 && [ "$(carga_viva)" = 0 ]; then
            ok "sem roteiro e sem vigia, a carga morre sozinha no prazo"
        else
            falha "sem roteiro e sem vigia, a carga continuou ($(carga_viva) processo(s))"
        fi
    fi
fi

# ─── 6. a condicao de partida do E3 ─────────────────────────────────
echo "--- a condicao de partida do E3"
recusa() {   # $1 = caso, $2 = descricao, $3 = arquivo na arvore, $4 = valor, $5 = fan esperado
    caso "e3-partida-$1"
    poe "$D/$3" "$4"
    roda "$D" "${E3[@]}"
    confere "E3 recusa comecar: $2" "$?" 12 "$5"
    [ "$(carga_viva)" = 0 ] || falha "E3 recusou e mesmo assim ligou a carga"
}
recusa manual "ventoinha em manual"      sys/devices/platform/acer-wmi/nitro_sense/fan_speed "30,30" "30,30"
recusa maximo "modo maximo ligado"       config.toml "maximum_mode = true" "0,0"
recusa pacote "pacote a 60 C ou mais"    sys/class/hwmon/hwmon11/temp4_input 61000 "0,0"
# O limite de SEN4 e 91 C; a partida pede 15 C de folga.
recusa sen4   "SEN4 a menos de 15 C do limite" sys/class/thermal/thermal_zone2/temp 77050 "0,0"

# ─── 7. E3b: o mesmo, com um jogo no lugar da carga ─────────────────
# Aqui a condicao se inverte: o jogo TEM de estar aberto, do comeco ao fim.
# O roteiro nao liga carga nenhuma: grava um trecho em automatico, escreve o
# manual no piso, e devolve. O jogo de mentira e uma linha no arquivo que o
# ps de mentira imprime.
echo "--- E3b: com um jogo"
casob() {    # $1 = nome, $2 = temperamento -> arvore em $D, comando em B
    nova "$1" "${2:-normal}"
    B=(env ENSAIO_E3B_PRE=20 ENSAIO_E3B_CARGA=60 ENSAIO_E3B_DESCIDA=20 "$S" e3b "$D/e3b.tsv")
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
tem_fases_b() {  # as tres fases no traco; sem isto as ausencias seriam vacuas
    local f
    for f in b:auto b:manual b:descida; do
        cut -f3 "$D/e3b.tsv" 2> /dev/null | grep -qxF "$f" || { falha "$1: o traco nao tem a fase $f"; return 1; }
    done
}

casob e3b-sem-jogo
roda "$D" "${B[@]}"
confere "E3b sem jogo aberto recusa comecar" "$?" 12 "0,0"

casob e3b-maximo
abre_jogo
poe "$D/config.toml" "maximum_mode = true"
roda "$D" "${B[@]}"
confere "E3b com o modo maximo ligado recusa comecar" "$?" 12 "0,0"

# Um sensor ja no limite em automatico: escrever o manual so mediria o aborto.
casob e3b-ja-no-limite
abre_jogo
poe "$D/sys/class/hwmon/hwmon7/temp2_input" 85000
roda "$D" "${B[@]}"
confere "E3b com um sensor ja no limite em automatico recusa comecar" "$?" 12 "0,0"

casob e3b-obedece
abre_jogo
roda "$D" "${B[@]}"
confere "E3b completo termina com 0 e a ventoinha em automatico" "$?" 0 "0,0"
if tem_fases_b "E3b completo"; then
    awk -F'\t' '$3 == "b:auto" && $4 != "0,0" { r = 1 } END { exit r }' "$D/e3b.tsv" \
        && ok "o trecho de referencia roda em automatico" \
        || falha "o trecho de referencia escreveu na ventoinha"
    awk -F'\t' '$3 == "b:manual" && $4 == "1,1" && $5 == "1,1" { n++ } END { exit !(n >= 10) }' "$D/e3b.tsv" \
        && ok "o trecho manual roda no piso, 1%" \
        || falha "o trecho manual nao rodou a 1%"
    awk -F'\t' '$3 == "b:descida" && ($4 != "0,0" || $5 != "0,0") { r = 1 } END { exit r }' "$D/e3b.tsv" \
        && ok "a descida roda em automatico" \
        || falha "a descida rodou com a ventoinha fora do automatico"
    awk -F'\t' 'NR > 1 && $3 != "partida" && $28 == 0 { r = 1 } END { exit r }' "$D/e3b.tsv" \
        && ok "o jogo esteve aberto em todas as amostras" \
        || falha "ha amostra sem jogo num ensaio que terminou"
fi
grep -q '^    o EC obedeceu ao manual' "$D/e3b.resumo.txt" \
    && ok "o resumo diz que o EC obedeceu" || falha "o resumo nao diz 'obedeceu'"
grep -q '^veredito: R2' "$D/e3b.resumo.txt" \
    && ok "veredito R2" || falha "veredito errado: $(grep '^veredito' "$D/e3b.resumo.txt")"
[ "$(carga_viva)" = 0 ] && ok "o E3b nao liga carga nenhuma" || falha "o E3b ligou carga"

casob e3b-estoura estoura
abre_jogo
roda "$D" "${B[@]}"
confere "com jogo e o limite estourando, o E3b sai com 10 e devolve a ventoinha" "$?" 10 "0,0"
grep -q 'aborto: SEN4' "$D/e3b.resumo.txt" \
    && ok "o resumo diz qual limite estourou, e quando" || falha "o resumo nao diz o limite"
# O aborto pode vir antes de a referencia do manual estar fixada -- na maquina
# veio aos 7 s. Mesmo assim o resumo diz onde a rotacao estava: saiu "? / ?".
if grep -q '? / ?' "$D/e3b.resumo.txt"; then
    falha "o resumo traz '? / ?' no lugar da rotacao"
elif grep -q '^    o EC obedeceu ao manual: a rotacao caiu de 4700 / 4181 rpm' "$D/e3b.resumo.txt"; then
    ok "abortado cedo, o resumo ainda diz de onde e para onde a rotacao caiu"
else
    falha "abortado cedo, o resumo nao diz a queda da rotacao: $(grep 'o EC' "$D/e3b.resumo.txt")"
fi
grep -q '^veredito: R3' "$D/e3b.resumo.txt" \
    && ok "veredito R3" || falha "veredito errado: $(grep '^veredito' "$D/e3b.resumo.txt")"
tem_fases_b "E3b abortado" && ok "a descida depois do aborto fica gravada"

casob e3b-retoma retoma
abre_jogo
roda "$D" "${B[@]}"
confere "com jogo e o EC passando por cima do manual, o E3b termina com 0" "$?" 0 "0,0"
grep -q '^    o EC tomou a ventoinha de volta' "$D/e3b.resumo.txt" \
    && ok "o resumo acusa a retomada" || falha "o resumo nao acusa a retomada"
grep -q '^veredito: R1' "$D/e3b.resumo.txt" \
    && ok "veredito R1" || falha "veredito errado: $(grep '^veredito' "$D/e3b.resumo.txt")"

# O jogo fecha no meio: a medicao nao conta, e a ventoinha volta.
casob e3b-jogo-fecha
abre_jogo
lanca "$D" "${B[@]}"
if espera_fan "$D" "1,1" 100; then
    poe "$D/processos" ""
    wait "$PID"
    confere "o jogo fecha no meio do manual: encerra com 11 e devolve a ventoinha" "$?" 11 "0,0"
else
    falha "jogo que fecha: o E3b nao chegou a escrever 1,1"
    kill "$PID" 2> /dev/null
fi

casob e3b-kill9
abre_jogo
lanca "$D" "${B[@]}"
if espera_fan "$D" "1,1" 100; then
    kill -KILL "$PID"
    wait "$PID" 2> /dev/null
    espera_fan "$D" "0,0" 30 \
        && ok "kill -9 no meio do manual, com jogo: o vigia devolve 0,0" \
        || falha "kill -9 com jogo: fan_speed ficou em '$(fan "$D")'"
else
    falha "kill -9 com jogo: o E3b nao chegou a escrever 1,1"
    kill "$PID" 2> /dev/null
fi

echo
[ "$fail" -eq 0 ] && echo "PASSOU" || echo "FALHOU"
exit "$fail"
