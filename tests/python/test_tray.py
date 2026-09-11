import pytest

from nexus_sense.device import read_state
from nexus_sense.gui.poller import Poller
from nexus_sense.sysfs import Sysfs
from nexus_sense.tray.menu import build_menu
from nexus_sense.tray.sni import (
    StatusNotifierItem,
    icon_level,
    icon_name,
    scroll_target,
    tooltip_text,
)

from conftest import build_tree

QUATRO = ("low-power", "quiet", "balanced", "balanced-performance")


# ------------------------------------------------------------- o scroll


def test_roda_para_cima_sobe_um_degrau():
    assert scroll_target("balanced", QUATRO, True, +1) == "balanced-performance"


def test_roda_para_baixo_desce_um_degrau():
    assert scroll_target("balanced", QUATRO, True, -1) == "quiet"


def test_na_bateria_o_scroll_pula_o_degrau_barrado():
    """O buraco da escada: subindo do Economico na bateria, o Silencioso e
    pulado e o destino e o Equilibrado. Nunca se para num degrau que
    falharia. Ver spec secao 7.2."""
    assert scroll_target("low-power", QUATRO, False, +1) == "balanced"


def test_na_bateria_o_scroll_bate_no_teto_e_para():
    """Girar mais para cima nao faz nada: o Desempenho tambem esta
    barrado. Bate no limite e para, sem erro e sem escrita que falha."""
    assert scroll_target("balanced", QUATRO, False, +1) == "balanced"


def test_no_chao_o_scroll_tambem_para():
    assert scroll_target("low-power", QUATRO, True, -1) == "low-power"


def test_delta_zero_nao_move():
    assert scroll_target("balanced", QUATRO, True, 0) == "balanced"


def test_perfil_que_deixou_de_valer_cai_no_mais_proximo():
    """Caso real: o cabo saiu com a maquina em balanced-performance."""
    assert scroll_target("balanced-performance", QUATRO, False, +1) == "balanced"


def test_sem_perfil_disponivel_devolve_o_corrente():
    assert scroll_target("balanced", (), True, +1) == "balanced"


# ------------------------------------------------------------- o tooltip


def test_o_tooltip_traz_perfil_ventoinhas_e_temperatura(fake_root):
    s = Sysfs(fake_root)
    texto = tooltip_text(read_state(s), Poller(s).read_now())
    assert "Equilibrado" in texto
    assert "2079" in texto and "1870" in texto
    assert "47" in texto


def test_o_tooltip_aguenta_amostra_vazia(tmp_path):
    s = Sysfs(tmp_path)
    texto = tooltip_text(read_state(s), Poller(s).read_now())
    assert isinstance(texto, str) and texto


# --------------------------------------------------------------- o icone


def test_cada_perfil_tem_seu_nivel():
    niveis = {icon_level(p, QUATRO) for p in QUATRO}
    assert niveis == {1, 2, 3, 4}


def test_o_topo_da_escada_enche_o_n():
    assert icon_level("balanced-performance", QUATRO) == 4


def test_o_chao_da_escada_e_sempre_o_nivel_um():
    assert icon_level("low-power", QUATRO) == 1


def test_sem_escada_nao_ha_nivel():
    assert icon_level("balanced", ()) is None
    assert icon_level("balanced", ("balanced",)) is None
    assert icon_level("inventado", QUATRO) is None


def test_a_polaridade_segue_o_tema():
    """No painel escuro o glifo e claro, e vice-versa. O sufixo nomeia a
    cor do desenho, nao a do painel."""
    assert icon_name("balanced", QUATRO, True).endswith("-claro")
    assert icon_name("balanced", QUATRO, False).endswith("-escuro")


def test_desempenho_maximo_usa_o_icone_dourado():
    assert icon_name("balanced-performance", QUATRO, True, maximum=True) \
        == "nexus-sense-tray-v2-max-claro"


