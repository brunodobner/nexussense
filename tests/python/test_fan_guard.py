"""A rede da ventoinha manual: a funcao pura.

Tres perguntas, nesta ordem, e cada uma so se faz se a anterior disse sim:
o manual esta abaixo do que o automatico faria neste modo? a GPU esta
quente? a ventoinha gira mesmo devagar? Duas passadas seguidas com as tres
e a rede devolve o automatico. Ver docs/plano-termico.md, secao 11.
"""

import pytest

from nexus_sense import fan_guard
from nexus_sense.fan_guard import GPU_QUENTE, SEGUIDAS, armada, decide

PISO = (2000, 1665)  # o que a ventoinha gira de 20% para baixo (E2)
QUENTE = GPU_QUENTE
FRIA = GPU_QUENTE - 1


# ------------------------------------------------------------- armar


@pytest.mark.parametrize(
    "setpoint, maximo, esperado",
    [
        ((0, 0), False, False),  # automatico
        ((100, 100), False, False),  # maximo
        ((20, 20), False, True),
        ((1, 1), False, True),  # abaixo de 20 e o mesmo piso
        ((52, 49), False, True),
        ((53, 50), False, False),  # o equivalente: a partir dele, nao arma
        ((52, 50), False, True),  # basta uma das duas abaixo
        ((53, 49), False, True),
        ((90, 90), False, False),
        # Zero num lado so e aquela ventoinha em automatico, nao parada.
        ((0, 30), False, True),
        ((30, 0), False, True),
        ((0, 60), False, False),
        # Com o modo maximo o automatico gira mais, e o equivalente sobe.
        ((60, 60), True, True),
        ((80, 81), True, True),
        ((81, 82), True, False),
        ((0, 0), True, False),
        ((100, 100), True, False),
    ],
)
def test_so_arma_em_manual_abaixo_do_automatico_do_modo(setpoint, maximo, esperado):
    assert armada(setpoint, maximo) is esperado


def test_sem_leitura_do_setpoint_nao_arma():
    assert armada(None, False) is False
    assert armada(None, True) is False


# ----------------------------------------------------------- disparar


def passadas(leituras, setpoint=(20, 20), maximo=False):
    """Roda a funcao sobre (gpu, rpm) em sequencia; devolve os vereditos."""
    seguidas, vereditos = 0, []
    for gpu, rpm in leituras:
        veredito = decide(seguidas, setpoint, maximo, gpu, rpm)
        seguidas = veredito.seguidas
        vereditos.append(veredito)
    return vereditos


def test_armada_e_quente_dispara_na_segunda_passada():
    assert SEGUIDAS == 2
    primeira, segunda = passadas([(QUENTE, PISO), (QUENTE, PISO)])
    assert primeira.dispara is False
    assert segunda.dispara is True


def test_um_grau_abaixo_nao_e_quente():
    assert not any(v.dispara for v in passadas([(FRIA, PISO)] * 10))


def test_uma_passada_fria_no_meio_recomeca_a_conta():
    vereditos = passadas([(QUENTE, PISO), (FRIA, PISO), (QUENTE, PISO), (QUENTE, PISO)])
    assert [v.dispara for v in vereditos] == [False, False, False, True]


def test_sem_armar_nao_dispara_por_mais_quente_que_esteja():
    for setpoint in ((0, 0), (100, 100), (53, 50), (90, 90)):
        vereditos = passadas([(95, PISO)] * 5, setpoint=setpoint)
        assert not any(v.dispara for v in vereditos), setpoint
        assert all(v.seguidas == 0 for v in vereditos), setpoint


def test_placa_dormindo_le_zero_e_nao_dispara():
    assert not any(v.dispara for v in passadas([(0, PISO)] * 5))


def test_sem_leitura_da_gpu_nao_dispara():
    """Leitura que falhou nao e prova de calor: tirar o manual de quem o
    escolheu pede prova."""
    vereditos = passadas([(QUENTE, PISO), (None, PISO), (QUENTE, PISO)])
    assert [v.dispara for v in vereditos] == [False, False, False]


def test_sem_leitura_da_rotacao_nao_dispara():
    assert not any(v.dispara for v in passadas([(QUENTE, None)] * 5))


# ------------------------------------- a rotacao, e nao so a memoria


def test_se_a_ventoinha_ja_gira_como_o_automatico_nao_ha_o_que_fazer():
    """fan_speed e a memoria do driver. Se ele lembra 20% e a ventoinha
    gira a 4500 rpm, quem manda nela ja e o firmware."""
    assert not any(v.dispara for v in passadas([(QUENTE, (4500, 4100))] * 5))


def test_a_rotacao_do_automatico_e_outra_com_o_modo_maximo():
    """5000 rpm e mais do que o automatico faz com o modo desligado, e
    menos do que ele faz com o modo ligado."""
    leituras = [(QUENTE, (5000, 4800))] * 3
    assert not any(v.dispara for v in passadas(leituras, setpoint=(50, 49)))
    assert any(v.dispara for v in passadas(leituras, setpoint=(60, 60), maximo=True))


def test_so_conta_a_rotacao_da_ventoinha_que_esta_em_manual_baixo():
    """GPU a 30%, CPU em automatico e girando alto: a da GPU esta lenta."""
    assert any(v.dispara for v in passadas([(QUENTE, (4500, 2469))] * 2, setpoint=(0, 30)))
    # E o contrario: a que esta em manual baixo gira alto, a outra nao conta.
    assert not any(
        v.dispara for v in passadas([(QUENTE, (2000, 4100))] * 5, setpoint=(0, 30))
    )


def test_a_rotacao_voltando_a_subir_recomeca_a_conta():
    vereditos = passadas([(QUENTE, PISO), (QUENTE, (4500, 4100)), (QUENTE, PISO)])
    assert [v.seguidas for v in vereditos] == [1, 0, 1]


# ---------------------------------------------------------- a tabela


def test_a_tabela_do_automatico_tem_os_dois_modos():
    """Os numeros sao os do plano termico, secao 6: o automatico com jogo
    gira 4414 / 4003 rpm com o modo maximo desligado e 6318 / 5984 com ele
    ligado, e isso e 53% / 50% e 81% / 82% de manual."""
    assert fan_guard.AUTOMATICO[False] == ((53, 50), (4414, 4003))
    assert fan_guard.AUTOMATICO[True] == ((81, 82), (6318, 5984))
