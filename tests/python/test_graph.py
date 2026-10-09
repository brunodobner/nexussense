import pytest

from nexus_sense.gui.graph import (
    FRAME_INTERVAL_MS,
    TEMP_MAX,
    TEMP_MIN,
    TemperatureGraph,
    interpolated_value,
    y_for_celsius,
)


def test_o_minimo_da_escala_fica_no_pe_do_grafico():
    assert y_for_celsius(TEMP_MIN, 200) == pytest.approx(200.0)


def test_o_maximo_da_escala_fica_no_topo():
    assert y_for_celsius(TEMP_MAX, 200) == pytest.approx(0.0)


def test_o_meio_da_escala_fica_no_meio():
    meio = (TEMP_MIN + TEMP_MAX) / 2
    assert y_for_celsius(meio, 200) == pytest.approx(100.0)


def test_valor_acima_da_escala_e_grampeado_no_topo():
    """Uma CPU a 105 graus nao pode desenhar fora da caixa."""
    assert y_for_celsius(150, 200) == pytest.approx(0.0)


def test_valor_abaixo_da_escala_e_grampeado_no_pe():
    assert y_for_celsius(-40, 200) == pytest.approx(200.0)


def test_o_grafico_interpola_sem_consultar_novamente_o_sensor():
    assert interpolated_value(40.0, 50.0, 0.5) == pytest.approx(45.0)
    assert interpolated_value(40.0, None, 0.5) is None


def test_a_ponta_leva_um_intervalo_de_sondagem_para_chegar():
    """E o que faz a linha deslizar sem parar entre uma amostra e outra.
    Com a duracao menor que o intervalo ela andaria aos trancos."""
    from nexus_sense.gui import graph, poller

    assert graph.ANIMATION_DURATION_MS == poller.INTERVALO_PADRAO


def test_a_animacao_repinta_em_aproximadamente_60_fps(qtbot):
    g = TemperatureGraph()
    qtbot.addWidget(g)
    assert FRAME_INTERVAL_MS == 16
    assert g._animation_timer.interval() == 16
    g.add_sample(40.0)
    g.add_sample(50.0)
    assert g._animation_timer.isActive()


def test_rotulo_da_serie_nao_balanca_na_horizontal(qtbot):
    class PainterRecorder:
        def __init__(self):
            self.text_x = []

        def setPen(self, *_args):
            pass

        def setBrush(self, *_args):
            pass

        def drawLine(self, *_args):
            pass

        def drawEllipse(self, *_args):
            pass

        def drawText(self, x, _y, _text):
            self.text_x.append(x)

    g = TemperatureGraph(maxlen=4)
    qtbot.addWidget(g)
    g.resize(320, 160)
    posicoes = []
    for deslocamento in (1.0, 0.5, 0.0):
        painter = PainterRecorder()
        g._desenha_serie(
            painter, [40.0, 60.0], g.cor_cpu, "CPU", 160, 20, 1, deslocamento
        )
        posicoes.append(painter.text_x[-1])
    assert posicoes == [286, 286, 286]


def test_o_grafico_guarda_as_amostras_ate_o_limite(qtbot):
    g = TemperatureGraph(maxlen=5)
    qtbot.addWidget(g)
    for valor in range(10):
        g.add_sample(float(valor))
    assert list(g.samples) == [5.0, 6.0, 7.0, 8.0, 9.0]


def test_amostra_none_e_ignorada(qtbot):
    """Sem coretemp nao ha o que plotar, e a linha nao pode virar zero."""
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.add_sample(None)
    assert list(g.samples) == []


def test_o_grafico_desenha_sem_explodir(qtbot):
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.resize(300, 150)
    for valor in (40.0, 55.0, 61.5):
        g.add_sample(valor)
    assert not g.grab().isNull()


def test_desenha_tambem_sem_amostra_nenhuma(qtbot):
    """A janela abre antes da primeira leitura."""
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.resize(300, 150)
    assert not g.grab().isNull()
