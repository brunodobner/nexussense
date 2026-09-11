"""StatusNotifierItem escrito a mao.

Por que nao QSystemTrayIcon: ele expõe Trigger, DoubleClick, MiddleClick
e Context, e nenhum evento de roda. O icone de energia do Plasma tem
scroll porque e um SNI e o host chama Scroll(delta, orientacao) por
DBus. Introspeccao de um item vivo desta sessao confirmou os quatro
metodos. Ver spec secao 7.1 e decisao D6.

As decisoes ficam em funcoes puras no topo do arquivo, fora do objeto
DBus: e o que permite testar o comportamento da bandeja sem barramento,
sem host e sem sessao grafica.
"""

import os

from PySide6.QtCore import QObject, Signal

from .. import model

SERVICE_PREFIX = "org.kde.StatusNotifierItem"
OBJECT_PATH = "/StatusNotifierItem"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"

ICON_BASE = "nexus-sense-tray"
PROFILE_ICON_BASE = f"{ICON_BASE}-v2"


def scroll_target(current, choices, on_ac, delta):
    """Para onde o scroll leva. Ja pula o indisponivel.

    Anda sobre a lista de perfis permitidos agora, e por isso nunca
    devolve um degrau que a escrita recusaria: na bateria, subir a partir
    do Economico vai direto ao Equilibrado, e subir de novo nao faz nada.
    Ver spec secao 7.2.
    """
    if not delta:
        return current
    return model.neighbour(current, choices, on_ac, +1 if delta > 0 else -1)


def tooltip_text(state, sample, maximum=False):
    """Perfil, rotacao das duas ventoinhas e temperatura."""
    perfil = (
        model.MAXIMUM_LABEL
        if maximum
        else model.LABELS.get(state.profile, state.profile) or "perfil desconhecido"
    )
    partes = [f"Nexus Sense — {perfil}"]
    if sample.fans is not None:
        partes.append(f"{sample.fans[0]} / {sample.fans[1]} rpm")
    if sample.cpu_temp is not None:
        partes.append(f"{sample.cpu_temp:.0f} °C")
    return "\n".join(partes)


def icon_level(profile, choices):
    """Quanto encher o N do ANV15-52, de 1 a 4.

    Este firmware anuncia quatro perfis. Cada degrau tem uma variante do
    ícone e o último deixa o N completamente preenchido.
    """
    escada = [p for p in model.PROFILES if p in set(choices)]
    if profile not in escada or len(escada) < 2:
        return None
    posicao = escada.index(profile)
    return 1 + round(posicao * 3 / (len(escada) - 1))


def icon_name(profile, choices=(), dark_panel=True, maximum=False):
    """O icone muda conforme o nivel, e a polaridade conforme o tema.

    Duas polaridades porque `currentColor` nao resolve aqui: ele so e
    repintado por temas que processam o SVG, e um arquivo no hicolor
    resolvido pelo host da bandeja fica preto -- some no painel escuro.
    Medido na maquina. Ver spec secao 7.2 e packaging/icons/README.md.

    O sufixo nomeia a cor do desenho, nao a do painel: `-claro` e o
    glifo claro, que e o que serve num painel escuro.
    """
    nivel = icon_level(profile, choices)
    if maximum:
        base = f"{PROFILE_ICON_BASE}-max"
    else:
        base = ICON_BASE if nivel is None else f"{PROFILE_ICON_BASE}-nivel{nivel}"
    return f"{base}-claro" if dark_panel else f"{base}-escuro"


class StatusNotifierItem(QObject):
    """O item em si. Traduz chamada do host em sinal do Qt."""

    activated = Signal()
    secondary = Signal()
    context_menu = Signal(int, int)
    scrolled = Signal(int, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.icon = ICON_BASE
        self.tooltip = "Nexus Sense"
        self._export = None
        self.menu_factory = None

    # -------------------------------------------------- o que o host chama

    def Activate(self, x, y):
        self.activated.emit()

    def SecondaryActivate(self, x, y):
        self.secondary.emit()

    def ContextMenu(self, x, y):
        self.context_menu.emit(x, y)

    def Scroll(self, delta, orientation):
        self.scrolled.emit(delta, orientation)

    # ------------------------------------------------ o que o app escreve

    def set_icon(self, nome):
        if nome != self.icon:
            self.icon = nome
            if self._export is not None:
                self._export.NewIcon()

    def set_tooltip(self, texto):
        if texto != self.tooltip:
            self.tooltip = texto
            if self._export is not None:
                self._export.NewTitle()


def register(item):
    """Publica SNI e DBusMenu; sem transporte compatível, usa o fallback."""
    try:
        from .dbus_export import publish
    except ImportError:
        return False
    return publish(item, f"{SERVICE_PREFIX}-{os.getpid()}-1")
