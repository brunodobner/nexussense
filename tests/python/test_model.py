import pytest

from nexus_sense.model import (
    AC_ONLY,
    LABELS,
    PROFILES,
    available,
    nearest,
    neighbour,
)

QUATRO = ["low-power", "quiet", "balanced", "balanced-performance"]
CINCO = QUATRO + ["performance"]


def test_ordem_canonica_vai_do_economico_ao_agressivo():
    assert PROFILES == (
        "low-power",
        "quiet",
        "balanced",
        "balanced-performance",
        "performance",
    )


def test_todo_perfil_tem_rotulo_em_portugues():
    assert set(LABELS) == set(PROFILES)
    assert LABELS["low-power"] == "Econômico"
    assert LABELS["balanced-performance"] == "Desempenho"


def test_na_tomada_todos_os_anunciados_estao_disponiveis():
    assert available(QUATRO, on_ac=True) == tuple(QUATRO)


def test_na_bateria_o_driver_recusa_tres():
    assert AC_ONLY == frozenset({"quiet", "balanced-performance", "performance"})
    assert available(QUATRO, on_ac=False) == ("low-power", "balanced")


def test_o_alcance_na_bateria_tem_buraco_no_meio():
    """O Silencioso fica entre dois validos e mesmo assim e barrado.
    Medido na maquina: -EOPNOTSUPP. Ver spec secao 2.8."""
    disponiveis = available(QUATRO, on_ac=False)
    assert "quiet" not in disponiveis
    assert disponiveis.index("low-power") == 0
    assert disponiveis.index("balanced") == 1


def test_ignora_perfil_que_o_firmware_nao_anuncia():
    assert "performance" not in available(QUATRO, on_ac=True)
    assert "performance" in available(CINCO, on_ac=True)


def test_a_ordem_devolvida_e_sempre_a_canonica():
    embaralhado = ["balanced", "low-power", "balanced-performance", "quiet"]
    assert available(embaralhado, on_ac=True) == tuple(QUATRO)


def test_scroll_sobe_um_degrau_na_tomada():
    assert neighbour("balanced", QUATRO, on_ac=True, step=+1) == "balanced-performance"


def test_scroll_desce_um_degrau_na_tomada():
    assert neighbour("balanced", QUATRO, on_ac=True, step=-1) == "quiet"


def test_scroll_pula_o_indisponivel_na_bateria():
    """Subir do Economico leva direto ao Equilibrado: o Silencioso e barrado."""
    assert neighbour("low-power", QUATRO, on_ac=False, step=+1) == "balanced"


def test_scroll_bate_no_limite_e_para():
    assert neighbour("balanced", QUATRO, on_ac=False, step=+1) == "balanced"
    assert neighbour("low-power", QUATRO, on_ac=False, step=-1) == "low-power"
    assert (
        neighbour("balanced-performance", QUATRO, on_ac=True, step=+1)
        == "balanced-performance"
    )


def test_scroll_a_partir_de_um_perfil_que_ficou_invalido():
    """Estava em balanced-performance e o cabo saiu: o perfil corrente nao
    esta mais na lista. Vai para o valido mais proximo, nao para a ponta."""
    assert neighbour("balanced-performance", QUATRO, on_ac=False, step=-1) == "balanced"


def test_nearest_escolhe_pela_distancia_na_escada():
    assert nearest("balanced-performance", ["low-power", "balanced"]) == "balanced"
    assert nearest("quiet", ["low-power", "balanced"]) in {"low-power", "balanced"}


def test_sem_nenhum_perfil_disponivel_o_atual_permanece():
    assert neighbour("balanced", [], on_ac=True, step=+1) == "balanced"


from nexus_sense.model import (
    USB_LEVELS,
    bool_value,
    fan_speed_value,
    parse_bool,
    parse_fan_speed,
    usb_charging_value,
)


def test_ventoinha_no_formato_que_o_driver_espera():
    """linuwu_sense.c:3651 imprime "%d,%d"; o store le com strsep na virgula."""
    assert fan_speed_value(0, 0) == "0,0"
    assert fan_speed_value(100, 100) == "100,100"
    assert fan_speed_value(55, 40) == "55,40"


@pytest.mark.parametrize(
    "cpu,gpu", [(-1, 50), (50, -1), (101, 50), (50, 101), (200, 200)]
)
def test_ventoinha_fora_de_0_100_e_recusada(cpu, gpu):
    with pytest.raises(ValueError, match="0 a 100"):
        fan_speed_value(cpu, gpu)


def test_le_a_ventoinha_de_volta():
    assert parse_fan_speed("0,0") == (0, 0)
    assert parse_fan_speed("55,40\n") == (55, 40)


def test_ventoinha_ilegivel_levanta_erro():
    with pytest.raises(ValueError):
        parse_fan_speed("automatico")


def test_carga_usb_so_aceita_os_quatro_niveis():
    assert USB_LEVELS == (0, 10, 20, 30)
    for nivel in USB_LEVELS:
        assert usb_charging_value(nivel) == str(nivel)


@pytest.mark.parametrize("nivel", [1, 5, 15, 40, -10])
def test_carga_usb_recusa_qualquer_outro(nivel):
    with pytest.raises(ValueError, match="0, 10, 20 ou 30"):
        usb_charging_value(nivel)


def test_booleanos_viram_um_e_zero():
    assert bool_value(True) == "1"
    assert bool_value(False) == "0"
    assert parse_bool("1") is True
    assert parse_bool("0\n") is False


# ------------------------------------------------ o cursor de manual
#
# De 20% para baixo a ventoinha gira o mesmo -- ~2000 / ~1665 rpm, medido
# em 2026-10-10 (docs/plano-termico.md, secao 6). O cursor segue de 0 a
# 100 na tela e vale 20 a 100 no firmware: a faixa morta some.

from nexus_sense.model import FAN_FLOOR, fan_bar_to_firmware, fan_firmware_to_bar


@pytest.mark.parametrize(
    "barra, firmware", [(0, 20), (1, 21), (25, 40), (50, 60), (75, 80), (100, 100)]
)
def test_a_barra_de_0_a_100_vale_20_a_100_no_firmware(barra, firmware):
    assert fan_bar_to_firmware(barra) == firmware


def test_nenhuma_posicao_da_barra_cai_na_faixa_morta():
    valores = [fan_bar_to_firmware(barra) for barra in range(101)]
    assert min(valores) == FAN_FLOOR == 20
    assert max(valores) == 100
    assert valores == sorted(valores)
    # E nenhum degrau do firmware fica sem posicao na barra.
    assert set(valores) == set(range(20, 101))


@pytest.mark.parametrize("firmware", [0, 1, 5, 19, 20])
def test_na_leitura_valor_ate_o_piso_mostra_zero(firmware):
    """Zero e automatico e 1 a 20 e o piso: na barra, tudo isso e o
    comeco dela."""
    assert fan_firmware_to_bar(firmware) == 0


@pytest.mark.parametrize("firmware, barra", [(21, 1), (40, 25), (60, 50), (80, 75), (100, 100)])
def test_na_leitura_o_firmware_volta_para_a_barra(firmware, barra):
    assert fan_firmware_to_bar(firmware) == barra


def test_o_que_se_le_e_o_que_se_escreveria():
    """A barra tem 101 posicoes e o firmware 81 degraus: duas posicoes
    podem valer o mesmo degrau, mas ler um degrau e escreve-lo de volta
    nunca o muda."""
    for firmware in range(20, 101):
        assert fan_bar_to_firmware(fan_firmware_to_bar(firmware)) == firmware
