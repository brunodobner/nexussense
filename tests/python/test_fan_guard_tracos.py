"""Os limiares da rede, contra o que a maquina fez de verdade.

Os tracos em tracos/ sao os da medicao de 2026-10-10, recortados por
tests/hardware/recorta-tracos.py: os ensaios E2, E3 e E3b a 1 Hz, e duas
sessoes de jogo em automatico, uma com o modo maximo desligado e outra com
ele ligado. Cada traco entra na funcao pura passada a passada, como o
agente a chamaria.

O criterio, escrito antes dos numeros (docs/plano-termico.md, secao 11):
em automatico, e em manual a partir do equivalente, a rede nao dispara
nenhuma vez; em manual abaixo dele, com um jogo, dispara antes do instante
em que o ensaio abortou.
"""

import csv
import pathlib

import pytest

from nexus_sense import fan_guard
from nexus_sense.model import parse_fan_speed

TRACOS = pathlib.Path(__file__).parent / "tracos"
INTERVALO = 2  # s; o do agente
FASES = (0, 1)  # o agente nao sabe em que segundo o ensaio comecou
PISO_RPM = (2000, 1665)


def carrega(nome):
    with open(TRACOS / nome, newline="") as arquivo:
        linhas = list(csv.DictReader(arquivo, delimiter="\t"))
    # Sem isto um recorte vazio aprovaria todo "nao dispara" (armadilha 14).
    # O mais curto, uma rodada do portao, tem 125 linhas.
    assert len(linhas) > 100, nome
    return linhas


def setpoint_de(linha):
    return parse_fan_speed(linha["fan_speed"])


def maximo_de(linha):
    # O que o agente chama de ativo: pedido e na tomada.
    return linha["maximo"] == "true" and linha["acad"] == "1"


def gpu_de(linha):
    return int(linha["ec_gpu"]) // 1000


def passadas(linhas, fase):
    """As linhas que o agente leria, uma a cada INTERVALO segundos.

    Pelo relogio, e nao de duas em duas linhas: os ensaios pulam um
    segundo aqui e ali, e os passivos gravam a cada 5 s. A passada le a
    linha mais recente, como o agente leria o sysfs.
    """
    inicio = int(linhas[0]["epoch"]) + fase
    fim = int(linhas[-1]["epoch"])
    indice = 0
    for instante in range(inicio, fim + 1, INTERVALO):
        while indice + 1 < len(linhas) and int(linhas[indice + 1]["epoch"]) <= instante:
            indice += 1
        yield linhas[indice]


def disparos(linhas, fase=0, setpoint=None, rpm=None):
    """As linhas em que a rede dispararia. `setpoint` e `rpm` trocam o que
    o traco gravou, para perguntar "e se o manual fosse este?"."""
    seguidas, onde = 0, []
    for linha in passadas(linhas, fase):
        veredito = fan_guard.decide(
            seguidas,
            setpoint or setpoint_de(linha),
            maximo_de(linha),
            gpu_de(linha),
            rpm or (int(linha["rpm_cpu"]), int(linha["rpm_gpu"])),
        )
        seguidas = 0 if veredito.dispara else veredito.seguidas
        if veredito.dispara:
            onde.append(linha)
    return onde


def armadas(linhas):
    return [l for l in linhas if fan_guard.armada(setpoint_de(l), maximo_de(l))]


# ------------------------------------------------- nao dispara: automatico


@pytest.mark.parametrize("nome", ["jogo-auto.tsv", "jogo-auto-maximo.tsv"])
@pytest.mark.parametrize("fase", FASES)
def test_em_automatico_com_jogo_nao_dispara(nome, fase):
    linhas = carrega(nome)
    assert {l["fan_speed"] for l in linhas} == {"0,0"}
    assert disparos(linhas, fase) == []


