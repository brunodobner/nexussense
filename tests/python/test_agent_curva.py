"""A curva propria dentro do agente, numa arvore de mentira.

O que se guarda: ela so age com fan_curve, na tomada, fora de quiet e
low-power e com o guarda no ar; registra antes de escrever; escreve so
quando muda; cede ao Manual da janela e volta com o automatico; devolve o
automatico quando sai; e, se a rede disparar com ela ativa, se desliga.
"""

import logging

import pytest

from conftest import build_tree
from nexus_sense import curva
from nexus_sense.agent import Agent
from nexus_sense.config import Config, load, save
from nexus_sense.sysfs import Sysfs


@pytest.fixture
def unit(tmp_path, monkeypatch):
    """O RuntimeDirectory que a unit daria ao agente."""
    pasta = tmp_path / "run"
    pasta.mkdir()
    monkeypatch.setenv("RUNTIME_DIRECTORY", str(pasta))
    return pasta


def arvore(tmp_path, cpu=45, gpu=0, fan="0,0", **kw):
    raiz = build_tree(tmp_path / "raiz", acer_temps=(cpu * 1000, gpu * 1000, 40000), **kw)
    escreve_fan(raiz, fan)
    return raiz


def escreve_fan(raiz, valor):
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text(f"{valor}\n")


