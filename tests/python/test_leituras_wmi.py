"""Os caminhos periodicos nao podem custar uma chamada WMI.

Cada leitura de um atributo do grupo nitro_sense/predator_sense executa
um `wmi_evaluate_method` no driver e imprime uma linha no journal. Com a
bandeja repintando a cada 5 s, isso rendeu 75 mil linhas de log em doze
horas nesta maquina. Ver docs/ARMADILHAS.md.

A regra que estes testes fixam: quem roda em timer le so o que exibe.
`features`, `writable` e `available` saem de `is_file`/`os.access`, que
sao stat e nao acionam o `show()` do driver -- por isso continuam de
graca e nao aparecem aqui.
"""

import json
import subprocess
from pathlib import Path

from nexus_sense.agent import Agent
from nexus_sense.config import Config, save
from nexus_sense.device import Controls, SENSE_ATTRS
from nexus_sense.gui.app import _connect_state
from nexus_sense.gui.window import Window
from nexus_sense.maximum import MaximumMode
from nexus_sense.sysfs import Sysfs
from nexus_sense.tray.controller import TrayController
from nexus_sense.tray.sni import StatusNotifierItem

from conftest import build_tree


class SysfsEspiao(Sysfs):
    """Sysfs de verdade que anota o nome de cada atributo lido.

    `Sysfs.read` e o unico caminho de leitura do projeto, entao contar
    aqui equivale a contar chamadas WMI no driver.
    """

    def __init__(self, root):
        super().__init__(root)
        self.lidos = []

    def read(self, path):
        self.lidos.append(Path(path).name)
        return super().read(path)

    @property
    def wmi(self):
        """So os atributos que custam uma chamada ao firmware."""
        return [nome for nome in self.lidos if nome in SENSE_ATTRS]


class RuntimeFalso:
    """O ppd e a GPU de mentira, sem tocar na maquina."""

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


def test_a_passada_do_agente_nao_le_atributos_wmi(tmp_path):
    """O agente decide por perfil e fonte; os cinco do grupo sense nao
    entram em nenhuma decisao dele."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced")
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
    espiao = SysfsEspiao(raiz)
    agente = Agent(espiao, caminho)
    runtime = RuntimeFalso()
    agente._maximum = MaximumMode(
        agente._maximum.controls, caminho, runtime, gpu=runtime
    )

    espiao.lidos.clear()
    agente.tick()

    assert espiao.wmi == []


def test_a_bandeja_nao_le_atributos_wmi_a_cada_passada(qtbot, fake_root):
    """O tooltip mostra perfil, rotacao e temperatura. Nada do grupo sense."""
    espiao = SysfsEspiao(fake_root)
    controlador = TrayController(espiao, Controls(espiao), StatusNotifierItem())
    controlador.refresh()

    espiao.lidos.clear()
    controlador.refresh()

    assert espiao.wmi == []


def _monta_par(qtbot, raiz):
    espiao = SysfsEspiao(raiz)
    controls = Controls(espiao)
    janela = Window(espiao, controls)
    qtbot.addWidget(janela)
    controlador = TrayController(espiao, controls, StatusNotifierItem())
    _connect_state(controlador, janela)
    return espiao, controlador, janela


def test_a_bandeja_nao_faz_a_janela_oculta_reler_o_aparelho(qtbot, fake_root):
    """Com --tray-only a janela nunca aparece, e relê-la e trabalho jogado
    fora: todo caminho que a torna visivel ja chama refresh antes."""
    espiao, controlador, _janela = _monta_par(qtbot, fake_root)

    espiao.lidos.clear()
    controlador.refresh()

    assert espiao.lidos.count("profile") == 1


def test_a_bandeja_continua_atualizando_a_janela_visivel(qtbot, fake_root):
    """A contrapartida do teste acima: com a janela aberta, a passada da
    bandeja tem de continuar repintando o painel."""
    espiao, controlador, janela = _monta_par(qtbot, fake_root)
    janela.show()
    qtbot.waitExposed(janela)

    espiao.lidos.clear()
    controlador.refresh()

    assert espiao.lidos.count("profile") == 2


def test_o_agente_le_o_perfil_uma_vez_por_passada(tmp_path):
    """Ler o perfil e uma chamada WMI, e das caras: 4,7 ms de CPU, medido
    em 2026-10-09, contra 0,17 ms de um sensor. Em modo maximo o agente
    lia duas vezes por passada -- uma para decidir, outra para conferir
    se o modo continuava de pe -- quando a segunda ja sabia a resposta."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = tmp_path / "config.toml"
    save(Config(maximum_mode=True, maximum_saved_ppd="balanced"), caminho)
    espiao = SysfsEspiao(raiz)
    agente = Agent(espiao, caminho)
    runtime = RuntimeFalso()
    agente._maximum = MaximumMode(
        agente._maximum.controls, caminho, runtime, gpu=runtime
    )
    agente.tick()

    espiao.lidos.clear()
    agente.tick()

    assert espiao.lidos.count("profile") == 1


def test_uma_acao_na_janela_rele_o_aparelho_uma_vez(qtbot, fake_root):
    """O `changed` de uma pagina chegava a janela por dois caminhos: o
    direto, e de volta pela bandeja. Eram dois `read_state` por clique --
    27 ms cada, medido, com cinco chamadas WMI dentro."""
    espiao, _controlador, janela = _monta_par(qtbot, fake_root)
    janela.show()
    qtbot.waitExposed(janela)
    pagina = janela.pages[0][2]

    espiao.lidos.clear()
    pagina.changed.emit()

    assert espiao.lidos.count("fan_speed") == 1
