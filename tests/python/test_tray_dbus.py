"""Contrato real SNI/DBusMenu, em sessão privada e sem escrever no hardware."""
import os
from pathlib import Path
import subprocess
import sys
import time

import dbus
import pytest

from conftest import build_tree

SNI = "org.kde.StatusNotifierItem"
MENU = "com.canonical.dbusmenu"
WATCHER = "org.kde.StatusNotifierWatcher"
ROOT = Path(__file__).resolve().parents[2]

WATCHER_CODE = """
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from PySide6.QtCore import QCoreApplication
app = QCoreApplication([])
bus = dbus.SessionBus(private=True, mainloop=DBusGMainLoop())
owner = dbus.service.BusName('org.kde.StatusNotifierWatcher', bus)
class Watcher(dbus.service.Object):
    @dbus.service.method('org.kde.StatusNotifierWatcher', in_signature='s', out_signature='')
    def RegisterStatusNotifierItem(self, name):
        pass
watcher = Watcher(bus, '/StatusNotifierWatcher')
app.exec()
"""


def wait_for(check, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = check()
        if result:
            return result
        time.sleep(0.02)
    raise AssertionError("Serviço DBus não ficou pronto")


@pytest.fixture
def remote(tmp_path):
    daemon = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1'],
                              stdout=subprocess.PIPE, text=True)
    address = daemon.stdout.readline().strip()
    env = {**os.environ, 'DBUS_SESSION_BUS_ADDRESS': address,
           'QT_QPA_PLATFORM': 'offscreen', 'PYTHONPATH': str(ROOT / 'src')}
    env.pop('QT_NO_GLIB', None)
    bus = dbus.bus.BusConnection(address)
    processes = []
    log = (tmp_path / 'gui.log').open('w+')
    try:
        watcher = subprocess.Popen([sys.executable, '-c', WATCHER_CODE], env=env,
                                   stdout=log, stderr=log)
        processes.append(watcher)
        wait_for(lambda: bus.name_has_owner(WATCHER))
        tree = build_tree(tmp_path / 'sysfs', module='nexus_sense')
        command = [sys.executable, '-m', 'nexus_sense.gui.app', '--tray-only', '--root', str(tree)]
        app = subprocess.Popen(command, env=env, stdout=log, stderr=log)
        processes.append(app)
        name = f'{SNI}-{app.pid}-1'
        wait_for(lambda: bus.name_has_owner(name))
        item = bus.get_object(name, '/StatusNotifierItem')
        menu = dbus.Interface(bus.get_object(name, '/MenuBar'), MENU)
        yield bus, item, menu, tree, command, env, app
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
        bus.close()
        daemon.terminate()
        daemon.wait(timeout=5)
        log.close()


def layout(menu):
    revision, root = menu.GetLayout(0, -1, dbus.Array([], signature='s'))
    assert isinstance(revision, dbus.UInt32)
    assert isinstance(root, dbus.Struct)
    return {str(node[1].get('label', '')): (int(node[0]), node[1]) for node in root[2]}


def click(menu, ident):
    menu.Event(ident, 'clicked', dbus.Int32(0), dbus.UInt32(0))


def test_menu_publicado_e_reabre_depois_de_duas_acoes(remote):
    bus, item, menu, tree, *_ = remote
    path = item.Get(SNI, 'Menu', dbus_interface='org.freedesktop.DBus.Properties')
    assert isinstance(path, dbus.ObjectPath) and path == '/MenuBar'
    rows = layout(menu)
    assert {'Econômico', 'Silencioso', 'Equilibrado', 'Desempenho',
            'Ventoinha automática', 'Ventoinha no máximo', 'Abrir', 'Sair'} <= rows.keys()
    assert rows['Equilibrado'][1]['toggle-state'] == 1
    profile = next(tree.glob('sys/devices/platform/acer-wmi/platform-profile/*/profile'))
    click(menu, rows['Econômico'][0])
    assert profile.read_text().strip() == 'low-power'
    menu.AboutToShow(0)
    rows = layout(menu)
    assert rows['Econômico'][1]['toggle-state'] == 1
    click(menu, rows['Equilibrado'][0])
    assert profile.read_text().strip() == 'balanced'
    rows = layout(menu)
    assert rows['Equilibrado'][1]['toggle-state'] == 1
    fan = tree / 'sys/devices/platform/acer-wmi/nitro_sense/fan_speed'
    click(menu, rows['Ventoinha no máximo'][0])
    assert fan.read_text().strip() == '100,100'
    click(menu, layout(menu)['Ventoinha automática'][0])
    assert fan.read_text().strip() == '0,0'
    assert 'Abrir' in layout(menu)


def test_ids_estaveis_e_perfil_removido_nao_executa_outro_comando(remote):
    _, _, menu, tree, *_ = remote
    before = layout(menu)
    (tree / 'sys/class/power_supply/ACAD/online').write_text('0\n')
    after = layout(menu)
    assert 'Silencioso' not in after and 'Desempenho' not in after
    assert after['Abrir'][0] == before['Abrir'][0]
    with pytest.raises(dbus.exceptions.DBusException):
        click(menu, before['Silencioso'][0])
    assert 'Abrir' in layout(menu)


def test_scroll_clique_do_meio_e_instancia_unica(remote):
    bus, item, menu, tree, command, env, app = remote
    profile = next(tree.glob('sys/devices/platform/acer-wmi/platform-profile/*/profile'))
    item.Scroll(120, 'vertical', dbus_interface=SNI)
    assert profile.read_text().strip() == 'balanced-performance'
    item.SecondaryActivate(0, 0, dbus_interface=SNI)
    assert profile.read_text().strip() == 'balanced'
    second = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
    assert second.returncode == 0 and 'já havia uma instância' in second.stdout
    assert [str(n) for n in bus.list_names() if str(n).startswith(SNI + '-')] == [f'{SNI}-{app.pid}-1']
    assert 'Abrir' in layout(menu)


def test_propriedades_grupos_e_profundidade(remote):
    _, _, menu, *_ = remote
    rows = layout(menu)
    ident = rows['Abrir'][0]
    _, root = menu.GetLayout(0, 0, dbus.Array([], signature='s'))
    assert list(root[2]) == []
    group = menu.GetGroupProperties(dbus.Array([ident], signature='i'), ['label'])
    assert dict(group[0][1]) == {'label': 'Abrir'}
    assert menu.GetProperty(ident, 'label') == 'Abrir'
    updates, errors = menu.AboutToShowGroup(dbus.Array([0, 99999], signature='i'))
    assert list(errors) == [99999]
    errors = menu.EventGroup(dbus.Array([(99999, 'clicked', dbus.Int32(0), dbus.UInt32(0))], signature='(isvu)'))
    assert list(errors) == [99999]


@pytest.mark.parametrize('no_glib', [False, True])
def test_sem_host_ou_sem_glib_nao_deixa_sni_parcial(no_glib):
    code = """
from PySide6.QtCore import QCoreApplication
from nexus_sense.tray.sni import StatusNotifierItem, register
import dbus
app = QCoreApplication([])
item = StatusNotifierItem()
assert register(item) is False
assert not any(str(n).startswith('org.kde.StatusNotifierItem-') for n in dbus.SessionBus().list_names())
"""
    env = {**os.environ, 'PYTHONPATH': str(ROOT / 'src')}
    if no_glib:
        env['QT_NO_GLIB'] = '1'
    else:
        env.pop('QT_NO_GLIB', None)
    result = subprocess.run(['dbus-run-session', '--', sys.executable, '-c', code],
                            env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
