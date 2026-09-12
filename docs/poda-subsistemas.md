# Poda de subsistemas

O que pode ser cortado do driver, o que **não** pode, e como provar a
diferença antes de apagar qualquer linha.

**Escrito em:** 2026-09-11. **Estado:** camadas A, B e D executadas e
verificadas na máquina. O driver saiu de 4734 para 2912 linhas.

A decisão que governa este documento é a
[seção 6 de decisoes.md](decisoes.md): podar a tabela de modelos é seguro,
podar subsistemas não é. Aqui está a parte operacional.

---

## Por que este documento existe

Uma versão anterior de `decisoes.md` deduziu que `WIRELESS` e `BLUETOOTH`
seriam código morto, porque o quirk do modelo não as liga. **A medição
refutou.** Elas chegam pelo descritor `AA` do firmware, em runtime — e o corte
teria arrancado o controle por hardware do wifi e do bluetooth sem que nada
acusasse, porque os seis atributos de `nitro_sense` continuariam no lugar.

A lição não é "meça o bitmask". É que **"o quirk não liga" não é prova de
morte**, e que provas de tipos diferentes valem coisas diferentes. Este
documento existe para classificar cada corte pelo *tipo de prova* que o
sustenta, antes de qualquer edição.

---

## O portão

Rodado **entre cada camada**, não no fim. Um corte que muda qualquer linha
abaixo está errado e volta atrás.

```bash
# 1. compila limpo
cd driver && make clean && make W=1        # nenhum aviso

# 2. reinstala e recarrega  (pkexec; ver "Como trabalhar aqui" em estado.md)
sudo ./setup.sh                            # opção de instalar drivers

# 3. o número que não pode mudar
journalctl -k -b | grep 'capability bitmask'
#   esperado: 0x00002c26
#   [WIRELESS BLUETOOTH SET_FUNCTION_MODE PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE]

# 4. o que o bitmask NÃO cobre, e por isso é conferido à mão
ls /sys/devices/platform/acer-wmi/nitro_sense/   # 6 arquivos
cat /sys/firmware/acpi/platform_profile_choices  # low-power quiet balanced balanced-performance
cat /sys/class/rfkill/*/name | grep acer         # acer-wireless, acer-bluetooth
# O critério é que as DUAS entradas existam. Para exercitar a ESCRITA, use
# o bluetooth: block/unblock, que passa pelo mesmo set_u32 do wireless --
# o cap e parametro. NAO bloqueie o acer-wireless: a sessao do Claude Code
# cai junto, mesmo com rede cabeada. Ver armadilha 25.
ls /sys/devices/platform/acer-wmi/hwmon/         # existe

# 5. as duas suítes
python3 -m pytest -q
./tests/run-all.sh
```

**O botão N** não aparece em nenhum comando acima e precisa de um toque humano:
ele passa por `sparse_keymap` e pelo tratador de eventos WMI, que nenhuma das
camadas deveria tocar — mas "não deveria" é exatamente o que se confere.

---

## As quatro camadas

Ordenadas por **força da prova**, da mais forte para a mais fraca. A ordem de
execução é a mesma: o que é mais defensável sai primeiro.

### Camada A — morto por fato de firmware — **feita em 2026-09-11**

**A prova:** o GUID não existe nesta máquina, então o caminho de código nunca é
alcançado. Medido em `/sys/bus/wmi/devices/`, 2026-09-11:

| GUID | define | presente? |
|---|---|---|
| `AMW0_GUID1` `67C3371D-95A3-4C37-BB61-DD47B491DAAB` | `:132` | **não** |
| `AMW0_GUID2` `431F16ED-0C2B-444C-B267-27DEB140CF9C` | `:133` | **não** |
| `WMID_GUID1` `6AF4F258-B401-42FD-BE91-3D4AC2D7C0D3` | `:134` | **não** |
| `WMID_GUID2` `95764E09-FB56-4E83-B31A-37761F60994A` | `:135` | **não** |
| `WMID_GUID3` `61EF69EA-865C-4BC3-A502-A0DEBA0CB531` | `:136` | sim |
| `WMID_GUID4` `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56` | `:137` | sim |
| evento `676AA15E-6A47-4D9F-A2CC-1E6D18D14026` | `:148` | sim |

