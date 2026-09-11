# Port das personalizações ANV15-52 para o DAMX atualizado

**Data:** 2026-09-04
**Estado:** aprovado para implementação
**Escopo:** Projeto A (o Projeto B — interface própria — fica para depois)

---

## 1. Problema

O workspace tem duas cópias do DAMX (*Div Acer Manager Max*, de
`PXDiv/Div-Acer-Manager-Max`):

- **`original/`** — release 1.0.2 do upstream (commit `1f88341`, build de
  2026-07-23). Atualizado, mas não funciona plenamente no notebook alvo.
- **`versaopessoal/`** — fork local de 2025-07-02, adaptado ao Acer Nitro
  ANV15-52 sobre CachyOS. Funciona, mas está ~1 ano defasado.

O objetivo é levar as adaptações de `versaopessoal/` para `original/`,
tornando-o plenamente funcional no ANV15-52 e portável entre distros.

### Hardware e ambiente alvo

```
DMI:     Acer / Nitro ANV15-52
Distro:  CachyOS (base Arch) — hoje; Ubuntu/Fedora são cenários futuros
Kernels: 6.18.48-1-cachyos-lts   CLANG
         7.2.2-1-cachyos         CLANG
         7.2.2-arch1-1           GCC
```

A convivência de kernels Clang e GCC na mesma máquina é o fato que mais
restringe o desenho da compilação (§4.2).

---

## 2. Descobertas que fundamentam o desenho

Levantadas por leitura do código, inspeção do sistema em execução e
extração dos binários. Registradas aqui porque várias contrariam a
hipótese inicial.

### 2.1 O ANV15-52 não casa com nenhuma entrada DMI do upstream

`DMI_MATCH` compara por substring. `"Nitro ANV15-51"` não é substring de
`"Nitro ANV15-52"`, logo `dmi_check_system()` não casa nada e
`find_quirks()` cai em `quirks = &quirk_unknown` — uma struct vazia
(`linuwu_sense.c:517`). Sem capability alguma, **nenhum grupo sysfs é
criado**.

Foi essa ausência — não a classificação do quirk — que produzia o painel
irreal relatado. A GUI não tinha o que consultar.

### 2.2 O painel é montado por existência de arquivo

Extraído do CArchive PyInstaller do daemon 0.5.2. Dois métodos decidem
tudo:

- `DAMXManager._detect_laptop_type()` — testa a existência de
  `.../acer-wmi/predator_sense` (→ Predator) e `.../acer-wmi/nitro_sense`
  (→ Nitro).
- `DAMXManager._detect_available_features()` — `os.path.exists()` arquivo
  a arquivo: `backlight_timeout`, `battery_calibration`,
  `battery_limiter`, `boot_animation_sound`, `fan_speed`, `lcd_override`,
  `usb_charging`, mais `four_zoned_kb/{per_zone_mode,four_zone_mode}` e
  `enek5130_hid_rgb`.

Não lê capability bits nem inspeciona valores.

### 2.3 `quirk_acer_nitro` é o classificador correto para o ANV15-52

Consequência direta de §2.2. Os dois candidatos produzem um diretório com
**o mesmo nome**, `nitro_sense` — `nitro_sense_v4_attr_group` apenas
reaponta para `predator_sense_attrs` (`linuwu_sense.c:3930`). O daemon
não os distingue.

| | `quirk_acer_nitro` | `quirk_acer_nitro_v4` |
|---|---|---|
| diretório sysfs | `nitro_sense` | `nitro_sense` |
| tipo detectado | Nitro | Nitro |
| `version`, `fan_speed`, `battery_limiter`, `battery_calibration`, `backlight_timeout`, `usb_charging` | ✅ | ✅ |
| `lcd_override` | ❌ | ✅ |
| `boot_animation_sound` | ❌ | ✅ |
| perfis térmicos, hwmon, `four_zoned_kb` | idêntico | idêntico |