def test_o_nome_sem_polaridade_nunca_e_usado():
    """O arquivo sem sufixo usa currentColor, que nenhum tema repinta
    quando o SVG vem do hicolor -- fica preto e some no painel escuro.
    Foi o defeito relatado. Nenhum nome devolvido pode ser o base."""
    for perfil in (*QUATRO, None, "inventado"):
        for escuro in (True, False):
            assert icon_name(perfil, QUATRO, escuro).endswith(("-claro", "-escuro"))


# ------------------------------------------------------------- o objeto


def test_o_item_guarda_icone_e_tooltip(qtbot):
    item = StatusNotifierItem()
    item.set_icon("nexus-sense-tray-quiet")
    item.set_tooltip("qualquer coisa")
    assert item.icon == "nexus-sense-tray-quiet"
    assert item.tooltip == "qualquer coisa"


def test_o_scroll_do_host_vira_sinal(qtbot):
    """E este metodo que o QSystemTrayIcon nao tem, e a razao de haver um
    SNI escrito a mao aqui. Ver spec secao 7.1."""
    item = StatusNotifierItem()
    with qtbot.waitSignal(item.scrolled, timeout=1000) as capturado:
        item.Scroll(120, "vertical")
    assert capturado.args == [120, "vertical"]


def test_os_outros_tres_metodos_tambem_viram_sinal(qtbot):
    item = StatusNotifierItem()
    with qtbot.waitSignal(item.activated, timeout=1000):
        item.Activate(0, 0)
    with qtbot.waitSignal(item.secondary, timeout=1000):
        item.SecondaryActivate(0, 0)
    with qtbot.waitSignal(item.context_menu, timeout=1000):
        item.ContextMenu(10, 20)


# ----------------------------------------------------------------- menu


def test_o_menu_lista_so_os_perfis_disponiveis(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False)
    estado = read_state(Sysfs(raiz))
    menu = build_menu(estado, {})
    qtbot.addWidget(menu)
    textos = [a.text() for a in menu.actions() if not a.isSeparator()]
    assert "Econômico" in textos
    assert "Silencioso" not in textos


def test_o_menu_marca_o_perfil_corrente(qtbot, fake_root):
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {})
    qtbot.addWidget(menu)
    marcadas = [a.text() for a in menu.actions() if a.isChecked()]
    assert marcadas == ["Equilibrado"]


def test_o_menu_oferece_e_marca_desempenho_maximo(qtbot, fake_root):
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {}, maximum_active=True)
    qtbot.addWidget(menu)
    maximum = next(a for a in menu.actions() if a.objectName() == "maximum")
    assert maximum.text() == "Desempenho máximo"
    assert maximum.isEnabled() and maximum.isChecked()
    fan_actions = [a for a in menu.actions() if a.objectName().startswith("fan_")]
    assert fan_actions and all(action.isEnabled() for action in fan_actions)


def test_o_menu_tem_ventoinha_abrir_e_sair(qtbot, fake_root):
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {})
    qtbot.addWidget(menu)
    textos = [a.text() for a in menu.actions() if not a.isSeparator()]
    for esperado in ("Ventoinha automática", "Ventoinha no máximo", "Abrir", "Sair"):
        assert esperado in textos


def test_clicar_num_perfil_do_menu_chama_a_acao(qtbot, fake_root):
    escolhidos = []
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {"set_profile": escolhidos.append})
    qtbot.addWidget(menu)
    for acao in menu.actions():
        if acao.text() == "Econômico":
            acao.trigger()
    assert escolhidos == ["low-power"]


def test_menu_sem_permissao_desabilita_controles(qtbot, fake_root):
    state = read_state(Sysfs(fake_root))._replace(profile_writable=False, writable=frozenset())
    menu = build_menu(state, {})
    qtbot.addWidget(menu)
    for action in menu.actions():
        if not action.isSeparator():
            assert action.isEnabled() == (action.text() in ("Abrir", "Sair"))


def test_maximo_e_unica_opcao_marcada_sobre_balanced_performance(qtbot, tmp_path):
    root = build_tree(tmp_path / "root", profile="balanced-performance")
    menu = build_menu(read_state(Sysfs(root)), {}, maximum_active=True)
    qtbot.addWidget(menu)
    assert [a.objectName() for a in menu.actions() if a.isChecked()] == ["maximum"]
