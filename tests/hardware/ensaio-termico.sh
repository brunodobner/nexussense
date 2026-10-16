#!/bin/bash
# Ensaio termico da ventoinha manual -- docs/plano-termico.md, e os ensaios
# da curva propria, de docs/plano-curva.md.
#
# ESTE ROTEIRO ESCREVE EM fan_speed NA MAQUINA DE VERDADE. Nao faz parte da
# suite: quem o roda e uma pessoa, com o combinado da secao 9 do plano feito
# antes. O que a suite roda e tests/shell/test-ensaio-termico.sh (e os -e3,
# -rede e -curva ao lado dele), que exercitam esta mesma logica contra uma
# arvore de mentira (ENSAIO_RAIZ).
#
# Uso:   tests/hardware/ensaio-termico.sh e2 [saida.tsv]
#        tests/hardware/ensaio-termico.sh e3 [saida.tsv]
#        tests/hardware/ensaio-termico.sh e3b [saida.tsv]
#        tests/hardware/ensaio-termico.sh rede [saida.tsv]
#        tests/hardware/ensaio-termico.sh ec2 [saida.tsv]
#        tests/hardware/ensaio-termico.sh ec2-jogo [saida.tsv]
#        tests/hardware/ensaio-termico.sh ec3 [saida.tsv]
#        tests/hardware/ensaio-termico.sh ec5 [saida.tsv]
#        tests/hardware/ensaio-termico.sh ec5-volta
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
#   e3b  o mesmo, com um jogo no lugar da carga: o jogo TEM de estar aberto,
#        do comeco ao fim, e quem o abre e voce. Dois minutos em automatico,
#        para a referencia; cinco com o manual no piso; dois de volta ao
#        automatico. O roteiro nao liga carga nenhuma.
#
#   rede a prova da rede do agente (secao 11 do plano), tambem com um jogo
#        aberto, e no modo maximo em que a maquina estiver. Dois controles --
#        um minuto em automatico, um minuto em manual ACIMA do que o
#        automatico faria -- em que fan_speed nao pode mudar. Depois o manual
#        no piso, onde fan_speed TEM de voltar a 0,0 por outra mao: a do
#        agente. O roteiro fica de vigia, com os mesmos limites, e so devolve
#        a ventoinha ele mesmo se a rede nao agir. E o unico modo em que a
#        outra mao e o que se espera.
#
# Os ensaios da curva propria -- docs/plano-curva.md, secao 6. Valem as mesmas
# regras (docs/plano-termico.md, secao 5) e os mesmos limites de aborto (a
# secao 7 de la). O que muda e que alguns pedem gestos seus: o roteiro escreve
# uma linha GESTO, espera o efeito aparecer no que le e confere. Enquanto um
# gesto dura, so a condicao que ele muda sai da conferencia; o resto -- os
# limites, a outra mao na ventoinha, o prazo -- segue valendo a cada amostra.
#
#   ec2  qual curva do EC, e o que a rotacao acima do teto compra. ESQUENTA A
#        MAQUINA: dez estagios de 180 s com a carga de CPU do E3, uma alavanca
#        de cada vez. 1 automatico, modo maximo desligado, perfil de energia
#        performance; 2 o mesmo em balanced; 3 automatico com o modo ligado;
#        4 o manual que o mapa de E2 diz girar o teto do 3 -- o controle: tem
#        de girar como ele, a 300 rpm, ou o ensaio para com 13; 5 manual a 92%;
#        6 o maximo do firmware (100,100); 7 o automatico do 3 de novo, que da
#        o ruido da medida; 8 automatico logo depois de desligar o modo; 9 em
#        balanced; 10 em performance. Entre dois estagios, descida ate o pacote
#        voltar a 60 C, ou 120 s. Depois, a parte com o jogo, com o modo
#        ligado: tres minutos em automatico, no maximo do firmware e em
#        automatico de novo. Conta o ultimo minuto de cada estagio. No fim, C1
#        (a curva que cada estagio em automatico pegou) e a regra da secao 7
#        do plano curva, com o veredito R0 ou R1. ~45 min, mais ~10 do jogo.
#        O ROTEIRO TROCA O PERFIL DE ENERGIA (power-profiles-daemon) e o devolve
#        no fim -- pelo trap e, num kill -9, pelo vigia. O MODO MAXIMO E VOCE
#        QUEM LIGA E DESLIGA, NA BANDEJA: o roteiro o pede com o perfil de
#        energia ainda em balanced, espera o config.toml mudar e confere que o
#        modo pos o perfil em performance. O jogo tambem e gesto seu. A
#        potencia pelo RAPL, opcional no plano, nao esta aqui: pede root.
#
#   ec2-jogo  so a parte com o jogo do ec2, para refaze-la sem a de CPU.
#
#   ec3  o ouvido, em repouso. A ventoinha passa por 30, 45, 55, 65, 75, 85, 92
#        e 99% e pelo maximo do firmware, 15 s em cada, e depois de cada uma o
#        roteiro pergunta no terminal: t (aceito trabalhando), j (so jogando)
#        ou n. Depois, quatro janelas de escuta em torno do limite de trabalho:
#        em tres a ventoinha sobe 5%, e em uma -- o controle -- nada muda. A
#        cada janela, "ouviu uma troca?". As respostas vem da entrada padrao;
#        sem elas, o roteiro devolve a ventoinha e sai com 11. ~5 min.
#
#   ec5  o que larga o manual, com a ventoinha a 95%. Gestos seus: suspender e
#        acordar, tirar e por o cabo, trocar o perfil termico para balanced e
#        voltar. A cada um o roteiro diz se a rotacao manteve o manual, largou,
#        ou largou e voltou a ele. Depois, o exercicio do guarda: o agente leva
#        kill -9, e depois SIGSTOP (travado, mas vivo); nos dois a ventoinha
#        tem de voltar a 0,0 por outra mao -- o ExecStopPost e o WatchdogSec
#        da unit -- e a rotacao tem de sair do manual. O guarda so devolve o
#        que o agente registrou ter escrito, e o roteiro registra por ele.
#        Sem o guarda na unit, o exercicio diz que nao rodou, e o roteiro sai
#        com 17. Por ultimo, pede
#        o reinicio e sai DE PROPOSITO COM A VENTOINHA A 95%: nem o trap nem o
#        vigia a devolvem. ~10 min. Antes de cada gesto e do guarda reescreve
#        os 95% e confere a rotacao: a suspensao faz o firmware largar o
#        manual com fan_speed ainda dizendo o valor. ENSAIO_C5_GESTOS escolhe
#        os gestos (padrao "suspensao cabo perfil"; vazio, nenhum); ENSAIO_C5_REINICIO=0
#        termina sem pedir o reinicio, com a ventoinha devolvida.
#
#   ec5-volta  depois do reinicio e do login: le o que voltou na partida
#        (fan_speed e rotacao), devolve 0,0 se for o manual do ec5 e fecha o
#        resumo. Sem reinicio (o mesmo boot_id), so devolve, e sai com 11.
#
# Todo traco tem, no fim, o perfil de energia (ppd) e a preferencia de
# energia da CPU (epp). O perfil de energia tambem troca a curva do
# automatico (armadilha 37): se ele muda no meio de uma medicao sem o roteiro
# pedir, a medicao para, como com o perfil termico.
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
#   3. no E3 e no ec2, o timeout de cada processo de carga: sem roteiro e
#      sem vigia a ventoinha fica em manual, mas o calor para sozinho;
#   4. voce: Ctrl-C, ou "Automatico" na janela. Se fan_speed aparecer com um
#      valor que o roteiro nao escreveu, ele para e NAO escreve por cima.
# O perfil de energia, quando o roteiro o troca (ec2), volta pelas camadas 1
# e 2. O agente que o ec5 deixa sob SIGSTOP tambem: o trap e o vigia o soltam.
#
# A curva propria do agente sai enquanto o ensaio roda, em todos os modos.
# Desde 2026-10-17 ela e o Automatico neste modelo: com ela valendo, o agente
# toma o 0,0 em 2 s e grava o par dela, e o ensaio mediria a curva -- ou
# pararia na outra mao. Antes da partida o roteiro grava fan_curve = false no
# config.toml, so essa linha, e espera o agente devolver o automatico; no fim
# devolve a linha como estava (ausente, true ou false), pelas camadas 1 e 2.
# Morto antes de o vigia subir, a curva fica desligada: o firmware segue no
# automatico, o lado seguro. No ec5 a pausa atravessa o reinicio, e quem a
# devolve e o ec5-volta.
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
#   16  a prova da rede falhou: ela nao agiu no piso, agiu num controle,
#       devolveu o manual, ou a rotacao nao saiu do manual
#   17  ec5: a unit do agente nao tem o guarda (ExecStopPost e WatchdogSec), e
#       o exercicio dele nao rodou inteiro. O resto do ec5 vale.
# No ec2, 13 e tambem o controle do estagio 4; no ec5, 14 e o guarda que nao
# devolveu a ventoinha, e 0 e 17 saem com ela a 95% de proposito, para o
# reinicio.
set -u

COD_ALVO=3; COD_LIMITE=10; COD_CONDICAO=11; COD_RECUSA=12
COD_CONTROLE=13; COD_EXERCICIO=14; COD_DEVOLUCAO=15; COD_REDE=16; COD_SEM_GUARDA=17

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

# O E3b, tambem em amostras.
E3B_PRE=${ENSAIO_E3B_PRE:-120}           # com jogo, em automatico: a referencia
E3B_CARGA=${ENSAIO_E3B_CARGA:-300}       # com jogo, manual no piso
E3B_DESCIDA=${ENSAIO_E3B_DESCIDA:-120}   # de volta ao automatico, o jogo ainda aberto

# A prova da rede, tambem em amostras. As porcentagens: o automatico com
# jogo equivale a ~53% de manual com o modo maximo desligado e a ~81% com ele
# ligado (secao 6 do plano); o controle "acima" fica com folga dos dois. O
# piso e 20%, o comeco da barra da tela Desempenho: gira o mesmo que 1%.
REDE_AUTO=${ENSAIO_REDE_AUTO:-60}        # com jogo, em automatico
REDE_ACIMA=${ENSAIO_REDE_ACIMA:-60}      # com jogo, manual acima do equivalente
REDE_PISO=${ENSAIO_REDE_PISO:-30}        # quanto se espera a rede, no piso
REDE_DEPOIS=${ENSAIO_REDE_DEPOIS:-30}    # em automatico, depois de ela agir
REDE_P_PISO=${ENSAIO_REDE_P_PISO:-20}
REDE_P_ACIMA=${ENSAIO_REDE_P_ACIMA:-60}
REDE_P_ACIMA_MAX=${ENSAIO_REDE_P_ACIMA_MAX:-90}
# O piso so e escrito com a GPU pelo EC a esta distancia do limite. A rede
# leva de 2 a 4 s para agir, e no piso a GPU sobe um grau por segundo: mais
# perto que isso, quem chegaria primeiro e o aborto -- e a prova mediria o
# ponto de partida, nao a rede. O E3b partiu de 79 C, a seis do limite.
REDE_FOLGA=${ENSAIO_REDE_FOLGA:-6000}

FAN="$R/sys/devices/platform/acer-wmi/nitro_sense/fan_speed"
PERFIL="$R/sys/firmware/acpi/platform_profile"
BAT="$R/sys/class/power_supply/BAT1"
ACAD="$R/sys/class/power_supply/ACAD/online"
TT="$R/sys/devices/system/cpu/cpu0/thermal_throttle"
SUSPENSOES="$R/sys/power/suspend_stats/success"
BOOT_ID="$R/proc/sys/kernel/random/boot_id"

# O perfil de energia mora no power-profiles-daemon e se le e escreve pelo
# barramento de sistema, como em src/nexus_sense/ppd.py. O agente se pergunta
# pela unit de usuario. Numa arvore de mentira o barramento e o gerenciador
# continuam sendo os da maquina de verdade (armadilha 30): sem um busctl e um
# systemctl dados de proposito, o roteiro nao fala com nenhum dos dois.
PPD_SERVICO=org.freedesktop.UPower.PowerProfiles
PPD_OBJETO=/org/freedesktop/UPower/PowerProfiles
UNIT_AGENTE=nexus-sense-agent.service
RUNTIME_AGENTE=nexus-sense      # o RuntimeDirectory da unit, onde mora o registro do guarda
BUSCTL=${ENSAIO_BUSCTL:-busctl}
SYSTEMCTL=${ENSAIO_SYSTEMCTL:-systemctl}
if [ -n "$R" ]; then BUSCTL=${ENSAIO_BUSCTL:-}; SYSTEMCTL=${ENSAIO_SYSTEMCTL:-}; fi

RUN=; VIGIA_PID=; SAIDA=
ULTIMO="0,0"          # o que este roteiro espera ler em fan_speed
DEVOLVIDO=0; FALHOU_DEVOLVER=0
REPOUSO=0             # 1 no E2: vale o limite de pacote mais baixo
COM_JOGO=0            # 1 no E3b: o jogo tem de estar aberto, em vez de fechado
N_PAC=0; MOTIVO=
PERFIL0=; MAX0=; FIM=0
REF1=; REF2=          # rotacao do automatico na partida: informa, nao julga
DRILL_PID=; DRILL_VALOR=
DRILL_RPM1=; DRILL_RPM2=   # o que a porcentagem dos exercicios gira
RESUMO=; ABORTOU=0; RETOMOU_NO_ULTIMO=0
PPD0=                 # o perfil de energia que a medicao espera
PPD_INICIAL=; MAX_INICIAL=   # o que devolver no fim, quando o roteiro mexe nele
CURVA_INICIAL=        # a linha fan_curve da partida (ausente, true), quando o roteiro a pausa
CURVA_ESPERA=${ENSAIO_CURVA_ESPERA:-10}   # segundos para o agente devolver o automatico
LIVRE=                # condicoes que um gesto pedido esta mudando: verifica() as pula
ACEITA_FAN=           # um fan_speed alem do escrito que nao e outra mao (o guarda)
AGENTE_PARADO=        # pid do agente sob SIGSTOP, para o trap o soltar

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