A diferença inteira são dois atributos. Ambos leem `-1` no hardware alvo
— valor que o driver documenta como *unknown value*: a chamada WMI
responde (falha retornaria `-ENODEV`), mas com um padrão de bits que o
driver não reconhece para este modelo. E o upstream já exclui
deliberadamente o `lcd_override` do grupo Nitro (`linuwu_sense.c:3935`,
comentado no fonte).

**Decisão:** adicionar a entrada DMI do ANV15-52 apontando para
`&quirk_acer_nitro`. A linha do ANV15-51 fica **intocada**, revertendo a
reclassificação que a versão pessoal fazia.

Verificação em hardware confirma ou refuta (§6). Se refutar, trocar para
`&quirk_acer_nitro_v4` é uma linha.

### 2.4 O upstream ganhou suporte a Arch/CachyOS, mas insuficiente para DKMS

`setup.sh` agora tem `is_llvm_kernel()` (checa `CONFIG_CC_IS_CLANG` em
`/boot/config-*`, `$KDIR/.config` e `/proc/config.gz`, com fallback
lendo `cachyos` em `/etc/os-release`) e instala dependências via
`pacman`/`apt-get`/`dnf`/`zypper`.

Porém ele inspeciona **apenas o kernel em execução** e exporta
`LLVM=1 CC=clang` globalmente. Num ambiente DKMS multi-kernel isso
quebra o build do `7.2.2-arch1-1` (GCC). A detecção precisa ser **por
kernel-alvo**, como faz o Makefile da versão pessoal.

### 2.5 A GUI já é multi-distro; o instalador não é

`DivAcerManagerMax` é um bundle .NET self-contained (assinatura HostModel
em `0xB21C78`, 208 DLLs embutidas, 308 blocos `BSJB`) sobre **Avalonia**.
O daemon é PyInstaller com o Python embutido. Ambos rodam em qualquer
glibc sem dependência de distro.

O que não é portável é o driver, o DKMS e o instalador — exatamente o
escopo deste projeto.

### 2.6 O `patches/anv15-52.patch` está quebrado

Referencia `src/acer_quirks`, arquivo que não existe; a indentação não
bate com o fonte; e não contém a reclassificação do -51 que o `.c` da
versão pessoal de fato aplica. Não é aproveitável. Fica preservado no
commit baseline como registro histórico.

---

## 3. Estratégia

**`original/` é o alvo.** As adaptações são portadas **por intenção, não
por transcrição**: `versaopessoal/` funciona como especificação de
requisitos, e cada peça é reimplementada na melhor forma disponível.

O instalador segue a **Abordagem 1**: o `setup.sh` do upstream é a base,
com DKMS enxertado. Ele já traz o que a versão pessoal não tem —
detecção multi-distro de pacotes, configuração da tecla Nitro via
`evtest`, permissões por `tmpfiles.d`, limpeza de instalações legadas — e
lhe falta apenas persistência entre kernels. O `install-damx.sh`, em
contraposição, é Arch-only (`pacman -Q base-devel` cravado), o que
contraria o requisito multi-distro.

Consequência feliz: o conflito entre o `LLVM=1` empurrado pelo `setup.sh`
e a detecção do Makefile **desaparece**. Com DKMS, o `setup.sh` deixa de
chamar `make`; ele só instala dependências. Quem compila é o DKMS, por
kernel, injetando `KERNELRELEASE` e detectando clang sozinho. O Makefile
respeita esse override e, na ausência dele, lê o `.config` do
kernel-alvo. As três camadas passam a concordar.

---

## 4. Desenho

### 4.1 `dkms.conf`

