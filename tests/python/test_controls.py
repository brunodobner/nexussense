import errno
import os

import pytest

from nexus_sense.device import Controls, WriteError, read_state
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

SENSE = "sys/devices/platform/acer-wmi/nitro_sense"
PROFILE = "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"


def test_escreve_o_perfil(fake_root):
    Controls(Sysfs(fake_root)).set_profile("quiet")
    assert (fake_root / PROFILE).read_text().strip() == "quiet"


def test_escreve_a_ventoinha_no_formato_do_driver(fake_root):
    Controls(Sysfs(fake_root)).set_fan_speed(70, 80)
    assert (fake_root / SENSE / "fan_speed").read_text().strip() == "70,80"


def test_ventoinha_fora_da_faixa_e_recusada_antes_de_escrever(fake_root):
    """Melhor recusar aqui, com a razao escrita, do que mandar e receber
    -EINVAL. A validacao mora em model.py e esta camada so a usa."""
    antes = (fake_root / SENSE / "fan_speed").read_text()
    with pytest.raises(ValueError):
        Controls(Sysfs(fake_root)).set_fan_speed(70, 120)
    assert (fake_root / SENSE / "fan_speed").read_text() == antes


def test_carga_usb_fora_dos_quatro_niveis_e_recusada(fake_root):
    with pytest.raises(ValueError):
        Controls(Sysfs(fake_root)).set_usb_charging(15)


def test_escreve_os_booleanos_como_0_e_1(fake_root):
    c = Controls(Sysfs(fake_root))
    c.set_battery_limiter(False)
    c.set_backlight_timeout(True)
    c.set_battery_calibration(True)
    assert (fake_root / SENSE / "battery_limiter").read_text().strip() == "0"
    assert (fake_root / SENSE / "backlight_timeout").read_text().strip() == "1"
    assert (fake_root / SENSE / "battery_calibration").read_text().strip() == "1"


def test_o_que_foi_escrito_volta_na_leitura_seguinte(fake_root):
    """O sysfs e o estado compartilhado entre a GUI e o agente: nao ha
    cache a invalidar. Ver spec secao 4.1."""
    Controls(Sysfs(fake_root)).set_usb_charging(20)
    assert read_state(Sysfs(fake_root)).usb_charging == 20


def test_recurso_ausente_da_uma_frase_e_nao_um_traceback(tmp_path):
    raiz = build_tree(tmp_path)
    (raiz / SENSE / "backlight_timeout").unlink()
    with pytest.raises(WriteError) as capturado:
        Controls(Sysfs(raiz)).set_backlight_timeout(True)
    assert "não existe" in capturado.value.message


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignora a permissão do arquivo")
def test_sem_permissao_a_frase_fala_de_grupo_e_de_relogar(fake_root):
    """Os dois sintomas sao identicos -- 'nao consigo escrever' -- e as
    causas sao diferentes: fora do grupo, ou dentro dele numa sessao que
    ainda nao o herdou. A frase precisa cobrir as duas. Ver spec secao 9."""
    alvo = fake_root / SENSE / "fan_speed"
    alvo.chmod(0o444)
    try:
        with pytest.raises(WriteError) as capturado:
            Controls(Sysfs(fake_root)).set_fan_speed(50, 50)
    finally:
        alvo.chmod(0o644)
    frase = capturado.value.message
    assert "nexus_sense" in frase and "relogar" in frase


def test_recusa_do_driver_vira_frase_sobre_a_bateria(fake_root, monkeypatch):
    """EOPNOTSUPP e o que o driver devolve para quiet na bateria. Aqui ele
    e simulado; o teste de hardware tests/shell/test-perfil-bateria.sh cobre o
    caso real. Ver spec secao 2.8."""
    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    controles = Controls(Sysfs(fake_root))
    monkeypatch.setattr(controles.sysfs, "write", recusa)
    with pytest.raises(WriteError) as capturado:
        controles.set_profile("quiet")
    assert "bateria" in capturado.value.message


def test_a_mensagem_tambem_e_o_str_da_excecao(fake_root):
    erro = WriteError("qualquer coisa")
    assert str(erro) == "qualquer coisa" == erro.message
