"""A rede da ventoinha manual, no laco do agente.

A funcao pura esta em test_fan_guard.py, e os limiares em
test_fan_guard_tracos.py. Aqui e o que o agente faz em volta dela: o que
le, quando le, o que escreve e o que diz.
"""

import errno
import json
import logging
import os
import subprocess

import pytest

from nexus_sense.agent import Agent
from nexus_sense.config import Config, save
from nexus_sense.maximum import MaximumMode
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

SENSE = "sys/devices/platform/acer-wmi/nitro_sense"
PISO = (2075, 1727)  # a rotacao do E3b, com o manual em 1%
QUENTE = (91000, 81000, 71000)  # CPU, GPU e placa pelo EC, no E3b
FRIA = (50000, 45000, 45000)


def monta(tmp_path, setpoint="20,20", fans=PISO, temps=QUENTE, config=None, **arvore):
    raiz = build_tree(tmp_path / "raiz", fans=fans, acer_temps=temps, **arvore)
    (raiz / SENSE / "fan_speed").write_text(f"{setpoint}\n")
    caminho = tmp_path / "config.toml"
    save(config or Config(), caminho)
    return raiz, Agent(Sysfs(raiz), caminho)


def setpoint(raiz):
    return (raiz / SENSE / "fan_speed").read_text().strip()


def esfria(raiz):
    acer = raiz / "sys/devices/platform/acer-wmi/hwmon/hwmon5"
    (acer / "temp2_input").write_text("45000\n")


def esquenta(raiz):
    acer = raiz / "sys/devices/platform/acer-wmi/hwmon/hwmon5"
    (acer / "temp2_input").write_text("81000\n")


def linhas_da_rede(caplog):
    return [r.getMessage() for r in caplog.records if "rede térmica" in r.getMessage()]


class Espiao:
    """Anota o nome de cada arquivo que o agente le."""

    def __init__(self, sysfs):
        self.lidos = []
        self._read = sysfs.read
        sysfs.read = self.read

    def read(self, caminho):
        self.lidos.append(os.path.basename(caminho))
        return self._read(caminho)

    def sensores(self):
        return [n for n in self.lidos if n.endswith("_input")]


# ------------------------------------------------------------ dispara


def test_manual_no_piso_e_gpu_quente_devolve_o_automatico_na_segunda_passada(tmp_path):
    raiz, agente = monta(tmp_path)
    agente.tick()
    assert setpoint(raiz) == "20,20"
    agente.tick()
    assert setpoint(raiz) == "0,0"


def test_registra_uma_linha_com_o_manual_a_temperatura_e_a_rotacao(tmp_path, caplog):
    raiz, agente = monta(tmp_path)
    with caplog.at_level(logging.INFO):
        for _ in range(6):
            agente.tick()
    linhas = linhas_da_rede(caplog)
    assert len(linhas) == 1
    for pedaco in ("20,20", "81 °C", "2075", "1727", "automático"):
        assert pedaco in linhas[0], linhas[0]


def test_disparada_fica_em_automatico_e_nao_devolve_o_manual(tmp_path):
    """Decisao do usuario: o manual so volta pela mao dele. A rede nao
    guarda o setpoint em lugar nenhum."""
    raiz, agente = monta(tmp_path)
    agente.tick()
    agente.tick()
    assert setpoint(raiz) == "0,0"
    antes = (tmp_path / "config.toml").read_text()

    esfria(raiz)
    for _ in range(10):
        agente.tick()

    assert setpoint(raiz) == "0,0"
    assert (tmp_path / "config.toml").read_text() == antes
    assert "20" not in antes


def test_uma_passada_fria_no_meio_recomeca_a_conta(tmp_path):
    raiz, agente = monta(tmp_path)
    agente.tick()
    esfria(raiz)
    agente.tick()
    esquenta(raiz)
    agente.tick()
    assert setpoint(raiz) == "20,20"
    agente.tick()
    assert setpoint(raiz) == "0,0"


def test_escolher_o_manual_baixo_de_novo_ainda_quente_dispara_de_novo(tmp_path, caplog):
    raiz, agente = monta(tmp_path)
    with caplog.at_level(logging.INFO):
        agente.tick()
        agente.tick()
        (raiz / SENSE / "fan_speed").write_text("20,20\n")
        agente.tick()
        assert setpoint(raiz) == "20,20"
        agente.tick()
    assert setpoint(raiz) == "0,0"
    assert len(linhas_da_rede(caplog)) == 2


# -------------------------------------------------------- nao dispara


@pytest.mark.parametrize("valor", ["0,0", "100,100", "53,50", "60,60", "90,90"])
def test_sem_armar_nao_le_temperatura_nem_rotacao(tmp_path, valor):
    """Em automatico, em maximo ou em manual alto, a rede custa a leitura
    de fan_speed -- que o driver responde de memoria -- e mais nada."""
    raiz, agente = monta(tmp_path, setpoint=valor)
    espiao = Espiao(agente.sysfs)
    for _ in range(5):
        agente.tick()
    assert espiao.sensores() == []
    assert "fan_speed" in espiao.lidos
    assert setpoint(raiz) == valor


def test_armada_e_fria_le_so_a_gpu_pelo_ec(tmp_path):
    """Manual baixo com a maquina parada e o uso legitimo do cursor, e
    dura horas: uma chamada ao firmware por passada, nao tres."""
    raiz, agente = monta(tmp_path, temps=FRIA)
    espiao = Espiao(agente.sysfs)
    for _ in range(5):
        agente.tick()
    assert espiao.sensores() == ["temp2_input"] * 5
    assert setpoint(raiz) == "20,20"


