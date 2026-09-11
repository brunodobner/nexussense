import os

import pytest

from nexus_sense.device import SENSE_ATTRS, read_state
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


def test_le_o_estado_inteiro_de_uma_arvore_completa(fake_root):
    e = read_state(Sysfs(fake_root))
    assert e.module_loaded is True
    assert e.on_ac is True
    assert e.profile == "balanced"
    assert e.choices == ("low-power", "quiet", "balanced", "balanced-performance")
    assert e.driver_version == "25.701"


def test_disponiveis_saem_do_modelo_e_nao_da_lista_crua(fake_root):
    """Na tomada os quatro anunciados passam."""
    e = read_state(Sysfs(fake_root))
    assert e.available == ("low-power", "quiet", "balanced", "balanced-performance")


def test_na_bateria_o_alcance_encolhe_e_nao_e_contiguo(tmp_path):
    """O 'quiet' fica entre dois permitidos e mesmo assim cai fora.
    Ver spec secao 2.8."""
    raiz = build_tree(tmp_path, on_ac=False)
    e = read_state(Sysfs(raiz))
    assert e.on_ac is False
    assert e.available == ("low-power", "balanced")


def test_le_os_cinco_controles_do_grupo_sense(fake_root):
    e = read_state(Sysfs(fake_root))
    assert e.fan_speed == (0, 0)
    assert e.battery_limiter is True
    assert e.usb_charging == 0
    assert e.backlight_timeout is False
    assert e.battery_calibration is False


def test_features_lista_o_que_existe_no_firmware(fake_root):
    assert read_state(Sysfs(fake_root)).features == frozenset(SENSE_ATTRS)


def test_atributo_ausente_sai_de_features_e_o_valor_e_none(tmp_path):
    """Numa maquina sem backlight_timeout a secao Teclado nao aparece.
    Ver spec secao 6.4."""
    raiz = build_tree(tmp_path)
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/backlight_timeout").unlink()
    e = read_state(Sysfs(raiz))
    assert "backlight_timeout" not in e.features
    assert e.backlight_timeout is None


def test_writable_reflete_a_permissao_de_verdade(fake_root):
    e = read_state(Sysfs(fake_root))
    assert "fan_speed" in e.writable
    assert e.profile_writable is True


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignora a permissão do arquivo")
def test_sem_permissao_o_atributo_sai_de_writable_mas_fica_em_features(fake_root):
    """E a diferenca entre 'nao existe' e 'existe e voce nao pode escrever'.
    A tela diz coisas diferentes nos dois casos. Ver spec secao 9."""
    alvo = fake_root / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed"
    alvo.chmod(0o444)
    try:
        e = read_state(Sysfs(fake_root))
    finally:
        alvo.chmod(0o644)
    assert "fan_speed" in e.features
    assert "fan_speed" not in e.writable


def test_arvore_vazia_nao_explode(tmp_path):
    """Modulo descarregado: a janela mostra a tela unica com o comando
    para carregar, e para isso precisa de um estado, nao de excecao."""
    e = read_state(Sysfs(tmp_path))
    assert e.module_loaded is False
    assert e.profile is None
    assert e.choices == ()
    assert e.available == ()
    assert e.features == frozenset()


def test_predator_sense_serve_igual(tmp_path):
    raiz = build_tree(tmp_path, sense="predator_sense")
    e = read_state(Sysfs(raiz))
    assert e.features == frozenset(SENSE_ATTRS)
    assert e.battery_limiter is True


def test_valor_ilegivel_vira_none_e_nao_excecao(tmp_path):
    raiz = build_tree(tmp_path)
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text("lixo\n")
    assert read_state(Sysfs(raiz)).fan_speed is None
