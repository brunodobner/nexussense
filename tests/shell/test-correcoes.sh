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

# O caminho do Nitro puro criava o grupo sysfs sem nunca carregar nem
# salvar o estado -- perfil termico e curvas de ventoinha por fonte de
# energia se perdiam a cada reinicio. E o remove nem removia o grupo.
# Ambos corrigidos. Ver armadilha 4.
#
# A guarda era "NITRO_SENSE && !NITRO_SENSE_V4". A camada B da poda
# (2026-09-12) removeu NITRO_SENSE_V4 do driver, entao sobrou a metade de
# cima -- o comportamento nao mudou, so a condicao ficou mais curta.
probe=$(awk '/if \(has_cap\(ACER_CAP_NITRO_SENSE\)\)/,/^    \}/' "$S" | head -20)
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
# four_zone_kb_state_save/load estavam nesta lista ate a camada B da poda
# (2026-09-12) remover o subsistema de teclado RGB inteiro.
for fn in acer_predator_state_save acer_predator_state_load; do
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

# Aqui havia um piso de usos do wrapper -- 14, depois 12. Ele caiu duas
# vezes em duas podas, sempre por remocao legitima de codigo morto, e
# nunca pegou nada: a checagem de chamada direta acima ja garante a regra
# inteira, porque qualquer fuga aparece la como um segundo wmi_evaluate_method.
#
# No lugar dele, o que um numero nao verificava: que o wrapper realmente
# serializa. Esta checagem nao envelhece com a poda.
corpo=$(awk '/^static acpi_status acer_wmi_evaluate_method\(/,/^}/' "$S")
if printf '%s' "$corpo" | grep -q 'mutex_lock(&acer_wmi_lock)' \
   && printf '%s' "$corpo" | grep -q 'mutex_unlock(&acer_wmi_lock)'; then
  echo "  OK   o wrapper toma e devolve o acer_wmi_lock"
else
  echo "  FALHA o wrapper nao serializa: mutex ausente no corpo"; fail=1
fi

# --- as sequencias ler-modificar-escrever sao atomicas (armadilha 24)
#
# Serializar cada chamada WMI nao basta: entre ler o valor atual e
# escrever o modificado, outro escritor entra. Ha dois, em processos
# separados -- o agente e a janela/bandeja.
if grep -q 'DEFINE_MUTEX(acer_op_lock)' "$S"; then
  echo "  OK   existe mutex de operacao"
else
  echo "  FALHA sem acer_op_lock: sequencias RMW nao sao atomicas"; fail=1
fi

for fn in predator_usb_charging_store acer_predator_v4_platform_profile_set; do
  if awk "/${fn}\(/,/^}/" "$S" | grep -q 'guard(mutex)(&acer_op_lock)'; then
    echo "  OK   ${fn} e atomica"
  else
    echo "  FALHA ${fn} faz RMW sem o acer_op_lock"; fail=1
  fi
done

# A ordem e o que impede deadlock: o caminho interno NUNCA pode tomar o
# lock de operacao, senao ha ciclo.
if awk '/^static acpi_status acer_wmi_evaluate_method/,/^}/' "$S" | grep -q 'acer_op_lock'; then
  echo "  FALHA o wrapper WMI toma acer_op_lock: ciclo de lock"; fail=1
else
  echo "  OK   o wrapper WMI nao toma o lock de operacao (sem ciclo)"
fi

# --- a mensagem de erro nao dereferencia o objeto que acabou de testar
#
# "if (!obj || ...) pr_err(..., obj->buffer.length)": quando o firmware
# nao devolve objeto, e a propria mensagem que derruba o kernel. Nao ha
# como provocar no hardware -- o firmware sempre responde --, entao a
# prova e o padrao nao existir. Plano de melhorias 2026-10, tarefa 2.1.
for fn in battery_health_query battery_health_set; do
  corpo=$(awk "/^static acpi_status ${fn}\(/,/^}/" "$S")
  [ -n "$corpo" ] || { echo "  ERRO alvo ausente: ${fn}"; exit 3; }
  if printf '%s' "$corpo" | grep -q '!obj ||'; then
    echo "  FALHA ${fn} testa !obj e usa obj na mesma condicao"; fail=1
  elif printf '%s' "$corpo" | grep -q 'if (!obj)'; then
    echo "  OK   ${fn} trata obj nulo antes de ler dele"
  else
    echo "  FALHA ${fn} nao testa obj nulo"; fail=1
  fi
done

exit $fail
