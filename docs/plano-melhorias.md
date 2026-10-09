# Plano de melhorias — 2026-10

**Estado: aprovado em 2026-10-09.** As decisões estão na seção 7.

Origem: avaliação de 2026-10-09 sobre o `master` em `8e80ec2` (v1.1.9). Tudo
que este plano manda consertar foi lido no código; o que foi **medido** está
marcado, e o que é só leitura também. As linhas citadas são desse commit e
andam assim que a primeira edição entrar — o nome da função é a referência
que dura.

---

## 1. Como executar

**Uma etapa por sessão.** Três razões, nenhuma de gosto:

1. As etapas 2 e 3 terminam em reinício, e reinício encerra a sessão de
   qualquer jeito.
2. Cada etapa tem ramo, portão e merge próprios. Se a etapa 2 reprovar no
   portão, a 1 já está em `master` e não fica refém dela.
3. Uma sessão nova lê este arquivo e `armadilhas.md` e começa do zero, sem
   depender de memória de conversa.

A etapa 1 é só Python e pode começar na mesma sessão em que este plano for
aprovado.

### Ao abrir cada sessão

1. Ler [armadilhas.md](armadilhas.md) inteiro e a etapa da vez neste arquivo.
2. Criar o ramo a partir de `master` limpo.
3. **Capturar o baseline antes de tocar em qualquer coisa**, num arquivo do
   scratchpad: `python3 -m pytest -q`, `./tests/run-all.sh`, e as medições que
   a etapa lista. O critério de aceite é "igual ao baseline, mais o que a
   etapa promete" — nomes das falhas, não só a contagem.

### Dentro da etapa

- Execução inline, um ponto de conferência por tarefa. Sem subagentes.
- Cada tarefa: o teste falha primeiro pelo motivo previsto, depois passa.
- Um commit por tarefa.
- **Parar e pedir confirmação** antes de: qualquer comando com root, recarga
  do módulo, reinstalação, reinício.
- Root por `pkexec`, entrando de caminho absoluto, agrupado em poucas chamadas.
- Nunca `rfkill block` no `acer-wireless`. Para exercitar rfkill, bluetooth.

### Ao fechar a etapa

Três camadas, e merge `--no-ff` só se as três passarem:

| camada | o que prova |
|---|---|
| estática | sintaxe, nenhuma referência órfã, `W=1` limpo quando há driver |
| suítes contra o baseline | mesmos números e mesmas falhas nominais, mais os testes novos |
| ensaio na máquina | o que a etapa lista em "Portão" |

A versão sobe no merge, nos três lugares do projeto (`SCRIPT_VERSION`,
`pyproject.toml`, `__version__`). `DRIVER_VERSION` não se mexe — decisão 7.
`estado.md` recebe o que fechou e o que a medição refutou.

---

## 2. Baseline medido em 2026-10-09

Máquina na tomada, modo máximo ligado, carga alta (load ~12) no momento dos
tempos avulsos. O número do agente é acumulado de 4,9 h e não sofre disso.

| | medido |
|---|---|
| suíte Python | 333 passaram, 5,9 s |
| suíte shell | não rodada nesta data; último registro 16 passam, 2 pulam |
| agente, CPU da unit | 1373 s em 17 496 s — **7,8% de um núcleo** |
| agente, CPU do processo | 105 s; o resto são os `powerprofilesctl get` |
| bandeja, CPU | 31 s em 17 496 s — 0,18% |
| `powerprofilesctl get` | 135 ms |
| `busctl get-property … ActiveProfile` | 3,9 ms |
| leitura do `profile` (1 WMI) | 4,7 ms |
| `read_basic` / `read_state` | 6,2 ms / 27 ms |
| `nvidia-smi` | 34 ms |
| varredura do PCI (`nvidia_device`) | 1,0 ms |
| `fan_rpm` (2 WMI) | 0,34 ms |

Falta medir, e a etapa 1 mede antes de mexer: CPU da janela por 30 s, num
arnês que a instancia fora da tela (`QT_QPA_PLATFORM=offscreen`) sobre o sysfs
real, contando também os filhos — é ali que o `nvidia-smi` aparece.

---

## 3. Etapa 1 — Python: agente e janela

**Fechada em 2026-10-09, v1.2.0.** O resultado medido e o que a execução
refutou estão em [estado.md](estado.md).

Ramo `melhorias/1-python`. Sem root até o ensaio final.

