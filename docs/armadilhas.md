# Armadilhas deste projeto

Lições que custaram tempo em 2026-09-04, para não custarem de novo. Cada uma
traz o sintoma que você veria, a causa e como verificar em vez de supor.

---

## 1. Falha de um dígito: o ANV15-52 não é o -51

`DMI_MATCH` compara por **substring**. `"Nitro ANV15-51"` não é substring de
`"Nitro ANV15-52"`, então um modelo sem entrada própria não casa com nada.

Isso apareceu em **duas camadas independentes**, e a segunda só foi
descoberta horas depois da primeira:

| camada | arquivo | sintoma |
|---|---|---|
| driver | `acer_quirks[]` em `linuwu_sense.c` | `quirk_unknown`, nenhum grupo sysfs criado, painel sem dados |
| systemd | `/usr/lib/udev/hwdb.d/60-keyboard.hwdb` | botão N chega como `KEY_PRESENTATION`, KDE não consegue vincular |

**Ao portar para um modelo novo, procure o modelo em toda parte, não só no
driver:**

```bash
grep -rn "ANV15\|AN515\|PHN16" /usr/lib/udev/hwdb.d/ driver/src/
```

---

## 2. Toolchain se decide por kernel-alvo, nunca pelo kernel em execução

Numa máquina com kernels Clang (CachyOS) e GCC (Arch) instalados lado a
lado, decidir o compilador pelo kernel corrente quebra o build do outro:

```
gcc: error: unrecognized command-line option '-mstack-alignment=8'
```

O `setup.sh` do upstream faz exatamente isso (`is_llvm_kernel` olha só
`uname -r` e exporta `LLVM=1` global). Sob DKMS, que compila para todos os
kernels, é falha garantida.

O Makefile lê `CONFIG_CC_IS_CLANG` do `.config` **do kernel alvo**, com
fallback em `/boot/config-$(KVER)`.

**`KERNELRELEASE` precisa de `override`.** Ele chega pela linha de comando
do `make`, e atribuição comum não vence variável de linha de comando. Sem
`override`, um `KVER` solto redireciona o build para outro kernel em
silêncio, gerando `.ko` com `vermagic` errado.

Verificação: `./tests/shell/test-toolchain.sh`

---

## 3. Valores do firmware são campos, não enums

O padrão que mais rendeu bug. O driver comparava respostas WMI contra listas
de constantes inteiras, cobrindo só as combinações que alguém já tinha
visto. Qualquer outra caía em `-1`.

**`usb_charging`** — defeito observado, com perda de dados:

```
0x [1E] [1F] [04]
    │    │    └─ id da função (só na escrita)
    │    └────── bit 0x10 = desligado
    └─────────── limiar em decimal: 0A=10%, 14=20%, 1E=30%
```

Seis combinações válidas, quatro enumeradas. E o `store()` cravava o limiar
`0x0A` ao desligar, então a cadeia completa era:

```
driver devolve -1  →  GUI não sabe exibir, escreve 0  →  store zera o limiar
```

Capturado no journal desta máquina: `1974016` (desligado, 30%) virou `663296`
(desligado, 10%) em um segundo, ao abrir o painel.

**Regra:** ao escrever num atributo destes, **parta do valor atual lido** e
modifique só os bits que mudam. Isso preserva campos que o driver ainda não
interpreta.

### 3b. `0xFF` num campo significa "não implementado"

`backlight_timeout` e `lcd_override` tinham o mesmo padrão. Endureci os dois
por inferência estrutural — e **a amostra real refutou minha inferência**.

O ANV15-52 devolve `0x00FF000001000000` para `lcd_override`. O campo de
estado (bits 48-55) vale `0xFF`, o sentinela clássico de *função não
implementada*. Minha primeira correção testava só o bit 48, que está dentro
do `0xFF`, então reportaria **"ligado"** para um recurso que o hardware não
tem — pior que o `-1` original, porque mente em vez de admitir
desconhecimento.

