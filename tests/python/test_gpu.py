import shutil
import subprocess
from pathlib import Path

import pytest

from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import (
    ESPERA_ENTRE_TESTES,
    OCIOSA_APOS,
    PAUSA_MAXIMA,
    GpuProbe,
    gpu_asleep,
    nvidia_device,
    read_gpu,
)

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


def test_o_nvidia_smi_que_a_suite_enxerga_e_a_isca(tmp_path_factory):
    """Rodar os testes nao pode acordar a dGPU de quem os roda. Medido em
    2026-10-09: a suite chamava o nvidia-smi de verdade 35 vezes por
    rodada, por todo teste que monta a arvore padrao -- nela a GPU esta
    'active' -- sem passar um runner. Ver armadilha 20."""
    achado = shutil.which("nvidia-smi")
    assert achado is not None
    assert Path(achado).is_relative_to(tmp_path_factory.getbasetemp())


def test_sem_runner_a_leitura_vem_da_isca(fake_root):
    """O caminho de producao inteiro -- subprocess de verdade, PATH de
    verdade -- com a mesma resposta em qualquer maquina: nesta, que tem
    a placa, e num CI, que nao tem."""
    leitura = read_gpu(Sysfs(fake_root))
    assert leitura.asleep is False
    assert leitura.temperature == pytest.approx(11.0)
    assert leitura.utilization == 1


# ------------------------------------------- a sonda que deixa a placa dormir
#
# Medido em 2026-10-10 (docs/estado.md, etapa 4b): um nvidia-smi por segundo
# numa placa acordada renova o prazo e ela nunca dorme. Sem ninguem
# perguntando, dorme em 7 a 21 s.

BDF = "0000:01:00.0"
OCIOSA = "45, 0 %\n"


class Relogio:
    """time.monotonic de mentira: so anda quando o teste manda."""

    def __init__(self):
        self.agora = 1000.0

    def __call__(self):
        return self.agora


def acorda(root, bdf=BDF):
    caminho = root / "sys/bus/pci/devices" / bdf / "power/runtime_status"
    caminho.write_text("active\n")


def passadas(sonda, relogio, n):
    """n leituras a 1 Hz, como o poller faz. Devolve a ultima."""
    for _ in range(n):
        leitura = sonda.read()
        relogio.agora += 1
    return leitura


def monta(root, stdout=OCIOSA):
    espiao = RunnerEspiao(stdout)
    relogio = Relogio()
    return GpuProbe(Sysfs(root), BDF, runner=espiao, clock=relogio), espiao, relogio


def test_as_constantes_cobrem_o_que_foi_medido():
    """A pausa tem de passar dos 21,0 s que a placa leva para dormir
    depois de acordada (4 de 4 em 2026-10-10); senao a sonda conclui que
    outro programa a segura e volta a perguntar."""
    assert OCIOSA_APOS == 10
    assert PAUSA_MAXIMA > 21.0
    assert ESPERA_ENTRE_TESTES >= 10 * PAUSA_MAXIMA


def test_ociosa_por_dez_leituras_a_sonda_para_de_perguntar(fake_root):
    sonda, espiao, relogio = monta(fake_root)

    leitura = passadas(sonda, relogio, OCIOSA_APOS)
    assert len(espiao.chamadas) == OCIOSA_APOS
    assert leitura.idle is False

    leitura = passadas(sonda, relogio, 15)
    assert len(espiao.chamadas) == OCIOSA_APOS


def test_na_pausa_a_leitura_traz_o_ultimo_valor_e_diz_ociosa(fake_root):
    """Opcao A, do usuario: o cartao mostra o ultimo valor com o selo, em
    vez de travessao."""
    sonda, espiao, relogio = monta(fake_root)
    leitura = passadas(sonda, relogio, OCIOSA_APOS + 5)
    assert leitura.idle is True
    assert leitura.asleep is False
    assert leitura.temperature == pytest.approx(45.0)
    assert leitura.utilization == 0


def test_uso_acima_de_zero_nunca_pausa(fake_root):
    sonda, espiao, relogio = monta(fake_root, "60, 35 %\n")
    leitura = passadas(sonda, relogio, 100)
    assert len(espiao.chamadas) == 100
    assert leitura.idle is False


def test_uma_leitura_com_uso_zera_a_contagem(fake_root):
    sonda, espiao, relogio = monta(fake_root)
    passadas(sonda, relogio, OCIOSA_APOS - 1)
    espiao._stdout = "50, 3 %\n"
    passadas(sonda, relogio, 1)
    espiao._stdout = OCIOSA
    leitura = passadas(sonda, relogio, OCIOSA_APOS - 1)
    assert len(espiao.chamadas) == 2 * OCIOSA_APOS - 1
    assert leitura.idle is False

    # a decima seguida fecha a conta, e dai em diante ninguem pergunta
    passadas(sonda, relogio, 1)
    passadas(sonda, relogio, 5)
    assert len(espiao.chamadas) == 2 * OCIOSA_APOS


