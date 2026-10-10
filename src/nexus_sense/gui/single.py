"""Uma instancia so.

Sem isto, abrir o app de novo registra um segundo StatusNotifierItem --
o nome do servico leva o PID -- e a bandeja fica com dois icones. Pior:
o icone antigo pode sobreviver ao processo que o criou, e clicar nele
nao faz nada, porque nao ha mais ninguem escutando.

O mecanismo e um nome bem-conhecido no barramento de sessao. Quem
consegue registra-lo e a instancia dona; quem nao consegue pede a ela
que apareca e sai em silencio. Nao ha arquivo de trava a limpar: se o
processo morre, o barramento libera o nome sozinho.
"""

from PySide6.QtCore import ClassInfo, QObject, Slot
from PySide6.QtDBus import QDBusAbstractAdaptor, QDBusConnection, QDBusInterface

APP_SERVICE = "com.nexussense.NexusSense"
APP_PATH = "/com/nexussense/NexusSense"
APP_INTERFACE = "com.nexussense.NexusSense"


@ClassInfo({"D-Bus Interface": APP_INTERFACE})
class _Adaptor(QDBusAbstractAdaptor):
    def __init__(self, parent):
        super().__init__(parent)
        self.alvo = parent

    @Slot()
    def Show(self):
        self.alvo.Show()


class SingleInstance(QObject):
    """O objeto que a segunda instancia chama para pedir a janela.

    `on_show` e o que fazer quando alguem pede: normalmente levantar a
    janela existente.
    """

    def __init__(self, on_show, parent=None):
        super().__init__(parent)
        self._on_show = on_show
        self._adaptor = _Adaptor(self)

    def Show(self):
        self._on_show()


def bus_available(*, bus=None):
    """Ha barramento de sessao? Sem ele nao ha nome a disputar.

    `claim` devolve False tanto para "o nome ja e de outro" quanto para
    "nao ha barramento", e so o primeiro quer dizer que ja existe uma
    instancia. Quem chama pergunta isto antes.
    """
    if bus is None:
        bus = QDBusConnection.sessionBus()
    return bool(bus.isConnected())


def claim(objeto, *, bus=None):
    """Tenta ser a instancia dona. False se ja ha uma.

    A ordem importa: registrar o objeto antes do nome deixaria uma
    janela em que o nome existe e o metodo ainda nao -- e a segunda
    instancia chamaria Show num objeto que nao esta la.
    """
    if bus is None:
        bus = QDBusConnection.sessionBus()
    if not bus.registerObject(APP_PATH, objeto, QDBusConnection.ExportAdaptors):
        return False
    return bool(bus.registerService(APP_SERVICE))


def raise_existing(*, bus=None, interface_factory=None):
    """Pede a instancia que ja roda para aparecer. False se nao deu."""
    if bus is None:
        bus = QDBusConnection.sessionBus()
    if interface_factory is None:
        def interface_factory(barramento):
            return QDBusInterface(APP_SERVICE, APP_PATH, APP_INTERFACE, barramento)

    interface = interface_factory(bus)
    if not interface.isValid():
        return False
    interface.call("Show")
    return True
