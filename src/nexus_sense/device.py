"""O instantaneo do aparelho, e os seis controles graveis.

Esta camada existe para que nenhum widget precise saber o que e sysfs.
A interface le um DeviceState e chama Controls; nao abre caminho, nao
valida valor e nao interpreta errno.

Distincao que a tela usa o tempo todo: `features` diz o que existe no
firmware, `writable` diz o que voce pode escrever agora. Um atributo que
existe e nao e gravavel produz uma frase diferente de um que nao existe.
Ver spec secao 9.
"""

import os
from typing import NamedTuple

from . import model

# Os cinco do grupo nitro_sense/predator_sense. O sexto gravavel e o
# profile, que mora sob platform-profile e por isso nao entra aqui.
SENSE_ATTRS = (
    "fan_speed",
    "battery_limiter",
    "usb_charging",
    "backlight_timeout",
    "battery_calibration",
)


class BasicState(NamedTuple):
    """O instantaneo que nao custa nada ao firmware.

    `features`, `writable` e `profile_writable` saem de `is_file` e
    `os.access` -- stat, nao leitura -- entao o driver nem acorda. Falta
    de proposito o *valor* dos cinco atributos do grupo sense: cada um
    deles e um `wmi_evaluate_method`, e quem roda em timer nao deve
    pagar por valor que nao exibe. Quem precisa deles chama `read_state`
    e recebe o tipo maior; tocar num campo ausente aqui e AttributeError
    na hora, e nao um None que finge ser "ilegivel".
    """

    module_loaded: bool
    on_ac: bool | None
    profile: str | None
    choices: tuple[str, ...]
    available: tuple[str, ...]
    features: frozenset
    writable: frozenset
    profile_writable: bool


class DeviceState(NamedTuple):
    module_loaded: bool
    on_ac: bool | None
    profile: str | None
    choices: tuple[str, ...]
    available: tuple[str, ...]
    features: frozenset
    writable: frozenset
    profile_writable: bool
    fan_speed: tuple[int, int] | None
    battery_limiter: bool | None
    usb_charging: int | None
    backlight_timeout: bool | None
    battery_calibration: bool | None
    driver_version: str | None


def _read(sysfs, caminho):
    """Le um atributo. Ausente ou ilegivel devolve None, nunca excecao."""
    if caminho is None or not caminho.is_file():
        return None
    try:
        return sysfs.read(caminho)
    except OSError:
        return None


def _parse(funcao, bruto):
    if bruto is None:
        return None
    try:
        return funcao(bruto)
    except ValueError:
        return None


def read_basic(sysfs):
    """Uma passada barata: nenhum atributo do grupo sense e lido."""
    sense = sysfs.sense_dir()
    perfil_caminho = sysfs.profile_path()

    features = set()
    writable = set()
    if sense is not None:
        for nome in SENSE_ATTRS:
            caminho = sense / nome
            if not caminho.is_file():
                continue
            features.add(nome)
            if os.access(caminho, os.W_OK):
                writable.add(nome)

    bruto_choices = _read(sysfs, sysfs.choices_path())
    choices = tuple(bruto_choices.split()) if bruto_choices else ()
    perfil = _read(sysfs, perfil_caminho)
    on_ac = sysfs.on_ac()

    disponiveis = ()
    if choices and on_ac is not None:
        disponiveis = model.available(choices, on_ac=on_ac)

    return BasicState(
        module_loaded=sysfs.module_loaded(),
        on_ac=on_ac,
        profile=perfil,
        choices=choices,
        available=disponiveis,
        features=frozenset(features),
        writable=frozenset(writable),
        profile_writable=(
            perfil_caminho is not None
            and perfil_caminho.is_file()
            and os.access(perfil_caminho, os.W_OK)
        ),
    )


def read_state(sysfs):
    """Uma passada completa pelo aparelho: o barato mais os cinco do
    grupo sense, que custam uma chamada WMI cada."""
    basico = read_basic(sysfs)
    sense = sysfs.sense_dir()

    def sense_attr(nome):
        return _read(sysfs, sense / nome) if nome in basico.features else None

    # Por nome, nao por posicao: reordenar BasicState nao pode calar aqui.
    return DeviceState(
        **basico._asdict(),
        fan_speed=_parse(model.parse_fan_speed, sense_attr("fan_speed")),
        battery_limiter=_parse(model.parse_bool, sense_attr("battery_limiter")),
        usb_charging=_parse(int, sense_attr("usb_charging")),
        backlight_timeout=_parse(model.parse_bool, sense_attr("backlight_timeout")),
        battery_calibration=_parse(model.parse_bool, sense_attr("battery_calibration")),
        driver_version=_read(sysfs, sense / "version") if sense is not None else None,
    )


