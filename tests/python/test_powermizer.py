import ctypes as c

import pytest

from nexus_sense.powermizer import Modes, PowerMizer, PowerMizerError


class Function:
    def __init__(self, call):
        self.call = call

    def __call__(self, *args):
        return self.call(*args)


class Library:
    def __init__(self, accept=True):
        self.current = 0
        self.opens = 0
        self.closes = 0
        self.accept = accept
        self.last_set = None
        self.nvmlInit_v2 = Function(self.init)
        self.nvmlShutdown = Function(self.shutdown)
        self.nvmlDeviceGetHandleByIndex_v2 = Function(lambda *_: 0)
        self.nvmlDeviceGetPowerMizerMode_v1 = Function(self.get)
        self.nvmlDeviceSetPowerMizerMode_v1 = Function(self.set)

    def init(self):
        self.opens += 1
        return 0

    def shutdown(self):
        self.closes += 1
        self.current = 0  # reproduce o pedido perdido ao encerrar o cliente
        return 0

    def get(self, handle, pointer):
        modes = c.cast(pointer, c.POINTER(Modes)).contents
        modes.currentMode = self.current
        modes.supportedPowerMizerModes = 7
        return 0

    def set(self, handle, pointer):
        self.last_set = c.cast(pointer, c.POINTER(Modes)).contents.mode
        if self.accept:
            self.current = c.cast(pointer, c.POINTER(Modes)).contents.mode
        return 0


def test_pedido_permanece_no_mesmo_cliente_entre_passadas():
    lib = Library()
    gpu = PowerMizer(loader=lambda _: lib)
    for _ in range(5):
        assert gpu.hold() == 1
        assert lib.current == 1
    assert (lib.opens, lib.closes) == (1, 0)
    gpu.close()
    assert lib.current == 0
    assert lib.closes == 1
    gpu.close()
    assert lib.closes == 1


def test_reconectar_abre_novo_pedido_e_restauracao_preserva_valor_anterior():
    lib = Library()
    lib.current = 2
    gpu = PowerMizer(loader=lambda _: lib)
    gpu.hold()
    assert gpu.previous == 2
    gpu.close()
    assert lib.last_set == 2
    gpu.hold()
    assert (lib.opens, lib.closes, lib.current) == (2, 1, 1)
    gpu.close()


def test_sucesso_da_escrita_sem_confirmacao_e_erro():
    lib = Library(accept=False)
    gpu = PowerMizer(loader=lambda _: lib)
    with pytest.raises(PowerMizerError, match="confirmado=0"):
        gpu.hold()
    gpu.close()


def test_inativo_nao_carrega_nvml_nem_acorda_gpu():
    def forbidden(_):
        raise AssertionError("não deve carregar")
    gpu = PowerMizer(loader=forbidden)
    gpu.close()


def test_ausencia_da_api_vira_erro_claro():
    gpu = PowerMizer(loader=lambda _: object())
    with pytest.raises(PowerMizerError, match="sem API"):
        gpu.hold()
