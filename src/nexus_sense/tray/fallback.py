"""Bandeja de reserva, quando nao ha host SNI no barramento.

Menu sim, scroll nao -- QSystemTrayIcon nao tem evento de roda. A
superficie e a mesma do StatusNotifierItem de proposito: o controlador
nao sabe com qual dos dois esta falando. Ver spec secao 7.3.
"""

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QSystemTrayIcon


class FallbackTray(QObject):
    """Embrulha um QSystemTrayIcon em vez de herdar dele.

    Herdar colidiria: QSystemTrayIcon ja tem um sinal `activated`, com
    outra assinatura -- ele emite um enum de razoes, e o controlador
    espera "clicaram com o esquerdo". Embrulhando, os quatro nomes ficam
    exatamente iguais aos do StatusNotifierItem.
    """

    activated = Signal()
    secondary = Signal()
    context_menu = Signal(int, int)
    scrolled = Signal(int, str)     # nunca emitido; existe pela simetria

    def __init__(self, parent=None):
        super().__init__(parent)
        self.icon = ""
        self.tooltip = ""
        self._tray = QSystemTrayIcon(self)
        self._tray.activated.connect(self._razao)

    def _razao(self, motivo):
        if motivo == QSystemTrayIcon.Trigger:
            self.activated.emit()
        elif motivo == QSystemTrayIcon.MiddleClick:
            self.secondary.emit()
        elif motivo == QSystemTrayIcon.Context:
            posicao = self._tray.geometry().center()
            self.context_menu.emit(posicao.x(), posicao.y())

    def show(self):
        self._tray.show()

    def set_icon(self, nome):
        self.icon = nome
        self._tray.setIcon(QIcon.fromTheme(nome))

    def set_tooltip(self, texto):
        self.tooltip = texto
        self._tray.setToolTip(texto)