**Regra:** ao decodificar campo de firmware, trate `0xFF` (e o all-ones do
tamanho do campo) como "não suportado" e devolva `-1`. E **não endureça
decodificação sem uma amostra real** — procure o valor cru no journal antes:

```bash
for b in 0 -1 -2 -3 -4 -5; do
  journalctl -k -b $b --no-pager 2>/dev/null | grep -o '<atributo> get status: [0-9]*' | tail -1
done
```

Foi assim que o valor apareceu: o atributo esteve exposto enquanto o quirk
era `nitro_v4`, e o `pr_info` do driver registrou tudo.

---

## 4. Escolher o quirk muda mais do que os atributos visíveis

`quirk_acer_nitro` e `quirk_acer_nitro_v4` criam diretórios de **mesmo nome**
(`nitro_sense`), então o daemon não os distingue — ele só testa a existência
de `predator_sense/` e `nitro_sense/`, e monta o painel por
`os.path.exists()` arquivo a arquivo.

A diferença visível são dois atributos. Mas `nitro_v4` também seta
`ACER_CAP_PREDATOR_SENSE`, e **é essa capability que liga
`acer_predator_state_load/save()`**. Trocar para `quirk_acer_nitro` remove
dois controles fantasmas e leva junto, sem avisar, a persistência de perfil
térmico e curvas de ventoinha entre reinícios.

Corrigido na origem: o caminho Nitro puro agora carrega e salva estado (e
remove o grupo sysfs, que também vazava).

**Ao mexer em quirk, verifique o que a capability habilita, não só o que ela
exibe.**

---

## 5. `strncpy` não existe mais no kernel

Em `include/linux/string.h` ela só aparece em comentários de "substituída
por". GCC 16 e clang recentes tratam a chamada implícita como **erro fatal**.
`#include <linux/string.h>` não resolve — não há o que declarar.

Use `memcpy` com guarda de tamanho:

```c
size_t len = min(count, sizeof(buf_local) - 1);
if (!len)
    return -EINVAL;      /* escrita de zero bytes faria buf[len-1] ler fora */
memcpy(buf_local, buf, len);
```

---

## 6. `dkms status` sai com 0 mesmo para pacote inexistente

Teste a **palavra** `installed` na saída, nunca o código de retorno.

E o estado do DKMS vive em `/var/lib/dkms`, não em `/usr/src`. Apagar só
`/usr/src` deixa registro órfão e o `dkms add` seguinte falha.

`CLEAN` e `REMAKE_INITRD` são deprecados no DKMS 3.x. E `KERNELRELEASE` no
`MAKE` é redundante: o `dkms` injeta sozinho (`/usr/sbin/dkms:1603`).

---

## 7. Nunca crave a versão em script de instalação

O instalador da versão pessoal repetia `25.701` em oito lugares. Na primeira
release em que o upstream subisse a versão, ele passaria a operar
silenciosamente no pacote errado.

Derive do fonte:

```bash
grep -oP '#define DRIVER_VERSION "\K[^"]+' driver/src/nexus_sense.c
```

---

## 8. Desinstalar é mais amplo do que parece

Seis lugares deixavam rastro. A varredura que encontra tudo:

```bash
for d in /etc /usr/local /usr/share /var/lib /opt /usr/src; do
  find "$d" -maxdepth 4 \( -iname '*damx*' -o -iname '*linuwu*' -o -iname '*divacer*' \) 2>/dev/null
done
systemctl list-unit-files | grep -iE 'damx|linuwu|nitro'
grep -i damx ~/.config/kglobalshortcutsrc
```

Cuidado com **instaladores de outra linhagem**: o pessoal criava
`damx-gui.desktop` apontando para `/usr/local/bin/damx-gui`, nome que o
`setup.sh` não conhecia. Sobrevivia como ícone morto no menu.

Depois de remover `.desktop`, chame `update-desktop-database` — senão o menu
continua exibindo o que já saiu do disco.

