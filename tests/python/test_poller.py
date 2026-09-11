from PySide6.QtWidgets import QWidget
from PySide6.QtCore import Signal

from nexus_sense.device import Controls
from nexus_sense.gui.poller import Poller
from nexus_sense.gui.window import Window
from nexus_sense.sysfs import Sysfs


def test_o_painel_atualiza_a_cada_decimo_de_segundo(fake_root):
    p = Poller(Sysfs(fake_root))
    assert p._timer.interval() == 100


def test_a_leitura_traz_ventoinhas_e_temperaturas(fake_root):
    amostra = Poller(Sysfs(fake_root)).read_now()
    assert amostra.fans == (2079, 1870)
    assert amostra.acer_temps == (25, 43, 43)
    assert amostra.cpu_temp == 47.0


def test_com_a_gpu_dormindo_a_amostra_diz_adormecida(fake_root):
    """E nao chama nvidia-smi. A guarda esta em telemetry.read_gpu; aqui
    so se confirma que o poller nao a contorna. Ver spec secao 10.2."""
    caminho = fake_root / "sys/bus/pci/devices/0000:01:00.0/power/runtime_status"
    caminho.write_text("suspended\n")
    amostra = Poller(Sysfs(fake_root)).read_now()
    assert amostra.gpu.asleep is True
    assert amostra.gpu.temperature is None


def test_arvore_vazia_devolve_amostra_vazia(tmp_path):
    amostra = Poller(Sysfs(tmp_path)).read_now()
    assert amostra.fans is None
    assert amostra.acer_temps == ()
    assert amostra.gpu is None


def test_o_poller_emite_enquanto_ligado(qtbot, fake_root):
    p = Poller(Sysfs(fake_root), interval_ms=10)
    p.start()
    try:
        with qtbot.waitSignal(p.sampled, timeout=2000) as capturado:
            pass
    finally:
        p.stop()
    assert capturado.args[0].fans == (2079, 1870)


def test_parar_desliga_de_verdade(qtbot, fake_root):
    p = Poller(Sysfs(fake_root), interval_ms=10)
    p.start()
    assert p.active is True
    p.stop()
    assert p.active is False


class PaginaComAmostra(QWidget):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.amostras = 0

    def has_content(self, state):
        return True

    def apply_state(self, state):
        pass

    def apply_sample(self, sample):
        self.amostras += 1


def test_a_telemetria_so_roda_com_a_janela_aberta(qtbot, fake_root):
    """A regra da spec secao 10.2: fechou, para. Um painel que continua
    sondando escondido gasta bateria para nao mostrar nada."""
    s = Sysfs(fake_root)
    j = Window(s, Controls(s), pages=(("a", "Painel", PaginaComAmostra()),))
    qtbot.addWidget(j)
    j.refresh()

    assert j.poller.active is False
    j.show()
    assert j.poller.active is True
    j.hide()
    assert j.poller.active is False


def test_a_amostra_chega_as_paginas_que_a_querem(qtbot, fake_root):
    s = Sysfs(fake_root)
    pagina = PaginaComAmostra()
    j = Window(s, Controls(s), pages=(("a", "Painel", pagina),))
    qtbot.addWidget(j)
    j.refresh()
    j.poller.sampled.emit(j.poller.read_now())
    assert pagina.amostras == 1