le_max() { grep -m1 '^maximum_mode' "$CFG" 2>/dev/null | tr -d ' ' | cut -d= -f2; }

ppd_le() {    # o perfil de energia, ou NA. A resposta: {"type":"s","data":"performance"}
    local v
    [ -n "$BUSCTL" ] || { echo NA; return 0; }
    v=$("$BUSCTL" --system --timeout=2 --json=short get-property \
            "$PPD_SERVICO" "$PPD_OBJETO" "$PPD_SERVICO" ActiveProfile 2>/dev/null \
        | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')
    echo "${v:-NA}"
}

ppd_poe() {   # $1 = perfil de energia. Confere lendo de volta: o efeito, nao o comando.
    local i
    [ -n "$BUSCTL" ] || return 1
    "$BUSCTL" --system --timeout=2 set-property "$PPD_SERVICO" "$PPD_OBJETO" \
        "$PPD_SERVICO" ActiveProfile s "$1" > /dev/null 2>&1 || return 1
    for ((i = 0; i < 20; i++)); do
        [ "$(ppd_le)" = "$1" ] && return 0
        sleep 0.1
    done
    return 1
}

epp_le() {    # a preferencia de energia dos nucleos; se elas discordam, todas, com +
    local v
    v=$(cat "$R"/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null \
        | sort -u | paste -sd+)
    echo "${v:-NA}"
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
    # O perfil de energia antes do modo maximo: quem liga ou desliga o modo
    # grava o config.toml primeiro e so depois troca o perfil de energia
    # (src/nexus_sense/maximum.py). Lidos nesta ordem, um gesto pego no meio
    # nunca mostra o perfil novo com o modo velho.
    V_PPD=$(ppd_le); V_EPP=$(epp_le)
    V_MAX=$(le_max)
    V_JOGO=$(ps -eo comm --no-headers 2>/dev/null | grep -cE "^(${JOGOS})$")
    V_LOAD=$(cut -d' ' -f1 "$R/proc/loadavg" 2>/dev/null || echo NA)
    # A bateria se le pela carga, nao pelo status (armadilha 36).
    V_PCT=NA
    if eh_num "$V_CHARGE" && eh_num "$V_CHEIA" && [ "$V_CHEIA" -gt 0 ]; then
        V_PCT=$(( V_CHARGE * 100 / V_CHEIA ))
    fi
}

# As duas ultimas colunas, ppd e epp, entraram depois: as 29 primeiras ficam
# onde estavam, e quem as le pelo numero continua lendo a certa.
CABECALHO='epoch\thora\tfase\tescrito\tfan_speed\trpm_cpu\trpm_gpu\tpacote\tcrit_alarm\tec_cpu\tec_gpu\tec_ext2\tsen2\tsen3\tsen4\tsen5\tnvme1\tnvme2\tthr_n\tthr_ms\tmhz\tcharge_now\tpct\tcorrente_uA\tacad\tperfil\tmaximo\tjogo\tload1\tppd\tepp\n'

registra() {
    [ -n "$SAIDA" ] || return 0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$EPOCHSECONDS" "$(date +%T)" "$FASE" "$ULTIMO" "$V_FAN" "$V_RPM1" "$V_RPM2" \
        "$V_PAC" "$V_ALARM" "$V_ECCPU" "$V_ECGPU" "$V_EXT2" \
        "$V_SEN2" "$V_SEN3" "$V_SEN4" "$V_SEN5" "$V_NV1" "$V_NV2" \
        "$V_THRN" "$V_THRMS" "$V_MHZ" "$V_CHARGE" "$V_PCT" "$V_CORR" "$V_ACAD" \
        "$V_PERFIL" "$V_MAX" "$V_JOGO" "$V_LOAD" "$V_PPD" "$V_EPP" >> "$SAIDA"
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

livre() { case " $LIVRE $LIVRE_SEMPRE " in *" $1 "*) return 0 ;; esac; return 1; }

verifica() {  # julga a ultima amostra. 0, COD_LIMITE ou COD_CONDICAO; ver MOTIVO
    local par nome valor lim_pac
    MOTIVO=

    # Primeiro a outra mao: se alguem escreveu na ventoinha, a escolha e de
    # quem a fez, e devolve() nao escreve por cima. ACEITA_FAN so existe no
    # exercicio do guarda, em que o 0,0 de outra mao e o que se espera.
    if [ "$V_FAN" != "$ULTIMO" ] && { [ -z "$ACEITA_FAN" ] || [ "$V_FAN" != "$ACEITA_FAN" ]; }; then
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

    # Um gesto pedido -- tirar o cabo, ligar o modo maximo, abrir o jogo --
    # muda a condicao de proposito: enquanto ele dura, quem o pediu confere.
    if ! livre cabo && [ "$V_ACAD" != 1 ]; then
        MOTIVO="cabo fora (ACAD/online = $V_ACAD)"; return "$COD_CONDICAO"
    fi
    if [ "$V_PCT" -lt "$LIM_CARGA" ]; then
        MOTIVO="bateria em $V_PCT%, abaixo de $LIM_CARGA%"; return "$COD_CONDICAO"
    fi
    if ! livre perfil && [ "$V_PERFIL" != "$PERFIL0" ]; then
        MOTIVO="o perfil mudou de $PERFIL0 para $V_PERFIL"; return "$COD_CONDICAO"
    fi
    if ! livre maximo && [ "$V_MAX" != "$MAX0" ]; then
        MOTIVO="o modo maximo mudou de '$MAX0' para '$V_MAX'"; return "$COD_CONDICAO"
    fi
    # O perfil de energia tambem troca a curva do automatico (armadilha 37).
    if ! livre ppd && [ "$V_PPD" != "$PPD0" ]; then
        MOTIVO="o perfil de energia mudou de '$PPD0' para '$V_PPD'"; return "$COD_CONDICAO"
    fi
    if livre jogo; then
        :
    elif [ "$COM_JOGO" = 1 ]; then
        if [ "$V_JOGO" = 0 ]; then
            MOTIVO="o jogo fechou (nenhum processo casando com $JOGOS)"; return "$COD_CONDICAO"
        fi
    elif [ "$V_JOGO" != 0 ]; then
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

devolve_ppd() {   # o perfil de energia volta ao da partida, se o roteiro o mexeu
    local atual
    [ -n "$PPD_INICIAL" ] && [ "$PPD_INICIAL" != NA ] || return 0
    atual=$(ppd_le)
    [ "$atual" = "$PPD_INICIAL" ] && return 0
    # Com o modo maximo ligado o agente repoe o performance a cada passada:
    # escrever por cima seria brigar com ele. Quem devolve e desligar o modo.
    if [ "$(le_max)" = true ] && [ "$MAX_INICIAL" != true ]; then
        avisa "o modo maximo segue ligado: desligue-o na bandeja. O perfil de energia da partida era $PPD_INICIAL; confira depois."
        return 0
    fi
    if ppd_poe "$PPD_INICIAL"; then
        avisa "perfil de energia devolvido: $PPD_INICIAL (estava em $atual)"
    else
        avisa "ERRO: nao consegui devolver o perfil de energia a $PPD_INICIAL; ele esta em $(ppd_le)"
    fi
}

le_curva() {   # a linha fan_curve do config: true, false, ou ausente (sem a linha, ou sem o arquivo)
    local v
    v=$(grep -m1 '^fan_curve' "$CFG" 2>/dev/null | tr -d ' ' | cut -d= -f2)
    echo "${v:-ausente}"
}

poe_curva() {   # $1 = true, false ou ausente. So a linha fan_curve muda; o resto do config fica
    local novo="$CFG.ensaio.$$"
    if grep -q '^fan_curve' "$CFG" 2>/dev/null; then
        if [ "$1" = ausente ]; then
            grep -v '^fan_curve' "$CFG" > "$novo"
        else
            sed "s/^fan_curve.*/fan_curve = $1/" "$CFG" > "$novo"
        fi
    elif [ "$1" = ausente ]; then
        return 0
    else
        # No topo: no TOML, uma chave depois de uma tabela seria da tabela.
        mkdir -p "$(dirname "$CFG")" || return 1
        { echo "fan_curve = $1"; cat "$CFG" 2>/dev/null; } > "$novo"
    fi
    # A troca e atomica, como a do config.save: o agente rele a cada passada.
    mv "$novo" "$(readlink -f "$CFG")"
}

pausa_curva() {   # antes da partida: a curva sai, e o agente devolve o automatico
    local i
    CURVA_INICIAL=$(le_curva)
    if [ "$CURVA_INICIAL" = false ]; then CURVA_INICIAL=; return 0; fi
    # Os traps do modo vem depois da partida; ate la, estes devolvem a linha.
    trap devolve_curva EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    if ! poe_curva false; then
        echo "ERRO: nao consegui gravar fan_curve = false em $CFG"
        CURVA_INICIAL=
        exit "$COD_RECUSA"
    fi
    echo "curva propria pausada (fan_curve = false, era $CURVA_INICIAL); volta como estava no fim"
    for ((i = 0; i < CURVA_ESPERA * 10; i++)); do
        [ "$(le "$FAN")" = "0,0" ] && return 0
        sleep 0.1
    done
    echo "  o agente nao devolveu o automatico em ${CURVA_ESPERA}s: fan_speed segue $(le "$FAN")"
}

devolve_curva() {   # a linha fan_curve volta a ser a da partida, se o roteiro a pausou
    local inicial=$CURVA_INICIAL
    [ -n "$inicial" ] || return 0
    CURVA_INICIAL=
    [ -n "$RUN" ] && rm -f "$RUN/curva_inicial"
    if poe_curva "$inicial"; then
        avisa "curva propria devolvida: fan_curve $inicial"
    else
        avisa "ERRO: nao consegui devolver fan_curve a '$inicial' em $CFG; confira o arquivo"
    fi
}

solta_agente() {  # o agente que um exercicio deixou sob SIGSTOP volta a andar
    [ -n "$AGENTE_PARADO" ] || return 0
    kill -CONT "$AGENTE_PARADO" 2>/dev/null
    AGENTE_PARADO=
}

ao_sair() {
    local rc=$?
    trap - EXIT INT TERM HUP
    solta_agente
    if [ -n "$DRILL_PID" ] && kill -0 "$DRILL_PID" 2>/dev/null; then
        kill -TERM "$DRILL_PID" 2>/dev/null
        sleep 1
    fi
    # Um exercicio interrompido pode ter deixado o valor dele em fan_speed.
    [ -n "$DRILL_VALOR" ] && [ "$(le "$FAN")" = "$DRILL_VALOR" ] && ULTIMO=$DRILL_VALOR
    devolve
    devolve_ppd
    devolve_curva
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
    # O vigia devolve tambem o perfil de energia, quando o roteiro o mexe.
    if [ -n "$PPD_INICIAL" ]; then
        printf '%s\n' "$PPD_INICIAL" > "$RUN/ppd_inicial"
        printf '%s\n' "$MAX_INICIAL" > "$RUN/max_inicial"
    fi
    # E a curva, quando o roteiro a pausou.
    [ -n "$CURVA_INICIAL" ] && printf '%s\n' "$CURVA_INICIAL" > "$RUN/curva_inicial"
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
    # Primeiro a ventoinha; o perfil de energia, se o roteiro o mexeu, depois.
    [ -e "$RUN/agente_parado" ] && kill -CONT "$(cat "$RUN/agente_parado")" 2>/dev/null
    if [ -s "$RUN/ppd_inicial" ]; then
        PPD_INICIAL=$(cat "$RUN/ppd_inicial"); MAX_INICIAL=$(cat "$RUN/max_inicial" 2>/dev/null)
        devolve_ppd
    fi
    # Por ultimo a curva: com a ventoinha ja em 0,0, ela a retoma.
    if [ -s "$RUN/curva_inicial" ]; then
        CURVA_INICIAL=$(cat "$RUN/curva_inicial")
        devolve_curva
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
    echo "  cabo $V_ACAD   bateria $V_PCT%   load1 $V_LOAD   jogo $V_JOGO   perfil de energia $V_PPD   EPP $V_EPP"
}

pode_comecar() {    # a condicao de partida do E2; nada foi escrito ainda. $1 = 1: aceita o modo maximo ligado
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
    [ "${1:-0}" != 1 ] && [ "$V_MAX" = true ] && recusa "modo maximo ligado; o ensaio e com ele desligado"
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
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
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
    pausa_curva
    amostra partida; registra
    exige_alvos || exit "$COD_ALVO"
    mostra_condicao
    pode_comecar || exit "$COD_RECUSA"
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD

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
    pausa_curva
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
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
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

# -------------------------------------------------------------------- E3b

tempo_ms() { awk -v n="$1" -v p="$PASSO" 'BEGIN { printf "%d", n * p * 1000 }'; }

modo_e3b() {
    local p=${ENSAIO_E3B_P:-$E3_P2} rc=0 rc2 i=0 nao=0 t0 t0ms dur_ms seg thr pct="?"
    local a1=() a2=() auto1 auto2 r1s=() r2s=() ref1="?" ref2="?" cnt=0 retomou=0 resta=0
    local fim=completo quando="" ec thr0 ch0 mhz=0 nm=0
    local mp=0 me=0 mg=0 m2=0 m3=0 m4=0 m5=0 mr1=0 mr2=0
    COM_JOGO=1; REPOUSO=0
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-e3b-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    RESUMO="${SAIDA%.tsv}.resumo.txt"

    echo "E3b -- manual no piso com um jogo aberto. O JOGO E A CARGA."
    echo "saida: $SAIDA"
    pausa_curva
    amostra partida; registra
    exige_alvos || exit "$COD_ALVO"
    mostra_condicao
    recusa() { echo "  RECUSA: $1"; nao=1; }
    [ "$V_FAN" = "0,0" ] || recusa "fan_speed e '$V_FAN'; o ensaio so comeca em 0,0 (automatico)"
    [ "$V_ACAD" = 1 ] || recusa "fora da tomada"
    eh_num "$V_PCT" && [ "$V_PCT" -ge "$PARTIDA_CARGA" ] \
        || recusa "bateria em $V_PCT%, abaixo de $PARTIDA_CARGA%"
    [ "$V_JOGO" != 0 ] || recusa "nenhum jogo aberto (nenhum processo casando com $JOGOS)"
    [ "$V_MAX" = true ] && recusa "modo maximo ligado; o ensaio e com ele desligado"
    [ "$nao" = 0 ] || exit "$COD_RECUSA"
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
    # Um limite ja estourado em automatico: escrever o manual so mediria o aborto.
    verifica; rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "  RECUSA: ainda em automatico, $MOTIVO"; exit "$COD_RECUSA"
    fi
    echo "perfil $PERFIL0, modo maximo ${MAX0:-?}; com jogo ($V_JOGO processo(s))" > "$RESUMO"

    prepara

    # ---- a referencia: o automatico, com o jogo
    dur_ms=$(tempo_ms "$E3B_PRE")
    echo
    echo "COM JOGO, EM AUTOMATICO -- $(( dur_ms / 1000 )) s"
    t0ms=$(agora_ms)
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        amostra "b:auto"; registra
        verifica; rc=$?
        if [ "$rc" -eq "$COD_LIMITE" ]; then
            MOTIVO="ainda em automatico, $MOTIVO: o limite estoura sem o manual, e o ensaio nao conta"
            termina "$COD_CONDICAO"
        fi
        [ "$rc" -ne 0 ] && termina "$rc"
        a1+=("$V_RPM1"); a2+=("$V_RPM2")
    done
    auto1=$(mediana "${a1[@]}"); auto2=$(mediana "${a2[@]}")
    echo "com jogo, em automatico: $auto1 / $auto2 rpm; pacote $V_PAC, GPU pelo EC $V_ECGPU, SEN2-5 $V_SEN2 $V_SEN3 $V_SEN4 $V_SEN5" \
        | tee -a "$RESUMO"

    # ---- o manual no piso
    dur_ms=$(tempo_ms "$E3B_CARGA")
    echo
    echo "COM JOGO, MANUAL A $p% -- ate $(( dur_ms / 1000 )) s"
    if ! escreve "$p,$p"; then MOTIVO="a escrita de $p,$p foi recusada"; termina "$COD_CONDICAO"; fi
    thr0=$V_THRMS; ch0=$V_CHARGE; t0=$EPOCHSECONDS; t0ms=$(agora_ms); rc=0
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        i=$(( i + 1 ))
        amostra "b:manual"; registra
        verifica; rc=$?
        maior mp "$V_PAC"; maior me "$V_ECCPU"; maior mg "$V_ECGPU"
        maior m2 "$V_SEN2"; maior m3 "$V_SEN3"; maior m4 "$V_SEN4"; maior m5 "$V_SEN5"
        maior mr1 "$V_RPM1"; maior mr2 "$V_RPM2"
        if eh_num "$V_MHZ"; then mhz=$(( mhz + V_MHZ )); nm=$(( nm + 1 )); fi
        if [ "$rc" -ne 0 ]; then fim="aborto: $MOTIVO, aos $(( EPOCHSECONDS - t0 )) s"; break; fi
        if [ $(( i % E3_ECO )) -eq 0 ]; then
            echo "  +$i: pacote $V_PAC, GPU pelo EC $V_ECGPU, rotacao $V_RPM1 / $V_RPM2, SEN2-5 $V_SEN2 $V_SEN3 $V_SEN4 $V_SEN5"
        fi
        if [ "$retomou" = 1 ]; then
            resta=$(( resta - 1 ))
            [ "$resta" -le 0 ] && break
        elif [ "$i" -le 8 ]; then
            # A ventoinha assenta em um ou dois segundos (E2). A referencia
            # e a mediana das amostras 3 a 8 depois da escrita.
            if [ "$i" -ge 3 ]; then r1s+=("$V_RPM1"); r2s+=("$V_RPM2"); fi
            if [ "$i" -eq 8 ]; then
                ref1=$(mediana "${r1s[@]}"); ref2=$(mediana "${r2s[@]}")
                echo "  no manual: $ref1 / $ref2 rpm (em automatico: $auto1 / $auto2)"
                # Se nem caiu em relacao ao automatico, o EC nao obedeceu.
                if [ $(( auto1 - ref1 )) -lt "$RETOMA_RPM" ] && [ $(( auto2 - ref2 )) -lt "$RETOMA_RPM" ]; then
                    retomou=1; resta=$E3_EXTRA
                    quando="desde a escrita: a rotacao ficou em $ref1 / $ref2 rpm, contra $auto1 / $auto2 em automatico"
                    echo "  o EC tomou a ventoinha de volta $quando (fan_speed = $V_FAN)"
                fi
            fi
        else
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
    [ "$retomou" = 1 ] && [ "$rc" -eq 0 ] && fim=retomada

    # O jogo fechou, outra mao, bateria, prazo: a medicao nao conta.
    [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"

    if [ "$retomou" = 1 ]; then
        ec="o EC tomou a ventoinha de volta $quando"
    elif [ "$ref1" = "?" ]; then
        # Acabou antes de a referencia assentar: vale a ultima leitura, contra
        # o automatico medido logo antes.
        if eh_num "$V_RPM1" && eh_num "$V_RPM2" \
           && [ $(( auto1 - V_RPM1 )) -ge "$RETOMA_RPM" ] && [ $(( auto2 - V_RPM2 )) -ge "$RETOMA_RPM" ]; then
            ec="o EC obedeceu ao manual: a rotacao caiu de $auto1 / $auto2 rpm, em automatico, para $V_RPM1 / $V_RPM2"
        else
            ec="nao deu tempo de ver se o EC obedeceu: rotacao em $V_RPM1 / $V_RPM2 rpm, contra $auto1 / $auto2 em automatico"
        fi
    else
        ec="o EC obedeceu ao manual: rotacao de $ref1 / $ref2 a no maximo $mr1 / $mr2 rpm"
    fi
    if ! escreve "0,0"; then MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"; fi

    thr=NA
    if eh_num "$thr0" && eh_num "$V_THRMS"; then
        thr=$(( V_THRMS - thr0 ))
        [ "$seg" -gt 0 ] && pct=$(awk -v t="$thr" -v s="$seg" 'BEGIN { printf "%.1f", t / 10 / s }')
    fi
    [ "$nm" -gt 0 ] && mhz=$(( mhz / nm ))
    {
        echo "com jogo, manual $p%: $seg s; fim: $fim"
        echo "    $ec"
        echo "    maximos: pacote $mp, CPU pelo EC $me, GPU pelo EC $mg, SEN2-5 $m2 $m3 $m4 $m5"
        echo "    throttle $thr ms ($pct% do tempo); frequencia media $mhz MHz; charge_now de $ch0 a $V_CHARGE"
    } | tee -a "$RESUMO"

    # ---- de volta ao automatico, o jogo ainda aberto
    dur_ms=$(tempo_ms "$E3B_DESCIDA")
    t0ms=$(agora_ms)
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        amostra "b:descida"; registra
        verifica; rc2=$?
        N_PAC=0
        # O limite que acabou de estourar ainda esta la, esfriando: nao e
        # novidade. O jogo fechar aqui so encurta a descida.
        [ "$rc2" -eq "$COD_CONDICAO" ] && break
    done
    echo "    de volta ao automatico: rotacao $V_RPM1 / $V_RPM2 rpm, pacote $V_PAC, SEN2-5 $V_SEN2 $V_SEN3 $V_SEN4 $V_SEN5" \
        | tee -a "$RESUMO"

    [ "$rc" -eq "$COD_LIMITE" ] && ABORTOU=1
    RETOMOU_NO_ULTIMO=$retomou
    veredito
    echo "E3b terminou. Resumo em $RESUMO"
    [ "$ABORTOU" = 1 ] && exit "$COD_LIMITE"
    exit 0
}

# ------------------------------------------------------------------- rede
# A prova da rede do agente. No resto do roteiro, fan_speed mudar por outra
# mao encerra a medicao; aqui, no piso, e o que se espera -- e nos dois
# controles e o que nao pode acontecer.

REDE_VALOR=      # o piso que a prova escreveu, depois de escrito

falha_rede() {   # $1 = o que deu errado. O trap de EXIT devolve a ventoinha.
    MOTIVO=$1
    # Depois de a rede agir o roteiro espera 0,0. Se o piso desta prova
    # reapareceu em fan_speed -- uma rede que devolve o manual -- ele nao e
    # "outra mao" a respeitar: e o que se veio vigiar, com um jogo aberto.
    [ -n "$REDE_VALOR" ] && [ "$(le "$FAN")" = "$REDE_VALOR" ] && ULTIMO=$REDE_VALOR
    echo "veredito: FALHOU -- $MOTIVO" | tee -a "$RESUMO"
    termina "$COD_REDE"
}

modo_rede() {
    local pa=$REDE_P_ACIMA pp=$REDE_P_PISO nao=0 rc=0 i t0 t0ms dur_ms fatia
    local a1=() a2=() ms="" agiu=0 p1="" p2="" g0 mg=0 saiu
    COM_JOGO=1; REPOUSO=0
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-rede-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    RESUMO="${SAIDA%.tsv}.resumo.txt"

    echo "REDE -- a prova da rede do agente, com um jogo aberto. O JOGO E A CARGA."
    echo "saida: $SAIDA"
    pausa_curva
    amostra partida; registra
    exige_alvos || exit "$COD_ALVO"
    mostra_condicao
    recusa() { echo "  RECUSA: $1"; nao=1; }
    [ "$V_FAN" = "0,0" ] || recusa "fan_speed e '$V_FAN'; a prova so comeca em 0,0 (automatico)"
    [ "$V_ACAD" = 1 ] || recusa "fora da tomada"
    eh_num "$V_PCT" && [ "$V_PCT" -ge "$PARTIDA_CARGA" ] \
        || recusa "bateria em $V_PCT%, abaixo de $PARTIDA_CARGA%"
    [ "$V_JOGO" = 0 ] && recusa "a prova pede um jogo aberto (nenhum processo casando com $JOGOS)"
    [ "$nao" = 0 ] || exit "$COD_RECUSA"
    # O modo maximo fica como estiver, e nao pode mudar no meio: ele troca a
    # curva do automatico, e com ela o que conta como "acima".
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
    [ "$MAX0" = true ] && pa=$REDE_P_ACIMA_MAX
    verifica; rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "  RECUSA: antes de escrever qualquer coisa, $MOTIVO"; exit "$COD_RECUSA"
    fi
    echo "perfil $PERFIL0, modo maximo ${MAX0:-?}; com jogo ($V_JOGO processo(s))" > "$RESUMO"

    prepara

    # ---- controle: o automatico, com o jogo
    dur_ms=$(tempo_ms "$REDE_AUTO")
    echo
    echo "CONTROLE, EM AUTOMATICO -- $(( dur_ms / 1000 )) s"
    t0=$EPOCHSECONDS; t0ms=$(agora_ms)
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        amostra "r:auto"; registra
        verifica; rc=$?
        if [ "$rc" -eq "$COD_LIMITE" ]; then
            MOTIVO="ainda em automatico, $MOTIVO: o limite estoura sem o manual, e a prova nao conta"
            termina "$COD_CONDICAO"
        fi
        [ "$rc" -ne 0 ] && termina "$rc"
        a1+=("$V_RPM1"); a2+=("$V_RPM2")
    done
    echo "controle, em automatico: $(( EPOCHSECONDS - t0 )) s; fan_speed nao saiu de 0,0; rotacao $(mediana "${a1[@]}") / $(mediana "${a2[@]}") rpm, GPU pelo EC $V_ECGPU" \
        | tee -a "$RESUMO"

    # ---- controle: manual acima do que o automatico faria
    dur_ms=$(tempo_ms "$REDE_ACIMA")
    echo
    echo "CONTROLE, MANUAL A $pa% -- $(( dur_ms / 1000 )) s"
    if ! escreve "$pa,$pa"; then MOTIVO="a escrita de $pa,$pa foi recusada"; termina "$COD_CONDICAO"; fi
    t0=$EPOCHSECONDS; t0ms=$(agora_ms)
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        amostra "r:acima"; registra
        if [ "$V_FAN" = "0,0" ]; then
            ULTIMO="0,0"
            falha_rede "no controle, com o manual a $pa%, fan_speed voltou a 0,0 aos $(( EPOCHSECONDS - t0 )) s: a rede agiu onde nao devia, ou alguem escolheu Automatico"
        fi
        verifica; rc=$?
        [ "$rc" -ne 0 ] && termina "$rc"
    done
    echo "controle, manual a $pa%: $(( EPOCHSECONDS - t0 )) s; fan_speed nao saiu de $pa,$pa; rotacao $V_RPM1 / $V_RPM2 rpm, GPU pelo EC $V_ECGPU" \
        | tee -a "$RESUMO"

    # ---- o piso: aqui a outra mao e a rede
    dur_ms=$(tempo_ms "$REDE_PISO")
    fatia=$(awk -v p="$PASSO" 'BEGIN { print p / 10 }')
    echo
    echo "NO PISO, MANUAL A $pp% -- espera a rede por ate $(( dur_ms / 1000 )) s"
    g0=$V_ECGPU
    if acima "$g0" $(( LIM_EC_GPU - REDE_FOLGA + 1 )); then
        MOTIVO="antes do piso a GPU pelo EC ja esta em $g0, a menos de $REDE_FOLGA do limite ($LIM_EC_GPU): o aborto viria antes de a rede ter tempo, e a prova nao conta"
        termina "$COD_CONDICAO"
    fi
    if ! escreve "$pp,$pp"; then MOTIVO="a escrita de $pp,$pp foi recusada"; termina "$COD_CONDICAO"; fi
    REDE_VALOR="$pp,$pp"
    t0=$EPOCHSECONDS; t0ms=$(agora_ms); rc=0
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        # Entre duas amostras, so fan_speed: o driver o responde de memoria, e
        # e ele que da o instante em que a rede agiu.
        for ((i = 0; i < 10; i++)); do
            if [ "$(le "$FAN")" = "0,0" ]; then ms=$(( $(agora_ms) - t0ms )); break; fi
            sleep "$fatia"
        done
        amostra "r:piso"; registra
        maior mg "$V_ECGPU"
        if [ "$V_FAN" = "0,0" ]; then
            [ -n "$ms" ] || ms=$(( $(agora_ms) - t0ms ))
            agiu=1; ULTIMO="0,0"
            break
        fi
        ms=
        verifica; rc=$?
        [ "$rc" -ne 0 ] && break
        p1=$V_RPM1; p2=$V_RPM2
    done

    if [ "$agiu" != 1 ]; then
        # Outro valor em fan_speed, o jogo fechou, bateria, prazo: nao conta.
        [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"
        if [ "$rc" -eq "$COD_LIMITE" ]; then
            echo "no piso, manual a $pp%: a rede NAO agiu antes do limite: $MOTIVO, aos $(( EPOCHSECONDS - t0 )) s" \
                | tee -a "$RESUMO"
            echo "veredito: FALHOU -- o limite veio antes da rede" | tee -a "$RESUMO"
            termina "$COD_LIMITE"
        fi
        echo "no piso, manual a $pp%: a rede NAO agiu em $(( EPOCHSECONDS - t0 )) s; GPU pelo EC de $g0 a no maximo $mg; rotacao $V_RPM1 / $V_RPM2 rpm" \
            | tee -a "$RESUMO"
        # Quem devolve a ventoinha daqui e o trap de EXIT, como em todo aborto.
        falha_rede "a rede nao agiu no prazo do piso, e nenhum limite estourou"
    fi

    echo "no piso, manual a $pp%: a rede devolveu o automatico em $ms ms; GPU pelo EC de $g0 a $V_ECGPU; rotacao no piso ${p1:-?} / ${p2:-?} rpm" \
        | tee -a "$RESUMO"
    if ! eh_num "$p1" || ! eh_num "$p2"; then
        falha_rede "fan_speed voltou a 0,0 antes da primeira amostra no piso: nao ha rotacao de referencia"
    fi
    # fan_speed e a memoria do driver. Quem diz que o EC largou o manual e a
    # rotacao -- e ela tem de sair do piso, nao de chegar a um numero.
    saiu=$(rotacao_largou 15 "$p1" "$p2" "$QUEDA_RPM" qualquer); rc=$?
    echo "$saiu" | tee -a "$RESUMO"
    [ "$rc" -eq 0 ] || falha_rede "fan_speed voltou a 0,0, mas a rotacao nao saiu do manual"

    # ---- depois: a rede nao devolve o manual
    dur_ms=$(tempo_ms "$REDE_DEPOIS")
    t0=$EPOCHSECONDS; t0ms=$(agora_ms)
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        amostra "r:depois"; registra
        if [ "$V_FAN" = "$pp,$pp" ]; then
            # E o manual desta prova, de volta: falha_rede manda devolve-lo.
            falha_rede "depois de a rede agir, fan_speed voltou a $V_FAN aos $(( EPOCHSECONDS - t0 )) s"
        fi
        verifica; rc=$?
        N_PAC=0
        # O limite que quase estourou ainda esta la, esfriando, com a
        # ventoinha ja em automatico: nao ha mais o que devolver.
        [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"
    done
    echo "depois: $(( EPOCHSECONDS - t0 )) s em automatico; fan_speed nao saiu de 0,0; rotacao $V_RPM1 / $V_RPM2 rpm, GPU pelo EC $V_ECGPU" \
        | tee -a "$RESUMO"
    echo "veredito: PASSOU -- a rede agiu no piso antes de qualquer limite, e nao agiu nos dois controles" \
        | tee -a "$RESUMO"
    echo "Prova terminada. Resumo em $RESUMO"
    exit 0
}

# ==================================================================== curva
# Os ensaios da curva propria -- docs/plano-curva.md, secao 6. Valem as regras
# e os limites de todo o resto do roteiro; o que muda e o que cada um pergunta.

# O mapa de E2 (docs/plano-termico.md, secao 6): porcentagem:rpm de cada
# ventoinha, em repouso, medido em 2026-10-10. O E-C2 o usa para achar o
# manual que gira o teto do automatico, e o estagio 4 confere se ele vale sob
# carga.
MAPA_CPU=${ENSAIO_MAPA_CPU:-100:7539 80:6250 60:4911 50:4170 40:3411 30:2582 20:2009}
MAPA_GPU=${ENSAIO_MAPA_GPU:-100:7069 80:5891 60:4647 50:3970 40:3252 30:2469 20:1675}

# A regra da secao 7 do plano. Fixada antes de medir: nao ha variavel que a mova.
REGRA_CPU=5          # % de frequencia, do maximo do firmware contra o automatico
REGRA_GPU=3000       # milesimos de grau da GPU pelo EC, no jogo

# O E-C2, em amostras -- segundos, com o passo padrao.
C2_CARGA=${ENSAIO_C2_CARGA:-180}       # carga de cada estagio, em tempo de relogio
C2_JANELA=${ENSAIO_C2_JANELA:-60}      # o que se mede: o ultimo minuto do estagio
C2_DESCIDA=${ENSAIO_C2_DESCIDA:-120}   # teto da descida entre dois estagios
C2_JOGO=${ENSAIO_C2_JOGO:-180}         # cada trecho da parte com o jogo
C2_P5=${ENSAIO_C2_P5:-92}
C2_TOL=${ENSAIO_C2_TOL:-300}           # o estagio 4 gira o teto do 3 a +- isto
# O teto da CPU em automatico a partir do qual o estagio conta como curva
# alta. Medido (plano, secao 2.1): a baixa para em ~4500 rpm, a alta em ~6550.
C2_LIMIAR_CURVA=${ENSAIO_C2_LIMIAR_CURVA:-5500}
GESTO_PRAZO=${ENSAIO_GESTO_PRAZO:-300}      # amostras esperando um gesto
GESTO_ACOMODA=${ENSAIO_GESTO_ACOMODA:-10}   # amostras para o efeito dele aparecer

# O E-C3, em amostras.
C3_NIVEIS=${ENSAIO_C3_NIVEIS:-30 45 55 65 75 85 92 99 100}   # 100 e o maximo do firmware
C3_SEGURA=${ENSAIO_C3_SEGURA:-15}
C3_RESPOSTA=${ENSAIO_C3_RESPOSTA:-300}   # amostras esperando uma resposta
C3_ESTAB=${ENSAIO_C3_ESTAB:-8}           # parado na base, antes de cada janela de escuta
C3_ESCUTA=${ENSAIO_C3_ESCUTA:-10}        # a janela em que a troca pode vir
C3_TROCA=${ENSAIO_C3_TROCA:-4}           # em que amostra da janela ela vem
C3_FALSO=${ENSAIO_C3_FALSO:-}            # a janela sem troca, de 1 a 4; sorteada se vazio

# O E-C5, em amostras; os prazos do guarda, em segundos.
C5_P=${ENSAIO_C5_P:-95}
# Quais gestos, e se termina pedindo o reinicio. Repetir so uma parte poupa os
# gestos que ja foram medidos. Sem os dois-pontos de proposito: vazio quer
# dizer nenhum gesto, e nao o padrao -- em 2026-10-16 um ENSAIO_C5_GESTOS=""
# rodou os tres.
C5_GESTOS=${ENSAIO_C5_GESTOS-suspensao cabo perfil}
C5_REINICIO=${ENSAIO_C5_REINICIO:-1}
C5_DEPOIS=${ENSAIO_C5_DEPOIS:-30}        # olhando a rotacao depois de cada gesto
C5_FORA=${ENSAIO_C5_FORA:-15}            # na bateria, ou no outro perfil
GUARDA_PRAZO_KILL=${ENSAIO_GUARDA_PRAZO_KILL:-5}   # ate o guarda devolver, depois do kill -9
GUARDA_FOLGA=${ENSAIO_GUARDA_FOLGA:-5}   # alem do WatchdogSec, depois do SIGSTOP
GUARDA_VOLTA=${ENSAIO_GUARDA_VOLTA:-15}  # para o agente voltar depois de morto
ESTADO_EC5=${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-ec5-reinicio.txt

N_GESTO=0
GESTO_HOOK=:          # chamado a cada amostra de um gesto; no E-C5, marca_fora
LIVRE_SEMPRE=         # condicoes que deixam de valer quando a medicao acabou

mediana_num() {   # so os numeros entram; NA se nao houver nenhum
    printf '%s\n' "$@" | grep -E '^-?[0-9]+$' | sort -n \
        | awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)]; else print "NA" }'
}
media_num() {
    printf '%s\n' "$@" | grep -E '^-?[0-9]+$' \
        | awk '{ s += $1; n++ } END { if (n) printf "%d\n", s / n; else print "NA" }'
}
graus() { if eh_num "$1"; then echo $(( $1 / 1000 )); else echo NA; fi; }

pct_do_mapa() {   # $1 = rpm, $2 = mapa -> o manual que gira isso, de 1 a 99
    awk -v r="$1" -v m="$2" 'BEGIN {
        n = split(m, par, " ")
        for (i = 1; i <= n; i++) { split(par[i], x, ":"); p[i] = x[1] + 0; v[i] = x[2] + 0 }
        for (i = 2; i <= n; i++)
            for (j = i; j > 1 && p[j] < p[j - 1]; j--) {
                t = p[j]; p[j] = p[j - 1]; p[j - 1] = t
                t = v[j]; v[j] = v[j - 1]; v[j - 1] = t
            }
        r += 0
        if (r <= v[1]) q = p[1]
        else if (r >= v[n]) q = p[n]
        else for (i = 1; i < n; i++)
            if (r >= v[i] && r < v[i + 1]) {
                q = p[i] + (r - v[i]) * (p[i + 1] - p[i]) / (v[i + 1] - v[i]); break
            }
        q = int(q + 0.5)
        if (q > 99) q = 99      # 100,100 nao e manual: e o maximo do firmware
        if (q < 1) q = 1
        print q
    }'
}

regra_c2() {   # $1..$3 = MHz dos estagios 3, 6 e 7; $4..$6 = GPU pelo EC em j1, j2 e j3; NA onde faltar
    awk -v f3="$1" -v f6="$2" -v f7="$3" -v g1="$4" -v g2="$5" -v g3="$6" \
        -v rc="$REGRA_CPU" -v rg="$REGRA_GPU" '
    function num(x) { return x ~ /^-?[0-9]+$/ }
    BEGIN {
        cpu = "falta"; jogo = "falta"
        if (num(f3) && num(f6) && num(f7) && f3 + f7 > 0) {
            b = (f3 + f7) / 2; ganho = (f6 - b) / b * 100
            d = f3 - f7; if (d < 0) d = -d; ruido = d / b * 100
            cpu = (ganho >= rc && ganho > ruido) ? "R1" : "R0"
            printf "CPU: o maximo do firmware (6) a %d MHz contra %d, a media de 3 e 7: ganho de %.1f%%; ruido (3 contra 7) de %.1f%% -> %s\n", \
                f6, b, ganho, ruido, (cpu == "R1" ? "passa da regra" : "nao passa da regra")
        } else print "CPU: faltam os estagios 3, 6 ou 7"
        if (num(g1) && num(g2) && num(g3)) {
            gb = (g1 + g3) / 2; q = gb - g2
            jogo = (q >= rg) ? "R1" : "R0"
            printf "jogo: GPU pelo EC a %.1f C no maximo do firmware contra %.1f C, a media dos automaticos: %.1f C mais fria -> %s\n", \
                g2 / 1000, gb / 1000, q / 1000, (jogo == "R1" ? "passa da regra" : "nao passa da regra")
        } else print "jogo: faltam os tres trechos com o jogo"
        printf "(a regra, fixada antes de medir: %d%% de frequencia e acima do ruido, ou %d C na GPU)\n", rc, rg / 1000
        if (cpu == "R1" || jogo == "R1") v = "R1 -- a ventoinha acima do teto da curva alta compensa: a forma A se justifica"
        else if (cpu == "R0" && jogo == "R0") v = "R0 -- a ventoinha acima do teto da curva alta nao compensa: a forma A nao se faz"
        else v = "incompleto -- falta uma das partes, e a outra nao passa da regra"
        print "veredito: " v
    }'
}

segundos() {   # um intervalo do systemd -- 3s, 1min 30s, 500ms, 0 -- em segundos inteiros, para cima
    awk -v t="$1" 'BEGIN {
        n = split(t, p, " ")
        for (i = 1; i <= n; i++) {
            v = p[i] + 0
            if (p[i] ~ /us$/) s += v / 1000000
            else if (p[i] ~ /ms$/) s += v / 1000
            else if (p[i] ~ /min$/) s += v * 60
            else if (p[i] ~ /h$/) s += v * 3600
            else if (p[i] ~ /s$/) s += v
        }
        printf "%d\n", (s > int(s)) ? int(s) + 1 : s
    }'
}

# ------------------------------------------------------------------- gestos
# O que muda a maquina de proposito, e e da pessoa: o modo maximo na bandeja,
# o jogo, a tampa, o cabo, o perfil, o reinicio. O roteiro pede numa linha
# GESTO, espera o efeito aparecer no que le e confere. Enquanto espera, a
# condicao que o gesto muda fica fora de verifica() -- o resto continua
# valendo, a cada amostra.

espera_gesto() {   # $1 = o pedido, $2 = condicoes que ele muda, $3 = funcao: veio?, $4 = fase, $5 = 1: sem ele, so volta 1
    local i rc
    N_GESTO=$(( N_GESTO + 1 ))
    echo "GESTO $N_GESTO: $1 Espero ate $(tempo_ms "$GESTO_PRAZO" | awk '{ printf "%d", $1 / 1000 }') s."
    LIVRE=$2
    for ((i = 0; i < GESTO_PRAZO; i++)); do
        sleep "$PASSO"
        amostra "$4"; registra
        "$GESTO_HOOK"
        if "$3"; then LIVRE=; return 0; fi
        verifica; rc=$?
        if [ "$rc" -ne 0 ]; then LIVRE=; termina "$rc"; fi
    done
    LIVRE=
    [ "${5:-0}" = 1 ] && return 1
    MOTIVO="o gesto $N_GESTO nao veio no prazo: $1"
    termina "$COD_CONDICAO"
}

acomoda() {   # $1 = funcao: o efeito apareceu?, $2 = condicoes livres, $3 = fase, $4 = o que dizer se nao
    local i rc
    LIVRE=$2
    for ((i = 0; i <= GESTO_ACOMODA; i++)); do
        if "$1"; then LIVRE=; return 0; fi
        [ "$i" -eq "$GESTO_ACOMODA" ] && break
        sleep "$PASSO"
        amostra "$3"; registra
        "$GESTO_HOOK"
        verifica; rc=$?
        if [ "$rc" -ne 0 ]; then LIVRE=; termina "$rc"; fi
    done
    LIVRE=
    MOTIVO="$4 (lido: modo maximo '$V_MAX', perfil de energia $V_PPD, perfil $V_PERFIL, cabo $V_ACAD)"
    termina "$COD_CONDICAO"
}

assenta_ppd() {   # $1 = fase. Amostra ate o perfil de energia ficar parado por tres amostras
    local i rc igual=0 antes=$V_PPD
    LIVRE=ppd
    for ((i = 0; i < GESTO_ACOMODA && igual < 3; i++)); do
        sleep "$PASSO"
        amostra "$1"; registra
        verifica; rc=$?
        if [ "$rc" -ne 0 ]; then LIVRE=; termina "$rc"; fi
        if [ "$V_PPD" = "$antes" ]; then igual=$(( igual + 1 )); else igual=0; antes=$V_PPD; fi
    done
    LIVRE=
}

maximo_ligado()    { [ "$V_MAX" = true ]; }
maximo_desligado() { [ "$V_MAX" != true ]; }
ppd_performance()  { [ "$V_PPD" = performance ]; }
jogo_aberto()      { [ "$V_JOGO" != 0 ]; }

liga_maximo() {   # $1 = fase. O gesto e seu, na bandeja: a mesma via do uso
    espera_gesto "ligue o modo maximo na bandeja (Desempenho maximo)." "maximo ppd" maximo_ligado "$1"
    MAX0=$V_MAX
    # O modo grava a intencao no config.toml e so depois poe o perfil de
    # energia em performance (src/nexus_sense/maximum.py): conferir os dois.
    acomoda ppd_performance ppd "$1" "o modo maximo ligou, mas o perfil de energia nao foi a performance"
    acomoda perfil_de_volta "" "$1" "o modo maximo ligou, mas o perfil nao e $PERFIL0"
    PPD0=$V_PPD
    echo "  modo maximo ligado; perfil de energia $V_PPD, EPP $V_EPP, perfil $V_PERFIL"
}

desliga_maximo() {   # $1 = fase, $2 = condicoes livres a mais, $3 = 1: sem o gesto, so volta 1
    espera_gesto "desligue o modo maximo na bandeja." "maximo ppd ${2:-}" maximo_desligado "$1" "${3:-0}" \
        || return 1
    MAX0=$V_MAX
    # Desligado, o modo devolve o perfil de energia que guardou ao ligar.
    assenta_ppd "$1"
    PPD0=$V_PPD
    echo "  modo maximo desligado; perfil de energia $V_PPD, EPP $V_EPP"
}

ppd_do_estagio() {   # $1 = o perfil de energia que o estagio pede. So com o modo maximo desligado:
                     # ligado, o agente repoe o performance a cada passada
    if [ "$V_PPD" != "$1" ]; then
        echo "  perfil de energia: $V_PPD -> $1"
        if ! ppd_poe "$1"; then
            MOTIVO="nao consegui por o perfil de energia em $1 (esta em $(ppd_le))"
            termina "$COD_CONDICAO"
        fi
        amostra c2:ppd; registra
    fi
    PPD0=$1
}

# --------------------------------------------------------------------- E-C2

declare -A C2_T1 C2_T2 C2_MHZ C2_THR C2_PAC C2_ECC C2_ECG C2_SEN C2_PPD C2_EPP C2_MAX C2_FAN

estagio_c2() {   # $1 = nome, $2 = descricao, $3 = fan_speed, $4 = amostras de relogio
    local n=$1 v=$3 dur_ms t0ms rc=0 i=0 k a
    local r1=() r2=() hz=() pa=() ec=() eg=() s2=() s3=() s4=() s5=() tm=() th=()
    echo
    echo "ESTAGIO $n -- $2: fan_speed $v, modo maximo ${V_MAX:-?}, perfil de energia $V_PPD"
    if [ "$v" != "$ULTIMO" ] && ! escreve "$v"; then
        MOTIVO="a escrita de $v foi recusada"; termina "$COD_CONDICAO"
    fi
    # Tempo de relogio, como no E3: a carga morre sozinha pelo relogio.
    dur_ms=$(tempo_ms "$4")
    [ "$COM_JOGO" = 1 ] || carga_liga "$4"
    t0ms=$(agora_ms)
    while [ $(( $(agora_ms) - t0ms )) -lt "$dur_ms" ]; do
        sleep "$PASSO"
        i=$(( i + 1 ))
        amostra "c2:$n"; registra
        verifica; rc=$?
        r1+=("$V_RPM1"); r2+=("$V_RPM2"); hz+=("$V_MHZ"); pa+=("$V_PAC")
        ec+=("$V_ECCPU"); eg+=("$V_ECGPU"); s2+=("$V_SEN2"); s3+=("$V_SEN3")
        s4+=("$V_SEN4"); s5+=("$V_SEN5"); tm+=("$(agora_ms)"); th+=("$V_THRMS")
        if [ "$rc" -ne 0 ]; then
            mata_carga
            echo "estagio $n ($2): aborto aos $(( ($(agora_ms) - t0ms) / 1000 )) s: $MOTIVO" >> "$RESUMO"
            termina "$rc"
        fi
        if [ $(( i % E3_ECO )) -eq 0 ]; then
            echo "  +$i: pacote $V_PAC, GPU pelo EC $V_ECGPU, rotacao $V_RPM1 / $V_RPM2, $V_MHZ MHz"
        fi
    done
    mata_carga
    if [ "$i" -lt 1 ]; then MOTIVO="o estagio $n terminou sem amostra"; termina "$COD_CONDICAO"; fi

    # O que conta e o ultimo minuto: o estagio ja assentou.
    k=$i; [ "$k" -gt "$C2_JANELA" ] && k=$C2_JANELA
    a=$(( i - k ))
    C2_T1[$n]=$(mediana_num "${r1[@]:a}"); C2_T2[$n]=$(mediana_num "${r2[@]:a}")
    C2_MHZ[$n]=$(media_num "${hz[@]:a}")
    C2_PAC[$n]=$(mediana_num "${pa[@]:a}"); C2_ECC[$n]=$(mediana_num "${ec[@]:a}")
    C2_ECG[$n]=$(mediana_num "${eg[@]:a}")
    C2_SEN[$n]="$(graus "$(mediana_num "${s2[@]:a}")") $(graus "$(mediana_num "${s3[@]:a}")") $(graus "$(mediana_num "${s4[@]:a}")") $(graus "$(mediana_num "${s5[@]:a}")")"
    C2_THR[$n]=NA
    if [ "$k" -gt 1 ] && eh_num "${th[a]}" && eh_num "${th[i - 1]}"; then
        C2_THR[$n]=$(awk -v t="$(( th[i - 1] - th[a] ))" -v s="$(( tm[i - 1] - tm[a] ))" \
            'BEGIN { if (s > 0) printf "%.1f", t / s * 100; else print "NA" }')
    fi
    C2_PPD[$n]=$V_PPD; C2_EPP[$n]=$V_EPP; C2_MAX[$n]=${V_MAX:-?}; C2_FAN[$n]=$v
    {
        echo "estagio $n ($2): fan_speed $v, modo maximo ${C2_MAX[$n]}, perfil de energia ${C2_PPD[$n]}, EPP ${C2_EPP[$n]}"
        echo "    ultimo minuto: rotacao ${C2_T1[$n]} / ${C2_T2[$n]} rpm; ${C2_MHZ[$n]} MHz; throttle ${C2_THR[$n]}% do tempo"
        echo "    pacote $(graus "${C2_PAC[$n]}") C, CPU pelo EC $(graus "${C2_ECC[$n]}"), GPU pelo EC $(graus "${C2_ECG[$n]}"), SEN2-5 ${C2_SEN[$n]}"
    } | tee -a "$RESUMO"
    if [ "$v" != "0,0" ] && ! escreve "0,0"; then
        MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"
    fi
}

descida_c2() {   # $1 = estagio. Carga fora, automatico: ate o pacote voltar a 60 C, ou o teto
    local i rc frias=0 t0=$EPOCHSECONDS
    for ((i = 0; i < C2_DESCIDA; i++)); do
        sleep "$PASSO"
        amostra "c2:$1:descida"; registra
        verifica; rc=$?
        N_PAC=0
        # Uma zona de placa ainda subindo depois da carga nao e novidade: o
        # estagio acabou. Pessoa, bateria e prazo continuam valendo.
        [ "$rc" -eq "$COD_CONDICAO" ] && termina "$rc"
        if acima "$V_PAC" "$PARTIDA_PACOTE_E3"; then frias=0; else frias=$(( frias + 1 )); fi
        [ "$frias" -ge 3 ] && break
    done
    echo "  descida: $(( EPOCHSECONDS - t0 )) s; pacote $V_PAC, rotacao $V_RPM1 / $V_RPM2 rpm"
}

tabela_c2() {   # $@ = estagios
    local n
    {
        echo
        printf '%-4s %-9s %-6s %-12s %-20s %-11s %-5s %-5s %-4s %-4s %-4s %s\n' \
            est fan_speed maximo ppd epp "rpm cpu/gpu" MHz thr% pac ecC ecG "SEN2-5"
        for n in "$@"; do
            [ -n "${C2_T1[$n]:-}" ] || continue
            printf '%-4s %-9s %-6s %-12s %-20s %-11s %-5s %-5s %-4s %-4s %-4s %s\n' \
                "$n" "${C2_FAN[$n]}" "${C2_MAX[$n]}" "${C2_PPD[$n]}" "${C2_EPP[$n]}" \
                "${C2_T1[$n]}/${C2_T2[$n]}" "${C2_MHZ[$n]}" "${C2_THR[$n]}" \
                "$(graus "${C2_PAC[$n]}")" "$(graus "${C2_ECC[$n]}")" "$(graus "${C2_ECG[$n]}")" "${C2_SEN[$n]}"
        done
    } | tee -a "$RESUMO"
}

curvas_c2() {   # C1: em que curva cada estagio em automatico ficou
    local n lista="" fechou=0
    local -A cv
    for n in 1 2 3 7 8 9 10; do
        eh_num "${C2_T1[$n]:-}" || continue
        if [ "${C2_T1[$n]}" -ge "$C2_LIMIAR_CURVA" ]; then cv[$n]=alta; else cv[$n]=baixa; fi
        lista="$lista $n:${cv[$n]}"
    done
    {
        echo
        echo "C1 -- a curva de cada estagio em automatico (teto da CPU contra $C2_LIMIAR_CURVA rpm):$lista"
        if [ "${cv[1]:-}${cv[2]:-}${cv[9]:-}${cv[10]:-}" = baixabaixabaixabaixa ] \
           && [ "${cv[3]:-}${cv[7]:-}" = altaalta ]; then
            echo "    1, 2, 9 e 10 na baixa, 3 e 7 na alta: quem escolhe e o modo maximo, por algo alem do perfil de energia"
            fechou=1
        fi
        if [ "${cv[8]:-}" = alta ]; then
            echo "    8 na alta: a curva alta fica presa depois de o modo desligar"; fechou=1
        fi
        if [ "${cv[10]:-}" = alta ] && [ "${cv[1]:-}" = baixa ]; then
            echo "    10 na alta e 1 na baixa: ela fica presa ate um reinicio"; fechou=1
        fi
        if [ "${cv[3]:-}" != "${cv[7]:-}" ]; then
            echo "    3 e 7, o mesmo estado, em curvas diferentes: a medida nao separa as curvas"; fechou=0
        fi
        [ "$fechou" = 1 ] || echo "    nada disso fecha: o DSDT (E1 do plano termico) volta a mesa"
        echo "    ruido da medida (3 contra 7): teto ${C2_T1[3]:-?} / ${C2_T1[7]:-?} rpm, ${C2_MHZ[3]:-?} / ${C2_MHZ[7]:-?} MHz"
    } | tee -a "$RESUMO"
}

parte_cpu() {   # os dez estagios, uma alavanca de cada vez
    local p1 p2 a b d1 d2
    ppd_do_estagio performance
    estagio_c2 1 "automatico, modo maximo desligado, perfil de energia performance" 0,0 "$C2_CARGA"
    descida_c2 1
    ppd_do_estagio balanced
    estagio_c2 2 "automatico, perfil de energia balanced" 0,0 "$C2_CARGA"
    descida_c2 2
    # O modo maximo e pedido com o perfil de energia ainda em balanced: quem o
    # poe em performance e o proprio modo, e esse e o efeito que se confere.
    liga_maximo c2:gesto
    estagio_c2 3 "automatico, modo maximo ligado" 0,0 "$C2_CARGA"
    descida_c2 3

    # O controle: o manual que o mapa de E2 diz girar o teto do estagio 3.
    if ! eh_num "${C2_T1[3]}" || ! eh_num "${C2_T2[3]}"; then
        MOTIVO="o estagio 3 terminou sem rotacao"; termina "$COD_CONDICAO"
    fi
    p1=$(pct_do_mapa "${C2_T1[3]}" "$MAPA_CPU"); p2=$(pct_do_mapa "${C2_T2[3]}" "$MAPA_GPU")
    echo "  o teto do estagio 3, ${C2_T1[3]} / ${C2_T2[3]} rpm, e pelo mapa de E2 o manual $p1,$p2" | tee -a "$RESUMO"
    estagio_c2 4 "manual que gira o teto do estagio 3 (o controle)" "$p1,$p2" "$C2_CARGA"
    if ! eh_num "${C2_T1[4]}" || ! eh_num "${C2_T2[4]}"; then
        MOTIVO="o estagio 4 terminou sem rotacao"; termina "$COD_CONDICAO"
    fi
    a=${C2_T1[4]}; b=${C2_T1[3]}; d1=$(( a - b ))
    a=${C2_T2[4]}; b=${C2_T2[3]}; d2=$(( a - b ))
    if [ "${d1#-}" -gt "$C2_TOL" ] || [ "${d2#-}" -gt "$C2_TOL" ]; then
        MOTIVO="o estagio 4 girou ${C2_T1[4]} / ${C2_T2[4]} rpm e o teto do 3 era ${C2_T1[3]} / ${C2_T2[3]}: mais de $C2_TOL rpm de diferenca. O mapa de E2 nao vale sob carga"
        echo "controle: FALHOU -- $MOTIVO" >> "$RESUMO"
        termina "$COD_CONTROLE"
    fi
    echo "controle: o estagio 4 girou o teto do 3 a menos de $C2_TOL rpm ($d1 / $d2)" | tee -a "$RESUMO"
    descida_c2 4
    estagio_c2 5 "manual a $C2_P5%" "$C2_P5,$C2_P5" "$C2_CARGA"
    descida_c2 5
    estagio_c2 6 "maximo do firmware" 100,100 "$C2_CARGA"
    descida_c2 6
    estagio_c2 7 "automatico, modo maximo ligado, de novo" 0,0 "$C2_CARGA"
    descida_c2 7
    # Desligado, o modo devolve o balanced que guardou; o estagio 8 e em
    # performance, como o 1, e quem o poe e o roteiro.
    desliga_maximo c2:gesto
    ppd_do_estagio performance
    estagio_c2 8 "automatico logo depois de desligar o modo maximo" 0,0 "$C2_CARGA"
    descida_c2 8
    ppd_do_estagio balanced
    estagio_c2 9 "automatico, perfil de energia balanced, depois do modo maximo" 0,0 "$C2_CARGA"
    descida_c2 9
    ppd_do_estagio performance
    estagio_c2 10 "automatico, perfil de energia performance, sem o modo maximo" 0,0 "$C2_CARGA"
    descida_c2 10
    tabela_c2 1 2 3 4 5 6 7 8 9 10
    curvas_c2
}

parte_jogo() {   # tres trechos com o jogo, o modo maximo ligado
    echo
    echo "A PARTE COM O JOGO -- modo maximo ligado, o jogo de sempre numa cena parada"
    # Ate o primeiro trecho, o jogo pode ja estar aberto, ou abrir a qualquer hora.
    LIVRE_SEMPRE=jogo
    [ "$V_MAX" = true ] || liga_maximo c2:jogo:gesto
    if [ "$V_JOGO" = 0 ]; then
        espera_gesto "abra o jogo de sempre e deixe-o numa cena parada." jogo jogo_aberto c2:jogo:gesto
    fi
    COM_JOGO=1; LIVRE_SEMPRE=
    estagio_c2 j1 "com jogo, automatico" 0,0 "$C2_JOGO"
    estagio_c2 j2 "com jogo, maximo do firmware" 100,100 "$C2_JOGO"
    estagio_c2 j3 "com jogo, automatico de novo" 0,0 "$C2_JOGO"
    tabela_c2 j1 j2 j3
}

modo_ec2() {   # $1 = saida, $2 = 1: so a parte com o jogo
    local i pacs=() med nao=0 so_jogo=${2:-0} nome=ec2
    REPOUSO=0
    [ "$so_jogo" = 1 ] && nome=ec2-jogo
    if [ -z "${ENSAIO_PRAZO:-}" ]; then
        if [ "$so_jogo" = 1 ]; then PRAZO=2400; else PRAZO=6000; fi
    fi
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-$nome-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    RESUMO="${SAIDA%.tsv}.resumo.txt"

    if [ "$so_jogo" = 1 ]; then
        echo "E-C2, SO A PARTE COM O JOGO -- o modo maximo ligado e o jogo sao gestos seus."
    else
        echo "E-C2 -- qual curva, e o que a rotacao acima do teto compra. ESQUENTA A MAQUINA."
    fi
    echo "saida: $SAIDA"
    pausa_curva
    # Cinco leituras do pacote, e vale a mediana, como no E3.
    for ((i = 0; i < 5; i++)); do
        amostra partida; registra
        eh_num "$V_PAC" && pacs+=("$V_PAC")
        sleep "$PASSO"
    done
    exige_alvos || exit "$COD_ALVO"
    if [ "$V_PPD" = NA ]; then
        echo "ERRO alvo ausente: perfil de energia (o power-profiles-daemon nao respondeu)"
        exit "$COD_ALVO"
    fi
    med=$(mediana_num "${pacs[@]}")
    mostra_condicao
    recusa() { echo "  RECUSA: $1"; nao=1; }
    if [ "$so_jogo" = 1 ]; then
        [ "$V_FAN" = "0,0" ] || recusa "fan_speed e '$V_FAN'; o ensaio so comeca em 0,0 (automatico)"
        [ "$V_ACAD" = 1 ] || recusa "fora da tomada"
        eh_num "$V_PCT" && [ "$V_PCT" -ge "$PARTIDA_CARGA" ] \
            || recusa "bateria em $V_PCT%, abaixo de $PARTIDA_CARGA%"
    else
        V_PAC=$med
        pode_comecar || nao=1
        frio_o_bastante "$med" \
            || recusa "a maquina nao esta fria o bastante: pacote $med (pede abaixo de $PARTIDA_PACOTE_E3) e cada SEN* a $PARTIDA_FOLGA_SEN do limite"
    fi
    [ "$V_PERFIL" = balanced-performance ] \
        || recusa "o perfil e $V_PERFIL; o ensaio e em balanced-performance, o que o modo maximo usa"
    [ "$nao" = 0 ] || exit "$COD_RECUSA"
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
    # O que volta no fim: o perfil de energia pelo roteiro, o modo maximo por
    # voce. Se o roteiro morrer, o trap e o vigia devolvem o perfil de energia.
    PPD_INICIAL=$V_PPD; MAX_INICIAL=$V_MAX
    echo "partida: perfil $PERFIL0, modo maximo ${MAX0:-?}, perfil de energia $PPD0, EPP $V_EPP; carga: $CARGA_N processos" > "$RESUMO"

    prepara

    [ "$so_jogo" = 1 ] || parte_cpu
    parte_jogo

    # A medicao acabou: o jogo pode fechar, e o modo maximo volta ao que era.
    LIVRE_SEMPRE=jogo
    echo
    regra_c2 "${C2_MHZ[3]:-NA}" "${C2_MHZ[6]:-NA}" "${C2_MHZ[7]:-NA}" \
        "${C2_ECG[j1]:-NA}" "${C2_ECG[j2]:-NA}" "${C2_ECG[j3]:-NA}" | tee -a "$RESUMO"
    [ "$so_jogo" = 1 ] && echo "(so a parte com o jogo: a de CPU esta no resumo da rodada inteira)" | tee -a "$RESUMO"
    if [ "$MAX_INICIAL" != true ] && [ "$V_MAX" = true ]; then
        echo
        desliga_maximo c2:fim "" 1 \
            || echo "o modo maximo seguiu ligado; desligue-o na bandeja quando quiser."
    fi
    echo "E-C2 terminou. Resumo em $RESUMO"
    exit 0
}

# --------------------------------------------------------------------- E-C3
# O ouvido. As respostas vem pela entrada padrao: o terminal de quem roda.

pergunta() {   # $1 = a pergunta, $2 = respostas aceitas, $3 = fase -> RESPOSTA
    local i r st rc
    echo "PERGUNTA: $1 [${2// //}]"
    for ((i = 0; i < C3_RESPOSTA; i++)); do
        r=
        read -r -t "$PASSO" r; st=$?
        if [ "$st" -le 128 ]; then
            # Fim da entrada sem resposta: ninguem vai responder.
            if [ "$st" -ne 0 ] && [ -z "$r" ]; then
                MOTIVO="a entrada acabou sem resposta: o E-C3 precisa de alguem respondendo no terminal"
                termina "$COD_CONDICAO"
            fi
            r=$(printf '%s' "$r" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [ -n "$r" ]; then
                case " $2 " in
                    *" $r "*) RESPOSTA=$r; echo "  resposta: $r"; return 0 ;;
                esac
            fi
            echo "  responda com uma destas: $2"
        fi
        # Esperando a resposta, a ventoinha segue onde esta: os limites tambem.
        amostra "$3"; registra
        verifica; rc=$?
        [ "$rc" -ne 0 ] && termina "$rc"
    done
    MOTIVO="sem resposta em $C3_RESPOSTA amostras"
    termina "$COD_CONDICAO"
}

modo_ec3() {
    local p v k nome l_trab="" l_jogo="" corrido_t=1 corrido_j=1 primeiro="" base falso t j b troca
    local reais=() disse_falso=""
    local -A R1 R2
    REPOUSO=1
    [ -n "${ENSAIO_PRAZO:-}" ] || PRAZO=1800
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-ec3-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    RESUMO="${SAIDA%.tsv}.resumo.txt"

    echo "E-C3 -- o ouvido. A ventoinha passa por varias rotacoes, e voce diz o que aceita."
    echo "saida: $SAIDA"
    pausa_curva
    amostra partida; registra
    exige_alvos || exit "$COD_ALVO"
    mostra_condicao
    falso=${C3_FALSO:-$(( RANDOM % 4 + 1 ))}
    case "$falso" in
        1|2|3|4) ;;
        *) echo "  RECUSA: ENSAIO_C3_FALSO e '$falso'; vai de 1 a 4"; exit "$COD_RECUSA" ;;
    esac
    # O modo maximo nao muda o manual: o E-C3 aceita os dois, e ele fica como esta.
    pode_comecar 1 || exit "$COD_RECUSA"
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
    echo "partida: perfil $PERFIL0, modo maximo ${MAX0:-?}, perfil de energia $PPD0" > "$RESUMO"

    prepara
    coleta auto-antes 0 "$LEITURAS" || termina $?
    REF1=$(mediana_num "${C1[@]}"); REF2=$(mediana_num "${C2[@]}")
    echo "  automatico, na partida: $REF1 / $REF2 rpm" | tee -a "$RESUMO"

    echo
    echo "A VARREDURA -- cada rotacao fica $(tempo_ms "$C3_SEGURA" | awk '{ printf "%d", $1 / 1000 }') s; depois, uma pergunta:"
    echo "  t = aceito trabalhando (e jogando)    j = so jogando    n = nem jogando"
    for p in $C3_NIVEIS; do
        [ -n "$primeiro" ] || primeiro=$p
        if [ "$p" = 100 ]; then v="100,100"; nome="o maximo do firmware"; else v="$p,$p"; nome="$p%"; fi
        if ! escreve "$v"; then MOTIVO="a escrita de $v foi recusada"; termina "$COD_CONDICAO"; fi
        coleta "c3:$p" 0 "$C3_SEGURA" || termina $?
        # A rotacao assenta em um ou dois segundos (E2): vale a segunda metade.
        k=$(( ${#C1[@]} / 2 ))
        R1[$p]=$(mediana_num "${C1[@]:k}"); R2[$p]=$(mediana_num "${C2[@]:k}")
        pergunta "a $nome (${R1[$p]} / ${R2[$p]} rpm), voce aceita?" "t j n" "c3:$p:resposta"
        echo "  $nome: ${R1[$p]} / ${R2[$p]} rpm -> $RESPOSTA" >> "$RESUMO"
        # O limite e o fim da sequencia aceita, de baixo para cima.
        if [ "$corrido_t" = 1 ]; then
            if [ "$RESPOSTA" = t ]; then l_trab=$p; else corrido_t=0; fi
        fi
        if [ "$corrido_j" = 1 ]; then
            case "$RESPOSTA" in t|j) l_jogo=$p ;; *) corrido_j=0 ;; esac
        fi
    done
    {
        if [ -n "$l_trab" ]; then
            echo "aceita trabalhando ate: $l_trab% (${R1[$l_trab]} / ${R2[$l_trab]} rpm)"
        else
            echo "aceita trabalhando ate: abaixo de $primeiro%"
        fi
        if [ -n "$l_jogo" ]; then
            echo "aceita jogando ate: $l_jogo% (${R1[$l_jogo]} / ${R2[$l_jogo]} rpm)"
        else
            echo "aceita jogando ate: abaixo de $primeiro%"
        fi
    } | tee -a "$RESUMO"

    # Os degraus, em torno do limite de trabalho: tres sobem 5%, e um --
    # o controle -- nao muda nada. Sem ele, "ouvi" nao se separa de "esperava ouvir".
    base=${l_trab:-$primeiro}
    [ "$base" -gt 94 ] && base=94
    for k in 10 5 0; do
        b=$(( base - k )); [ "$b" -lt 20 ] && b=20
        reais+=("$b")
    done
    echo
    echo "OS DEGRAUS -- quatro janelas de escuta. Em tres a ventoinha sobe 5%; em uma, nada muda."
    j=0
    for ((t = 1; t <= 4; t++)); do
        if [ "$t" = "$falso" ]; then b=${reais[1]}; troca=0; else b=${reais[j]}; j=$(( j + 1 )); troca=1; fi
        if ! escreve "$b,$b"; then MOTIVO="a escrita de $b,$b foi recusada"; termina "$COD_CONDICAO"; fi
        coleta "c3:degrau$t:base" 0 "$C3_ESTAB" || termina $?
        echo "ESCUTE ($t de 4): nos proximos $(tempo_ms "$C3_ESCUTA" | awk '{ printf "%d", $1 / 1000 }') s a ventoinha pode trocar de rotacao, ou nao."
        for ((k = 1; k <= C3_ESCUTA; k++)); do
            sleep "$PASSO"
            if [ "$k" = "$C3_TROCA" ] && [ "$troca" = 1 ] && ! escreve "$(( b + 5 )),$(( b + 5 ))"; then
                MOTIVO="a escrita de $(( b + 5 )),$(( b + 5 )) foi recusada"; termina "$COD_CONDICAO"
            fi
            amostra "c3:degrau$t:escuta"; registra
            verifica || termina $?
        done
        pergunta "ouviu uma troca?" "s n" "c3:degrau$t:resposta"
        if [ "$troca" = 1 ]; then
            echo "degrau $t: de $b% para $(( b + 5 ))% -> ouviu: $RESPOSTA" | tee -a "$RESUMO"
        else
            disse_falso=$RESPOSTA
            echo "degrau $t: sem troca, parado em $b% (o controle) -> ouviu: $RESPOSTA" | tee -a "$RESUMO"
        fi
    done
    [ "$disse_falso" = s ] \
        && echo "    o controle ouviu uma troca que nao houve: os 'ouvi' dos outros degraus valem menos" | tee -a "$RESUMO"

    if ! escreve "0,0"; then MOTIVO="a escrita de 0,0 foi recusada"; termina "$COD_CONDICAO"; fi
    coleta auto-depois 0 "$LEITURAS" || termina $?
    echo "E-C3 terminou. Resumo em $RESUMO"
    exit 0
}

# --------------------------------------------------------------------- E-C5
# O que larga o manual. A ventoinha fica a 95%, bem acima de qualquer
# automatico em repouso: uma falha e barulho, e "largou" tem sentido conhecido.

reinicia_obs() { OBS_N=0; OBS_FORA=0; OBS_ULT=0; OBS_MIN1=; OBS_MIN2=; OBS_PERFIS=; }

marca_fora() {   # a ultima amostra esta fora do manual? Acumula para relata()
    local d1 d2 f=0
    eh_num "$V_RPM1" && eh_num "$V_RPM2" || return 0
    d1=$(( V_RPM1 - C5_REF1 )); d2=$(( V_RPM2 - C5_REF2 ))
    if [ "${d1#-}" -ge "$QUEDA_RPM" ] || [ "${d2#-}" -ge "$QUEDA_RPM" ]; then f=1; fi
    OBS_N=$(( OBS_N + 1 )); OBS_FORA=$(( OBS_FORA + f )); OBS_ULT=$f
    if [ -z "$OBS_MIN1" ] || [ "$V_RPM1" -lt "$OBS_MIN1" ]; then OBS_MIN1=$V_RPM1; fi
    if [ -z "$OBS_MIN2" ] || [ "$V_RPM2" -lt "$OBS_MIN2" ]; then OBS_MIN2=$V_RPM2; fi
    case " $OBS_PERFIS " in *" $V_PERFIL "*) ;; *) OBS_PERFIS="${OBS_PERFIS:+$OBS_PERFIS }$V_PERFIL" ;; esac
    return 0
}