**Config de sessão do KDE:** o instalador escreve o atalho da tecla N em
`~/.config/kglobalshortcutsrc` (via `runuser` + `kwriteconfig6`, como o
usuário do desktop), e por isso a desinstalação **tem** de removê-lo — senão
sobra atalho vivo apontando para o `.desktop` recém-apagado, que é o problema
do ícone morto em outra forma.

Regra dos dois lados: **nunca sobrescrever escolha do usuário.** Na
instalação, se já existe vínculo, preserva. Na remoção, só apaga se o valor
for exatamente o que o instalador escreve (`Launch (1)`).

`kwriteconfig6` **não tem `--delete-group`** — só `--key ... --delete`. Usar
a opção inexistente falha em silêncio: o script anuncia a remoção e não
remove nada.

---

## 9. Nem toda tecla é vinculável

O botão N chegava como `KEY_PRESENTATION` (425). Seu keysym,
`XF86Presentation`, **não tem nome no Qt** — verificado em `libQt6Gui`,
`libKF6GlobalAccel` e `libkwin`, nenhuma das três o conhece. O KDE registra o
componente e **apaga o valor do atalho em silêncio**.

Diagnóstico: se `_launch=` aparece vazio em `~/.config/kglobalshortcutsrc`
depois de você escrever algo lá, o toolkit rejeitou a sequência.

Solução: `hwdb` mapeando `0xf5` para `prog1` → `XF86Launch1` → Qt
`"Launch (1)"`. É a convenção do próprio systemd para Acer gamer.

E a checagem de "já mapeado" tem de exigir **`prog1`**, não a mera presença
de `KEYBOARD_KEY_f5`: existe uma entrada genérica Acer que define
`f5=presentation` em toda máquina da marca, então testar a presença faria a
função pular sempre — no-op disfarçado.

---

## 10. `pgrep -f` casa com a própria linha de comando

Reportei "o DAMX está rodando" quando não estava: o `pgrep -f
DivAcerManagerMax` casou com o **meu próprio shell**, cuja linha de comando
continha a string procurada.

Use o nome do executável, não a linha inteira:

```bash
ps -eo comm --no-headers | grep -c '^DivAcerManagerMax$'
```

Dois processos `DAMX-Daemon` são normais: o empacotamento PyInstaller onefile
gera bootloader (o `MainPID` da unit) mais o app real como filho.

---

## 11. `/tmp` é tmpfs: some no reboot

Helper de askpass, scripts de captura e logs de medição guardados em
`/tmp/claude-*` desaparecem ao reiniciar. Um comando que dependia deles
falhou em silêncio e eu reportei sucesso sem checar o código de saída.

**Cheque o efeito, não o comando.** Se o script deveria criar um log, teste
`[ -s "$LOG" ]` antes de dizer que iniciou.

---

## 12. Sudo guarda credencial por TTY

`tty_tickets` é o padrão. Cada chamada de ferramenta roda num TTY diferente,
então a senha digitada numa não vale na seguinte, e keep-alive em background
não funciona.

O que funciona: `SUDO_ASKPASS` apontando para um wrapper de `kdialog`, e
**agrupar o trabalho com root em poucas chamadas grandes** em vez de muitas
pequenas.

---

## 13. `$(...)` na mesma linha que `$?` destrói o status

Reportei "8 suítes verdes" várias vezes com este laço:

```bash
./teste.sh >/dev/null 2>&1
printf '%-28s exit=%s\n' "$(basename $t)" "$?"     # ERRADO
```

A substituição `$(basename ...)` é expandida **antes** de `"$?"` e zera o
status. O relatório saía `exit=0` para qualquer resultado — inclusive para
testes que estavam falhando.

Guarde o status numa variável imediatamente depois do comando:

```bash
saida=$("./$t" 2>&1)
st=$?                    # antes de qualquer outra coisa
```

O `tests/run-all.sh` faz isso e distingue quatro desfechos: passou (0),
pulou por falta de root (2), alvo ausente (3) e falhou (demais).

---

## 14. Teste que não acha o alvo passa por vácuo

