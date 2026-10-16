"""O agente e a suspensao: o watchdog alargado antes de dormir, e o que o
firmware desfaz reaplicado ao acordar.

O logind e o systemd ficam de fora: o busctl e o systemd-inhibit sao
processos de mentira, e o relogio do sono e injetado. A prova com a maquina
de verdade e o E-C5 (tests/hardware/ensaio-termico.sh ec5).
"""

import io
import json
import logging
import threading

import pytest

from conftest import build_tree
from nexus_sense import sono
from nexus_sense.agent import Agent
from nexus_sense.config import Config, save
from nexus_sense.sysfs import Sysfs


class Processo:
    """Um Popen de mentira. O do busctl entrega as linhas dadas e acaba."""

    def __init__(self, argv, linhas=(), eventos=None):
        self.argv = argv
        self.stdout = io.StringIO("".join(linhas))
        self.vivo = True
        self.eventos = eventos if eventos is not None else []

    def poll(self):
        return None if self.vivo else 0

    def terminate(self):
        if self.vivo:
            self.eventos.append(("solta", self.argv[0]))
        self.vivo = False

    def wait(self, timeout=None):
        return 0

    def kill(self):
        self.vivo = False


def sinal(dormir):
    return json.dumps({"type": "b", "data": [dormir]}) + "\n"


def roda(linhas):
    """Uma volta do fio do sono com estes sinais. Devolve o que aconteceu,
    na ordem."""
    eventos = []
    processos = []

    def executa(argv, **_):
        p = Processo(argv, linhas if argv[0] == "busctl" else (), eventos)
        processos.append(p)
        eventos.append(("abre", argv[0]))
        return p

    parar = threading.Event()

    def espera(_):
        parar.set()  # o busctl acabou as linhas: encerra o laco

    s = sono.Sono(
        lambda m: eventos.append(("avisa", m)) or True,
        6_000_000,
        lambda: eventos.append(("dormir",)),
        lambda: eventos.append(("acordou",)),
        executa=executa,
        espera=espera,
    )
    s._parar = parar
    s._laco()
    return eventos, processos


def test_os_comandos():
    assert sono.comando_espera()[:4] == ["busctl", "--system", "--json=short", "wait"]
    assert sono.comando_espera()[-4:] == list(sono.LOGIND)
    assert "--mode=delay" in sono.comando_bloqueio()
    assert "--what=sleep" in sono.comando_bloqueio()


@pytest.mark.parametrize(
    "linha, esperado",
    [(sinal(True), True), (sinal(False), False), ("lixo\n", None),
     ('{"type":"s","data":["x"]}\n', None), ('{"data":[true,false]}\n', None)],
)
def test_le_o_sinal(linha, esperado):
    assert sono.le_sinal(linha) is esperado


def test_antes_de_dormir_alarga_o_watchdog_e_so_depois_solta_o_bloqueio():
    eventos, processos = roda([sinal(True)])
    bloqueio = processos[0]
    assert bloqueio.argv[0] == "systemd-inhibit"
    i_alarga = eventos.index(("avisa", f"WATCHDOG_USEC={sono.DORMINDO_USEC}"))
    i_dormir = eventos.index(("dormir",))
    i_solta = eventos.index(("solta", "systemd-inhibit"))
    assert i_alarga < i_dormir < i_solta
    # O bloqueio saiu: o logind pode suspender.
    assert not bloqueio.vivo


def test_ao_acordar_devolve_o_watchdog_avisa_e_bloqueia_de_novo():
    eventos, processos = roda([sinal(True), sinal(False)])
    depois = eventos[eventos.index(("dormir",)) + 1:]
    assert ("avisa", "WATCHDOG_USEC=6000000") in depois
    assert ("avisa", "WATCHDOG=1") in depois
    assert ("acordou",) in depois
    # Um bloqueio novo para a proxima suspensao.
    assert [p.argv[0] for p in processos].count("systemd-inhibit") == 2


