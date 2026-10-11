"""Desempenho: os perfis termicos.

A regra que manda nesta tela: as posicoes sao fixas. O que muda com a
fonte de energia e o estado de cada botao, nunca a quantidade nem a
ordem. Ver spec secao 6.2 e decisao D7.
"""

from PySide6.QtCore import QTimer, Qt, Signal
from PySide6.QtGui import QPainter, QPen
from PySide6.QtWidgets import (
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSlider,
    QStyle,
    QStyleOptionSlider,
    QVBoxLayout,
    QWidget,
)

from ... import model
from ...device import WriteError, read_state
from ...maximum import MaximumMode

# Quatro perfis do firmware e o modo composto do Nexus Sense.
COLUNAS = 5

# Os tres modos que o setpoint das ventoinhas assume. "0,0" e o driver
# assumindo o controle -- automatico, e nao parada. Ver spec secao 2.5.
FAN_AUTO = (0, 0)
FAN_MAX = (100, 100)

# Quanto o cursor espera parado antes de escrever. Escrever a cada passo
# do arrasto mandava dezenas de comandos ao firmware por segundo, cada um
# seguido de uma releitura completa do aparelho.
ATRASO_CURSOR_MS = 150

FAN_ROTULOS = (
    ("auto", "Automático", "o driver decide pela temperatura"),
    ("max", "Máximo", "as duas ventoinhas a 100%"),
    ("manual", "Manual", "você escolhe a velocidade de cada uma"),
)


def fan_mode(fan_speed):
    """Qual dos tres modos este setpoint representa. None se ilegivel."""
    if fan_speed is None:
        return None
    if fan_speed == FAN_AUTO:
        return "auto"
    if fan_speed == FAN_MAX:
        return "max"
    return "manual"


SOMENTE_LEITURA = (
    "Os perfis estão em somente-leitura: a permissão de grupo não está "
    "aplicada nesta sessão. Confira o Diagnóstico."
)


def unavailable_reason(profile, state):
    """Por que este perfil nao pode ser usado agora. Vazio se pode."""
    if profile in state.available:
        return ""
    if state.on_ac is False and profile in model.AC_ONLY:
        return "o driver recusa este perfil na bateria"
    return "não disponível neste firmware"


def maximum_reason(state):
    if state.on_ac is not True:
        return "suspenso na bateria; volta quando a tomada for reconectada"
    if "balanced-performance" not in state.available:
        return "o firmware não oferece o perfil térmico necessário"
    if not state.profile_writable or "fan_speed" not in state.writable:
        return SOMENTE_LEITURA
    return ""


class ProfileButton(QPushButton):
    """Botao de perfil que sabe se desenhar hachurado.

    O hachurado e pintado a mao porque QSS nao tem gradiente repetido: a
    alternativa seria uma imagem de fundo por tamanho de botao.
    """

    def __init__(self, profile, parent=None):
        super().__init__(parent)
        self.profile = profile
        self.unavailable = False
        self.reason = ""
        self.setCheckable(True)
        self.setMinimumHeight(64)

    def paintEvent(self, evento):
        super().paintEvent(evento)
        if not self.unavailable:
            return
        pintor = QPainter(self)
        caneta = QPen(self.palette().mid().color())
        caneta.setWidth(1)
        pintor.setPen(caneta)
        largura, altura = self.width(), self.height()
        # diagonais a cada 6 px, cobrindo a caixa inteira
        for x in range(-altura, largura, 6):
            pintor.drawLine(x, altura, x + altura, 0)


class DirectSlider(QSlider):
    """Cursor cujo clique no trilho escolhe diretamente aquele ponto."""

    def mousePressEvent(self, event):
        if event.button() != Qt.LeftButton:
            super().mousePressEvent(event)
            return

        option = QStyleOptionSlider()
        self.initStyleOption(option)
        handle = self.style().subControlRect(
            QStyle.CC_Slider, option, QStyle.SC_SliderHandle, self
        )
        if handle.contains(event.position().toPoint()):
            super().mousePressEvent(event)
            return

        usable = max(1, self.width() - handle.width())
        position = round(event.position().x() - handle.width() / 2)
        value = QStyle.sliderValueFromPosition(
            self.minimum(), self.maximum(), max(0, min(position, usable)), usable
        )
        self.setValue(value)
        event.accept()


