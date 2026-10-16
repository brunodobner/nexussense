"""O agente e a suspensao -- docs/plano-curva.md, secao 11.

Medido no E-C5, em 2026-10-16: ao acordar de uma suspensao (S3) o systemd
contou o tempo dormindo como tempo sem aviso, e o WatchdogSec matou o agente
-- a cada suspensao, um agente sadio morto. Na mesma volta o firmware largou
o manual da ventoinha e trocou o perfil termico para balanced, com o driver
ainda dizendo o manual.

Este modulo cuida do primeiro e avisa do segundo. Segura um bloqueio de
atraso do logind (systemd-inhibit --mode=delay) e espera o PrepareForSleep
(busctl wait). Antes de dormir alarga o watchdog e so entao solta o
bloqueio: o logind espera por ele. Ao acordar devolve o watchdog ao valor da
unit, avisa que esta vivo, e chama quem reaplica o que o firmware desfez.

Sem dependencia nova: as duas ferramentas vem com o systemd, e e o mesmo
caminho que outros programas da sessao usam (systemd-inhibit --list).
"""

import json
import logging
import subprocess
import threading

LOG = logging.getLogger("nexus_sense.sono")

LOGIND = (
    "org.freedesktop.login1",
    "/org/freedesktop/login1",
    "org.freedesktop.login1.Manager",
    "PrepareForSleep",
)

# Enquanto a maquina dorme o watchdog fica neste valor, maior que qualquer
# suspensao. Ao acordar volta ao da unit.
DORMINDO_USEC = 30 * 24 * 3600 * 1_000_000

# Se o busctl cair, espera isto antes de tentar de novo.
RECOMECO = 5.0


def comando_espera():
    # --limit-messages alto: um processo so para todos os sinais, sem a
    # janela entre um "wait" e o seguinte em que um sinal se perderia. Sem
    # --timeout: o wait espera para sempre (medido, 45 s sem sinal), e o
    # "--timeout=infinity" o busctl 262 recusa.
    #
    # stdbuf -oL: escrevendo para um pipe, o busctl guarda a saida num buffer
    # e so a entrega ao sair -- e com --limit-messages alto ele nao sai. No
    # E-C5 de 2026-10-16 o aviso de dormir ficou preso la, o bloqueio nunca
    # saiu ("Delay lock is active ... but inhibitor timeout is reached") e o
    # watchdog matou o agente ao acordar. Medido logo depois, com os mesmos
    # sinais da bateria: sem stdbuf, nenhuma linha em 100 s; com ele, cada
    # uma na hora.
    return [
        "stdbuf", "-oL", "busctl", "--system", "--json=short", "wait",
        "--limit-messages=1000000", *LOGIND,
    ]


def comando_bloqueio():
    return [
        "systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Nexus Sense",
        "--why=Alarga o watchdog do agente antes de dormir", "sleep", "infinity",
    ]


def le_sinal(linha):
    """True: vai dormir. False: acordou. None: outra coisa.

    O busctl escreve cada sinal numa linha: {"type":"b","data":[true]}.
    """
    try:
        dado = json.loads(linha)["data"]
    except (ValueError, KeyError, TypeError):
        return None
    if isinstance(dado, list) and len(dado) == 1 and isinstance(dado[0], bool):
        return dado[0]
    return None


class Sono:
    """O fio que vigia a suspensao. `ao_dormir` e `ao_acordar` sao chamados
    deste fio: devem ser curtos, e quem precisa agir de verdade espera a
    proxima passada do agente."""

    def __init__(self, notifica, watchdog_usec, ao_dormir, ao_acordar,
                 executa=subprocess.Popen, espera=None, log=None):
        self._notifica = notifica
        self._watchdog_usec = watchdog_usec
        self._ao_dormir = ao_dormir
        self._ao_acordar = ao_acordar
        self._executa = executa
        self._parar = threading.Event()
        self._espera = espera or self._parar.wait
        self._log = log or LOG
        self._bloqueio = None
        self._processo = None
        self._fio = None

    def inicia(self):
        self._fio = threading.Thread(target=self._laco, name="nexus-sense-sono", daemon=True)
        self._fio.start()

    def para(self):
        self._parar.set()
        self._solta()
        processo, self._processo = self._processo, None
        if processo is not None and processo.poll() is None:
            processo.terminate()
        if self._fio is not None:
            self._fio.join(timeout=2)

    def _bloqueia(self):
        if self._bloqueio is None and not self._parar.is_set():
            try:
                self._bloqueio = self._executa(
                    comando_bloqueio(), stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            except OSError as erro:
                self._log.warning("sono: não foi possível segurar o bloqueio do logind: %s", erro)

    def _solta(self):
        bloqueio, self._bloqueio = self._bloqueio, None
        if bloqueio is not None and bloqueio.poll() is None:
            bloqueio.terminate()
            try:
                bloqueio.wait(timeout=2)
            except subprocess.TimeoutExpired:
                bloqueio.kill()

    def _laco(self):
        avisado = False
        while not self._parar.is_set():
            self._bloqueia()
            try:
                self._processo = self._executa(
                    comando_espera(), stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                )
            except OSError as erro:
                if not avisado:
                    self._log.warning("sono: não foi possível esperar a suspensão: %s", erro)
                avisado = True
                self._espera(RECOMECO)
                continue
            for linha in self._processo.stdout:
                sinal = le_sinal(linha)
                if sinal is True:
                    # Primeiro o watchdog, depois o bloqueio: o logind so
                    # suspende quando o bloqueio sai.
                    self._notifica(f"WATCHDOG_USEC={DORMINDO_USEC}")
                    self._ao_dormir()
                    self._solta()
                    self._log.info("sono: a máquina vai dormir; watchdog alargado")
                elif sinal is False:
                    self._notifica(f"WATCHDOG_USEC={self._watchdog_usec}")
                    self._notifica("WATCHDOG=1")
                    self._bloqueia()
                    self._ao_acordar()
                    self._log.info("sono: a máquina acordou; watchdog de volta")
            if self._parar.is_set():
                break
            # O busctl saiu sozinho -- o barramento caiu, ou ele morreu.
            if not avisado:
                self._log.warning("sono: o busctl que esperava a suspensão saiu; tentando de novo")
            avisado = True
            self._espera(RECOMECO)