Esta é a prova mais forte do documento, porque é a única que não depende de
nenhuma leitura do nosso próprio código.

**O que saiu, e o que a estimativa errou.** Previa ~290 linhas; saíram **641**.
A conta original esqueceu que os caminhos do `WMID_GUID1` — `WMI_execute_u32`,
`WMID_get_u32`, `WMID_set_u32` — caem pelo mesmo motivo, e que sem eles o `enum`
de tipos, o campo `.type` e os dois `switch` de despacho perdem o objeto.

| o que saiu |
|---|
| `wmab_execute` e as structs `wmab_args`/`wmab_ret` |
| `AMW0_get_u32`, `AMW0_set_u32`, `AMW0_find_mailled` |
| `AMW0_set_cap_acpi_check_device`, `AMW0_set_capabilities` |
| `AMW0_interface`, `AMW0_V2_interface` |
| `WMI_execute_u32`, `WMID_get_u32`, `WMID_set_u32` |
| `WMID_set_capabilities`, `wmid_interface` |
| as três macros `ACER_AMW0_*` e os quatro `#define` de GUID |
| o `enum` de tipos, o campo `.type` e os dois `switch` de despacho |
| a cascata de seleção de interface em `acer_wmi_init()` |

`get_u32` e `set_u32` viraram três linhas cada: as únicas capabilities que
chegam ali são `WIRELESS`, `BLUETOOTH` e `THREEG`, e todas vão para
`wmid_v2_*`.

**Três coisas caíram junto por dependência**, como na poda da tabela:
`max_brightness` virou constante (quem a variava era `WMID_set_capabilities`, e
o backlight — camada B — ainda a lê); `get_wmid_devices()` consulta o
`WMID_GUID2` direto; e com ela fora, `create_debugfs`/`remove_debugfs` ficaram
sem chamador, levando `struct acer_debug` e o campo `.debug`. O `acer_debug`
estava listado na camada D, a decidir: não chegou a ser decisão, caiu por
dependência.

**A guarda de carregamento mudou de critério, de propósito.** Era
`AMW0_GUID1 presente && quirk desconhecido`, herdada de quando o driver
carregava em máquinas de outros fabricantes que expõem esse GUID. Com o AMW0
fora, manter a metade do GUID **afrouxaria** a defesa — virou a checagem direta
do quirk, que num driver de um modelo só é mais estreita, não menos.

**O portão, medido depois:** bitmask `0x00002c26` idêntico, os quatro perfis,
os seis atributos, `acer-wireless` e `acer-bluetooth` presentes, `hwmon`
presente, `Thermal states loaded/restored` no log, zero avisos, `W=1` limpo,
333 Python e 15/0/2 shell com e sem root.

**O caminho de escrita do rfkill também foi exercitado**, já que `set_u32` foi
reescrito nesta camada: `rfkill block` devolveu 0 nos dois rádios e o bluetooth
segurou o bloqueio através do poll. O wireless *parecia* voltar sozinho, e o driver
**anterior**, compilado num worktree e carregado por `insmod`, fazia o mesmo —
o que já mostrava não ser regressão. Mais tarde se descobriu que não era
comportamento nenhum: era o usuário religando o wifi à mão. Ver armadilha 25.

**Confirmação por outro caminho:** o log mostra
`Function bitmap for Communication Button: 0x801` *antes* do bitmask, o que
prova que `has_type_aa` é verdadeiro. É daí que `WIRELESS` e `BLUETOOTH` vêm —
e é por isso que remover `WMID_set_capabilities` não as leva junto.

**Cuidado:** `type_aa_dmi_decode()` **fica**. Ele é a única fonte restante das
duas capabilities.

**O risco residual, dito por escrito:** uma atualização de firmware que passasse
a expor `AMW0_GUID1` reintroduziria a necessidade. É o mesmo risco que a poda da
tabela DMI já aceitou, e o portão o detecta no boot seguinte.

