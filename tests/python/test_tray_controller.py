import os

from nexus_sense.device import Controls, read_state
from nexus_sense.sysfs import Sysfs
from nexus_sense.tray import build_tray
from nexus_sense.tray.controller import TrayController
from nexus_sense.tray.fallback import FallbackTray
from nexus_sense.tray.sni import StatusNotifierItem

from conftest import build_tree

PROFILE = "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"


class FakeMaximum:
    def __init__(self, enabled=False):
        self.enabled = enabled

    def requested(self):
        return self.enabled

    def active(self, on_ac):
        return self.enabled and on_ac is True

    def enable(self, _state):
        self.enabled = True
        return ()

    def disable(self, _profile=None):
        self.enabled = False
        return ()


def controlador(qtbot, raiz):
    s = Sysfs(raiz)
    item = StatusNotifierItem()
    c = TrayController(s, Controls(s), item)
    c.refresh()
    return c, item


def test_modo_maximo_troca_icone_tooltip_e_scroll(qtbot, fake_root):
    s = Sysfs(fake_root)
    item = StatusNotifierItem()
    maximum = FakeMaximum()
    c = TrayController(s, Controls(s), item, maximum=maximum)
    c.refresh()
    c.apply_profile("balanced-performance")
    item.Scroll(120, "vertical")
    assert maximum.enabled is True
    assert item.icon.startswith("nexus-sense-tray-v2-max-")
    assert "Desempenho máximo" in item.tooltip
    item.Scroll(-120, "vertical")
    assert maximum.enabled is False


def test_o_icone_segue_o_perfil(qtbot, tmp_path):
    c, item = controlador(qtbot, build_tree(tmp_path / "t", profile="quiet"))
    # O nivel e o que importa aqui; a polaridade depende do tema de
    # quem roda o teste e tem cobertura propria em test_tray.py.
    assert item.icon.startswith("nexus-sense-tray-v2-nivel2-")


def test_o_tooltip_traz_o_perfil_e_a_rotacao(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    assert "Equilibrado" in item.tooltip
    assert "2079" in item.tooltip


def test_a_bandeja_nao_sonda_a_gpu(qtbot, fake_root, monkeypatch):
    """A bandeja le so hwmon. Se ela chamasse read_gpu a cada 5 s,
    manteria a dGPU acordada de graca. Ver spec secao 10.2."""
    from nexus_sense import telemetry

    def explode(*args, **kwargs):
        raise AssertionError("a bandeja não pode sondar a GPU")

    monkeypatch.setattr(telemetry, "read_gpu", explode)
    c, item = controlador(qtbot, fake_root)
    c.refresh()


def test_a_roda_para_cima_escreve_o_perfil_de_cima(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    item.Scroll(120, "vertical")
    assert (fake_root / PROFILE).read_text().strip() == "balanced-performance"


def test_na_bateria_a_roda_pula_o_degrau_barrado(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False, profile="low-power")
    c, item = controlador(qtbot, raiz)
    item.Scroll(120, "vertical")
    assert (raiz / PROFILE).read_text().strip() == "balanced"


def test_na_bateria_a_roda_bate_no_teto_sem_escrever(qtbot, tmp_path):
    """Girar mais nao pode nem mudar o perfil nem tentar uma escrita que
    o driver recusaria."""
    raiz = build_tree(tmp_path / "t", on_ac=False, profile="balanced")
    c, item = controlador(qtbot, raiz)
    escritas = []
    c.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)
    item.Scroll(120, "vertical")
    assert escritas == []


def test_o_clique_do_meio_alterna_com_o_anterior(qtbot, fake_root):
    """O anterior e o de antes da ultima troca feita pela bandeja."""
    c, item = controlador(qtbot, fake_root)
    item.Scroll(120, "vertical")          # balanced -> balanced-performance
    assert (fake_root / PROFILE).read_text().strip() == "balanced-performance"
    item.SecondaryActivate(0, 0)          # volta ao balanced
    assert (fake_root / PROFILE).read_text().strip() == "balanced"


def test_o_clique_do_meio_sem_anterior_nao_faz_nada(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    escritas = []
    c.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)
    item.SecondaryActivate(0, 0)
    assert escritas == []


def test_o_clique_esquerdo_pede_para_abrir(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    with qtbot.waitSignal(c.open_requested, timeout=1000):
        item.Activate(0, 0)


def test_escrita_recusada_pela_bandeja_nao_derruba_nada(qtbot, fake_root):
    """Sem janela aberta nao ha onde mostrar frase: engole, relê e segue."""
    import errno

    c, item = controlador(qtbot, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    c.controls.sysfs.write = recusa
    item.Scroll(120, "vertical")     # não pode levantar


def test_o_relogio_da_bandeja_liga_e_desliga(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    c.start()
    assert c.active is True
    c.stop()
    assert c.active is False


def test_ventoinha_recusada_nao_impede_proxima_acao(qtbot, fake_root):
    import errno

    c, item = controlador(qtbot, fake_root)
    write = c.controls.sysfs.write

    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    c.controls.sysfs.write = recusa
    c.apply_fan_speed(100, 100)
    c.controls.sysfs.write = write
    item.Scroll(120, "vertical")
    assert c.state.profile == "balanced-performance"


# --------------------------------------------------------------- fallback


def test_o_fallback_tem_a_mesma_superficie_do_sni(qtbot):
    """Trocar um pelo outro nao pode exigir mudar o controlador."""
    f = FallbackTray()
    for nome in ("activated", "secondary", "context_menu", "scrolled"):
        assert hasattr(f, nome)
    f.set_icon("nexus-sense-tray-quiet")
    f.set_tooltip("texto")
    assert f.icon == "nexus-sense-tray-quiet"
    assert f.tooltip == "texto"


def test_o_fallback_serve_ao_controlador(qtbot, fake_root):
    s = Sysfs(fake_root)
    f = FallbackTray()
    c = TrayController(s, Controls(s), f)
    c.refresh()
    assert f.icon.startswith("nexus-sense-tray-v2-nivel")


def test_a_suite_nao_enxerga_o_barramento_de_sessao_de_verdade():
    """O teste abaixo diz "sem host SNI no barramento de teste" e ate
    2026-10-09 nao havia barramento de teste nenhum: build_tray falava com
    o da sessao de quem rodava a suite, achava o watcher do Plasma e
    registrava um item de verdade. Passava por isso, e so por isso."""
    endereco = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    assert endereco.startswith("unix:path=")
    assert not os.path.exists(endereco.removeprefix("unix:path="))


def test_build_tray_diz_qual_bandeja_subiu(qtbot, fake_root):
    """Sem barramento de sessao -- e o que a fixture autouse do conftest
    entrega -- o registro SNI nao tem como dar certo, e o resultado tem de
    ser uma das duas reservas, nunca excecao. Ver spec secao 7.3.

    Ate a sub-etapa 4c isto levantava DBusException: publish() abria a
    conexao fora do try."""
    s = Sysfs(fake_root)
    controlador_, modo = build_tray(s, Controls(s))
    assert modo in ("qsystemtrayicon", "nenhuma")
