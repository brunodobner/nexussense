"""Uma instancia so. Ver src/nexus_sense/gui/single.py."""

from PySide6.QtDBus import QDBusConnection

from nexus_sense.gui.single import (
    APP_PATH,
    APP_SERVICE,
    SingleInstance,
    claim,
    raise_existing,
)


class BarramentoFalso:
    def __init__(self, servico=True, objeto=True):
        self._servico = servico
        self._objeto = objeto
        self.servicos = []
        self.caminho = None
        self.opcoes = None

    def registerService(self, nome):
        self.servicos.append(nome)
        return self._servico

    def registerObject(self, caminho, objeto, opcoes):
        self.caminho = caminho
        self.opcoes = opcoes
        return self._objeto


class InterfaceFalsa:
    def __init__(self, valida=True):
        self._valida = valida
        self.chamadas = []

    def isValid(self):
        return self._valida

    def call(self, metodo, *args):
        self.chamadas.append(metodo)


def test_a_primeira_instancia_fica_com_o_nome(qtbot):
    barramento = BarramentoFalso()
    assert claim(SingleInstance(lambda: None), bus=barramento) is True
    assert barramento.servicos == [APP_SERVICE]
    assert barramento.caminho == APP_PATH


def test_o_objeto_sobe_pelos_adaptadores(qtbot):
    """Mesma armadilha do SNI: ExportAllContents nao inclui adaptadores."""
    barramento = BarramentoFalso()
    claim(SingleInstance(lambda: None), bus=barramento)
    assert barramento.opcoes == QDBusConnection.ExportAdaptors


def test_a_segunda_instancia_nao_consegue_o_nome(qtbot):
    barramento = BarramentoFalso(servico=False)
    assert claim(SingleInstance(lambda: None), bus=barramento) is False


def test_o_objeto_entra_antes_do_nome(qtbot):
    """Se o nome subisse primeiro, haveria uma janela em que ele existe e
    o metodo ainda nao -- e a segunda instancia chamaria Show no vazio."""
    barramento = BarramentoFalso(objeto=False)
    assert claim(SingleInstance(lambda: None), bus=barramento) is False
    assert barramento.servicos == []


def test_a_segunda_instancia_pede_a_janela(qtbot):
    interface = InterfaceFalsa()
    assert raise_existing(bus=BarramentoFalso(), interface_factory=lambda _: interface) is True
    assert interface.chamadas == ["Show"]


def test_sem_a_outra_no_barramento_nao_da_para_pedir(qtbot):
    interface = InterfaceFalsa(valida=False)
    assert raise_existing(bus=BarramentoFalso(), interface_factory=lambda _: interface) is False
    assert interface.chamadas == []


def test_o_pedido_chega_a_quem_abre_a_janela(qtbot):
    """E o caminho todo: a segunda instancia chama Show, e quem responde e
    a funcao que levanta a janela da primeira."""
    abriu = []
    alvo = SingleInstance(lambda: abriu.append(True))
    alvo.Show()
    assert abriu == [True]
