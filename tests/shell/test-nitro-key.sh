#!/bin/bash
# Verifica o remap de keycode do botao Nitro: sem ele o botao chega como
# KEY_PRESENTATION (425), cujo keysym nenhum toolkit grafico sabe vincular.
set -u

# Localiza os alvos a partir da raiz do repositorio: estes testes vivem
# fora de driver/, para sobreviverem a sobrescrita da pasta na proxima
# release do upstream -- que e exatamente quando eles sao mais necessarios.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DRV="$ROOT/driver"

# Sem isto um alvo ausente faria as asserções de ausencia passarem por
# vacuo: grep num arquivo inexistente falha, e "falhou" era lido como
# "padrao ausente". Alvo sumido tem de ser erro alto, nao aprovacao.
exigir() {
  [ -e "$1" ] || { echo "  ERRO alvo ausente: $1"; exit 3; }
}
S="$ROOT/setup.sh"
exigir "$S"
exigir "$ROOT/packaging/scripts/nitro-key-detection.sh"
fail=0

if grep -q '^install_nitro_key_hwdb() {' "$S"; then
  echo "  OK   install_nitro_key_hwdb existe"
else
  echo "  FALHA install_nitro_key_hwdb ausente"; fail=1
fi

fn=$(sed -n '/^install_nitro_key_hwdb() {/,/^}/p' "$S")

if printf '%s' "$fn" | grep -q 'KEYBOARD_KEY_f5=prog1'; then
  echo "  OK   mapeia 0xf5 para prog1 (convencao do systemd)"
else
  echo "  FALHA mapeamento errado"; fail=1
fi

# A checagem de "ja mapeado" tem de exigir prog1. O hwdb do systemd tem
# uma entrada generica Acer que mapeia 0xf5=presentation em TODO Acer,
# entao testar so a presenca de KEYBOARD_KEY_f5 faria a funcao pular em
# qualquer maquina -- um no-op disfarcado.
if printf '%s' "$fn" | grep -q 'KEYBOARD_KEY_f5=prog1.*then\|grep -q .KEYBOARD_KEY_f5=prog1'; then
  echo "  OK   so pula quando o mapeamento ja e prog1"
else
  echo "  FALHA checagem aceita qualquer KEYBOARD_KEY_f5 -- seria no-op"; fail=1
fi

if printf '%s' "$fn" | grep -q 'Nitro\*|Predator\*'; then
  echo "  OK   restrito a modelos Nitro/Predator"
else
  echo "  FALHA nao restringe por modelo"; fail=1
fi

# Estado real da maquina, quando aplicavel.
modelo=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
case "$modelo" in
  Nitro*|Predator*)
    kbd=$(grep -l 'AT Translated Set 2 keyboard' /sys/class/input/event*/device/name 2>/dev/null \
          | head -1 | sed 's|/sys/class/input/\(event[0-9]*\)/.*|/dev/input/\1|')
    if [ -n "$kbd" ] && udevadm info "$kbd" 2>/dev/null | grep -q 'KEYBOARD_KEY_f5=prog1'; then
      echo "  OK   botao mapeado para prog1 nesta maquina ($modelo)"
    else
      echo "  FALHA botao nao mapeado nesta maquina"; fail=1
    fi
    ;;
  *) echo "  PULADO nao e um Acer Nitro/Predator ($modelo)" ;;
esac

# O remap e do teclado, nao do driver: tem de rodar mesmo quando a
# instalacao pula os drivers (opcao 2 do menu), e ANTES da captura em
# configure_nitro_button -- senao ela grava o keycode pre-remap.
perform=$(sed -n '/^perform_install() {/,/^}/p' "$S")
if printf '%s' "$perform" | grep -q 'install_nitro_key_hwdb'; then
  echo "  OK   chamada de perform_install, nao de dentro de install_drivers"
else
  echo "  FALHA nao e chamada em perform_install"; fail=1
fi

