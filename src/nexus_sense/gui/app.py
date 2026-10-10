"""Executavel da interface: nexus-sense."""

import argparse
import sys

from PySide6.QtWidgets import QApplication

from .. import __version__
from ..device import Controls
from ..sysfs import Sysfs
from ..tray import build_tray
from .single import SingleInstance, bus_available, claim, raise_existing
from .style import apply_to
from .window import Window


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="nexus-sense",
        description="Controle e monitoramento para laptops Acer Nitro e Predator.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--root", default="/", help="raiz alternativa do sysfs")
    parser.add_argument(
        "--tray-only", action="store_true", help="começa só na bandeja, sem abrir a janela"
    )
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    app = QApplication([])
    app.setApplicationName("Nexus Sense")
    app.setDesktopFileName("nexus-sense")

    # A pele segue o tema de quem esta usando, decidida pela luminancia da
    # paleta e nao pelo nome do tema. Ver gui/style.py.
    apply_to(app)

    sysfs = Sysfs(args.root)
    controls = Controls(sysfs)
    janela = Window(sysfs, controls)
    janela.refresh()

    # Uma instancia so. Sem isto, reabrir o app deixa dois icones na
    # bandeja -- o nome do servico do SNI leva o PID -- e o antigo pode
    # sobreviver ao processo que o criou, virando icone morto.
    #
    # Sem barramento de sessao nao ha nome a disputar nem outra instancia a
    # quem pedir a janela: a recusa do registro nao quer dizer "ja ha uma".
    dono = SingleInstance(lambda: _abre(janela))
    if bus_available() and not claim(dono):
        raise_existing()
        print("já havia uma instância: pedi para ela aparecer")
        return 0

    controlador, modo = build_tray(sysfs, controls)
    # Com flush: sob a unit a saida e um socket, o Python a guarda em bloco,
    # e a linha so sairia no encerramento -- que e por SIGTERM, e a perde.
    # O journal passou um boot inteiro sem ela.
    print(f"bandeja: {modo}", flush=True)

    if controlador is None:
        janela.show()
    else:
        # Com bandeja, fechar a janela nao encerra o app: o icone continua.
        app.setQuitOnLastWindowClosed(False)
        controlador.open_requested.connect(lambda: _abre(janela))
        controlador.quit_requested.connect(app.quit)
        controlador.item.context_menu.connect(
            lambda x, y: _menu(controlador, janela, app, x, y)
        )
        _connect_state(controlador, janela)
        controlador.start()
        controlador.item.menu_factory = lambda: _build_menu(controlador, janela, app)
        if not args.tray_only:
            janela.show()

    return app.exec()


def _connect_state(controlador, janela):
    # refresh não emite changed: permite os dois sentidos sem recursão.
    #
    # Só com a janela à vista. Sob --tray-only ela nunca aparece, e a
    # passada de 5 s da bandeja estava mandando repintar widgets que
    # ninguém vê -- ao preço de um read_state inteiro, cinco chamadas
    # WMI, a cada vez. Não se perde atualização: todo caminho que torna
    # a janela visível chama refresh antes (main e _abre).
    controlador.state_refreshed.connect(
        lambda: janela.refresh(update_session=False) if janela.isVisible() else None
    )
    # Sem notificar de volta: o `changed` ja fez a janela se reler, pelo
    # caminho direto. O eco pela bandeja era um segundo read_state por
    # clique -- 27 ms, medido, com cinco chamadas WMI dentro.
    for _, _, pagina in janela.pages:
        pagina.changed.connect(lambda: controlador.refresh(notify=False))


def _abre(janela):
    janela.refresh(update_session=False)
    janela.show()
    janela.raise_()
    janela.activateWindow()


def _build_menu(controlador, janela, app):
    from ..tray.menu import build_menu

    controlador.refresh()

    acoes = {
        "set_profile": controlador.apply_profile,
        "maximum": controlador.apply_maximum,
        "fan_auto": lambda: controlador.apply_fan_speed(0, 0),
        "fan_max": lambda: controlador.apply_fan_speed(100, 100),
        "open": lambda: _abre(janela),
        "quit": app.quit,
    }
    return build_menu(
        controlador.state, acoes, maximum_active=controlador.maximum_active
    )


def _menu(controlador, janela, app, x, y):
    from PySide6.QtCore import QPoint

    # O menu fica preso na janela de proposito: sem dono, o coletor do
    # Python pode leva-lo durante o exec(), que roda um laco de eventos
    # proprio. O anterior e descartado a cada abertura.
    anterior = getattr(janela, "_menu_bandeja", None)
    if anterior is not None:
        anterior.deleteLater()
    menu = _build_menu(controlador, janela, app)
    janela._menu_bandeja = menu
    menu.exec(QPoint(x, y))


if __name__ == "__main__":
    # Sem isto, `python3 -m nexus_sense.gui.app` importa o modulo e sai 0
    # sem abrir nada. O executavel instalado nao passa por aqui -- ele
    # chama main() direto pelo entry point -- e por isso o defeito so
    # aparece rodando como modulo.
    sys.exit(main())
