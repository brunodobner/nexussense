"""Exportação SNI e DBusMenu na mesma conexão do barramento de sessão.

dbus-python conserva as assinaturas compostas do DBusMenu. O dispatcher
GLib do Qt atende a conexão no mesmo thread da GUI, sem polling ou thread
auxiliar. Sem esse dispatcher, build_tray usa QSystemTrayIcon.
"""

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from PySide6.QtCore import QCoreApplication

SNI = "org.kde.StatusNotifierItem"
MENU = "com.canonical.dbusmenu"
PROPERTIES = "org.freedesktop.DBus.Properties"
MENU_PATH = "/MenuBar"


class Properties(dbus.service.Object):
    @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.properties() if interface == self.interface else {}

    @dbus.service.method(PROPERTIES, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        values = self.GetAll(interface)
        if name not in values:
            raise dbus.exceptions.DBusException(
                "Propriedade desconhecida", name="org.freedesktop.DBus.Error.UnknownProperty"
            )
        return values[name]

    @dbus.service.method(PROPERTIES, in_signature="ssv", out_signature="")
    def Set(self, interface, name, value):
        raise dbus.exceptions.DBusException(
            "Propriedade somente leitura", name="org.freedesktop.DBus.Error.PropertyReadOnly"
        )


class MenuExport(Properties):
    interface = MENU

    def __init__(self, bus, item):
        super().__init__(bus, MENU_PATH)
        self.item = item
        self.menu = None
        self.revision = 0
        self.actions = {}
        self._snapshot = None
        self._ids = {}

    def properties(self):
        return {"Version": dbus.UInt32(3), "TextDirection": "ltr", "Status": "normal",
                "IconThemePath": dbus.Array([], signature="s")}

    def refresh(self):
        if self.item.menu_factory is None:
            return False
        menu = self.item.menu_factory()
        actions = {}
        snapshot = {}
        for index, action in enumerate(menu.actions()):
            # Identidade estável: retirar um perfil na bateria não reaproveita
            # seu id para outro comando em um menu que o host ainda tem aberto.
            key = (action.objectName() or action.text()) if not action.isSeparator() else f"separator-{index}"
            ident = self._ids.setdefault(key, len(self._ids) + 1)
            props = {"label": action.text(), "enabled": action.isEnabled(), "visible": action.isVisible()}
            if action.isSeparator():
                props = {"type": "separator"}
            elif action.isCheckable():
                props.update({"toggle-type": "radio", "toggle-state": int(action.isChecked())})
            actions[ident] = action
            snapshot[ident] = props
        old = self.menu
        self.menu, self.actions = menu, actions
        if old is not None:
            old.deleteLater()
        if snapshot == self._snapshot:
            return False
        self._snapshot = snapshot
        self.revision += 1
        self.LayoutUpdated(self.revision, 0)
        return True

    def _props(self, ident, names):
        if ident == 0:
            props = {"children-display": "submenu"}
        elif ident in (self._snapshot or {}):
            props = self._snapshot[ident]
        else:
            raise dbus.exceptions.DBusException("Item desconhecido", name=MENU + ".Error.InvalidMenuItem")
        return dbus.Dictionary({k: v for k, v in props.items() if not names or k in names}, signature="sv")

    def _layout(self, ident, depth, names):
        children = []
        if ident == 0 and depth != 0:
            children = [self._layout(i, 0, names) for i in self.actions]
        return dbus.Struct((dbus.Int32(ident), self._props(ident, names),
                            dbus.Array(children, signature="v")), signature="ia{sv}av")

    @dbus.service.method(MENU, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parentId, recursionDepth, propertyNames):
        self.refresh()
        return self.revision, self._layout(parentId, recursionDepth, propertyNames)

    @dbus.service.method(MENU, in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, ids, propertyNames):
        return [(i, self._props(i, propertyNames)) for i in (ids or [0, *self.actions])
                if i == 0 or i in self.actions]

    @dbus.service.method(MENU, in_signature="is", out_signature="v")
    def GetProperty(self, ident, name):
        props = self._props(ident, [])
        if name not in props:
            raise dbus.exceptions.DBusException("Propriedade desconhecida", name=MENU + ".Error.InvalidProperty")
        return props[name]

    @dbus.service.method(MENU, in_signature="isvu", out_signature="")
    def Event(self, ident, eventId, data, timestamp):
        self.refresh()
        self._props(ident, [])
        action = self.actions.get(ident)
        if eventId == "clicked" and action is not None and action.isEnabled() and not action.isSeparator():
            action.trigger()
            self.refresh()

    @dbus.service.method(MENU, in_signature="a(isvu)", out_signature="ai")
    def EventGroup(self, events):
        errors = []
        for event in events:
            try:
                self.Event(*event)
            except dbus.exceptions.DBusException:
                errors.append(event[0])
        return errors

    @dbus.service.method(MENU, in_signature="i", out_signature="b")
    def AboutToShow(self, ident):
        changed = self.refresh()
        self._props(ident, [])
        return changed

    @dbus.service.method(MENU, in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, ids):
        changed = self.refresh()
        valid = [i for i in ids if i == 0 or i in self.actions]
        return valid if changed else [], [i for i in ids if i not in valid]

    @dbus.service.signal(MENU, signature="ui")
    def LayoutUpdated(self, revision, parent):
        pass


class ItemExport(Properties):
    interface = SNI

    def __init__(self, bus, item):
        super().__init__(bus, "/StatusNotifierItem")
        self.item = item
        self.menu = MenuExport(bus, item)

    def properties(self):
        return {"Category": "Hardware", "Id": "nexus-sense", "Title": self.item.tooltip,
                "Status": "Active", "IconName": self.item.icon, "ItemIsMenu": False,
                "Menu": dbus.ObjectPath(MENU_PATH)}

    @dbus.service.method(SNI, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        self.item.Activate(x, y)

    @dbus.service.method(SNI, in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        self.item.SecondaryActivate(x, y)

    @dbus.service.method(SNI, in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        self.item.ContextMenu(x, y)

    @dbus.service.method(SNI, in_signature="is", out_signature="")
    def Scroll(self, delta, orientation):
        self.item.Scroll(delta, orientation)

    @dbus.service.signal(SNI, signature="")
    def NewIcon(self):
        pass

    @dbus.service.signal(SNI, signature="")
    def NewTitle(self):
        pass


def publish(item, name):
    app = QCoreApplication.instance()
    if app is None or "Glib" not in app.eventDispatcher().metaObject().className():
        return False
    # Sem barramento de sessao a propria conexao levanta. E o primeiro dos
    # motivos para cair na reserva, e por isso mora dentro de um try.
    try:
        bus = dbus.SessionBus(private=True, mainloop=DBusGMainLoop())
    except dbus.exceptions.DBusException:
        return False
    owner = exported = None
    try:
        owner = dbus.service.BusName(name, bus, do_not_queue=True)
        exported = ItemExport(bus, item)
        watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
        watcher.RegisterStatusNotifierItem(name, dbus_interface="org.kde.StatusNotifierWatcher")
    except dbus.exceptions.DBusException:
        # Sem watcher (ou com o nome ja tomado): desfazer tudo, para nao
        # deixar SNI pela metade no barramento. A ordem decide duas coisas.
        #
        #   o nome sai antes da conexao   BusName.__del__ chama release_name,
        #                                 e numa conexao fechada isso vira
        #                                 traceback no stderr
        #   quem fecha somos nos          a libdbus encerra com _exit(1) o
        #                                 processo que perde o barramento --
        #                                 e so no laco de eventos, quando
        #                                 esta funcao ja devolveu False e
        #                                 ninguem mais associa as duas coisas
        owner = exported = None
        bus.set_exit_on_disconnect(False)
        bus.close()
        return False
    item._export = exported
    item._bus = bus
    item._owner = owner
    return True