Reescrito enxuto. O arquivo da versão pessoal traz cinco variáveis que
seus próprios comentários marcam como `⚠️ INERTE` — `SUPPORTED_KERNELS`,
`MINIMUM_KERNEL_VERSION`, `KERNEL_UAPI_VERSION_REQUIREMENT`,
`BUILD_DATE`, `MAINTAINER`, `LICENSE`. O diagnóstico estava correto: o
DKMS não lê nenhuma delas. Saem, junto com o `POST_BUILD` decorativo.

Restam as efetivas: `PACKAGE_NAME`, `PACKAGE_VERSION`,
`BUILT_MODULE_NAME`, `BUILT_MODULE_LOCATION`, `DEST_MODULE_LOCATION`,
`MAKE`, `AUTOINSTALL`.

### 4.2 `Makefile`

Detecção de toolchain **por kernel-alvo**, não pelo kernel em execução:

- `KVER` vem de `KERNELRELEASE` quando o DKMS o injeta; senão de
  `uname -r`.
- Se `LLVM` não foi definido externamente (`$(origin LLVM)`), procurar
  `CONFIG_CC_IS_CLANG=y` em `$(KDIR)/.config` **e** em
  `/boot/config-$(KVER)` — o segundo cobre pacotes de headers que não
  trazem `.config`. Este é o ponto que a versão pessoal não cobria.
- Respeitar `LLVM=1` quando o DKMS já o passou.

Correções sobre a versão pessoal:

- `clean` remove `src/*.o` etc., não `*.o` na raiz — onde nunca houve
  objeto algum.
- Nenhum `sudo` dentro do Makefile. O instalador já roda como root, e
  `sudo` embutido quebra build não-interativo.
- `install` permanece como caminho manual de fallback (sem DKMS), sem
  mexer em serviços, grupos ou tmpfiles — isso é responsabilidade do
  `setup.sh`.

### 4.3 `src/linuwu_sense.c`

**Entrada DMI**, junto às demais entradas Nitro:

```c
{
    .callback = dmi_matched,
    .ident = "Acer Nitro ANV15-52",
    .matches = {
        DMI_MATCH(DMI_SYS_VENDOR, "Acer"),
        DMI_MATCH(DMI_PRODUCT_NAME, "Nitro ANV15-52"),
    },
    .driver_data = &quirk_acer_nitro,
},
```

**Correções que entram por mérito próprio**, independentes de compilação:

| local | mudança | motivo |
|---|---|---|
| `acer_platform_remove` (`:4537`, `:4542`) | `&` → `&&` | `has_cap()` retorna `bool`; o bitwise funciona por acidente |
| `acer_predator_v4_platform_profile_probe` (`:2350`) | `unsigned long supported_profiles = 0` | leitura de memória não inicializada — ver abaixo |
| `WMID_gaming_set_fan_mode` (`:1893`) | `1ULL << (i + 1)` | endurecimento; sem defeito ativo neste hardware |

O caso do `supported_profiles` é um defeito real, e mais grave do que
parecia. `WMID_gaming_get_misc_setting()` recebe `u8 *value` e faz
`*value = FIELD_GET(...)` (`:1942`) — escreve **exatamente um byte**. O
chamador passa `(u8 *)&supported_profiles`, um `unsigned long` de 8
bytes, e em seguida lê a palavra inteira com `test_bit()`. Sete dos oito
bytes ficam indefinidos. Funciona hoje por acidente de layout: em x86-64
little-endian, os perfis testados (`QUIET`=0 … `ECO`=6) caem todos no
byte inicializado. Inicializar com `0` custa nada e remove a
fragilidade.

Já o `1ULL <<` é honestamente só endurecimento: com
`cpu_fans = gpu_fans = 1`, o deslocamento máximo é 3, longe dos 32 que
tornariam o comportamento indefinido. Entra porque é gratuito e correto,
não porque conserta algo observável. Pela mesma razão, o `1 << (i + 3)`
logo abaixo — que a versão pessoal deixou passar — recebe o mesmo
tratamento, por consistência.