def test_com_o_modo_desligado_quem_segura_e_o_armar():
    """O controle do teste acima: a GPU deste traco e quente para a rede em
    quase todas as amostras. Se o mesmo calor viesse com a ventoinha no
    piso, ela dispararia -- o que a cala em automatico e nao estar armada."""
    linhas = carrega("jogo-auto.tsv")
    quentes = [l for l in linhas if gpu_de(l) >= fan_guard.GPU_QUENTE]
    assert len(quentes) > 0.9 * len(linhas)
    assert len(disparos(linhas, setpoint=(20, 20), rpm=PISO_RPM)) > 100


def test_com_o_modo_ligado_o_automatico_nem_chega_a_quente():
    """Com o modo maximo a ventoinha gira 1900 rpm a mais e a GPU pelo EC
    nao passou de 75 C em 35 minutos de jogo. O limiar fica acima disso:
    um manual que gire como o automatico nao dispara neste modo."""
    linhas = carrega("jogo-auto-maximo.tsv")
    assert {l["maximo"] for l in linhas} == {"true"}
    assert max(gpu_de(l) for l in linhas) < fan_guard.GPU_QUENTE
    assert disparos(linhas, setpoint=(20, 20), rpm=PISO_RPM) == []


# -------------------------------- nao dispara: manual a partir do equivalente


@pytest.mark.parametrize(
    "nome, maximo", [("jogo-auto.tsv", False), ("jogo-auto-maximo.tsv", True)]
)
@pytest.mark.parametrize("fase", FASES)
def test_manual_no_equivalente_com_jogo_nao_dispara(nome, maximo, fase):
    """O automatico com jogo gira o que o manual equivalente gira. O mesmo
    traco, com o setpoint dizendo esse manual, e o manual no equivalente."""
    equivalente = fan_guard.AUTOMATICO[maximo].percentual
    assert disparos(carrega(nome), fase, setpoint=equivalente) == []


@pytest.mark.parametrize("fase", FASES)
def test_o_mapa_do_e2_em_repouso_nao_dispara(fase):
    """De 100% a 1%, 25 s em cada, com a maquina parada. Do equivalente
    para cima nao arma; abaixo dele arma e nao ha calor."""
    linhas = carrega("e2.tsv")
    acima = [l for l in linhas if l["fase"] in ("p=100", "p=80", "p=60")]
    assert len(acima) == 75 and armadas(acima) == []
    # Mais de metade do traco esta armada: o "nao dispara" nao e por vacuo.
    assert len(armadas(linhas)) > 150
    assert disparos(linhas, fase) == []


# ------------------------------------------- dispara: manual baixo, com jogo


@pytest.mark.parametrize("fase", FASES)
def test_no_e3b_dispara_antes_do_aborto(fase):
    """Jogo aberto, manual no piso: a GPU pelo EC subiu um grau por segundo
    e o ensaio abortou aos 85 C, sete segundos depois de escrever."""
    linhas = carrega("e3b.tsv")
    manual = [l for l in linhas if l["fase"] == "b:manual"]
    assert manual and {l["fan_speed"] for l in manual} == {"1,1"}
    aborto = int(manual[-1]["epoch"])
    assert gpu_de(manual[-1]) == 85

    onde = disparos(linhas, fase)

    assert onde, "a rede nao disparou no ensaio que abortou"
    assert onde[0]["fase"] == "b:manual"
    assert int(onde[0]["epoch"]) < aborto
    # Em segundos, e nao em 30: a contar da escrita do manual.
    assert int(onde[0]["epoch"]) - int(manual[0]["epoch"]) <= 4


@pytest.mark.parametrize("fase", FASES)
def test_no_e3b_nao_dispara_enquanto_esta_em_automatico(fase):
    """Os dois minutos de jogo em automatico que vem antes do manual."""
    linhas = carrega("e3b.tsv")
    antes = [l for l in linhas if l["fase"] in ("partida", "b:auto")]
    assert len(antes) > 100
    assert disparos(antes, fase) == []


# -------------------------------------- nao dispara: calor que e so de CPU


