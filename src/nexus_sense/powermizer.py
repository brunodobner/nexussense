"""Pedido PowerMizer com conexão NVML persistente, pertencente ao agente.

ABI do nvml.h distribuído com nvidia-settings 610.57.04. Nesse driver a
consulta é por cliente: subprocessos não mantêm nem observam nosso pedido.
"""

import ctypes as c


class Modes(c.Structure):
    _fields_ = [("currentMode", c.c_uint), ("mode", c.c_uint),
                ("supportedPowerMizerModes", c.c_uint)]


class PowerMizerError(RuntimeError):
    pass


class PowerMizer:
    def __init__(self, loader=c.CDLL):
        self.loader = loader
        self.lib = None
        self.handle = c.c_void_p()
        self.previous = None

    def _check(self, result):
        if result:
            raise PowerMizerError(f"NVML retornou erro {result}")

    def _open(self):
        if self.lib is not None:
            return
        try:
            lib = self.loader("libnvidia-ml.so.1")
            signatures = {
                "nvmlInit_v2": [], "nvmlShutdown": [],
                "nvmlDeviceGetHandleByIndex_v2": [c.c_uint, c.POINTER(c.c_void_p)],
                "nvmlDeviceGetPowerMizerMode_v1": [c.c_void_p, c.POINTER(Modes)],
                "nvmlDeviceSetPowerMizerMode_v1": [c.c_void_p, c.POINTER(Modes)],
            }
            for name, args in signatures.items():
                function = getattr(lib, name)
                function.argtypes = args
                function.restype = c.c_int
        except (OSError, AttributeError) as error:
            raise PowerMizerError("driver sem API NVML de PowerMizer") from error
        self._check(lib.nvmlInit_v2())
        self.lib = lib
        try:
            self._check(lib.nvmlDeviceGetHandleByIndex_v2(0, c.byref(self.handle)))
            modes = self._read()
            if not modes.supportedPowerMizerModes & (1 << 1):
                raise PowerMizerError("GPU não oferece preferência por desempenho máximo")
            self.previous = modes.currentMode
        except Exception:
            self.lib = None
            lib.nvmlShutdown()
            raise

    def _read(self):
        modes = Modes()
        self._check(self.lib.nvmlDeviceGetPowerMizerMode_v1(self.handle, c.byref(modes)))
        return modes

    def _set(self, value):
        modes = Modes(mode=value)
        self._check(self.lib.nvmlDeviceSetPowerMizerMode_v1(self.handle, c.byref(modes)))
        actual = self._read().currentMode
        if actual != value:
            raise PowerMizerError(f"PowerMizer solicitado={value}, confirmado={actual}")

    def hold(self):
        self._open()
        if self._read().currentMode != 1:
            self._set(1)
        return 1

    def close(self):
        if self.lib is None:
            return
        lib = self.lib
        try:
            if self.previous is not None:
                self._set(self.previous)
        finally:
            self.lib = None
            self.previous = None
            self._check(lib.nvmlShutdown())
