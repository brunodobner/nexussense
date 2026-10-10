#!/bin/bash
# Verifica que o Makefile escolhe o toolchain pelo kernel-ALVO,
# nao pelo kernel em execucao.
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
exigir "$DRV/Makefile"
cd "$DRV" || exit 3
fail=0

check() {
  local kver="$1" esperado="$2" extra="${3:-}"
  local saida
  saida=$(make -s toolchain-info KVER="$kver" $extra 2>&1)
  if printf '%s' "$saida" | grep -q "TOOLCHAIN=$esperado"; then
    printf '  OK   %-34s %-6s %s\n' "$kver" "$esperado" "$extra"
  else
    printf '  FALHA %-34s esperava %-6s obteve: %s\n' "$kver" "$esperado" "$saida"
    fail=1
  fi
}

# =====================================================================
# 1. Os dois ramos, com kernels SINTETICOS (determinístico)
# =====================================================================
# O Makefile le a config do kernel-alvo assim:
#
#     grep -sh CONFIG_CC_IS_CLANG=y $(KDIR)/.config /boot/config-$(KVER)
#
# O `-s` faz o primeiro caminho inexistente ser ignorado, entao basta
# plantar /boot/config-<sentinela> para exercitar a deteccao sem que o
# kernel exista. Isso prova OS DOIS ramos numa maquina que so tem kernels
# de um tipo -- que e o caso sempre que alguem so usa CachyOS (Clang) ou
# so Arch (GCC).
#
# Por que isto importa: antes, a cobertura do ramo GCC dependia de haver
# por acaso um kernel GCC instalado. Num parque so-Clang, um Makefile que
# respondesse "LLVM" a tudo passaria no teste. A cobertura ficava refem
# do que o gerenciador de pacotes fez naquela semana. Ver armadilha 22.
CLANG_FAKE="0.0.0-toolchain-sintetico-clang"
GCC_FAKE="0.0.0-toolchain-sintetico-gcc"
sinteticos=()

limpar_sinteticos() {
  local f
  for f in "${sinteticos[@]:-}"; do
    [ -n "$f" ] && rm -f "$f"
  done
}
trap limpar_sinteticos EXIT

if [ "$(id -u)" -eq 0 ] && [ -d /boot ] && [ -w /boot ]; then
  # Nunca sobrescrever arquivo de verdade: o sentinela nao deve existir.
  if [ -e "/boot/config-$CLANG_FAKE" ] || [ -e "/boot/config-$GCC_FAKE" ]; then
    echo "  ERRO alvo ausente: /boot/config-<sentinela> ja existe; abortando para nao sobrescrever"
    exit 3
  fi

  printf 'CONFIG_CC_IS_CLANG=y\n' > "/boot/config-$CLANG_FAKE"
  sinteticos+=("/boot/config-$CLANG_FAKE")
  printf 'CONFIG_CC_IS_GCC=y\n'   > "/boot/config-$GCC_FAKE"
  sinteticos+=("/boot/config-$GCC_FAKE")

  echo "Deteccao por kernel-alvo, ramos sinteticos (cobertura completa):"
  check "$CLANG_FAKE" LLVM
  check "$GCC_FAKE"   GCC

  # A prova de que a deteccao olha o ALVO e nao o kernel em execucao:
  # o sentinela do tipo OPOSTO ao corrente tem de vencer.
  corrente_clang=no
  grep -qs 'CONFIG_CC_IS_CLANG=y' "/lib/modules/$(uname -r)/build/.config" \
        "/boot/config-$(uname -r)" && corrente_clang=sim
  if [ "$corrente_clang" = sim ]; then
    echo "  (kernel corrente e Clang; o ramo GCC acima prova que o alvo vence)"
  else
    echo "  (kernel corrente e GCC; o ramo LLVM acima prova que o alvo vence)"
  fi
else
  echo "Ramos sinteticos: PULADOS (precisa de root para escrever em /boot)"
  echo "  sem eles a cobertura depende dos kernels instalados; ver abaixo"
fi

