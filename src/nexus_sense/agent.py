"""Correcao do perfil termico na troca de fonte de energia.

Por que isto existe: o driver recusa quiet, balanced-performance e
performance na bateria, mas NAO derruba um perfil ja ativo -- ele nao
tem notificador de fonte de energia nenhum. Sem alguem corrigindo, a
maquina fica em balanced-performance na bateria por tempo indefinido,
num estado que ela recusaria assumir se pedido. Ver spec secao 2.9.

`decide` e pura de proposito: recebe o estado, devolve o que escrever.
Todo o comportamento do agente e testavel sem hardware e sem relogio.
"""

import dataclasses
import logging
import threading
from typing import NamedTuple

from .config import Config, load, save
from .device import Controls, WriteError
from .maximum import MaximumMode, THERMAL_PROFILE
from .model import available, nearest
from .powermizer import PowerMizer, PowerMizerError


class Decision(NamedTuple):
    profile: str | None  # None significa "nao escreva nada"
    config: Config  # possivelmente atualizado em relacao ao recebido
    reason: str


def decide(current_profile, was_on_ac, now_on_ac, config, choices):
    """O que fazer quando a fonte de energia acabou de ser lida.

    `was_on_ac` e None na primeira leitura: nao houve troca ainda, entao
    nada dispara.
    """
    # O modo máximo sempre acompanha a tomada, mesmo que a troca
    # automática comum esteja desligada. Também corrige a primeira
    # leitura após o agente iniciar já na bateria.
    if config.maximum_mode and was_on_ac != now_on_ac:
        if not now_on_ac:
            return _on_unplug(current_profile, config, choices)
        if was_on_ac is not None:
            return _on_plug(config, choices)

    if was_on_ac is None or was_on_ac == now_on_ac:
        return Decision(None, config, "sem troca de fonte")

    if not config.auto_switch:
        return Decision(None, config, "troca automatica desligada")

    if not now_on_ac:
        return _on_unplug(current_profile, config, choices)
    return _on_plug(config, choices)


def _on_unplug(current_profile, config, choices):
    permitidos = available(choices, on_ac=False)
    if not permitidos:
        return Decision(None, config, "nenhum perfil permitido na bateria")

    if current_profile in permitidos:
        return Decision(None, config, "o perfil corrente ja e permitido na bateria")

    desejado = config.battery_profile
    if desejado in permitidos:
        alvo = desejado
        razao = f"na bateria: {current_profile} nao e permitido, indo para {alvo}"
    else:
        # Recua para o padrao, nao para o vizinho mais proximo. Se o
        # usuario pediu 'quiet' -- que o driver recusa na bateria --, o
        # vizinho mais proximo seria 'low-power', bem mais agressivo na
        # economia do que ele pediu. O padrao e a escolha menos
        # surpreendente. Ver spec secao 8.
        padrao = Config().battery_profile
        alvo = padrao if padrao in permitidos else nearest(desejado, permitidos)
        razao = (
            f"o perfil de bateria escolhido ({desejado}) e recusado pelo driver; "
            f"usando {alvo}"
        )

    novo = dataclasses.replace(config, saved_ac_profile=current_profile)
    return Decision(alvo, novo, razao)


def _on_plug(config, choices):
    guardado = config.saved_ac_profile
    limpo = dataclasses.replace(config, saved_ac_profile=None)

    if guardado is None:
        return Decision(None, config, "nada guardado para devolver")

    if guardado not in available(choices, on_ac=True):
        return Decision(
            None, limpo, f"o perfil guardado ({guardado}) nao esta mais disponivel"
        )

    return Decision(guardado, limpo, f"de volta na tomada: devolvendo {guardado}")


LOG = logging.getLogger("nexus-sense-agent")

# Sondagem simples: um arquivo de 4 bytes, modo 444. As alternativas --
# netlink do udev, UPower via DBus -- sao mais elegantes e mais frageis,
# e trariam dependencia. Ver spec secao 4.2.
DEFAULT_INTERVAL = 2.0