def fan(raiz):
    return (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").read_text().strip()


def temperaturas(raiz, cpu, gpu):
    hw = next((raiz / "sys/devices/platform/acer-wmi/hwmon").iterdir())
    (hw / "temp1_input").write_text(f"{cpu * 1000}\n")
    (hw / "temp2_input").write_text(f"{gpu * 1000}\n")


def agente(tmp_path, raiz, ligada=True):
    caminho = tmp_path / "config.toml"
    save(Config(fan_curve=ligada), caminho)
    return Agent(Sysfs(raiz), caminho)


def test_ligada_a_curva_escreve_a_tabela_e_registra(tmp_path, unit):
    raiz = arvore(tmp_path, cpu=45, gpu=0)
    agente(tmp_path, raiz).tick()
    assert fan(raiz) == "25,24"
    assert (unit / "ventoinha").read_text() == "0,0\n25,24\n"


def test_desligada_nao_toca_na_ventoinha(tmp_path, unit):
    raiz = arvore(tmp_path)
    agente(tmp_path, raiz, ligada=False).tick()
    assert fan(raiz) == "0,0"
    assert not (unit / "ventoinha").exists()


def test_so_escreve_quando_a_porcentagem_muda(tmp_path, unit, monkeypatch):
    raiz = arvore(tmp_path, cpu=45, gpu=0)
    a = agente(tmp_path, raiz)
    escritas = []
    original = a._controls.set_fan_speed
    monkeypatch.setattr(a._controls, "set_fan_speed", lambda c, g: (escritas.append((c, g)), original(c, g)))
    a.tick()
    a.tick()
    temperaturas(raiz, 80, 78)
    # O piso da GPU quente entra na hora, pela leitura de agora; a tabela da
    # GPU espera a mediana das ultimas leituras chegar la.
    a.tick()
    a.tick()
    a.tick()
    assert escritas == [(25, 24), (81, 82), (81, 91)]
    assert fan(raiz) == "81,91"
    assert (unit / "ventoinha").read_text() == "81,82\n81,91\n"


def test_um_pulo_de_temperatura_nao_move_a_ventoinha(tmp_path, unit):
    """Na maquina a CPU pelo EC pulou de 54 a 88 C e voltou em segundos, com
    carga em rajadas, e a ventoinha ia atras. A mediana nao vai."""
    raiz = arvore(tmp_path, cpu=45, gpu=0)
    a = agente(tmp_path, raiz)
    for _ in range(4):
        a.tick()
    temperaturas(raiz, 90, 0)
    a.tick()
    a.tick()
    assert fan(raiz) == "25,24"
    temperaturas(raiz, 45, 0)
    a.tick()
    assert fan(raiz) == "25,24"
    # Uma carga que dura move, sim: tres leituras de cinco.
    temperaturas(raiz, 90, 0)
    for _ in range(3):
        a.tick()
    assert fan(raiz) == "99,24"


def test_cede_ao_manual_da_janela_e_volta_com_o_automatico(tmp_path, unit, caplog):
    raiz = arvore(tmp_path)
    a = agente(tmp_path, raiz)
    a.tick()
    escreve_fan(raiz, "60,60")         # a janela, em Manual
    with caplog.at_level(logging.INFO):
        a.tick()
        a.tick()
    assert fan(raiz) == "60,60"
    assert sum("que ela não escreveu" in r.getMessage() for r in caplog.records) == 1
    escreve_fan(raiz, "0,0")           # Automatico na janela, ou o modo maximo ligando
    a.tick()
    assert fan(raiz) == "25,24"


def test_na_primeira_passada_assume_o_manual_que_esta_la(tmp_path, unit):
    """Depois de um reinicio o driver devolve o manual gravado no
    desligamento; o agente novo nao sabe de quem era."""
    raiz = arvore(tmp_path, fan="40,40")
    agente(tmp_path, raiz).tick()
    assert fan(raiz) == "25,24"


def test_desligar_no_arquivo_devolve_o_automatico(tmp_path, unit):
    raiz = arvore(tmp_path)
    a = agente(tmp_path, raiz)
    a.tick()
    save(Config(fan_curve=False), tmp_path / "config.toml")
    a.tick()
    assert fan(raiz) == "0,0"


def test_na_bateria_devolve_o_automatico(tmp_path, unit):
    raiz = arvore(tmp_path)
    a = agente(tmp_path, raiz)
    a.tick()
    (raiz / "sys/class/power_supply/ACAD/online").write_text("0\n")
    a.tick()
    assert fan(raiz) == "0,0"


@pytest.mark.parametrize("perfil", ["quiet", "low-power"])
def test_em_quiet_e_low_power_nao_age(tmp_path, unit, perfil):
    raiz = arvore(tmp_path, profile=perfil)
    agente(tmp_path, raiz).tick()
    assert fan(raiz) == "0,0"


def test_sem_o_guarda_a_curva_nao_age(tmp_path, monkeypatch, caplog):
    """Fora da unit nao ha onde registrar, e o guarda nao devolveria."""
    monkeypatch.delenv("RUNTIME_DIRECTORY", raising=False)
    raiz = arvore(tmp_path)
    a = agente(tmp_path, raiz)
    with caplog.at_level(logging.WARNING):
        a.tick()
        a.tick()
    assert fan(raiz) == "0,0"
    assert sum("sem o guarda" in r.getMessage() for r in caplog.records) == 1


def test_sem_temperatura_segura_e_depois_devolve(tmp_path, unit):
    raiz = arvore(tmp_path)
    a = agente(tmp_path, raiz)
    a.tick()
    hw = next((raiz / "sys/devices/platform/acer-wmi/hwmon").iterdir())
    (hw / "temp2_input").unlink()
    a.tick()
    a.tick()
    assert fan(raiz) == "25,24"        # uma leitura falha, de vez em quando
    a.tick()
    assert fan(raiz) == "0,0"          # tres seguidas: devolve o automatico


def test_a_rede_disparando_com_a_curva_desliga_a_curva(tmp_path, unit, monkeypatch, caplog):
    """A curva cumpre o invariante da rede. Se a rede dispara com ela
    ativa, e defeito da curva: ela sai, e sai no arquivo."""
    raiz = arvore(tmp_path, cpu=80, gpu=80)
    monkeypatch.setattr(curva, "decide", lambda *_, **__: (25, 24))
    a = agente(tmp_path, raiz)
    with caplog.at_level(logging.WARNING):
        for _ in range(3):
            a.tick()
    assert fan(raiz) == "0,0"
    assert load(tmp_path / "config.toml").fan_curve is False
    assert any("defeito da curva" in r.getMessage() for r in caplog.records)
