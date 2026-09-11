"""O menu do clique direito.

So os perfis disponiveis entram: um menu nao tem como hachurar, e um
item que falharia ao ser clicado e pior do que um item ausente. A tela
de Desempenho e que mostra o indisponivel com o motivo.
"""

from PySide6.QtGui import QAction
from PySide6.QtWidgets import QMenu

from .. import model


def build_menu(state, actions, maximum_active=False):
    """Monta o menu. `actions` pode vir vazio -- util em teste."""
    menu = QMenu()

    for perfil in state.available:
        acao = QAction(model.LABELS.get(perfil, perfil), menu)
        acao.setObjectName(f"profile-{perfil}")
        acao.setEnabled(state.profile_writable)
        acao.setCheckable(True)
        acao.setChecked(not maximum_active and perfil == state.profile)
        if "set_profile" in actions:
            acao.triggered.connect(lambda _=False, p=perfil: actions["set_profile"](p))
        menu.addAction(acao)

    acao = QAction(model.MAXIMUM_LABEL, menu)
    acao.setObjectName("maximum")
    acao.setEnabled(
        state.on_ac is True
        and state.profile_writable
        and "fan_speed" in state.writable
        and "balanced-performance" in state.available
    )
    acao.setCheckable(True)
    acao.setChecked(maximum_active)
    if "maximum" in actions:
        acao.triggered.connect(lambda _=False: actions["maximum"]())
    menu.addAction(acao)

    menu.addSeparator()

    for chave, rotulo in (("fan_auto", "Ventoinha automática"), ("fan_max", "Ventoinha no máximo")):
        acao = QAction(rotulo, menu)
        acao.setObjectName(chave)
        acao.setEnabled("fan_speed" in state.writable)
        if chave in actions:
            acao.triggered.connect(lambda _=False, c=chave: actions[c]())
        menu.addAction(acao)

    menu.addSeparator()

    for chave, rotulo in (("open", "Abrir"), ("quit", "Sair")):
        acao = QAction(rotulo, menu)
        acao.setObjectName(chave)
        if chave in actions:
            acao.triggered.connect(lambda _=False, c=chave: actions[c]())
        menu.addAction(acao)

    return menu
