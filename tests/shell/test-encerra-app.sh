#!/bin/bash
# A desinstalacao encerra o agente e a bandeja -- e este teste nao encerra
# nada de verdade.
#
# Ate 2026-10-10 a desinstalacao apagava os lancadores e o pacote debaixo de
# dois processos que seguiam rodando ate o fim da sessao. stop_nexus_sense
# os encerra: o agente pelo gerenciador do usuario, porque a unit tem
# Restart=always e um sinal so o faria voltar em 3 s; a bandeja pelo
# processo, porque ela nao tem unit fixa.
#
# Tres camadas separam o ensaio da sessao de quem o roda:
#   - /proc e /run/user sao arvores plantadas (PROC_DIR, RUN_USER_DIR);
#   - runuser, systemctl e kill sao funcoes que so anotam;
#   - os PIDs plantados ficam acima do pid_max, e as contas nao existem.
# E duas medem se alguma vazou: iscas de runuser e systemctl no PATH, e a
# lista dos processos de verdade, lida antes e depois.
#
# A fiacao -- uninstall chama stop_nexus_sense, a limpeza da reinstalacao
# nao -- esta em test-uninstall.sh (estatica) e em
# test-desinstalacao-namespace.sh (executada, num namespace).
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ_TESTE="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ_TESTE/setup.sh"
falhas=0

[ -e "$S" ] || { echo "ERRO: alvo ausente: $S"; exit 3; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# ─── iscas: quem escapar das funcoes-dublê cai aqui ─────────────────
ISCA="$T/isca"
mkdir -p "$T/bin"
for c in runuser systemctl pkill; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$c" "$ISCA" > "$T/bin/$c"
    chmod +x "$T/bin/$c"
done
: > "$ISCA"

# Os processos de verdade, antes: so leitura, num shell a parte.
de_verdade() { bash -c "source '$S'; nexus_sense_pids" 2>/dev/null | sort -n | tr '\n' ' '; }
ANTES=$(de_verdade)

PATH="$T/bin:$PATH"

# Importar nao abre o menu: o setup.sh so chama main_menu quando executado.
# shellcheck source=/dev/null
source "$S"
for f in nexus_sense_pids each_user_manager stop_nexus_sense; do
    declare -F "$f" > /dev/null || { echo "ERRO: alvo ausente: $f"; exit 3; }
done

# ─── o mundo de mentira ─────────────────────────────────────────────
REGISTRO="$T/registro"
runuser()   { echo "runuser $*" >> "$REGISTRO"; }
systemctl() { echo "systemctl $*" >> "$REGISTRO"; }
kill()      { echo "kill $*" >> "$REGISTRO"; }
id() {
    case "$*" in
        "-nu 1001") echo alice ;;
        "-nu 964")  echo sddm ;;
        *) return 1 ;;
    esac
}
for f in runuser systemctl kill id; do
    [ "$(type -t "$f")" = function ] || { echo "ERRO: o dublê de $f nao esta no lugar"; exit 3; }
done

PROC_DIR="$T/proc"
RUN_USER_DIR="$T/run"
mkdir -p "$PROC_DIR" "$RUN_USER_DIR"

# pid_max desta maquina e 4194304, o teto do kernel: um kill de verdade
# nestes numeros responderia "processo inexistente".
processo() {  # $1=pid  resto: o argv, um elemento por argumento
    local pid="$1"
    shift
    mkdir -p "$PROC_DIR/$pid"
    if [ "$#" -gt 0 ]; then printf '%s\0' "$@"; fi > "$PROC_DIR/$pid/cmdline"
}

# O formato e o medido nesta maquina em 2026-10-10, em /proc/<pid>/cmdline.
processo 9000001 /usr/bin/python3 -P -m nexus_sense
processo 9000002 /usr/bin/python3 -P -m nexus_sense.gui.app --tray-only
# O lancador de antes da etapa 3, sem o -P: a sessao pode ser mais velha
# que a ultima atualizacao.
processo 9000009 /usr/bin/python3 -m nexus_sense.gui.app

# Os que NAO sao nossos.
processo 9000003 /usr/bin/zsh -c 'eval "/usr/bin/python3 -P -m nexus_sense"'   # armadilha 10
processo 9000004 /usr/bin/python3 -P -m nexus_sense_outro
processo 9000005 /usr/bin/python3 -m pytest -k -m nexus_sense
processo 9000006 python3 -m nexus_sense                 # rodado do repositorio
processo 9000007 /usr/bin/python3 /srv/nexus_sense.py
processo 9000008                                        # thread do kernel: argv vazio
mkdir -p "$PROC_DIR/9000010"                            # saiu no meio da varredura
mkdir -p "$PROC_DIR/self" "$PROC_DIR/sys"
printf '%s\0' /usr/bin/python3 -P -m nexus_sense > "$PROC_DIR/self/cmdline"

confere() {  # $1=descricao  $2=esperado  $3=obtido
    if [ "$2" = "$3" ]; then
        echo "  OK   $1"
    else
        echo "  FALHA $1"
        echo "        esperado: $2"
        echo "        veio:     $3"
        falhas=$((falhas + 1))
    fi
}

# ─── quais processos ────────────────────────────────────────────────
obtido=$(nexus_sense_pids 2>&1 | sort -n | tr '\n' ' ')
confere "acha o agente e a bandeja pelo argv, e so eles" "9000001 9000002 9000009 " "$obtido"

# ─── em que ordem, e por quem ───────────────────────────────────────
mkdir -p "$RUN_USER_DIR/1001" "$RUN_USER_DIR/964"
mkdir -p "$RUN_USER_DIR/4242"     # diretorio sem conta
mkdir -p "$RUN_USER_DIR/lixo"     # nao e uid
: > "$REGISTRO"
stop_nexus_sense > /dev/null 2>&1
rc=$?
confere "stop_nexus_sense devolve 0" 0 "$rc"

esperado="runuser -u alice -- env XDG_RUNTIME_DIR=$RUN_USER_DIR/1001 systemctl --user stop nexus-sense-agent.service
runuser -u sddm -- env XDG_RUNTIME_DIR=$RUN_USER_DIR/964 systemctl --user stop nexus-sense-agent.service
kill -TERM 9000001
kill -TERM 9000002
kill -TERM 9000009"
confere "para a unit em cada gerenciador de usuario, e so depois sinaliza os processos" \
    "$esperado" "$(cat "$REGISTRO")"

# ─── sem ninguem logado e sem processo: nao faz nada, e nao reclama ──
rm -rf "$PROC_DIR" "$RUN_USER_DIR"
mkdir -p "$PROC_DIR" "$RUN_USER_DIR"
: > "$REGISTRO"
saida=$(stop_nexus_sense 2>&1)
rc=$?
confere "maquina vazia: nenhum comando" "" "$(cat "$REGISTRO")"
confere "maquina vazia: devolve 0" 0 "$rc"
if printf '%s' "$saida" | grep -qiE 'erro|error|no such|n[aã]o encontrad'; then
    echo "  FALHA maquina vazia: reclamou: $saida"; falhas=$((falhas + 1))
else
    echo "  OK   maquina vazia: sem reclamacao"
fi

# ─── nada vazou ─────────────────────────────────────────────────────
confere "nenhuma chamada escapou para o PATH" "" "$(cat "$ISCA")"
unset -f runuser systemctl kill id
confere "os processos de verdade seguem os mesmos: [${ANTES}]" "$ANTES" "$(de_verdade)"

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: a desinstalacao sabe encerrar o agente e a bandeja"
exit 0
