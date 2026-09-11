# Decisões

Por que o projeto é como é. Cada entrada traz a decisão, a medição que a
sustenta e o que foi descartado — porque saber o que **não** foi feito costuma
valer mais do que saber o que foi.

Isto complementa [armadilhas.md](armadilhas.md), que registra o que morde.
Aqui está o que foi escolhido.

> Extraído dos 108 commits de desenvolvimento (2026-09-04 a 2026-09-10) antes
> do reset de histórico da v1.0.0. O que estava só em mensagem de commit passou
> a viver aqui.

---

## 1. Não há processo root permanente — nem helper sob demanda

**A medição que decidiu:** o `sysfs` honra permissão de grupo. A escrita como
uid 1000 nos seis atributos passou sem root.

Isso tornou o daemon desnecessário. Com ele saiu o socket em
`/var/run/DAMX.sock`, que era **modo 666 e aceitava comandos de qualquer
processo da máquina sem autenticação** — incluindo recarregar o driver.

A escrita diária passa por permissão de grupo em `sysfs`, aplicada por uma
regra udev. `udev` não altera permissão de atributo por `ATTR{}`, então a regra
chama um script.

**Descartado:**

- `capable(CAP_SYS_ADMIN)` no driver — as funções de estado só são chamadas de
  `probe`/`remove`, que já exigem root. A checagem não protegeria nada e
  poderia fazer o `state_save` falhar em silêncio no `rmmod`.
- Helper privilegiado + regra polkit — existiam para a ação de forçar perfis no
  Diagnóstico, que saiu do desenho. Sem ela seriam código root sem propósito.
  Um teste guarda isso: se alguém ressuscitar `pkexec` no instalador sem
  decisão, ele acusa.

## 2. PySide6 no lugar de .NET

A GUI do upstream tinha **104 MB** por ser .NET self-contained: carregava
runtime, Skia, HarfBuzz e Avalonia embutidos para desenhar seis atributos.

Em PySide6 sobre o Qt6 que o Plasma já carrega, são ~40 KB de fonte. Com o
daemon junto, **121 MB de blob opaco viraram ~60 KB de código legível**, sem
instalar nada novo.

A fronteira entre a GUI antiga e o daemon era um socket falando JSON de linha —
não uma biblioteca. Por isso os dois lados puderam ser substituídos.

## 3. O pacote vai para `/usr/lib/nexus-sense`, não por `pip`

Instalar por `pip` dentro de `/usr` brigaria com o gerenciador de pacotes pelos
mesmos caminhos. O pacote vai inteiro para um diretório próprio e os dois
lançadores apontam `PYTHONPATH` para lá. Desinstalar passa a ser apagar uma
pasta.

## 4. A unit systemd é só de desligamento

**Decidido por teste de boot, não por suposição.** Com a unit desabilitada e a
máquina reiniciada, o módulo carregou assim mesmo: o
`systemd-modules-load.service` o carrega de `/etc/modules-load.d/`, mais cedo
do que qualquer unit ordenada `After=multi-user.target` conseguiria.

O `ExecStart` era redundante. O que falta sem unit nenhuma é o
**descarregamento**: o systemd não remove módulos no desligamento, então o
caminho de `remove` do driver — e com ele `acer_predator_state_save()` — nunca
rodaria. É para isso que a unit existe.

## 5. O quirk do ANV15-52 é `quirk_acer_nitro`, não `nitro_v4`

Os dois criam diretório de mesmo nome (`nitro_sense`), então nada os distingue
pelo caminho. A diferença visível são dois atributos que leem `-1` neste
hardware.

Mas `nitro_v4` também seta `ACER_CAP_PREDATOR_SENSE`, e é essa capability que
liga `acer_predator_state_load/save()`. Escolher o quirk correto teria
**levado junto a persistência de perfil térmico entre reinícios**.

Corrigido na origem em vez de contornado: o caminho Nitro puro agora carrega e
salva estado. Ver [armadilhas.md](armadilhas.md) armadilha 4.

## 6. Podar a tabela de modelos é seguro; podar os subsistemas não é

Duas operações diferentes foram confundidas durante um bom tempo. Elas têm
risco oposto.

**As capabilities têm três fontes, e a tabela de quirks é só uma:**

