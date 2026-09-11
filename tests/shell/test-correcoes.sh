#!/bin/bash
# Verifica que os defeitos de correcao conhecidos foram corrigidos.
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
S="$DRV/src/nexus_sense.c"
exigir "$S"
fail=0

esperar_ausente() {
  local padrao="$1" descricao="$2"
  if grep -qF "$padrao" "$S"; then
    printf '  FALHA %s\n        ainda presente: %s\n' "$descricao" "$padrao"
    fail=1
  else
    printf '  OK   %s\n' "$descricao"
  fi
}

esperar_presente() {
  local padrao="$1" descricao="$2"
  if grep -qF "$padrao" "$S"; then
    printf '  OK   %s\n' "$descricao"
  else
    printf '  FALHA %s\n        esperava: %s\n' "$descricao" "$padrao"
    fail=1
  fi
}

esperar_ausente 'ACER_CAP_PREDATOR_SENSE) & ' \
  'acer_platform_remove usa && , nao & bitwise'
esperar_presente 'unsigned long supported_profiles = 0;' \
  'supported_profiles inicializado'
esperar_ausente 'gpu_fan_config2 |= 1 << (i + 1);' \
  'shift de fan_config2 (i+1) usa 1ULL'
esperar_ausente 'gpu_fan_config2 |= 1 << (i + 3);' \
  'shift de fan_config2 (i+3) usa 1ULL'

# Spec 4.3: o capable(CAP_SYS_ADMIN) da versao pessoal NAO deve ser
# portado. As funcoes de estado so sao chamadas de probe/remove, que ja
# exigem root; a checagem nao protege nada e pode fazer o state_save
# falhar em silencio no rmmod, perdendo as configuracoes salvas.
esperar_ausente 'capable(CAP_SYS_ADMIN)' \
  'capable(CAP_SYS_ADMIN) nao foi portado'

# O caminho do Nitro puro (nitro_sense sem nitro_v4) criava o grupo sysfs
# sem nunca carregar nem salvar o estado -- perfil termico e curvas de
# ventoinha por fonte de energia se perdiam a cada reinicio. E o remove
# nem removia o grupo. Ambos corrigidos.
probe=$(awk '/has_cap\(ACER_CAP_NITRO_SENSE\) && !has_cap\(ACER_CAP_NITRO_SENSE_V4\)/,/^    \}/' "$S" | head -20)
if printf '%s' "$probe" | grep -q 'acer_predator_state_load'; then
  echo "  OK   caminho nitro_sense carrega o estado no probe"
else
  echo "  FALHA caminho nitro_sense nao carrega o estado"; fail=1
fi

if grep -A4 'sysfs_remove_group(&device->dev.kobj, &nitro_sense_attr_group)' "$S" \
   | grep -q 'acer_predator_state_save'; then
  echo "  OK   caminho nitro_sense salva o estado no remove"
else
  echo "  FALHA caminho nitro_sense nao salva o estado"; fail=1
fi

exit $fail
