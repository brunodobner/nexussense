"""A bandeja, e a escolha de qual delas.

Tres caminhos, na ordem de preferencia, e nenhum deles e erro:

  sni               ha host StatusNotifierItem: bandeja completa, com scroll
  qsystemtrayicon   nao ha: menu sim, scroll nao
  nenhuma           nem isso: o app abre a janela direto

Em nenhum dos tres a correcao de perfil e afetada -- ela mora no agente,
que nao sabe o que e Qt. Ver spec secao 7.3.
"""

from PySide6.QtWidgets import QSystemTrayIcon

from .controller import TrayController
from .fallback import FallbackTray
from .sni import StatusNotifierItem, register


def build_tray(sysfs, controls, parent=None):
    """Devolve (controlador, modo). O controlador e None no modo 'nenhuma'."""
    item = StatusNotifierItem(parent)
    if register(item):
        return TrayController(sysfs, controls, item, parent), "sni"

    if QSystemTrayIcon.isSystemTrayAvailable():
        reserva = FallbackTray(parent)
        controlador = TrayController(sysfs, controls, reserva, parent)
        reserva.show()
        return controlador, "qsystemtrayicon"

    return None, "nenhuma"