Ao mover os testes para `tests/`, os nove **passaram** — com os caminhos
todos quebrados.

A causa está no formato das asserções de ausência:

```bash
grep -qF "$padrao" "$ARQUIVO" || echo "OK: padrão ausente"
```

Se o arquivo não existe, o `grep` falha, e "falhou" é lido como "padrão
ausente". Aprovação por vácuo.

Todo teste agora começa com `exigir` sobre seus alvos, que sai com código 3
se algum sumiu. Verificado: escondendo `linuwu_sense.c`, o teste sai 3 em vez
de aprovar.

---

## 15. `filp_open` devolve `ERR_PTR`, nunca `NULL`

**Há dois locais com este defeito no driver agora** — `:3867` e `:4494`, os
dois caminhos de **escrita** do estado.

```c
file = filp_open(STATE_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
if (!file)                 /* ERRADO: nunca e verdadeiro */
    return -1;
len = kernel_write(file, ...);   /* escreve atraves do ponteiro de erro */
```

`filp_open` devolve `ERR_PTR(-errno)` em falha — um ponteiro pequeno e
negativo, tipo `0xFFFFFFFFFFFFFFE2`, que **não é NULL**. A guarda passa, e o
`kernel_write` seguinte dereferencia aquilo: oops de kernel.

Só não morde hoje porque `/etc` é gravável. Um sistema de arquivos em
somente-leitura, disco cheio ou `/etc` num tmpfs cheio derrubam a máquina no
desligamento, que é quando `acer_predator_state_save()` roda.

**A forma certa** — e os outros dois locais do mesmo arquivo (`:3803`, `:4526`)
já a usam:

```c
if (IS_ERR(file))
    return PTR_ERR(file);
```

### 15b. E o mesmo bloco fecha o arquivo duas vezes

```c
len = kernel_write(file, ...);
if (len < 0) {
    pr_info(...);
    filp_close(file, NULL);    /* fecha */
}
filp_close(file, NULL);        /* fecha de novo, sempre */
```

No caminho de erro, `filp_close` roda duas vezes sobre o mesmo `struct file`.
O `if` deveria sair da função, ou não fechar.

Os dois defeitos vivem juntos nos mesmos dois blocos e se consertam juntos.

---

## 16. Release do upstream se identifica por commit, não por número

`1.0.2` e `1.0.2-h1` distribuem tarballs de mesmo nome. A base deste projeto é
o commit `1f88341` (o hotfix), não `c1a4292`. Registrado no README, seção
"Licença e origem".

Sem consequência prática hoje — o projeto não puxa mais releases — mas a
confusão existe e custou tempo uma vez.

---

## 17. `set -e` e função que depende de retorno não-zero

`packaging/scripts/nitro-key-detection.sh` e `packaging/icons/gerar.sh` usam
`set -euo pipefail`. Sob `set -e`, uma função que devolve não-zero **por
projeto** — para dizer "não achei", "não aplicável" — mata o script em vez de
ser tratada.

O `setup.sh` não usa `set -e` de propósito: ele é feito de funções que
reportam por código de retorno (`install_drivers`, `driver_version`,
`bind_button_to_nexus`), e o chamador decide o que fazer. Ligar `set -e` nele
transformaria cada "não" em abortar no meio da instalação.

Ao acrescentar `set -e` a um script existente, procure antes por
`|| true`, `if funcao; then` e `$?` — são os sinais de que alguém está
tratando retorno não-zero como informação.

---

## 19. O índice do `hwmon` muda entre boots

`/sys/class/hwmon/hwmonN` é numerado pela ordem em que os módulos
registram seus sensores, e essa ordem não é estável. Nesta máquina o
sensor do `acer-wmi` é o `hwmon5` hoje; depois de um `modprobe -r` seguido
de `modprobe`, ou de um kernel novo, pode ser outro. Código que abre
`/sys/class/hwmon/hwmon5/fan1_input` funciona até o dia em que não
funciona, e falha lendo a temperatura do sensor errado — sem erro nenhum.