if printf '%s' "$perform" | grep -B20 'configure_nitro_button' | grep -q 'install_nitro_key_hwdb'; then
  echo "  OK   roda antes de configure_nitro_button"
else
  echo "  FALHA roda depois da captura"; fail=1
fi

# O codigo de reserva nao pode ser cravado: depende do mapeamento em vigor.
for f in "$S" "$ROOT/packaging/scripts/nitro-key-detection.sh"; do
  if grep -q 'KEYBOARD_KEY_f5=prog1' "$f"; then
    echo "  OK   $(basename $f) deriva o codigo de reserva"
  else
    echo "  FALHA $(basename $f) crava o codigo de reserva"; fail=1
  fi
done

# O vinculo do atalho passou a ser feito pelo proprio instalador. Se ele
# escreve, a desinstalacao tem de remover -- senao sobra atalho vivo
# apontando para um .desktop que acabou de ser apagado, que e o problema
# do icone morto em outra forma.
if grep -q '^bind_button_to_nexus() {' "$S"; then
  echo "  OK   instalador vincula o atalho"
else
  echo "  FALHA nao vincula o atalho"; fail=1
fi

if grep -q '^unbind_button_from_nexus() {' "$S"; then
  echo "  OK   desinstalacao remove o vinculo"
else
  echo "  FALHA nao remove o vinculo"; fail=1
fi

# Nunca sobrescrever escolha do usuario, nem na instalacao nem na remocao.
bind=$(sed -n '/^bind_button_to_nexus() {/,/^}/p' "$S")
if printf '%s' "$bind" | grep -q 'already has the shortcut'; then
  echo "  OK   preserva atalho pre-existente na instalacao"
else
  echo "  FALHA sobrescreve atalho do usuario"; fail=1
fi

unbind=$(sed -n '/^unbind_button_from_nexus() {/,/^}/p' "$S")
if printf '%s' "$unbind" | grep -q 'current" = "Launch (1)'; then
  echo "  OK   so remove o valor que o proprio instalador escreve"
else
  echo "  FALHA remove qualquer valor"; fail=1
fi

# kwriteconfig6 nao tem --delete-group; apagar grupo inteiro e no-op.
# Ignorar comentarios: o proprio codigo explica por que nao usa a opcao,
# e a explicacao contem a string procurada.
if printf '%s' "$unbind" | grep -v '^\s*#' | grep -q -- '--delete-group'; then
  echo "  FALHA usa --delete-group, que nao existe no kwriteconfig6"; fail=1
else
  echo "  OK   remove chave a chave, sem --delete-group"
fi

# Reinstalacao: a regra hwdb ja esta no lugar e a funcao retorna cedo. O
# atalho mora na config do usuario e pode faltar mesmo assim, entao o
# retorno antecipado tem de vincular tambem.
hwdb=$(sed -n '/^install_nitro_key_hwdb() {/,/^}/p' "$S")
antecipado=$(printf '%s' "$hwdb" | sed -n '/already maps to prog1/,/return 0/p')
if printf '%s' "$antecipado" | grep -q 'bind_button_to_nexus'; then
  echo "  OK   retorno antecipado ainda vincula o atalho"
else
  echo "  FALHA reinstalacao pularia o vinculo do atalho"; fail=1
fi

# O prompt do servico de deteccao roda logo depois do remap. Com o botao
# ja funcionando, oferecer o servico sem contexto induz a instalar um
# processo root que le o teclado inteiro, duplicando o que ja funciona.
prompt=$(sed -n '/^configure_nitro_button() {/,/^}/p' "$S")
if printf '%s' "$prompt" | grep -q 'NITRO_KEY_BOUND'; then
  echo "  OK   prompt sabe se o botao ja esta vinculado"
else
  echo "  FALHA prompt oferece o servico sem contexto"; fail=1
fi

if printf '%s' "$prompt" | grep -q 'watches every'; then
  echo "  OK   prompt informa o custo (le todas as teclas)"
else
  echo "  FALHA prompt nao informa o custo do servico"; fail=1
fi

exit $fail
