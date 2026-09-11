"""A sondagem de sensores da janela.

Duas regras, as duas da spec secao 10.2:

  - so roda com a janela visivel. Quem liga e desliga e a Window, no
    showEvent e no hideEvent;
  - nunca acorda a dGPU. A guarda mora em telemetry.read_gpu, e este
    modulo nao a contorna.
"""

from typing import NamedTuple

from PySide6.QtCore import QObject, QTimer, Signal

from .. import telemetry

INTERVALO_PADRAO = 100  # ms; dez atualizações por segundo no painel


class Sample(NamedTuple):
    fans: tuple | None
    acer_temps: tuple
    cpu_temp: float | None
    gpu: object | None      # telemetry.GpuReading ou None
    battery: object | None   # telemetry.BatteryReading ou None
    cpu_usage: float | None


class Poller(QObject):
    sampled = Signal(object)

    def __init__(self, sysfs, interval_ms=INTERVALO_PADRAO, parent=None):
        super().__init__(parent)
        self.sysfs = sysfs
        self._timer = QTimer(self)
        self._timer.setInterval(interval_ms)
        self._timer.timeout.connect(self._passada)

        # Uso de CPU e diferenca entre duas leituras de /proc/stat, entao
        # a passada anterior precisa sobreviver ate a proxima.
        self._cpu_anterior = None

    @property
    def active(self):
        return self._timer.isActive()

    def start(self):
        if not self._timer.isActive():
            self._timer.start()
            self._passada()      # nao esperar o primeiro intervalo

    def stop(self):
        self._timer.stop()

    def read_now(self):
        """Uma leitura sincrona. Usada pelo start e pelos testes."""
        cpu_agora = telemetry.cpu_times(self.sysfs)
        uso = telemetry.cpu_usage(self._cpu_anterior, cpu_agora)
        self._cpu_anterior = cpu_agora
        return Sample(
            fans=telemetry.fan_rpm(self.sysfs),
            acer_temps=telemetry.acer_temperatures(self.sysfs),
            cpu_temp=telemetry.cpu_package_temp(self.sysfs),
            gpu=telemetry.read_gpu(self.sysfs),
            battery=telemetry.battery(self.sysfs),
            cpu_usage=uso,
        )

    def _passada(self):
        self.sampled.emit(self.read_now())
