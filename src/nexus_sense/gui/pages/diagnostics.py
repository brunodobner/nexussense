"""Diagnostico: por que aquele botao esta cinza.

Substitui o "System Settings" da GUI antiga. Saem os botoes "Check for
Updates" e "Issue/Feedback": apontam para as releases e o GitHub do
PXDiv, que nao sao mais a base deste fork. Ver spec secao 6.5.
"""

from typing import NamedTuple

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QFrame,
    QGridLayout,
    QGroupBox,
    QLabel,
    QVBoxLayout,
    QWidget,
)

from ... import session
from ...device import read_system
from ...session import AGENT_UNIT, GROUP

VAZIO = "—"


class Check(NamedTuple):
    label: str
    ok: bool
    detail: str


def run_checks(state, *, agent, ppd, in_group):
    """As quatro verificacoes, sempre as quatro e sempre nesta ordem.

    Funcao pura: recebe o estado e os fatos da sessao, devolve o que
    mostrar. Quem chama subprocess e a pagina.
    """
    checagens = [
        Check(
            "Módulo carregado",
            state.module_loaded,
            "" if state.module_loaded else "carregue com: sudo modprobe nexus_sense",
        )
    ]

    graveis = state.profile_writable and bool(state.writable)
    if graveis:
        detalhe = ""
    elif not in_group:
        detalhe = (
            f"você não está no grupo {GROUP}. Para entrar: "
            f"sudo usermod -aG {GROUP} $USER — e relogue em seguida"
        )
    else:
        detalhe = (
            f"você está no grupo {GROUP}, mas esta sessão ainda não o carrega: "
            "é preciso relogar. Se já relogou, a regra udev não foi aplicada — "
            "confira /etc/udev/rules.d/60-nexus-sense.rules"
        )
    checagens.append(Check(f"Permissão de grupo ({GROUP})", graveis, detalhe))

    checagens.append(
        Check(
            "Agente ativo",
            agent,
            ""
            if agent
            else f"ligue com: systemctl --user enable --now {AGENT_UNIT}",
        )
    )

    if not ppd.present:
        linha = Check("power-profiles-daemon", True, "não instalado, ou fora do ar")
    elif ppd.drives_platform:
        linha = Check(
            "power-profiles-daemon",
            False,
            "ele se ligou ao platform_profile e está disputando o perfil com o "
            "Nexus Sense. Escolha um dos dois: desligue o ppd, ou desligue a "
            "troca automática do agente.",
        )
    else:
        linha = Check(
            "power-profiles-daemon",
            True,
            f"presente (perfil {ppd.profile or VAZIO}), mas não disputa o perfil "
            "térmico: dirige apenas o driver da CPU",
        )
    checagens.append(linha)

    return tuple(checagens)


class DiagnosticsPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls

        self.system_card = QGroupBox("Sistema")
        self._sistema = QGridLayout(self.system_card)
        self._sistema.setColumnStretch(1, 1)
        self._sistema.setVerticalSpacing(4)
        self._campos = {}
        self._rotulos = {}
        campos = (
            ("product", "Modelo"),
            ("family", "Família"),
            ("driver_version", "Versão do driver"),
            ("module_params", "Parâmetros do módulo"),
            ("choices", "Perfis que o firmware anuncia"),
            ("features", "Recursos disponíveis"),
        )
        linha = 0
        for chave, rotulo in campos:
            nome = QLabel(f"{rotulo}:")
            nome.setObjectName("diagnostico_rotulo")
            valor = QLabel(VAZIO)
            valor.setWordWrap(True)
            valor.setObjectName("diagnostico_valor")
            valor.setTextInteractionFlags(Qt.TextSelectableByMouse)
            self._sistema.addWidget(nome, linha, 0, 1, 2)
            linha += 1
            self._sistema.addWidget(valor, linha, 0, 1, 2)
            linha += 1
            self._rotulos[chave] = nome
            self._campos[chave] = valor

        self.checks_box = QGroupBox("Verificações")
        QVBoxLayout(self.checks_box)

        raiz = QVBoxLayout(self)
        raiz.addWidget(self.system_card)
        raiz.addWidget(self.checks_box)
        raiz.addStretch(1)

    def has_content(self, state):
        # Justamente quando nada funciona e que esta tela precisa aparecer.
        return True

    def apply_state(self, state):
        sistema = read_system(self.controls.sysfs)
        self._campos["product"].setText(sistema.product or VAZIO)
        self._campos["family"].setText(sistema.family or VAZIO)
        self._campos["driver_version"].setText(sistema.driver_version or VAZIO)
        self._campos["module_params"].setText(
            ", ".join(f"{k}={v}" for k, v in sorted(sistema.module_params.items()))
            or VAZIO
        )
        self._campos["choices"].setText(" · ".join(state.choices) or VAZIO)
        self._campos["features"].setText(" · ".join(sorted(state.features)) or VAZIO)

        # Consultas de sessão são lentas. Só rode quando esta página está
        # visível; cliques nas outras páginas devem repintar imediatamente.
        if self.isVisible() or self.parent() is None:
            self.refresh_checks(state)

    def refresh_checks(self, state):
        self._desenha_checagens(
            run_checks(
                state,
                agent=session.agent_active(),
                ppd=session.ppd_state(),
                in_group=session.in_group(GROUP),
            )
        )

    def showEvent(self, event):
        super().showEvent(event)
        from ...device import read_state

        self.refresh_checks(read_state(self.controls.sysfs))

    def _desenha_checagens(self, checagens):
        leiaute = self.checks_box.layout()
        while leiaute.count():
            item = leiaute.takeAt(0)
            if item.widget() is not None:
                item.widget().deleteLater()

        for checagem in checagens:
            linha = QFrame()
            interno = QVBoxLayout(linha)
            titulo = QLabel(f"{'✓' if checagem.ok else '✗'}  {checagem.label}")
            titulo.setObjectName("check_ok" if checagem.ok else "check_falhou")
            interno.addWidget(titulo)
            if checagem.detail:
                detalhe = QLabel(checagem.detail)
                detalhe.setWordWrap(True)
                detalhe.setObjectName("check_detalhe")
                interno.addWidget(detalhe)
            leiaute.addWidget(linha)
