#!/usr/bin/env python3
"""Os testes do ensaio termico mordem? Uma protecao estragada por vez.

tests/hardware/ensaio-termico.sh escreve na ventoinha de verdade e esquenta a
maquina de proposito. O que o impede de fazer besteira esta provado em arvore
de mentira, por tests/shell/test-ensaio-termico.sh, -e3.sh, -rede.sh e
-curva.sh e -pausa.sh. Este roteiro prova os testes: copia o ensaio, estraga UMA
protecao, roda o teste que a guarda, e cobra que ele reprove.

Nao faz parte da suite -- leva uns quinze minutos e ocupa cinco nucleos. Rode
depois de mexer no ensaio ou nos testes dele, e nunca durante um ensaio na
maquina: a carga esquenta a maquina que esta sendo medida.

    python3 tests/hardware/mutacoes-ensaio.py            todas
    python3 tests/hardware/mutacoes-ensaio.py 25,26,37   so estas

Sai com 0 se toda mutacao foi reprovada, descontadas as equivalentes; com 1
se alguma passou, ou se um trecho a estragar nao existe mais no ensaio -- a
lista envelhece junto com o codigo, e isso tambem e noticia.

Vivia no scratchpad e sumiu duas vezes, com dois reinicios, em 2026-10-10.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

REPO = pathlib.Path(__file__).resolve().parents[2]
ENSAIO = REPO / "tests/hardware/ensaio-termico.sh"
E2 = "test-ensaio-termico.sh"
E3 = "test-ensaio-termico-e3.sh"
REDE = "test-ensaio-termico-rede.sh"
CURVA = "test-ensaio-termico-curva.sh"
PAUSA = "test-ensaio-termico-pausa.sh"
APOIO = "lib-arvore-termica.sh"
GUARDA = "packaging/scripts/guarda-ventoinha.sh"

# O trecho da retomada existe igual no E3 e no E3b; o comentario o ancora no E3.
RETOMA_E3 = (
    "            # fan_speed ainda diz o manual -- verifica() acabou de conferir --\n"
    "            # e a ventoinha gira acima do que essa porcentagem girava fria.\n"
    '            if [ $(( V_RPM1 - ref1 )) -gt "$RETOMA_RPM" ] || [ $(( V_RPM2 - ref2 )) -gt "$RETOMA_RPM" ]; then\n'
    "                cnt=$(( cnt + 1 ))\n"
    "            else\n"
    "                cnt={zera}\n"
    "            fi\n"
    "            {se}\n"
)
SE_RETOMOU = 'if [ "$cnt" -ge "$RETOMA_N" ]; then'

# (nome, teste que tem de reprovar, trecho, o que entra no lugar)
MUT = [
    # ---- o que devolve a ventoinha
    ("devolve nao escreve", E2,
     '    elif [ "$atual" = "$ULTIMO" ]; then\n        if volta_ao_automatico; then',
     '    elif [ "$atual" = "$ULTIMO" ]; then\n        if true; then'),
    ("vigia nao devolve", E2,
     '    elif grep -qxF -- "$atual" "$RUN/escrito" 2>/dev/null; then\n        if volta_ao_automatico; then',
     '    elif grep -qxF -- "$atual" "$RUN/escrito" 2>/dev/null; then\n        if true; then'),
    ("devolve escreve por cima da outra mao", E2,
     '    elif [ "$atual" = "$ULTIMO" ]; then\n        if volta_ao_automatico; then',
     '    elif true; then\n        if volta_ao_automatico; then'),
    ("vigia escreve por cima da outra mao", E2,
     '    elif grep -qxF -- "$atual" "$RUN/escrito" 2>/dev/null; then',
     '    elif true; then'),
    ("sem 100,100 quando o 0,0 e recusado", E2,
     '    escreve_cru "100,100"\n    return 1', '    return 1'),
    # ---- os limites e as condicoes
    ("verifica nao ve a outra mao", E2,
     '    if [ "$V_FAN" != "$ULTIMO" ] && { [ -z "$ACEITA_FAN" ] || [ "$V_FAN" != "$ACEITA_FAN" ]; }; then\n'
     '        MOTIVO="fan_speed e',
     '    if false; then\n        MOTIVO="fan_speed e'),
    ("SEN4 fora dos limites", E2,
     '               "SEN4:$V_SEN4:$LIM_SEN4" "SEN5:$V_SEN5:$LIM_SEN5" \\',
     '               "SEN5:$V_SEN5:$LIM_SEN5" \\'),
    ("segundo NVMe fora dos limites", E2,
     '"NVMe 1:$V_NV1:$LIM_NVME" "NVMe 2:$V_NV2:$LIM_NVME"; do',
     '"NVMe 1:$V_NV1:$LIM_NVME"; do'),
    ("pacote nunca aborta", E2,
     '    if [ "$N_PAC" -ge 3 ]; then', '    if [ "$N_PAC" -ge 300 ]; then'),
    ("pacote aborta na primeira amostra", E2,
     '    if [ "$N_PAC" -ge 3 ]; then', '    if [ "$N_PAC" -ge 1 ]; then'),
    ("crit_alarm ignorado", E2,
     '    if [ "$V_ALARM" = 1 ]; then', '    if [ "$V_ALARM" = x ]; then'),
    ("cabo fora ignorado", E2,
     '    if ! livre cabo && [ "$V_ACAD" != 1 ]; then', '    if ! livre cabo && [ "$V_ACAD" = x ]; then'),
    ("carga baixa ignorada", E2,
     '    if [ "$V_PCT" -lt "$LIM_CARGA" ]; then', '    if [ "$V_PCT" -lt 0 ]; then'),
    ("jogo aberto ignorado, fora do E3b", E2,
     '    elif [ "$V_JOGO" != 0 ]; then\n        MOTIVO="jogo aberto',
     '    elif false; then\n        MOTIVO="jogo aberto'),
    ("sensor sumido ignorado", E2,
     '        if ! eh_num "$valor"; then\n            MOTIVO="$nome sumiu',
     '        if false; then\n            MOTIVO="$nome sumiu'),
    # ---- o E2: a partida, os exercicios e o controle positivo
    ("E2 comeca com a ventoinha em manual", E2,
     '    local nao=0\n    recusa() { echo "  RECUSA: $1"; nao=1; }\n    [ "$V_FAN" = "0,0" ] || recusa',
     '    local nao=0\n    recusa() { echo "  RECUSA: $1"; nao=1; }\n    true || recusa'),
    ("E2 comeca com o pacote quente", E2,
     '    acima "$V_PAC" "$PARTIDA_PACOTE" && recusa', '    false && recusa'),
    ("E2 comeca com a maquina ocupada", E2,
     "    awk -v l=\"$V_LOAD\" -v m=\"$PARTIDA_LOAD\" 'BEGIN { exit !(l + 0 < m + 0) }' \\\n        || recusa",
     "    true \\\n        || recusa"),
    ("E2 comeca com o modo maximo ligado", E2,
     '    [ "${1:-0}" != 1 ] && [ "$V_MAX" = true ] && recusa "modo maximo ligado; o ensaio e com ele desligado"\n'
     '    awk -v l=',
     '    awk -v l='),
    ("controle positivo do mapa desligado", E2,
     '                termina "$COD_CONTROLE"', '                :'),
    ("exercicio do vigia nao cobra a volta do fan_speed", E2,
     "        echo \"  FALHA: $(( VIGIA_MAX + 2 )) s depois do kill -9, fan_speed ainda e '$(le \"$FAN\")'\"\n        return 1",
     "        ms=0"),
    ("a rotacao que nao sai do manual passa", E2,
     '    echo "  a rotacao NAO saiu do manual: era $2 / $3 e esta em $r1 / $r2 rpm"\n    return 1',
     '    return 0'),
    ("manual indistinguivel do automatico nao e acusado", E2,
     '        espera_fan "0,0" 50 > /dev/null\n        return 2',
     '        espera_fan "0,0" 50 > /dev/null'),
    ("a volta cobrada contra a rotacao da partida, como antes", E2,
     '    rotacao_largou 30 "$rpm1" "$rpm2" "$QUEDA_RPM" queda || return 1\n    DRILL_RPM1',
     '    [ "$(le "$F_RPM1")" -le $(( REF1 + 500 )) ] || return 1\n    DRILL_RPM1'),
    # ---- o E3: a carga e os estagios
    ("E3: mata_carga nao mata", E3,
     'mata_carga() {     # cada carga e lider do proprio grupo (setsid): vai o grupo\n    local p\n',
     'mata_carga() {     # cada carga e lider do proprio grupo (setsid): vai o grupo\n    local p\n    return 0\n'),
    ("E3: carga sem timeout", E3,
     '        setsid timeout "$seg" bash -c "$CARGA_CMD"', '        setsid bash -c "$CARGA_CMD"'),
    ("E3: carga que morre antes do fim do estagio", E3,
     "'BEGIN { s = n * p; t = int(s); if (t < s) t++; print t + f }')", "'BEGIN { print 1 }')"),
    ("E3: controle positivo do automatico desligado", E3,
     'menos de $CONTROLE_AUTO de subida"\n            termina "$COD_CONTROLE"',
     'menos de $CONTROLE_AUTO de subida"\n            :'),
    ("E3: retomada nunca vista", E3,
     RETOMA_E3.format(zera="0", se=SE_RETOMOU), RETOMA_E3.format(zera="0", se="if false; then")),
    ("E3: retomada vista onde nao houve", E3,
     RETOMA_E3.format(zera="0", se=SE_RETOMOU),
     RETOMA_E3.format(zera="$(( cnt + 1 ))", se=SE_RETOMOU)),
    ("E3: o estagio seguinte roda depois de um aborto", E3,
     '    if [ "$rc" -eq "$COD_LIMITE" ]; then ABORTOU=1; return "$COD_LIMITE"; fi',
     '    if [ "$rc" -eq "$COD_LIMITE" ]; then ABORTOU=1; return 0; fi'),
    ("E3: veredito ignora o aborto", E3,
     '    if [ "$ABORTOU" = 1 ]; then\n        v="R3', '    if false; then\n        v="R3'),
    ("E3: partida sem conferir se a maquina esta fria", E3,
     '    if ! frio_o_bastante "$med"; then', '    if false; then'),
    ("E3: estagio mais baixo fora do piso", E3,
     'E3_P2=${ENSAIO_E3_P2:-1} ', 'E3_P2=${ENSAIO_E3_P2:-20} '),
    ("E3: a descida roda com a ventoinha em manual", E3,
     '        if ! escreve "0,0"; then MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"; fi\n    fi\n\n    thr=NA',
     '    fi\n\n    thr=NA'),
    ("E3: condicao no meio da carga nao encerra", E3,
     '    [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"\n\n    if [ "$p" = 0 ]',
     '    if [ "$p" = 0 ]'),
    # ---- o E3b: com um jogo
    ("E3b: comeca sem jogo aberto", E3,
     '    [ "$V_JOGO" != 0 ] || recusa "nenhum jogo aberto', '    true || recusa "nenhum jogo aberto'),
    ("E3b: o jogo fechar nao encerra", E3,
     '        if [ "$V_JOGO" = 0 ]; then\n            MOTIVO="o jogo fechou',
     '        if false; then\n            MOTIVO="o jogo fechou'),
    ("E3b: comeca com o modo maximo ligado", E3,
     '    [ "$V_MAX" = true ] && recusa "modo maximo ligado; o ensaio e com ele desligado"\n    [ "$nao" = 0 ]',
     '    [ "$nao" = 0 ]'),
    ("E3b: comeca com um limite ja estourado em automatico", E3,
     '        echo "  RECUSA: ainda em automatico, $MOTIVO"; exit "$COD_RECUSA"', '        :'),
    ("E3b: limite estourado nao aborta o manual", E3,
     '        if [ "$rc" -ne 0 ]; then fim="aborto: $MOTIVO, aos $(( EPOCHSECONDS - t0 )) s"; break; fi',
     '        if [ "$rc" -eq "$COD_CONDICAO" ]; then fim="aborto: $MOTIVO, aos $(( EPOCHSECONDS - t0 )) s"; break; fi'),
    ("E3b: retomada desde a escrita nao e vista", E3,
     '                if [ $(( auto1 - ref1 )) -lt "$RETOMA_RPM" ] && [ $(( auto2 - ref2 )) -lt "$RETOMA_RPM" ]; then',
     '                if false; then'),
    ("E3b: a descida roda com a ventoinha em manual", E3,
     '$mr2 rpm"\n    fi\n    if ! escreve "0,0"; then MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"; fi\n\n    thr=NA',
     '$mr2 rpm"\n    fi\n\n    thr=NA'),
    # ---- a prova da rede: a outra mao e o que se espera, e so no piso
    ("rede: comeca sem jogo aberto", REDE,
     '    [ "$V_JOGO" = 0 ] && recusa "a prova pede um jogo aberto',
     '    false && recusa "a prova pede um jogo aberto'),
    ("rede: comeca com um limite ja estourado em automatico", REDE,
     '        echo "  RECUSA: antes de escrever qualquer coisa, $MOTIVO"; exit "$COD_RECUSA"', '        :'),
    ("rede: o jogo pode estar fechado", REDE,
     'p1="" p2="" g0 mg=0 saiu\n    COM_JOGO=1; REPOUSO=0', 'p1="" p2="" g0 mg=0 saiu\n    COM_JOGO=0; REPOUSO=0'),
    ("rede: com o modo maximo, o controle fica abaixo do equivalente", REDE,
     '    [ "$MAX0" = true ] && pa=$REDE_P_ACIMA_MAX\n', ''),
    ("rede: limite em automatico conta como aborto", REDE,
     'e a prova nao conta"\n            termina "$COD_CONDICAO"',
     'e a prova nao conta"\n            termina "$COD_LIMITE"'),
    ("rede: fan_speed de volta a 0,0 no controle nao e acusado", REDE,
     '        if [ "$V_FAN" = "0,0" ]; then\n            ULTIMO="0,0"\n            falha_rede "no controle',
     '        if false; then\n            ULTIMO="0,0"\n            falha_rede "no controle'),
    ("rede: o piso fora do piso", REDE,
     'REDE_P_PISO=${ENSAIO_REDE_P_PISO:-20}', 'REDE_P_PISO=${ENSAIO_REDE_P_PISO:-60}'),
    ("rede: o piso e escrito sem folga do limite", REDE,
     '    if acima "$g0" $(( LIM_EC_GPU - REDE_FOLGA + 1 )); then', '    if false; then'),
    ("rede: a folga do piso exige um grau a mais", REDE,
     '    if acima "$g0" $(( LIM_EC_GPU - REDE_FOLGA + 1 )); then',
     '    if acima "$g0" $(( LIM_EC_GPU - REDE_FOLGA )); then'),
    ("rede: no piso a rede agir conta como outra mao", REDE,
     '        if [ "$V_FAN" = "0,0" ]; then\n            [ -n "$ms" ] || ms=',
     '        if false; then\n            [ -n "$ms" ] || ms='),
    ("rede: limite no piso nao encerra", REDE,
     '        [ "$rc" -ne 0 ] && break\n        p1=$V_RPM1; p2=$V_RPM2', '        p1=$V_RPM1; p2=$V_RPM2'),
    ("rede: sem a rede agir, a prova segue como se tivesse agido", REDE,
     '    if [ "$agiu" != 1 ]; then\n        # Outro valor em fan_speed',
     '    if false; then\n        # Outro valor em fan_speed'),
    ("rede: a rotacao que nao sai do piso passa", REDE,
     '    [ "$rc" -eq 0 ] || falha_rede "fan_speed voltou a 0,0, mas a rotacao nao saiu do manual"\n', ''),
    ("rede: o manual de volta depois de a rede agir nao e acusado", REDE,
     '        if [ "$V_FAN" = "$pp,$pp" ]; then\n            # E o manual desta prova',
     '        if false; then\n            # E o manual desta prova'),
    ("rede: o manual de volta e acusado, e fica no piso", REDE,
     '    [ -n "$REDE_VALOR" ] && [ "$(le "$FAN")" = "$REDE_VALOR" ] && ULTIMO=$REDE_VALOR\n', ''),
    # ---- o perfil de energia e os ensaios da curva
    ("verifica nao ve o perfil de energia mudar", E2,
     '    if ! livre ppd && [ "$V_PPD" != "$PPD0" ]; then', '    if false; then'),
    ("curva: o perfil de energia nao volta no fim", CURVA,
     '    [ -n "$PPD_INICIAL" ] && [ "$PPD_INICIAL" != NA ] || return 0\n', '    return 0\n'),
    ("curva: o vigia nao devolve o perfil de energia", CURVA,
     '    if [ -s "$RUN/ppd_inicial" ]; then', '    if false; then'),
    ("curva: o controle do estagio 4 nao para o ensaio", CURVA,
     '        echo "controle: FALHOU -- $MOTIVO" >> "$RESUMO"\n        termina "$COD_CONTROLE"',
     '        :'),
    ("curva: o gesto que nao vem passa", CURVA,
     '    [ "${5:-0}" = 1 ] && return 1\n    MOTIVO="o gesto $N_GESTO nao veio no prazo: $1"',
     '    return 1\n    MOTIVO="o gesto $N_GESTO nao veio no prazo: $1"'),
    ("curva: o degrau de controle tambem troca", CURVA,
     'then b=${reais[1]}; troca=0;', 'then b=${reais[1]}; troca=1;'),
    ("curva: o trap devolve o manual que tinha de atravessar o reinicio", CURVA,
     '    DEVOLVIDO=1; : > "$RUN/devolvido"\n    CURVA_INICIAL=;', '    : > "$RUN/devolvido"\n    CURVA_INICIAL=;'),
    ("curva: o agente fica sob SIGSTOP", CURVA,
     '    kill -CONT "$AGENTE_PARADO" 2>/dev/null\n', ''),
    ("curva: o guarda passa sem a rotacao sair do manual", CURVA,
     '        if rotacao_largou 30 "$C5_REF1" "$C5_REF2" "$QUEDA_RPM" queda; then\n'
     '            echo "guarda, kill -9: PASSOU',
     '        if true; then\n            echo "guarda, kill -9: PASSOU'),
    # ---- a curva do agente, pausada enquanto o ensaio roda
    ("pausa: o E2 nao pausa a curva", PAUSA,
     '    echo "E2 -- mapa de porcentagem para rotacao, em repouso"\n    echo "saida: $SAIDA"\n    pausa_curva\n',
     '    echo "E2 -- mapa de porcentagem para rotacao, em repouso"\n    echo "saida: $SAIDA"\n'),
    ("pausa: antes da partida, nada devolve a curva", PAUSA,
     '    trap devolve_curva EXIT\n', ''),
    ("pausa: o trap nao devolve a curva", PAUSA,
     '    devolve_ppd\n    devolve_curva\n', '    devolve_ppd\n'),
    ("pausa: o vigia nao devolve a curva", PAUSA,
     '    if [ -s "$RUN/curva_inicial" ]; then', '    if false; then'),
    ("pausa: a curva volta sempre como false", PAUSA,
     '    if poe_curva "$inicial"; then', '    if poe_curva false; then'),
    ("pausa: o reinicio do ec5 devolve a curva antes da hora", CURVA,
     '    CURVA_INICIAL=; rm -f "$RUN/curva_inicial"\n', ''),
    ("pausa: o ec5-volta nao devolve a curva", CURVA,
     '    CURVA_INICIAL=$(chave curva)\n    devolve_curva\n', ''),
]

# Mutacoes que nao mudam o que o roteiro faz, e por isso nao tem como
# reprovar. Ficam na lista para alguem que as releia nao as "descobrir".
EQUIVALENTES = {
    "E3b: comeca sem jogo aberto":
        "sem a recusa, a conferencia seguinte (verifica) recusa igual, com o mesmo codigo",
    "rede: comeca sem jogo aberto":
        "sem a recusa, a conferencia seguinte (verifica) recusa igual, com o mesmo codigo",
}


def uma(i, nome, teste, de, para, orig, base):
    n = orig.count(de)
    if n != 1:
        return f"{i:2} ERRO     {nome}: o trecho aparece {n} vezes no ensaio", 1
    d = base / f"m{i}"
    (d / "tests/hardware").mkdir(parents=True)
    (d / "tests/shell").mkdir(parents=True)
    alvo = d / "tests/hardware/ensaio-termico.sh"
    alvo.write_text(orig.replace(de, para))
    alvo.chmod(0o755)
    for f in (APOIO, teste):
        shutil.copy(REPO / "tests/shell" / f, d / "tests/shell" / f)
    # O E-C5 roda o guarda de verdade como ExecStopPost do systemd de mentira.
    (d / "packaging/scripts").mkdir(parents=True)
    shutil.copy2(REPO / GUARDA, d / GUARDA)
    r = subprocess.run([str(d / "tests/shell" / teste)], capture_output=True, text=True)
    falhas = [l.strip()[6:].split(":")[0][:55] for l in r.stdout.splitlines() if l.startswith("  FALHA")]
    shutil.rmtree(d, ignore_errors=True)
    if r.returncode == 1 and falhas:
        return f"{i:2} reprovou {nome}: {len(falhas)} falha(s) -- " + " | ".join(falhas[:2]), 0
    if nome in EQUIVALENTES:
        return f"{i:2} passou   {nome}: equivalente -- {EQUIVALENTES[nome]}", 0
    return f"{i:2} PASSOU   {nome}: rc={r.returncode} -- o teste nao viu", 1


def main():
    so = {int(v) for v in sys.argv[1].split(",")} if len(sys.argv) > 1 else None
    orig = ENSAIO.read_text()
    base = pathlib.Path(tempfile.mkdtemp(prefix="mutacoes-ensaio."))
    ruins = 0
    try:
        with ThreadPoolExecutor(max_workers=5) as pool:
            futuros = [
                pool.submit(uma, i, *m, orig, base)
                for i, m in enumerate(MUT, 1)
                if so is None or i in so
            ]
            for f in futuros:
                linha, ruim = f.result()
                print(linha, flush=True)
                ruins += ruim
    finally:
        shutil.rmtree(base, ignore_errors=True)
    print(f"mutacoes que o teste nao viu, ou que nao acharam o trecho: {ruins} de {len(futuros)}")
    return 1 if ruins else 0


if __name__ == "__main__":
    sys.exit(main())
