#!/usr/bin/env python3
"""Recorta os tracos da medicao termica para virarem teste.

Os tracos de E2, E3, E3b e os dois passivos de jogo moram em
~/.local/state/nexus-sense/, fora do repositorio: 670 kB, 28 colunas. O que a
rede da ventoinha le sao seis delas. Este roteiro grava em
tests/python/tracos/ so essas colunas, e so as janelas em que a condicao
vale -- conferida linha a linha, nao pelo nome do arquivo:

    e2.tsv, e3.tsv, e3b.tsv    os tres ensaios, inteiros, a 1 Hz
    jogo-auto.tsv              automatico, com jogo, modo maximo desligado
    jogo-auto-maximo.tsv       o mesmo, com o modo maximo ligado
    rede-sem-rede-maximo.tsv   o portao da sessao 2, contra a versao sem rede,
                               com o modo maximo ligado: o piso ate o aborto
    rede-desligado.tsv         o portao, ja com a rede, com o modo desligado:
                               o controle a 60% com a GPU quente

Por que a janela e nao o arquivo: o passivo "da noite" comecou as 19:31, com
o modo maximo desligado, e seguiu gravando. Dentro dele estao o E3b (duas
amostras com a ventoinha em 1,1), cinco minutos de mutacoes do ensaio
esquentando a maquina, a virada para o modo maximo as 21:26 e o fim do jogo.
"O passivo com o modo desligado" e a janela das 19:50 as 21:25, e so ela.

Nao faz parte da suite e nao precisa rodar de novo: o resultado esta no
repositorio. Serve para refazer o recorte, ou para recortar um traco novo.

    python3 tests/hardware/recorta-tracos.py [pasta dos tracos]

Sai com 1 se um traco sumiu ou se alguma linha de uma janela esta fora da
condicao que a janela promete.
"""
import csv
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
DESTINO = REPO / "tests/python/tracos"
ORIGEM = pathlib.Path.home() / ".local/state/nexus-sense"

COLUNAS = (
    "epoch", "hora", "fase", "fan_speed", "rpm_cpu", "rpm_gpu",
    "ec_gpu", "pacote", "acad", "maximo", "jogo",
)

# (destino, origem, primeira epoca, ultima epoca, o que toda linha tem de ter)
# Epoca e nao hora: os passivos seguem gravando, e outro jogo noutro dia
# cairia na mesma faixa de horas.
RECORTES = (
    ("e2.tsv", "ensaio-e2-20261010-104034.tsv", None, None,
     {"acad": "1", "maximo": "false", "jogo": "0"}),
    ("e3.tsv", "ensaio-e3-20261010-185354.tsv", None, None,
     {"acad": "1", "maximo": "false", "jogo": "0"}),
    ("e3b.tsv", "ensaio-e3b-20261010-194448.tsv", None, None,
     {"acad": "1", "maximo": "false"}),
    ("rede-sem-rede-maximo.tsv", "ensaio-rede-20261010-233636.tsv", None, None,
     {"acad": "1", "maximo": "true"}),
    ("rede-desligado.tsv", "ensaio-rede-20261011-000321.tsv", None, None,
     {"acad": "1", "maximo": "false"}),
    ("jogo-auto.tsv", "passivo-20261010-noite.tsv", 1791672600, 1791678359,
     {"acad": "1", "maximo": "false", "fan_speed": "0,0",
      "perfil": "balanced-performance", "dgpu": "active"}),
    ("jogo-auto-maximo.tsv", "passivo-20261010-maximo.tsv", 1791678403, 1791680579,
     {"acad": "1", "maximo": "true", "fan_speed": "0,0",
      "perfil": "balanced-performance", "dgpu": "active"}),
)


def recorta(origem, primeira, ultima, condicao):
    with open(origem, newline="") as arquivo:
        linhas = list(csv.DictReader(arquivo, delimiter="\t"))
    janela = [
        linha for linha in linhas
        if (primeira is None or int(linha["epoch"]) >= primeira)
        and (ultima is None or int(linha["epoch"]) <= ultima)
    ]
    fora = [
        (linha["hora"], coluna, linha[coluna])
        for linha in janela
        for coluna, valor in condicao.items()
        if linha[coluna] != valor
    ]
    # Os passivos nao tem ensaio dentro: com jogo, do comeco ao fim.
    if "fase" not in linhas[0]:
        fora += [(l["hora"], "jogo", l["jogo"]) for l in janela if l["jogo"] == "0"]
    return janela, fora


def main(argv):
    origem = pathlib.Path(argv[1]) if len(argv) > 1 else ORIGEM
    DESTINO.mkdir(parents=True, exist_ok=True)
    falhou = False
    for destino, nome, primeira, ultima, condicao in RECORTES:
        if not (origem / nome).is_file():
            print(f"ERRO traco ausente: {origem / nome}")
            falhou = True
            continue
        janela, fora = recorta(origem / nome, primeira, ultima, condicao)
        if fora or not janela:
            print(f"ERRO {destino}: {len(janela)} linhas, {len(fora)} fora da condicao")
            for item in fora[:5]:
                print("     ", *item)
            falhou = True
            continue
        with open(DESTINO / destino, "w", newline="") as arquivo:
            saida = csv.writer(arquivo, delimiter="\t", lineterminator="\n")
            saida.writerow(COLUNAS)
            for linha in janela:
                saida.writerow(linha.get(c, "passivo") for c in COLUNAS)
        print(f"{destino}: {len(janela)} linhas, {janela[0]['hora']} a {janela[-1]['hora']}")
    return 1 if falhou else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
