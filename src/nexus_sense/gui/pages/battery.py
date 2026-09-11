"""Bateria: limite de carga, carregamento USB e calibracao."""

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QCheckBox, QComboBox, QLabel, QVBoxLayout, QWidget

from ... import model
from ...device import WriteError
from .rows import SEM_PERMISSAO, ControlRow

NIVEIS_USB = (
    (0, "desligado"),
    (10, "para de fornecer abaixo de 10%"),
    (20, "para de fornecer abaixo de 20%"),
    (30, "para de fornecer abaixo de 30%"),
)


class BatteryPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls
        self.message_label = QLabel("")
        self.message_label.setWordWrap(True)

        limitador = QCheckBox()
        limitador.toggled.connect(
            lambda ligado: self._escreve(self.controls.set_battery_limiter, ligado)
        )

        usb = QComboBox()
        for nivel, rotulo in NIVEIS_USB:
            usb.addItem(rotulo, nivel)
        usb.currentIndexChanged.connect(
            lambda _: self._escreve(self.controls.set_usb_charging, usb.currentData())
        )

        calibracao = QCheckBox()
        calibracao.toggled.connect(
            lambda ligado: self._escreve(self.controls.set_battery_calibration, ligado)
        )

        self.rows = {
            "battery_limiter": ControlRow(
                "Limite de carga",
                "para de carregar em 80% para preservar a bateria",
                limitador,
            ),
            "usb_charging": ControlRow(
                "Carregamento USB com a tampa fechada",
                "abaixo do nível escolhido, as portas param de fornecer energia",
                usb,
            ),
            "battery_calibration": ControlRow(
                "Calibração da bateria",
                "não tire da tomada durante a calibração: o ciclo precisa "
                "descarregar e carregar por completo",
                calibracao,
            ),
        }

        raiz = QVBoxLayout(self)
        titulo = QLabel("Bateria")
        titulo.setObjectName("titulo")
        raiz.addWidget(titulo)
        for linha in self.rows.values():
            raiz.addWidget(linha)
        raiz.addWidget(self.message_label)
        raiz.addStretch(1)

    def has_content(self, state):
        return bool(set(self.rows) & set(state.features))

    def apply_state(self, state):
        valores = {
            "battery_limiter": state.battery_limiter,
            "usb_charging": state.usb_charging,
            "battery_calibration": state.battery_calibration,
        }
        for nome, linha in self.rows.items():
            existe = nome in state.features
            linha.setVisible(existe)
            if not existe:
                continue
            gravavel = nome in state.writable
            linha.widget.setEnabled(gravavel)
            linha.set_reason("" if gravavel else SEM_PERMISSAO)

            # Bloquear o sinal e obrigatorio: setChecked emite toggled, e
            # sem isto repintar a tela escreveria no sysfs.
            linha.widget.blockSignals(True)
            if nome == "usb_charging":
                indice = linha.widget.findData(valores[nome])
                if indice >= 0:
                    linha.widget.setCurrentIndex(indice)
            else:
                linha.widget.setChecked(bool(valores[nome]))
            linha.widget.blockSignals(False)

    def _escreve(self, funcao, valor):
        self.message_label.setText("")
        try:
            funcao(valor)
        except (WriteError, ValueError) as erro:
            self.message_label.setText(getattr(erro, "message", str(erro)))
        self.changed.emit()
