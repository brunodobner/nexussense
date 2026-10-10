#!/bin/bash
# Verifica que o layout do repositorio esta integro e que o instalador
# acha tudo que precisa copiar.
#
# Nasceu como verificacao unica da reorganizacao de 2026-09-10, que
# dissolveu original/ e moveu 36 arquivos. Ficou porque o que ela mede
# nao foi consertado de uma vez: o setup.sh precisa continuar achando
# seus alvos por RAIZ, e a raiz precisa continuar com um executavel so.
#
# A parte que NAO sobreviveu da versao original foi a comparacao contra
# o baseline ("333 pytest, 12/2/2/0 no shell"). Aqueles numeros medem uma
# migracao especifica e apodreceriam no primeiro teste novo -- e chamar
# run-all.sh daqui de dentro faria o run-all chamar a si mesmo.
#
# Contrato de saida (igual ao do resto da suite, ver run-all.sh):
#   0 passou   2 pulou por falta de dependencia   3 alvo ausente   1 falhou
set -u

# Localiza os alvos a partir da raiz do repositorio: estes testes vivem
# fora de driver/, para sobreviverem a sobrescrita da pasta na proxima
# release do upstream -- que e exatamente quando eles sao mais necessarios.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Sem isto um alvo ausente faria as asserções de ausencia passarem por
# vacuo: grep que nao acha arquivo "falha", e falha vira "padrao ausente".
exigir() { [ -e "$1" ] || { echo "ERRO alvo ausente: $1"; exit 3; }; }
exigir "$ROOT/setup.sh"
exigir "$ROOT/driver/Makefile"
exigir "$ROOT/packaging"
# cmp vem do diffutils, que uma imagem minima nao traz. Sem ele a
# comparacao das licencas lia "comando nao existe" como "as duas diferem"
# -- foi assim que o container do CI reprovou uma arvore certa.
command -v cmp > /dev/null 2>&1 || { echo "ERRO alvo ausente: cmp (pacote diffutils)"; exit 3; }

cd "$ROOT" || exit 3
fail=0
ok()    { echo "  OK    $1"; }
falha() { echo "  FALHA $1"; fail=1; }

