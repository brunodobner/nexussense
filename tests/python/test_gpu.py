import subprocess

import pytest

from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import gpu_asleep, nvidia_device, read_gpu

from conftest import build_tree


class RunnerEspiao:
    """Substitui subprocess.run e registra se foi chamado."""

    def __init__(self, stdout="42, 7 %\n"):
        self.chamadas = []
        self._stdout = stdout

    def __call__(self, args, **kwargs):
        self.chamadas.append(args)
        return subprocess.CompletedProcess(args, 0, stdout=self._stdout, stderr="")


def adormece(root, bdf="0000:01:00.0"):
    caminho = root / "sys/bus/pci/devices" / bdf / "power/runtime_status"
    caminho.write_text("suspended\n")


def test_acha_a_dgpu_pelo_vendor_e_pela_classe(fake_root):
    assert nvidia_device(Sysfs(fake_root)) == "0000:01:00.0"


def test_sem_dgpu_nvidia_devolve_none(tmp_path):
    build_tree(tmp_path)
    vendor = tmp_path / "sys/bus/pci/devices/0000:01:00.0/vendor"
    vendor.write_text("0x8086\n")
    assert nvidia_device(Sysfs(tmp_path)) is None


def test_reconhece_a_gpu_acordada(fake_root):
    assert gpu_asleep(Sysfs(fake_root), "0000:01:00.0") is False


def test_reconhece_a_gpu_adormecida(fake_root):
    adormece(fake_root)
    assert gpu_asleep(Sysfs(fake_root), "0000:01:00.0") is True


def test_com_a_gpu_dormindo_nao_chama_nvidia_smi(fake_root):
    """A regra central: o painel nunca pode ser o motivo de a GPU acordar.
    nvidia-smi custa 18 ms e acorda a dGPU. Ver spec secao 10.2."""
    adormece(fake_root)
    espiao = RunnerEspiao()
    leitura = read_gpu(Sysfs(fake_root), runner=espiao)
    assert espiao.chamadas == []
    assert leitura.asleep is True
    assert leitura.temperature is None
    assert leitura.utilization is None


def test_com_a_gpu_acordada_sonda_normalmente(fake_root):
    espiao = RunnerEspiao("42, 7 %\n")
    leitura = read_gpu(Sysfs(fake_root), runner=espiao)
    assert len(espiao.chamadas) == 1
    assert espiao.chamadas[0][0] == "nvidia-smi"
    assert leitura.asleep is False
    assert leitura.temperature == pytest.approx(42.0)
    assert leitura.utilization == 7


def test_nvidia_smi_ausente_nao_derruba_a_leitura(fake_root):
    def explode(args, **kwargs):
        raise FileNotFoundError("nvidia-smi")

    leitura = read_gpu(Sysfs(fake_root), runner=explode)
    assert leitura.asleep is False
    assert leitura.temperature is None


def test_saida_inesperada_do_nvidia_smi_nao_derruba(fake_root):
    espiao = RunnerEspiao("erro qualquer\n")
    leitura = read_gpu(Sysfs(fake_root), runner=espiao)
    assert leitura.temperature is None


def test_sem_gpu_a_leitura_e_none(tmp_path):
    assert read_gpu(Sysfs(tmp_path)) is None