**Ancore no dispositivo, ou procure pelo nome.** O sensor do `acer-wmi`
tem caminho próprio, que não passa pelo índice:

```
/sys/devices/platform/acer-wmi/hwmon/hwmon*/
```

Para os demais, leia `name` de cada um e compare:

```bash
for d in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$d/name")" = coretemp ] && echo "$d"
done
```

Dentro do sensor vale a mesma regra: `temp1_input` costuma ser o pacote da
CPU, mas a garantia está em `temp1_label` dizer `Package id 0`.

---

## 20. `nvidia-smi` acorda a dGPU adormecida

Num laptop com Optimus a GPU discreta fica em `power/control = auto` e
adormece quando ninguém a usa. `nvidia-smi` a acorda para responder. Um
painel que sonda a cada 2 s para exibir temperatura mantém a GPU acesa o
tempo todo — gastando bateria por causa do medidor, não do trabalho.

Medido nesta máquina:

```
nvidia-smi                    18 ms      e acorda a GPU
2 leituras de hwmon            0,23 ms   e não acorda nada
```

**Pergunte antes de sondar.** Ler o estado é de graça e não acorda:

```bash
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```

Se disser `suspended`, mostre "adormecida" e não chame `nvidia-smi`. O
mesmo vale para qualquer ferramenta que fale com a GPU — `nvtop`,
`nvidia-settings`, uma consulta NVML.

---

## 21. Renomeação DKMS exige conferir pacote e integrações

Renomear o fonte não remove o registro antigo do DKMS. Verifique
`dkms status`: deve haver apenas `nexus_sense` para os kernels instalados.
Dois módulos para o mesmo dispositivo WMI podem disputar seu controle.

A limpeza ampla do instalador também remove autostart e hwdb do botão N.
Na migração de 2026-09-06, o driver novo iniciou no reboot, mas a bandeja
não: faltava `/etc/xdg/autostart/nexus-sense-autostart.desktop`.
Restaure as integrações da aplicação antes de pedir reboot e confira seu
funcionamento depois. Não repita uma desinstalação ampla para esse reparo.

---

## 22. Versão de kernel cravada em teste apodrece sozinha no Arch

Três testes cravavam `7.2.2-arch1-1` e `7.2.2-1-cachyos` nas asserções. Num
rolling release o kernel sobe de versão toda semana; os dois saíram do disco,
o `KDIR` passou a apontar para nada, a detecção de toolchain caiu no fallback
e o `test-toolchain.sh` reportou **GCC onde esperava LLVM**.

O pior não é a falha — é o que ela vira. O teste ficou vermelho por semanas
**acusando a si mesmo**, e a falha ficou tão familiar que virou ruído de
fundo. Um teste sempre vermelho não informa nada: perde-se a capacidade de
distinguir "quebrei agora" de "está assim desde sempre".

**Descubra o parque, não o escreva:**

```bash
mapfile -t KERNELS < <(for b in /lib/modules/*/build; do
    [ -d "$b" ] && basename "$(dirname "$b")"
done | sort)
[ "${#KERNELS[@]}" -eq 0 ] && { echo "ERRO alvo ausente"; exit 3; }
```

A guarda de vazio é obrigatória — ver armadilha 14. Um `for k in $(ls ...)`
que não acha nada executa zero iterações e **sai 0**: aprovação por vácuo,
exatamente o que o código 3 existe para impedir.

### 22a. Melhor que descobrir o parque: não depender dele

Descobrir os kernels instalados conserta o apodrecimento, mas deixa a
**cobertura** refém do ambiente. Numa máquina só-CachyOS (Clang), o ramo GCC
nunca é exercitado — e um Makefile que respondesse `LLVM` a tudo passaria no
teste. O teste fica verde justamente por não conseguir testar.

Quando o código sob teste lê um arquivo, sintetize o arquivo. O Makefile faz:

```make
grep -sh CONFIG_CC_IS_CLANG=y $(KDIR)/.config /boot/config-$(KVER)
```

