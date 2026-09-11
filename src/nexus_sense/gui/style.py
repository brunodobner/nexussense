"""A folha de estilo, nas duas peles.

O sistema visual esta em docs/interface.md; este arquivo so o traduz para
QSS. Toda cor vem das duas tabelas abaixo, e nenhum widget carrega cor
propria -- trocar de pele e trocar um dicionario.

Duas regras que valem a pena guardar:

- **A pele segue o tema do sistema.** `is_dark()` decide olhando a
  luminancia da janela na paleta corrente, e nao o nome do tema: nome de
  tema e texto livre e quebra em qualquer distribuicao que renomeie.
- **Cor nunca vem sozinha.** As tres semanticas -- verde, ambar e
  vermelho -- sempre acompanham um icone ou uma palavra. A QSS aqui so
  colore o que ja diz o que e.
"""

# Os nomes sao os papeis, nao as cores: `superficie`, e nao `cinza_18`.
# Ver interface.md secao 2.
ESCURO = {
    "fundo": "#10141B",
    "painel": "#171D27",
    "cartao": "#1B222E",
    "elevado": "#222A38",
    "linha": "#29323F",
    "linha_forte": "#364152",
    "texto": "#E5EAF2",
    "texto_2": "#98A4B6",
    "texto_3": "#6B7789",
    "marca": "#4A78C8",
    "marca_texto": "#7FA5E6",
    "marca_fundo": "#1C2740",
    "ok": "#4FB287",
    "atencao": "#D3A05A",
    "falha": "#E0736B",
}

CLARO = {
    "fundo": "#EFF2F7",
    "painel": "#FFFFFF",
    "cartao": "#FFFFFF",
    "elevado": "#F4F6FA",
    "linha": "#E0E5EE",
    "linha_forte": "#CBD3E0",
    "texto": "#171C25",
    "texto_2": "#57626F",
    "texto_3": "#838E9D",
    "marca": "#4A78C8",
    "marca_texto": "#35619F",
    "marca_fundo": "#E8EFFA",
    "ok": "#23795A",
    "atencao": "#91601D",
    "falha": "#A73B34",
}


def is_dark(palette):
    """A pele a usar, decidida pela luminancia e nao pelo nome do tema.

    Nome de tema e texto livre -- 'BreezeDark', 'Adwaita-dark', qualquer
    coisa -- e quebra na primeira distribuicao que renomeie. A luminancia
    do fundo da janela responde a mesma pergunta e nao mente.
    """
    cor = palette.window().color()
    luminancia = 0.299 * cor.red() + 0.587 * cor.green() + 0.114 * cor.blue()
    return luminancia < 128


def palette_for(dark):
    return ESCURO if dark else CLARO


