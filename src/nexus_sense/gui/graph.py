"""Grafico de temperatura com eixo em graus, duas series.

A GUI antiga desenha as linhas sem referencia nenhuma: sobe e desce, e
nao se sabe entre que valores. Aqui a escala e fixa de 20 a 100 graus,
com marca a cada 20, e o valor e grampeado nas pontas -- uma CPU a 105
nao desenha fora da caixa. Ver spec secao 6.1.

**Um eixo so, nunca dois.** As duas series sao °C, entao dividem a mesma
escala; dois eixos com escalas diferentes fariam duas linhas que nao se
podem comparar parecerem comparaveis.

A identidade de cada linha nunca depende so da cor: alem das duas cores
ha rotulo direto na ponta de cada uma, e o cartao correspondente tem um
ponto da mesma cor no titulo. Ver interface.md secao 2.
"""

from collections import deque

from PySide6.QtCore import QElapsedTimer, QTimer, Qt
from PySide6.QtGui import QColor, QFontMetrics, QPainter, QPen
from PySide6.QtWidgets import QWidget

from .style import is_dark, palette_for

TEMP_MIN = 20
TEMP_MAX = 100
TICK = 20
MARGEM_ESQUERDA = 34
# Folga vertical para o texto do eixo caber inteiro. Sem ela o "100°" e o
# "20°" sao cortados pelas bordas da caixa -- apareceu na primeira
# renderizacao e e o defeito que este grafico existe para nao ter.
MARGEM_TOPO = 9
MARGEM_BASE = 9

# As duas series. O indigo e o acento da marca; o rosa foi escolhido por
# validacao contra ele -- violeta e ciano reprovam sob daltonismo, com
# separacao de 2,9 e 13,4. Ver interface.md secao 2.
COR_CPU = "#4A78C8"
COR_GPU = "#D2688F"
ANIMATION_DURATION_MS = 100
FRAME_INTERVAL_MS = 16


def y_for_celsius(celsius, height):
    """Onde este valor cai, em pixels, com 0 no topo da caixa."""
    fracao = (celsius - TEMP_MIN) / (TEMP_MAX - TEMP_MIN)
    fracao = max(0.0, min(1.0, fracao))
    return height * (1.0 - fracao)


def interpolated_value(previous, current, progress):
    """Interpola temperaturas válidas; buracos continuam sendo buracos."""
    if previous is None or current is None:
        return current
    return previous + (current - previous) * progress