def test_dormiu_na_pausa_vira_adormecida(fake_root):
    """O caso que a sonda existe para permitir: era so a janela."""
    sonda, espiao, relogio = monta(fake_root)
    passadas(sonda, relogio, OCIOSA_APOS + 7)
    adormece(fake_root)

    leitura = passadas(sonda, relogio, 3)

    assert leitura.asleep is True
    assert leitura.idle is False
    assert leitura.temperature is None
    assert len(espiao.chamadas) == OCIOSA_APOS


def test_acordou_depois_de_dormir_a_sonda_pergunta_de_novo(fake_root):
    sonda, espiao, relogio = monta(fake_root)
    passadas(sonda, relogio, OCIOSA_APOS + 7)
    adormece(fake_root)
    passadas(sonda, relogio, 3)
    acorda(fake_root)
    espiao._stdout = "52, 40 %\n"

    leitura = passadas(sonda, relogio, 1)

    assert len(espiao.chamadas) == OCIOSA_APOS + 1
    assert leitura.idle is False
    assert leitura.utilization == 40


def test_placa_que_nao_dorme_na_pausa_volta_a_ser_sondada(fake_root):
    """Outro programa a segura -- nesta maquina, o coolercontrold. Calar
    a janela nao muda nada, entao ela volta a mostrar numero vivo."""
    sonda, espiao, relogio = monta(fake_root)
    passadas(sonda, relogio, OCIOSA_APOS)
    inicio_da_pausa = relogio.agora - 1

    while relogio.agora - inicio_da_pausa < PAUSA_MAXIMA:
        assert passadas(sonda, relogio, 1).idle is True
    assert len(espiao.chamadas) == OCIOSA_APOS

    leitura = passadas(sonda, relogio, 1)
    assert len(espiao.chamadas) == OCIOSA_APOS + 1
    assert leitura.idle is False


def test_o_teste_so_se_repete_depois_de_cinco_minutos_ociosa(fake_root):
    """Com outro programa segurando a placa o tempo todo, a pausa aparece
    a cada cinco minutos, nao a cada dez segundos."""
    sonda, espiao, relogio = monta(fake_root)
    passadas(sonda, relogio, OCIOSA_APOS)
    passadas(sonda, relogio, int(PAUSA_MAXIMA))      # a pausa inteira
    antes = len(espiao.chamadas)
    retomada = relogio.agora

    while relogio.agora - retomada < ESPERA_ENTRE_TESTES:
        assert passadas(sonda, relogio, 1).idle is False
    assert len(espiao.chamadas) - antes == int(ESPERA_ENTRE_TESTES)

    passadas(sonda, relogio, 1)           # esta ainda pergunta, e abre a pausa
    depois = len(espiao.chamadas)
    assert passadas(sonda, relogio, 5).idle is True
    assert len(espiao.chamadas) == depois


def test_depois_de_trabalhar_e_parar_o_teste_nao_espera(fake_root):
    """O jogo fechou: quem segurava a placa pode ter ido embora. Esperar
    cinco minutos para conferir seria manter a placa acesa a toa."""
    sonda, espiao, relogio = monta(fake_root)
    passadas(sonda, relogio, OCIOSA_APOS)
    passadas(sonda, relogio, int(PAUSA_MAXIMA) + 1)   # pausa, e a retomada
    espiao._stdout = "70, 95 %\n"
    passadas(sonda, relogio, 20)
    espiao._stdout = OCIOSA
    antes = len(espiao.chamadas)

    passadas(sonda, relogio, OCIOSA_APOS)
    leitura = passadas(sonda, relogio, 5)

    assert len(espiao.chamadas) - antes == OCIOSA_APOS
    assert leitura.idle is True


def test_nvidia_smi_falhando_nunca_conta_como_ociosa(fake_root):
    """Sem numero nao ha como dizer que a placa esta parada."""
    chamadas = []

    def explode(args, **kwargs):
        chamadas.append(args)
        raise FileNotFoundError("nvidia-smi")

    relogio = Relogio()
    sonda = GpuProbe(Sysfs(fake_root), BDF, runner=explode, clock=relogio)
    leitura = passadas(sonda, relogio, 40)
    assert len(chamadas) == 40
    assert leitura.idle is False
    assert leitura.temperature is None