observa() {   # $1 = fase, $2 = amostras, $3 = condicoes livres
    local i rc
    LIVRE=${3:-}
    for ((i = 0; i < $2; i++)); do
        sleep "$PASSO"
        amostra "$1"; registra; marca_fora
        verifica; rc=$?
        if [ "$rc" -ne 0 ]; then LIVRE=; termina "$rc"; fi
    done
    LIVRE=
}

reassume_manual() {   # $1 = fase. Reescreve o manual e confere que a rotacao voltou a ele
    # Um gesto pode ter feito o firmware largar o manual com fan_speed ainda
    # dizendo o valor -- a suspensao faz isso (2026-10-16). Sem reescrever, o
    # gesto seguinte partiria do automatico e mediria nada.
    local v="$C5_P,$C5_P" i rc d1 d2
    if ! escreve "$v"; then MOTIVO="a escrita de $v foi recusada"; termina "$COD_CONDICAO"; fi
    for ((i = 0; i < ASSENTA + LEITURAS + 10; i++)); do
        sleep "$PASSO"
        amostra "$1"; registra
        verifica; rc=$?
        [ "$rc" -ne 0 ] && termina "$rc"
        eh_num "$V_RPM1" && eh_num "$V_RPM2" || continue
        d1=$(( V_RPM1 - C5_REF1 )); d2=$(( V_RPM2 - C5_REF2 ))
        [ "${d1#-}" -lt "$QUEDA_RPM" ] && [ "${d2#-}" -lt "$QUEDA_RPM" ] && return 0
    done
    echo "$1: o manual reescrito nao pegou -- a rotacao ficou em $V_RPM1 / $V_RPM2 rpm (no manual: $C5_REF1 / $C5_REF2)" \
        | tee -a "$RESUMO"
    MOTIVO="o manual reescrito nao pegou"
    termina "$COD_CONDICAO"
}

