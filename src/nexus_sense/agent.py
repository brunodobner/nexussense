"""Correcao do perfil termico na troca de fonte de energia.

Por que isto existe: o driver recusa quiet, balanced-performance e
performance na bateria, mas NAO derruba um perfil ja ativo -- ele nao
tem notificador de fonte de energia nenhum. Sem alguem corrigindo, a
maquina fica em balanced-performance na bateria por tempo indefinido,
num estado que ela recusaria assumir se pedido. Ver spec secao 2.9.

`decide` e pura de proposito: recebe o estado, devolve o que escrever.
Todo o comportamento do agente e testavel sem hardware e sem relogio.

A mesma passada carrega a rede da ventoinha manual, que tem a funcao pura
dela em fan_guard.py: o agente le, ela decide, o agente escreve.
"""

import dataclasses
import logging
import os
import threading
from collections import deque
from typing import NamedTuple

from . import curva, fan_guard, guarda, telemetry
from .config import Config, load, save
from .device import Controls, WriteError
from .maximum import MaximumMode, THERMAL_PROFILE
from .model import available, fan_speed_value, nearest, parse_fan_speed
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

# O fan_speed que a curva leu na passada, para a rede nao ler de novo.
_NAO_LIDO = object()


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
        self._controls = Controls(sysfs)
        self._maximum = MaximumMode(self._controls, config_path, gpu=PowerMizer())
        self._gpu_confirmed = False
        # Devolucao que o firmware recusou: (perfil a devolver, perfil que
        # estava em vigor na recusa). Ver _retoma_pendente.
        self._pendente = None
        # True depois que a suspensao do modo maximo na bateria foi
        # aplicada com sucesso. Ver _reconcile_maximum.
        self._suspensao_feita = False
        # As falhas do modo maximo ja avisadas. Repetir a mesma linha a
        # cada passada enterra no journal o momento em que ela comecou.
        self._falhas_maximo = ()
        # A rede da ventoinha: quantas passadas seguidas ela viu o manual
        # baixo, a GPU quente e a rotacao lenta. Ver _guarda_ventoinha.
        self._rede_seguidas = 0
        self._rede_recusa_avisada = False
        # A curva propria. `_curva_escrito` e o par que ela escreveu por
        # ultimo, e None quando a ventoinha nao e dela. Ver _curva.
        self._curva_escrito = None
        self._curva_primeira = True
        self._curva_falhas = 0
        self._curva_cedeu = False
        self._curva_sem_guarda_avisado = False
        # As ultimas leituras: a curva usa a mediana delas (curva.JANELA).
        self._curva_cpus = deque(maxlen=curva.JANELA)
        self._curva_gpus = deque(maxlen=curva.JANELA)
        self._fan_da_passada = _NAO_LIDO

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
        # A curva antes da rede: ela cumpre o invariante da rede, e a rede,
        # depois, confere por fora.
        self._curva(decisao.config, now_on_ac, perfil)
        self._guarda_ventoinha(decisao.config.maximum_mode and now_on_ac is True)

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
            self._suspensao_feita = False
            return
        active = on_ac is True
        falhas = []
        if active:
            try:
                if perfil_atual != THERMAL_PROFILE:
                    self._maximum.controls.set_profile(THERMAL_PROFILE)
            except WriteError as error:
                falhas.append(str(error))
        if active or not self._suspensao_feita:
            errors = self._maximum.enforce_runtime(config, active=active)
        else:
            # Suspenso nao e preso. O perfil de CPU guardado foi
            # devolvido quando o cabo saiu; dali em diante ele e de quem
            # usa a maquina. Reimpor a cada passada desfazia em 2 s
            # qualquer escolha feita no applet de energia.
            errors = ()
        # So conta como feita se deu certo: uma devolucao que falhou
        # deixaria a CPU em performance na bateria.
        self._suspensao_feita = not active and not errors
        falhas.extend(errors)
        self._avisa_falhas(falhas)
        confirmed = active and not errors
        if confirmed and not self._gpu_confirmed:
            self.log.info("GPUPowerMizerMode=1 confirmado no cliente NVML persistente")
        if not active and self._gpu_confirmed:
            self.log.info("pedido PowerMizer liberado na bateria")
        self._gpu_confirmed = confirmed

    def _read_fan_speed(self):
        sense = self.sysfs.sense_dir()
        if sense is None:
            return None
        try:
            return parse_fan_speed(self.sysfs.read(sense / "fan_speed"))
        except (OSError, ValueError):
            return None

    # Perfis em que a curva nao age: o driver escreve 0,0 ao entrar neles, e
    # o que o firmware faz com a ventoinha ali nunca foi medido.
    PERFIS_SEM_CURVA = ("quiet", "low-power")
    # Passadas seguidas sem a temperatura em que a curva segura o que esta,
    # antes de devolver o automatico. Uma leitura falha, de vez em quando,
    # e a proxima volta (armadilha 24).
    CURVA_FALHAS = 3

    def _curva(self, config, on_ac, perfil):
        """Uma passada da curva, e o fan_speed como ela o deixou: a rede, logo
        depois, julga esse valor sem ler de novo. Cada leitura de fan_speed e
        uma linha no journal do driver (test_leituras_wmi.py)."""
        self._fan_da_passada = self._curva_passada(config, on_ac, perfil)

    def _curva_passada(self, config, on_ac, perfil):
        """A curva propria (docs/plano-curva.md, secao 11), uma passada.

        So age com fan_curve no config, na tomada, fora de quiet e
        low-power, e com o guarda no ar. Fora disso, devolve o automatico
        se a ventoinha for dela, e para por ai.

        Um valor em fan_speed que ela nao escreveu, e que nao e o
        automatico, e de outra mao -- o Manual da janela: a curva espera o
        automatico voltar. Na primeira passada do agente nao ha como saber
        de quem e o manual que esta la, e ela o assume: com a curva ligada,
        a ventoinha e dela quando o agente sobe.

        Devolve o fan_speed depois do que ela fez.
        """
        setpoint = self._read_fan_speed()
        if not config.fan_curve:
            return self._curva_larga(setpoint, "fan_curve desligado")
        if on_ac is not True:
            return self._curva_larga(setpoint, "na bateria")
        if perfil in self.PERFIS_SEM_CURVA:
            return self._curva_larga(setpoint, f"perfil {perfil}")

        primeira, self._curva_primeira = self._curva_primeira, False
        if (
            not primeira
            and setpoint not in (None, (0, 0))
            and setpoint != self._curva_escrito
        ):
            if not self._curva_cedeu:
                self.log.info(
                    "curva: fan_speed em %d,%d, que ela não escreveu; "
                    "espera o automático voltar",
                    *setpoint,
                )
            self._curva_cedeu = True
            self._curva_escrito = None
            return setpoint
        if self._curva_cedeu:
            self.log.info("curva: o automático voltou; a curva retoma")
        self._curva_cedeu = False

        cpu = telemetry.acer_cpu_temp(self.sysfs)
        gpu = telemetry.acer_gpu_temp(self.sysfs)
        alvo = None
        if cpu is not None and gpu is not None:
            self._curva_cpus.append(cpu)
            self._curva_gpus.append(gpu)
            alvo = curva.decide(
                curva.mediana(self._curva_cpus),
                curva.mediana(self._curva_gpus),
                self._curva_escrito,
                gpu_agora=gpu,
            )
        if alvo is None:
            self._curva_falhas += 1
            if self._curva_falhas >= self.CURVA_FALHAS:
                return self._curva_larga(
                    setpoint, f"sem a temperatura há {self._curva_falhas} passadas"
                )
            return setpoint
        self._curva_falhas = 0
        if alvo == setpoint and alvo == self._curva_escrito:
            return setpoint

        # O registro antes da escrita: sem ele o guarda nao reconheceria o
        # manual como do agente, e um agente travado deixaria a ventoinha
        # baixa sem ninguem. Sem guarda, a curva nao age. Registra tambem
        # quando assume um manual que ja estava la, sem escrever.
        anterior = fan_speed_value(*setpoint) if setpoint else "0,0"
        if not guarda.registra(anterior, fan_speed_value(*alvo)):
            if not self._curva_sem_guarda_avisado:
                self.log.warning(
                    "curva: sem onde registrar o que escreve (RuntimeDirectory "
                    "da unit); sem o guarda, a curva não age"
                )
            self._curva_sem_guarda_avisado = True
            return setpoint
        self._curva_sem_guarda_avisado = False
        if alvo != setpoint:
            try:
                self._controls.set_fan_speed(*alvo)
            except WriteError as erro:
                self.log.warning("curva: não conseguiu escrever %d,%d: %s", *alvo, erro)
                return setpoint
        if self._curva_escrito is None:
            self.log.info(
                "curva: ventoinha em %d,%d (CPU a %d °C, GPU a %d °C)", *alvo, cpu, gpu
            )
        self._curva_escrito = alvo
        return alvo

    def _curva_larga(self, setpoint, motivo):
        """Devolve o automatico, se a ventoinha for da curva. Devolve o
        fan_speed depois disso."""
        escrito, self._curva_escrito = self._curva_escrito, None
        self._curva_falhas = 0
        self._curva_cpus.clear()
        self._curva_gpus.clear()
        if escrito is None or setpoint != escrito:
            return setpoint
        try:
            self._controls.set_fan_speed(0, 0)
        except WriteError as erro:
            self.log.warning("curva: não conseguiu devolver o automático (%s): %s", motivo, erro)
            return setpoint
        self.log.info("curva: ventoinha devolvida ao automático (%s)", motivo)
        return (0, 0)

    def _guarda_ventoinha(self, maximo_ativo):
        """A rede da ventoinha manual: devolve o automatico, e so isso.

        A ordem das leituras e o custo. fan_speed o driver responde de
        memoria; se ele nao diz manual baixo, a passada acaba ali. A GPU
        pelo EC e uma chamada ao firmware, e so com ela quente vem a
        rotacao, que sao mais duas. Nunca o nvidia-smi (armadilha 20).

        `maximo_ativo` e pedido E na tomada, como em _reconcile_maximum:
        e o modo que troca a curva do automatico.
        """
        # A curva acabou de ler, e talvez de escrever: vale o que ela deixou.
        setpoint, self._fan_da_passada = self._fan_da_passada, _NAO_LIDO
        if setpoint is _NAO_LIDO:
            setpoint = self._read_fan_speed()
        if not fan_guard.armada(setpoint, maximo_ativo):
            self._rede_seguidas = 0
            self._rede_recusa_avisada = False
            return

        gpu = telemetry.acer_gpu_temp(self.sysfs)
        rpm = telemetry.fan_rpm(self.sysfs) if fan_guard.quente(gpu) else None
        veredito = fan_guard.decide(
            self._rede_seguidas, setpoint, maximo_ativo, gpu, rpm
        )
        self._rede_seguidas = veredito.seguidas
        if not veredito.dispara:
            return

        try:
            self._controls.set_fan_speed(0, 0)
        except WriteError as erro:
            # A conta fica onde esta: a proxima passada tenta de novo.
            if not self._rede_recusa_avisada:
                self.log.warning(
                    "rede térmica: não conseguiu devolver a ventoinha ao "
                    "automático, com a GPU a %d °C: %s",
                    gpu,
                    erro,
                )
            self._rede_recusa_avisada = True
            return

        # Nada daqui e guardado: o manual so volta pela mao de quem o
        # escolheu. A linha e o unico aviso -- decisao do usuario.
        self._rede_seguidas = 0
        self._rede_recusa_avisada = False
        self.log.warning(
            "rede térmica: ventoinha em manual a %d,%d (%d / %d rpm) com a "
            "GPU a %d °C; devolvida ao automático",
            *setpoint,
            *rpm,
            gpu,
        )
        if self._curva_escrito is not None and setpoint == self._curva_escrito:
            self._curva_desliga()

    def _curva_desliga(self):
        """A rede disparou com a curva ativa: e defeito da curva, que
        cumpre o invariante dela (docs/plano-curva.md, secao 8). A curva sai,
        e sai no arquivo -- senao ela reescreveria o manual na passada
        seguinte, e a rede o devolveria de novo."""
        self._curva_escrito = None
        self.log.warning(
            "curva: a rede térmica disparou com a curva ativa; a curva foi "
            "desligada (fan_curve = false). É defeito da curva"
        )
        try:
            save(dataclasses.replace(load(self.config_path), fan_curve=False), self.config_path)
        except OSError as erro:
            self.log.warning("não foi possível gravar a configuração: %s", erro)

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

    def _avisa_systemd(self, mensagem):
        """sd_notify, pela unit Type=notify. Sem socket -- num terminal, nos
        testes -- nao ha a quem avisar. Com socket e sem conseguir, o
        WatchdogSec vai matar um agente sadio a cada poucos segundos: isso
        merece uma linha, uma vez."""
        if guarda.notifica(mensagem) or not os.environ.get("NOTIFY_SOCKET"):
            return
        if not self._aviso_systemd_falhou:
            self.log.warning("não foi possível avisar o systemd (%s)", mensagem)
        self._aviso_systemd_falhou = True

    def run(self, stop_event=None):
        """O laco. Para quando `stop_event` for sinalizado."""
        parar = stop_event or threading.Event()
        self._aviso_systemd_falhou = False
        self.log.info("agente no ar, sondando a cada %.1f s", self.interval)
        self._avisa_systemd("READY=1")
        try:
            while not parar.is_set():
                try:
                    self.tick()
                except Exception:  # nunca deixar o laco morrer por um tick ruim
                    self.log.exception("falha inesperada numa passada")
                # Depois de cada passada, boa ou ruim: o agente esta vivo.
                # Quem para de avisar e o travado, e o WatchdogSec o mata --
                # e o guarda devolve a ventoinha (docs/plano-curva.md, secao 8).
                self._avisa_systemd("WATCHDOG=1")
                parar.wait(self.interval)
        finally:
            self._release_gpu()
        self.log.info("agente encerrado")
