import pytest

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.performance import PerformancePage, unavailable_reason
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

QUATRO = ("low-power", "quiet", "balanced", "balanced-performance")


def pagina(qtbot, raiz, maximum=None):
    s = Sysfs(raiz)
    p = PerformancePage(Controls(s), maximum=maximum)
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    return p


class MaximumFake:
    def requested(self):
        return True


def test_um_botao_por_perfil_anunciado_na_ordem_canonica(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    assert tuple(p.buttons) == (*QUATRO, "maximum")


def test_desempenho_maximo_e_o_quinto_modo(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    assert p.buttons["maximum"].text() == "Desempenho máximo\nCPU + GPU"


def test_desempenho_maximo_fica_suspenso_na_bateria(qtbot, tmp_path):
    p = pagina(qtbot, build_tree(tmp_path / "t", on_ac=False))
    assert p.buttons["maximum"].isEnabled() is False
    assert "bateria" in p.buttons["maximum"].reason


def test_desempenho_maximo_permite_ventoinhas_maximas_e_manuais(qtbot, fake_root):
    p = pagina(qtbot, fake_root, maximum=MaximumFake())
    assert p.fan_buttons["max"].isEnabled()
    assert p.fan_buttons["manual"].isEnabled()


def test_as_posicoes_nao_mudam_quando_o_cabo_sai(qtbot, tmp_path):
    """O requisito central da tela: o conjunto nao muda de tamanho nem de
    conteudo com a fonte. Hoje a GUI antiga troca tres botoes por dois e
    nada fica no lugar. Ver spec secao 6.2 e decisao D7."""
    raiz = build_tree(tmp_path / "t", on_ac=True)
    p = pagina(qtbot, raiz)
    na_tomada = tuple(p.buttons)

    (raiz / "sys/class/power_supply/ACAD/online").write_text("0\n")
    p.apply_state(read_state(Sysfs(raiz)))
    assert tuple(p.buttons) == na_tomada


def test_na_bateria_o_indisponivel_fica_desligado_com_o_motivo(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False)
    p = pagina(qtbot, raiz)
    assert p.buttons["quiet"].isEnabled() is False
    assert p.buttons["quiet"].unavailable is True
    assert "bateria" in p.buttons["quiet"].reason
    assert p.buttons["balanced"].isEnabled() is True
    assert p.buttons["balanced"].unavailable is False


def test_o_buraco_da_escada_aparece_na_tela(qtbot, tmp_path):
    """O 'quiet' e mais economico que o 'balanced' e mesmo assim e
    barrado; o alcance nao e contiguo. Ver spec secao 2.8."""
    raiz = build_tree(tmp_path / "t", on_ac=False)
    p = pagina(qtbot, raiz)
    ligados = [n for n, b in p.buttons.items() if b.isEnabled()]
    assert ligados == ["low-power", "balanced"]


def test_o_perfil_corrente_fica_marcado(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", profile="quiet")
    p = pagina(qtbot, raiz)
    assert p.buttons["quiet"].isChecked() is True
    assert p.buttons["balanced"].isChecked() is False


def test_clicar_escreve_no_sysfs(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.buttons["quiet"].click()
    caminho = fake_root / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    assert caminho.read_text().strip() == "quiet"


def test_clicar_avisa_a_janela_para_reler(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    with qtbot.waitSignal(p.changed, timeout=1000):
        p.buttons["low-power"].click()


def test_escrita_recusada_vira_frase_na_tela_e_nao_excecao(qtbot, fake_root, monkeypatch):
    """Corrida real: o cabo sai entre o clique e a escrita. Relê o estado
    e corrige a tela, sem diálogo. Ver spec secao 9."""
    import errno

    p = pagina(qtbot, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    monkeypatch.setattr(p.controls.sysfs, "write", recusa)
    p.buttons["quiet"].click()
    assert "bateria" in p.message_label.text()


def test_sem_perfil_anunciado_a_secao_nao_tem_conteudo(qtbot, tmp_path):
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    s = Sysfs(vazia)
    p = PerformancePage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is False


def test_o_motivo_e_vazio_para_quem_esta_disponivel(fake_root):
    e = read_state(Sysfs(fake_root))
    assert unavailable_reason("balanced", e) == ""
