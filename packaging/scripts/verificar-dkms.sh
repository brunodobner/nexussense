#!/bin/sh
# Confere se o nexus_sense foi construido para todos os kernels bootaveis.
#
# Chamado pelo gancho do pacman depois que um kernel e instalado ou
# atualizado. O DKMS ja tenta reconstruir sozinho, e quase sempre
# consegue; este script existe para o caso em que ele NAO consegue.
#
# Por que importa: o instalador poe 'blacklist acer_wmi' para os dois
# drivers nao disputarem os mesmos GUIDs WMI. Se o nexus_sense nao
# constroi para o kernel novo, o boot seguinte fica sem driver Acer
# NENHUM -- sem perfis termicos, sem ventoinha, sem os atributos. E a
# mensagem de erro do DKMS se perde no meio de uma atualizacao grande.
#
# Este script troca "descobri no boot seguinte, com a maquina sem
# controle termico" por "o pacman me avisou e eu conserto quando quiser".
#
# Nunca falha a transacao: sai 0 sempre. Avisar e o trabalho dele;
# derrubar a atualizacao do usuario nao e.
set -u

VERMELHO='\033[0;31m'; AMARELO='\033[0;33m'; VERDE='\033[0;32m'; NC='\033[0m'

command -v dkms > /dev/null 2>&1 || exit 0

# 'dkms status' sai 0 ate para pacote inexistente -- ver armadilha 6.
# Procure a palavra, nunca o codigo de saida.
versao=$(dkms status nexus_sense 2>/dev/null | head -1 | sed 's|^nexus_sense[/,] *||; s|,.*||')
[ -n "$versao" ] || exit 0   # nao instalado por DKMS: nada a conferir

faltando=""
for caminho in /lib/modules/*/; do
    kver=${caminho#/lib/modules/}
    kver=${kver%/}
    # vmlinuz e o discriminador de kernel bootavel: headers sem o pacote
    # do kernel criam o diretorio sem imagem nenhuma. Ver install_drivers.
    [ -e "${caminho}vmlinuz" ] || continue
    if ! dkms status "nexus_sense/${versao}" -k "$kver" 2>/dev/null | grep installed > /dev/null; then
        faltando="${faltando} ${kver}"
    fi
done

if [ -z "$faltando" ]; then
    printf "${VERDE}Nexus Sense: modulo presente em todos os kernels bootaveis.${NC}\n"
    exit 0
fi

printf "\n${VERMELHO}=====================================================================${NC}\n"
printf "${VERMELHO} ATENCAO: o nexus_sense NAO foi construido para:${NC}\n"
for k in $faltando; do printf "${VERMELHO}   - %s${NC}\n" "$k"; done
printf "\n"
printf "${AMARELO} Se voce bootar nesse kernel, ficara sem driver Acer nenhum --${NC}\n"
printf "${AMARELO} sem perfis termicos, sem controle de ventoinha, sem os atributos.${NC}\n"
printf "${AMARELO} O acer_wmi do kernel esta na blacklist para nao brigar com ele.${NC}\n"
printf "\n"
printf " Diagnostico:\n"
printf "   dkms install -m nexus_sense -v %s -k <kernel>\n" "$versao"
printf "\n"
printf " Socorro, se precisar bootar antes de consertar:\n"
printf "   sudo rm /etc/modprobe.d/blacklist-acer_wmi.conf\n"
printf "   # reinicia; o acer_wmi oficial assume e devolve perfis termicos\n"
printf "   # e leitura de ventoinha. Perde so os cinco controles.\n"
printf "${VERMELHO}=====================================================================${NC}\n\n"
exit 0