# =====================================================================
# 2. Os kernels reais da maquina (nunca uma lista escrita aqui)
# =====================================================================
# Ate 2026-09-10 este teste cravava 7.2.2-arch1-1 e 7.2.2-1-cachyos. Num
# Arch/CachyOS o kernel sobe de versao toda semana: os dois sumiram do
# disco, o KDIR passou a apontar para nada, a deteccao caiu no fallback e
# o teste reportou GCC onde esperava LLVM. Ficou vermelho por semanas
# acusando a si mesmo. Ver armadilha 22.
mapfile -t KERNELS < <(
  for build in /lib/modules/*/build; do
    [ -d "$build" ] || continue
    k=$(basename "$(dirname "$build")")
    [ -r "$build/.config" ] || [ -r "/boot/config-$k" ] || continue
    printf '%s\n' "$k"
  done | sort
)

# Zero kernels nao e "tudo certo" -- mas tambem nao e alvo ausente: o alvo
# e o Makefile, e os kernels sao da maquina. Num container nao ha nenhum.
# Se os ramos sinteticos rodaram, os dois lados da deteccao ja estao
# provados e o teste segue. Sem root E sem kernel, a deteccao por alvo nao
# foi exercitada: o teste roda o que nao depende da maquina e sai 2, que o
# run-all mostra como PULOU. Nunca 0 -- ver armadilhas 14 e 22.
sem_cobertura=0
if [ "${#KERNELS[@]}" -eq 0 ]; then
  if [ -n "${sinteticos[1]:-}" ]; then
    echo "  NOTA nenhum kernel real com headers nesta maquina: valem os ramos sinteticos"
  else
    sem_cobertura=1
  fi
fi

# Expectativa lida do kernel-ALVO, independente do Makefile. Nao e
# circular: o defeito que o teste pega (armadilha 2) e o Makefile decidir
# pelo kernel em EXECUCAO; se ele voltar a isso, todo alvo de tipo
# diferente do corrente diverge desta leitura e o teste acusa.
toolchain_esperado() {
  if grep -qs 'CONFIG_CC_IS_CLANG=y' "/lib/modules/$1/build/.config" "/boot/config-$1"; then
    printf 'LLVM'
  else
    printf 'GCC'
  fi
}

[ "${#KERNELS[@]}" -gt 0 ] && echo "Kernels reais desta maquina (${#KERNELS[@]}):"
gcc_kernel=""
for k in ${KERNELS[@]+"${KERNELS[@]}"}; do
  esperado=$(toolchain_esperado "$k")
  check "$k" "$esperado"
  [ "$esperado" = GCC ] && [ -z "$gcc_kernel" ] && gcc_kernel="$k"
done

echo "Override externo (o DKMS passa LLVM=1 por conta propria):"
# Vale em qualquer kernel, mas so num GCC o override aparece vencendo a
# deteccao; num Clang o resultado seria LLVM de qualquer jeito. Com root,
# o sentinela GCC garante esse caso mesmo num parque so-Clang.
if [ -n "${sinteticos[1]:-}" ]; then
  check "$GCC_FAKE" LLVM "LLVM=1"
else
  # Sem kernel real, um KVER que nao existe: a deteccao nao acha config
  # nenhuma e cai em GCC, que e onde o override aparece vencendo.
  check "${gcc_kernel:-${KERNELS[0]:-0.0.0-kver-que-nao-existe}}" LLVM "LLVM=1"
fi

echo "KERNELRELEASE tem precedencia sobre KVER (modo DKMS):"
# O KVER aqui e um sentinela deliberadamente inexistente: toolchain-info
# so ecoa as variaveis, nao abre o KDIR, e o que se mede e qual das duas
# vence. Um kernel real no lugar tornaria o teste refem de haver dois
# instalados ao mesmo tempo.
alvo_dkms="${KERNELS[0]:-0.0.0-kernelrelease-sintetico}"
saida=$(make -s toolchain-info KVER="0.0.0-kver-que-nao-existe" \
                               KERNELRELEASE="$alvo_dkms" 2>&1)
if printf '%s' "$saida" | grep -q "KVER=${alvo_dkms} "; then
  echo "  OK   KERNELRELEASE vence"
else
  echo "  FALHA KERNELRELEASE ignorado: $saida"
  fail=1
fi

if [ "$sem_cobertura" -eq 1 ]; then
  echo "  PULOU deteccao por kernel-alvo: sem root para os ramos sinteticos e sem kernel com headers"
  [ "$fail" -eq 0 ] && exit 2 || exit 1
fi

exit $fail
