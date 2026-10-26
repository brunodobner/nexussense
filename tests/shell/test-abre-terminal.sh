#!/bin/bash
# Clicado no gerenciador de arquivos, o setup.sh tem de abrir uma janela.
#
# O Dolphin roda o script sem terminal: entrada em /dev/null, saida no
# journal. Ate 2026-10-26 o check_root fazia "exec sudo" ali mesmo, o sudo
# nao tinha onde pedir a senha, e o clique terminava sem nada na tela. Agora
# o script se reabre num emulador de terminal -- e so quando nao ha
# terminal nenhum e ha uma sessao grafica para abri-lo.
#
# O ensaio roda o setup.sh de verdade, com um PATH que so tem emuladores
# falsos: cada um anota como foi chamado e sai. Sem sudo nem systemctl no
# PATH, o caminho que nao reabre termina num erro, sem tocar na maquina.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ_TESTE="$(cd "$(dirname "$0")/../.." && pwd)"
S="$RAIZ_TESTE/setup.sh"
falhas=0

[ -e "$S" ] || { echo "ERRO: alvo ausente: $S"; exit 3; }
grep -q '^abrir_em_terminal()' "$S" || {
    echo "ERRO: alvo ausente: abrir_em_terminal"; exit 3; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Monta um PATH com dirname e basename de verdade e os falsos pedidos.
# Cada falso grava o proprio nome e os argumentos, um por linha.
monta_path() {
    rm -rf "${TMP:?}/bin" "${TMP:?}/registro"
    mkdir -p "$TMP/bin"
    ln -s "$(command -v dirname)" "$TMP/bin/dirname"
    ln -s "$(command -v basename)" "$TMP/bin/basename"
    local f
    for f in "$@"; do
        # shellcheck disable=SC2016  # o falso expande, nao o teste
        printf '#!/bin/bash\nprintf "%%s\\n" "${0##*/}" "$@" >> "%s"\n' \
            "$TMP/registro" > "$TMP/bin/$f"
        chmod +x "$TMP/bin/$f"
    done
}

# $1=descricao  $2=esperado  $3=falsos (separados por espaco)
# resto: VAR=valor do ambiente. O setup.sh roda sem terminal.
caso() {
    local desc="$1" esperado="$2" falsos="$3" obtido
    shift 3
    # shellcheck disable=SC2086
    monta_path $falsos
    env -i PATH="$TMP/bin" "$@" /bin/bash "$S" um "dois tres" \
        < /dev/null > "$TMP/saida" 2>&1
    obtido=$(cat "$TMP/registro" 2>/dev/null)
    if [ "$obtido" = "$esperado" ]; then
        echo "  OK   $desc"
    else
        echo "  FALHA $desc"
        echo "        esperado: $(printf '%s' "$esperado" | tr '\n' ' ')"
        echo "        veio:     $(printf '%s' "$obtido" | tr '\n' ' ')"
        falhas=$((falhas + 1))
    fi
}

relancado() {  # $1=emulador  resto: argumentos dele antes do comando
    printf '%s\n' "$@" env NEXUS_SENSE_JANELA=1 /bin/bash "$S" um "dois tres"
}

echo "--- reabre no emulador, com o comando separado do jeito de cada um ---"
caso "konsole, sob Wayland" "$(relancado konsole -e)" \
     "konsole" WAYLAND_DISPLAY=wayland-9
caso "gnome-terminal, sob X11" "$(relancado gnome-terminal --)" \
     "gnome-terminal" DISPLAY=:9
caso "xfce4-terminal" "$(relancado xfce4-terminal -x)" \
     "xfce4-terminal" DISPLAY=:9
caso "kitty, sem separador" "$(relancado kitty)" \
     "kitty" DISPLAY=:9
caso "xterm" "$(relancado xterm -e)" \
     "xterm" DISPLAY=:9
caso "xdg-terminal-exec antes do konsole" "$(relancado xdg-terminal-exec)" \
     "konsole xdg-terminal-exec" WAYLAND_DISPLAY=wayland-9

echo "--- chamado por caminho relativo, reabre pelo absoluto ---"
monta_path konsole
( cd "$RAIZ_TESTE" && env -i PATH="$TMP/bin" WAYLAND_DISPLAY=wayland-9 \
      /bin/bash ./setup.sh < /dev/null > "$TMP/saida" 2>&1 )
if [ "$(sed -n 6p "$TMP/registro" 2>/dev/null)" = "$S" ]; then
    echo "  OK   ./setup.sh vira $S"
else
    echo "  FALHA caminho relativo: veio '$(sed -n 6p "$TMP/registro" 2>/dev/null)'"
    falhas=$((falhas + 1))
fi

echo "--- nao reabre ---"
caso "sem sessao grafica" "" "konsole"
caso "ja reaberto uma vez" "" "konsole" \
     WAYLAND_DISPLAY=wayland-9 NEXUS_SENSE_JANELA=1

echo "--- sessao grafica sem emulador: avisa, e na tela ---"
caso "notify-send recebe o aviso" \
     "$(printf '%s\n' notify-send "Nexus Sense" \
        "nenhum terminal encontrado. Rode num terminal: sudo $S")" \
     "notify-send" WAYLAND_DISPLAY=wayland-9
if grep -q "nenhum terminal encontrado" "$TMP/saida"; then
    echo "  OK   o aviso sai tambem no stderr"
else
    echo "  FALHA o aviso nao saiu no stderr"
    falhas=$((falhas + 1))
fi

# Na janela reaberta, o sudo que falha pausa antes de o script sair: senao
# a janela fecha com o erro. Como root o check_root nao chama o sudo.
echo "--- na janela reaberta, o erro do sudo fica na tela ---"
if [ "$EUID" -eq 0 ]; then
    echo "  PULOU como root, o check_root nao chama o sudo"
else
    cat > "$TMP/sudo-falso" << 'EOL'
#!/bin/bash
echo "sudo falso: 3 tentativas incorretas de senha"
exit 1
EOL
    chmod +x "$TMP/sudo-falso"
    for janela in 1 ""; do
        monta_path
        ln -s "$TMP/sudo-falso" "$TMP/bin/sudo"
        env -i PATH="$TMP/bin" NEXUS_SENSE_JANELA="$janela" /bin/bash "$S" \
            < /dev/null > "$TMP/saida" 2>&1
        st=$?
        if grep -q "Press any key" "$TMP/saida"; then pausou=sim; else pausou=nao; fi
        if [ -n "$janela" ]; then esperado=sim; else esperado=nao; fi
        if [ "$pausou" = "$esperado" ] && [ "$st" -eq 1 ]; then
            echo "  OK   NEXUS_SENSE_JANELA='$janela': pausou=$pausou, saida=$st"
        else
            echo "  FALHA NEXUS_SENSE_JANELA='$janela': pausou=$pausou" \
                 "(esperado $esperado), saida=$st"
            falhas=$((falhas + 1))
        fi
    done
fi

# Dentro de um terminal o menu abre ali mesmo. O script(1) da um pty ao
# setup.sh; o pause espera tecla, e o timeout encerra a espera.
echo "--- com terminal, nao reabre ---"
if command -v script > /dev/null && command -v timeout > /dev/null; then
    monta_path konsole
    timeout 5 script -qec "env -i PATH='$TMP/bin' WAYLAND_DISPLAY=wayland-9 \
        /bin/bash '$S'" /dev/null < /dev/null > /dev/null 2>&1
    if [ -e "$TMP/registro" ]; then
        echo "  FALHA reabriu com terminal: $(tr '\n' ' ' < "$TMP/registro")"
        falhas=$((falhas + 1))
    else
        echo "  OK   com pty, o konsole nao foi chamado"
    fi
else
    echo "  PULOU sem script(1) ou timeout(1)"
fi

echo
if [ "$falhas" -eq 0 ]; then
    echo "PASSOU"
    exit 0
fi
echo "FALHOU: $falhas"
exit 1