**Correções de compilação**: decididas por build real nos três kernels.
Aplicar **apenas** o que o compilador exigir — sem porte às cegas. As
candidatas, vindas da versão pessoal, são `strncpy` → `memcpy` (3
ocorrências, com guarda `if (!len) return -EINVAL`), o `#include
<linux/string.h>` associado, a captura do retorno de `i8042_command`, e
a checagem `if (result > 0xFF)` nas leituras EC.

**Não entra:** `capable(CAP_SYS_ADMIN)` em `acer_predator_state_load` e
`acer_predator_state_save`, nem o modo `0600`.

Justificativa: as duas funções são chamadas exclusivamente de
`acer_platform_probe` (`:4480`, `:4487`) e `acer_platform_remove`
(`:4540`, `:4545`). Nenhuma está ligada a atributo sysfs — não há
caminho de userspace sem privilégio que as alcance, e bind/unbind já
exige root. A checagem não protege nada. Em compensação, `capable()`
avalia as credenciais da tarefa corrente, que nesses caminhos pode ser um
kworker ou o processo do `rmmod`; se reprovar, `state_save` retorna
`-EACCES` em silêncio e as configurações salvas se perdem no
descarregamento. Proteção zero, risco de perda de dados não-zero.

O `0600` é inofensivo, mas rende pouco e engorda o diff contra o
upstream. Fica de fora; reintroduzível em uma linha.

### 4.4 `setup.sh` — DKMS em `install_drivers()`

Só essa função muda. O resto do script (menu, limpeza de legado,
dependências multi-distro, tecla Nitro, tmpfiles, serviço do daemon,
instalação da GUI) fica como o upstream entregou, para manter o diff
concentrado e o rebase barato.

Nova `install_drivers()`, com o núcleo DKMS derivado do
`install-damx.sh`:

1. **Derivar a versão do fonte** — `DRIVER_VERSION` de
   `src/linuwu_sense.c`, nunca literal. O `install-damx.sh` cravava
   `25.701` em ~8 pontos; quando o upstream subir a versão, um instalador
   assim opera silenciosamente na errada. Esta é a correção de maior
   valor prático do port.
2. **Garantir `dkms`** entre as dependências de cada distro (o upstream
   ainda não o instala).
3. **Limpar estado anterior** — `dkms remove --all`, depois `/usr/src/
   linuwu_sense-$VER` e `/var/lib/dkms/linuwu_sense`. O estado do DKMS
   vive em `/var/lib/dkms`; apagar só `/usr/src` deixa registro órfão e o
   `dkms add` seguinte falha. (Observação correta da versão pessoal,
   preservada.)
4. **Copiar fonte** para `/usr/src/linuwu_sense-$VER/` e registrar com
   `dkms add`.
5. **Compilar para todos os kernels instalados**, não só o corrente —
   é o que permite reiniciar em qualquer entrada do boot e ainda ter o
   módulo. Falha em kernel secundário é aviso, não erro fatal.
6. **Verificar de fato** — `dkms status` retorna 0 mesmo para módulo
   inexistente, então o teste é procurar `installed` na saída, não o
   código de retorno. (Observação correta da versão pessoal, preservada.)
7. **Resolver o conflito com `acer_wmi`** — blacklist em
   `/etc/modprobe.d/`, descarregar da sessão corrente, carregar
   `linuwu_sense`, e confirmar que o sysfs populou.

Fallback: se `dkms` não estiver disponível na distro, cair no
`make && make install` que o upstream já faz, com aviso claro de que o
módulo não sobreviverá a atualizações de kernel.

### 4.5 Unidades systemd

**A decidir por teste, não por suposição.** A hipótese é que a unit da
versão pessoal seja redundante para *carregar* o módulo, já que
`/etc/modules-load.d/linuwu_sense.conf` o faz mais cedo, via
`systemd-modules-load.service`. O valor real da unit seria o `ExecStop`
ordenado no shutdown, que dispara `acer_predator_state_save()` — que é,
aliás, exatamente o que a unit original do upstream fazia.

