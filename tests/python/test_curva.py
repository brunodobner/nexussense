"""A curva propria, pura: a tabela, a histerese e o piso da GPU quente.

E, contra os tracos da medicao, o invariante da rede: com a GPU pelo EC a
76 C ou mais, nenhuma ventoinha abaixo do equivalente do automatico. Os
tracos sao os da rede (tests/python/tracos/), passada a passada.
"""

import csv
import pathlib
from collections import deque

import pytest

from nexus_sense import curva, fan_guard

TRACOS = pathlib.Path(__file__).parent / "tracos"


# ─── a tabela ───────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "temperatura, esperado",
    [(30, 25), (50, 25), (55, 30), (60, 35), (65, 43), (70, 50), (80, 73), (88, 99), (100, 99)],
)
def test_a_tabela_da_cpu(temperatura, esperado):
    assert curva.na_tabela(curva.CPU, temperatura) == esperado


@pytest.mark.parametrize(
    "temperatura, esperado",
    [(0, 24), (55, 24), (60, 31), (65, 37), (70, 53), (76, 82), (78, 91), (80, 99), (90, 99)],
)
def test_a_tabela_da_gpu(temperatura, esperado):
    assert curva.na_tabela(curva.GPU, temperatura) == esperado


def test_as_tabelas_sao_as_aprovadas():
    """docs/plano-curva.md, secao 11. Mudar um ponto e decisao do usuario."""
    assert curva.CPU == ((50, 25), (60, 35), (70, 50), (80, 73), (88, 99))
    assert curva.GPU == ((55, 24), (65, 37), (70, 53), (76, 82), (80, 99))


def test_a_tabela_nunca_desce_com_a_temperatura():
    for tabela in (curva.CPU, curva.GPU):
        valores = [curva.na_tabela(tabela, t) for t in range(0, 101)]
        assert valores == sorted(valores)
        assert all(1 <= v <= 99 for v in valores)


def test_placa_dormindo_e_repouso():
    """O EC responde zero com a dGPU dormindo (armadilha 20)."""
    assert curva.decide(45, 0, None) == (25, 24)


def test_sem_temperatura_a_curva_nao_decide():
    assert curva.decide(None, 50, None) is None
    assert curva.decide(50, None, (30, 30)) is None


# ─── sobe na hora, desce devagar ────────────────────────────────────


def test_sobe_na_hora():
    assert curva.decide(70, 50, (25, 24)) == (50, 24)


def test_desce_so_tres_graus_depois():
    escrito = curva.decide(70, 50, None)
    assert escrito == (50, 24)
    # Dois graus abaixo: fica.
    assert curva.decide(68, 50, escrito) == escrito
    # Quatro abaixo: desce, mas so ate o que a tabela da tres graus acima.
    assert curva.decide(66, 50, escrito) == (curva.na_tabela(curva.CPU, 69), 24)


def test_o_piso_da_gpu_quente_vale_para_as_duas():
    assert curva.decide(60, 76, None) == (81, 82)


def test_o_piso_sai_tres_graus_abaixo_de_onde_entrou():
    escrito = curva.decide(60, 76, None)
    assert curva.decide(60, 74, escrito)[0] == 81
    # Fora do piso, desce -- devagar.
    assert curva.decide(60, 72, escrito)[0] == 81 - curva.DESCE_POR_PASSADA


def test_desce_no_maximo_quatro_pontos_por_passada():
    """Do teto ao repouso: 99 a 25 em passos de 4, sem queda brusca."""
    escrito = curva.decide(95, 50, None)
    assert escrito == (99, 24)
    passos = [escrito[0]]
    while escrito[0] > 25:
        escrito = curva.decide(45, 50, escrito)
        passos.append(escrito[0])
    assert all(a - b <= curva.DESCE_POR_PASSADA for a, b in zip(passos, passos[1:]))
    assert len(passos) - 1 == -(-(99 - 25) // curva.DESCE_POR_PASSADA)


def test_o_piso_olha_a_gpu_de_agora_e_nao_a_mediana():
    """A mediana atrasa a GPU quente em segundos, e a GPU sobe um grau por
    segundo com um jogo (E3b). O piso nao espera."""
    assert curva.decide(50, 60, None, gpu_agora=78) == (81, 82)


def test_a_mediana_ignora_um_ou_dois_pulos():
    assert curva.mediana([54, 54, 88, 91, 55]) == 55
    assert curva.mediana([54, 88]) == 54
    assert curva.mediana([]) is None
    assert curva.JANELA == 5


def test_o_piso_e_o_da_rede():
    """Se a rede mudar o equivalente, a curva o segue sozinha."""
    assert curva.PISO_QUENTE == fan_guard.AUTOMATICO[True].percentual
    assert curva.GPU_QUENTE == fan_guard.GPU_QUENTE
    assert all(
        piso >= fan_guard.AUTOMATICO[maximo].percentual[i]
        for maximo in (False, True)
        for i, piso in enumerate(curva.PISO_QUENTE)
    )


# ─── contra os tracos: a rede nunca dispara com a curva ─────────────


def _tracos():
    return sorted(TRACOS.glob("*.tsv"))


def test_ha_tracos_com_a_gpu_quente():
    """Sem isto o teste de baixo passaria por vacuo (armadilha 14)."""
    quentes = 0
    for caminho in _tracos():
        with caminho.open() as f:
            for linha in csv.DictReader(f, delimiter="\t"):
                if linha["ec_gpu"].isdigit() and int(linha["ec_gpu"]) // 1000 >= fan_guard.GPU_QUENTE:
                    quentes += 1
    assert quentes >= 50


@pytest.mark.parametrize("caminho", _tracos(), ids=lambda p: p.name)
def test_a_rede_nunca_dispara_com_a_curva(caminho):
    """Passada a passada: a curva decide com o que o traco leu, e a rede
    julga o que a curva escreveria, com a mediana que o agente usa. O
    pacote faz as vezes da CPU pelo EC, que estes tracos nao gravaram; o
    piso da GPU quente nao depende dele. A rotacao entra como zero: o pior
    caso para a rede."""
    escrito = None
    seguidas = 0
    cpus, gpus = deque(maxlen=curva.JANELA), deque(maxlen=curva.JANELA)
    with caminho.open() as f:
        for linha in csv.DictReader(f, delimiter="\t"):
            if not (linha["ec_gpu"].isdigit() and linha["pacote"].isdigit()):
                continue
            gpu = int(linha["ec_gpu"]) // 1000
            cpu = int(linha["pacote"]) // 1000
            cpus.append(cpu)
            gpus.append(gpu)
            escrito = curva.decide(curva.mediana(cpus), curva.mediana(gpus), escrito, gpu_agora=gpu)
            if gpu >= fan_guard.GPU_QUENTE:
                assert escrito[0] >= curva.PISO_QUENTE[0], linha
                assert escrito[1] >= curva.PISO_QUENTE[1], linha
            veredito = fan_guard.decide(
                seguidas, escrito, linha["maximo"] == "true", gpu, (0, 0)
            )
            seguidas = veredito.seguidas
            assert not veredito.dispara, linha