| fonte | o que liga | vem da tabela DMI? |
|---|---|---|
| `set_quirks()` | `PLATFORM_PROFILE`, `FAN_SPEED_READ`, `NITRO_SENSE`, `TURBO`, `MAILLED`, `BRIGHTNESS` | **sim** |
| `type_aa_dmi_decode()` | `WIRELESS`, `BLUETOOTH`, `THREEG` | não — descritor `AA` do firmware, em runtime |
| `WMID_set_capabilities()` | `WIRELESS`, `BLUETOOTH`, `THREEG` | não |

Medido nesta máquina: `Function bitmap for Communication Button: 0x801`, que é
`WIRELESS` (`1<<0`) mais `BLUETOOTH` (`1<<11`) — e de fato há `acer-wireless` e
`acer-bluetooth` em `/sys/class/rfkill/`, **apesar de `quirk_acer_nitro` não
ligar nenhum dos dois**.

### A tabela foi podada em 2026-09-11

Feito, e verificado pelo critério acima.

| | antes | depois |
|---|---|---|
| entradas DMI | 32 Acer + 7 não-Acer | **1** (`Nitro ANV15-52`) |
| structs de quirk | 14 | **2** (o do modelo e `quirk_unknown`) |
| tabelas auxiliares | `acer_blacklist`, `amw0_whitelist` | removidas |
| linhas do `.c` | 5167 | **4728** |

O quirk novo é `quirk_acer_anv15_52 = { .nitro_sense = 1 }` — exatamente o que
o `quirk_acer_nitro` tinha, agora com nome que diz de quem é.

**A verificação, medida antes e depois:**

```
capability bitmask: 0x00002c26
[WIRELESS BLUETOOTH SET_FUNCTION_MODE PLATFORM_PROFILE FAN_SPEED_READ NITRO_SENSE]
```

Idêntico. Mais: modelo reconhecido, os seis atributos no lugar, perfis térmicos
inalterados (`low-power quiet balanced balanced-performance`), e **`acer-wireless`
e `acer-bluetooth` continuam em `/sys/class/rfkill/`** — que é o critério que
separa esta poda da perigosa.

Três coisas caíram junto por dependência, e voltaram ou foram ajustadas:

- o `enum acer_predator_v4_thermal_profile` e quatro declarações de estado
  (`last_non_turbo_profile`, `acer_predator_v4_max_perf`, …) moravam **entre**
  as tabelas e foram restaurados;
- `set_force_caps()` era `.callback` de quatro entradas DMI apagadas e ficou
  sem chamador — removida;
- a guarda `AMW0_GUID1 && !amw0_whitelist && quirk_unknown` virou
  `AMW0_GUID1 && quirk_unknown`: num driver de um modelo só, quirk desconhecido
  já basta para não carregar.

Compilar entre cada estágio foi o que tornou isso administrável — os três
primeiros builds falharam, cada um apontando exatamente o que tinha caído junto.

**O que NÃO foi podado, de propósito:** os parâmetros de módulo `enable_all`,
`predator_v4` e `nitro_v4`. Eles são inertes (nascem `false` e ninguém os
passa), mas estão entranhados na lógica de provisionamento de perfis —
`:1933`, `:2046`, `:2109`, `:4524`, `:4608`. Mexer neles é alterar código que
roda, e merece mudança própria, não carona nesta.

### Podar os subsistemas: risco alto, e é o que está bloqueado

Remover o **código** por trás de `WIRELESS`, `BLUETOOTH`, hotkeys ou `hwmon` é
outra coisa. Essas capabilities chegam em runtime, então nenhuma leitura da
tabela de quirks diz se são usadas.

Uma versão anterior deste documento deduziu que elas seriam código morto porque
o quirk não as liga. **A medição refutou**, e o erro teria arrancado o controle
por hardware do wifi e do bluetooth — sem que nada acusasse, porque os seis
atributos do `nitro_sense` continuariam presentes.

O passo zero foi feito em 2026-09-11: `acer_dump_capabilities()` imprime o
bitmask real no carregamento. **O corte de subsistema continua pendente**, mas
agora tem critério: medir antes, medir depois, e exigir que o número não mude.