import errno as _errno


class WriteError(Exception):
    """Falha de escrita ja traduzida para uma frase em pt-BR.

    Quem levanta e esta camada; quem mostra e a interface. Nenhum widget
    olha errno, e nenhuma tela mostra traceback. Ver spec secao 9.
    """

    def __init__(self, message):
        super().__init__(message)
        self.message = message


# As tres causas que acontecem de verdade nesta maquina. Qualquer outra
# cai no texto generico com o errno junto, para nao esconder novidade.
def _traduz(erro, alvo, valor):
    if erro.errno in (_errno.EACCES, _errno.EPERM):
        return (
            f"sem permissão para escrever em {alvo}. Confira se você está no "
            "grupo nexus_sense; se acabou de entrar nele, é preciso relogar "
            "para a sessão herdar o grupo."
        )
    if erro.errno == _errno.EOPNOTSUPP:
        return (
            f"o driver recusou {valor!r}: este valor não é aceito na bateria. "
            "Ligue o cabo para usá-lo."
        )
    if erro.errno == _errno.EINVAL:
        return f"o driver recusou o valor {valor!r} como inválido."
    if erro.errno == _errno.ENOENT:
        return f"{alvo} não existe neste firmware."
    return f"falha ao escrever em {alvo}: {erro.strerror or erro}"


class Controls:
    """Os seis atributos graveis, e nada mais.

    A validacao vem de model.py e roda antes da escrita: e melhor recusar
    aqui, com a razao escrita, do que mandar e receber -EINVAL.
    """

    def __init__(self, sysfs):
        self.sysfs = sysfs

    # ------------------------------------------------------------------
    # o perfil, que mora fora do grupo sense
    # ------------------------------------------------------------------

    def set_profile(self, profile):
        caminho = self.sysfs.profile_path()
        if caminho is None:
            raise WriteError("o perfil térmico não existe neste firmware.")
        self._write(caminho, profile, "o perfil térmico")

    # ------------------------------------------------------------------
    # os cinco do grupo sense
    # ------------------------------------------------------------------

    def set_fan_speed(self, cpu, gpu):
        self._write_sense("fan_speed", model.fan_speed_value(cpu, gpu))

    def set_usb_charging(self, level):
        self._write_sense("usb_charging", model.usb_charging_value(level))

    def set_battery_limiter(self, on):
        self._write_sense("battery_limiter", model.bool_value(on))

    def set_backlight_timeout(self, on):
        self._write_sense("backlight_timeout", model.bool_value(on))

    def set_battery_calibration(self, on):
        self._write_sense("battery_calibration", model.bool_value(on))

    # ------------------------------------------------------------------

    def _write_sense(self, nome, valor):
        sense = self.sysfs.sense_dir()
        if sense is None:
            raise WriteError("o driver não está carregado.")
        caminho = sense / nome
        if not caminho.is_file():
            raise WriteError(f"{nome} não existe neste firmware.")
        self._write(caminho, valor, nome)

    def _write(self, caminho, valor, alvo):
        try:
            self.sysfs.write(caminho, valor)
        except OSError as erro:
            raise WriteError(_traduz(erro, alvo, valor)) from erro


class SystemInfo(NamedTuple):
    product: str | None
    family: str | None                # 'nitro', 'predator' ou None
    driver_version: str | None
    module_params: dict


def read_system(sysfs):
    """Identidade da maquina e do driver, para o Diagnostico."""
    sense = sysfs.sense_dir()
    familia = None
    if sense is not None:
        familia = sense.name.split("_", 1)[0]

    parametros = {}
    for nome in ("nexus_sense", "linuwu_sense"):
        pasta = sysfs.root / "sys/module" / nome / "parameters"
        if not pasta.is_dir():
            continue
        for arquivo in sorted(pasta.iterdir()):
            valor = _read(sysfs, arquivo)
            if valor is not None:
                parametros[arquivo.name] = valor
        break

    return SystemInfo(
        product=_read(sysfs, sysfs.root / "sys/class/dmi/id/product_name"),
        family=familia,
        driver_version=_read(sysfs, sense / "version") if sense is not None else None,
        module_params=parametros,
    )
