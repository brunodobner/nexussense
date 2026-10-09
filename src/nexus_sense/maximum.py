"""Modo composto de desempenho máximo, acima dos perfis do firmware."""

import dataclasses
import subprocess

from . import ppd
from .config import default_path, load, save
from .device import WriteError
from .powermizer import PowerMizerError

THERMAL_PROFILE = "balanced-performance"
PPD_PROFILE = "performance"


def _set(args, description, runner):
    result = ppd.run(args, runner)
    if result is None or result.returncode != 0:
        detail = (result.stderr or "").strip() if result is not None else "indisponível"
        return f"{description}: {detail or 'comando recusado'}"
    return None


class MaximumMode:
    """Ativa, restaura e mantém as partes do quinto modo."""

    def __init__(self, controls, config_path=None, runner=subprocess.run, gpu=None):
        self.gpu = gpu
        self.controls = controls
        self.config_path = config_path or default_path()
        self.runner = runner

    def config(self):
        return load(self.config_path)

    def requested(self):
        return self.config().maximum_mode

    def active(self, on_ac):
        return self.requested() and on_ac is True

    def enable(self, state):
        if state.on_ac is not True:
            return ("Desempenho máximo só fica disponível na tomada.",)
        if THERMAL_PROFILE not in state.available:
            return ("O firmware não oferece o perfil térmico necessário.",)
        if not state.profile_writable or "fan_speed" not in state.writable:
            return ("Sem permissão para aplicar perfil e ventoinhas automáticas.",)

        current = self.config()
        if not current.maximum_mode:
            current = dataclasses.replace(
                current,
                maximum_mode=True,
                maximum_saved_profile=state.profile,
                maximum_saved_ppd=ppd.active_profile(self.runner),
                maximum_saved_powermizer=None,
            )

        # Ventoinhas automáticas fazem parte do modo aprovado.
        self.controls.set_fan_speed(0, 0)
        self.controls.set_profile(THERMAL_PROFILE)
        save(current, self.config_path)
        return self.enforce_runtime(current, active=True)

    def disable(self, profile=None):
        current = self.config()
        target = profile or current.maximum_saved_profile
        disabled = dataclasses.replace(
            current,
            maximum_mode=False,
            maximum_saved_profile=None,
            maximum_saved_ppd=None,
            maximum_saved_powermizer=None,
        )
        # Desliga a intenção antes de restaurar para o agente não reaplicar.
        save(disabled, self.config_path)
        errors = list(self.enforce_runtime(current, active=False))
        if target:
            try:
                self.controls.set_profile(target)
            except WriteError as error:
                errors.append(error.message)
        return tuple(errors)

    def enforce_runtime(self, config, *, active):
        errors = []
        wanted_ppd = PPD_PROFILE if active else config.maximum_saved_ppd

        if wanted_ppd and ppd.active_profile(self.runner) != wanted_ppd:
            error = _set(
                ppd.set_argv(wanted_ppd),
                "não foi possível ajustar a CPU",
                self.runner,
            )
            if error:
                errors.append(error)

        # Só o agente recebe o cliente persistente. GUI/tray salvam intenção.
        if self.gpu is not None:
            try:
                if active:
                    self.gpu.hold()
                else:
                    self.gpu.close()
            except PowerMizerError as error:
                errors.append(f"não foi possível ajustar a GPU: {error}")
        return tuple(errors)
