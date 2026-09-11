import errno

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.battery import BatteryPage
from nexus_sense.gui.pages.keyboard import KeyboardPage
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

SENSE = "sys/devices/platform/acer-wmi/nitro_sense"


def monta(qtbot, classe, raiz):
    s = Sysfs(raiz)
    p = classe(Controls(s))
    qtbot.addWidget(p)
    # Exibir e necessario para isVisible() dizer a verdade: no Qt ele e
    # False em todo filho enquanto o pai nao foi exibido, independente do
    # setVisible de cada um. Sem isto o teste da linha que some passaria
    # por acidente, com as duas linhas dando False.
    p.show()
    p.apply_state(read_state(s))
    return p


def test_a_bateria_tem_as_tres_linhas(qtbot, fake_root):
    """Os tres cartoes de hoje viram tres linhas de uma lista.
    Ver spec secao 6.3."""
    p = monta(qtbot, BatteryPage, fake_root)
    assert tuple(p.rows) == ("battery_limiter", "usb_charging", "battery_calibration")


def test_o_aviso_da_calibracao_e_o_subtitulo_da_linha_dela(qtbot, fake_root):
    """Deixa de ser paragrafo solto e passa a pertencer ao controle a que
    se refere. Ver spec secao 6.3."""
    p = monta(qtbot, BatteryPage, fake_root)
    assert "tomada" in p.rows["battery_calibration"].subtitle.text().lower()


def test_o_estado_dos_controles_vem_do_sysfs(qtbot, fake_root):
    p = monta(qtbot, BatteryPage, fake_root)
    assert p.rows["battery_limiter"].widget.isChecked() is True
    assert p.rows["usb_charging"].widget.currentData() == 0


def test_aplicar_o_estado_nao_dispara_escrita(qtbot, fake_root):
    """Armadilha classica de Qt: setChecked emite toggled, e sem bloquear
    o sinal a tela escreveria no sysfs so por ter sido repintada."""
    escritas = []
    p = monta(qtbot, BatteryPage, fake_root)
    p.controls.sysfs.write = lambda caminho, valor: escritas.append((caminho, valor))
    p.apply_state(read_state(Sysfs(fake_root)))
    assert escritas == []


def test_desmarcar_o_limitador_escreve_zero(qtbot, fake_root):
    p = monta(qtbot, BatteryPage, fake_root)
    p.rows["battery_limiter"].widget.setChecked(False)
    assert (fake_root / SENSE / "battery_limiter").read_text().strip() == "0"


def test_escolher_a_carga_usb_escreve_o_nivel(qtbot, fake_root):
    p = monta(qtbot, BatteryPage, fake_root)
    combo = p.rows["usb_charging"].widget
    combo.setCurrentIndex(combo.findData(20))
    assert (fake_root / SENSE / "usb_charging").read_text().strip() == "20"


def test_linha_de_recurso_ausente_some(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "usb_charging").unlink()
    p = monta(qtbot, BatteryPage, raiz)
    assert p.rows["usb_charging"].isVisible() is False
    assert p.rows["battery_limiter"].isVisible() is True


def test_sem_nenhum_dos_tres_a_secao_nao_tem_conteudo(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    for nome in ("battery_limiter", "usb_charging", "battery_calibration"):
        (raiz / SENSE / nome).unlink()
    s = Sysfs(raiz)
    p = BatteryPage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is False


def test_o_teclado_tem_o_unico_controle_que_o_firmware_anuncia(qtbot, fake_root):
    """Um controle so. O RGB de quatro zonas esta fora de escopo.
    Ver spec secao 6.4 e secao 14."""
    p = monta(qtbot, KeyboardPage, fake_root)
    assert tuple(p.rows) == ("backlight_timeout",)


def test_sem_backlight_timeout_a_secao_teclado_some(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "backlight_timeout").unlink()
    s = Sysfs(raiz)
    p = KeyboardPage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is False


def test_o_teclado_escreve_ao_marcar(qtbot, fake_root):
    p = monta(qtbot, KeyboardPage, fake_root)
    p.rows["backlight_timeout"].widget.setChecked(True)
    assert (fake_root / SENSE / "backlight_timeout").read_text().strip() == "1"


def test_erro_de_escrita_vira_frase_na_pagina(qtbot, fake_root):
    p = monta(qtbot, KeyboardPage, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EACCES, "Permission denied")

    p.controls.sysfs.write = recusa
    p.rows["backlight_timeout"].widget.setChecked(True)
    assert "grupo" in p.message_label.text()


def test_sem_permissao_o_controle_fica_desligado_com_o_motivo(qtbot, tmp_path):
    import os
    import pytest

    if os.geteuid() == 0:
        pytest.skip("root ignora a permissão do arquivo")
    raiz = build_tree(tmp_path / "t")
    alvo = raiz / SENSE / "battery_limiter"
    alvo.chmod(0o444)
    try:
        p = monta(qtbot, BatteryPage, raiz)
    finally:
        alvo.chmod(0o644)
    linha = p.rows["battery_limiter"]
    assert linha.widget.isEnabled() is False
    assert "grupo" in linha.reason.text()
