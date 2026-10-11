"""Perfis termicos: ordem, disponibilidade e navegacao.

Modulo puro: recebe listas e devolve listas, nao toca em disco. Toda a
logica que a bandeja e a janela usam para decidir o que mostrar e o que
o scroll faz mora aqui.
"""

# Do mais economico ao mais agressivo. A ordem importa: e ela que define
# o que "subir" e "descer" significam no scroll da bandeja.
PROFILES = (
    "low-power",
    "quiet",
    "balanced",
    "balanced-performance",
    "performance",
)

LABELS = {
    "low-power": "Econômico",
    "quiet": "Silencioso",
    "balanced": "Equilibrado",
    "balanced-performance": "Desempenho",
    "performance": "Turbo",
}

# O driver devolve -EOPNOTSUPP para estes tres quando nao ha energia da
# tomada (linuwu_sense.c:2317). Medido na maquina, com o cabo fora.
#
# Repare que o alcance resultante NAO e contiguo: o 'quiet' fica entre
# dois permitidos e mesmo assim e barrado, apesar de ser mais economico
# que o 'balanced'. Ver spec secao 2.8.
AC_ONLY = frozenset({"quiet", "balanced-performance", "performance"})
MAXIMUM_MODE = "maximum"
MAXIMUM_LABEL = "Desempenho máximo"


def available(choices, on_ac):
    """Perfis que o driver aceita agora, na ordem canonica.

    `choices` e o que o firmware anuncia; nesta maquina sao quatro, sem o
    'performance'. Ver spec secao 2.10.
    """
    anunciados = set(choices)
    return tuple(
        perfil
        for perfil in PROFILES
        if perfil in anunciados and (on_ac or perfil not in AC_ONLY)
    )


def nearest(current, options):
    """O perfil de `options` mais proximo de `current` na escada."""
    if not options:
        return current
    if current in options:
        return current
    if current not in PROFILES:
        return options[0]
    alvo = PROFILES.index(current)
    return min(options, key=lambda p: abs(PROFILES.index(p) - alvo))


def neighbour(current, choices, on_ac, step):
    """Proximo perfil valido na direcao `step` (+1 sobe, -1 desce).

    Anda sobre a lista de disponiveis, o que faz o indisponivel ser
    pulado em vez de virar um degrau que falharia. Bate no limite e para.
    Se o perfil corrente nao estiver mais disponivel -- caso de quem
    estava em balanced-performance quando o cabo saiu -- vai para o
    valido mais proximo.
    """
    opcoes = available(choices, on_ac)
    if not opcoes:
        return current
    if current not in opcoes:
        return nearest(current, opcoes)
    destino = opcoes.index(current) + step
    destino = max(0, min(len(opcoes) - 1, destino))
    return opcoes[destino]


# ----------------------------------------------------------------------
# Validacao dos controles graveis
#
# A validacao aqui espelha a do driver de proposito: e melhor recusar na
# interface, com a razao escrita, do que mandar e receber -EINVAL.
# ----------------------------------------------------------------------

USB_LEVELS = (0, 10, 20, 30)


def fan_speed_value(cpu, gpu):
    """Formata a velocidade das duas ventoinhas para o sysfs.

    O driver le "%d,%d" com strsep na virgula e recusa fora de 0-100
    (linuwu_sense.c:3681-3693). Zero significa automatico, nao parado.
    """
    for valor in (cpu, gpu):
        if not isinstance(valor, int) or not 0 <= valor <= 100:
            raise ValueError(f"velocidade de ventoinha fora de 0 a 100: {valor!r}")
    return f"{cpu},{gpu}"


def parse_fan_speed(raw):
    """Le de volta o "%d,%d" que o driver imprime."""
    partes = raw.strip().split(",")
    if len(partes) != 2:
        raise ValueError(f"velocidade de ventoinha ilegivel: {raw!r}")
    try:
        return int(partes[0]), int(partes[1])
    except ValueError as erro:
        raise ValueError(f"velocidade de ventoinha ilegivel: {raw!r}") from erro


# De 20% para baixo o firmware segura a ventoinha no mesmo piso, ~2000 /
# ~1665 rpm: medido em 2026-10-10, de 20% a 1% (docs/plano-termico.md,
# secao 6). O cursor da tela segue de 0 a 100 e vale FAN_FLOOR a 100
# aqui. Somem duas coisas: a faixa em que mexer no cursor nao mudava
# nada, e o zero num lado so, que era aquela ventoinha em automatico --
# automatico passa a ser so pelo botao.
FAN_FLOOR = 20


def fan_bar_to_firmware(bar):
    """Da posicao do cursor, 0 a 100, para o valor de fan_speed."""
    return FAN_FLOOR + (2 * bar * (100 - FAN_FLOOR) + 100) // 200


def fan_firmware_to_bar(value):
    """De fan_speed para a posicao do cursor. Do piso para baixo, zero.

    A barra tem 101 posicoes e o firmware 81 degraus: a volta devolve
    uma posicao que vale o degrau lido, nao necessariamente a que o
    usuario soltou. Quem repinta confere isso antes de mexer no cursor.
    """
    if value <= FAN_FLOOR:
        return 0
    faixa = 100 - FAN_FLOOR
    return (2 * (value - FAN_FLOOR) * 100 + faixa) // (2 * faixa)


def usb_charging_value(level):
    """O nivel de bateria abaixo do qual a carga USB para de fornecer."""
    if level not in USB_LEVELS:
        raise ValueError(f"carga USB deve ser 0, 10, 20 ou 30: {level!r}")
    return str(level)


def bool_value(ligado):
    return "1" if ligado else "0"


def parse_bool(raw):
    return raw.strip() == "1"