def test_armada_e_quente_le_a_gpu_e_as_duas_rotacoes(tmp_path):
    raiz, agente = monta(tmp_path)
    espiao = Espiao(agente.sysfs)
    agente.tick()
    assert espiao.sensores() == ["temp2_input", "fan1_input", "fan2_input"]


def test_com_a_placa_dormindo_nao_dispara(tmp_path):
    """O canal da GPU le zero com a placa dormindo."""
    raiz, agente = monta(tmp_path, temps=(91000, 0, 71000))
    for _ in range(5):
        agente.tick()
    assert setpoint(raiz) == "20,20"


def test_se_a_ventoinha_ja_gira_como_o_automatico_nao_escreve(tmp_path, caplog):
    """fan_speed e a memoria do driver, nao o firmware."""
    raiz, agente = monta(tmp_path, fans=(4500, 4100))
    with caplog.at_level(logging.INFO):
        for _ in range(5):
            agente.tick()
    assert setpoint(raiz) == "20,20"
    assert linhas_da_rede(caplog) == []


def test_fan_speed_ilegivel_nao_arma_e_nao_derruba(tmp_path):
    raiz, agente = monta(tmp_path, setpoint="lixo")
    for _ in range(3):
        agente.tick()
    assert setpoint(raiz) == "lixo"


def test_sem_o_atributo_fan_speed_a_passada_segue(tmp_path):
    raiz, agente = monta(tmp_path)
    (raiz / SENSE / "fan_speed").unlink()
    agente.tick()
    agente.tick()


# ---------------------------------------------------- os dois modos


class Runtime:
    """PPD e PowerMizer de mentira, para o modo maximo poder ficar ligado."""

    def __init__(self):
        self.ppd = "balanced"

    def hold(self):
        pass

    def close(self):
        pass

    def __call__(self, args, **_kwargs):
        if args[:1] == ["busctl"] and "get-property" in args:
            return subprocess.CompletedProcess(
                args, 0, json.dumps({"type": "s", "data": self.ppd}), ""
            )
        if args[:1] == ["busctl"] and "set-property" in args:
            self.ppd = args[-1]
            return subprocess.CompletedProcess(args, 0, "", "")
        raise AssertionError(args)


def com_maximo(tmp_path, **arvore):
    raiz, agente = monta(
        tmp_path,
        setpoint="60,60",
        fans=(4911, 4647),  # o que 60% gira, pelo mapa do E2
        config=Config(maximum_mode=True, maximum_saved_profile="balanced"),
        **arvore,
    )
    runtime = Runtime()
    agente._maximum = MaximumMode(
        agente._maximum.controls, tmp_path / "config.toml", runtime, gpu=runtime
    )
    return raiz, agente


def test_com_o_modo_maximo_ligado_60_por_cento_esta_abaixo_do_automatico(tmp_path):
    raiz, agente = com_maximo(tmp_path)
    agente.tick()
    agente.tick()
    assert setpoint(raiz) == "0,0"


def test_com_o_modo_maximo_desligado_60_por_cento_nao_arma(tmp_path):
    raiz, agente = monta(tmp_path, setpoint="60,60", fans=(4911, 4647))
    for _ in range(5):
        agente.tick()
    assert setpoint(raiz) == "60,60"


def test_modo_maximo_suspenso_na_bateria_vale_como_desligado(tmp_path):
    """Pedido nao e ativo: na bateria o agente solta as tres alavancas, e
    a curva que vale e a outra."""
    raiz, agente = com_maximo(tmp_path, on_ac=False)
    for _ in range(5):
        agente.tick()
    assert setpoint(raiz) == "60,60"


# ------------------------------------------------- a escrita recusada


def test_escrita_recusada_avisa_uma_vez_e_segue_tentando(tmp_path, caplog):
    raiz, agente = monta(tmp_path)
    escreve = agente.sysfs.write
    recusando = True

    def write(caminho, valor):
        if recusando and os.path.basename(caminho) == "fan_speed":
            raise OSError(errno.EACCES, "Permission denied")
        escreve(caminho, valor)

    agente.sysfs.write = write
    with caplog.at_level(logging.INFO):
        for _ in range(5):
            agente.tick()
        assert setpoint(raiz) == "20,20"
        recusas = [r for r in caplog.records if "não conseguiu devolver" in r.getMessage()]
        assert len(recusas) == 1
        assert linhas_da_rede(caplog) == [recusas[0].getMessage()]

        recusando = False
        agente.tick()
    assert setpoint(raiz) == "0,0"
    assert len(linhas_da_rede(caplog)) == 2


# ------------------------------------------------- nunca o nvidia-smi


def test_a_rede_nunca_chama_o_nvidia_smi(tmp_path, monkeypatch):
    """Ele acorda a placa e, chamado a cada passada, nao a deixa dormir
    (armadilha 20). A isca na frente do PATH anota quem a chamar."""
    marca = tmp_path / "chamaram"
    pasta = tmp_path / "isca"
    pasta.mkdir()
    isca = pasta / "nvidia-smi"
    isca.write_text(f"#!/bin/sh\necho chamada >> '{marca}'\necho '11, 1 %'\n")
    isca.chmod(0o755)
    monkeypatch.setenv("PATH", f"{pasta}{os.pathsep}{os.environ['PATH']}")
    # A isca funciona: sem isto, "ninguem chamou" passaria por vacuo.
    subprocess.run(["nvidia-smi"], capture_output=True, check=True)
    assert marca.read_text() == "chamada\n"
    marca.unlink()

    raiz, agente = monta(tmp_path)
    agente.tick()
    agente.tick()

    assert setpoint(raiz) == "0,0"
    assert not marca.exists()
