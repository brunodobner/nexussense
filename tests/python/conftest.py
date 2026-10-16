"""Arvore sysfs falsa, para testar sem hardware, sem root e sem laptop Acer.

O indice do hwmon e deslocavel de proposito (hwmon_offset): o codigo de
producao nunca pode depender do numero, so do nome ou do dispositivo pai.
Ver spec secao 10.1.
"""

import os

# Qt sem servidor grafico. Precisa vir antes de qualquer import de
# PySide6, inclusive os indiretos que os testes fazem: o QPA e escolhido
# na primeira vez que o Qt e carregado, e nao muda depois.
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import pytest

CHOICES_PADRAO = "low-power quiet balanced balanced-performance"

ATRIBUTOS_SENSE = {
    "fan_speed": "0,0",
    "battery_limiter": "1",
    "usb_charging": "0",
    "backlight_timeout": "0",
    "battery_calibration": "0",
    "version": "25.701",
}


@pytest.fixture(autouse=True)
def config_isolada(monkeypatch, tmp_path):
    """Testes nunca leem nem alteram a configuração real do usuário."""
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))


@pytest.fixture(autouse=True)
def sem_barramento_de_sessao(monkeypatch, tmp_path):
    """Testes nunca falam com o barramento de sessao de quem os roda.

    Medido em 2026-10-09 com um barramento isca no lugar: uma conexao por
    rodada, pedindo o nome org.kde.StatusNotifierItem-<pid>-1. Na sessao
    de verdade isso e um item registrado na bandeja do Plasma a cada
    suite. O endereco abaixo nao existe, e nao existe do mesmo jeito num
    CI: quem precisa de barramento sobe o seu e passa o endereco adiante,
    como a fixture `remote` de test_tray_dbus.py."""
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", f"unix:path={tmp_path}/sem-barramento")


@pytest.fixture(autouse=True)
def fora_da_unit(monkeypatch, tmp_path_factory):
    """Testes nunca falam com o systemd de quem os roda. Rodada de dentro de
    uma unit -- um CI, um servico --, a suite herdaria o NOTIFY_SOCKET, e o
    agente dos testes avisaria o gerenciador de verdade (armadilha 30). Quem
    precisa de socket abre o seu, como os testes de test_guarda.py."""
    for nome in ("NOTIFY_SOCKET", "RUNTIME_DIRECTORY", "WATCHDOG_USEC", "WATCHDOG_PID"):
        monkeypatch.delenv(nome, raising=False)
    # Nem com o agente de quem os roda: a janela le o registro da curva em
    # $XDG_RUNTIME_DIR/nexus-sense, e o agente de verdade escreve la.
    # Fora do tmp_path do teste, que alguns conferem arquivo por arquivo.
    sessao = tmp_path_factory.mktemp("xdg-run")
    sessao.chmod(0o700)
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(sessao))


# Resposta fixa da isca. 11 graus e um valor que placa nenhuma devolve em
# uso, e os espioes dos testes respondem outra coisa: quando um teste ve
# este par, sabe que passou pelo PATH e nao por um runner injetado.
ISCA_NVIDIA_SMI = "11, 1 %"


@pytest.fixture(scope="session")
def pasta_da_isca(tmp_path_factory):
    pasta = tmp_path_factory.mktemp("isca")
    isca = pasta / "nvidia-smi"
    isca.write_text(f"#!/bin/sh\necho '{ISCA_NVIDIA_SMI}'\n")
    isca.chmod(0o755)
    return pasta


@pytest.fixture(autouse=True)
def nvidia_smi_e_isca(monkeypatch, pasta_da_isca):
    """Testes nunca chamam o nvidia-smi de verdade: ele acorda a dGPU
    (armadilha 20). A arvore padrao traz a placa 'active', entao todo
    teste que le a GPU sem injetar um runner chegaria ate ele -- eram 35
    por rodada. A isca na frente do PATH responde no lugar, e responde o
    mesmo numa maquina sem a placa."""
    monkeypatch.setenv("PATH", f"{pasta_da_isca}{os.pathsep}{os.environ.get('PATH', '')}")


