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
    # 70 e 80 no firmware sao 63 e 75 na barra, que vale 20 a 100.
    assert p.fan_sliders["cpu"].value() == 63
    assert p.fan_sliders["gpu"].value() == 75
    assert p.fan_values["cpu"].text() == "63%"


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
    alvo = fake_root / SENSE / "fan_speed"
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "68,56", timeout=2000)


def test_arrastar_o_cursor_escreve_quando_ele_para(qtbot, fake_root):
    """Cada passo do arrasto era uma escrita no firmware seguida de uma
    releitura completa do aparelho. O cursor agora escreve quando para."""
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    escritas = []
    p.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)

    for valor in range(1, 21):
        p.fan_sliders["cpu"].setValue(valor)
    assert escritas == []

    qtbot.waitUntil(lambda: escritas != [], timeout=2000)
    qtbot.wait(300)
    assert escritas == ["36,20"]


def test_repintura_nao_puxa_de_volta_o_cursor_com_escrita_pendente(qtbot, fake_root):
    """A bandeja repinta a janela a cada 5 s. Se isso cair entre o
    arrasto e a escrita, o cursor nao pode voltar ao valor antigo -- a
    escrita pendente levaria o valor antigo junto."""
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(60)

    p.apply_state(read_state(Sysfs(fake_root)))

    assert p.fan_sliders["cpu"].value() == 60
    alvo = fake_root / SENSE / "fan_speed"
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "68,20", timeout=2000)


def test_escolher_automatico_cancela_a_escrita_pendente_do_cursor(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(60)
    p.fan_buttons["auto"].click()

    qtbot.wait(400)
    assert (fake_root / SENSE / "fan_speed").read_text().strip() == "0,0"


# ------------------------------------- escolher Manual sem mexer no cursor
#
# Entrar em manual nao escreve. A janela repinta pelo firmware a cada
# passada da bandeja, e ele ainda diz 0,0: a escolha tem de sobreviver a
# isso ate o primeiro cursor se mexer. Visto pelo usuario em 2026-10-11:
# "tentei colocar no manual e o app forcou 2x modo automatico".


def test_escolher_manual_sobrevive_a_repintura_antes_de_mexer_no_cursor(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()

    for _ in range(3):
        p.apply_state(read_state(Sysfs(fake_root)))

    assert p.fan_manual_box.isVisible() is True
    assert p.fan_buttons["manual"].isChecked() is True
    assert p.fan_buttons["auto"].isChecked() is False
    # E continua sem escrever: quem manda na ventoinha e o cursor.
    assert (fake_root / SENSE / "fan_speed").read_text().strip() == "0,0"


def test_depois_de_escrever_a_tela_volta_a_seguir_o_firmware(qtbot, fake_root):
    """A escolha pendente acaba na primeira escrita. Dali em diante, se o
    firmware voltar a 0,0 por outra mao -- a rede do agente, a bandeja --
    a tela mostra Automatico."""
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(50)
    alvo = fake_root / SENSE / "fan_speed"
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "60,20", timeout=2000)

    alvo.write_text("0,0\n")
    p.apply_state(read_state(Sysfs(fake_root)))

    assert p.fan_buttons["auto"].isChecked() is True
    assert p.fan_manual_box.isVisible() is False


def test_escolher_automatico_desfaz_a_escolha_pendente(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_buttons["auto"].click()
    p.apply_state(read_state(Sysfs(fake_root)))
    assert p.fan_buttons["auto"].isChecked() is True
    assert p.fan_manual_box.isVisible() is False


def test_a_escolha_pendente_nao_esconde_um_maximo_vindo_de_fora(qtbot, fake_root):
    """Manual escolhido e nenhum cursor mexido; a bandeja poe a ventoinha
    no maximo. O firmware saiu do automatico: a tela mostra o que ele diz."""
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    (fake_root / SENSE / "fan_speed").write_text("100,100\n")
    p.apply_state(read_state(Sysfs(fake_root)))
    assert p.fan_buttons["max"].isChecked() is True
    assert p.fan_manual_box.isVisible() is False


# ---------------------------------------- a barra vale 20 a 100 no firmware


def test_o_comeco_da_barra_e_o_piso_e_nao_o_automatico(qtbot, fake_root):
    """De 20% para baixo a ventoinha gira o mesmo, e zero num lado so era
    aquela ventoinha em automatico. A barra em zero escreve 20: automatico
    passa a ser so pelo botao."""
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(50)
    alvo = fake_root / SENSE / "fan_speed"
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "60,20", timeout=2000)

    p.fan_sliders["cpu"].setValue(0)
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "20,20", timeout=2000)


def test_o_fim_da_barra_e_cem(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(100)
    p.fan_sliders["gpu"].setValue(100)
    alvo = fake_root / SENSE / "fan_speed"
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "100,100", timeout=2000)


@pytest.mark.parametrize("gravado", ["10,10", "1,19", "20,20"])
def test_valor_abaixo_do_piso_aparece_como_zero(qtbot, tmp_path, gravado):
    """O que a versao anterior, ou um ensaio, deixou gravado."""
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "fan_speed").write_text(f"{gravado}\n")
    p = pagina(qtbot, raiz)
    assert p.fan_buttons["manual"].isChecked() is True
    assert p.fan_sliders["cpu"].value() == 0
    assert p.fan_sliders["gpu"].value() == 0
    assert p.fan_values["cpu"].text() == "0%"


def test_zero_num_lado_so_aparece_como_zero_e_segue_manual(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "fan_speed").write_text("0,60\n")
    p = pagina(qtbot, raiz)
    assert p.fan_buttons["manual"].isChecked() is True
    assert p.fan_sliders["cpu"].value() == 0
    assert p.fan_sliders["gpu"].value() == 50


def test_repintar_nao_mexe_no_cursor_que_ja_vale_o_que_esta_gravado(qtbot, fake_root):
    """A barra tem 101 posicoes para 81 degraus: 2 e 3 valem 22. Quem
    parou no 2 nao pode ver o cursor pular para o 3 na repintura."""
    p = pagina(qtbot, fake_root)
    p.fan_buttons["manual"].click()
    p.fan_sliders["cpu"].setValue(2)
    alvo = fake_root / SENSE / "fan_speed"
    qtbot.waitUntil(lambda: alvo.read_text().strip() == "22,20", timeout=2000)

    p.apply_state(read_state(Sysfs(fake_root)))

    assert p.fan_sliders["cpu"].value() == 2
    assert p.fan_values["cpu"].text() == "2%"


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
