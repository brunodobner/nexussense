import os

from PySide6.QtWidgets import QWidget
from PySide6.QtCore import Signal

from nexus_sense.device import Controls
from nexus_sense.gui.poller import Poller
from nexus_sense.gui.window import Window
from nexus_sense.sysfs import Sysfs


def test_o_painel_atualiza_uma_vez_por_segundo(fake_root):
    """Eram dez. Medido em 2026-10-09 com a janela aberta: 44,6% de um
    nucleo, a maior parte em `nvidia-smi` chamado dez vezes por segundo.
    Temperatura nao muda nessa escala; a escolha por 1 Hz foi do usuario.
    Ver docs/plano-melhorias.md, decisao D3."""
    p = Poller(Sysfs(fake_root))
    assert p._timer.interval() == 1000


class SysfsContaVendor(Sysfs):
    """Conta quantos `vendor` foram lidos: e o rastro da varredura do PCI."""

    def __init__(self, root):
        super().__init__(root)
        self.vendors = 0

    def read(self, path):
        from pathlib import Path

        if Path(path).name == "vendor":
            self.vendors += 1
        return super().read(path)


def test_a_gpu_e_procurada_no_pci_uma_vez_so(fake_root):
    """Achar a dGPU e varrer /sys/bus/pci/devices inteiro lendo o vendor
    de cada dispositivo -- 1,0 ms medido, e era a cada passada. O
    endereco dela nao muda com a maquina ligada."""
    # Adormecida, para o teste nao chamar o nvidia-smi de verdade.
    caminho = fake_root / "sys/bus/pci/devices/0000:01:00.0/power/runtime_status"
    caminho.write_text("suspended\n")
    espiao = SysfsContaVendor(fake_root)
    p = Poller(espiao)

    for _ in range(3):
        amostra = p.read_now()

    assert amostra.gpu.asleep is True
    assert espiao.vendors == 1


def test_a_leitura_traz_ventoinhas_e_temperaturas(fake_root):
    amostra = Poller(Sysfs(fake_root)).read_now()
    assert amostra.fans == (2079, 1870)
    assert amostra.cpu_temp == 47.0


def test_a_amostra_nao_carrega_o_que_ninguem_exibe(fake_root):
    """As tres temperaturas do EC eram lidas a cada passada -- uma
    chamada WMI cada -- e nenhuma pagina as mostrava."""
    assert "acer_temps" not in Poller(Sysfs(fake_root)).read_now()._fields


def test_com_a_gpu_dormindo_a_amostra_diz_adormecida(fake_root):
    """E nao chama nvidia-smi. A guarda esta em telemetry.read_gpu; aqui
    so se confirma que o poller nao a contorna. Ver spec secao 10.2."""
    caminho = fake_root / "sys/bus/pci/devices/0000:01:00.0/power/runtime_status"
    caminho.write_text("suspended\n")
    amostra = Poller(Sysfs(fake_root)).read_now()
    assert amostra.gpu.asleep is True
    assert amostra.gpu.temperature is None


def isca_contadora(pasta, monkeypatch, resposta="45, 0 %"):
    """Um nvidia-smi falso na frente do PATH, que anota cada chamada.

    Devolve a funcao que conta as chamadas feitas ate agora."""
    isca = pasta / "isca-contadora"
    isca.mkdir()
    registro = pasta / "chamadas.log"
    (isca / "nvidia-smi").write_text(
        f"#!/bin/sh\necho x >> '{registro}'\necho '{resposta}'\n"
    )
    (isca / "nvidia-smi").chmod(0o755)
    monkeypatch.setenv("PATH", f"{isca}{os.pathsep}{os.environ['PATH']}")
    return lambda: len(registro.read_text().splitlines()) if registro.exists() else 0


def test_com_a_placa_ociosa_o_poller_para_de_chamar_o_nvidia_smi(
    fake_root, tmp_path, monkeypatch
):
    """A guarda de read_gpu evita acordar a placa, nao evita mante-la
    acordada. Medido em 2026-10-10: com a janela aberta a dGPU ficou 4 min
    12 s sem dormir, com um nvidia-smi por segundo renovando o prazo;
    fechada, dorme em 21 s. Depois de dez leituras seguidas com uso 0% o
    poller para de perguntar. Ver docs/estado.md, etapa 4b."""
    chamadas = isca_contadora(tmp_path, monkeypatch)
    p = Poller(Sysfs(fake_root))

    for _ in range(40):
        amostra = p.read_now()

    assert chamadas() == 10
    assert amostra.gpu.asleep is False
    assert amostra.gpu.idle is True
    assert amostra.gpu.temperature == 45.0


def test_com_a_placa_trabalhando_o_poller_sonda_toda_passada(
    fake_root, tmp_path, monkeypatch
):
    """Jogo rodando nunca e pausado: qualquer uso acima de 0% zera a
    contagem."""
    chamadas = isca_contadora(tmp_path, monkeypatch, resposta="68, 98 %")
    p = Poller(Sysfs(fake_root))

    for _ in range(25):
        amostra = p.read_now()

    assert chamadas() == 25
    assert amostra.gpu.idle is False
    assert amostra.gpu.utilization == 98


def test_arvore_vazia_devolve_amostra_vazia(tmp_path):
    amostra = Poller(Sysfs(tmp_path)).read_now()
    assert amostra.fans is None
    assert amostra.gpu is None


def test_o_poller_emite_enquanto_ligado(qtbot, fake_root):
    p = Poller(Sysfs(fake_root), interval_ms=10)
    p.start()
    try:
        with qtbot.waitSignal(p.sampled, timeout=2000) as capturado:
            pass
    finally:
        p.stop()
    assert capturado.args[0].fans == (2079, 1870)


def test_parar_desliga_de_verdade(qtbot, fake_root):
    p = Poller(Sysfs(fake_root), interval_ms=10)
    p.start()
    assert p.active is True
    p.stop()
    assert p.active is False


class PaginaComAmostra(QWidget):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.amostras = 0

    def has_content(self, state):
        return True

    def apply_state(self, state):
        pass

    def apply_sample(self, sample):
        self.amostras += 1


def test_a_telemetria_so_roda_com_a_janela_aberta(qtbot, fake_root):
    """A regra da spec secao 10.2: fechou, para. Um painel que continua
    sondando escondido gasta bateria para nao mostrar nada."""
    s = Sysfs(fake_root)
    j = Window(s, Controls(s), pages=(("a", "Painel", PaginaComAmostra()),))
    qtbot.addWidget(j)
    j.refresh()

    assert j.poller.active is False
    j.show()
    assert j.poller.active is True
    j.hide()
    assert j.poller.active is False


def test_a_amostra_chega_as_paginas_que_a_querem(qtbot, fake_root):
    s = Sysfs(fake_root)
    pagina = PaginaComAmostra()
    j = Window(s, Controls(s), pages=(("a", "Painel", pagina),))
    qtbot.addWidget(j)
    j.refresh()
    j.poller.sampled.emit(j.poller.read_now())
    assert pagina.amostras == 1
