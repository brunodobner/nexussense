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

# --- filp_open devolve ERR_PTR, nunca NULL (armadilha 15)
#
# "if (!file)" nunca dispara, e o kernel_write seguinte dereferencia o
# ponteiro de erro. Dois dos quatro locais tinham o defeito, e eram os
# dois caminhos de ESCRITA -- os que rodam no desligamento.
n_bang=$(grep -c 'if (!file)' "$S" || true)
if [ "$n_bang" -eq 0 ]; then
  echo "  OK   nenhum 'if (!file)' apos filp_open"
else
  echo "  FALHA $n_bang guarda(s) 'if (!file)': filp_open devolve ERR_PTR"; fail=1
fi

n_open=$(grep -c 'filp_open' "$S" || true)
n_iserr=$(grep -A1 'filp_open' "$S" | grep -c 'IS_ERR(file)' || true)
if [ "$n_open" -eq "$n_iserr" ]; then
  echo "  OK   os $n_open filp_open sao testados com IS_ERR"
else
  echo "  FALHA $n_open filp_open mas so $n_iserr com IS_ERR"; fail=1
fi

# --- um filp_close por funcao (armadilha 15b)
#
# O caminho de erro fechava dentro do if e de novo depois dele: dois
# filp_close sobre o mesmo struct file.
for fn in acer_predator_state_save four_zone_kb_state_save \
          acer_predator_state_load four_zone_kb_state_load; do
  n=$(awk "/^static int ${fn}\(void\)/,/^}/" "$S" | grep -c 'filp_close' || true)
  if [ "$n" -eq 1 ]; then
    echo "  OK   ${fn} fecha o arquivo uma vez"
  else
    echo "  FALHA ${fn} tem $n filp_close (esperado 1)"; fail=1
  fi
done

# --- toda chamada WMI e serializada (armadilha 24)
#
# O driver nao tinha lock nenhum: leitores concorrentes colidiam no
# firmware e o journal enchia de "Failed to get profile for handler
# acer-wmi". Sequencial nao reproduz; 8 leitores paralelos reproduzem.
if grep -q 'DEFINE_MUTEX(acer_wmi_lock)' "$S"; then
  echo "  OK   existe mutex para as chamadas WMI"
else
  echo "  FALHA sem mutex: chamadas WMI concorrentes colidem"; fail=1
fi

# Fora do proprio wrapper, ninguem pode chamar wmi_evaluate_method direto.
direto=$(grep -c '[^_]wmi_evaluate_method(' "$S" || true)
if [ "$direto" -eq 1 ]; then
  echo "  OK   so o wrapper chama wmi_evaluate_method direto"
else
  echo "  FALHA $direto chamadas diretas a wmi_evaluate_method (esperado 1)"; fail=1
fi

n_wrap=$(grep -c 'acer_wmi_evaluate_method(' "$S" || true)
if [ "$n_wrap" -ge 14 ]; then
  echo "  OK   $n_wrap usos do wrapper serializado"
else
  echo "  FALHA so $n_wrap usos do wrapper: alguem escapou"; fail=1
fi

exit $fail