---

### Camada B — morto pela tabela de um quirk só — **feita em 2026-09-12**

**A prova:** `quirk_acer_anv15_52 = { .nitro_sense = 1 }` é a única entrada, e
desde a remoção dos parâmetros inertes (2026-09-11) **não existe mais nenhum
caminho** para ligar as outras capabilities: nem parâmetro de módulo, nem campo
de quirk. `set_quirks()` tem quatro ramos e três deles são inalcançáveis.

Prova mais fraca que a camada A — depende de ler o nosso código, não o
firmware — mas fechada por construção, não por acaso.

**O que saiu**, em quatro estágios com build entre cada um. Previa ~765
linhas; saíram **1077** — a estimativa errou por baixo pela segunda vez, e pelo
mesmo motivo: contou os blocos, não o que eles arrastam.

| estágio | linhas |
|---|---|
| `four_zone_kb` inteiro | −526 |
| `MAILLED` e `BRIGHTNESS` | −185 |
| turbo e `kbd_dock` | −205 |
| grupos `predator_sense` e `nitro_sense_v4` | −158 |
| includes órfãos (`leds`, `backlight`, `acpi/video`) | −3 |

`MAILLED` e `BRIGHTNESS` arrastaram junto o `struct acer_data`, o campo `.data`
do `wmi_interface` e o `acer_platform_shutdown`, que só apagava o LED de e-mail.
`acer_suspend` ficou vazio; `acer_resume` só cuida do gsensor.

#### Duas coisas que esta classificação errava

**1. O turbo não morre "porque a capability está apagada".** A chamada de
`acer_toggle_turbo()` no tratador de eventos WMI não consulta capability
nenhuma — só o `key_num`. Se aquele `key_num` chegasse, a função rodaria.

> **Cuidado com a palavra "turbo" neste arquivo.** Aqui ela é sempre o turbo de
> *firmware* do upstream — a tecla dedicada dos Predator e o quinto perfil
> térmico. **Este modelo não tem nem um nem outro**, e o evento que o driver
> chamava de `pressed turbo button` é, nele, o **botão N**. O "Desempenho
> máximo" do Nexus Sense é outra coisa: um modo composto do aplicativo,
> acionado pela janela ou pela bandeja. Ver decisões 19.

O que o torna morto de verdade é outra coisa: `WMID_gaming_get_u64` e
`set_u64` começam com `if (!(interface->capability & cap)) return
AE_BAD_PARAMETER`, e os únicos caps que recebem são `TURBO_LED` e `TURBO_FAN`,
ambos fora do bitmask. `acer_toggle_turbo` falha na primeira linha e devolve
`-EIO` sempre, dispare a tecla ou não.

**A lição:** guarda no *sítio de chamada* e guarda *dentro da função* provam
coisas diferentes. Esta classificação só olhou a primeira.

**2. `WMID_gaming_get_sys_info` quase foi junto**, por estar entre duas funções
mortas. Ela é viva — o `hwmon` a usa. O build apontou, como apontou as três
dependências da camada A.

**E uma armadilha adjacente que a medição desfez:** o controle de ventoinha que
*funciona* não passa por nada disso. `acer_set_fan_speed()` chama
`WMI_gaming_execute_u64` direto, sem checagem de capability — é ele que produz
`AUTO FAN MODE!` no log. `WMID_gaming_set_fan_mode()`, que parece ser o
caminho das ventoinhas, era chamado só pelo turbo e já falhava calado.

**O erro que esta camada quase teve.** Uma leitura anterior classificou
`acer_predator_state_load/save()` como morta aqui, porque o nome diz "predator"
e `ACER_CAP_PREDATOR_SENSE` está apagada. **Está errado.** O ramo
`ACER_CAP_NITRO_SENSE` também a chama, de propósito, e é ela que preserva perfil
térmico e curvas de ventoinha entre reinícios — a correção descrita na
armadilha 4. O log de boot confirma: `Thermal states loaded` /
`Thermal states restored successfully`.