@pytest.mark.parametrize("fase", FASES)
def test_no_e3_com_carga_so_de_cpu_nao_dispara(fase):
    """Dez minutos no piso com oito nucleos a pleno: o pacote foi a 94 C,
    nada passou do envelope, e a GPU pelo EC parou em 69 -- calor do
    dissipador vizinho. A regra do plano chama isso de R2 e deixa a decisao
    com o usuario; a rede que a regra mandou fazer e a do jogo. O limiar
    fica acima dos 69."""
    linhas = carrega("e3.tsv")
    piso = [l for l in linhas if l["fase"] == "e2:carga"]
    assert len(piso) > 500 and len(armadas(piso)) == len(piso)
    assert max(int(l["pacote"]) for l in piso) >= 93000
    assert max(gpu_de(l) for l in linhas) == 69 < fan_guard.GPU_QUENTE
    assert disparos(linhas, fase) == []


# ---------------------------------------- os tracos do portao, 2026-10-10/11
#
# tests/hardware/ensaio-termico.sh rede, na maquina, com um jogo. O primeiro
# rodou contra a versao sem rede, com o modo maximo ligado: e o E3b que
# faltava nesse modo. O segundo, ja com a rede, com o modo desligado.


@pytest.mark.parametrize("fase", FASES)
def test_com_o_modo_maximo_ligado_dispara_bem_antes_do_aborto(fase):
    """Sem rede instalada, manual no piso com o modo maximo ligado: a GPU
    pelo EC foi de 73 a 85 C em 22 s, e o roteiro abortou. O limiar e
    cruzado aos 7 s; a rede, se estivesse la, agiria muito antes do fim."""
    linhas = carrega("rede-sem-rede-maximo.tsv")
    assert {l["maximo"] for l in linhas} == {"true"}
    piso = [l for l in linhas if l["fase"] == "r:piso"]
    assert piso and {l["fan_speed"] for l in piso} == {"20,20"}
    assert gpu_de(piso[-1]) == 85
    aborto = int(piso[-1]["epoch"])

    onde = disparos(linhas, fase)

    assert onde and onde[0]["fase"] == "r:piso"
    assert aborto - int(onde[0]["epoch"]) >= 10
    assert gpu_de(onde[0]) <= 80


@pytest.mark.parametrize("fase", FASES)
def test_com_o_modo_maximo_ligado_os_controles_do_portao_nao_disparam(fase):
    """Um minuto em automatico e um a 90%, com jogo: nenhum arma."""
    linhas = carrega("rede-sem-rede-maximo.tsv")
    controles = [l for l in linhas if l["fase"] in ("partida", "r:auto", "r:acima")]
    acima = [l for l in controles if l["fase"] == "r:acima"]
    assert len(acima) > 40 and {l["fan_speed"] for l in acima} == {"90,90"}
    assert disparos(controles, fase) == []


@pytest.mark.parametrize("fase", FASES)
def test_manual_a_60_com_o_modo_desligado_e_a_gpu_quente_nao_dispara(fase):
    """O controle que nao e por falta de calor: um minuto a 60%, com jogo,
    e a GPU pelo EC a 76 C ou mais em tres quartos das amostras. Com o modo
    desligado 60% esta acima do equivalente, e a rede nao arma."""
    linhas = carrega("rede-desligado.tsv")
    acima = [l for l in linhas if l["fase"] == "r:acima"]
    assert len(acima) > 40 and {l["fan_speed"] for l in acima} == {"60,60"}
    assert {l["maximo"] for l in acima} == {"false"}
    quentes = [l for l in acima if gpu_de(l) >= fan_guard.GPU_QUENTE]
    assert len(quentes) > 0.7 * len(acima)
    assert armadas(acima) == []
    antes_do_piso = [l for l in linhas if l["fase"] in ("partida", "r:auto", "r:acima")]
    assert disparos(antes_do_piso, fase) == []