def test_sem_busctl_o_fio_avisa_uma_vez_e_nao_morre(caplog):
    parar = threading.Event()
    voltas = []

    def executa(argv, **_):
        if argv[0] == "busctl":
            raise FileNotFoundError("busctl")
        return Processo(argv)

    def espera(_):
        voltas.append(1)
        if len(voltas) >= 3:
            parar.set()

    s = sono.Sono(lambda m: True, 6_000_000, lambda: None, lambda: None,
                  executa=executa, espera=espera)
    s._parar = parar
    with caplog.at_level(logging.WARNING):
        s._laco()
    assert len(voltas) == 3
    assert sum("esperar a suspensão" in r.getMessage() for r in caplog.records) == 1


# ─── o agente ao acordar ────────────────────────────────────────────


@pytest.fixture
def unit(tmp_path, monkeypatch):
    pasta = tmp_path / "run"
    pasta.mkdir()
    monkeypatch.setenv("RUNTIME_DIRECTORY", str(pasta))
    return pasta


def perfil_de(raiz):
    return (raiz / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile").read_text().strip()


def poe_perfil(raiz, valor):
    (raiz / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile").write_text(f"{valor}\n")


def test_ao_acordar_devolve_o_perfil_que_o_firmware_trocou(tmp_path, caplog):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    a = Agent(Sysfs(raiz), tmp_path / "config.toml")
    a.tick()
    a._vai_dormir()
    poe_perfil(raiz, "balanced")          # o firmware, na volta
    a._acordou.set()
    with caplog.at_level(logging.INFO):
        a.tick()
    assert perfil_de(raiz) == "balanced-performance"
    assert any("devolvido balanced-performance" in r.getMessage() for r in caplog.records)


def test_sem_dormir_um_perfil_trocado_e_escolha_de_alguem(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    a = Agent(Sysfs(raiz), tmp_path / "config.toml")
    a.tick()
    poe_perfil(raiz, "balanced")          # a janela
    a.tick()
    assert perfil_de(raiz) == "balanced"


def test_o_relogio_que_salta_conta_como_acordar(tmp_path):
    """Sem o aviso do logind, a diferenca entre o relogio de boot e o
    monotonico salta o tempo dormido."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    a = Agent(Sysfs(raiz), tmp_path / "config.toml")
    relogio = [10.0]
    a._relogio_sono = lambda: relogio[0]
    a.tick()
    a._vai_dormir()
    poe_perfil(raiz, "balanced")
    relogio[0] = 40.0                     # dormiu 30 s
    a.tick()
    assert perfil_de(raiz) == "balanced-performance"


def test_ao_acordar_a_curva_reescreve_o_mesmo_manual(tmp_path, unit, monkeypatch):
    """O firmware larga o manual e fan_speed segue dizendo o valor: so
    escrever de novo o reaplica."""
    raiz = build_tree(tmp_path / "raiz", acer_temps=(45000, 0, 40000))
    caminho = tmp_path / "config.toml"
    save(Config(fan_curve=True), caminho)
    a = Agent(Sysfs(raiz), caminho)
    escritas = []
    original = a._controls.set_fan_speed
    monkeypatch.setattr(a._controls, "set_fan_speed", lambda c, g: (escritas.append((c, g)), original(c, g)))
    a.tick()
    a.tick()
    assert escritas == [(25, 24)]
    a._vai_dormir()
    a._acordou.set()
    a.tick()
    assert escritas == [(25, 24), (25, 24)]
    a.tick()
    assert escritas == [(25, 24), (25, 24)]


def test_na_bateria_ao_acordar_nao_devolve_o_perfil_da_tomada(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    a = Agent(Sysfs(raiz), tmp_path / "config.toml")
    a.tick()
    a._vai_dormir()
    (raiz / "sys/class/power_supply/ACAD/online").write_text("0\n")
    poe_perfil(raiz, "balanced")
    a._acordou.set()
    a.tick()
    assert perfil_de(raiz) == "balanced"
