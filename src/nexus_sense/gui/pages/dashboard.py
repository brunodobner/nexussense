"""Painel: o que a maquina esta fazendo agora.

Alinhamento e requisito desta tela, nao acabamento. Os tres cartoes da
linha de cima tem o mesmo numero de linhas, na mesma ordem de campos, e
por isso a mesma altura -- e por isso os olhos varrem em coluna. Hoje a
GUI antiga tem tres alturas diferentes. Ver spec secao 6.1.

Campo sem valor mostra travessao, nunca zero: zero e um numero, e
numero errado engana.
"""

from PySide6.QtWidgets import (
    QFormLayout,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QVBoxLayout,
    QWidget,
)
from PySide6.QtCore import Signal

from ... import model, telemetry
from ...maximum import MaximumMode
from ..graph import COR_CPU, COR_GPU, TemperatureGraph

VAZIO = "—"

# Os tres cartoes de cima tem exatamente este numero de linhas. Cartao
# com menos informacao preenche com travessao em vez de encolher.
LINHAS_POR_CARTAO = 3

# O sysfs devolve o estado da bateria em ingles. O desconhecido cai no
# valor cru, e nao em travessao: o que o driver disser continua visivel,
# mesmo que a gente nao tenha previsto. Ver interface.md secao 5.
ESTADO_BATERIA = {
    "Charging": "carregando",
    "Discharging": "descarregando",
    "Not charging": "não carregando",
    "Full": "cheia",
    "Unknown": "desconhecido",
}


def battery_status(bruto):
    if not bruto:
        return None
    return ESTADO_BATERIA.get(bruto, bruto)


class Card(QFrame):
    """Cartao de titulo e linhas rotulo/valor, com altura previsivel.

    O titulo pode carregar duas coisas alem do nome: um ponto da cor da
    serie -- que e o que liga o cartao a sua linha no grafico -- e um
    selo, que so aparece quando ha estado anormal a dizer.
    """

    def __init__(self, title, fields, parent=None, series_color=None):
        super().__init__(parent)
        self.setFrameShape(QFrame.StyledPanel)
        self.rows = {}

        leiaute = QVBoxLayout(self)

        linha_titulo = QHBoxLayout()
        self.dot = QLabel("")
        self.dot.setObjectName("cartao_ponto")
        self.dot.setFixedSize(8, 8)
        if series_color is None:
            self.dot.setVisible(False)
        else:
            self.dot.setStyleSheet(
                f"background:{series_color}; border-radius:4px;"
            )
        linha_titulo.addWidget(self.dot)

        self.title = QLabel(title)
        self.title.setObjectName("cartao_titulo")
        linha_titulo.addWidget(self.title)

        self.badge = QLabel("")
        self.badge.setObjectName("cartao_selo")
        self.badge.setVisible(False)
        linha_titulo.addStretch(1)
        linha_titulo.addWidget(self.badge)
        leiaute.addLayout(linha_titulo)

        formulario = QFormLayout()
        formulario.setLabelAlignment(formulario.labelAlignment())
        for chave, rotulo in fields:
            valor = QLabel(VAZIO)
            valor.setObjectName(f"valor_{chave}")
            formulario.addRow(f"{rotulo}:", valor)
            self.rows[chave] = valor
        leiaute.addLayout(formulario)

    def set_value(self, chave, texto):
        self.rows[chave].setText(texto if texto else VAZIO)

    def set_badge(self, texto):
        """Selo de estado. Vazio o esconde -- normal nao merece selo."""
        self.badge.setText(texto)
        self.badge.setVisible(bool(texto))


class DashboardPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None, maximum=None):
        super().__init__(parent)
        self.controls = controls
        self.maximum = maximum or MaximumMode(controls)
        self.graph = TemperatureGraph()

        self.header = QLabel("")
        self.header.setObjectName("painel_cabecalho")

        # CPU e GPU tem os mesmos tres campos na mesma ordem: e o que faz
        # o olho varrer a coluna. Ver interface.md secao 4.2.
        campos_dispositivo = (
            ("modelo", "Modelo"),
            ("uso", "Uso"),
            ("temperatura", "Temperatura"),
        )
        self.cards = {
            "cpu": Card("CPU", campos_dispositivo, series_color=COR_CPU),
            "gpu": Card("GPU", campos_dispositivo, series_color=COR_GPU),
            "ventoinhas": Card(
                "Ventoinhas",
                (("cpu", "CPU"), ("gpu", "GPU"), ("modo", "Modo")),
            ),
            "bateria": Card(
                "Bateria",
                (("carga", "Carga"), ("estado", "Estado"), ("limite", "Limite de carga")),
            ),
        }

        # Uma grade so para as duas linhas. Duas grades irmas, com fracoes
        # proprias, erram por alguns pixels porque os vaos nao coincidem --
        # e a coluna da Bateria nao cai sob a das Ventoinhas.
        grade = QGridLayout()
        for coluna, nome in enumerate(("cpu", "gpu", "ventoinhas")):
            grade.addWidget(self.cards[nome], 0, coluna)
            grade.setColumnStretch(coluna, 1)

        temperatura = Card("Temperatura", ())
        temperatura.layout().addWidget(self.graph)
        grade.addWidget(temperatura, 1, 0, 1, 2)
        grade.addWidget(self.cards["bateria"], 1, 2)

        raiz = QVBoxLayout(self)
        raiz.addWidget(self.header)
        raiz.addLayout(grade)
        raiz.addStretch(1)

        self._cpu_name = None
        self._gpu_name = None

    def has_content(self, state):
        return True

    def apply_state(self, state):
        perfil = state.profile
        fonte = {True: "na tomada", False: "na bateria"}.get(state.on_ac, VAZIO)
        if self.maximum.active(state.on_ac):
            rotulo = f"{model.MAXIMUM_LABEL} (CPU + GPU)"
        else:
            rotulo = f"{model.LABELS.get(perfil, perfil)} ({perfil})" if perfil else VAZIO
        self.header.setText(f"Perfil: {rotulo}   ·   {fonte}")

        # Os dois modelos nao mudam enquanto o programa roda: le uma vez.
        # O da GPU sai do PCI e nao a acorda. Ver interface.md secao 4.2.
        if self._cpu_name is None:
            self._cpu_name = telemetry.cpu_name(self.controls.sysfs) or VAZIO
        self.cards["cpu"].set_value("modelo", self._cpu_name)

        if self._gpu_name is None:
            self._gpu_name = telemetry.gpu_name(self.controls.sysfs) or VAZIO
        self.cards["gpu"].set_value("modelo", self._gpu_name)

        # O setpoint, nao a rotacao: "0,0" e automatico. Ver spec secao 2.5.
        if state.fan_speed is None:
            self.cards["ventoinhas"].set_value("modo", VAZIO)
        elif state.fan_speed == (0, 0):
            self.cards["ventoinhas"].set_value("modo", "automático")
        else:
            # Na escala do cursor da tela Desempenho, nao na do firmware:
            # os dois lugares tem de mostrar o mesmo numero.
            cpu, gpu = (model.fan_firmware_to_bar(v) for v in state.fan_speed)
            self.cards["ventoinhas"].set_value("modo", f"manual — {cpu}% / {gpu}%")

        self.cards["bateria"].set_value(
            "limite",
            "80% (limitador ligado)" if state.battery_limiter else "sem limite",
        )

    def apply_sample(self, sample):
        self.cards["cpu"].set_value(
            "temperatura",
            f"{sample.cpu_temp:.1f} °C" if sample.cpu_temp is not None else VAZIO,
        )
        self.cards["cpu"].set_value(
            "uso",
            f"{sample.cpu_usage:.0f}%" if sample.cpu_usage is not None else VAZIO,
        )
        gpu_temp = None
        if sample.gpu is not None and not sample.gpu.asleep:
            gpu_temp = sample.gpu.temperature
        self.graph.add_sample(sample.cpu_temp, gpu_temp)

        if sample.fans is None:
            self.cards["ventoinhas"].set_value("cpu", VAZIO)
            self.cards["ventoinhas"].set_value("gpu", VAZIO)
        else:
            cpu, gpu = sample.fans
            self.cards["ventoinhas"].set_value("cpu", f"{cpu} rpm")
            self.cards["ventoinhas"].set_value("gpu", f"{gpu} rpm")

        self._aplica_gpu(sample.gpu)

        if sample.battery is None:
            self.cards["bateria"].set_value("carga", VAZIO)
            self.cards["bateria"].set_value("estado", VAZIO)
        else:
            carga = sample.battery.capacity
            self.cards["bateria"].set_value(
                "carga", f"{carga}%" if carga is not None else VAZIO
            )
            self.cards["bateria"].set_value(
                "estado", battery_status(sample.battery.status) or VAZIO
            )

    def _aplica_gpu(self, leitura):
        """O cartao da GPU nao tem linha de estado.

        Se ha temperatura e uso na tela, a placa esta acordada -- dizer
        isso de novo numa linha propria e redundancia. O estado so aparece
        quando e anormal, e ai vira selo no titulo. Ver interface.md
        secao 4.2.
        """
        cartao = self.cards["gpu"]
        if leitura is None:
            cartao.set_badge("ausente")
            cartao.set_value("temperatura", VAZIO)
            cartao.set_value("uso", VAZIO)
            return
        if leitura.asleep:
            # Nao sondamos de proposito. O modelo continua na tela: le-lo
            # nao depende de a placa estar acordada. Ver spec secao 10.2.
            cartao.set_badge("adormecida")
            cartao.set_value("temperatura", VAZIO)
            cartao.set_value("uso", VAZIO)
            return
        # Ociosa: a sonda se calou para a placa poder dormir, e os numeros
        # sao os da ultima leitura. Ficam na tela, com o selo dizendo por
        # que pararam de andar. Ver docs/estado.md, etapa 4b.
        cartao.set_badge("ociosa" if leitura.idle else "")
        cartao.set_value(
            "temperatura",
            f"{leitura.temperature:.0f} °C" if leitura.temperature is not None else VAZIO,
        )
        cartao.set_value(
            "uso", f"{leitura.utilization}%" if leitura.utilization is not None else VAZIO
        )