**Ela ficou na camada C.** Fica registrada aqui como o exemplo de por que nome
de função não é prova.

**O portão, medido depois:** bitmask `0x00002c26` idêntico, os quatro perfis, os
seis atributos, `acer-wireless` e `acer-bluetooth` presentes, `hwmon` presente,
`Thermal states loaded/restored` no log, zero avisos, `W=1` limpo, 333 Python e
15/0/2 shell com e sem root. Agente ativo, sem avisos no journal.

---

### Camada C — vivo. Não encostar.

Nenhuma destas sai, em nenhuma camada. A lista existe para ser lida **antes** de
cada corte, não depois.

| subsistema | como se sabe que está vivo |
|---|---|
| rfkill `WIRELESS` e `BLUETOOTH` | `acer-wireless` e `acer-bluetooth` em `/sys/class/rfkill/` |
| `type_aa_dmi_decode()` | `Function bitmap for Communication Button: 0x801` no log |
| `platform_profile` | os quatro perfis em `platform_profile_choices` |
| `hwmon` / `FAN_SPEED_READ` | `/sys/devices/platform/acer-wmi/hwmon/` existe |
| grupo sysfs `nitro_sense` | os cinco atributos graváveis + `version` |
| `acer_predator_state_load/save/update/restore` | chamadas pelo ramo `NITRO_SENSE`; log de boot |
| tratador de eventos WMI + `sparse_keymap` | o botão N abre o app |
| `SET_FUNCTION_MODE` | bit 5 do bitmask, ligado por `WMID_GUID3` |
| os dois mutexes WMI | armadilha 24; a correção da v1.1.1/v1.1.2 |

---

### Camada D — decidir um a um, sem lote — **feita em 2026-09-12**

Cada um tem argumento nos dois sentidos, e por isso nenhum entrou em lote:
são cinco decisões, não uma. Três removeram, duas mantiveram — e uma das
mantidas ficou diferente do que era.

| candidato | decisão |
|---|---|
| `ec_raw_mode` | **removido.** Nasce `false` e ninguém o passa; o caminho que ele abria (`acer_wmi_enable_ec_raw`) nunca rodou. Sai também das duas condições de agendamento do trabalho de rfkill, onde era o primeiro termo de um `\|\|` cujo segundo termo já era falso. |
| `force_caps` | **fica, mascarado.** Continua sendo a válvula de escape se o bitmask mudar num firmware novo. Mas depois das camadas A e B ele podia ligar bits sem código atrás, e o bitmask impresso no carregamento — que é o instrumento deste documento — anunciaria algo inexistente. Agora é mascarado por `ACER_CAP_IMPLEMENTED` e avisa o que ignorou. |
| `cycle_gaming_thermal_profile` | **fica.** Não é inerte: governa se o botão N percorre os perfis ou alterna. Botão em uso. |
| `THREEG` | **removido.** O descritor AA desta máquina não a anuncia (bitmap `0x801`, sem o bit 6) e não há rádio 3G no aparelho. Sai o rfkill `acer-threeg`, o parâmetro, o mapeamento cap→device e a capability de `ACER_CAP_IMPLEMENTED` — o `#define` fica, como os outros bits sem código, para ler bitmask de outra máquina. |
| o trabalho periódico de `rfkill` | **removido.** `acer_rfkill_update()` e o `delayed_work` nunca eram agendados aqui, porque `ACERWMID_EVENT_GUID` existe. Com o `ec_raw_mode` fora, a condição virou só `!wmi_has_guid(...)` — falsa sempre. |
| os `pr_info` | saíram do escopo da poda e viraram item próprio; feito na v1.1.6. |

#### Estes dois quase não saíram, e o motivo errado merece registro

A primeira redação adiou os dois. O argumento era: ambos vivem no caminho do
`rfkill`, onde há um efeito não explicado (armadilha 25), e **testar o wireless
derruba a rede desta máquina** — então não haveria como verificar o caminho de
escrita depois de mexer nele.

