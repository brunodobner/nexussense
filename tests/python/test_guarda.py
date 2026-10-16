"""O lado do agente no guarda da ventoinha: o aviso ao systemd e o registro.

O systemd de verdade fica de fora: o socket de notificacao aqui e um
datagrama que o proprio teste abre, e o registro vai para um tmp_path. A
parte do systemd -- WatchdogSec, ExecStopPost, RuntimeDirectory -- foi
provada em 2026-10-15 com units descartaveis (docs/plano-curva.md, secao 8).
"""

import os
import socket
import threading

import pytest

from conftest import build_tree
from nexus_sense import guarda
from nexus_sense.agent import Agent
from nexus_sense.sysfs import Sysfs


@pytest.fixture
def ouvinte(tmp_path):
    """Um socket como o do systemd, e o endereco que o agente recebe."""
    caminho = str(tmp_path / "notify")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    s.bind(caminho)
    s.settimeout(2)
    yield s, caminho
    s.close()


def recebe(s, n):
    return [s.recv(256).decode() for _ in range(n)]


# ─── o aviso ────────────────────────────────────────────────────────


def test_sem_socket_o_aviso_nao_faz_nada():
    assert guarda.notifica("READY=1", {}) is False


def test_o_aviso_chega_ao_socket(ouvinte):
    s, caminho = ouvinte
    assert guarda.notifica("WATCHDOG=1", {"NOTIFY_SOCKET": caminho}) is True
    assert recebe(s, 1) == ["WATCHDOG=1"]


def test_o_aviso_chega_pelo_namespace_abstrato():
    nome = f"nexus-sense-teste-{os.getpid()}"
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
        s.bind("\0" + nome)
        s.settimeout(2)
        assert guarda.notifica("READY=1", {"NOTIFY_SOCKET": "@" + nome}) is True
        assert s.recv(256) == b"READY=1"


def test_socket_que_sumiu_nao_derruba_quem_avisa(tmp_path):
    ambiente = {"NOTIFY_SOCKET": str(tmp_path / "nao-existe")}
    assert guarda.notifica("WATCHDOG=1", ambiente) is False


# ─── o registro ─────────────────────────────────────────────────────


def test_fora_da_unit_nao_ha_registro():
    assert guarda.caminho_do_registro({}) is None
    assert guarda.registra("0,0", "25,24", {}) is False


def test_o_registro_guarda_o_valor_de_antes_e_o_novo(tmp_path):
    ambiente = {"RUNTIME_DIRECTORY": str(tmp_path)}
    assert guarda.registra("0,0", "25,24", ambiente) is True
    assert (tmp_path / "ventoinha").read_text() == "0,0\n25,24\n"
    # Uma escrita nova troca o arquivo inteiro, e nao deixa temporario.
    assert guarda.registra("25,24", "35,37", ambiente) is True
    assert (tmp_path / "ventoinha").read_text() == "25,24\n35,37\n"
    assert sorted(os.listdir(tmp_path)) == ["ventoinha"]


def test_com_varias_pastas_o_registro_vai_para_a_primeira(tmp_path):
    ambiente = {"RUNTIME_DIRECTORY": f"{tmp_path}:{tmp_path}/outra"}
    assert guarda.caminho_do_registro(ambiente) == str(tmp_path / "ventoinha")


def test_registro_que_nao_grava_diz_que_nao_gravou(tmp_path):
    ambiente = {"RUNTIME_DIRECTORY": str(tmp_path / "nao-existe")}
    assert guarda.registra("0,0", "25,24", ambiente) is False


# ─── o registro visto da janela ─────────────────────────────────────


def test_a_janela_acha_o_registro_pela_sessao(tmp_path):
    ambiente = {"XDG_RUNTIME_DIR": str(tmp_path)}
    assert guarda.caminho_na_sessao(ambiente) == str(tmp_path / "nexus-sense/ventoinha")
    assert guarda.caminho_na_sessao({}) is None


