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
    if not sysfs.module_loaded():
        logging.error("o módulo do driver não está carregado; nada a fazer")
        return 1

    agente = Agent(sysfs, args.config or default_path(), interval=args.interval)

    if args.once:
        agente.tick()
        return 0

    parar = threading.Event()
    for sinal in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sinal, lambda *_: parar.set())
    agente.run(parar)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
