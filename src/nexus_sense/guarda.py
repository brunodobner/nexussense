"""O lado do agente no guarda da ventoinha -- docs/plano-curva.md, secao 8.

A curva propria pode deixar a ventoinha abaixo do automatico, e a rede que a
protege (fan_guard.py) mora no mesmo processo que a escreve. Se o agente
morrer ou travar, ninguem a sobe. Quem cobre isso e a unit, por duas camadas
do systemd, e este modulo e a parte delas que cabe ao agente:

- avisar que esta vivo, pelo $NOTIFY_SOCKET: READY=1 ao subir e WATCHDOG=1 a
  cada passada. O agente travado para de avisar, o WatchdogSec o mata, e o
  ExecStopPost (packaging/scripts/guarda-ventoinha.sh) devolve a ventoinha;
- registrar, ANTES de escrever, o manual que o agente vai por em fan_speed,
  em $RUNTIME_DIRECTORY/ventoinha. O ExecStopPost so devolve o que achar ali:
  um manual escolhido na janela nao e do agente, e fica como esta.

O registro leva o valor de antes e o novo, como o ensaio termico faz com o
vigia: um kill -9 entre as duas linhas -- registro gravado, escrita nao --
deixaria em fan_speed o valor de antes, e ele tambem e do agente.

Sem dependencia nova: o protocolo do sd_notify e uma linha num socket de
datagrama. Fora da unit -- num terminal, nos testes -- nao ha socket nem
diretorio, e as duas coisas nao fazem nada.
"""

import os
import socket

ARQUIVO = "ventoinha"
# O RuntimeDirectory= da unit. Numa unit de usuario ele mora em
# $XDG_RUNTIME_DIR, e o systemd o apaga quando ela para.
PASTA = "nexus-sense"


def notifica(mensagem, ambiente=None):
    """Manda uma linha ao systemd. False se nao ha a quem mandar, ou se o
    envio falhou: quem chama decide se isso merece aviso."""
    ambiente = os.environ if ambiente is None else ambiente
    endereco = ambiente.get("NOTIFY_SOCKET")
    if not endereco:
        return False
    # O "@" na frente e o namespace abstrato do Linux, que o socket escreve
    # com um byte zero.
    if endereco.startswith("@"):
        endereco = "\0" + endereco[1:]
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM | socket.SOCK_CLOEXEC) as s:
            s.connect(endereco)
            s.sendall(mensagem.encode())
    except OSError:
        return False
    return True


def caminho_do_registro(ambiente=None):
    """Onde o registro mora, ou None fora da unit."""
    ambiente = os.environ if ambiente is None else ambiente
    pasta = ambiente.get("RUNTIME_DIRECTORY")
    if not pasta:
        return None
    # O systemd passa varias, separadas por ":", quando a unit pede varias.
    return os.path.join(pasta.split(":")[0], ARQUIVO)


def registra(anterior, novo, ambiente=None):
    """Grava os dois valores, um por linha, antes de o agente escrever o
    novo. A troca e atomica: o guarda nunca le o arquivo pela metade.

    False fora da unit ou se a gravacao falhou. Com False, quem chama nao
    escreve um manual baixo: sem registro, o guarda nao o devolveria.
    """
    caminho = caminho_do_registro(ambiente)
    if caminho is None:
        return False
    temporario = caminho + ".novo"
    try:
        with open(temporario, "w") as arquivo:
            arquivo.write(f"{anterior}\n{novo}\n")
        os.replace(temporario, caminho)
    except OSError:
        return False
    return True


def caminho_na_sessao(ambiente=None):
    """Onde o registro mora visto de fora da unit -- da janela. None sem
    XDG_RUNTIME_DIR."""
    ambiente = os.environ if ambiente is None else ambiente
    base = ambiente.get("XDG_RUNTIME_DIR")
    if not base:
        return None
    return os.path.join(base, PASTA, ARQUIVO)


def agente_no_ar(ambiente=None):
    """Se a unit do agente esta rodando: a pasta dela so existe enquanto
    ela roda."""
    caminho = caminho_na_sessao(ambiente)
    return caminho is not None and os.path.isdir(os.path.dirname(caminho))


def registrado(caminho):
    """O manual que o agente registrou por ultimo, como "cpu,gpu". None
    sem registro."""
    if caminho is None:
        return None
    try:
        with open(caminho) as arquivo:
            linhas = arquivo.read().splitlines()
    except OSError:
        return None
    return linhas[1] if len(linhas) >= 2 else None


def esquece(ambiente=None):
    """A janela vai escrever um manual: o que estiver em fan_speed deixa de
    ser do agente. Sem isto, Manual sem mexer nos cursores escreve o mesmo
    par que a curva escreveu, e ela, que so compara o par, seguiria mandando.
    Sem o registro a curva cede, e o guarda deixa o manual como esta."""
    caminho = caminho_na_sessao(ambiente)
    if caminho is None:
        return
    try:
        os.unlink(caminho)
    except OSError:
        pass
