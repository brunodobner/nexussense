"""Leitura de sensores.

Regra que atravessa o modulo inteiro: hwmon nunca pelo indice.

O numero em /sys/class/hwmon/hwmonN depende da ordem de carga dos
modulos e muda entre boots. Nesta maquina o sensor do acer e o hwmon5
hoje, e pode ser outro amanha. O acer se acha pelo dispositivo pai; os
demais, procurando pelo conteudo de 'name'. Ver spec secao 10.1.
"""

import subprocess
from typing import NamedTuple

PACKAGE_LABEL = "Package id 0"


def acer_hwmon(sysfs):
    """O sensor do acer-wmi, ancorado no dispositivo de plataforma."""
    base = sysfs.acer_base() / "hwmon"
    if not base.is_dir():
        return None
    for filho in sorted(base.iterdir()):
        if (filho / "name").is_file():
            return filho
    return None


def hwmon_by_name(sysfs, name):
    """Procura em /sys/class/hwmon pelo conteudo de 'name', nunca pelo numero."""
    base = sysfs.root / "sys/class/hwmon"
    if not base.is_dir():
        return None
    for filho in sorted(base.iterdir()):
        rotulo = filho / "name"
        try:
            if rotulo.read_text().strip() == name:
                return filho
        except OSError:
            continue
    return None


def fan_rpm(sysfs):
    """Rotacao real das duas ventoinhas, em rpm.

    Nao confundir com o atributo fan_speed do driver, que e o setpoint:
    ele devolve "0,0" para automatico. Ver spec secao 2.5.
    """
    hwmon = acer_hwmon(sysfs)
    if hwmon is None:
        return None
    try:
        return (
            int(sysfs.read(hwmon / "fan1_input")),
            int(sysfs.read(hwmon / "fan2_input")),
        )
    except (OSError, ValueError):
        return None


