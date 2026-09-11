"""A janela: barra lateral, paginas empilhadas e o rodape do agente."""

from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QListWidget,
    QMainWindow,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from ..device import read_state
from ..session import agent_active
from .pages import build_pages
from .poller import Poller

CARREGAR = "sudo modprobe nexus_sense"


class DriverMissingPage(QWidget):
    """A tela unica de quando o modulo nao esta carregado.

    Nao adianta mostrar controles cinzas: sem o modulo nao ha o que
    controlar. Uma tela, com o comando. Ver spec secao 9.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        leiaute = QVBoxLayout(self)
        rotulo = QLabel(
            "O driver não está carregado.\n\n"
            f"Para carregá-lo agora:\n    {CARREGAR}\n\n"
            "Se ele não volta sozinho no próximo boot, o instalador não "
            "chegou a escrever /etc/modules-load.d."
        )
        rotulo.setObjectName("driver_missing")
        rotulo.setWordWrap(True)
        leiaute.addStretch(1)
        leiaute.addWidget(rotulo)
        leiaute.addStretch(1)


class Window(QMainWindow):
    def __init__(self, sysfs, controls, pages=None):
        super().__init__()
        self.sysfs = sysfs
        self.controls = controls
        self.pages = tuple(build_pages(controls) if pages is None else pages)

        self.setWindowTitle("Nexus Sense")
        self.resize(920, 620)

        self.sidebar = QListWidget()
        self.sidebar.setFixedWidth(180)
        self.sidebar.currentRowChanged.connect(self._troca_pagina)

        self.agent_label = QLabel("")
        self.agent_label.setObjectName("agente")
        self.agent_label.setWordWrap(True)

        lateral = QVBoxLayout()
        lateral.addWidget(self.sidebar, 1)
        lateral.addWidget(self.agent_label)

        self.stack = QStackedWidget()
        self._driver_missing = DriverMissingPage()
        self.stack.addWidget(self._driver_missing)
        for _, _, pagina in self.pages:
            self.stack.addWidget(pagina)
            pagina.changed.connect(lambda: self.refresh(update_session=False))

        corpo = QHBoxLayout()
        corpo.addLayout(lateral)
        corpo.addWidget(self.stack, 1)

        central = QWidget()
        central.setLayout(corpo)
        self.setCentralWidget(central)

        # `_visiveis` guarda as chaves na ordem em que estao na barra, para
        # traduzir linha selecionada em pagina.
        self._visiveis = ()

        # A telemetria so roda com a janela visivel. Ver spec secao 10.2.
        self.poller = Poller(sysfs, parent=self)
        self.poller.sampled.connect(self._distribui_amostra)

    # ------------------------------------------------------------------

    def refresh(self, *, update_session=True):
        """Rele o aparelho e repinta tudo. E o unico caminho de
        atualizacao: nao ha cache, porque o sysfs e o estado."""
        estado = read_state(self.sysfs)
        if update_session or not self.agent_label.text():
            self.agent_label.setText(
                "Agente: ativo" if agent_active() else "Agente: fora do ar"
            )

        if not estado.module_loaded:
            self.sidebar.clear()
            self._visiveis = ()
            self.stack.setCurrentWidget(self._driver_missing)
            return

        visiveis = []
        for chave, rotulo, pagina in self.pages:
            pagina.apply_state(estado)
            if pagina.has_content(estado):
                visiveis.append((chave, rotulo, pagina))

        anterior = self._chave_atual()
        self._visiveis = tuple(v[0] for v in visiveis)
        self.sidebar.blockSignals(True)
        self.sidebar.clear()
        for _, rotulo, _ in visiveis:
            self.sidebar.addItem(rotulo)
        self.sidebar.blockSignals(False)

        if not visiveis:
            self.stack.setCurrentWidget(self._driver_missing)
            return
        linha = self._visiveis.index(anterior) if anterior in self._visiveis else 0
        self.sidebar.setCurrentRow(linha)
        self.stack.setCurrentWidget(visiveis[linha][2])

    def _chave_atual(self):
        linha = self.sidebar.currentRow()
        if 0 <= linha < len(self._visiveis):
            return self._visiveis[linha]
        return None

    def _troca_pagina(self, linha):
        if not (0 <= linha < len(self._visiveis)):
            return
        chave = self._visiveis[linha]
        for c, _, pagina in self.pages:
            if c == chave:
                self.stack.setCurrentWidget(pagina)
                return

    def _distribui_amostra(self, sample):
        """Entrega a leitura as paginas que a querem. apply_sample e
        protocolo opcional: quem nao tem, nao recebe."""
        for _, _, pagina in self.pages:
            metodo = getattr(pagina, "apply_sample", None)
            if metodo is not None:
                metodo(sample)

    def showEvent(self, evento):
        super().showEvent(evento)
        self.poller.start()

    def hideEvent(self, evento):
        super().hideEvent(evento)
        self.poller.stop()
