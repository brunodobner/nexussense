#!/bin/bash
# Verifica o remap de keycode do botao Nitro: sem ele o botao chega como
# KEY_PRESENTATION (425), cujo keysym nenhum toolkit grafico sabe vincular.
set -u

# Localiza os alvos a partir da raiz do repositorio: estes testes vivem
# fora de driver/, para sobreviverem a sobrescrita da pasta na proxima
# release do upstream -- que e exatamente quando eles sao mais necessarios.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Sem isto um alvo ausente faria as asserções de ausencia passarem por
# vacuo: grep num arquivo inexistente falha, e "falhou" era lido como
# "padrao ausente". Alvo sumido tem de ser erro alto, nao aprovacao.
exigir() {
  [ -e "$1" ] || { echo "  ERRO alvo ausente: $1"; exit 3; }
}
S="$ROOT/setup.sh"
exigir "$S"
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
# instalacao pula os drivers (opcao 2 do menu).
perform=$(sed -n '/^perform_install() {/,/^}/p' "$S")
if printf '%s' "$perform" | grep -q 'install_nitro_key_hwdb'; then
  echo "  OK   chamada de perform_install, nao de dentro de install_drivers"
else
  echo "  FALHA nao e chamada em perform_install"; fail=1
fi

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

# O atalho da linhagem antiga. O instalador do DAMX escrevia o mesmo valor
# sob [services][damx.desktop], e a renomeacao nao o levou: achado no portao
# de 2026-10-09, vivo e apontando para um .desktop que nao existe mais.
if printf '%s' "$unbind" | grep -v '^\s*#' | grep -q 'damx\.desktop'; then
  echo "  OK   remove tambem o atalho morto do damx.desktop"
else
  echo "  FALHA deixa o atalho do damx.desktop para tras"; fail=1
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

# O servico root de deteccao de tecla saiu (plano-melhorias.md, D4). Ele
# rodava como root e lia todas as teclas do teclado, senhas inclusive, para
# fazer o que o remap acima mais um atalho do desktop ja fazem sem processo
# nenhum. Nesta maquina nunca chegou a ser instalado.
#
# As asserções abaixo sao de ausencia; o exigir no topo garante que o
# setup.sh existe, senao passariam por vacuo (armadilha 14).
codigo=$(grep -v '^\s*#' "$S")

for fn in configure_nitro_button install_nitro_service; do
  if printf '%s' "$codigo" | grep -q "$fn"; then
    echo "  FALHA $fn ainda existe ou ainda e chamada"; fail=1
  else
    echo "  OK   $fn saiu"
  fi
done

if [ -e "$ROOT/packaging/scripts/nitro-key-detection.sh" ]; then
  echo "  FALHA packaging/scripts/nitro-key-detection.sh ainda existe"; fail=1
else
  echo "  OK   o script do servico saiu do repositorio"
fi

# evtest so servia a captura e ao servico.
if printf '%s' "$codigo" | grep -q 'evtest'; then
  echo "  FALHA o instalador ainda usa ou instala evtest"; fail=1
else
  echo "  OK   o instalador nao instala evtest"
fi

# NITRO_KEY_BOUND so existia para o prompt do servico.
if printf '%s' "$codigo" | grep -q 'NITRO_KEY_BOUND'; then
  echo "  FALHA NITRO_KEY_BOUND ficou sem leitor"; fail=1
else
  echo "  OK   NITRO_KEY_BOUND saiu junto com o prompt"
fi

# A limpeza do servico ANTIGO fica: quem instalou uma versao anterior e
# respondeu "y" ao prompt tem a unit habilitada, o script em
# /usr/local/bin e /etc/damx -- e so a desinstalacao os tira de la.
limpeza=$(sed -n '/^cleanup_nitro_service() {/,/^}/p' "$S")
for alvo in 'nitro-key-detection.service' '/usr/local/bin/nitro-key-detection.sh' \
            '/etc/damx/nitro_key.conf'; do
  if printf '%s' "$limpeza" | grep -qF "$alvo"; then
    echo "  OK   a limpeza ainda remove $alvo"
  else
    echo "  FALHA a limpeza deixou de remover $alvo"; fail=1
  fi
done

cleanup=$(sed -n '/^comprehensive_cleanup() {/,/^}/p' "$S")
if printf '%s' "$cleanup" | grep -qE '^\s*cleanup_nitro_service\s*$'; then
  echo "  OK   comprehensive_cleanup chama cleanup_nitro_service"
else
  echo "  FALHA comprehensive_cleanup nao limpa o servico antigo"; fail=1
fi

exit $fail
