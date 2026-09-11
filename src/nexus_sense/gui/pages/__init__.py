"""As paginas da janela.

Cada pagina cumpre o mesmo protocolo, e a janela nao sabe nada alem
dele:

    apply_state(state)   recebe o DeviceState e se repinta
    has_content(state)   False faz a secao sumir da barra lateral
    changed              sinal; a janela rele o estado quando ele vem

Uma pagina nova entra registrando-se em build_pages, e so.
"""

from .battery import BatteryPage
from .dashboard import DashboardPage
from .diagnostics import DiagnosticsPage
from .keyboard import KeyboardPage
from .performance import PerformancePage


def build_pages(controls):
    """As secoes, na ordem em que aparecem na barra lateral."""
    return (
        ("painel", "Painel", DashboardPage(controls)),
        ("desempenho", "Desempenho", PerformancePage(controls)),
        ("bateria", "Bateria", BatteryPage(controls)),
        ("teclado", "Teclado", KeyboardPage(controls)),
        ("diagnostico", "Diagnóstico", DiagnosticsPage(controls)),
    )
