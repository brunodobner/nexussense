#!/bin/bash
# Roda a suite inteira e reporta o status REAL de cada teste.
#
# Sobre a captura do status: nao use
#     ./teste.sh; printf '%s exit=%s' "$(basename $t)" "$?"
# A substituicao $(basename ...) executa antes de "$?" ser expandido e
# zera o status -- o relatorio sai sempre 0, qualquer que seja o
# resultado. Guarde $? numa variavel imediatamente apos o comando.
#
# Uso:  ./tests/run-all.sh          testes que nao exigem root
#       sudo ./tests/run-all.sh     inclui os que exigem
set -u
cd "$(dirname "$0")/shell" || exit 1

VERDE='\033[0;32m'; VERMELHO='\033[0;31m'; AMARELO='\033[0;33m'; NC='\033[0m'
ok=0; falhou=0; pulou=0; erro=0

for t in test-*.sh; do
    saida=$("./$t" 2>&1)
    st=$?                     # imediatamente, antes de qualquer outro comando

    case $st in
        0) printf "  ${VERDE}PASSOU ${NC} %s\n" "$t"; ok=$((ok + 1)) ;;
        2) printf "  ${AMARELO}PULOU  ${NC} %s\n" "$t"; pulou=$((pulou + 1)) ;;
        3) printf "  ${VERMELHO}ERRO   ${NC} %s  (alvo ausente)\n" "$t"
           printf '%s\n' "$saida" | sed 's/^/           /'
           erro=$((erro + 1)) ;;
        *) printf "  ${VERMELHO}FALHOU ${NC} %s  (exit=%s)\n" "$t" "$st"
           printf '%s\n' "$saida" | grep -E 'FALHA|ERRO' | sed 's/^/           /'
           falhou=$((falhou + 1)) ;;
    esac
done

echo
printf "  %d passaram, %d falharam, %d pularam, %d com alvo ausente\n" \
       "$ok" "$falhou" "$pulou" "$erro"

[ "$falhou" -eq 0 ] && [ "$erro" -eq 0 ]