def build_tree(
    root,
    *,
    on_ac=True,
    profile="balanced",
    choices=CHOICES_PADRAO,
    hwmon_offset=0,
    sense="nitro_sense",
    module="linuwu_sense",
    fans=(2079, 1870),
    acer_temps=(25000, 43000, 43000),
    cpu_package=47000,
):
    """Monta uma arvore ANV15-52 completa sob `root` e devolve `root`."""

    def escreve(caminho, conteudo):
        caminho.parent.mkdir(parents=True, exist_ok=True)
        caminho.write_text(f"{conteudo}\n")

    acer = root / "sys/devices/platform/acer-wmi"

    for nome, valor in ATRIBUTOS_SENSE.items():
        escreve(acer / sense / nome, valor)

    escreve(acer / "platform-profile/platform-profile-0/profile", profile)
    escreve(acer / "platform-profile/platform-profile-0/choices", choices)
    escreve(acer / "platform-profile/platform-profile-0/name", "acer-wmi")

    if module:
        (root / "sys/module" / module).mkdir(parents=True, exist_ok=True)

    # DMI e o que a spec chama de "modelo" no Diagnostico.
    escreve(root / "sys/class/dmi/id/product_name", "Nitro ANV15-52")
    escreve(root / "sys/class/dmi/id/sys_vendor", "Acer")

    # Parametros do modulo em vigor. 'N' e como o kernel imprime um bool
    # desligado; e assim que este esta nesta maquina.
    if module:
        for parametro in ("nitro_v4", "predator_v4", "enable_all"):
            escreve(root / "sys/module" / module / "parameters" / parametro, "N")

    # hwmon do acer, ancorado no dispositivo
    n_acer = hwmon_offset + 5
    h_acer = acer / f"hwmon/hwmon{n_acer}"
    escreve(h_acer / "name", "acer")
    escreve(h_acer / "fan1_input", fans[0])
    escreve(h_acer / "fan2_input", fans[1])
    # Os rotulos sao os do driver, lidos na maquina: quem quer o canal da
    # GPU o acha por eles, nao pelo numero.
    rotulos = ("CPU", "GPU", "External 2")
    for i, t in enumerate(acer_temps, start=1):
        escreve(h_acer / f"temp{i}_input", t)
        if i <= len(rotulos):
            escreve(h_acer / f"temp{i}_label", rotulos[i - 1])
    escreve(h_acer / "fan1_label", "CPU")
    escreve(h_acer / "fan2_label", "GPU")

    # /sys/class/hwmon: links por indice, na ordem embaralhada
    classe = root / "sys/class/hwmon"
    classe.mkdir(parents=True, exist_ok=True)
    (classe / f"hwmon{n_acer}").symlink_to(h_acer)

    n_core = hwmon_offset + 6
    h_core = root / f"sys/devices/platform/coretemp.0/hwmon/hwmon{n_core}"
    escreve(h_core / "name", "coretemp")
    escreve(h_core / "temp1_label", "Package id 0")
    escreve(h_core / "temp1_input", cpu_package)
    escreve(h_core / "temp2_label", "Core 0")
    escreve(h_core / "temp2_input", cpu_package - 2000)
    (classe / f"hwmon{n_core}").symlink_to(h_core)

    # /proc por baixo da mesma raiz: uso e modelo da CPU saem daqui, e a
    # regra de nao abrir caminho absoluto continua valendo.
    escreve(root / "proc/cpuinfo", "processor\t: 0\nmodel name\t: Intel(R) Core(TM) i5-13420H")
    escreve(root / "proc/stat", "cpu  100 0 50 850 0 0 0 0 0 0")

    # fonte de energia
    escreve(root / "sys/class/power_supply/ACAD/online", 1 if on_ac else 0)
    escreve(root / "sys/class/power_supply/BAT1/capacity", 80)
    escreve(root / "sys/class/power_supply/BAT1/status", "Not charging")

    # dGPU NVIDIA
    gpu = root / "sys/bus/pci/devices/0000:01:00.0"
    escreve(gpu / "vendor", "0x10de")
    escreve(gpu / "class", "0x030000")
    escreve(gpu / "power/runtime_status", "active")
    escreve(gpu / "power/control", "auto")
    escreve(gpu / "device", "0x28a1")

    # A base de nomes do PCI, sob a mesma raiz. Ler os IDs do sysfs nao
    # acorda a GPU: vem do cache da enumeracao, sem transacao no
    # barramento. Ver INTERFACE.md secao 4.2.
    escreve(
        root / "usr/share/hwdata/pci.ids",
        "10de  NVIDIA Corporation\n"
        "\t28a1  AD107M [GeForce RTX 4050 Max-Q / Mobile]\n"
        "\t2860  AD107M [GeForce RTX 4060 Max-Q]\n"
        "8086  Intel Corporation\n"
        "\ta7a8  Raptor Lake-P [UHD Graphics]",
    )

    return root


@pytest.fixture
def fake_root(tmp_path):
    """Arvore ANV15-52 padrao: na tomada, perfil balanced, quatro escolhas."""
    return build_tree(tmp_path)