# ─── 1. a raiz tem um executavel so ────────────────────────────────
# O criterio da reorganizacao: quem clona o repositorio ve setup.sh e
# sabe o que rodar, sem escolher entre varios scripts. Os demais sao
# metadados que a raiz exige: pyproject (o pytest e o build leem dali) e
# LICENSE, que o GitHub so reconhece na raiz -- o projeto e
# GPL-3.0-or-later e precisa dizer isso onde se procura.
# LC_ALL=C no sort: a ordem de maiusculas e minusculas e do locale, e a
# lista esperada so vale num deles. Sem cravar, o teste passava em pt_BR
# e reprovava sob LC_ALL=C -- que e como um CI roda.
raiz=$(find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')
[ "$raiz" = ".gitignore LICENSE README.md pyproject.toml setup.sh " ] \
    && ok "raiz tem so setup.sh mais README, LICENSE, pyproject e .gitignore" \
    || falha "raiz inesperada: $raiz"

# A licenca da raiz cobre o projeto; a de driver/ acompanha o codigo
# derivado. Divergirem seria pior que faltar uma.
if cmp -s LICENSE driver/LICENSE; then
    ok "LICENSE da raiz e a de driver/ sao a mesma GPLv3"
else
    falha "LICENSE da raiz difere de driver/LICENSE"
fi

# ─── 2. o layout antigo nao voltou ─────────────────────────────────
# Tres arquivos citam os caminhos antigos de PROPOSITO e ficam de fora:
#   README.md       a tabela de procedencia -- de onde veio cada arquivo
#                   do DAMX. Sao os caminhos da arvore DELE, nao da nossa.
#   docs/README.md  explica onde foi parar o historico de desenvolvimento
#   este arquivo    o padrao de busca contem as strings que ele proibe
orfaos=$(grep -rn 'original/Linuwu-Sense\|"Linuwu-Sense\|\boriginal/setup\.sh\|\$ORIG\b\|tests/test-[a-z]' \
    --include='*.sh' --include='*.py' --include='*.md' --include='*.toml' \
    --include='*.conf' --include='*.service' --include='*.desktop' --include='*.rules' \
    . --exclude-dir=.git --exclude-dir=__pycache__ \
    2>/dev/null | grep -vE '^\./(README\.md|docs/README\.md|tests/shell/test-arvore\.sh):')
[ -z "$orfaos" ] && ok "nenhuma referencia ao layout antigo" \
    || { falha "referencias orfas:"; printf '%s\n' "$orfaos" | sed 's/^/        /'; }

# ─── 3. todo caminho que o setup.sh cita existe ────────────────────
# Esta e a checagem central. O instalador deriva tudo de RAIZ; se um
# arquivo se mover sem que a referencia acompanhe, "install" falha no
# meio da instalacao, com metade do sistema ja modificado.
mapfile -t caminhos < <(grep -oE '\$\{?(RAIZ|DRIVER_DIR)\}?/[A-Za-z0-9_./-]+' setup.sh \
    | sed -e 's|${RAIZ}/||; s|$RAIZ/||; s|${DRIVER_DIR}/|driver/|; s|$DRIVER_DIR/|driver/|' \
    | sed 's|/$||' | sort -u)
if [ "${#caminhos[@]}" -lt 10 ]; then
    falha "so ${#caminhos[@]} caminhos extraidos do setup.sh; o padrao de RAIZ mudou?"
else
    falta=0
    for c in "${caminhos[@]}"; do
        [ -e "$c" ] || { falha "setup.sh cita '$c', que nao existe"; falta=1; }
    done
    [ "$falta" -eq 0 ] && ok "os ${#caminhos[@]} caminhos citados no setup.sh existem"
fi

# ─── 4. sintaxe de todo shell script ───────────────────────────────
erro=0
while IFS= read -r f; do
    bash -n "$f" 2>/dev/null || { falha "sintaxe invalida: $f"; erro=1; }
done < <(find . -name '*.sh' -not -path './.git/*')
[ "$erro" -eq 0 ] && ok "sintaxe valida em todos os .sh"

# ─── 5. links markdown internos resolvem ───────────────────────────
quebrados=0
while IFS= read -r linha; do
    arq="${linha%%:*}"; alvo="${linha#*:}"
    [ -e "$(dirname "$arq")/$alvo" ] \
        || { falha "link quebrado em $arq -> $alvo"; quebrados=1; }
done < <(grep -roE '\]\([a-zA-Z0-9_./-]+\.(md|txt|sh)\)' README.md docs/*.md 2>/dev/null \
         | sed -E 's/:\]\(/:/; s/\)$//')
[ "$quebrados" -eq 0 ] && ok "todos os links markdown internos resolvem"

# ─── 6. os artefatos que o instalador consome existem ──────────────
alvos=(
  driver/Makefile driver/dkms.conf driver/src/nexus_sense.c
  src/nexus_sense packaging/scripts/apply-perms.sh
  packaging/systemd/nexus_sense.service packaging/systemd/nexus-sense-agent.service
  packaging/desktop/nexus-sense.desktop packaging/desktop/nexus-sense-autostart.desktop
  packaging/udev/60-nexus-sense.rules
  packaging/icons/scalable/apps packaging/icons/scalable/status
)
falta=0
for a in "${alvos[@]}"; do
    [ -e "$a" ] || { falha "ausente: $a"; falta=1; }
done
[ "$falta" -eq 0 ] && ok "os ${#alvos[@]} artefatos que o instalador consome existem"

# Glob vazio nao e erro em bash: "cp icons/*x*/" com zero casamentos copia
# nada e segue calado, e o painel fica sem icone sem ninguem saber por que.
n_tam=$(find packaging/icons -maxdepth 1 -type d -name '*x*' | wc -l)
n_svg=$(find packaging/icons/scalable/status -name '*.svg' | wc -l)
[ "$n_tam" -ge 6 ] && [ "$n_svg" -ge 10 ] \
    && ok "globs de icone casam: $n_tam tamanhos, $n_svg svg de bandeja" \
    || falha "glob de icone vazio ou raso: $n_tam tamanhos, $n_svg svg"

# ─── 7. o setup.sh se acha fora do repositorio ─────────────────────
# Metade dos caminhos do instalador ja foi relativa ao diretorio
# corrente, e so funcionava com "cd original" antes. Isto prova que
# RAIZ resolve de qualquer lugar. Importar nao abre o menu: o setup.sh
# so chama main_menu quando BASH_SOURCE == $0.
COPIA=$(mktemp -d)
trap 'rm -rf "$COPIA"' EXIT
tar -cf - --exclude=.git --exclude=__pycache__ --exclude=.pytest_cache \
          --exclude=.superpowers . 2>/dev/null | tar -xf - -C "$COPIA"

ensaio=$(cd / && bash -c "set -u; source '$COPIA/setup.sh'
    echo \"RAIZ=\$RAIZ\"; echo \"VERSAO=\$(driver_version 2>&1)\"" 2>&1)

printf '%s' "$ensaio" | grep -q "RAIZ=$COPIA" \
    && ok "setup.sh resolve a raiz importado de outro diretorio" \
    || falha "setup.sh nao resolveu a raiz fora do repositorio: $ensaio"

ver=$(printf '%s' "$ensaio" | sed -n 's/^VERSAO=//p')
printf '%s' "$ver" | grep -qE '^[0-9]+\.[0-9]+' \
    && ok "driver_version le a versao do fonte: $ver" \
    || falha "driver_version falhou: $ver"

# ─── 8. o driver compila ───────────────────────────────────────────
# Sem headers do kernel em execucao nao da para afirmar nada: pula.
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo "  PULOU compilacao do driver: sem headers para $(uname -r)"
    [ "$fail" -eq 0 ] && exit 2 || exit 1
fi

saida=$(cd driver && make clean >/dev/null 2>&1; make 2>&1)
if [ -f driver/src/nexus_sense.ko ]; then
    ok "driver compila para $(uname -r)"
    (cd driver && make clean >/dev/null 2>&1)
else
    falha "o driver NAO compilou:"; printf '%s\n' "$saida" | tail -12 | sed 's/^/        /'
fi

exit $fail