class PerformancePage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None, maximum=None):
        super().__init__(parent)
        self.controls = controls
        self.maximum = maximum or MaximumMode(controls)
        self.buttons = {}
        # Guarda contra o setValue que emite valueChanged ao repintar.
        self._aplicando = False
        self._fan_timer = QTimer(self)
        self._fan_timer.setSingleShot(True)
        self._fan_timer.setInterval(ATRASO_CURSOR_MS)
        self._fan_timer.timeout.connect(self._escreve_cursores)
        self._grade = QGridLayout()
        self.message_label = QLabel("")
        self.message_label.setWordWrap(True)
        self.message_label.setObjectName("mensagem")

        raiz = QVBoxLayout(self)
        titulo = QLabel("Perfil térmico")
        titulo.setObjectName("titulo")
        raiz.addWidget(titulo)
        raiz.addLayout(self._grade)
        raiz.addWidget(self._monta_ventoinhas())
        raiz.addWidget(self.message_label)
        raiz.addStretch(1)

    # ------------------------------------------------------- ventoinhas

    def _monta_ventoinhas(self):
        """Tres modos, e os dois cursores que so o manual usa."""
        self.fan_box = QWidget()
        self.fan_box.setObjectName("secao_ventoinhas")
        caixa = QVBoxLayout(self.fan_box)
        caixa.setContentsMargins(0, 18, 0, 0)

        rotulo = QLabel("Ventoinhas")
        rotulo.setObjectName("titulo")
        caixa.addWidget(rotulo)

        self.fan_buttons = {}
        linha = QHBoxLayout()
        for chave, nome, explicacao in FAN_ROTULOS:
            botao = QPushButton(f"{nome}\n{explicacao}")
            botao.setCheckable(True)
            botao.setMinimumHeight(52)
            botao.clicked.connect(lambda _=False, c=chave: self._escolhe_ventoinha(c))
            linha.addWidget(botao)
            self.fan_buttons[chave] = botao
        caixa.addLayout(linha)

        # Os cursores so aparecem no modo manual: em automatico os numeros
        # nao querem dizer nada, e mostra-los convidaria a mexer num valor
        # que o driver ignora.
        self.fan_manual_box = QWidget()
        self.fan_manual_box.setObjectName("controles_ventoinhas")
        manual = QGridLayout(self.fan_manual_box)
        self.fan_sliders = {}
        self.fan_values = {}
        for linha_n, (chave, nome) in enumerate((("cpu", "CPU"), ("gpu", "GPU"))):
            cursor = DirectSlider(Qt.Horizontal)
            cursor.setRange(0, 100)
            cursor.setSingleStep(5)
            cursor.setPageStep(10)
            valor = QLabel("0%")
            valor.setObjectName("linha_subtitulo")
            valor.setMinimumWidth(44)
            cursor.valueChanged.connect(
                lambda v, c=chave: self._cursor_mudou(c, v)
            )
            manual.addWidget(QLabel(nome), linha_n, 0)
            manual.addWidget(cursor, linha_n, 1)
            manual.addWidget(valor, linha_n, 2)
            self.fan_sliders[chave] = cursor
            self.fan_values[chave] = valor
        self.fan_manual_box.setVisible(False)
        caixa.addWidget(self.fan_manual_box)

        return self.fan_box

    def _escolhe_ventoinha(self, modo):
        """Auto e maximo escrevem na hora; manual so revela os cursores.

        Entrar em manual nao pode escrever sozinho -- quem manda na
        ventoinha e o usuario, movendo o cursor.
        """
        self.message_label.setText("")
        # Quem acabou de arrastar e clicou em Automatico quer automatico:
        # a escrita pendente do cursor nao pode chegar depois e desfazer.
        self._fan_timer.stop()
        self._marca_modo(modo)
        if modo == "manual":
            self.fan_manual_box.setVisible(True)
            return
        self.fan_manual_box.setVisible(False)
        self._escreve_ventoinha(*(FAN_AUTO if modo == "auto" else FAN_MAX))

    def _cursor_mudou(self, chave, valor):
        self.fan_values[chave].setText(f"{valor}%")
        if self._aplicando:
            return
        # Reinicia a cada passo: so dispara quando o cursor para.
        self._fan_timer.start()

    def _escreve_cursores(self):
        # A barra vale do piso do firmware a 100: ver model.FAN_FLOOR.
        self._escreve_ventoinha(
            model.fan_bar_to_firmware(self.fan_sliders["cpu"].value()),
            model.fan_bar_to_firmware(self.fan_sliders["gpu"].value()),
        )

    def _cursor_em_uso(self):
        return self._fan_timer.isActive() or any(
            cursor.isSliderDown() for cursor in self.fan_sliders.values()
        )

    def _escreve_ventoinha(self, cpu, gpu):
        try:
            self.controls.set_fan_speed(cpu, gpu)
        except (WriteError, ValueError) as erro:
            self.message_label.setText(getattr(erro, "message", str(erro)))
        self.changed.emit()

    def _marca_modo(self, modo):
        for chave, botao in self.fan_buttons.items():
            botao.setChecked(chave == modo)

    def _aplica_ventoinhas(self, state):
        existe = "fan_speed" in state.features
        self.fan_box.setVisible(existe)
        if not existe:
            return
        gravavel = "fan_speed" in state.writable
        for botao in self.fan_buttons.values():
            botao.setEnabled(gravavel)
            botao.setToolTip("")
        for cursor in self.fan_sliders.values():
            cursor.setEnabled(gravavel)

        # Com o cursor na mao ou uma escrita pendente, a tela nao o puxa de
        # volta: o estado lido ainda e o antigo, e a escrita que vem a
        # seguir levaria o valor antigo junto.
        if self._cursor_em_uso():
            return

        modo = fan_mode(state.fan_speed)
        self._marca_modo(modo)
        self.fan_manual_box.setVisible(modo == "manual")
        if state.fan_speed is not None:
            # Bloquear e obrigatorio: setValue emite valueChanged, e sem
            # isto repintar a tela escreveria na ventoinha.
            self._aplicando = True
            try:
                for chave, valor in zip(("cpu", "gpu"), state.fan_speed):
                    cursor = self.fan_sliders[chave]
                    barra = model.fan_firmware_to_bar(valor)
                    # Duas posicoes da barra podem valer o mesmo degrau
                    # do firmware. Se a que esta la ja vale o que foi
                    # lido, fica: senao o cursor pularia sozinho.
                    if model.fan_bar_to_firmware(
                        cursor.value()
                    ) != model.fan_bar_to_firmware(barra):
                        cursor.setValue(barra)
                    self.fan_values[chave].setText(f"{cursor.value()}%")
            finally:
                self._aplicando = False

    def has_content(self, state):
        # A ventoinha sozinha ja da conteudo: uma maquina que a exponha
        # sem anunciar perfil ainda tem o que mostrar aqui.
        return bool(state.choices) or "fan_speed" in state.features

    def apply_state(self, state):
        maximum_requested = self.maximum.requested()
        self._aplica_ventoinhas(state)
        self._monta(state.choices)
        for nome, botao in self.buttons.items():
            if nome == model.MAXIMUM_MODE:
                continue
            motivo = unavailable_reason(nome, state)
            botao.unavailable = bool(motivo)
            botao.reason = motivo
            botao.setEnabled(not motivo and state.profile_writable)
            botao.setToolTip(motivo or model.LABELS.get(nome, nome))
            # setChecked dispara clicked? Nao: clicked so vem de interacao.
            botao.setChecked(not maximum_requested and nome == state.profile)
            botao.update()

        if model.MAXIMUM_MODE in self.buttons:
            botao = self.buttons[model.MAXIMUM_MODE]
            motivo = maximum_reason(state)
            botao.unavailable = bool(motivo)
            botao.reason = motivo
            botao.setEnabled(not motivo)
            botao.setToolTip(motivo or "CPU e GPU priorizadas; ventoinhas configuráveis")
            botao.setChecked(maximum_requested)
            botao.update()

        # So esta mensagem e gerida aqui. A de erro de escrita fica onde
        # esta: apaga-la a cada repintura a faria sumir antes de ser lida,
        # porque escrever emite changed e a janela repinta na hora.
        if not state.profile_writable and state.choices:
            self.message_label.setText(SOMENTE_LEITURA)
        elif self.message_label.text() == SOMENTE_LEITURA:
            self.message_label.setText("")

    def _monta(self, choices):
        """Cria os botoes uma vez so. A grade nunca e remontada: e
        exatamente isso que mantem as posicoes fixas."""
        if self.buttons or not choices:
            return
        anunciados = [p for p in model.PROFILES if p in set(choices)]
        for indice, nome in enumerate(anunciados):
            botao = ProfileButton(nome)
            botao.setText(f"{model.LABELS.get(nome, nome)}\n{nome}")
            botao.clicked.connect(lambda _=False, p=nome: self._escolhe(p))
            self._grade.addWidget(botao, indice // COLUNAS, indice % COLUNAS)
            self.buttons[nome] = botao
        indice = len(anunciados)
        botao = ProfileButton(model.MAXIMUM_MODE)
        botao.setObjectName("maximum_profile")
        botao.setText(f"{model.MAXIMUM_LABEL}\nCPU + GPU")
        botao.clicked.connect(
            lambda _=False: self._escolhe(model.MAXIMUM_MODE)
        )
        self._grade.addWidget(botao, indice // COLUNAS, indice % COLUNAS)
        self.buttons[model.MAXIMUM_MODE] = botao

    def _escolhe(self, profile):
        self.message_label.setText("")
        try:
            if profile == model.MAXIMUM_MODE:
                state = read_state(self.controls.sysfs)
                if self.maximum.requested():
                    errors = self.maximum.disable()
                else:
                    errors = self.maximum.enable(state)
            elif self.maximum.requested():
                errors = self.maximum.disable(profile)
            else:
                self.controls.set_profile(profile)
                errors = ()
            if errors:
                self.message_label.setText(" · ".join(errors))
        except (WriteError, OSError) as erro:
            # Acontece de verdade: o cabo sai entre o clique e a escrita.
            self.message_label.setText(getattr(erro, "message", str(erro)))
        self.changed.emit()
