#!/usr/bin/env python3
"""Os testes da rede da ventoinha mordem? Um numero ou uma guarda por vez.

A rede (src/nexus_sense/fan_guard.py, e o que o agente faz em volta dela)
tira o manual de quem o escolheu. Errar para um lado e deixar a GPU bater no
limite com um jogo aberto; errar para o outro e devolver o automatico a quem
so queria silencio. O que a prende no lugar sao os testes -- os de unidade,
os do agente e os tracos da medicao. Este roteiro prova os testes: copia o
fonte, estraga UMA coisa, roda o teste que a guarda, e cobra que ele reprove.

Nao faz parte da suite. E leve -- uns quinze segundos, um nucleo --, mas
como toda carga nao roda durante um ensaio na maquina.

    python3 tests/hardware/mutacoes-rede.py

Sai com 0 se toda mutacao foi reprovada; com 1 se alguma passou, ou se um
trecho a estragar nao existe mais no fonte -- a lista envelhece junto com o
codigo, e isso tambem e noticia.

Parente de tests/hardware/mutacoes-ensaio.py, que faz o mesmo pelo roteiro
do ensaio.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
REDE = "src/nexus_sense/fan_guard.py"
AGENTE = "src/nexus_sense/agent.py"
SENSORES = "src/nexus_sense/telemetry.py"

TRACOS = "tests/python/test_fan_guard_tracos.py"
UNIDADE = "tests/python/test_fan_guard.py"
LACO = "tests/python/test_agent_fan_guard.py"
LEITURA = "tests/python/test_telemetry.py"

CONFERE_ROTACAO = (
    "    if not any(rpm[indice] < teto[indice] for indice in baixas):\n"
    "        return Veredito(0, False)\n"
)

# (nome, arquivo, trecho, o que entra no lugar, teste que tem de reprovar)
MUT = [
    # ---- o limiar: cercado por 69, 75 e 79 graus, um de cada traco
    ("limiar em 83: tarde demais para o E3b", REDE, "GPU_QUENTE = 76", "GPU_QUENTE = 83", TRACOS),
    ("limiar em 80", REDE, "GPU_QUENTE = 76", "GPU_QUENTE = 80", TRACOS),
    ("limiar em 75: o automatico do modo maximo chega la", REDE, "GPU_QUENTE = 76", "GPU_QUENTE = 75", TRACOS),
    ("limiar em 69: dispara com carga so de CPU", REDE, "GPU_QUENTE = 76", "GPU_QUENTE = 69", TRACOS),
    ("quente so acima do limiar, e nao a partir dele", REDE,
     "return gpu is not None and gpu >= GPU_QUENTE", "return gpu is not None and gpu > GPU_QUENTE", UNIDADE),
    ("placa dormindo conta como quente", REDE,
     "return gpu is not None and gpu >= GPU_QUENTE", "return gpu is not None and (gpu == 0 or gpu >= GPU_QUENTE)", UNIDADE),
    # ---- quantas passadas
    ("quatro passadas seguidas", REDE, "SEGUIDAS = 2", "SEGUIDAS = 4", TRACOS),
    ("tres passadas seguidas", REDE, "SEGUIDAS = 2", "SEGUIDAS = 3", TRACOS),
    ("uma passada so", REDE, "SEGUIDAS = 2", "SEGUIDAS = 1", UNIDADE),
    ("a conta nao recomeca com uma passada fria", REDE,
     "    if not baixas or not quente(gpu) or rpm is None:\n        return Veredito(0, False)\n",
     "    if not baixas or not quente(gpu) or rpm is None:\n        return Veredito(seguidas, False)\n",
     UNIDADE),
    ("a conta nao recomeca com a rotacao de volta", REDE,
     CONFERE_ROTACAO, CONFERE_ROTACAO.replace("Veredito(0, False)", "Veredito(seguidas, False)"), UNIDADE),
    ("nunca dispara", REDE,
     "return Veredito(seguidas, seguidas >= SEGUIDAS)", "return Veredito(seguidas, False)", TRACOS),
    # ---- armar
    ("arma em qualquer manual", REDE, "if 0 < manual < auto", "if 0 < manual", TRACOS),
    ("arma tambem em automatico", REDE, "if 0 < manual < auto", "if manual < auto", UNIDADE),
    ("o equivalente do modo maximo vale para os dois modos", REDE,
     "equivalente = AUTOMATICO[bool(maximo)].percentual", "equivalente = AUTOMATICO[True].percentual", TRACOS),
    ("o equivalente do modo desligado vale para os dois modos", REDE,
     "equivalente = AUTOMATICO[bool(maximo)].percentual", "equivalente = AUTOMATICO[False].percentual", UNIDADE),
    # ---- a rotacao
    ("nao confere a rotacao", REDE, CONFERE_ROTACAO, "", UNIDADE),
    ("confere a rotacao de qualquer ventoinha", REDE, "for indice in baixas)", "for indice in (0, 1))", UNIDADE),
    ("a rotacao do automatico e a mesma nos dois modos", REDE,
     "teto = AUTOMATICO[bool(maximo)].rpm", "teto = AUTOMATICO[False].rpm", UNIDADE),
    # ---- o agente: o que le, e quando
    ("le temperatura sem estar armada", AGENTE,
     "        if not fan_guard.armada(setpoint, maximo_ativo):\n", "        if False:\n", LACO),
    ("le a rotacao com a GPU fria", AGENTE,
     "rpm = telemetry.fan_rpm(self.sysfs) if fan_guard.quente(gpu) else None",
     "rpm = telemetry.fan_rpm(self.sysfs)", LACO),
    ("o canal da GPU pelo numero, e nao pelo rotulo", SENSORES,
     "            if sysfs.read(rotulo) != GPU_LABEL:\n                continue\n",
     "            if rotulo.name != \"temp2_label\":\n                continue\n", LEITURA),
    # ---- o agente: o que escreve, e o que diz
    ("decide e nao escreve", AGENTE,
     "            self._controls.set_fan_speed(0, 0)\n", "            pass\n", LACO),
    ("escreve e nao registra", AGENTE,
     '            "GPU a %d °C; devolvida ao automático",\n            *setpoint,\n            *rpm,\n            gpu,\n        )\n',
     '            "GPU a %d °C; devolvida ao automático",\n            *setpoint,\n            *rpm,\n            gpu,\n        ) if False else None\n',
     LACO),
    ("a recusa da escrita avisa a cada passada", AGENTE,
     "            if not self._rede_recusa_avisada:\n", "            if True:\n", LACO),
    # ---- o agente: em que modo esta
    ("modo maximo pedido vale como ativo na bateria", AGENTE,
     "self._guarda_ventoinha(decisao.config.maximum_mode and now_on_ac is True)",
     "self._guarda_ventoinha(decisao.config.maximum_mode)", LACO),
    ("o agente esquece o modo maximo", AGENTE,
     "self._guarda_ventoinha(decisao.config.maximum_mode and now_on_ac is True)",
     "self._guarda_ventoinha(False)", LACO),
]

def uma(i, nome, arquivo, de, para, teste, base):
    orig = (REPO / arquivo).read_text()
    n = orig.count(de)
    if n != 1:
        return f"{i:2} ERRO     {nome}: o trecho aparece {n} vezes em {arquivo}", 1
    alvo = base / arquivo
    alvo.write_text(orig.replace(de, para))
    try:
        r = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", "-x", "-p", "no:cacheprovider", teste],
            cwd=base, capture_output=True, text=True,
        )
    finally:
        alvo.write_text(orig)
    falhas = [l.split("::")[1].split(" ")[0] for l in r.stdout.splitlines() if l.startswith("FAILED")]
    if r.returncode == 1 and falhas:
        return f"{i:2} reprovou {nome} -- {falhas[0][:70]}", 0
    return f"{i:2} PASSOU   {nome}: rc={r.returncode} -- o teste nao viu", 1


def main():
    base = pathlib.Path(tempfile.mkdtemp(prefix="mutacoes-rede."))
    ruins = 0
    try:
        shutil.copy(REPO / "pyproject.toml", base / "pyproject.toml")
        shutil.copytree(REPO / "src", base / "src", ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copytree(REPO / "tests/python", base / "tests/python",
                        ignore=shutil.ignore_patterns("__pycache__"))
        # O controle: sem mutacao nenhuma, os quatro testes passam na copia.
        r = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
             TRACOS, UNIDADE, LACO, LEITURA],
            cwd=base, capture_output=True, text=True,
        )
        if r.returncode != 0:
            print("ERRO: sem mutacao nenhuma os testes ja reprovam na copia")
            print(r.stdout[-2000:])
            return 1
        for i, m in enumerate(MUT, 1):
            linha, ruim = uma(i, *m, base)
            print(linha, flush=True)
            ruins += ruim
    finally:
        shutil.rmtree(base, ignore_errors=True)
    print(f"mutacoes que o teste nao viu, ou que nao acharam o trecho: {ruins} de {len(MUT)}")
    return 1 if ruins else 0


if __name__ == "__main__":
    sys.exit(main())