O `-s` ignora o primeiro caminho inexistente, então basta plantar
`/boot/config-<sentinela>` para exercitar a detecção **sem que o kernel
exista**:

```bash
printf 'CONFIG_CC_IS_CLANG=y\n' > /boot/config-0.0.0-sintetico-clang
printf 'CONFIG_CC_IS_GCC=y\n'   > /boot/config-0.0.0-sintetico-gcc
make -s toolchain-info KVER=0.0.0-sintetico-clang   # deve dizer LLVM
make -s toolchain-info KVER=0.0.0-sintetico-gcc     # deve dizer GCC
```

Os dois ramos, determinísticos, em qualquer máquina. Três cuidados:

- **`trap ... EXIT`** para remover os sentinelas, inclusive quando o teste
  falha no meio.
- **Aborte se o sentinela já existir**, em vez de sobrescrever — o nome tem
  de ser inconfundível (`0.0.0-...`) e a checagem, explícita.
- **Precisa de root** para escrever em `/boot`. Sem ele, caia na cobertura do
  parque real e **diga que caiu**; cobertura parcial silenciosa é pior que
  cobertura parcial anunciada.

### 22b. "Tem headers" não é o mesmo que "dá boot"

`linux-headers` sem o pacote `linux` correspondente é comum no Arch, quando
algo puxa os headers como dependência. Isso cria um `/lib/modules/<ver>/`
com `build/` e mais nada:

```
6.18.48-1-cachyos-lts   build=sim  vmlinuz=sim  modules.dep=sim   ← bootável
7.2.4-arch1-2           build=sim  vmlinuz=não  modules.dep=não   ← só headers
```

O instalador gastava minutos compilando para esse kernel, e o
`test-install-drivers.sh` **reprovava** por um módulo que nunca seria
carregado. **`vmlinuz` é o discriminador:** só o pacote do kernel o instala.

Cuidado com a assimetria: `dkms build` precisa apenas de headers, então o
`test-dkms.sh` usa o critério largo (`build/`); o instalador e a verificação
de instalação usam o estreito (`vmlinuz`).

---

## 23. Não pergunte ao estado que o seu passo anterior acabou de invalidar

A reinstalação quebrou o botão N **de um jeito que só apareceria no próximo
boot** — o pior formato de defeito, porque a instalação reporta sucesso e a
verificação imediata confirma.

A cadeia:

1. `comprehensive_cleanup` apaga `/etc/udev/hwdb.d/61-damx-nitro-key.hwdb`
2. `install_nitro_key_hwdb` pergunta "já está mapeado?" com
   `udevadm info <device> | grep KEYBOARD_KEY_f5=prog1`
3. **A resposta é `prog1`** — a propriedade é cache do último evento udev,
   gravada antes da remoção do passo 1
4. A função conclui "trabalho já feito", retorna cedo, nunca reescreve o
   arquivo
5. No reboot o botão volta a `KEY_PRESENTATION`, cujo keysym nenhum toolkit
   vincula (armadilha 9)

A armadilha 9 já tinha endurecido o **formato** desta checagem — exigir
`prog1`, não a mera presença de `KEYBOARD_KEY_f5`. O que passou foi a
**fonte**: o valor certo, lido do lugar errado.

**Pergunte à fonte de verdade, depois de recompilá-la:**

```bash
systemd-hwdb update                       # o banco passa a refletir o disco
dmi=$(cat /sys/class/dmi/id/modalias)
systemd-hwdb query "evdev:atkbd:${dmi}" | grep -q '^KEYBOARD_KEY_f5=prog1$'
```

O `update` antes da consulta não é zelo: `systemd-hwdb query` lê o binário
compilado, que também pode estar velho. Sem ele, troca-se um cache obsoleto
por outro.

**Como diagnosticar isso sem reiniciar** — force o que o boot faria:

```bash
udevadm trigger --subsystem-match=input --action=change && udevadm settle
udevadm info /dev/input/event3 | grep KEYBOARD_KEY_f5
```