| # | o quê | onde | teste que falha primeiro |
|---|---|---|---|
| 1.1 | PPD por `busctl` em vez de `powerprofilesctl`: ler, escrever, e a lista do Diagnóstico | `maximum.py` (`ppd_profile`, `enforce_runtime`), `session.py` (`ppd_state`) | o `Runtime` de `test_maximum.py` passa a exigir o argv novo |
| 1.2 | uma leitura do perfil por passada: o `tick` entrega o que leu (ou escreveu) ao `_reconcile_maximum` | `agent.py` | espião contando leituras do `profile` numa passada em modo máximo: 2 → 1 |
| 1.3 | aviso só quando o conjunto de erros muda, e uma linha quando some | `agent.py` (`_reconcile_maximum`) | 10 passadas com PPD ausente geram 1 linha, não 10 |
| 1.4 | agente não morre sem o driver: fica vivo, avisa uma vez, retoma quando o módulo aparece (decisão D1) | `__main__.py`, `agent.py` | `main` com raiz vazia não devolve 1; a árvore aparece e a passada seguinte funciona |
| 1.5 | gravação atômica do `config.toml`: temporário no mesmo diretório + `os.replace` | `config.py` (`save`) | leitor e escritor concorrentes por 0,5 s: hoje 57% de leituras erradas, depois zero |
| 1.6 | religar o cabo abaixo de 40% não perde o perfil guardado: `saved_ac_profile` só é limpo depois que a escrita passa, e a devolução é tentada de novo enquanto pendente | `agent.py` (`_on_plug`, `tick`); frase em `device.py` (`_traduz`) | sysfs falso recusando com `EOPNOTSUPP` na tomada: o perfil guardado sobrevive e volta quando a recusa cessa |
| 1.7 | PPD na bateria — **medir antes**, ver decisão D2 | `maximum.py` (`enforce_runtime`), `agent.py` | depende da medição |
| 1.8 | sondagem a 1 Hz em tudo (decisão D3): `INTERVALO_PADRAO` de 100 para 1000 ms, a animação do gráfico acompanha o intervalo, e o histórico passa de 12 s para 2 min; sai `acer_temps` (lida e nunca usada) e o BDF da GPU é guardado em vez de varrer o PCI a cada passada | `gui/poller.py`, `gui/graph.py`, `telemetry.py`, `tray/controller.py` | o intervalo padrão é 1000; duas passadas varrem o PCI uma vez; `Sample` não tem `acer_temps` |
| 1.9 | uma atualização por ação, e o cursor de ventoinha escreve com atraso de 150 ms em vez de a cada passo | `gui/app.py` (`_connect_state`), `gui/window.py`, `pages/performance.py` | um `changed` produz um `read_state`; arrasto de 20 passos produz 1 escrita |
| ~~1.10~~ | **retirada.** As checagens do Diagnóstico rodariam só ao mostrar a página | `pages/diagnostics.py` | perdeu o objeto: depois da 1.1 a checagem inteira custa 12 ms, medido, contra os ~270 ms que a justificavam |
| 1.11 | limpeza: ramos de `nvidia-settings` mortos nos três `Runtime` de teste | `test_maximum.py`, `test_agent_loop.py`, `test_leituras_wmi.py` | feita dentro da 1.1, que reescreveu os três |

Notas de execução:

- **1.1 começa medindo**, não escrevendo: qual nome responde nesta máquina
  (`org.freedesktop.UPower.PowerProfiles` ou `net.hadess.PowerProfiles`), o
  formato de `--json=short` para `ActiveProfile` e `Profiles`, e se
  `set-property` passa sem senha a partir da unit de usuário. Para testar a
  escrita, escrever o valor que já está lá.
- **1.6 vem da medição de 2026-09-30**, que não chegou ao `armadilhas.md`: o
  firmware responde "fora da tomada" enquanto a bateria está abaixo de 40%,
  mesmo com `ACAD/online=1`. Esta tarefa escreve a armadilha 27.
- **1.7 foi demonstrada por teste, não por cabo.** Com o barramento simulado,
  o agente antigo desfazia a escolha em uma passada — a lógica é determinística
  e não precisava do hardware para aparecer. A conferência com o cabo na mão
  fica no portão: tirar o cabo, `powerprofilesctl set power-saver`, esperar 5 s,
  `powerprofilesctl get`. Tem de continuar `power-saver`.

### Portão da etapa 1

Ensaio na máquina, depois de instalar com
`pkexec /bin/bash -c "cd /home/brunodobner/Claude/Nitrosense; source ./setup.sh; install_nexus_sense"`
e reiniciar agente e bandeja:

1. `diff -rq --exclude=__pycache__ src/nexus_sense /usr/lib/nexus-sense/nexus_sense` vazio.
2. CPU da unit do agente por 10 min, modo máximo, na tomada: de 7,8% para
   **abaixo de 1%**.
