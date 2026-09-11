"""A folha de estilo. Ver docs/INTERFACE.md."""

from PySide6.QtGui import QColor, QPalette

from nexus_sense.gui.style import CLARO, ESCURO, apply_to, is_dark, palette_for, stylesheet


def _paleta(cor):
    p = QPalette()
    p.setColor(QPalette.Window, QColor(cor))
    return p


def test_fundo_escuro_pede_a_pele_escura():
    assert is_dark(_paleta("#10141B")) is True


def test_fundo_claro_pede_a_pele_clara():
    assert is_dark(_paleta("#EFF2F7")) is False


def test_a_decisao_e_por_luminancia_e_nao_por_nome_de_tema():
    """Um azul escuro e um amarelo claro tem nomes que nao ajudam; a
    luminancia responde certo nos dois."""
    assert is_dark(_paleta("#1C2740")) is True
    assert is_dark(_paleta("#F5E9A0")) is False


def test_as_duas_peles_definem_os_mesmos_papeis():
    """Um papel definido so numa das peles produziria widget sem cor na
    outra -- o defeito classico de tema pela metade."""
    assert set(ESCURO) == set(CLARO)


def test_o_acento_e_o_mesmo_indigo_da_marca_nas_duas():
    assert ESCURO["marca"] == CLARO["marca"] == "#4A78C8"


def test_toda_cor_da_folha_sai_da_paleta():
    """Nenhum literal solto na QSS: trocar de pele tem de ser trocar o
    dicionario, e nada mais."""
    import re

    for escuro in (True, False):
        folha = stylesheet(escuro)
        usados = {c.lower() for c in re.findall(r"#[0-9A-Fa-f]{6}", folha)}
        permitidos = {v.lower() for v in palette_for(escuro).values()}
        assert usados <= permitidos, usados - permitidos


def test_as_tres_semanticas_aparecem_na_folha():
    for escuro in (True, False):
        folha = stylesheet(escuro)
        cores = palette_for(escuro)
        for papel in ("ok", "atencao", "falha"):
            assert cores[papel] in folha


def test_titulo_de_secao_nao_cria_faixa_de_cor():
    for escuro in (True, False):
        folha = stylesheet(escuro)
        regra = folha.split("QLabel#titulo", 1)[1].split("}", 1)[0]
        assert "background: transparent" in regra
        assert "QWidget#secao_ventoinhas" in folha


def test_aplicar_devolve_a_pele_escolhida(qtbot):
    from PySide6.QtWidgets import QApplication

    app = QApplication.instance()
    anterior = app.styleSheet()
    try:
        escuro = apply_to(app)
        assert isinstance(escuro, bool)
        assert app.styleSheet() != ""
    finally:
        app.setStyleSheet(anterior)


# ------------------------------------------------- contraste do grafico


def _lum(hexa):
    c = QColor(hexa)
    return 0.299 * c.red() + 0.587 * c.green() + 0.114 * c.blue()


def test_o_eixo_do_grafico_contrasta_com_o_cartao(qtbot):
    """O defeito que isto guarda: o grafico pegava cor da paleta do Qt, e
    no Breeze escuro o papel Mid e #1c1f21 -- praticamente o fundo do
    cartao. O eixo ficava invisivel, e nenhum teste acusava porque grab()
    nao e nulo quando o texto some. Agora as cores vem dos tokens."""
    from nexus_sense.gui.graph import TemperatureGraph

    g = TemperatureGraph()
    qtbot.addWidget(g)
    for escuro in (True, False):
        cores = palette_for(escuro)
        texto, grade = QColor(cores["texto_3"]), QColor(cores["linha_forte"])
        fundo = _lum(cores["cartao"])
        assert abs(_lum(texto.name()) - fundo) > 40, escuro
        assert abs(_lum(grade.name()) - fundo) > 10, escuro


def test_a_paleta_do_qt_nao_manda_nas_cores_do_eixo(qtbot):
    """Mesmo com uma paleta hostil -- Mid igual ao fundo -- o eixo sai
    legivel, porque nao e dela que a cor vem."""
    from nexus_sense.gui.graph import TemperatureGraph

    g = TemperatureGraph()
    qtbot.addWidget(g)
    hostil = QPalette()
    hostil.setColor(QPalette.Window, QColor("#10141B"))
    hostil.setColor(QPalette.Mid, QColor("#1B222E"))
    g.setPalette(hostil)
    texto, grade = g._cores()
    assert texto.name().lower() == ESCURO["texto_3"].lower()
    assert grade.name().lower() == ESCURO["linha_forte"].lower()