def test_o_agente_no_ar_e_a_pasta_da_unit(tmp_path):
    ambiente = {"XDG_RUNTIME_DIR": str(tmp_path)}
    assert guarda.agente_no_ar(ambiente) is False
    (tmp_path / "nexus-sense").mkdir()
    assert guarda.agente_no_ar(ambiente) is True
    assert guarda.agente_no_ar({}) is False


def test_registrado_e_a_segunda_linha(tmp_path):
    ambiente = {"RUNTIME_DIRECTORY": str(tmp_path)}
    caminho = guarda.caminho_do_registro(ambiente)
    assert guarda.registrado(caminho) is None
    guarda.registra("0,0", "25,24", ambiente)
    assert guarda.registrado(caminho) == "25,24"
    assert guarda.registrado(None) is None


def test_a_janela_esquece_o_registro(tmp_path):
    ambiente = {"XDG_RUNTIME_DIR": str(tmp_path)}
    (tmp_path / "nexus-sense").mkdir()
    guarda.registra("0,0", "25,24", {"RUNTIME_DIRECTORY": str(tmp_path / "nexus-sense")})
    guarda.esquece(ambiente)
    assert not (tmp_path / "nexus-sense/ventoinha").exists()
    # Sem registro, ou fora de uma sessao, nao ha o que esquecer.
    guarda.esquece(ambiente)
    guarda.esquece({})


# ─── o agente avisa ─────────────────────────────────────────────────


def test_o_agente_avisa_que_subiu_e_a_cada_passada(tmp_path, ouvinte, monkeypatch):
    """READY uma vez, ao entrar no laco; WATCHDOG depois de cada passada.
    Sem o WATCHDOG, o WatchdogSec mataria um agente sadio."""
    s, caminho = ouvinte
    monkeypatch.setenv("NOTIFY_SOCKET", caminho)
    raiz = build_tree(tmp_path / "raiz")
    agente = Agent(Sysfs(raiz), tmp_path / "config.toml", interval=0.01)
    parar = threading.Event()
    passadas = []
    original = agente.tick

    def tick():
        passadas.append(1)
        original()
        if len(passadas) >= 3:
            parar.set()

    agente.tick = tick
    agente.run(parar)
    assert recebe(s, 4) == ["READY=1", "WATCHDOG=1", "WATCHDOG=1", "WATCHDOG=1"]


def test_passada_que_explode_ainda_avisa(tmp_path, ouvinte, monkeypatch, caplog):
    """Uma passada ruim e registrada e o laco segue: o agente esta vivo, e
    o watchdog nao e para isso."""
    s, caminho = ouvinte
    monkeypatch.setenv("NOTIFY_SOCKET", caminho)
    raiz = build_tree(tmp_path / "raiz")
    agente = Agent(Sysfs(raiz), tmp_path / "config.toml", interval=0.01)
    parar = threading.Event()

    def tick():
        parar.set()
        raise RuntimeError("passada ruim")

    agente.tick = tick
    agente.run(parar)
    assert recebe(s, 2) == ["READY=1", "WATCHDOG=1"]


def test_sem_systemd_o_agente_roda_igual(tmp_path):
    """Num terminal nao ha socket: o laco nao muda."""
    raiz = build_tree(tmp_path / "raiz")
    agente = Agent(Sysfs(raiz), tmp_path / "config.toml", interval=0.01)
    parar = threading.Event()
    agente.tick = parar.set
    agente.run(parar)


def test_socket_que_nao_responde_e_avisado_uma_vez(tmp_path, monkeypatch, caplog):
    """Com socket e sem conseguir avisar, o WatchdogSec mataria um agente
    sadio a cada poucos segundos: o journal tem de dizer por que."""
    monkeypatch.setenv("NOTIFY_SOCKET", str(tmp_path / "nao-existe"))
    raiz = build_tree(tmp_path / "raiz")
    agente = Agent(Sysfs(raiz), tmp_path / "config.toml", interval=0.01)
    parar = threading.Event()
    passadas = []

    def tick():
        passadas.append(1)
        if len(passadas) >= 3:
            parar.set()

    agente.tick = tick
    with caplog.at_level("WARNING"):
        agente.run(parar)
    avisos = [r for r in caplog.records if "avisar o systemd" in r.getMessage()]
    assert len(avisos) == 1