quer_gesto() { case " $C5_GESTOS " in *" $1 "*) return 0 ;; esac; return 1; }

relata() {   # $1 = o gesto
    local r
    if [ "$OBS_FORA" = 0 ]; then r="manteve o manual"
    elif [ "$OBS_ULT" = 1 ]; then r="LARGOU o manual e nao voltou a ele"
    else r="LARGOU o manual e voltou a ele"; fi
    echo "$1: $r -- $OBS_FORA de $OBS_N amostras fora; rotacao minima ${OBS_MIN1:-?} / ${OBS_MIN2:-?} rpm (no manual: $C5_REF1 / $C5_REF2); fan_speed $V_FAN" \
        | tee -a "$RESUMO"
}

suspendeu()       { local s; s=$(le "$SUSPENSOES"); eh_num "$s" && [ "$s" -gt "$C5_SUSP0" ]; }
cabo_fora()       { [ "$V_ACAD" = 0 ]; }
cabo_dentro()     { [ "$V_ACAD" = 1 ]; }
perfil_trocado()  { [ "$V_PERFIL" != "$PERFIL0" ]; }
perfil_de_volta() { [ "$V_PERFIL" = "$PERFIL0" ]; }

unit_prop() { [ -n "$SYSTEMCTL" ] || return 1; "$SYSTEMCTL" --user show -p "$1" --value "$UNIT_AGENTE" 2>/dev/null; }