class Agent:
    """Vigia a fonte de energia e corrige o perfil termico."""

    def __init__(self, sysfs, config_path, interval=DEFAULT_INTERVAL, logger=None):
        self.sysfs = sysfs
        self.config_path = config_path
        self.interval = interval
        self.log = logger or LOG
        self._was_on_ac = None
        # None ate a primeira passada; depois, se o driver estava la.
        self._driver_presente = None
        # Ultimo perfil de tomada conhecido. Espelha o arquivo quando ele
        # e gravavel, e o substitui quando nao e.
        self._saved_memoria = None
        self._maximum = MaximumMode(Controls(sysfs), config_path, gpu=PowerMizer())
        self._gpu_confirmed = False
        # Devolucao que o firmware recusou: (perfil a devolver, perfil que
        # estava em vigor na recusa). Ver _retoma_pendente.
        self._pendente = None
        # As falhas do modo maximo ja avisadas. Repetir a mesma linha a
        # cada passada enterra no journal o momento em que ela comecou.
        self._falhas_maximo = ()

    def _read_choices(self):
        caminho = self.sysfs.choices_path()
        if caminho is None:
            return []
        try:
            return self.sysfs.read(caminho).split()
        except OSError:
            return []

    def _read_profile(self):
        caminho = self.sysfs.profile_path()
        if caminho is None:
            return None
        try:
            return self.sysfs.read(caminho)
        except OSError:
            return None

    def tick(self):
        """Uma passada: le a fonte, decide, escreve se preciso."""
        now_on_ac = self.sysfs.on_ac()
        perfil = self._read_profile()

        if now_on_ac is None or perfil is None:
            # Esperar, e nao sair: quem sai e reaberto pela unit a cada
            # 3 s, para sempre. Uma linha na ida e outra na volta.
            if self._driver_presente is not False:
                self.log.warning("driver ou fonte de energia ausente; aguardando")
            self._driver_presente = False
            self._release_gpu()
            return Decision(None, load(self.config_path), "driver ou fonte ausente")

        if self._driver_presente is False:
            self.log.info("driver de volta; retomando")
        self._driver_presente = True

        # Recarregado a cada passada de proposito: a GUI escreve neste
        # arquivo, e o agente nao tem outro jeito de saber.
        config = load(self.config_path)

        # Se a gravacao anterior falhou, o disco nao sabe qual era o
        # perfil da tomada -- mas nos sabemos. Sem isto, um $HOME
        # somente-leitura desliga a restauracao inteira deixando so um
        # aviso, que foi exatamente o que aconteceu na virada.
        # Persistir e bom; restaurar dentro da sessao nao pode depender
        # disso.
        if config.saved_ac_profile is None and self._saved_memoria is not None:
            config = dataclasses.replace(
                config, saved_ac_profile=self._saved_memoria
            )

        decisao = decide(
            perfil,
            was_on_ac=self._was_on_ac,
            now_on_ac=now_on_ac,
            config=config,
            choices=self._read_choices(),
        )
        self._was_on_ac = now_on_ac

        ja_avisada = self._pendente is not None
        if decisao.profile is None:
            decisao = self._retoma_pendente(decisao, config, perfil, now_on_ac)

        # Devolver e consumir o guardado. So vale se a escrita passar.
        devolvendo = (
            decisao.profile is not None
            and config.saved_ac_profile is not None
            and decisao.config.saved_ac_profile is None
        )

        # A escrita vem ANTES da gravacao, e a ordem importa: antes era o
        # contrario, e uma devolucao recusada ja tinha apagado do disco o
        # perfil que deveria voltar.
        if decisao.profile is not None:
            try:
                self.sysfs.write(self.sysfs.profile_path(), decisao.profile)
            except OSError as erro:
                if devolvendo:
                    # O caso real: cabo ligado e bateria abaixo de 40%.
                    # O firmware ainda se diz fora da tomada e recusa. O
                    # guardado fica, e a devolucao e tentada de novo.
                    if not ja_avisada:
                        self.log.warning(
                            "o firmware recusou devolver %s (%s); acontece com a "
                            "bateria abaixo de uns 40%%. Fica pendente",
                            decisao.profile,
                            erro,
                        )
                    self._pendente = (decisao.profile, perfil)
                    decisao = decisao._replace(config=config)
                else:
                    # Acontece de verdade: sem a regra udev aplicada, ou
                    # numa corrida em que o cabo volta entre a decisao e
                    # a escrita.
                    self.log.warning(
                        "não foi possível escrever o perfil %s: %s",
                        decisao.profile,
                        erro,
                    )
            else:
                # O que acabou de ser escrito e o perfil em vigor: quem
                # vem depois nao precisa perguntar de novo ao firmware.
                perfil = decisao.profile
                self._pendente = None
                self.log.info("perfil -> %s (%s)", decisao.profile, decisao.reason)

        # A memoria acompanha a decisao, tenha a gravacao dado certo ou nao.
        self._saved_memoria = decisao.config.saved_ac_profile

        if decisao.config != config:
            try:
                save(decisao.config, self.config_path)
            except OSError as erro:
                self.log.warning("não foi possível gravar a configuração: %s", erro)

        self._reconcile_maximum(decisao.config, now_on_ac, perfil)

        return decisao

    def _retoma_pendente(self, decisao, config, perfil, on_ac):
        """Tenta de novo a devolucao que o firmware recusou.

        Tres saidas. Na bateria a pendencia some da memoria, mas o
        guardado fica no arquivo para a proxima vez que o cabo entrar.
        Se o perfil mudou desde a recusa, alguem escolheu a mao -- e
        carregar de 26% a 40% leva minutos, tempo de sobra para isso --
        entao a escolha vence e a devolucao e cancelada. Senao, tenta.
        """
        if self._pendente is None:
            return decisao
        if not on_ac:
            self._pendente = None
            return decisao

        guardado, visto = self._pendente
        limpo = dataclasses.replace(config, saved_ac_profile=None)
        if perfil != visto:
            self._pendente = None
            return Decision(
                None, limpo, "devolução cancelada: o perfil foi escolhido à mão"
            )
        return Decision(guardado, limpo, f"carga suficiente: devolvendo {guardado}")

    def _reconcile_maximum(self, config, on_ac, perfil_atual):
        """Mantém o modo após login, suspensão e alterações externas.

        `perfil_atual` vem da passada: o que ela leu, ou o que ela mesma
        escreveu. Reler aqui custava uma segunda chamada WMI -- 4,7 ms de
        CPU, medido -- para ouvir uma resposta que o `tick` ja tinha.
        """
        if not config.maximum_mode:
            self._release_gpu()
            self._falhas_maximo = ()
            return
        active = on_ac is True
        falhas = []
        if active:
            try:
                if perfil_atual != THERMAL_PROFILE:
                    self._maximum.controls.set_profile(THERMAL_PROFILE)
            except WriteError as error:
                falhas.append(str(error))
        errors = self._maximum.enforce_runtime(config, active=active)
        falhas.extend(errors)
        self._avisa_falhas(falhas)
        confirmed = active and not errors
        if confirmed and not self._gpu_confirmed:
            self.log.info("GPUPowerMizerMode=1 confirmado no cliente NVML persistente")
        if not active and self._gpu_confirmed:
            self.log.info("pedido PowerMizer liberado na bateria")
        self._gpu_confirmed = confirmed

    def _avisa_falhas(self, falhas):
        """Uma linha quando a falha aparece, outra quando todas somem."""
        for falha in falhas:
            if falha not in self._falhas_maximo:
                self.log.warning("não foi possível manter desempenho máximo: %s", falha)
        if self._falhas_maximo and not falhas:
            self.log.info("desempenho máximo: as falhas anteriores cessaram")
        self._falhas_maximo = tuple(falhas)

    def _release_gpu(self):
        try:
            if self._maximum.gpu is not None:
                self._maximum.gpu.close()
            if self._gpu_confirmed:
                self.log.info("pedido PowerMizer liberado")
        except PowerMizerError as error:
            self.log.warning("falha ao liberar PowerMizer: %s", error)
        self._gpu_confirmed = False

    def run(self, stop_event=None):
        """O laco. Para quando `stop_event` for sinalizado."""
        parar = stop_event or threading.Event()
        self.log.info("agente no ar, sondando a cada %.1f s", self.interval)
        try:
            while not parar.is_set():
                try:
                    self.tick()
                except Exception:  # nunca deixar o laco morrer por um tick ruim
                    self.log.exception("falha inesperada numa passada")
                parar.wait(self.interval)
        finally:
            self._release_gpu()
        self.log.info("agente encerrado")