Procedimento: instalar, reiniciar, verificar se o módulo carregou e se o
sysfs populou sem a unit de `ExecStart`. O resultado decide entre manter
o `ExecStart` ou reduzir a unit ao `ExecStop`.

`linuwu_sense.target` **não entra**: o arquivo existe na versão pessoal
mas nenhuma unit o referencia por `WantedBy` ou `Requires`.

### 4.6 Scripts auxiliares

`uninstall-damx.sh` e `diagnostico-dkms.sh` não são portados como
scripts separados. A desinstalação é responsabilidade do
`comprehensive_cleanup()` do `setup.sh`, que passa a remover também o
registro DKMS. O diagnóstico não tem equivalente no upstream e pode ser
retomado depois, se fizer falta.

---

## 5. Layout do git

Commit baseline `375e3c5`, tag `upstream/1.0.2`, registra
`original/` e `versaopessoal/` intactos. Nada anterior a ele pode ser
perdido.

Sobre ele, commits temáticos **tocando apenas `original/`**:

1. `build:` Makefile com detecção de toolchain por kernel
2. `build:` `dkms.conf`
3. `driver:` entrada DMI do ANV15-52
4. `fix:` `&` → `&&` em `acer_platform_remove`
5. `fix:` correções de compilação exigidas pelos kernels alvo
6. `install:` DKMS em `install_drivers()`
7. `systemd:` unidades, conforme o resultado de §4.5

`git diff upstream/1.0.2 -- original/` passa a ser a lista completa e
exata das personalizações. Na próxima release do upstream, `original/` é
sobrescrito e esses commits são a receita de reaplicação — cada um
isolado e revertível.

`.gitignore` cobre apenas artefatos de build de módulo.

---

## 6. Verificação

Nenhuma afirmação de funcionamento sem saída de comando que a sustente.

**Build** — `dkms install` conclui nos três kernels, incluindo o
`7.2.2-arch1-1` (GCC), que é o caso que a estratégia do upstream
quebraria.

**Classificação do quirk** (§2.3) — após carregar, o sysfs deve
apresentar exatamente:

```
/sys/devices/platform/acer-wmi/nitro_sense/
  version  fan_speed  battery_limiter  battery_calibration
  backlight_timeout  usb_charging
```

Sem `lcd_override` e sem `boot_animation_sound`. E `predator_sense/` não
deve existir.

**Painel** — abrir a GUI e confirmar que os controles correspondem ao
hardware. Este é o teste que refuta ou confirma §2.3; se algo real
sumir, trocar para `&quirk_acer_nitro_v4`.

**Persistência** — reiniciar e confirmar que o módulo carregou e o sysfs
populou. Decide §4.5.

**Regressão de perfis** — `platform_profile_choices` deve continuar
`low-power quiet balanced balanced-performance`. Esses perfis vêm da
consulta ao firmware, não do quirk: o ramo que força todos testa os
*module params* `predator_v4`/`nitro_v4`, não `quirks->nitro_v4`. A
mudança de classificação não deve alterá-los.

---

## 7. Fora de escopo

- **Projeto B — interface própria.** Adiado por decisão explícita. As
  duas razões que o motivavam já têm solução mais barata: a portabilidade
  multi-distro é problema do instalador (§2.5), e os controles fantasmas
  somem com a correção do quirk (§2.3). Se ainda for desejado, o fonte
  está no GitHub sob GPL-3.0 — Avalonia/C# e daemon Python — e o
  protocolo do socket `/var/run/DAMX.sock` já está parcialmente mapeado.
- **Contribuição ao upstream.** Decisão do usuário: o trabalho é local.
- **Recompilar daemon e GUI a partir do fonte.** Usamos os binários da
  release 1.0.2.
- **`versaopessoal/`** não é mais modificada. Fica congelada como
  referência.
