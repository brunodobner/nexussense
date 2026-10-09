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


class PpdQuebrado(MaximumRuntime):
    """O barramento responde erro a tudo, como com o ppd parado."""

    def __call__(self, args, **_kwargs):
        return subprocess.CompletedProcess(args, 1, "", "sem serviço")


def _avisos(caplog):
    return [r for r in caplog.records if r.levelno == logging.WARNING]


def test_falha_persistente_do_modo_maximo_avisa_uma_vez(tmp_path, caplog):
    """Com o ppd fora do ar a mesma falha se repetia a cada passada: uma
    linha a cada 2 s, 43 200 por dia. O que interessa no journal e a
    falha aparecer, mudar ou sumir -- nao que ela continua igual."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = tmp_path / "config.toml"
    save(Config(maximum_mode=True, maximum_saved_ppd="balanced"), caminho)
    agente = Agent(Sysfs(raiz), caminho)
    quebrado = PpdQuebrado()
    agente._maximum = MaximumMode(agente._maximum.controls, caminho, quebrado, gpu=quebrado)

    with caplog.at_level(logging.INFO):
        for _ in range(10):
            agente.tick()
        assert len(_avisos(caplog)) == 1

        agente._maximum.runner = MaximumRuntime()
        agente.tick()
        assert "cessaram" in caplog.text

        agente._maximum.runner = quebrado
        agente.tick()
        assert len(_avisos(caplog)) == 2


def test_sem_driver_o_agente_avisa_uma_vez_e_retoma(tmp_path, caplog):
    """Driver ausente nao e motivo para morrer: e o cenario de uma
    atualizacao de kernel em que o DKMS falhou (armadilha 26). O agente
    espera, e quando o modulo aparece segue sem ninguem precisar relogar."""
    raiz = tmp_path / "raiz"
    agente = Agent(Sysfs(raiz), liga(tmp_path))

    with caplog.at_level(logging.INFO):
        for _ in range(5):
            assert agente.tick().profile is None
        assert len(_avisos(caplog)) == 1
        assert "ausente" in caplog.text

        build_tree(raiz, profile="balanced")
        agente.tick()
        assert "de volta" in caplog.text
        assert len(_avisos(caplog)) == 1


def test_main_sem_driver_fica_vivo_em_vez_de_sair(tmp_path):
    """Sair com 1 virava laco. A unit tem Restart=always e RestartSec=3,
    e o limite de 5 partidas em 10 s nunca e atingido nesse ritmo.
    Reproduzido em 2026-10-09 numa unit descartavel: 8 reinicios em 26 s,
    sem parar."""
    import signal
    import threading
    import time

    from nexus_sense.__main__ import main

    antigos = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
    # Cancelado no finally: se main voltar antes do sinal, ele nao pode
    # sobrar apontado para o proprio pytest.
    alarme = threading.Timer(0.3, lambda: os.kill(os.getpid(), signal.SIGTERM))
    inicio = time.monotonic()
    alarme.start()
    try:
        codigo = main(
            [
                "--root", str(tmp_path / "vazia"),
                "--config", str(tmp_path / "config.toml"),
                "--interval", "0.01",
            ]
        )
        durou = time.monotonic() - inicio
    finally:
        alarme.cancel()
        for sinal, tratador in antigos.items():
            signal.signal(sinal, tratador)

    assert durou >= 0.25, "o agente saiu sozinho em vez de esperar o driver"
    assert codigo == 0


def test_once_sem_driver_continua_acusando(tmp_path):
    """`--once` e diagnostico de uma passada: ali sair com erro informa."""
    from nexus_sense.__main__ import main

    assert main(["--root", str(tmp_path / "vazia"), "--once"]) == 1


# ---------------------------------------------------------------------
# Abaixo de 40% de bateria o firmware se diz fora da tomada
# ---------------------------------------------------------------------


class SysfsAbaixoDe40(Sysfs):
    """O ANV15-52 com o cabo ligado e a bateria abaixo de 40%.

    `ACAD/online` diz 1, e mesmo assim o firmware recusa os perfis de
    tomada com EOPNOTSUPP -- para ele a maquina ainda esta na bateria.
    Medido em 2026-09-30 e de novo em 2026-10-09. Ver armadilha 27.
    """

    def __init__(self, root):
        super().__init__(root)
        self.recusa = True

    def write(self, path, value):
        from pathlib import Path

        from nexus_sense.model import AC_ONLY

        if self.recusa and Path(path).name == "profile" and str(value) in AC_ONLY:
            raise OSError(95, "Operation not supported")
        super().write(path, value)


def _religado_abaixo_de_40(tmp_path):
    """Estava em balanced-performance, tirou o cabo, religou com pouca
    carga. Devolve (raiz, caminho, sysfs, agente) ja depois da recusa."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    sysfs = SysfsAbaixoDe40(raiz)
    agente = Agent(sysfs, caminho)
    agente.tick()
    desconecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced"
    conecta(raiz)
    agente.tick()
    return raiz, caminho, sysfs, agente


def test_religar_abaixo_de_40_nao_perde_o_perfil_guardado(tmp_path):
    """O defeito: o guardado era apagado ANTES de a escrita dar certo.
    Recusada a escrita, a maquina ficava em balanced para sempre."""
    raiz, caminho, _sysfs, _agente = _religado_abaixo_de_40(tmp_path)

    assert perfil(raiz) == "balanced"
    assert load(caminho).saved_ac_profile == "balanced-performance"


def test_o_perfil_volta_quando_a_carga_passa_de_40(tmp_path, caplog):
    raiz, caminho, sysfs, agente = _religado_abaixo_de_40(tmp_path)
    # A recusa ja foi dita uma vez, na religada. Daqui em diante a espera
    # nao pode encher o journal.
    assert len(_avisos(caplog)) == 1
    caplog.clear()

    with caplog.at_level(logging.INFO):
        for _ in range(5):
            agente.tick()
        assert perfil(raiz) == "balanced"
        assert len(_avisos(caplog)) == 0

        sysfs.recusa = False
        agente.tick()

    assert perfil(raiz) == "balanced-performance"
    assert load(caminho).saved_ac_profile is None


def test_escolha_manual_durante_a_espera_cancela_a_devolucao(tmp_path):
    """Carregar de 26% a 40% leva minutos. Se nesse meio tempo voce
    escolhe outro perfil, a escolha e sua: o agente nao pode desfaze-la
    quando a carga chegar."""
    raiz, caminho, sysfs, agente = _religado_abaixo_de_40(tmp_path)

    Sysfs(raiz).write(Sysfs(raiz).profile_path(), "low-power")
    agente.tick()
    sysfs.recusa = False
    agente.tick()

    assert perfil(raiz) == "low-power"
    assert load(caminho).saved_ac_profile is None


def test_tirar_o_cabo_durante_a_espera_guarda_para_a_proxima(tmp_path):
    raiz, caminho, sysfs, agente = _religado_abaixo_de_40(tmp_path)

    desconecta(raiz)
    agente.tick()
    assert load(caminho).saved_ac_profile == "balanced-performance"

    sysfs.recusa = False
    conecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced-performance"
