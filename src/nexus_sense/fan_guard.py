"""A rede da ventoinha manual.

Por que isto existe: o firmware obedece ao manual ate o fim. Com a
ventoinha no piso e um jogo aberto, a GPU pelo EC subiu um grau por
segundo e bateu no limite em sete -- medido em 2026-10-10, e o EC nao
tomou a ventoinha de volta em dez minutos a 94 C. Quem deixa o cursor la
embaixo para ter silencio e depois abre um jogo fica sem ninguem que suba
a rotacao. Ver docs/plano-termico.md, secoes 6 e 11.

O que ela faz e pouco: devolve a ventoinha ao automatico. Nao guarda o
setpoint, nao devolve o manual depois e nao inventa curva -- a do
fabricante e a que ele validou.

Puro de proposito, como `agent.decide`: recebe o que foi lido, devolve o
que fazer. Quem le e quem escreve e o agente.

Todos os numeros daqui sairam dos tracos da medicao, e os tracos sao
teste: tests/python/test_fan_guard_tracos.py.
"""

from typing import NamedTuple


class Automatico(NamedTuple):
    """O automatico com um jogo aberto, e o manual que gira o mesmo."""

    percentual: tuple[int, int]  # CPU, GPU
    rpm: tuple[int, int]


# Sao duas curvas, e quem troca de uma para a outra e o modo maximo: com
# ele ligado a ventoinha gira 1900 rpm a mais, no mesmo perfil termico e
# com o mesmo jogo. "Abaixo do que o automatico faria" tem, entao, duas
# respostas. Medidas em balanced-performance, na tomada; noutro perfil
# vale a do modo desligado, que e a que arma menos.
AUTOMATICO = {
    False: Automatico(percentual=(53, 50), rpm=(4414, 4003)),
    True: Automatico(percentual=(81, 82), rpm=(6318, 5984)),
}

# Celsius, no canal GPU do hwmon do acer. Tres medidas o cercam:
#   69  o maximo com carga so de CPU, dez minutos no piso: e calor do
#       dissipador vizinho, e nao e caso desta rede;
#   75  o maximo em automatico com jogo e o modo maximo ligado: um manual
#       que gire como esse automatico nao dispara;
#   79  de onde a GPU partiu no ensaio que abortou, sete segundos e seis
#       graus antes do limite.
GPU_QUENTE = 76

# Passadas seguidas, a 2 s cada. Uma so bastaria para chegar antes do
# aborto, mas pegaria o cursor de passagem por um valor baixo no meio de
# um arrasto, e a rotacao ainda caindo depois de uma escrita.
SEGUIDAS = 2


class Veredito(NamedTuple):
    seguidas: int  # passadas seguidas armada, quente e lenta, com esta
    dispara: bool


def _baixas(setpoint, maximo):
    """Quais ventoinhas estao em manual abaixo do automatico deste modo.

    Zero e aquela ventoinha em automatico, e nao parada: nao conta.
    """
    if setpoint is None:
        return ()
    equivalente = AUTOMATICO[bool(maximo)].percentual
    return tuple(
        indice
        for indice, (manual, auto) in enumerate(zip(setpoint, equivalente))
        if 0 < manual < auto
    )


def armada(setpoint, maximo):
    """A rede so olha temperatura se isto disser que sim.

    `setpoint` e o par de fan_speed, que o driver responde de memoria,
    sem chamar o firmware: em automatico, em maximo ou em manual alto, a
    rede custa essa leitura e mais nada.
    """
    return bool(_baixas(setpoint, maximo))


def decide(seguidas, setpoint, maximo, gpu, rpm):
    """Uma passada da rede. `dispara` quer dizer: escreva 0,0.

    `gpu` vale zero com a placa dormindo e None se a leitura falhou; nos
    dois casos nao ha prova de calor, e tirar o manual de quem o escolheu
    pede prova. `rpm` existe porque `setpoint` e so o que o driver lembra:
    se a ventoinha ja gira como o automatico, quem manda nela e o
    firmware e nao ha o que devolver.
    """
    baixas = _baixas(setpoint, maximo)
    if not baixas or gpu is None or gpu < GPU_QUENTE or rpm is None:
        return Veredito(0, False)

    teto = AUTOMATICO[bool(maximo)].rpm
    if not any(rpm[indice] < teto[indice] for indice in baixas):
        return Veredito(0, False)

    seguidas += 1
    return Veredito(seguidas, seguidas >= SEGUIDAS)
