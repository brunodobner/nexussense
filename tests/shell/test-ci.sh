#!/bin/bash
# O CI: o que os workflows prometem, e que uma edicao perde sem ninguem ver.
#
# Nada aqui prova que o CI passa -- isso so o GitHub diz. O que este teste
# guarda sao as propriedades que, perdidas, deixam o CI VERDE e inutil:
# suite rodando como root, falha engolida, teste pulando sem cobranca,
# lista de pulos apontando para teste que nao existe mais.
#
# Saidas: 0 passou   3 alvo ausente   1 falhou
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
CI="$RAIZ/.github/workflows/ci.yml"
T="$RAIZ/tests/shell"

for alvo in "$CI" "$RAIZ/tests/run-all.sh"; do
  [ -f "$alvo" ] || { echo "ERRO alvo ausente: $alvo"; exit 3; }
done

fail=0
ok()    { echo "  OK   $1"; }
falha() { echo "  FALHA $1"; fail=1; }

# So o que executa. Os workflows explicam em comentario o que NAO fazem, e
# um grep que le comentario reprova a explicacao -- ja aconteceu duas vezes.
codigo() { grep -v '^[[:space:]]*#' "$1"; }

# --- o YAML abre. Sem o modulo yaml nao ha como afirmar: diz que pulou.
if python3 -c 'import yaml' 2>/dev/null; then
  for w in "$RAIZ"/.github/workflows/*.yml; do
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$w" 2>/dev/null \
      && ok "$(basename "$w") e YAML valido" \
      || falha "$(basename "$w") nao e YAML valido"
  done
else
  echo "  PULADO validacao do YAML: python sem o modulo yaml"
fi

# --- a cada push
codigo "$CI" | grep -qE '^  push:[[:space:]]*$' \
  && ok "ci.yml roda a cada push" \
  || falha "ci.yml nao dispara em push"

# --- as suites como usuario comum. Root atravessa permissao de arquivo:
# os testes que provam uma recusa reprovariam, e os de shell que pulam
# "por falta de root" deixariam de pular.
codigo "$CI" | grep -qE "su ci -c 'python -m pytest" \
  && ok "pytest roda como usuario comum" \
  || falha "pytest nao roda como usuario comum"

codigo "$CI" | grep -qE "su ci -c '\./tests/run-all\.sh'" \
  && ok "suite shell roda sem root" \
  || falha "suite shell nao roda sem root"

codigo "$CI" | grep -qE '^[[:space:]]+run: \./tests/run-all\.sh' \
  && ok "suite shell roda tambem como root" \
  || falha "suite shell nao roda como root"

# --- nenhuma reprovacao engolida. O unico '|| true' admitido e o do
# relatorio de info e estilo, que por desenho nao reprova.
engolidos=$(codigo "$CI" | grep -cE 'continue-on-error|\|\| *true')
do_estilo=$(codigo "$CI" | grep -cE -- '-S style .*\|\| *true')
[ "$engolidos" -eq 1 ] && [ "$do_estilo" -eq 1 ] \
  && ok "so o relatorio de estilo deixa de reprovar" \
  || falha "$engolidos passo(s) engolem falha; so o de estilo pode"

codigo "$CI" | grep -E -- 'shellcheck .*-S warning' | grep -qv '||' \
  && ok "shellcheck reprova em erro e aviso" \
  || falha "shellcheck nao reprova em aviso"

# --- a lista dos que podem pular no CI
# Um nome que nao existe mais e entrada morta; um teste que nao sabe sair
# 2 nao tem por que estar nela.
mapfile -t permitidos < <(codigo "$CI" | sed -n 's/^[[:space:]]*permitidos="\(.*\)"$/\1/p' | tr ' ' '\n' | grep .)
if [ "${#permitidos[@]}" -lt 5 ]; then
  falha "so ${#permitidos[@]} nomes extraidos da lista de pulos; o formato mudou?"
else
  ruim=0
  for t in "${permitidos[@]}"; do
    [ -f "$T/$t" ] || { falha "a lista de pulos cita $t, que nao existe"; ruim=1; continue; }
    grep -q 'exit 2' "$T/$t" || { falha "$t esta na lista de pulos e nunca sai 2"; ruim=1; }
  done
  [ "$ruim" -eq 0 ] && ok "os ${#permitidos[@]} testes da lista de pulos existem e sabem pular"
fi

codigo "$CI" | grep -q 'GITHUB_STEP_SUMMARY' \
  && ok "o que pulou vai para o resumo do job" \
  || falha "os pulos nao aparecem no resumo do job"

# --- o modulo contra os headers do Arch
M="$RAIZ/.github/workflows/modulo.yml"
[ -f "$M" ] || { echo "ERRO alvo ausente: $M"; exit 3; }

# --- nenhum passo deixa arquivo dentro do repositorio
# test-arvore.sh cobra que a raiz tenha so o que e do projeto. Na primeira
# rodada os workflows gravavam o log do build e a saida da suite na raiz
# do checkout, e a suite reprovava o proprio CI: "raiz inesperada".
sujeira=$(codigo "$CI"; codigo "$M")
sujeira=$(printf '%s\n' "$sujeira" | grep -nE '(\btee|[^2&]>>?)[[:space:]]+"?[A-Za-z.]' \
          | grep -vE '>>?[[:space:]]*/dev/null')
if [ -z "$sujeira" ]; then
  ok "os workflows so gravam em RUNNER_TEMP e no resumo do job"
else
  falha "passo gravando arquivo no diretorio do checkout:"
  printf '%s\n' "$sujeira" | sed 's/^/        /'
fi

codigo "$M" | grep -qE "^[[:space:]]+- cron: '[0-9*/, -]+'" \
  && ok "modulo.yml tem agenda" \
  || falha "modulo.yml sem agenda: so rodaria quando alguem lembrasse"

codigo "$M" | grep -qE "^[[:space:]]+- 'driver/\*\*'" \
  && ok "modulo.yml roda tambem quando o driver muda" \
  || falha "modulo.yml nao dispara em mudanca do driver"

# No container o kernel em execucao e o do hospedeiro, sem headers. Um
# make sem KVER iria atras dele e reprovaria toda semana -- armadilha 2,
# pelo lado do CI.
if codigo "$M" | grep -qE 'uname -r'; then
  falha "modulo.yml decide o alvo pelo kernel em execucao"
elif codigo "$M" | grep -E 'make -C driver' | grep -qv 'KVER='; then
  falha "ha um make em modulo.yml sem KVER"
else
  ok "todo make de modulo.yml leva o kernel-alvo em KVER"
fi

# Sem dkms ou sem root o test-dkms.sh pula, a suite fica verde e o job
# nao teria conferido o caminho que o pacman percorre.
codigo "$M" | grep -q "PASSOU \*test-dkms.sh" \
  && ok "modulo.yml cobra que test-dkms.sh rodou de verdade" \
  || falha "modulo.yml aceita test-dkms.sh pulado"

codigo "$M" | grep -cE 'continue-on-error' | grep -qx 0 \
  && ok "nenhuma falha engolida em modulo.yml" \
  || falha "modulo.yml engole falha"

exit $fail