Foi assim que apareceu: `prog1` virou `presentation` na hora.

E confirme que o `hwdb` do systemd não cobre o seu modelo antes de supor que
cobre — aqui o único padrão ANV é `pnNitro*ANV*15-51`, e esta máquina é
`ANV15-52`. É a armadilha 1 outra vez, no mesmo dígito.

**A regra geral:** num script que limpa e depois reinstala, toda checagem de
"já está feito" tem de ler disco ou banco recompilado, nunca cache de
runtime. O cache foi povoado pelo mundo de antes da limpeza.

---

## 24. Chamada WMI concorrente colide, e o erro é esporádico

Sintoma no journal, algumas vezes por hora, sem dano visível:

```
platform_profile: Failed to get profile for handler acer-wmi
```

O driver não serializava **nada** — zero `mutex_lock` em 4728 linhas. Quando
dois leitores caem na mesma janela, o firmware devolve status não-zero,
`WMID_gaming_get_misc_setting` traduz para `-EIO`, e o núcleo do
`platform_profile` registra a linha acima.

Nesta máquina há três leitores: o agente a cada 2 s, a bandeja a cada 5 s e a
janela quando visível.

**Por que passou meses despercebido:** é esporádico e não quebra nada que o
usuário veja. Uma leitura falha, a próxima funciona. O erro vira paisagem no
journal.

### Como provar que é concorrência, e não outra coisa

Leitura sequencial **não** reproduz. O teste que separa as duas hipóteses é
pressão paralela:

```bash
P=$(echo /sys/devices/platform/acer-wmi/platform-profile/platform-profile-*/profile)
F=/sys/devices/platform/acer-wmi/nitro_sense/fan_speed
antes=$(journalctl -k --no-pager | grep -c 'Failed to get profile')
for i in $(seq 8); do
  ( for j in $(seq 150); do cat "$P" >/dev/null; cat "$F" >/dev/null; done ) &
done; wait; sleep 2
echo "novos: $(( $(journalctl -k --no-pager | grep -c 'Failed to get profile') - antes ))"
```

Medido: **200 leituras sequenciais → 0 erros. 8 leitores paralelos → 2 erros.**
Depois do mutex, 16 leitores × 200 leituras → 0.

### A correção

Um `mutex` no nível da folha, em `acer_wmi_evaluate_method()`, por onde passam
as 14 chamadas a `wmi_evaluate_method`.

**Mutex e não spinlock:** `wmi_evaluate_method` dorme. Todos os chamadores
estão em contexto de processo — handlers de sysfs, `probe`, `remove`, e o
notify do ACPI, que roda na workqueue de eventos, não em interrupção.

**A seção crítica é uma chamada só, de propósito.** Nada dentro de
`wmi_evaluate_method` chama de volta para o driver, então não há como aninhar
e travar. Pôr o lock em nível mais alto — nos helpers `WMID_*` — criaria esse
risco, porque alguns chamam outros.

### O que isto NÃO resolve

Sequências ler-modificar-escrever continuam sem atomicidade. A armadilha 3
manda partir do valor atual ao escrever num atributo de campos
(`usb_charging`, por exemplo); entre a leitura e a escrita, outro escritor
ainda pode entrar. Cada chamada é serializada, a sequência não.

Não foi observado na prática — só há um escritor por vez na interface — mas
está aqui para quando alguém acrescentar o segundo.

---

## Verificação rápida do conjunto

```bash
cd /home/brunodobner/Claude/Nitrosense
./tests/run-all.sh          # os que rodam sem privilégio
sudo ./tests/run-all.sh     # inclui o de DKMS
```

Os testes vivem em `tests/`, **fora de `driver/`**, de propósito: a próxima
release do upstream manda sobrescrever o driver e o instalador, e é justamente
aí que a suíte precisa existir para dizer o que quebrou.

De onde veio cada arquivo está no
[README da raiz](../README.md#licença-e-origem). O projeto não rastreia mais o
upstream, então não há diff de personalizações a manter.