espera_guarda() {   # $1 = segundos, $2 = fase. 0 com GUARDA_MS se fan_speed virou 0,0 por outra mao
    local t0ms lim_ms fatia i rc
    t0ms=$(agora_ms); lim_ms=$(( $1 * 1000 ))
    fatia=$(awk -v p="$PASSO" 'BEGIN { print p / 10 }')
    ACEITA_FAN="0,0"
    while [ $(( $(agora_ms) - t0ms )) -lt "$lim_ms" ]; do
        # Entre duas amostras, so fan_speed: e ele que da o instante.
        for ((i = 0; i < 10; i++)); do
            if [ "$(le "$FAN")" = "0,0" ]; then
                GUARDA_MS=$(( $(agora_ms) - t0ms ))
                ACEITA_FAN=; ULTIMO="0,0"
                amostra "$2"; registra
                return 0
            fi
            sleep "$fatia"
        done
        amostra "$2"; registra
        verifica; rc=$?
        if [ "$rc" -ne 0 ]; then ACEITA_FAN=; termina "$rc"; fi
    done
    ACEITA_FAN=
    return 1
}

volta_do_agente() {   # $1 = pid antigo -> NOVO_PID, se a unit o subiu de novo
    local i p
    NOVO_PID=
    for ((i = 0; i < GUARDA_VOLTA * 10; i++)); do
        p=$(unit_prop MainPID)
        if eh_num "$p" && [ "$p" -gt 0 ] && [ "$p" != "$1" ]; then NOVO_PID=$p; return 0; fi
        sleep 0.1
    done
    return 1
}

