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


@pytest.fixture
def bus_address():
    """Um dbus-daemon so do teste, sem ninguem dentro. Devolve o endereco."""
    daemon = subprocess.Popen(['dbus-daemon', '--session', '--nofork', '--print-address=1'],
                              stdout=subprocess.PIPE, text=True)
    try:
        yield daemon.stdout.readline().strip()
    finally:
        daemon.terminate()
        daemon.wait(timeout=5)


def private_env(address):
    env = {**os.environ, 'DBUS_SESSION_BUS_ADDRESS': address,
           'QT_QPA_PLATFORM': 'offscreen', 'PYTHONPATH': str(ROOT / 'src')}
    env.pop('QT_NO_GLIB', None)
    return env


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


TRAY_CODE = """
import sys
from PySide6.QtCore import QTimer
from PySide6.QtDBus import QDBusConnection
from PySide6.QtWidgets import QApplication
from nexus_sense.device import Controls
from nexus_sense.sysfs import Sysfs
from nexus_sense.tray import build_tray
app = QApplication([])
print('barramento:', QDBusConnection.sessionBus().isConnected(), flush=True)
s = Sysfs(sys.argv[1])
controlador, modo = build_tray(s, Controls(s))
print('bandeja:', modo, flush=True)
QTimer.singleShot(700, app.quit)
app.exec()
print('depois do laco', flush=True)
"""


def test_barramento_sem_watcher_cai_na_reserva_e_o_processo_segue(bus_address, tmp_path):
    """Em subprocesso porque era o processo inteiro que morria: publish()
    fechava a conexao privada, e a libdbus encerra com _exit(1) quem perde
    o barramento -- no laco de eventos, depois de register() ja ter
    devolvido False. Dentro do pytest levaria a suite junto.

    A primeira linha da saida e a guarda contra passar por vacuo: sem ela
    um endereco errado viraria o caso "sem barramento", que e outro."""
    bus = dbus.bus.BusConnection(bus_address)
    try:
        assert not bus.name_has_owner(WATCHER)
    finally:
        bus.close()
    tree = build_tree(tmp_path / 'sysfs', module='nexus_sense')
    result = subprocess.run([sys.executable, '-c', TRAY_CODE, str(tree)], env=private_env(bus_address),
                            capture_output=True, text=True, timeout=20)
    lines = result.stdout.splitlines()
    assert lines[:1] == ['barramento: True'], result.stderr
    assert result.returncode == 0, result.stderr
    assert lines[1] in ('bandeja: qsystemtrayicon', 'bandeja: nenhuma')
    assert lines[2:] == ['depois do laco']
    assert 'Traceback' not in result.stderr


# Um watcher que anota quem se registrou, uma linha por chamada. O objeto
# entra antes do nome, como no kded6: quem reage ao nome ja encontra o
# metodo. `Reacquire` solta o nome e o pede de novo, sem o processo morrer.
# Com 'refuse', recusa o registro.
RECORDING_WATCHER_CODE = """
import sys
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from PySide6.QtCore import QCoreApplication
app = QCoreApplication([])
bus = dbus.SessionBus(private=True, mainloop=DBusGMainLoop())
class Watcher(dbus.service.Object):
    @dbus.service.method('org.kde.StatusNotifierWatcher', in_signature='s', out_signature='')
    def RegisterStatusNotifierItem(self, name):
        with open(sys.argv[1], 'a') as record:
            record.write(name + chr(10))
        if sys.argv[2:] == ['refuse']:
            raise dbus.exceptions.DBusException('recusado de proposito', name='test.Watcher.Refused')
    @dbus.service.method('test.Watcher', in_signature='', out_signature='')
    def Reacquire(self):
        bus.release_name('org.kde.StatusNotifierWatcher')
        bus.request_name('org.kde.StatusNotifierWatcher')
watcher = Watcher(bus, '/StatusNotifierWatcher')
bus.request_name('org.kde.StatusNotifierWatcher')
app.exec()
"""


def registered(record):
    return record.read_text().split() if record.exists() else []


@pytest.fixture
def stage(bus_address, tmp_path):
    """Barramento privado, e um jeito de por processos nele que a fixture
    encerra no fim. Devolve (bus, spawn, log)."""
    env = private_env(bus_address)
    bus = dbus.bus.BusConnection(bus_address)
    processes = []
    log = tmp_path / 'stage.log'
    handle = log.open('w')

    def spawn(*args):
        process = subprocess.Popen([sys.executable, *map(str, args)], env=env, stdout=handle, stderr=handle)
        processes.append(process)
        return process

    try:
        yield bus, spawn, log
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
        bus.close()
        handle.close()