3. Journal do agente confirma `GPUPowerMizerMode=1` como antes.
4. CPU da janela no arnês de 30 s: menor que o baseline capturado no início
   da etapa.
5. Com o cabo na mão: tirar, conferir queda para `balanced`; religar, conferir
   volta — o mesmo ensaio da virada. E o teste da 1.7.
6. Gesto humano: arrastar o cursor de ventoinha e clicar no trilho, os dois
   respondem; e o Painel atualizando uma vez por segundo, com o gráfico
   cobrindo dois minutos.

---

## 4. Etapa 2 — driver

Ramo `melhorias/2-driver`. Sessão própria.

| # | o quê | onde | como se prova |
|---|---|---|---|
| 2.1 | `NULL` deref no caminho de erro: testa `!obj` e em seguida imprime `obj->buffer.length` | `battery_health_query`, `battery_health_set` | teste shell que reprova o padrão; não há como provocar no hardware |
| 2.2 | `sscanf("%hhd")` em `u8` aceita "256" como 0 — trocar por `kstrtou8` | os quatro `_store` de bateria, USB e backlight | depois do conserto, escrever `256`: `EINVAL` e valor inalterado |
| 2.3 | `fan_speed_store` e `acer_thermal_profile_change` sob `acer_op_lock` | idem | 8 escritores paralelos de ventoinha e perfil, estado final coerente, zero erro no journal |
| 2.4 | estado lido para um temporário, validado (ventoinha 0–100, perfil entre os anunciados) e só então adotado | `acer_predator_state_load` | arquivo plantado de 12 bytes, e outro com ventoinha negativa: os dois caem nos padrões e o log diz |
| 2.5 | opcional — ver decisão D6: rótulos no hwmon, `sysfs_emit`, código comentado fora, `pr_info` do caminho de ventoinha para `pr_debug` | vários | bitmask idêntico |

Cuidados que não são óbvios:

- **2.3 tem uma ordem de trava a respeitar.** O núcleo do `platform_profile`
  toma a trava dele e chama `profile_set`, que toma `acer_op_lock`. Em
  `acer_thermal_profile_change`, soltar `acer_op_lock` **antes** de
  `platform_profile_notify` — senão a ordem inverte e trava. A trava entra no
  `_store`, não dentro de `acer_set_fan_speed`, que o `profile_set` já chama
  com ela tomada.
- **2.2 só se testa depois do conserto.** Antes dele, escrever `256` muda a
  configuração de verdade.
- **2.4 planta arquivo em `/etc/predator_state`**: cópia do original antes, e
  `trap` devolvendo, inclusive se o ensaio falhar no meio.
- Parar agente e bandeja antes de recarregar o módulo; religar depois.

### Portão da etapa 2

O mesmo da poda: `W=1` limpo sob Clang, reinstalação por DKMS, recarga, e

```
capability bitmask: 0x00002c26
perfis      low-power quiet balanced balanced-performance
atributos   os seis, 664 root:nexus_sense
rfkill      bluetooth bloqueia e desbloqueia
hwmon       presente
estado      sobrevive à recarga
estresse    16 leitores x 200 leituras, zero "Failed to get profile"
```

Depois, reinício. **A partida a frio se confere no começo da sessão
seguinte**, e só então a etapa se dá por fechada em `estado.md`.

---

## 5. Etapa 3 — instalador e empacotamento

Ramo `melhorias/3-instalador`. Sessão própria.

| # | o quê | onde | teste |
|---|---|---|---|
| 3.1 | lançadores com `python3 -P`: hoje um `tomli_w.py` no diretório corrente é executado no lugar do verdadeiro, e agente e autostart rodam em `$HOME` (confirmado em 2026-10-09) | `install_nexus_sense` | shell: módulo plantado no diretório corrente não é importado |
| 3.2 | desinstalação remove o que a instalação põe: lançadores, pacote, regra udev, unit do agente e o `--global enable`, `.desktop`, ícones — ver decisão D5 para grupo | `comprehensive_cleanup` | `test-uninstall.sh` cobra cada caminho |
| 3.3 | sai o serviço root que lê o teclado — ver decisão D4 | `configure_nitro_button`, `install_nitro_service`, `packaging/scripts/nitro-key-detection.sh` | `test-nitro-key.sh` e `test-arvore.sh` reescritos; a limpeza do serviço antigo **fica** |
| 3.4 | `detect_desktop_user` consulta `PKEXEC_UID` e recusa uid abaixo de 1000 | idem | shell, com a variável plantada |
| 3.5 | dependências: sai `nvidia-settings`, que o código não usa mais; headers pelo `pkgbase` de cada kernel instalado, não `linux-headers` genérico (armadilha 22b) | `runtime_dependencies_ok`, `install_runtime_deps`, `install_build_deps` | `test-setup-deps.sh` |
| 3.6 | regra udev também em `bind`, emitido depois que o `probe` termina — hoje ela corre contra a criação dos atributos e ganha por margem | `packaging/udev/60-nexus-sense.rules` | `test-permissoes.sh`; e na máquina, recarga do módulo 10 vezes com permissão conferida a cada uma |