**O argumento tem um furo.** `acer_rfkill_set()` chama `set_u32()` com o `cap`
como parâmetro: wireless e bluetooth passam pela **mesma** função, pelo **mesmo**
ramo. Testar o bluetooth testa a escrita do wireless — e o teste de bluetooth é
seguro, já tinha sido feito sem derrubar sequer o fone conectado.

Some-se a isso que nenhuma das duas remoções toca a lógica do efeito não
explicado: o `THREEG` nunca casa no bitmask, então tirá-lo de um `|` é neutro
por construção, e o poll nunca era agendado.

Feito, e verificado: bitmask idêntico, as duas entradas de rfkill no lugar, e o
`block`/`unblock` do bluetooth exercitando `set_u32` — `rc=0`, estado `0→1`,
segurou, voltou a `0`, fone conectado o tempo todo.

**A lição não é "corte sempre".** É que "não consigo verificar" precisa ser
conferido como qualquer outra afirmação técnica: aqui bastava seguir o `cap` até
a função para ver que a verificação existia. Cautela sem medição é palpite com
outro nome.

**Nada ficou em aberto.** O que parecia um mecanismo por explicar — a armadilha
25 — foi medido depois com rede cabeada de reserva: o bloqueio do wireless
**segura**, e o driver fica calado. Não havia fenômeno. A armadilha foi
retratada e hoje registra só o erro de método.

---|---|---|
| `THREEG` (rfkill, parâmetro, capability) | capability apagada, nenhum rfkill 3G na máquina | compartilha `acer_rfkill_init/exit` com wireless e bluetooth — errar aqui é o erro original de novo |
| `force_caps` | parâmetro de depuração, ninguém passa | é a válvula de escape se o bitmask mudar num firmware novo |
| `ec_raw_mode` | acesso EC cru, sem uso neste modelo | custo de manter é quase zero; o `acer_debug` que o acompanhava já caiu por dependência na camada A |
| `cycle_gaming_thermal_profile` | ninguém o passa | muda o comportamento do botão N, que é usado |
| os 57 `pr_info` | ~50 linhas/minuto no log do kernel | ver abaixo — é item próprio, não poda |

---

## O que isto não é

**O barulho no log não é poda.** O driver despeja ~50 linhas por minuto
(`battery health query`, `usb charging get status`, `backlight_timeout get
status`, a cada sondagem do agente), ~72 mil linhas por dia. É um item separado
no roteiro, porque a decisão ali é sobre *nível de log* (`pr_debug` vs
`pr_info`), não sobre remover código. Cortar `pr_info` em bloco durante uma
camada de poda misturaria duas mudanças com critérios de aceite diferentes.

---

## Ordem de execução e resultado esperado

Um commit por camada, portão entre cada um. A camada A vem antes da B porque
tem prova mais forte: se algo quebrar, o diagnóstico é mais barato.

```
[x] Camada A    641 linhas   prova de firmware       2026-09-11
[x] Camada B   1077 linhas   prova de construção     2026-09-12
[x] Camada D    110 linhas   ec_raw_mode, THREEG e o poll de rfkill
                             fora; force_caps mascarado e honesto
```

| | linhas |
|---|---|
| v1.1.2 | 4734 |
| depois de A | 4093 |
| depois de B | 3016 |
| depois de D | **2912** |

*(O fonte tem 3022 linhas hoje: o commit do log do kernel, posterior a esta
camada, acrescentou um comentário de seis linhas explicando o botão N.)*

**As duas estimativas erraram por baixo, e para o mesmo lado:** A previa ~290 e
saíram 641; B previa ~765 e saíram 1077. Em ambos os casos a conta somou o
tamanho dos blocos e esqueceu o que eles arrastam — structs, campos, includes,
funções que ficam sem chamador. **Numa poda, a estimativa é piso, não teto**, e
só o compilador sabe o número de verdade.

**Compilar entre cada estágio** foi o que tornou a poda da tabela administrável:
os três primeiros builds falharam, cada um apontando exatamente o que tinha
caído junto. A mesma disciplina vale aqui, e com mais razão — estes cortes são
maiores.
