"""Liga os gestos da bandeja aos controles.

Ritmo proprio, mais lento que o da janela, e leitura barata: so hwmon,
nunca a GPU. Sao 0,23 ms a cada 5 s. Um nvidia-smi aqui manteria a dGPU
acordada o tempo todo para exibir um numero que ninguem esta olhando.
Ver spec secao 10.2.
"""

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtGui import QGuiApplication

from .. import telemetry
from ..device import WriteError, read_basic
from ..gui.poller import Sample
from ..gui.style import is_dark
from ..maximum import MaximumMode
from .sni import icon_name, scroll_target, tooltip_text

INTERVALO_BANDEJA = 5000  # ms


class TrayController(QObject):
    state_refreshed = Signal()
    open_requested = Signal()
    quit_requested = Signal()

    def __init__(self, sysfs, controls, item, parent=None, maximum=None):
        super().__init__(parent)
        self.sysfs = sysfs
        self.controls = controls
        self.item = item
        self.state = None
        self.previous_profile = None
        self.maximum = maximum or MaximumMode(controls)
        self.maximum_active = False

        item.scrolled.connect(self._rolou)
        item.activated.connect(self.open_requested.emit)
        item.secondary.connect(self._alterna)

        self._timer = QTimer(self)
        self._timer.setInterval(INTERVALO_BANDEJA)
        self._timer.timeout.connect(self.refresh)

    @property
    def active(self):
        return self._timer.isActive()

    def start(self):
        if not self._timer.isActive():
            self._timer.start()
            self.refresh()

    def stop(self):
        self._timer.stop()

    def refresh(self):
        """Relê o barato e repinta o icone e o tooltip.

        `read_basic` e nao `read_state`: o icone quer perfil e escolhas,
        o tooltip quer rotacao e temperatura. Nenhum dos dois olha os
        atributos do grupo sense, e isto aqui roda a cada 5 s.
        """
        self.state = read_basic(self.sysfs)
        self.maximum_active = self.maximum.active(self.state.on_ac)
        amostra = Sample(
            fans=telemetry.fan_rpm(self.sysfs),
            acer_temps=(),
            cpu_temp=telemetry.cpu_package_temp(self.sysfs),
            gpu=None,          # de proposito: a bandeja nao acorda a GPU
            battery=None,
            cpu_usage=None,    # nao interessa ao tooltip, e evita ler /proc
        )
        self.item.set_icon(
            icon_name(
                self.state.profile,
                self.state.choices,
                self._painel_escuro(),
                maximum=self.maximum_active,
            )
        )
        self.item.set_tooltip(
            tooltip_text(self.state, amostra, maximum=self.maximum_active)
        )

        self.state_refreshed.emit()

    def _painel_escuro(self):
        """O painel costuma seguir o tema da sessao, e e o que temos.

        Ler o tema do painel em si exigiria falar com o Plasma; a paleta
        do app segue o mesmo tema do sistema e acerta na pratica.
        """
        app = QGuiApplication.instance()
        if app is None:
            return True
        return is_dark(app.palette())

    # ------------------------------------------------------------ gestos

    def _rolou(self, delta, orientation):
        if self.state is None:
            self.refresh()
        atual = self.state.profile
        if self.maximum_active:
            if delta < 0:
                self.apply_maximum(False)
            return
        if (
            delta > 0
            and self.state.on_ac is True
            and atual == "balanced-performance"
        ):
            self.apply_maximum(True)
            return
        destino = scroll_target(atual, self.state.choices, self.state.on_ac, delta)
        if destino == atual:
            # Bateu no limite. Nao escrever e o comportamento certo: uma
            # escrita que falharia daria erro sem nada para o usuario fazer.
            return
        self.apply_profile(destino)

    def _alterna(self):
        if self.previous_profile is None:
            return
        self.apply_profile(self.previous_profile)

    def apply_profile(self, profile):
        """Escreve o perfil e guarda o anterior. Publico: o menu usa."""
        anterior = self.state.profile
        try:
            if self.maximum.requested():
                self.maximum.disable(profile)
            else:
                self.controls.set_profile(profile)
        except WriteError:
            # Sem janela aberta nao ha onde mostrar frase. Relê e segue: a
            # proxima passada mostra o estado real no icone e no tooltip.
            self.refresh()
            return
        self.previous_profile = anterior
        self.refresh()

    def apply_maximum(self, enabled=None):
        """Ativa o quinto modo; público porque menu e scroll usam."""
        if self.state is None:
            self.refresh()
        wanted = not self.maximum.requested() if enabled is None else enabled
        try:
            if wanted:
                self.maximum.enable(self.state)
            else:
                self.maximum.disable()
        except (WriteError, OSError):
            pass
        self.refresh()

    def apply_fan_speed(self, cpu, gpu):
        """Uma recusa do firmware não encerra o processamento do menu."""
        try:
            self.controls.set_fan_speed(cpu, gpu)
        except WriteError:
            pass
        self.refresh()
