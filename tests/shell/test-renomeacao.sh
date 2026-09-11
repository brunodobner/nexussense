#!/bin/bash
# A renomeacao nao pode deixar rastro do nome antigo onde ele faca mal,
# nem apagar o credito aos autores originais.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ/setup.sh"
C="$RAIZ/driver/src/nexus_sense.c"
M="$RAIZ/driver/Makefile"
D="$RAIZ/driver/dkms.conf"
U="$RAIZ/packaging/systemd/nexus_sense.service"
falhas=0

for alvo in "$S" "$C" "$M" "$D" "$U"; do
    [ -e "$alvo" ] || { echo "ERRO: alvo ausente: $alvo"; exit 3; }
done

ok()    { echo "  OK   $1"; }
falha() { echo "  FALHA $1"; falhas=$((falhas + 1)); }

# --- o nome novo esta onde precisa estar
grep -q '^obj-m := src/nexus_sense.o' "$M" && ok "Makefile compila nexus_sense" \
    || falha "Makefile ainda aponta para o fonte antigo"
grep -q '^PACKAGE_NAME="nexus_sense"' "$D" && ok "dkms.conf registra nexus_sense" \
    || falha "dkms.conf com o nome antigo"
grep -q 'modprobe -r nexus_sense' "$U" && ok "a unit descarrega nexus_sense" \
    || falha "a unit descarrega o modulo errado"

# --- autoria: os dois lados
#
# O driver e GPL-2.0-or-later derivado do acer_wmi do kernel. Os avisos
# de copyright da linhagem TEM de continuar no arquivo -- distribuir sem
# eles violaria a licenca, e este repositorio e publico. Ao mesmo tempo,
# o autor atual do projeto tem de aparecer: um arquivo que so credita a
# origem esconde de quem e o trabalho de hoje.
#
# Por isso as duas asserções andam juntas. Remover qualquer uma das duas
# quebra alguma coisa: a de cima, a licenca; a de baixo, a autoria.
for credito in 'Linuwu-Sense' 'Carlos Corbacho' 'E.M. Smith' 'Div Sharp'; do
    grep -q "$credito" "$C" \
        && ok "credito da linhagem preservado: $credito" \
        || falha "o cabecalho perdeu o credito a $credito (GPL exige)"
done

if grep -q 'Bruno Dobner' "$C" && grep -q 'MODULE_AUTHOR("Bruno Dobner' "$C"; then
    ok "o autor atual assina o driver"
else
    falha "Bruno Dobner ausente do cabecalho ou do MODULE_AUTHOR"
fi

# --- a limpeza cobre o nome antigo: sem isso sobra DKMS orfao
for padrao in 'dkms remove' 'linuwu_sense'; do
    if grep -q -- "$padrao" "$S"; then
        ok "a desinstalacao conhece: $padrao"
    else
        falha "a desinstalacao nao trata: $padrao"
    fi
done

# --- e os grupos sysfs NAO podem ter sido renomeados: sao do firmware
for grupo in nitro_sense predator_sense; do
    if grep -q "$grupo" "$C"; then
        ok "grupo sysfs $grupo intacto"
    else
        falha "grupo sysfs $grupo foi renomeado -- quebra o driver"
    fi
done

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: a renomeacao esta completa e nao apagou o que nao devia"
exit 0
