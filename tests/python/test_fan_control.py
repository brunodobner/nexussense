"""O ajuste das ventoinhas na tela Desempenho.

O atributo fan_speed e o setpoint das duas ventoinhas, no formato
"%d,%d". Tres modos que importam: "0,0" e automatico -- e nao parada --,
"100,100" e maximo, e qualquer outro par e manual. Ver spec secao 2.5.
"""

import errno

import pytest

from PySide6.QtCore import QPoint, Qt

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.performance import PerformancePage, fan_mode
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

SENSE = "sys/devices/platform/acer-wmi/nitro_sense"


def pagina(qtbot, raiz):
    s = Sysfs(raiz)
    p = PerformancePage(Controls(s))
    qtbot.addWidget(p)
    p.show()
    p.apply_state(read_state(s))
    return p


# ------------------------------------------------------------ o modo


def test_zero_e_automatico_e_nao_parada():
    """Chamar '0,0' de parada seria mentira: e o driver assumindo."""
    assert fan_mode((0, 0)) == "auto"


def test_cem_e_maximo():
    assert fan_mode((100, 100)) == "max"


def test_qualquer_outro_par_e_manual():
    assert fan_mode((70, 80)) == "manual"
    assert fan_mode((0, 50)) == "manual"
    assert fan_mode((100, 40)) == "manual"


def test_sem_leitura_nao_ha_modo():
    assert fan_mode(None) is None


# --------------------------------------------------------- a interface


def test_a_tela_tem_os_tres_modos(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    assert tuple(p.fan_buttons) == ("auto", "max", "manual")


def test_o_modo_corrente_vem_do_sysfs(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    assert p.fan_buttons["auto"].isChecked() is True
    assert p.fan_buttons["manual"].isChecked() is False


def test_setpoint_manual_marca_o_modo_manual(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "fan_speed").write_text("70,80\n")
    p = pagina(qtbot, raiz)
    assert p.fan_buttons["manual"].isChecked() is True
    assert p.fan_sliders["cpu"].value() == 70
    assert p.fan_sliders["gpu"].value() == 80


def test_os_controles_manuais_so_aparecem_no_modo_manual(qtbot, fake_root):
    """Em automatico os numeros nao querem dizer nada, e mostra-los
    convidaria a mexer num valor que o driver ignora."""
    p = pagina(qtbot, fake_root)
    assert p.fan_manual_box.isVisible() is False
    p.fan_buttons["manual"].click()
    assert p.fan_manual_box.isVisible() is True


def test_escolher_automatico_escreve_zero_zero(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "fan_speed").write_text("70,80\n")
    p = pagina(qtbot, raiz)
    p.fan_buttons["auto"].click()
    assert (raiz / SENSE / "fan_speed").read_text().strip() == "0,0"


def test_escolher_maximo_escreve_cem_cem(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.fan_buttons["max"].click()
    assert (fake_root / SENSE / "fan_speed").read_text().strip() == "100,100"


def test_entrar_em_manual_nao_escreve_sozinho(qtbot, fake_root):
    """So mostrar os controles nao pode mexer na ventoinha: quem escreve
    e o usuario, ao mover o cursor ou confirmar."""
    p = pagina(qtbot, fake_root)
    escritas = []
    p.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)
    p.fan_buttons["manual"].click()
    assert escritas == []


def test_mover_o_cursor_escreve_o_par(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(60)
    p.fan_sliders["gpu"].setValue(45)
    assert (fake_root / SENSE / "fan_speed").read_text().strip() == "60,45"


def test_clicar_no_trilho_move_direto_ao_ponto(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.resize(800, 500)
    p.fan_buttons["manual"].click()
    cursor = p.fan_sliders["cpu"]
    qtbot.mouseClick(
        cursor,
        Qt.LeftButton,
        pos=QPoint(round(cursor.width() * 3 / 4), cursor.height() // 2),
    )
    assert 73 <= cursor.value() <= 77
    assert p.fan_values["cpu"].text() == f"{cursor.value()}%"


def test_aplicar_o_estado_nao_dispara_escrita(qtbot, fake_root):
    """A mesma armadilha das outras paginas: setValue emite valueChanged."""
    p = pagina(qtbot, fake_root)
    escritas = []
    p.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)
    p.apply_state(read_state(Sysfs(fake_root)))
    assert escritas == []


def test_sem_o_recurso_a_secao_da_ventoinha_some(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "fan_speed").unlink()
    p = pagina(qtbot, raiz)
    assert p.fan_box.isVisible() is False


@pytest.mark.skipif(__import__("os").geteuid() == 0, reason="root ignora a permissão")
def test_sem_permissao_a_ventoinha_fica_desligada(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    alvo = raiz / SENSE / "fan_speed"
    alvo.chmod(0o444)
    try:
        p = pagina(qtbot, raiz)
    finally:
        alvo.chmod(0o644)
    assert p.fan_buttons["max"].isEnabled() is False


def test_erro_de_escrita_vira_frase_e_nao_excecao(qtbot, fake_root):
    p = pagina(qtbot, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EACCES, "Permission denied")

    p.controls.sysfs.write = recusa
    p.fan_buttons["max"].click()
    assert "grupo" in p.message_label.text()


def test_a_secao_aparece_mesmo_sem_perfil_anunciado(qtbot, tmp_path):
    """Uma maquina que exponha fan_speed e nenhum perfil ainda tem o que
    mostrar aqui -- a secao nao pode sumir junto."""
    raiz = build_tree(tmp_path / "t", choices="")
    s = Sysfs(raiz)
    p = PerformancePage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is True
