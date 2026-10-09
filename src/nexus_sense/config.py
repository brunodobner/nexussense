"""Preferencias do usuario.

O sysfs guarda o estado; este arquivo guarda a intencao -- o que o
kernel nao tem como saber. Ver spec secao 4.1.

Nenhuma leitura daqui pode derrubar o agente: arquivo ausente,
corrompido ou com tipos errados cai para o padrao e segue.
"""

import os
import tomllib
from dataclasses import asdict, dataclass, fields
from pathlib import Path

import tomli_w


@dataclass(frozen=True)
class Config:
    # Ligado desde a virada. Enquanto o damx-daemon existia isto ficava
    # desligado, para os dois nao disputarem o perfil; agora nao ha com
    # quem disputar. Ver spec secao 2.9.
    auto_switch: bool = True

    # 'balanced' e 'low-power' sao os unicos que o driver aceita na
    # bateria. Ver spec secao 2.8.
    battery_profile: str = "balanced"

    # Em que perfil estava na tomada, para devolver ao religar. O daemon
    # antigo derrubava e nunca restaurava.
    saved_ac_profile: str | None = None

    # Modo composto do app: o firmware continua anunciando quatro perfis.
    maximum_mode: bool = False
    maximum_saved_profile: str | None = None
    maximum_saved_ppd: str | None = None
    maximum_saved_powermizer: str | None = None


def default_path():
    base = os.environ.get("XDG_CONFIG_HOME")
    raiz = Path(base) if base else Path.home() / ".config"
    return raiz / "nexus-sense/config.toml"


def load(path):
    """Le a configuracao. Qualquer problema devolve os padroes."""
    try:
        with open(path, "rb") as arquivo:
            bruto = tomllib.load(arquivo)
    except (OSError, tomllib.TOMLDecodeError):
        return Config()

    padrao = Config()
    aceitos = {}
    for campo in fields(Config):
        if campo.name not in bruto:
            continue
        valor = bruto[campo.name]
        atual = getattr(padrao, campo.name)
        esperado = type(atual) if atual is not None else str
        if isinstance(valor, esperado) and not (
            esperado is int and isinstance(valor, bool)
        ):
            aceitos[campo.name] = valor

    return Config(**aceitos)


def save(config, path):
    """Grava a configuracao, criando o diretorio se faltar.

    A troca e atomica: escreve num temporario ao lado e o renomeia por
    cima. Abrir o proprio arquivo com 'wb' o truncava antes de escrever,
    e o agente -- que rele a cada passada -- podia pegar o arquivo vazio
    e tomar os padroes por verdade.
    """
    # realpath, para gravar atraves de um link em vez de troca-lo por
    # uma copia.
    caminho = Path(os.path.realpath(path))
    caminho.parent.mkdir(parents=True, exist_ok=True)
    # tomli_w nao serializa None; a ausencia da chave e o proprio None.
    dados = {k: v for k, v in asdict(config).items() if v is not None}
    # O PID no nome separa os dois escritores, janela e agente.
    provisorio = caminho.with_name(f".{caminho.name}.{os.getpid()}.tmp")
    try:
        with open(provisorio, "wb") as arquivo:
            tomli_w.dump(dados, arquivo)
        os.replace(provisorio, caminho)
    finally:
        # Depois do replace ele ja nao existe; so sobra se algo falhou.
        provisorio.unlink(missing_ok=True)
