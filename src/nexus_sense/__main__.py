"""Executavel do agente: nexus-sense-agent."""

import argparse
import logging
import signal
import threading

from . import __version__
from .agent import DEFAULT_INTERVAL, Agent
from .config import default_path
from .sysfs import Sysfs


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="nexus-sense-agent",
        description="Gerencia perfis de energia e o modo de desempenho máximo.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--root", default="/", help="raiz alternativa do sysfs")
    parser.add_argument("--config", default=None, help="caminho do config.toml")
    parser.add_argument(
        "--interval", type=float, default=DEFAULT_INTERVAL, help="segundos entre leituras"
    )
    parser.add_argument("--once", action="store_true", help="uma passada e sai")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )

    sysfs = Sysfs(args.root)
    agente = Agent(sysfs, args.config or default_path(), interval=args.interval)

    if args.once:
        if not sysfs.module_loaded():
            logging.error("o módulo do driver não está carregado; nada a fazer")
            return 1
        agente.tick()
        return 0

    # Sem o modulo o laco entra assim mesmo, e espera. Sair com erro aqui
    # nao encerrava nada: a unit tem Restart=always e reabria o agente a
    # cada 3 s, indefinidamente -- o limite de 5 partidas em 10 s nunca e
    # atingido nesse ritmo. Quem avisa da ausencia e o proprio tick.

    parar = threading.Event()
    for sinal in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sinal, lambda *_: parar.set())
    agente.run(parar)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