def stylesheet(dark):
    """A QSS inteira, montada a partir da pele escolhida."""
    c = palette_for(dark)
    return f"""
/* ---------------------------------------------------------------- base */
QWidget {{
    background: {c["fundo"]};
    color: {c["texto"]};
    font-size: 13px;
}}

/* --------------------------------------------------- barra lateral */
QListWidget {{
    background: {c["painel"]};
    border: none;
    border-right: 1px solid {c["linha"]};
    padding: 8px 6px;
    outline: none;
}}
QListWidget::item {{
    padding: 8px 10px;
    border-radius: 7px;
    color: {c["texto_2"]};
}}
QListWidget::item:hover {{
    background: {c["elevado"]};
    color: {c["texto"]};
}}
QListWidget::item:selected {{
    background: {c["marca_fundo"]};
    color: {c["marca_texto"]};
    font-weight: 600;
}}

/* O rodape do agente: informa sem competir. */
QLabel#agente {{
    color: {c["texto_2"]};
    font-size: 12px;
    padding: 8px 10px;
    border-top: 1px solid {c["linha"]};
}}

/* -------------------------------------------------------- titulos */
QLabel#titulo {{
    background: transparent;
    font-size: 17px;
    font-weight: 600;
    padding-bottom: 10px;
}}
QWidget#secao_ventoinhas,
QWidget#controles_ventoinhas {{
    background: transparent;
}}

/* Titulo de cartao e de secao: mono, caixa alta, terciario. E rotulo,
   nao manchete -- por isso e o menor texto da tela. */
QLabel#cartao_titulo {{
    font-family: "IBM Plex Mono", monospace;
    font-size: 10px;
    font-weight: 500;
    letter-spacing: 1px;
    color: {c["texto_3"]};
}}

QLabel#cartao_selo {{
    font-family: "IBM Plex Mono", monospace;
    font-size: 9px;
    font-weight: 600;
    letter-spacing: 1px;
    color: {c["atencao"]};
    border: 1px solid {c["atencao"]};
    border-radius: 8px;
    padding: 1px 7px;
}}

/* ------------------------------------------------------- cartoes */
QFrame {{
    background: {c["cartao"]};
    border: 1px solid {c["linha"]};
    border-radius: 9px;
}}
QFrame QLabel {{
    background: transparent;
    border: none;
}}

QGroupBox {{
    background: {c["cartao"]};
    border: 1px solid {c["linha"]};
    border-radius: 9px;
    margin-top: 14px;
    padding: 14px 12px 10px;
    font-family: "IBM Plex Mono", monospace;
    font-size: 10px;
    letter-spacing: 1px;
    color: {c["texto_3"]};
}}
QGroupBox::title {{
    subcontrol-origin: margin;
    left: 12px;
    padding: 0 4px;
}}

/* ---------------------------------------------- linhas de controle */
QLabel#linha_titulo {{
    font-size: 13px;
    font-weight: 600;
}}
QLabel#linha_subtitulo {{
    color: {c["texto_2"]};
    font-size: 12px;
}}
/* O motivo de estar cinza fica em ambar: e atencao, nao falha -- ha o
   que fazer, e a frase diz o que. */
QLabel#linha_motivo {{
    color: {c["atencao"]};
    font-size: 12px;
}}
QLabel#mensagem {{
    color: {c["falha"]};
    font-size: 12px;
}}

/* ------------------------------------------------------ diagnostico */
QLabel#check_ok {{
    color: {c["ok"]};
    font-weight: 600;
}}
QLabel#check_falhou {{
    color: {c["falha"]};
    font-weight: 600;
}}
QLabel#check_detalhe {{
    color: {c["texto_2"]};
    font-size: 12px;
    padding-left: 18px;
}}
QLabel#diagnostico_rotulo {{
    background: transparent;
    border: none;
    border-radius: 0;
    padding: 0;
    color: {c["texto_2"]};
    font-weight: 600;
}}
QLabel#diagnostico_valor {{
    background: transparent;
    border: none;
    border-radius: 0;
    padding: 0;
    color: {c["texto"]};
}}

QLabel#painel_cabecalho {{
    color: {c["texto_2"]};
    padding-bottom: 10px;
}}
QLabel#driver_missing {{
    font-size: 14px;
    padding: 24px;
}}

/* ---------------------------------------------------- perfis termicos */
QPushButton {{
    background: {c["cartao"]};
    border: 1px solid {c["linha"]};
    border-radius: 9px;
    padding: 10px;
    color: {c["texto"]};
}}
QPushButton:hover:enabled {{
    background: {c["elevado"]};
    border-color: {c["linha_forte"]};
}}
/* O perfil corrente: borda da marca e fundo tenue. O hachurado do
   indisponivel e pintado a mao no paintEvent -- QSS nao tem gradiente
   repetido. */
QPushButton:checked {{
    background: {c["marca_fundo"]};
    border: 2px solid {c["marca"]};
    color: {c["marca_texto"]};
    font-weight: 600;
}}
QPushButton#maximum_profile:checked {{
    background: {c["elevado"]};
    border: 2px solid {c["atencao"]};
    color: {c["atencao"]};
    font-weight: 600;
}}
QPushButton:disabled {{
    color: {c["texto_3"]};
}}

/* ------------------------------------------------------- controles */
QCheckBox::indicator {{
    width: 17px;
    height: 17px;
    border: 1px solid {c["linha_forte"]};
    border-radius: 4px;
    background: {c["elevado"]};
}}
QCheckBox::indicator:checked {{
    background: {c["marca"]};
    border-color: {c["marca"]};
}}
QCheckBox::indicator:disabled {{
    border-color: {c["linha"]};
}}

QComboBox {{
    background: {c["elevado"]};
    border: 1px solid {c["linha_forte"]};
    border-radius: 6px;
    padding: 5px 10px;
    min-width: 190px;
    color: {c["texto"]};
}}
QComboBox:disabled {{
    color: {c["texto_3"]};
    border-color: {c["linha"]};
}}
QComboBox QAbstractItemView {{
    background: {c["painel"]};
    border: 1px solid {c["linha_forte"]};
    selection-background-color: {c["marca_fundo"]};
    selection-color: {c["marca_texto"]};
    outline: none;
}}

/* Cursor das ventoinhas: trilho fino, alca grande o bastante para pegar
   com o mouse sem mira. */
QSlider::groove:horizontal {{
    height: 5px;
    background: {c["elevado"]};
    border: 1px solid {c["linha"]};
    border-radius: 3px;
}}
QSlider::sub-page:horizontal {{
    background: {c["marca"]};
    border: 1px solid {c["marca"]};
    border-radius: 3px;
}}
QSlider::handle:horizontal {{
    width: 15px;
    height: 15px;
    margin: -6px 0;
    border-radius: 8px;
    background: {c["marca"]};
    border: 2px solid {c["painel"]};
}}
QSlider::handle:horizontal:hover {{
    background: {c["marca_texto"]};
}}
QSlider::groove:horizontal:disabled,
QSlider::sub-page:horizontal:disabled {{
    background: {c["linha"]};
    border-color: {c["linha"]};
}}
QSlider::handle:horizontal:disabled {{
    background: {c["linha_forte"]};
}}

QMenu {{
    background: {c["painel"]};
    border: 1px solid {c["linha_forte"]};
    border-radius: 8px;
    padding: 5px;
}}
QMenu::item {{
    padding: 6px 22px 6px 12px;
    border-radius: 5px;
}}
QMenu::item:selected {{
    background: {c["marca_fundo"]};
    color: {c["marca_texto"]};
}}
QMenu::separator {{
    height: 1px;
    background: {c["linha"]};
    margin: 5px 8px;
}}
"""


def apply_to(app):
    """Aplica a pele que combina com o tema de quem esta usando."""
    escuro = is_dark(app.palette())
    app.setStyleSheet(stylesheet(escuro))
    return escuro