# O guarda so devolve o manual que o PROPRIO agente escreveu: o agente o
# registra em $RUNTIME_DIRECTORY/ventoinha antes de escrever, e o
# ExecStopPost confere fan_speed contra o registro. O exercicio escreve o
# manual pelo agente, e por isso registra por ele: o mesmo arquivo, no
# RuntimeDirectory da unit. Um manual da janela, sem registro, o guarda deixa.
registra_pelo_agente() {   # $1 = o manual que vai ser escrito. 1 se a pasta nao existe
    local p="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$RUNTIME_AGENTE"
    [ -d "$p" ] || return 1
    printf '%s\n%s\n' "$ULTIMO" "$1" > "$p/ventoinha.novo" && mv "$p/ventoinha.novo" "$p/ventoinha"
}

exercicio_guarda() {   # 0 passou, 1 falhou, 2 nao rodou inteiro: a unit nao tem o guarda
    local pid sp wd rd seg v="$C5_P,$C5_P" falhou=0 parcial=0
    echo
    echo "O GUARDA -- o agente morre, e depois trava, com a ventoinha em $v"
    if [ -z "$SYSTEMCTL" ]; then
        echo "guarda: nao rodou -- sem um systemctl dado de proposito, a arvore de mentira nao fala com a unit" | tee -a "$RESUMO"
        return 2
    fi
    pid=$(unit_prop MainPID); sp=$(unit_prop ExecStopPost); wd=$(unit_prop WatchdogUSec)
    rd=$(unit_prop RuntimeDirectory)
    seg=$(segundos "${wd:-0}")
    echo "  $UNIT_AGENTE: MainPID ${pid:-?}, ExecStopPost '$sp', WatchdogUSec ${wd:-?}, RuntimeDirectory '$rd'"
    if ! eh_num "$pid" || [ "$pid" -le 0 ]; then
        echo "guarda: nao rodou -- o agente nao esta no ar" | tee -a "$RESUMO"
        return 2
    fi
    if [ -z "$sp" ]; then
        echo "guarda: nao rodou -- a unit nao tem ExecStopPost: o guarda da secao 8 do plano ainda nao existe" | tee -a "$RESUMO"
        return 2
    fi
    if [ "$rd" != "$RUNTIME_AGENTE" ]; then
        echo "guarda: nao rodou -- a unit nao tem RuntimeDirectory=$RUNTIME_AGENTE, onde o agente registra o que escreve" | tee -a "$RESUMO"
        return 2
    fi

    # ---- kill -9: o ExecStopPost tem de devolver
    if ! registra_pelo_agente "$v"; then
        echo "guarda: nao rodou -- a pasta do agente em \$XDG_RUNTIME_DIR/$RUNTIME_AGENTE nao existe" | tee -a "$RESUMO"
        return 2
    fi
    reassume_manual c5:guarda:antes
    echo "  kill -9 no agente (pid $pid)"
    kill -KILL "$pid" 2>/dev/null
    if espera_guarda "$GUARDA_PRAZO_KILL" c5:guarda:kill; then
        echo "  fan_speed de volta a 0,0 em $GUARDA_MS ms"
        # fan_speed e a memoria do driver: quem diz que o EC largou e a rotacao.
        if rotacao_largou 30 "$C5_REF1" "$C5_REF2" "$QUEDA_RPM" queda; then
            echo "guarda, kill -9: PASSOU -- 0,0 em $GUARDA_MS ms, e a rotacao saiu do manual" | tee -a "$RESUMO"
        else
            falhou=1
            echo "guarda, kill -9: FALHOU -- fan_speed em 0,0, mas a rotacao nao saiu do manual" | tee -a "$RESUMO"
        fi
    else
        falhou=1
        echo "guarda, kill -9: FALHOU -- $GUARDA_PRAZO_KILL s depois, fan_speed ainda e '$(le "$FAN")'" | tee -a "$RESUMO"
    fi
    if volta_do_agente "$pid"; then
        echo "  o agente voltou: pid $NOVO_PID" | tee -a "$RESUMO"
    else
        echo "  o agente NAO voltou em $GUARDA_VOLTA s" | tee -a "$RESUMO"
    fi

    # ---- SIGSTOP: travado, mas vivo; o WatchdogSec tem de pegar
    if [ "$seg" -le 0 ]; then
        echo "guarda, SIGSTOP: nao rodou -- a unit nao tem WatchdogSec" | tee -a "$RESUMO"
        parcial=1
    elif [ -z "$NOVO_PID" ]; then
        echo "guarda, SIGSTOP: nao rodou -- sem agente no ar" | tee -a "$RESUMO"
        falhou=1
    elif ! registra_pelo_agente "$v"; then
        echo "guarda, SIGSTOP: nao rodou -- o agente voltou sem a pasta $RUNTIME_AGENTE" | tee -a "$RESUMO"
        falhou=1
    else
        reassume_manual c5:guarda:antes
        pid=$NOVO_PID
        # Antes do sinal: se o roteiro morrer aqui, o trap e o vigia o soltam.
        printf '%s\n' "$pid" > "$RUN/agente_parado"; AGENTE_PARADO=$pid
        echo "  SIGSTOP no agente (pid $pid); WatchdogSec de $seg s"
        kill -STOP "$pid" 2>/dev/null
        if espera_guarda $(( seg + GUARDA_FOLGA )) c5:guarda:stop; then
            echo "  fan_speed de volta a 0,0 em $GUARDA_MS ms"
            if rotacao_largou 30 "$C5_REF1" "$C5_REF2" "$QUEDA_RPM" queda; then
                echo "guarda, SIGSTOP: PASSOU -- 0,0 em $GUARDA_MS ms, e a rotacao saiu do manual" | tee -a "$RESUMO"
            else
                falhou=1
                echo "guarda, SIGSTOP: FALHOU -- fan_speed em 0,0, mas a rotacao nao saiu do manual" | tee -a "$RESUMO"
            fi
        else
            falhou=1
            echo "guarda, SIGSTOP: FALHOU -- $(( seg + GUARDA_FOLGA )) s depois, fan_speed ainda e '$(le "$FAN")'" | tee -a "$RESUMO"
        fi
        solta_agente
        rm -f "$RUN/agente_parado"
        volta_do_agente "$pid" && echo "  o agente voltou: pid $NOVO_PID" | tee -a "$RESUMO"
    fi
    [ "$falhou" = 1 ] && return 1
    [ "$parcial" = 1 ] && return 2
    return 0
}

