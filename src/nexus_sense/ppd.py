"""O power-profiles-daemon, pelo barramento.

Por que `busctl` e nao `powerprofilesctl`: o segundo e um script Python.
Medido em 2026-10-09: 135 ms por chamada, contra 3,9 ms do `busctl` para
a mesma propriedade. O agente pergunta o perfil a cada passada em modo
maximo, e so essa pergunta custava 7,8% de um nucleo o dia inteiro.

O `busctl` vem com o systemd, que o agente ja exige. Nome, caminho e
formato da resposta foram conferidos nesta maquina com o ppd 0.30; o nome
antigo, net.hadess.PowerProfiles, ainda responde, mas e o legado.
"""

import json
import subprocess

SERVICE = "org.freedesktop.UPower.PowerProfiles"
OBJECT = "/org/freedesktop/UPower/PowerProfiles"


def get_argv(prop):
    return [
        "busctl", "--system", "--json=short", "get-property",
        SERVICE, OBJECT, SERVICE, prop,
    ]


def set_argv(profile):
    return [
        "busctl", "--system", "set-property",
        SERVICE, OBJECT, SERVICE, "ActiveProfile", "s", profile,
    ]


def run(args, runner=subprocess.run):
    """Roda o comando. None quando nem rodar deu."""
    try:
        return runner(args, capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return None


def _get(prop, runner):
    """O valor de uma propriedade. None se o ppd nao responde ou se a
    resposta nao e o JSON que o busctl promete."""
    result = run(get_argv(prop), runner)
    if result is None or result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)["data"]
    except (ValueError, KeyError, TypeError):
        return None


def active_profile(runner=subprocess.run):
    valor = _get("ActiveProfile", runner)
    return valor if isinstance(valor, str) and valor else None


def platform_drivers(runner=subprocess.run):
    """O PlatformDriver de cada perfil que tem um. None se o ppd nao
    responde.

    Nem todo perfil traz a chave: nesta maquina o 'performance' vem so
    com CpuDriver.
    """
    perfis = _get("Profiles", runner)
    if not isinstance(perfis, list):
        return None
    drivers = []
    for perfil in perfis:
        try:
            drivers.append(perfil["PlatformDriver"]["data"])
        except (KeyError, TypeError):
            continue
    return drivers