def tray_on(stage, tmp_path, *watcher_args):
    """Sobe um watcher que anota em tmp_path/'first' e, depois dele, o
    aplicativo. Devolve (watcher, app, nome do item)."""
    bus, spawn, _ = stage
    watcher = spawn('-c', RECORDING_WATCHER_CODE, tmp_path / 'first', *watcher_args)
    wait_for(lambda: bus.name_has_owner(WATCHER))
    tree = build_tree(tmp_path / 'sysfs', module='nexus_sense')
    app = spawn('-m', 'nexus_sense.gui.app', '--tray-only', '--root', tree)
    name = f'{SNI}-{app.pid}-1'
    wait_for(lambda: registered(tmp_path / 'first') == [name])
    return watcher, app, name


def test_o_item_se_registra_de_novo_quando_o_watcher_reinicia(stage, tmp_path):
    """O watcher guarda a lista de itens na memoria. Quando reinicia nasce
    com ela vazia, e o item que nao se apresenta de novo some da bandeja
    ate o aplicativo reiniciar."""
    bus, spawn, log = stage
    watcher, app, name = tray_on(stage, tmp_path)
    watcher.terminate()
    watcher.wait(timeout=5)
    wait_for(lambda: not bus.name_has_owner(WATCHER))
    spawn('-c', RECORDING_WATCHER_CODE, tmp_path / 'second')
    wait_for(lambda: registered(tmp_path / 'second'))
    time.sleep(0.3)     # uma vez so: um segundo registro chegaria aqui
    assert registered(tmp_path / 'second') == [name]
    assert registered(tmp_path / 'first') == [name]
    # Nem ao watcher que saiu, nem a quem mais entrou no barramento: uma
    # chamada dessas volta com erro, e o erro vai para o log.
    assert 'recusou o registro' not in log.read_text()
    assert app.poll() is None


def test_o_item_se_registra_de_novo_quando_o_mesmo_dono_retoma_o_nome(stage, tmp_path):
    """Um watcher pode soltar o nome e pedi-lo de novo sem morrer, e o
    dono novo e o mesmo de antes. Quem perguntasse "o dono mudou?" em vez
    de "ha dono?" concluiria que nada aconteceu."""
    bus, _, log = stage
    _, app, name = tray_on(stage, tmp_path)
    owner = bus.get_name_owner(WATCHER)
    bus.call_blocking(owner, '/StatusNotifierWatcher', 'test.Watcher', 'Reacquire', '', ())
    assert bus.get_name_owner(WATCHER) == owner
    wait_for(lambda: len(registered(tmp_path / 'first')) > 1)
    time.sleep(0.3)
    assert registered(tmp_path / 'first') == [name, name]
    assert 'recusou o registro' not in log.read_text()
    assert app.poll() is None


def test_watcher_que_volta_e_recusa_nao_derruba_o_aplicativo(stage, tmp_path):
    bus, spawn, log = stage
    watcher, app, name = tray_on(stage, tmp_path)
    watcher.terminate()
    watcher.wait(timeout=5)
    wait_for(lambda: not bus.name_has_owner(WATCHER))
    spawn('-c', RECORDING_WATCHER_CODE, tmp_path / 'second', 'refuse')
    wait_for(lambda: registered(tmp_path / 'second') == [name])
    wait_for(lambda: 'recusou o registro' in log.read_text())
    assert app.poll() is None
    assert bus.name_has_owner(name)


def test_sem_barramento_o_aplicativo_abre_em_vez_de_se_dar_por_repetido(tmp_path):
    """Sem barramento de sessao nao ha nome de instancia unica a disputar.
    O aplicativo lia a recusa do registro como "ja ha outra aberta", pedia
    a ela que aparecesse e saia com 0 -- antes de chegar a bandeja, e sem
    abrir nada. O endereco e o da fixture autouse do conftest, que nao
    existe."""
    address = os.environ['DBUS_SESSION_BUS_ADDRESS']
    assert not os.path.exists(address.removeprefix('unix:path='))
    tree = build_tree(tmp_path / 'sysfs', module='nexus_sense')
    env = {**private_env(address), 'PYTHONUNBUFFERED': '1'}
    log = tmp_path / 'app.log'
    with log.open('w') as handle:
        app = subprocess.Popen([sys.executable, '-m', 'nexus_sense.gui.app', '--tray-only', '--root', str(tree)],
                               env=env, stdout=handle, stderr=handle)
        try:
            wait_for(lambda: app.poll() is not None or 'bandeja: ' in log.read_text())
            assert 'já havia uma instância' not in log.read_text()
            assert app.poll() is None, log.read_text()
            assert log.read_text().splitlines()[-1] in ('bandeja: qsystemtrayicon', 'bandeja: nenhuma')
            time.sleep(0.7)     # o laco de eventos roda, e o processo segue
            assert app.poll() is None, log.read_text()
        finally:
            if app.poll() is None:
                app.terminate()
            app.wait(timeout=5)