## 6b. Por que não usar o `acer_wmi` nativo do kernel

A pergunta certa a fazer sobre qualquer fork de driver, e a resposta não é
"o nativo não serve" — é mais matizada que isso.

**O que o `acer_wmi` do kernel já faz**, medido extraindo símbolos do módulo
instalado (`/lib/modules/<kver>/kernel/drivers/platform/x86/acer-wmi.ko.zst`):

| | |
|---|---|
| perfis térmicos | ✅ `devm_platform_profile_register`, `acer_predator_v4_platform_profile_get/set` |
| leitura de ventoinha e temperatura | ✅ `acer_wmi_hwmon_init`, `ACER_WMID_SENSOR_CPU/GPU_FAN_SPEED` |
| rfkill, backlight, teclas | ✅ |

Não é um driver pobre. **Troca de perfil e telemetria já vêm do kernel** — e
este projeto as reimplementa.

**O que ele não faz.** Dos nove atributos de controle, expõe **zero**:

```
fan_speed  battery_limiter  usb_charging  backlight_timeout
battery_calibration  boot_animation_sound  lcd_override
nitro_sense  predator_sense          →  0 de 9
```

Ele **lê** a rotação da ventoinha; não a **define**. Não tem limitador de
bateria nem calibração. E não reconhece o ANV15-52: zero aliases DMI com `ANV`,
sendo o `AN515-58` o único Nitro na tabela dele.

**A decisão:** manter o fork, porque os cinco atributos em uso aqui —
`fan_speed`, `battery_limiter`, `usb_charging`, `backlight_timeout`,
`battery_calibration` — só existem nele. É exatamente o conjunto que motiva o
projeto.

**A consequência que vale encarar:** há duplicação real. Perfil térmico e
telemetria são funcionalidade que o kernel já entrega e o fork refaz. Se o
mainline ganhar os atributos de controle, o fork perde a razão de ser.

E o blacklist do `acer_wmi` não é preferência: os dois disputam os mesmos GUIDs
WMI, e sem ele o nativo ganha a corrida no boot — o `nexus_sense` carrega e
nunca vincula.

Ver [estado.md](estado.md), "Projeto futuro", para o caminho que encerraria o
fork.

## 7. A versão do driver vem do fonte, nunca cravada

**Decisão:** `driver_version()` deriva de `DRIVER_VERSION` no `.c`.
**Descartado:** cravar o número no instalador — uma versão anterior repetia
`25.701` em oito lugares e passaria a operar no pacote errado assim que o
número subisse.

**Dois espaços de versão, de propósito:**

| | o quê |
|---|---|
| `v1.0.0` — tag, `pyproject`, `__version__`, `SCRIPT_VERSION` | o projeto |
| `DRIVER_VERSION` `25.701` | o módulo |

Alinhá-los obrigaria a re-registrar o DKMS (`/usr/src/nexus_sense-25.701`,
`/var/lib/dkms/nexus_sense/25.701/`) por ganho cosmético, com risco de registro
órfão — ver armadilha 6.

## 8. Os testes vivem fora de `driver/` — e a razão original já morreu

**A razão era:** a próxima release do upstream mandaria sobrescrever `driver/`,
e a suíte precisava existir justamente aí para dizer o que quebrou.

**Essa razão acabou em 2026-09-11**, quando o projeto deixou de rastrear o
upstream. Não há mais sobrescrita a sobreviver.

Os testes continuam em `tests/` porque movê-los não traria ganho nenhum e
quebraria caminhos em 17 arquivos. Mas se você encontrar esse layout e se
perguntar por quê, a resposta hoje é **inércia justificada**, não desenho — o
motivo que o criou não existe mais.

## 9. A raiz do `sysfs` é um parâmetro, não um caminho fixo

**Escolha:** `/sys` codificado no acesso **vs.** raiz injetável.
**Decidido:** injetável.

Com o caminho fixo, testar exigiria um laptop Acer com o módulo carregado e
root. Com a raiz como parâmetro, os testes montam uma árvore falsa em `tmp_path`
— e as 333 suítes Python rodam **em qualquer máquina, sem hardware e sem root**.

O preço é uma indireção em todo acesso. Valeu: é o que torna a suíte executável
em CI e no seu laptop de trabalho.