def acer_temperatures(sysfs):
    """As temperaturas do acer-wmi, em Celsius inteiros."""
    hwmon = acer_hwmon(sysfs)
    if hwmon is None:
        return ()
    valores = []
    for indice in range(1, 10):
        caminho = hwmon / f"temp{indice}_input"
        if not caminho.is_file():
            break
        try:
            valores.append(int(sysfs.read(caminho)) // 1000)
        except (OSError, ValueError):
            break
    return tuple(valores)


def cpu_package_temp(sysfs):
    """Temperatura do pacote da CPU, em Celsius com uma casa.

    Achada pelo rotulo 'Package id 0', nao pelo numero: temp1 costuma ser
    o pacote, mas a garantia esta no rotulo.
    """
    hwmon = hwmon_by_name(sysfs, "coretemp")
    if hwmon is None:
        return None
    for rotulo in sorted(hwmon.glob("temp*_label")):
        try:
            if rotulo.read_text().strip() != PACKAGE_LABEL:
                continue
            entrada = rotulo.with_name(rotulo.name.replace("_label", "_input"))
            return int(entrada.read_text().strip()) / 1000
        except (OSError, ValueError):
            continue
    return None


NVIDIA_VENDOR = "0x10de"
# 0x0300xx e VGA, 0x0302xx e "3D controller" -- as dGPUs de laptop
# aparecem numa das duas conforme o modo do Optimus.
GPU_CLASS_PREFIXES = ("0x0300", "0x0302")

NVIDIA_SMI_QUERY = "temperature.gpu,utilization.gpu"


class GpuReading(NamedTuple):
    """asleep=True significa que nao sondamos, nao que nao ha GPU."""

    asleep: bool
    temperature: float | None
    utilization: int | None


def nvidia_device(sysfs):
    """BDF da dGPU NVIDIA, ex. '0000:01:00.0'. None se nao houver."""
    base = sysfs.root / "sys/bus/pci/devices"
    if not base.is_dir():
        return None
    for filho in sorted(base.iterdir()):
        try:
            if sysfs.read(filho / "vendor") != NVIDIA_VENDOR:
                continue
            classe = sysfs.read(filho / "class")
        except OSError:
            continue
        if classe.startswith(GPU_CLASS_PREFIXES):
            return filho.name
    return None


def gpu_asleep(sysfs, bdf):
    """True quando a gerencia de energia ja suspendeu a GPU.

    Ler este arquivo custa praticamente nada e NAO acorda a GPU. E o
    contrario de nvidia-smi, que custa 18 ms e acorda.
    """
    caminho = sysfs.root / "sys/bus/pci/devices" / bdf / "power/runtime_status"
    try:
        return sysfs.read(caminho) == "suspended"
    except OSError:
        return False


def read_gpu(sysfs, runner=subprocess.run):
    """Le a GPU sem nunca acorda-la.

    A ordem importa e e a razao de ser desta funcao: primeiro o
    runtime_status, que e um arquivo; so se ele disser 'active' e que o
    nvidia-smi entra. Um laco de 2 s sondando sem essa guarda manteria a
    dGPU acesa permanentemente, gastando bateria para exibir um numero.
    Ver spec secao 10.2.
    """
    bdf = nvidia_device(sysfs)
    if bdf is None:
        return None

    if gpu_asleep(sysfs, bdf):
        return GpuReading(asleep=True, temperature=None, utilization=None)

    try:
        saida = runner(
            ["nvidia-smi", f"--query-gpu={NVIDIA_SMI_QUERY}", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return GpuReading(asleep=False, temperature=None, utilization=None)

    try:
        bruto_temp, bruto_uso = saida.stdout.split(",")
        temperatura = float(bruto_temp.strip())
        utilizacao = int(bruto_uso.strip().rstrip(" %"))
    except (AttributeError, ValueError):
        return GpuReading(asleep=False, temperature=None, utilization=None)

    return GpuReading(asleep=False, temperature=temperatura, utilization=utilizacao)


# Como no AC_NAMES do sysfs.py: o nome varia por firmware. Nesta maquina
# e BAT1, mas BAT0 e o mais comum por ai.
BATTERY_NAMES = ("BAT0", "BAT1", "BATT", "CMB0")


class BatteryReading(NamedTuple):
    capacity: int | None
    status: str | None


def battery(sysfs):
    """Carga e estado da bateria. None quando nao ha bateria nenhuma."""
    base = sysfs.root / "sys/class/power_supply"
    for nome in BATTERY_NAMES:
        pasta = base / nome
        if not (pasta / "capacity").is_file():
            continue
        try:
            carga = int(sysfs.read(pasta / "capacity"))
        except (OSError, ValueError):
            carga = None
        try:
            estado = sysfs.read(pasta / "status")
        except OSError:
            estado = None
        return BatteryReading(capacity=carga, status=estado)
    return None


def cpu_name(sysfs):
    """O 'model name' do primeiro nucleo, como o /proc/cpuinfo o escreve."""
    try:
        for linha in (sysfs.root / "proc/cpuinfo").read_text().splitlines():
            if linha.startswith("model name"):
                return linha.split(":", 1)[1].strip()
    except OSError:
        return None
    return None


def cpu_times(sysfs):
    """(ocioso, total) em jiffies, da primeira linha de /proc/stat."""
    try:
        primeira = (sysfs.root / "proc/stat").read_text().splitlines()[0]
    except (OSError, IndexError):
        return None
    campos = primeira.split()
    if campos[0] != "cpu" or len(campos) < 6:
        return None
    try:
        numeros = [int(c) for c in campos[1:]]
    except ValueError:
        return None
    # user nice system idle iowait irq softirq ... -- ocioso e idle+iowait
    return numeros[3] + numeros[4], sum(numeros)


def cpu_usage(anterior, atual):
    """Percentual entre duas leituras de cpu_times.

    None na primeira leitura, porque nao ha com o que comparar. Inventar
    um numero ali seria mentir sobre a unica coisa que este campo diz.
    """
    if anterior is None or atual is None:
        return None
    ocioso = atual[0] - anterior[0]
    total = atual[1] - anterior[1]
    if total <= 0:
        return None
    return max(0.0, min(100.0, 100.0 * (1.0 - ocioso / total)))


# A base de nomes do PCI, sob a raiz configuravel como todo o resto.
# Duas localizacoes porque as distribuicoes discordam.
PCI_IDS = ("usr/share/hwdata/pci.ids", "usr/share/misc/pci.ids")


def _pci_lookup(sysfs, vendor, device):
    """Traduz um par de IDs para o nome do modelo, ou None.

    Formato do pci.ids: fornecedor na margem, dispositivo com uma
    tabulacao, subdispositivo com duas. Le em fluxo e para no primeiro
    acerto -- o arquivo tem ~1,6 MB e nao vale carregar inteiro.
    """
    for relativo in PCI_IDS:
        caminho = sysfs.root / relativo
        if not caminho.is_file():
            continue
        try:
            with caminho.open(encoding="utf-8", errors="replace") as arquivo:
                dentro = False
                for linha in arquivo:
                    if not linha.strip() or linha.startswith("#"):
                        continue
                    if not linha.startswith("\t"):
                        # Ja passamos do fornecedor certo sem achar: para.
                        if dentro:
                            return None
                        dentro = linha[:4].lower() == vendor
                    elif dentro and not linha.startswith("\t\t"):
                        if linha[1:5].lower() == device:
                            return linha[5:].strip()
        except OSError:
            return None
        return None
    return None


def _nome_comercial(bruto):
    """Do que o pci.ids diz para o que cabe no cartao.

    "AD107M [GeForce RTX 4050 Max-Q / Mobile]" vira
    "GeForce RTX 4050 Max-Q": fora o codinome do die, que nao diz nada a
    quem le, e o sufixo "/ Mobile", que num laptop e obvio.
    """
    if "[" in bruto and "]" in bruto:
        bruto = bruto[bruto.index("[") + 1 : bruto.rindex("]")]
    return bruto.split(" / ")[0].strip()


def gpu_name(sysfs):
    """Modelo da dGPU. None se nao houver GPU.

    **Nao acorda a placa.** Os dois atributos saem da configuracao que o
    kernel leu na enumeracao e mantem em cache, sem transacao no
    barramento -- o contrario do nvidia-smi, que abre o dispositivo do
    driver. Ver spec secao 10.2 e interface.md secao 4.2.

    Sem a base de nomes, ou com um ID que ela nao conheca, devolve o
    identificador cru: esconder atras de travessao apagaria informacao
    que existe.
    """
    bdf = nvidia_device(sysfs)
    if bdf is None:
        return None

    base = sysfs.root / "sys/bus/pci/devices" / bdf
    try:
        vendor = sysfs.read(base / "vendor").removeprefix("0x").lower()
        device = sysfs.read(base / "device").removeprefix("0x").lower()
    except OSError:
        return None

    bruto = _pci_lookup(sysfs, vendor, device)
    return _nome_comercial(bruto) if bruto else f"{vendor}:{device}"
