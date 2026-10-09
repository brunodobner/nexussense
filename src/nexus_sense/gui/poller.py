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

# Uma atualizacao por segundo. Eram dez, e medido com a janela aberta
# isso custava 44,6% de um nucleo -- a maior parte em `nvidia-smi`, que
# leva 34 ms e era chamado a cada passada. Temperatura e rotacao nao
# mudam nessa escala. Ver docs/plano-melhorias.md, decisao D3.
INTERVALO_PADRAO = 1000  # ms

_NAO_PROCURADA = object()


class Sample(NamedTuple):
    fans: tuple | None
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

        # O endereco PCI da dGPU, achado na primeira passada. Procura-lo
        # e varrer o barramento inteiro, e ele nao muda com a maquina
        # ligada. None quando nao ha placa.
        self._gpu_bdf = _NAO_PROCURADA

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
        if self._gpu_bdf is _NAO_PROCURADA:
            self._gpu_bdf = telemetry.nvidia_device(self.sysfs)
        gpu = None
        if self._gpu_bdf is not None:
            gpu = telemetry.read_gpu(self.sysfs, bdf=self._gpu_bdf)
        return Sample(
            fans=telemetry.fan_rpm(self.sysfs),
            cpu_temp=telemetry.cpu_package_temp(self.sysfs),
            gpu=gpu,
            battery=telemetry.battery(self.sysfs),
            cpu_usage=uso,
        )

    def _passada(self):
        self.sampled.emit(self.read_now())