A árvore falsa desloca o índice do `hwmon` de propósito (0, 3, 11, 40) para
provar que o código de produção nunca depende do número.

## 10. O scroll pula o degrau barrado em vez de parar nele

**Escolha:** andar na escada canônica de perfis **vs.** andar só nos disponíveis.
**Decidido:** só nos disponíveis.

O motivo é que a lista permitida **tem buraco no meio**. Medido com o cabo fora:
o driver recusa `quiet`, `balanced-performance` e `performance` na bateria
(`-EOPNOTSUPP`), e o `quiet` fica *entre dois válidos*. Andar na escada canônica
faria a roda parar num degrau que falharia ao ser escrito.

**Decisão relacionada:** quem devolve o perfil ao religar o cabo é o agente. O
driver não tem notificador de fonte de energia, e o daemon antigo derrubava o
perfil ao desconectar e **nunca devolvia**.

## 11. A tradução de erro mora numa camada só

**Escolha:** cada widget interpreta `errno` **vs.** uma camada traduz e a
interface só exibe.
**Decidido:** camada única. Nenhum widget olha `errno`.

As três causas que acontecem de verdade — sem permissão, recusado na bateria,
valor inválido — viram frase em pt-BR num lugar só.

**Sub-decisão que parece inconsistente e não é:** a frase de permissão funde
dois casos de propósito (fora do grupo / dentro dele numa sessão que não o
herdou), porque para quem está usando o sintoma é o mesmo. Mas o **Diagnóstico**
os separa, porque ali a pergunta é "o que eu faço agora?" — e as respostas são
diferentes: entrar no grupo ou relogar.

Para isso o `in_group` lê `/etc/group`, não `os.getgroups()`. Só a sessão
colapsava os dois casos, e a tela mandava rodar `usermod` de novo para quem já
estava no grupo — conselho que não resolve nada quando o que falta é relogar.

## 12. O ícone da bandeja não é a marca

**Escolha:** usar a marca completa nos dois ícones **vs.** desenhar um símbolo
próprio para a bandeja.
**Decidido:** símbolo próprio — só o N.

A 22 px cada aresta da rede ocupa menos de um pixel, e o resultado é cinza
embaralhado. **Em PNG e em SVG igualmente** — o que descarta a hipótese de que
vetor resolveria. O peso do SVG de quatro candidatos (17,0 / 25,5 / 15,9 /
3,4 KB) mede quanto contorno cada um carrega, e a ordem é exatamente a da
ilegibilidade.

**Escolha:** tirar o hexágono por limiar de cor **vs.** por componente conexo.
**Decidido:** componente conexo — por limiar, as hastes têm a mesma densidade
das arestas do N e sobrariam como quatro setas.

**Escolha:** manter o ciano do desenho original **vs.** trocar a cor da marca.
**Decidido:** trocar, por contraste medido. O ciano dá 7,46 no tema escuro mas
**1,99 no claro**, abaixo do mínimo WCAG de 3,0. O `#4A78C8` dá 3,79 e 3,93 —
praticamente igual nos dois temas.

O colorido original fica em `packaging/icons/src/` como referência: com 19.074
cores distintas ele não vetoriza.

## 13. A cor da segunda série do gráfico passou por daltonismo

**Escolha:** violeta, ciano ou rosa para a segunda temperatura.
**Decidido:** rosa, por validação e não por gosto. Violeta **reprova com dE 2,9
em protanopia**; o rosa passa com 9,8.

A proximidade do rosa com o vermelho semântico foi avaliada e aceita: os dois
nunca aparecem juntos.

**Regra geral:** cor nunca vem sozinha. Há legenda, rótulo direto na ponta e
ponto colorido no título do cartão — quem não distingue as cores ainda
identifica a série.

**Escolha:** a pele segue o nome do tema **vs.** a luminância da paleta.
**Decidido:** luminância. Nome de tema é texto livre e quebra na primeira
distribuição que renomeie o seu.

**Escolha:** cores do eixo vindas da paleta do Qt **vs.** dos tokens do sistema
de design.
**Decidido:** tokens. `palette().mid()` no Breeze escuro é `#1c1f21`,
praticamente o fundo do cartão — o eixo ficava **invisível**, e nenhum teste
acusava porque `grab()` não é nulo quando o texto some no fundo.

