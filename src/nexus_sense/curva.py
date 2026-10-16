"""A curva propria da ventoinha -- docs/plano-curva.md, secao 11.

Cada ventoinha pela propria temperatura, as duas como o EC as ve: a da CPU
pela CPU pelo EC, a da GPU pela GPU pelo EC. A tabela foi desenhada com o
usuario a partir dos tetos medidos (secao 2.1 do plano) e do mapa de
porcentagem para rotacao de E2, e aprovada por ele em 2026-10-15. E escolha
dele: nenhuma medida a move.

Uma curva so, com o modo maximo ligado ou desligado. Ela gira abaixo do
firmware entre 50 e 70 C, e por isso so entra no ar com o guarda
(guarda.py): o agente travado com a ventoinha baixa e devolvido pela unit.

Puro de proposito, como fan_guard.decide: recebe o que foi lido e o que a
curva escreveu por ultimo, devolve o que escrever. Quem le e quem escreve e
o agente.
"""

import math

from . import fan_guard

# (temperatura em C, porcentagem de manual). Entre dois pontos, linha reta;
# fora deles, o ponto da ponta. Pelo mapa de E2, a CPU vai de 2.300 a 7.450
# rpm e a GPU de 2.000 a 6.980.
CPU = ((50, 25), (60, 35), (70, 50), (80, 73), (88, 99))
GPU = ((55, 24), (65, 37), (70, 53), (76, 82), (80, 99))

# Com a GPU quente a rede exige das DUAS ventoinhas o manual que gira como o
# automatico. A curva e uma so, com ou sem o modo maximo: vale o mais alto dos
# dois equivalentes. Abaixo dele a rede devolveria o automatico, e a curva
# reescreveria o manual na passada seguinte -- vaivem.
GPU_QUENTE = fan_guard.GPU_QUENTE
PISO_QUENTE = fan_guard.AUTOMATICO[True].percentual

# Sobe na hora; so desce depois de a temperatura cair isto. Provisorio: se
# ajusta pelo ouvido.
HISTERESE = 3


def na_tabela(tabela, temperatura):
    """A porcentagem da tabela nesta temperatura, arredondada para cima: na
    duvida, um ponto a mais de ventoinha."""
    t0, p0 = tabela[0]
    if temperatura <= t0:
        return p0
    for (ta, pa), (tb, pb) in zip(tabela, tabela[1:]):
        if temperatura <= tb:
            return math.ceil(pa + (temperatura - ta) * (pb - pa) / (tb - ta))
    return tabela[-1][1]


def _alvo(tabela, temperatura, gpu, indice):
    porcentagem = na_tabela(tabela, temperatura)
    if gpu >= GPU_QUENTE:
        porcentagem = max(porcentagem, PISO_QUENTE[indice])
    return porcentagem


def _uma(tabela, temperatura, gpu, indice, atual):
    # Duas leituras da mesma tabela: a de agora diz ate onde subir, e a de
    # tres graus acima diz ate onde descer. Entre as duas, fica onde esta.
    # O piso da GPU quente entra nas duas, e por isso tambem so sai tres
    # graus abaixo de onde entrou.
    sobe = _alvo(tabela, temperatura, gpu, indice)
    desce = _alvo(tabela, temperatura + HISTERESE, gpu + HISTERESE, indice)
    if atual is None or atual < sobe:
        return sobe
    if atual > desce:
        return desce
    return atual


def decide(cpu, gpu, atual):
    """O par a escrever em fan_speed: (CPU, GPU), em porcentagem de manual.

    `cpu` e `gpu` em Celsius inteiros. A GPU vale zero com a placa
    dormindo, e isso e repouso. `atual` e o par que a curva escreveu por
    ultimo, ou None se ela ainda nao escreveu.

    Sem uma das leituras (None) devolve None: sem saber a temperatura, a
    curva nao decide, e quem chama segura ou devolve o automatico.
    """
    if cpu is None or gpu is None:
        return None
    anterior = atual or (None, None)
    return (
        _uma(CPU, cpu, gpu, 0, anterior[0]),
        _uma(GPU, gpu, gpu, 1, anterior[1]),
    )