### Portão da etapa 3

`./tests/run-all.sh` com e sem root contra o baseline. Depois, na máquina, numa
chamada só de root: `comprehensive_cleanup`, a varredura da armadilha 8
(esperado: nada), e a instalação completa. Antes de reiniciar, conferir o que
a armadilha 21 manda: autostart e hwdb do botão N no lugar. Reinício, e na
sessão seguinte: módulo, permissões, agente, bandeja subindo sozinha, botão N.

---

## 6. Etapa 4 — o que sobra, cada item independente

Nada aqui bloqueia as três primeiras, e cada um pode ser recusado sozinho.

- **CI** — ver decisão D7: pytest e shellcheck a cada push, e o módulo
  compilado uma vez por semana contra os headers atuais do Arch. Essa última
  parte avisa da quebra de API antes do pacman avisar (armadilha 26).
- **Temperatura da GPU pelo EC.** Medido: `temp2` do acer deu 69 °C com o
  `nvidia-smi` em 65. Falta medir o que ele devolve com a placa adormecida. Se
  servir, a temperatura dispensa o `nvidia-smi`.
- **A janela impede a dGPU de dormir?** Hipótese, não medida: `nvidia-smi` em
  laço enquanto ela está ativa nunca a deixa ociosa. Medir `runtime_status`
  por 60 s com a janela aberta e fechada, fora do modo máximo.
- **SNI re-registra** quando o `StatusNotifierWatcher` reinicia.
- **Rede de segurança térmica** para ventoinha manual baixa com CPU quente.
  Precisa de brainstorm próprio: não se sabe o que o EC já faz sozinho.

Fora do plano de propósito: alinhar `DRIVER_VERSION` ao projeto (decisão 7 já
descartou), pré-compilar bytecode (medido: 8 ms na partida), mover a
persistência de estado do kernel para o espaço de usuário (mudança de desenho,
não conserto).

---

## 7. Decisões

Uma etapa por sessão, a etapa 1 começando na sessão do plano — confirmado pelo
usuário em 2026-10-09.

D3 é gosto visual e foi o usuário quem decidiu. As demais foram fechadas por
verificação, não por pergunta: eram técnicas, e a máquina respondia.

| | decisão | o que a sustenta |
|---|---|---|
| D1 | sem o driver, o agente **fica vivo**, avisa uma vez e segue no mesmo intervalo | laço reproduzido numa unit descartável com as mesmas duas linhas (`Restart=always`, `RestartSec=3`) e raiz vazia: 8 reinícios em 26 s, nunca atinge o limite. E 50 passadas do `tick` sem driver: nenhuma exceção, 0,15 ms cada; a árvore aparece e o mesmo processo retoma. Só Python muda; a unit fica como está |
| D2 | na bateria, o PPD guardado é devolvido **uma vez** na troca; depois vale o que o usuário escolher | "suspenso na bateria" não é "preso". Depende de a medição da 1.7 confirmar o defeito |
| D3 | a janela atualiza **tudo uma vez por segundo**, GPU inclusive; o gráfico cobre 2 min em vez de 12 s | escolha do usuário em 2026-10-09, contra a recomendação de manter 10 Hz e espaçar só a GPU |
| D4 | o serviço root de tecla **sai** | nesta máquina ele nunca foi instalado: sem unit, sem script em `/usr/local/bin`, sem `/etc/damx`. O botão já abre o app por hwdb (`KEYBOARD_KEY_f5=prog1`) e atalho do KDE (`Launch (1)`) |
| D5 | a desinstalação apaga o grupo `nexus_sense`; `~/.config/nexus-sense` **fica** | o grupo é do instalador; a configuração é escolha do usuário (decisão 17) |
| D6 | a limpeza do driver (2.5) **entra**, por último e em commit separado; sai se o portão reprovar | — |
| D7 | a etapa 4 **tem CI** | repositório privado com Actions habilitado (`gh api …/actions/permissions`) |