## 14. O poller para quando a janela some

**Escolha:** sondar sempre **vs.** sondar só com a janela visível.
**Decidido:** só visível — liga no `showEvent`, para no `hideEvent`.

Um painel que continua sondando escondido gasta bateria para não mostrar nada. E
no caso da dGPU é pior: a mantém acordada.

**Decisão separada para a bandeja:** relógio próprio, mais lento, lendo **só**
`hwmon` — 0,23 ms a cada 5 s, sem nunca acordar a GPU. Um teste falha de
propósito se alguém chamar `read_gpu` de lá.

## 15. Instância única pelo barramento, não por arquivo de trava

**Escolha:** arquivo de trava em disco **vs.** nome bem-conhecido no DBus.
**Decidido:** DBus.

O problema: o nome do serviço do SNI levava o PID, então cada execução
registrava um item novo — reabrir o app deixava **dois ícones** na bandeja, e o
antigo podia sobreviver ao processo virando ícone morto.

Por que DBus e não arquivo: **não há trava a limpar**. Se o processo morre, o
barramento libera o nome sozinho. Arquivo de trava exige limpeza no crash, e
todo esquema de limpeza tem o caso em que falha.

Quem registra o nome é a instância dona; quem não consegue pede a ela que
apareça e sai.

## 16. `StatusNotifierItem` escrito à mão

**Escolha:** `QSystemTrayIcon` **vs.** implementar SNI sobre QtDBus.
**Decidido:** SNI próprio — e a razão é uma só: **`QSystemTrayIcon` não entrega
evento de roda.** Sem scroll não há troca de perfil pelo ícone, que é o gesto
principal.

O custo é falar DBus à mão. Contido assim: as decisões — o scroll que pula o
degrau barrado, o texto do tooltip, o nome do ícone — ficam em **funções puras
fora do objeto DBus**, testáveis sem barramento, sem host e sem sessão gráfica.

Há fallback com a mesma superfície, então trocar um pelo outro não muda o
controlador.

## 17. O instalador nunca sobrescreve escolha do usuário

**Escolha:** o instalador cria o atalho sempre **vs.** só quando não existe.
**Decidido:** só quando não existe. E o lado espelho: a desinstalação só remove
se o valor for **exatamente** o que o instalador escreve (`Launch (1)`).

Sem o segundo lado, desinstalar deixaria atalho vivo apontando para o `.desktop`
recém-apagado — o problema do ícone morto em outra forma. Com ele, um atalho que
você escolheu sobrevive à desinstalação.

**Escolha:** tratar todos os ambientes **vs.** só o verificado.
**Decidido:** só o KDE Plasma automaticamente; os outros recebem instruções.
Adivinhar o formato de configuração de outro ambiente a partir de um instalador
rodando como root seria pior que não fazer.

## 18. O que foi descartado, e por quê

| descartado | motivo |
|---|---|
| forçar perfis no Diagnóstico | o firmware não anuncia o quinto perfil (bitmap `0x53`), e `nitro_v4` troca o conjunto de quirks |
| informe de RGB na página Teclado | nota de desenvolvimento vazando para a interface; o modelo tem LED de cor única |
| botões "Check for Updates" e "Issue/Feedback" | apontavam para o GitHub do PXDiv, que não é a base deste projeto |
| caminho GNOME no instalador | a máquina roda KDE; o resto recebe instruções |
| `linuwu_sense.target` | existia na versão pessoal, mas nenhuma unit o referenciava |
| manifesto de binários e verificação sha256 | perdeu o objeto quando GUI e daemon viraram fonte |

---

## Lacuna conhecida

**O modo de desempenho máximo não tem razão registrada.** Os commits
`c475ec7`, `57fe3b9`, `e45daa7` e `22121bb` (2026-09-06/07) entraram só com
linha de assunto, sem corpo. O que ele faz está no código e em
[interface.md](interface.md); *por que* foi desenhado assim, e o que foi
descartado no caminho, não foi gravado em lugar nenhum.

Se a decisão precisar ser revisitada, ela terá de ser reconstruída lendo
`src/nexus_sense/maximum.py` e `powermizer.py`.