reinicio_ec5() {   # $1 = como foi o guarda. Deixa o manual DE PROPOSITO e sai; quem le e o ec5-volta
    local v="$C5_P,$C5_P"
    echo
    echo "O REINICIO -- o que volta na partida, antes do login"
    # O manual vai registrado como do agente, como o da curva: no desligamento
    # o guarda tenta devolver o 0,0, e o driver grava o estado no rmmod. A unit
    # do driver nao tem ordem contra a sessao (plano, secao 8): quem chega
    # primeiro diz o que volta na partida. 0,0 de volta, o guarda chegou antes;
    # o manual de volta, o driver gravou antes.
    registra_pelo_agente "$v" || echo "  (sem a pasta do agente: o guarda nao vai reconhecer este manual)"
    reassume_manual c5:reinicio:antes
    mkdir -p "$(dirname "$ESTADO_EC5")" || exit 1
    {
        echo "valor=$v"; echo "rpm1=$C5_REF1"; echo "rpm2=$C5_REF2"
        echo "boot=$(le "$BOOT_ID")"; echo "saida=$SAIDA"; echo "resumo=$RESUMO"; echo "epoch=$EPOCHSECONDS"
        echo "curva=$CURVA_INICIAL"
    } > "$ESTADO_EC5"
    # Nem o trap nem o vigia devolvem: o manual atravessa o reinicio de
    # proposito. A 95% e barulho, nao calor. A curva pausada tambem: com ela
    # valendo, o agente da partida tomaria o 0,0, e o ec5-volta nao veria o
    # que o desligamento deixou.
    DEVOLVIDO=1; : > "$RUN/devolvido"
    CURVA_INICIAL=; rm -f "$RUN/curva_inicial"
    echo "reinicio: pedido com fan_speed em $v; o resultado vem do ec5-volta" >> "$RESUMO"
    N_GESTO=$(( N_GESTO + 1 ))
    echo "GESTO $N_GESTO: reinicie a maquina agora. A ventoinha fica a $C5_P% ate la: barulho, nao calor."
    echo "  depois do login, rode:  $EU ec5-volta"
    echo "  se desistir do reinicio, rode o mesmo comando: ele devolve a ventoinha."
    case "$1" in
        1) exit "$COD_EXERCICIO" ;;
        2) exit "$COD_SEM_GUARDA" ;;
    esac
    exit 0
}

