import subprocess

import pytest
from PySide6.QtCore import Signal
from PySide6.QtWidgets import QLabel, QWidget

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.window import Window
from nexus_sense.session import agent_active
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


class PaginaFalsa(QWidget):
    """Pagina de mentira que cumpre o protocolo."""

    changed = Signal()

    def __init__(self, conteudo=True):
        super().__init__()
        self._conteudo = conteudo
        self.aplicou = 0

    def has_content(self, state):
        return self._conteudo

    def apply_state(self, state):
        self.aplicou += 1


def janela(qtbot, raiz, paginas):
    s = Sysfs(raiz)
    j = Window(s, Controls(s), pages=paginas)
    qtbot.addWidget(j)
    return j


def test_a_barra_lateral_lista_as_secoes_com_conteudo(qtbot, fake_root):
    j = janela(qtbot, fake_root, (
        ("a", "Painel", PaginaFalsa()),
        ("b", "Bateria", PaginaFalsa()),
    ))
    j.refresh()
    assert [j.sidebar.item(i).text() for i in range(j.sidebar.count())] == ["Painel", "Bateria"]


def test_secao_sem_controle_algum_some_da_barra(qtbot, fake_root):
    """Numa maquina sem backlight_timeout a secao Teclado nao e exibida
    vazia: some. Ver spec secao 6.4."""
    j = janela(qtbot, fake_root, (
        ("a", "Painel", PaginaFalsa()),
        ("b", "Teclado", PaginaFalsa(conteudo=False)),
    ))
    j.refresh()
    assert [j.sidebar.item(i).text() for i in range(j.sidebar.count())] == ["Painel"]


def test_refresh_repassa_o_estado_a_cada_pagina(qtbot, fake_root):
    p = PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", p),))
    j.refresh()
    j.refresh()
    assert p.aplicou == 2


def test_trocar_de_secao_troca_a_pagina(qtbot, fake_root):
    a, b = PaginaFalsa(), PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", a), ("b", "Bateria", b)))
    j.refresh()
    j.sidebar.setCurrentRow(1)
    assert j.stack.currentWidget() is b


def test_o_sinal_da_pagina_faz_a_janela_reler(qtbot, fake_root):
    p = PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", p),))
    j.refresh()
    antes = p.aplicou
    p.changed.emit()
    assert p.aplicou > antes


def test_acao_de_controle_nao_repete_consulta_da_sessao(qtbot, fake_root, monkeypatch):
    consultas = []
    monkeypatch.setattr(
        "nexus_sense.gui.window.agent_active", lambda: consultas.append(1) or True
    )
    p = PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", p),))
    j.refresh()
    assert len(consultas) == 1
    p.changed.emit()
    assert len(consultas) == 1


def test_sem_o_modulo_a_janela_mostra_uma_tela_so(qtbot, tmp_path):
    """Modulo descarregado: nao adianta mostrar controles. Uma tela, com o
    comando para carregar. Ver spec secao 9."""
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    j = janela(qtbot, vazia, (("a", "Painel", PaginaFalsa()),))
    j.refresh()
    assert j.sidebar.count() == 0
    assert "sudo modprobe nexus_sense" in j.stack.currentWidget().findChild(QLabel, "driver_missing").text()


def test_o_rodape_diz_se_o_agente_esta_de_pe(qtbot, fake_root):
    """A informacao que passa a importar quando nao ha mais daemon.
    Ver spec secao 6.1."""
    j = janela(qtbot, fake_root, (("a", "Painel", PaginaFalsa()),))
    j.refresh()
    assert j.agent_label.text() != ""


def test_agente_ativo_le_o_systemctl_do_usuario():
    chamadas = []

    def espiao(args, **kwargs):
        chamadas.append(args)
        return subprocess.CompletedProcess(args, 0, stdout="active\n", stderr="")

    assert agent_active(runner=espiao) is True
    assert chamadas[0][:3] == ["systemctl", "--user", "is-active"]


def test_agente_inativo_nao_derruba_nada():
    def espiao(args, **kwargs):
        return subprocess.CompletedProcess(args, 3, stdout="inactive\n", stderr="")

    assert agent_active(runner=espiao) is False


def test_sem_systemctl_o_agente_e_dado_como_fora():
    def explode(args, **kwargs):
        raise FileNotFoundError("systemctl")

    assert agent_active(runner=explode) is False