class TemperatureGraph(QWidget):
    def __init__(self, maxlen=120, parent=None):
        super().__init__(parent)
        self.samples = deque(maxlen=maxlen)
        self.gpu_samples = deque(maxlen=maxlen)
        self.cor_cpu = COR_CPU
        self.cor_gpu = COR_GPU
        self._cpu_animation_start = None
        self._gpu_animation_start = None
        self._animation_clock = QElapsedTimer()
        self._animation_timer = QTimer(self)
        self._animation_timer.setInterval(FRAME_INTERVAL_MS)
        self._animation_timer.timeout.connect(self._animation_tick)
        self.setMinimumHeight(140)

    def add_sample(self, celsius, gpu_celsius=None):
        """None na CPU e ignorado: sem sensor nao ha ponto, e zero seria
        mentira. Na GPU o None entra como buraco -- adormecida no meio da
        janela interrompe a linha em vez de derruba-la ao chao."""
        if celsius is None:
            return
        cpu_previous = self._displayed_endpoint(
            self.samples, self._cpu_animation_start
        )
        gpu_previous = self._displayed_endpoint(
            self.gpu_samples, self._gpu_animation_start
        )
        self.samples.append(float(celsius))
        self.gpu_samples.append(
            None if gpu_celsius is None else float(gpu_celsius)
        )
        if len(self.samples) > 1:
            self._cpu_animation_start = cpu_previous
            self._gpu_animation_start = gpu_previous
            self._animation_clock.restart()
            self._animation_timer.start()
        self.update()

    # ------------------------------------------------------------------

    def _animation_progress(self):
        if not self._animation_timer.isActive():
            return 1.0
        return min(1.0, self._animation_clock.elapsed() / ANIMATION_DURATION_MS)

    def _displayed_endpoint(self, values, start):
        if not values:
            return None
        return interpolated_value(start, values[-1], self._animation_progress())

    def _animated_values(self, values, start, progress):
        result = list(values)
        if result:
            result[-1] = interpolated_value(start, result[-1], progress)
        return result

    def _animation_tick(self):
        if self._animation_progress() >= 1.0:
            self._animation_timer.stop()
        self.update()

    def _cores(self):
        """Cores do eixo, vindas dos tokens e nao da paleta do Qt.

        A paleta do tema nao serve aqui: no Breeze escuro o papel Mid e
        #1c1f21, praticamente igual ao fundo do cartao, e o eixo some.
        Medido na maquina depois que a folha de estilo entrou. Os tokens
        garantem contraste porque foram escolhidos para isso.
        """
        c = palette_for(is_dark(self.palette()))
        return QColor(c["texto_3"]), QColor(c["linha_forte"])

    def _y(self, valor, altura):
        """Do grau ao pixel, ja dentro da area util."""
        util = altura - MARGEM_TOPO - MARGEM_BASE
        return MARGEM_TOPO + y_for_celsius(valor, util)

    def _desenha_serie(
        self, pintor, dados, cor, rotulo, altura, passo, primeiro, deslocamento
    ):
        """Uma serie. Trechos separados por None sao desenhados soltos."""
        caneta = QPen(QColor(cor), 2)
        caneta.setJoinStyle(Qt.RoundJoin)
        caneta.setCapStyle(Qt.RoundCap)
        pintor.setPen(caneta)

        anterior = None
        ultimo = None
        for indice, valor in enumerate(dados, start=primeiro):
            if valor is None:
                anterior = None
                continue
            x = MARGEM_ESQUERDA + (indice + deslocamento) * passo
            y = self._y(valor, altura)
            if anterior is not None:
                pintor.drawLine(int(anterior[0]), int(anterior[1]), int(x), int(y))
            anterior = (x, y)
            ultimo = (x, y)

        if ultimo is None:
            return
        # A ponta se desloca com a linha. O rótulo fica preso à borda
        # direita e acompanha somente o eixo vertical; usar ultimo[0] aqui
        # fazia "CPU" e "GPU" tremerem para os lados a cada amostra.
        pintor.setBrush(QColor(cor))
        pintor.drawEllipse(int(ultimo[0]) - 3, int(ultimo[1]) - 3, 6, 6)
        pintor.drawText(self.width() - 34, int(ultimo[1]) - 6, rotulo)

    def paintEvent(self, evento):
        pintor = QPainter(self)
        pintor.setRenderHint(QPainter.Antialiasing)
        altura = self.height()
        largura = self.width()
        area = largura - MARGEM_ESQUERDA

        cor_texto, cor_grade = self._cores()
        metrica = QFontMetrics(self.font())

        # eixo: uma marca a cada TICK graus, com o numero a esquerda
        for grau in range(TEMP_MIN, TEMP_MAX + 1, TICK):
            y = self._y(grau, altura)
            pintor.setPen(QPen(cor_grade, 1, Qt.DotLine))
            pintor.drawLine(MARGEM_ESQUERDA, int(y), largura, int(y))
            pintor.setPen(QPen(cor_texto))
            pintor.drawText(0, int(y) + metrica.ascent() // 2, f"{grau}°")

        if len(self.samples) < 2 or area <= 1:
            return

        passo = area / (self.samples.maxlen - 1)
        # alinhado a direita: a amostra mais nova encosta na borda
        primeiro = self.samples.maxlen - len(self.samples)
        progresso = self._animation_progress()
        deslocamento = 1.0 - progresso if self._animation_timer.isActive() else 0.0
        cpu_values = self._animated_values(
            self.samples, self._cpu_animation_start, progresso
        )
        gpu_values = self._animated_values(
            self.gpu_samples, self._gpu_animation_start, progresso
        )

        self._desenha_serie(
            pintor,
            cpu_values,
            self.cor_cpu,
            "CPU",
            altura,
            passo,
            primeiro,
            deslocamento,
        )
        if any(v is not None for v in gpu_values):
            self._desenha_serie(
                pintor,
                gpu_values,
                self.cor_gpu,
                "GPU",
                altura,
                passo,
                primeiro,
                deslocamento,
            )