modo_ec5() {
    local rcg v="$C5_P,$C5_P" falta=0 par
    REPOUSO=1
    [ -n "${ENSAIO_PRAZO:-}" ] || PRAZO=1800
    SAIDA=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/nexus-sense/ensaio-ec5-$(date +%Y%m%d-%H%M%S).tsv}
    mkdir -p "$(dirname "$SAIDA")" || exit 1
    # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
    printf "$CABECALHO" > "$SAIDA"
    RESUMO="${SAIDA%.tsv}.resumo.txt"

    echo "E-C5 -- o que larga o manual. A ventoinha fica a $C5_P%, e os gestos sao seus."
    echo "saida: $SAIDA"
    pausa_curva
    amostra partida; registra
    exige_alvos || exit "$COD_ALVO"
    for par in "suspend_stats:$SUSPENSOES" "boot_id:$BOOT_ID"; do
        [ -r "${par#*:}" ] || { echo "ERRO alvo ausente: ${par%%:*}"; falta=1; }
    done
    [ "$falta" = 0 ] || exit "$COD_ALVO"
    mostra_condicao
    pode_comecar || exit "$COD_RECUSA"
    if [ -e "$ESTADO_EC5" ]; then
        echo "  RECUSA: ha um reinicio pendente de outra rodada ($ESTADO_EC5): rode antes '$EU ec5-volta'"
        exit "$COD_RECUSA"
    fi
    PERFIL0=$V_PERFIL; MAX0=$V_MAX; PPD0=$V_PPD
    echo "partida: perfil $PERFIL0, modo maximo ${MAX0:-?}, perfil de energia $PPD0" > "$RESUMO"

    prepara
    coleta auto-antes 0 "$LEITURAS" || termina $?
    REF1=$(mediana_num "${C1[@]}"); REF2=$(mediana_num "${C2[@]}")
    if ! escreve "$v"; then MOTIVO="a escrita de $v foi recusada"; termina "$COD_CONDICAO"; fi
    coleta c5:manual "$ASSENTA" "$LEITURAS" || termina $?
    C5_REF1=$(mediana_num "${C1[@]}"); C5_REF2=$(mediana_num "${C2[@]}")
    echo "  a $C5_P%: $C5_REF1 / $C5_REF2 rpm (automatico, na partida: $REF1 / $REF2)" | tee -a "$RESUMO"
    # Sem distancia entre o manual e o automatico, "largou" nao se ve.
    if ! eh_num "$C5_REF1" || ! eh_num "$C5_REF2" \
       || [ $(( C5_REF1 - REF1 )) -lt $(( QUEDA_RPM * 2 )) ] \
       || [ $(( C5_REF2 - REF2 )) -lt $(( QUEDA_RPM * 2 )) ]; then
        MOTIVO="o manual a $C5_P% nao se distingue do automatico: menos de $(( QUEDA_RPM * 2 )) rpm acima"
        termina "$COD_CONTROLE"
    fi

    GESTO_HOOK=marca_fora
    if quer_gesto suspensao; then
        echo
        echo "SUSPENSAO"
        reinicia_obs; C5_SUSP0=$(le "$SUSPENSOES")
        pid0=$(unit_prop MainPID)
        # O perfil fica livre: medido em 2026-10-16, ao acordar o firmware o
        # troca para balanced. E achado, e nao motivo para parar; quem o devolve
        # e o agente (sono.py e Agent._depois_de_dormir).
        espera_gesto "suspenda a maquina (menu Suspender, ou feche a tampa) e acorde-a." perfil suspendeu c5:suspensao
        observa c5:suspensao:depois "$C5_DEPOIS" perfil
        relata suspensao
        pid1=$(unit_prop MainPID)
        {
            echo "    perfis vistos na suspensao: $OBS_PERFIS"
            if [ -z "$pid0" ] || [ -z "$pid1" ]; then
                echo "    o agente: sem a unit para perguntar"
            elif [ "$pid0" = "$pid1" ]; then
                echo "    o agente atravessou a suspensao vivo (pid $pid1)"
            else
                echo "    o agente NAO atravessou a suspensao: pid $pid0 antes, $pid1 depois"
            fi
        } | tee -a "$RESUMO"
        acomoda perfil_de_volta perfil c5:suspensao \
            "depois da suspensao o perfil nao voltou a $PERFIL0: quem o devolve e o agente"
    fi

    if quer_gesto cabo; then
        echo
        echo "CABO"
        reassume_manual c5:cabo:manual
        reinicia_obs
        # Na bateria o agente troca o perfil, e o devolve com o cabo de volta.
        espera_gesto "tire o cabo de energia." "cabo perfil" cabo_fora c5:cabo
        observa c5:cabo:bateria "$C5_FORA" "cabo perfil"
        espera_gesto "ponha o cabo de volta." "cabo perfil" cabo_dentro c5:cabo
        acomoda perfil_de_volta perfil c5:cabo "com o cabo de volta, o perfil nao voltou a $PERFIL0"
        observa c5:cabo:depois "$C5_DEPOIS"
        relata cabo
    fi

    if quer_gesto perfil; then
        echo
        echo "PERFIL TERMICO"
        reassume_manual c5:perfil:manual
        reinicia_obs
        # balanced, e nao quiet ou low-power: esses dois escrevem 0,0 no driver.
        espera_gesto "na janela, troque o perfil termico para balanced." perfil perfil_trocado c5:perfil
        observa c5:perfil:fora "$C5_FORA" perfil
        espera_gesto "volte o perfil termico para $PERFIL0." perfil perfil_de_volta c5:perfil
        observa c5:perfil:depois "$C5_DEPOIS"
        relata "perfil termico"
    fi
    GESTO_HOOK=:

    exercicio_guarda; rcg=$?
    if [ "$C5_REINICIO" = 1 ]; then
        reinicio_ec5 "$rcg"
    fi
    echo "E-C5 terminou sem pedir o reinicio (ENSAIO_C5_REINICIO=0). Resumo em $RESUMO"
    case "$rcg" in
        1) exit "$COD_EXERCICIO" ;;
        2) exit "$COD_SEM_GUARDA" ;;
    esac
    exit 0
}

chave() { grep -m1 "^$1=" "$ESTADO_EC5" 2>/dev/null | cut -d= -f2-; }

modo_ec5_volta() {
    local v r1 r2 boot0 boot up m1 m2 d1 d2 a1=() a2=() i reiniciou=1 rc=0 o no_manual=0
    if [ ! -f "$ESTADO_EC5" ]; then
        echo "ERRO alvo ausente: $ESTADO_EC5 -- nenhum reinicio pendente; o ec5 vem antes"
        exit "$COD_ALVO"
    fi
    v=$(chave valor); r1=$(chave rpm1); r2=$(chave rpm2); boot0=$(chave boot)
    SAIDA=$(chave saida); RESUMO=$(chave resumo)
    [ -n "$RESUMO" ] || RESUMO=/dev/null
    if [ -n "$SAIDA" ] && [ ! -f "$SAIDA" ]; then
        mkdir -p "$(dirname "$SAIDA")" || exit 1
        # shellcheck disable=SC2059  # o cabecalho e o formato, de proposito
        printf "$CABECALHO" > "$SAIDA"
    fi
    echo "E-C5, A VOLTA DO REINICIO"
    boot=$(le "$BOOT_ID"); up=$(cut -d' ' -f1 "$R/proc/uptime" 2>/dev/null)
    for ((i = 0; i < LEITURAS; i++)); do
        [ "$i" -gt 0 ] && sleep "$PASSO"
        amostra c5:volta; registra
        a1+=("$V_RPM1"); a2+=("$V_RPM2")
    done
    m1=$(mediana_num "${a1[@]}"); m2=$(mediana_num "${a2[@]}")
    # A rotacao esta onde o manual a deixou antes do reinicio?
    if eh_num "$m1" && eh_num "$m2" && eh_num "$r1" && eh_num "$r2"; then
        d1=$(( m1 - r1 )); d2=$(( m2 - r2 ))
        [ "${d1#-}" -lt "$QUEDA_RPM" ] && [ "${d2#-}" -lt "$QUEDA_RPM" ] && no_manual=1
    fi
    if [ "$boot" = "$boot0" ]; then
        reiniciou=0
        o="a maquina NAO reiniciou (o boot_id e o mesmo): nada a medir"
    elif [ "$V_FAN" = "$v" ]; then
        if [ "$no_manual" = 1 ]; then
            o="o manual $v VOLTOU na partida, e o EC o obedece: o driver gravou antes de o guarda devolver; $m1 / $m2 rpm"
        else
            o="fan_speed diz $v, mas a rotacao e $m1 / $m2, e nao a do manual ($r1 / $r2)"
        fi
    elif [ "$V_FAN" = "0,0" ]; then
        o="voltou em automatico (0,0): o guarda devolveu no desligamento antes de o driver gravar; $m1 / $m2 rpm"
    else
        o="voltou outro valor: fan_speed '$V_FAN', $m1 / $m2 rpm"
    fi
    echo "reinicio: $o; lido ${up:-?} s depois da partida" | tee -a "$RESUMO"

    # Devolve so o que o ec5 escreveu.
    if [ "$V_FAN" = "$v" ]; then
        ULTIMO=$v
        if volta_ao_automatico; then
            echo "ventoinha devolvida: fan_speed = $(le "$FAN")"
            # So se cobra a queda quando a rotacao estava no manual.
            if [ "$no_manual" = 1 ] && ! rotacao_largou 30 "$m1" "$m2" "$QUEDA_RPM" queda; then
                rc=$COD_EXERCICIO
            fi
        else
            echo "ERRO: nao consegui escrever 0,0 em tres tentativas; ventoinha em $(le "$FAN")."
            rc=$COD_DEVOLUCAO
        fi
    fi
    # A curva que o ec5 pausou volta agora, com a ventoinha ja devolvida.
    CURVA_INICIAL=$(chave curva)
    devolve_curva
    rm -f "$ESTADO_EC5"
    [ "$rc" -ne 0 ] && exit "$rc"
    [ "$reiniciou" = 1 ] || exit "$COD_CONDICAO"
    exit 0
}

case "${1:-}" in
    --vigia)  modo_vigia "$2" "$3" "$4" ;;
    _segura)  modo_segura ;;
    e2)       modo_e2 "${2:-}" ;;
    e3)       modo_e3 "${2:-}" ;;
    e3b)      modo_e3b "${2:-}" ;;
    rede)     modo_rede "${2:-}" ;;
    ec2)      modo_ec2 "${2:-}" ;;
    ec2-jogo) modo_ec2 "${2:-}" 1 ;;
    ec3)      modo_ec3 "${2:-}" ;;
    ec5)      modo_ec5 "${2:-}" ;;
    ec5-volta) modo_ec5_volta ;;
    _mapa)    pct_do_mapa "$2" "$3" ;;
    _regra)   regra_c2 "$2" "$3" "$4" "$5" "$6" "$7" ;;
    *)        sed -n '2,/^set -u$/{/^set -u$/d;p}' "$0"; exit 2 ;;
esac
