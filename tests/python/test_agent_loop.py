import logging
import os

import pytest
import json
import subprocess

from nexus_sense.agent import Agent
from nexus_sense.config import Config, load, save
from nexus_sense.device import read_state
from nexus_sense.sysfs import Sysfs
from nexus_sense.maximum import MaximumMode

from conftest import build_tree


def liga(tmp_path):
    caminho = tmp_path / "config.toml"
    save(Config(auto_switch=True), caminho)
    return caminho


def desconecta(root):
    (root / "sys/class/power_supply/ACAD/online").write_text("0\n")


def conecta(root):
    (root / "sys/class/power_supply/ACAD/online").write_text("1\n")


def perfil(root):
    caminho = root / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    return caminho.read_text().strip()


class MaximumRuntime:
    def __init__(self):
        self.ppd = "balanced"
        self.powermizer = "0"

    def hold(self):
        self.powermizer = "1"

    def close(self):
        self.powermizer = "0"

    def __call__(self, args, **_kwargs):
        if args[:1] == ["busctl"] and "get-property" in args:
            resposta = json.dumps({"type": "s", "data": self.ppd})
            return subprocess.CompletedProcess(args, 0, resposta, "")
        if args[:1] == ["busctl"] and "set-property" in args:
            self.ppd = args[-1]
            return subprocess.CompletedProcess(args, 0, "", "")
        raise AssertionError(args)


def test_agente_mantem_o_modo_maximo_e_suspende_na_bateria(tmp_path):
    raiz = build_tree(
        tmp_path / "raiz", profile="balanced", fans=(2079, 1870)
    )
    caminho = tmp_path / "config.toml"
    save(
        Config(
            maximum_mode=True,
            maximum_saved_profile="balanced",
            maximum_saved_ppd="balanced",
            maximum_saved_powermizer="0",
        ),
        caminho,
    )
    runtime = MaximumRuntime()
    agente = Agent(Sysfs(raiz), caminho)
    agente._maximum = MaximumMode(agente._maximum.controls, caminho, runtime, gpu=runtime)

    agente.tick()
    assert perfil(raiz) == "balanced-performance"
    assert read_state(Sysfs(raiz)).fan_speed == (0, 0)
    assert (runtime.ppd, runtime.powermizer) == ("performance", "1")

    agente._maximum.controls.set_fan_speed(73, 81)
    agente.tick()
    assert read_state(Sysfs(raiz)).fan_speed == (73, 81)

    desconecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced"
    assert (runtime.ppd, runtime.powermizer) == ("balanced", "0")

    conecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced-performance"
    assert (runtime.ppd, runtime.powermizer) == ("performance", "1")


def test_modo_maximo_iniciado_na_bateria_e_suspenso_na_primeira_passada(tmp_path):
    raiz = build_tree(
        tmp_path / "raiz", on_ac=False, profile="balanced-performance"
    )
    caminho = tmp_path / "config.toml"
    save(Config(maximum_mode=True, auto_switch=False), caminho)
    agente = Agent(Sysfs(raiz), caminho)

    agente.tick()

    assert perfil(raiz) == "balanced"
    assert load(caminho).saved_ac_profile == "balanced-performance"


def test_a_primeira_passada_so_observa(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))
    agente.tick()
    assert perfil(raiz) == "balanced-performance"


def test_desconectar_derruba_o_perfil_no_sysfs(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))
    agente.tick()
    desconecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced"


def test_religar_devolve_o_perfil(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    agente = Agent(Sysfs(raiz), caminho)
    agente.tick()
    desconecta(raiz)
    agente.tick()
    conecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced-performance"


def test_o_perfil_guardado_persiste_no_arquivo(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    agente = Agent(Sysfs(raiz), caminho)
    agente.tick()
    desconecta(raiz)
    agente.tick()
    assert load(caminho).saved_ac_profile == "balanced-performance"


def test_um_agente_novo_retoma_do_arquivo(tmp_path):
    """Se o agente for reiniciado enquanto voce esta na bateria, o
    perfil guardado tem de sobreviver."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    primeiro = Agent(Sysfs(raiz), caminho)
    primeiro.tick()
    desconecta(raiz)
    primeiro.tick()

    segundo = Agent(Sysfs(raiz), caminho)
    segundo.tick()
    conecta(raiz)
    segundo.tick()
    assert perfil(raiz) == "balanced-performance"


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignora a permissão do arquivo")
def test_escrita_recusada_pelo_driver_nao_derruba_o_agente(tmp_path, caplog):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))
    agente.tick()
    desconecta(raiz)

    alvo = raiz / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    alvo.chmod(0o444)
    try:
        with caplog.at_level(logging.WARNING):
            agente.tick()
    finally:
        alvo.chmod(0o644)
    assert "não foi possível" in caplog.text.lower() or "nao foi possivel" in caplog.text.lower()


def test_sem_driver_o_agente_nao_explode(tmp_path):
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    agente = Agent(Sysfs(vazia), liga(tmp_path))
    assert agente.tick().profile is None


def test_run_para_quando_o_evento_e_sinalizado(tmp_path):
    import threading

    raiz = build_tree(tmp_path / "raiz")
    agente = Agent(Sysfs(raiz), liga(tmp_path), interval=0.01)
    parar = threading.Event()
    fio = threading.Thread(target=agente.run, args=(parar,))
    fio.start()
    parar.set()
    fio.join(timeout=2)
    assert not fio.is_alive()


def test_restaura_mesmo_sem_conseguir_gravar(tmp_path, monkeypatch, caplog):
    """O caso que a virada mostrou na maquina: a unit tinha
    ProtectHome=read-only, o agente nao conseguia gravar a configuracao,
    e a restauracao simplesmente nao acontecia -- com um aviso, e nada
    mais. O agente recarregava o disco a cada passada e nao guardava
    nada, entao o perfil da tomada morria na falha de gravacao.

    Persistir e bom; restaurar dentro da sessao nao pode depender disso.
    """
    from nexus_sense import agent as modulo

    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    agente = Agent(Sysfs(raiz), caminho)

    def recusa(config, alvo):
        raise OSError(30, "Read-only file system")

    agente.tick()
    monkeypatch.setattr(modulo, "save", recusa)
    desconecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced"
    conecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced-performance"


def test_a_falha_de_gravacao_continua_sendo_avisada(tmp_path, monkeypatch, caplog):
    """Degradar em silencio seria pior: sem o arquivo, um agente novo
    depois de reiniciar nao sabe para onde voltar."""
    from nexus_sense import agent as modulo

    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))

    def recusa(config, alvo):
        raise OSError(30, "Read-only file system")

    agente.tick()
    monkeypatch.setattr(modulo, "save", recusa)
    desconecta(raiz)
    with caplog.at_level(logging.WARNING):
        agente.tick()
    assert "não foi possível gravar" in caplog.text


def test_desativar_modo_libera_cliente_que_o_agente_mantinha(tmp_path):
    raiz = build_tree(tmp_path / "root")
    caminho = tmp_path / "config.toml"
    save(Config(maximum_mode=True), caminho)
    runtime = MaximumRuntime()
    agent = Agent(Sysfs(raiz), caminho)
    agent._maximum = MaximumMode(agent._maximum.controls, caminho, runtime, gpu=runtime)
    agent.tick()
    assert runtime.powermizer == "1"
    save(Config(maximum_mode=False), caminho)
    agent.tick()
    assert runtime.powermizer == "0"
