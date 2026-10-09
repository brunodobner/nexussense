"""Fatos da sessao do usuario que nao estao no sysfs.

Ficam fora da GUI de proposito: o Diagnostico e o rodape da barra
lateral perguntam a mesma coisa, e nenhum dos dois deve chamar
subprocess por conta propria.
"""

import subprocess

from . import ppd

AGENT_UNIT = "nexus-sense-agent.service"


def agent_active(runner=subprocess.run):
    """True quando o servico de usuario do agente esta no ar.

    Qualquer falha -- systemd ausente, unit inexistente, sessao sem
    barramento -- responde False. Nao saber e o mesmo que estar fora,
    para efeito do que a tela mostra.
    """
    try:
        saida = runner(
            ["systemctl", "--user", "is-active", "--quiet", AGENT_UNIT],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return saida.returncode == 0


import grp
import os
import pwd
from typing import NamedTuple

GROUP = "nexus_sense"


def in_group(name, groups=None):
    """True quando o usuario e membro deste grupo **por cadastro**.

    Cadastro, e nao sessao, de proposito. Quem entrou no grupo agora
    consta em /etc/group mas ainda nao o carrega, e as duas situacoes
    pedem frases diferentes na tela: uma manda relogar, a outra manda
    entrar no grupo. Ver spec secao 9.

    Quem responde "da para escrever agora?" nao e esta funcao, e a
    permissao do arquivo -- DeviceState.writable. Consultar so
    os.getgroups() aqui colapsaria os dois casos num so, e a tela diria
    "voce nao esta no grupo" para quem esta.
    """
    if groups is not None:
        return name in set(groups)

    # A sessao ja carregar o grupo basta como prova de que e membro.
    try:
        if name in {grp.getgrgid(gid).gr_name for gid in os.getgroups()}:
            return True
    except (KeyError, OSError):
        pass

    # Nao carregar nao quer dizer nao ser membro: falta relogar.
    try:
        usuario = pwd.getpwuid(os.getuid()).pw_name
        entrada = grp.getgrnam(name)
    except (KeyError, OSError):
        return False
    return usuario in entrada.gr_mem or entrada.gr_gid == os.getgid()


class PpdState(NamedTuple):
    present: bool
    profile: str | None
    drives_platform: bool


def ppd_state(runner=subprocess.run):
    """O power-profiles-daemon esta ai? Esta disputando o platform_profile?

    Medido nesta maquina: o ppd 0.30 anuncia 'PlatformDriver: placeholder',
    ou seja, dirige so o intel_pstate. Por isso ele diz 'performance'
    enquanto o platform_profile diz 'balanced', sem conflito nenhum. Se
    numa versao futura ele passar a se ligar, esta verificacao acusa.
    Ver spec secao 2.11.
    """
    # Pelo barramento, como o agente: ver ppd.py. Servico que nao
    # responde conta como ausente -- nao ha o que disputar com quem nao
    # esta rodando.
    plataformas = ppd.platform_drivers(runner)
    if plataformas is None:
        return PpdState(present=False, profile=None, drives_platform=False)

    return PpdState(
        present=True,
        profile=ppd.active_profile(runner),
        drives_platform=any(p and p != "placeholder" for p in plataformas),
    )
