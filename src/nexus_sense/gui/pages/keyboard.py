"""Teclado: o unico recurso que este firmware anuncia.

O RGB de quatro zonas esta fora de escopo -- este laptop nao o tem
(has_four_zone_kb: false) e o codigo seria escrito sem poder ser
verificado. Ver spec secao 14.

Sai tambem o aviso laranja "This Section Requires Testing" da GUI
antiga: e nota de desenvolvimento vazando para a interface.
"""

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QCheckBox, QLabel, QVBoxLayout, QWidget

from ...device import WriteError
from .rows import SEM_PERMISSAO, ControlRow


class KeyboardPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls
        self.message_label = QLabel("")
        self.message_label.setWordWrap(True)

        caixa = QCheckBox()
        caixa.toggled.connect(self._escreve)

        self.rows = {
            "backlight_timeout": ControlRow(
                "Apagar a iluminação após inatividade",
                "apaga o teclado depois de 30 segundos sem uso",
                caixa,
            )
        }

        raiz = QVBoxLayout(self)
        titulo = QLabel("Teclado")
        titulo.setObjectName("titulo")
        raiz.addWidget(titulo)
        for linha in self.rows.values():
            raiz.addWidget(linha)
        raiz.addWidget(self.message_label)
        raiz.addStretch(1)

    def has_content(self, state):
        return "backlight_timeout" in state.features

    def apply_state(self, state):
        linha = self.rows["backlight_timeout"]
        existe = "backlight_timeout" in state.features
        linha.setVisible(existe)
        if not existe:
            return
        gravavel = "backlight_timeout" in state.writable
        linha.widget.setEnabled(gravavel)
        linha.set_reason("" if gravavel else SEM_PERMISSAO)
        linha.widget.blockSignals(True)
        linha.widget.setChecked(bool(state.backlight_timeout))
        linha.widget.blockSignals(False)

    def _escreve(self, ligado):
        self.message_label.setText("")
        try:
            self.controls.set_backlight_timeout(ligado)
        except WriteError as erro:
            self.message_label.setText(erro.message)
        self.changed.emit()
