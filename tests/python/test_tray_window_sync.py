import subprocess

from nexus_sense.device import Controls
from nexus_sense.sysfs import Sysfs
from nexus_sense.maximum import MaximumMode
from nexus_sense.gui.window import Window
from nexus_sense.gui.app import _connect_state
from nexus_sense.tray.controller import TrayController
from nexus_sense.tray.sni import StatusNotifierItem


def test_tray_atualiza_janela_e_janela_atualiza_tray(qtbot, fake_root):
    sysfs = Sysfs(fake_root)
    controls = Controls(sysfs)
    def runner(args, **kwargs):
        return subprocess.CompletedProcess(args, 0, "performance", "")
    maximum = MaximumMode(controls, runner=runner)
    window = Window(sysfs, controls)
    qtbot.addWidget(window)
    # Visivel de proposito: a bandeja so repinta a janela a vista. Oculta,
    # ela nao gasta uma chamada WMI por passada. Ver test_leituras_wmi.py.
    window.show()
    qtbot.waitExposed(window)
    pages = {name: page for name, _, page in window.pages}
    pages["desempenho"].maximum = maximum
    tray = TrayController(sysfs, controls, StatusNotifierItem(), maximum=maximum)
    _connect_state(tray, window)
    tray.refresh()
    tray.apply_maximum(True)
    assert pages["desempenho"].buttons["maximum"].isChecked()
    assert not pages["desempenho"].buttons["balanced-performance"].isChecked()
    assert "Desempenho máximo" in pages["painel"].header.text()
    tray.apply_profile("balanced-performance")
    assert not pages["desempenho"].buttons["maximum"].isChecked()
    assert pages["desempenho"].buttons["balanced-performance"].isChecked()
    pages["desempenho"].buttons["maximum"].click()
    assert tray.maximum_active
    assert "max-" in tray.item.icon
