"""A linha de controle que Bateria e Teclado usam.

Titulo, subtitulo e o controle a direita. O subtitulo e onde mora o
aviso que pertence aquele controle -- e nao um paragrafo solto no fim da
tela, como na GUI antiga. Ver spec secao 6.3.
"""

from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout

# Frase unica para os dois motivos de nao poder escrever: estar fora do
# grupo, e estar nele numa sessao que ainda nao o herdou. O sintoma e o
# mesmo e a saida tambem. Ver spec secao 9.
SEM_PERMISSAO = (
    "somente leitura: a sessão não tem o grupo nexus_sense "
    "(se você acabou de entrar no grupo, relogue)"
)


class ControlRow(QFrame):
    def __init__(self, title, subtitle, widget, parent=None):
        super().__init__(parent)
        self.setFrameShape(QFrame.StyledPanel)
        self.widget = widget

        self.title = QLabel(title)
        self.title.setObjectName("linha_titulo")
        self.subtitle = QLabel(subtitle)
        self.subtitle.setObjectName("linha_subtitulo")
        self.subtitle.setWordWrap(True)
        self.subtitle.setVisible(bool(subtitle))
        self.reason = QLabel("")
        self.reason.setObjectName("linha_motivo")
        self.reason.setWordWrap(True)
        self.reason.setVisible(False)

        texto = QVBoxLayout()
        texto.addWidget(self.title)
        texto.addWidget(self.subtitle)
        texto.addWidget(self.reason)

        leiaute = QHBoxLayout(self)
        leiaute.addLayout(texto, 1)
        leiaute.addWidget(widget)

    def set_reason(self, texto):
        self.reason.setText(texto)
        self.reason.setVisible(bool(texto))
