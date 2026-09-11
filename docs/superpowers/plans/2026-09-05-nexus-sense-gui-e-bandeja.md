# Nexus Sense — GUI e bandeja — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir a janela PySide6, a bandeja `StatusNotifierItem` e o helper com `pkexec`, e então fazer a virada que remove o `damx-daemon` e a GUI binária.

**Architecture:** Sobre o núcleo do plano 1 (`Sysfs`, `model`, `telemetry`, `config`, `agent`) entram duas camadas. A primeira é `device.py`: um instantâneo do aparelho e os seis controles graváveis, sem Qt e testável contra a árvore de mentira. A segunda é a interface, que só lê esse instantâneo e chama esses controles — nenhum widget abre caminho, valida valor ou interpreta `errno`. A bandeja é um `StatusNotifierItem` próprio sobre `QtDBus`, com toda a decisão (o que o scroll faz, o que o tooltip diz, qual ícone usar) em funções puras fora do objeto DBus.

**Tech Stack:** Python 3.14, PySide6 6.11.2 e Qt 6.11.2 (medidos nesta máquina), `QtDBus`, `pytest` e `pytest-qt` (`extra/python-pytest-qt`), `polkit`. Sem dependência nova além dessas.

**Spec:** `docs/superpowers/specs/2026-09-05-nexus-sense-gui-agente-design.md`

**Plano antecessor:** `docs/superpowers/plans/2026-09-05-nexus-sense-nucleo-e-agente.md`, concluído — as dez tarefas dele estão em `master`.

## Global Constraints

Valem para todas as tarefas. Valores copiados da spec e do plano 1.

- **Identificadores públicos em inglês, variáveis locais e comentários em português, textos de usuário em pt-BR.** É a convenção do código já escrito: `model.available()` e `model.neighbour()` têm nome em inglês, e dentro deles as locais são `anunciados`, `opcoes`, `destino`.
- **Nenhum acesso a caminho absoluto fora de `Sysfs`.** Nenhum widget abre arquivo. Spec §4.3.
- **hwmon nunca por índice.** Já resolvido em `telemetry.py`; a interface só chama as funções de lá. Spec §10.1, armadilha 19.
- **Nunca chamar `nvidia-smi` com a GPU adormecida.** Já resolvido em `telemetry.read_gpu`. Além disso: **a telemetria só roda com a janela aberta** — fechou, para. A bandeja usa apenas hwmon, que é barato. O agente não lê sensor nenhum. Spec §10.2, armadilha 20.
- **Os seis atributos graváveis** (spec §2.6), e nenhum outro:
  ```
  <acer-wmi>/nitro_sense/{fan_speed,battery_limiter,usb_charging,
                          backlight_timeout,battery_calibration}
  <acer-wmi>/platform-profile/platform-profile-0/profile
  ```
  Grupo `nexus_sense`, modo `664`. O atributo `version` continua `444`.
- **Perfis recusados na bateria pelo driver:** `quiet`, `balanced-performance`, `performance` (`linuwu_sense.c:2317`). O alcance permitido **não é contíguo**. Spec §2.8.
- **Formato do `fan_speed`:** `"%d,%d"`, ambos inteiros de 0 a 100. **Níveis de `usb_charging`:** exatamente `0`, `10`, `20`, `30`. Já validados em `model.py`.
- **Os quatro perfis ficam sempre nas mesmas posições.** O que muda com a fonte é o estado, não a forma. Spec §6.2, decisão D7.
- **Uma seção sem nenhum controle não aparece na barra lateral.** Não se exibe seção vazia. Spec §6.4.
- **Nenhum estado degradado vira exceção na tela.** Cada um tem lugar fixo e uma frase que diz o que fazer. Spec §9.
- **Nomes** conforme spec §12.1. O módulo do kernel ainda se chama `linuwu_sense` nesta fase; `Sysfs.module_loaded()` já aceita os dois nomes.
- **Qt sem tela nos testes:** `tests/python/conftest.py` define `QT_QPA_PLATFORM=offscreen` antes de qualquer import de Qt. A suíte continua rodando sem hardware, sem root e sem sessão gráfica.
- **A virada é a última tarefa, e só ela desliga coisas.** Até a Task 12 o `damx-daemon` continua no ar e o agente continua com `auto_switch = false`.

---

## Estrutura de arquivos

| arquivo | responsabilidade |
|---|---|
| `src/nexus_sense/device.py` | instantâneo do aparelho e os seis controles graváveis; traduz `errno` para frase |
| `src/nexus_sense/privileged.py` | fala com o helper por `pkexec` |
| `src/nexus_sense/gui/app.py` | monta `QApplication`, janela e bandeja; ponto de entrada `main()` |
| `src/nexus_sense/gui/window.py` | barra lateral, páginas empilhadas, rodapé do agente |
| `src/nexus_sense/gui/poller.py` | `QTimer` da telemetria; para quando a janela some |
| `src/nexus_sense/gui/graph.py` | gráfico de temperatura com eixo em °C |
| `src/nexus_sense/gui/pages/dashboard.py` | Painel |
| `src/nexus_sense/gui/pages/performance.py` | Desempenho |
| `src/nexus_sense/gui/pages/battery.py` | Bateria |
| `src/nexus_sense/gui/pages/keyboard.py` | Teclado |
| `src/nexus_sense/gui/pages/diagnostics.py` | Diagnóstico |
| `src/nexus_sense/tray/sni.py` | `StatusNotifierItem` sobre `QtDBus` + as decisões puras |
| `src/nexus_sense/tray/fallback.py` | `QSystemTrayIcon`, quando não há host SNI |
| `src/nexus_sense/tray/__init__.py` | escolhe entre SNI, fallback e nenhuma bandeja |
| `packaging/nexus-sense-helper` | root por `pkexec`; conjunto fechado de operações |
| `packaging/com.nexussense.helper.policy` | regra polkit do helper |
| `packaging/nexus-sense.desktop` | lançador |
| `packaging/icons/gerar.sh` | ganha quatro variantes de bandeja, uma por perfil deste ANV15-52 |
| `docs/VERIFICACAO-MANUAL.md` | o que não é automatizável: SNI na bandeja e `pkexec` |
| `tests/python/test_*.py` | suíte sem hardware, agora com `pytest-qt` |
| `tests/test-instalacao-nexus.sh` | teste de shell do instalador |

Os testes em shell seguem o contrato do `tests/run-all.sh`: saída `0` passou, `2` pulou, `3` alvo ausente, qualquer outra falhou.

---

### Task 1: O instantâneo do aparelho

**Files:**
- Create: `src/nexus_sense/device.py`
- Test: `tests/python/test_device.py`

**Interfaces:**
- Consumes: `Sysfs` e `model` do plano 1.
- Produces:
  - `SENSE_ATTRS: tuple[str, ...]` — os cinco atributos do grupo `nitro_sense`
  - `DeviceState` — `NamedTuple` com `module_loaded: bool`, `on_ac: bool | None`, `profile: str | None`, `choices: tuple[str, ...]`, `available: tuple[str, ...]`, `features: frozenset[str]`, `writable: frozenset[str]`, `profile_writable: bool`, `fan_speed: tuple[int, int] | None`, `battery_limiter: bool | None`, `usb_charging: int | None`, `backlight_timeout: bool | None`, `battery_calibration: bool | None`, `driver_version: str | None`
  - `read_state(sysfs: Sysfs) -> DeviceState`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_device.py`:

```python
import os

import pytest

from nexus_sense.device import SENSE_ATTRS, read_state
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


def test_le_o_estado_inteiro_de_uma_arvore_completa(fake_root):
    e = read_state(Sysfs(fake_root))
    assert e.module_loaded is True
    assert e.on_ac is True
    assert e.profile == "balanced"
    assert e.choices == ("low-power", "quiet", "balanced", "balanced-performance")
    assert e.driver_version == "25.701"


def test_disponiveis_saem_do_modelo_e_nao_da_lista_crua(fake_root):
    """Na tomada os quatro anunciados passam."""
    e = read_state(Sysfs(fake_root))
    assert e.available == ("low-power", "quiet", "balanced", "balanced-performance")


def test_na_bateria_o_alcance_encolhe_e_nao_e_contiguo(tmp_path):
    """O 'quiet' fica entre dois permitidos e mesmo assim cai fora.
    Ver spec secao 2.8."""
    raiz = build_tree(tmp_path, on_ac=False)
    e = read_state(Sysfs(raiz))
    assert e.on_ac is False
    assert e.available == ("low-power", "balanced")


def test_le_os_cinco_controles_do_grupo_sense(fake_root):
    e = read_state(Sysfs(fake_root))
    assert e.fan_speed == (0, 0)
    assert e.battery_limiter is True
    assert e.usb_charging == 0
    assert e.backlight_timeout is False
    assert e.battery_calibration is False


def test_features_lista_o_que_existe_no_firmware(fake_root):
    assert read_state(Sysfs(fake_root)).features == frozenset(SENSE_ATTRS)


def test_atributo_ausente_sai_de_features_e_o_valor_e_none(tmp_path):
    """Numa maquina sem backlight_timeout a secao Teclado nao aparece.
    Ver spec secao 6.4."""
    raiz = build_tree(tmp_path)
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/backlight_timeout").unlink()
    e = read_state(Sysfs(raiz))
    assert "backlight_timeout" not in e.features
    assert e.backlight_timeout is None


def test_writable_reflete_a_permissao_de_verdade(fake_root):
    e = read_state(Sysfs(fake_root))
    assert "fan_speed" in e.writable
    assert e.profile_writable is True


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignora a permissão do arquivo")
def test_sem_permissao_o_atributo_sai_de_writable_mas_fica_em_features(fake_root):
    """E a diferenca entre 'nao existe' e 'existe e voce nao pode escrever'.
    A tela diz coisas diferentes nos dois casos. Ver spec secao 9."""
    alvo = fake_root / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed"
    alvo.chmod(0o444)
    try:
        e = read_state(Sysfs(fake_root))
    finally:
        alvo.chmod(0o644)
    assert "fan_speed" in e.features
    assert "fan_speed" not in e.writable


def test_arvore_vazia_nao_explode(tmp_path):
    """Modulo descarregado: a janela mostra a tela unica com o comando
    para carregar, e para isso precisa de um estado, nao de excecao."""
    e = read_state(Sysfs(tmp_path))
    assert e.module_loaded is False
    assert e.profile is None
    assert e.choices == ()
    assert e.available == ()
    assert e.features == frozenset()


def test_predator_sense_serve_igual(tmp_path):
    raiz = build_tree(tmp_path, sense="predator_sense")
    e = read_state(Sysfs(raiz))
    assert e.features == frozenset(SENSE_ATTRS)
    assert e.battery_limiter is True


def test_valor_ilegivel_vira_none_e_nao_excecao(tmp_path):
    raiz = build_tree(tmp_path)
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text("lixo\n")
    assert read_state(Sysfs(raiz)).fan_speed is None
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_device.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.device'`.

- [ ] **Step 3: Implementar**

`src/nexus_sense/device.py`:

```python
"""O instantaneo do aparelho, e os seis controles graveis.

Esta camada existe para que nenhum widget precise saber o que e sysfs.
A interface le um DeviceState e chama Controls; nao abre caminho, nao
valida valor e nao interpreta errno.

Distincao que a tela usa o tempo todo: `features` diz o que existe no
firmware, `writable` diz o que voce pode escrever agora. Um atributo que
existe e nao e gravavel produz uma frase diferente de um que nao existe.
Ver spec secao 9.
"""

import os
from typing import NamedTuple

from . import model

# Os cinco do grupo nitro_sense/predator_sense. O sexto gravavel e o
# profile, que mora sob platform-profile e por isso nao entra aqui.
SENSE_ATTRS = (
    "fan_speed",
    "battery_limiter",
    "usb_charging",
    "backlight_timeout",
    "battery_calibration",
)


class DeviceState(NamedTuple):
    module_loaded: bool
    on_ac: bool | None
    profile: str | None
    choices: tuple[str, ...]
    available: tuple[str, ...]
    features: frozenset
    writable: frozenset
    profile_writable: bool
    fan_speed: tuple[int, int] | None
    battery_limiter: bool | None
    usb_charging: int | None
    backlight_timeout: bool | None
    battery_calibration: bool | None
    driver_version: str | None


def _read(sysfs, caminho):
    """Le um atributo. Ausente ou ilegivel devolve None, nunca excecao."""
    if caminho is None or not caminho.is_file():
        return None
    try:
        return sysfs.read(caminho)
    except OSError:
        return None


def _parse(funcao, bruto):
    if bruto is None:
        return None
    try:
        return funcao(bruto)
    except ValueError:
        return None


def read_state(sysfs):
    """Uma passada completa pelo aparelho."""
    sense = sysfs.sense_dir()
    perfil_caminho = sysfs.profile_path()

    features = set()
    writable = set()
    if sense is not None:
        for nome in SENSE_ATTRS:
            caminho = sense / nome
            if not caminho.is_file():
                continue
            features.add(nome)
            if os.access(caminho, os.W_OK):
                writable.add(nome)

    bruto_choices = _read(sysfs, sysfs.choices_path())
    choices = tuple(bruto_choices.split()) if bruto_choices else ()
    perfil = _read(sysfs, perfil_caminho)
    on_ac = sysfs.on_ac()

    disponiveis = ()
    if choices and on_ac is not None:
        disponiveis = model.available(choices, on_ac=on_ac)

    def sense_attr(nome):
        return _read(sysfs, sense / nome) if nome in features else None

    return DeviceState(
        module_loaded=sysfs.module_loaded(),
        on_ac=on_ac,
        profile=perfil,
        choices=choices,
        available=disponiveis,
        features=frozenset(features),
        writable=frozenset(writable),
        profile_writable=(
            perfil_caminho is not None
            and perfil_caminho.is_file()
            and os.access(perfil_caminho, os.W_OK)
        ),
        fan_speed=_parse(model.parse_fan_speed, sense_attr("fan_speed")),
        battery_limiter=_parse(model.parse_bool, sense_attr("battery_limiter")),
        usb_charging=_parse(int, sense_attr("usb_charging")),
        backlight_timeout=_parse(model.parse_bool, sense_attr("backlight_timeout")),
        battery_calibration=_parse(model.parse_bool, sense_attr("battery_calibration")),
        driver_version=_read(sysfs, sense / "version") if sense is not None else None,
    )
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_device.py -q
```

Esperado: `11 passed`.

- [ ] **Step 5: Verificar contra o hardware**

```bash
cd /home/brunodobner/Claude/Nitrosense && PYTHONPATH=src python3 -c "
from nexus_sense.sysfs import Sysfs
from nexus_sense.device import read_state
e = read_state(Sysfs('/'))
print('perfil:', e.profile, '| na tomada:', e.on_ac)
print('anunciados:', e.choices)
print('disponiveis:', e.available)
print('graveis:', sorted(e.writable), '| profile gravavel:', e.profile_writable)
"
```

Esperado: quatro anunciados, `profile` gravável e os cinco em `writable` — a regra udev da Task 9 do plano 1 está instalada. Se `writable` sair vazio, a sessão não herdou o grupo: relogue ou use `sudo -A -u "$USER" -g nexus_sense`.

- [ ] **Step 6: Commit**

```bash
git add src/nexus_sense/device.py tests/python/test_device.py
git commit -m "feat: instantaneo do aparelho numa leitura so

features diz o que existe no firmware; writable diz o que da para
escrever agora. Sao coisas diferentes e a tela fala diferente de cada
uma: recurso ausente some, recurso sem permissao fica visivel e cinza,
com o comando de correcao.

Valor ilegivel vira None em vez de excecao -- a janela precisa abrir
mesmo com o driver a meio caminho.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Os seis controles e a tradução do erro

**Files:**
- Modify: `src/nexus_sense/device.py` (acrescenta ao fim)
- Test: `tests/python/test_controls.py`

**Interfaces:**
- Consumes: `Sysfs`, `model`, `SENSE_ATTRS` da Task 1.
- Produces:
  - `WriteError(Exception)` — com atributo `message: str`, uma frase pronta em pt-BR
  - `Controls(sysfs: Sysfs)` com `set_profile(profile: str)`, `set_fan_speed(cpu: int, gpu: int)`, `set_battery_limiter(on: bool)`, `set_usb_charging(level: int)`, `set_backlight_timeout(on: bool)`, `set_battery_calibration(on: bool)` — todos devolvem `None` e levantam `WriteError`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_controls.py`:

```python
import errno
import os

import pytest

from nexus_sense.device import Controls, WriteError, read_state
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

SENSE = "sys/devices/platform/acer-wmi/nitro_sense"
PROFILE = "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"


def test_escreve_o_perfil(fake_root):
    Controls(Sysfs(fake_root)).set_profile("quiet")
    assert (fake_root / PROFILE).read_text().strip() == "quiet"


def test_escreve_a_ventoinha_no_formato_do_driver(fake_root):
    Controls(Sysfs(fake_root)).set_fan_speed(70, 80)
    assert (fake_root / SENSE / "fan_speed").read_text().strip() == "70,80"


def test_ventoinha_fora_da_faixa_e_recusada_antes_de_escrever(fake_root):
    """Melhor recusar aqui, com a razao escrita, do que mandar e receber
    -EINVAL. A validacao mora em model.py e esta camada so a usa."""
    antes = (fake_root / SENSE / "fan_speed").read_text()
    with pytest.raises(ValueError):
        Controls(Sysfs(fake_root)).set_fan_speed(70, 120)
    assert (fake_root / SENSE / "fan_speed").read_text() == antes


def test_carga_usb_fora_dos_quatro_niveis_e_recusada(fake_root):
    with pytest.raises(ValueError):
        Controls(Sysfs(fake_root)).set_usb_charging(15)


def test_escreve_os_booleanos_como_0_e_1(fake_root):
    c = Controls(Sysfs(fake_root))
    c.set_battery_limiter(False)
    c.set_backlight_timeout(True)
    c.set_battery_calibration(True)
    assert (fake_root / SENSE / "battery_limiter").read_text().strip() == "0"
    assert (fake_root / SENSE / "backlight_timeout").read_text().strip() == "1"
    assert (fake_root / SENSE / "battery_calibration").read_text().strip() == "1"


def test_o_que_foi_escrito_volta_na_leitura_seguinte(fake_root):
    """O sysfs e o estado compartilhado entre a GUI e o agente: nao ha
    cache a invalidar. Ver spec secao 4.1."""
    Controls(Sysfs(fake_root)).set_usb_charging(20)
    assert read_state(Sysfs(fake_root)).usb_charging == 20


def test_recurso_ausente_da_uma_frase_e_nao_um_traceback(tmp_path):
    raiz = build_tree(tmp_path)
    (raiz / SENSE / "backlight_timeout").unlink()
    with pytest.raises(WriteError) as capturado:
        Controls(Sysfs(raiz)).set_backlight_timeout(True)
    assert "não existe" in capturado.value.message


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignora a permissão do arquivo")
def test_sem_permissao_a_frase_fala_de_grupo_e_de_relogar(fake_root):
    """Os dois sintomas sao identicos -- 'nao consigo escrever' -- e as
    causas sao diferentes: fora do grupo, ou dentro dele numa sessao que
    ainda nao o herdou. A frase precisa cobrir as duas. Ver spec secao 9."""
    alvo = fake_root / SENSE / "fan_speed"
    alvo.chmod(0o444)
    try:
        with pytest.raises(WriteError) as capturado:
            Controls(Sysfs(fake_root)).set_fan_speed(50, 50)
    finally:
        alvo.chmod(0o644)
    frase = capturado.value.message
    assert "nexus_sense" in frase and "relogar" in frase


def test_recusa_do_driver_vira_frase_sobre_a_bateria(fake_root, monkeypatch):
    """EOPNOTSUPP e o que o driver devolve para quiet na bateria. Aqui ele
    e simulado; o teste de hardware tests/test-perfil-bateria.sh cobre o
    caso real. Ver spec secao 2.8."""
    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    controles = Controls(Sysfs(fake_root))
    monkeypatch.setattr(controles.sysfs, "write", recusa)
    with pytest.raises(WriteError) as capturado:
        controles.set_profile("quiet")
    assert "bateria" in capturado.value.message


def test_a_mensagem_tambem_e_o_str_da_excecao(fake_root):
    erro = WriteError("qualquer coisa")
    assert str(erro) == "qualquer coisa" == erro.message
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_controls.py -q
```

Esperado: `ImportError: cannot import name 'Controls'`.

- [ ] **Step 3: Implementar**

Ao **fim** de `src/nexus_sense/device.py`:

```python
import errno as _errno


class WriteError(Exception):
    """Falha de escrita ja traduzida para uma frase em pt-BR.

    Quem levanta e esta camada; quem mostra e a interface. Nenhum widget
    olha errno, e nenhuma tela mostra traceback. Ver spec secao 9.
    """

    def __init__(self, message):
        super().__init__(message)
        self.message = message


# As tres causas que acontecem de verdade nesta maquina. Qualquer outra
# cai no texto generico com o errno junto, para nao esconder novidade.
def _traduz(erro, alvo, valor):
    if erro.errno in (_errno.EACCES, _errno.EPERM):
        return (
            f"sem permissão para escrever em {alvo}. Confira se você está no "
            "grupo nexus_sense; se acabou de entrar nele, é preciso relogar "
            "para a sessão herdar o grupo."
        )
    if erro.errno == _errno.EOPNOTSUPP:
        return (
            f"o driver recusou {valor!r}: este valor não é aceito na bateria. "
            "Ligue o cabo para usá-lo."
        )
    if erro.errno == _errno.EINVAL:
        return f"o driver recusou o valor {valor!r} como inválido."
    if erro.errno == _errno.ENOENT:
        return f"{alvo} não existe neste firmware."
    return f"falha ao escrever em {alvo}: {erro.strerror or erro}"


class Controls:
    """Os seis atributos graveis, e nada mais.

    A validacao vem de model.py e roda antes da escrita: e melhor recusar
    aqui, com a razao escrita, do que mandar e receber -EINVAL.
    """

    def __init__(self, sysfs):
        self.sysfs = sysfs

    # ------------------------------------------------------------------
    # o perfil, que mora fora do grupo sense
    # ------------------------------------------------------------------

    def set_profile(self, profile):
        caminho = self.sysfs.profile_path()
        if caminho is None:
            raise WriteError("o perfil térmico não existe neste firmware.")
        self._write(caminho, profile, "o perfil térmico")

    # ------------------------------------------------------------------
    # os cinco do grupo sense
    # ------------------------------------------------------------------

    def set_fan_speed(self, cpu, gpu):
        self._write_sense("fan_speed", model.fan_speed_value(cpu, gpu))

    def set_usb_charging(self, level):
        self._write_sense("usb_charging", model.usb_charging_value(level))

    def set_battery_limiter(self, on):
        self._write_sense("battery_limiter", model.bool_value(on))

    def set_backlight_timeout(self, on):
        self._write_sense("backlight_timeout", model.bool_value(on))

    def set_battery_calibration(self, on):
        self._write_sense("battery_calibration", model.bool_value(on))

    # ------------------------------------------------------------------

    def _write_sense(self, nome, valor):
        sense = self.sysfs.sense_dir()
        if sense is None:
            raise WriteError("o driver não está carregado.")
        caminho = sense / nome
        if not caminho.is_file():
            raise WriteError(f"{nome} não existe neste firmware.")
        self._write(caminho, valor, nome)

    def _write(self, caminho, valor, alvo):
        try:
            self.sysfs.write(caminho, valor)
        except OSError as erro:
            raise WriteError(_traduz(erro, alvo, valor)) from erro
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_controls.py -q
```

Esperado: `10 passed`.

- [ ] **Step 5: Verificar contra o hardware, com restauração**

O `backlight_timeout` é o mais inócuo dos seis. Este comando o alterna e
devolve ao valor original:

```bash
cd /home/brunodobner/Claude/Nitrosense && PYTHONPATH=src python3 -c "
from nexus_sense.sysfs import Sysfs
from nexus_sense.device import Controls, read_state
s = Sysfs('/'); c = Controls(s)
antes = read_state(s).backlight_timeout
print('antes:', antes)
c.set_backlight_timeout(not antes)
print('depois:', read_state(s).backlight_timeout)
c.set_backlight_timeout(antes)
print('restaurado:', read_state(s).backlight_timeout)
"
```

Esperado: o valor alterna e volta. Se sair `WriteError` falando de grupo,
a sessão ainda não o herdou — rode com `sudo -A -u "$USER" -g nexus_sense`.

- [ ] **Step 6: Commit**

```bash
git add src/nexus_sense/device.py tests/python/test_controls.py
git commit -m "feat: os seis controles graveis, com o erro ja traduzido

Nenhum widget olha errno. As tres causas que acontecem de verdade --
sem permissao, recusado na bateria, valor invalido -- viram frase em
pt-BR aqui, e a interface so mostra.

A frase de permissao cobre as duas causas de propósito: estar fora do
grupo e estar dentro dele numa sessao que ainda nao o herdou produzem o
mesmo sintoma.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: A janela, a barra lateral e a página Desempenho

A primeira fatia vertical: uma janela que abre de verdade, com uma página
real dentro. As demais páginas entram nas tarefas seguintes, cada uma se
registrando em `build_pages`.

**Files:**
- Create: `src/nexus_sense/session.py`
- Create: `src/nexus_sense/gui/__init__.py`
- Create: `src/nexus_sense/gui/window.py`
- Create: `src/nexus_sense/gui/app.py`
- Create: `src/nexus_sense/gui/pages/__init__.py`
- Create: `src/nexus_sense/gui/pages/performance.py`
- Modify: `tests/python/conftest.py` (acrescenta o offscreen no topo)
- Modify: `pyproject.toml` (acrescenta o executável da GUI)
- Test: `tests/python/test_window.py`, `tests/python/test_performance.py`

**Interfaces:**
- Consumes: `read_state`, `Controls`, `WriteError` da Task 2.
- Produces:
  - `session.agent_active(runner=subprocess.run) -> bool`
  - `gui.pages.build_pages(controls) -> tuple[tuple[str, str, QWidget], ...]` — `(chave, rótulo, página)`
  - **protocolo de página:** todo widget de página expõe `apply_state(state) -> None`, `has_content(state) -> bool` e o sinal `changed`
  - `gui.window.Window(sysfs, controls, pages=None)` com `refresh()`, `.sidebar`, `.stack`, `.agent_label`
  - `gui.pages.performance.PerformancePage(controls)` com `.buttons: dict[str, ProfileButton]`
  - `gui.pages.performance.ProfileButton(QPushButton)` com `.unavailable: bool` e `.reason: str`
  - `gui.pages.performance.unavailable_reason(profile, state) -> str`
  - `gui.app.main(argv=None) -> int`

- [ ] **Step 1: Instalar o `pytest-qt`**

```bash
export SUDO_ASKPASS=~/.local/bin/claude-askpass
sudo -A pacman -S --needed --noconfirm python-pytest-qt
python3 -c "import pytestqt, PySide6; print('ok', PySide6.__version__)"
```

Esperado: `ok 6.11.2`. O `pyside6` e o `qt6-base` já estão instalados nesta
máquina — foram medidos ao escrever este plano.

- [ ] **Step 2: Fazer a suíte rodar sem tela**

No **topo** de `tests/python/conftest.py`, **antes de qualquer import de
Qt** (isto é, antes de tudo menos a docstring):

```python
import os

# Qt sem servidor grafico. Precisa vir antes de qualquer import de
# PySide6, inclusive os indiretos que os testes fazem: o QPA e escolhido
# na primeira vez que o Qt e carregado, e nao muda depois.
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
```

- [ ] **Step 3: Registrar o executável da GUI**

Em `pyproject.toml`, na seção `[project.scripts]`, acrescente a linha da
GUI ao lado da que já existe:

```toml
[project.scripts]
nexus-sense-agent = "nexus_sense.__main__:main"
nexus-sense = "nexus_sense.gui.app:main"
```

- [ ] **Step 4: Escrever os testes que falham**

`tests/python/test_performance.py`:

```python
import pytest

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.performance import PerformancePage, unavailable_reason
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

QUATRO = ("low-power", "quiet", "balanced", "balanced-performance")


def pagina(qtbot, raiz):
    s = Sysfs(raiz)
    p = PerformancePage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    return p


def test_um_botao_por_perfil_anunciado_na_ordem_canonica(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    assert tuple(p.buttons) == QUATRO


def test_as_posicoes_nao_mudam_quando_o_cabo_sai(qtbot, tmp_path):
    """O requisito central da tela: o conjunto nao muda de tamanho nem de
    conteudo com a fonte. Hoje a GUI antiga troca tres botoes por dois e
    nada fica no lugar. Ver spec secao 6.2 e decisao D7."""
    raiz = build_tree(tmp_path / "t", on_ac=True)
    p = pagina(qtbot, raiz)
    na_tomada = tuple(p.buttons)

    (raiz / "sys/class/power_supply/ACAD/online").write_text("0\n")
    p.apply_state(read_state(Sysfs(raiz)))
    assert tuple(p.buttons) == na_tomada


def test_na_bateria_o_indisponivel_fica_desligado_com_o_motivo(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False)
    p = pagina(qtbot, raiz)
    assert p.buttons["quiet"].isEnabled() is False
    assert p.buttons["quiet"].unavailable is True
    assert "bateria" in p.buttons["quiet"].reason
    assert p.buttons["balanced"].isEnabled() is True
    assert p.buttons["balanced"].unavailable is False


def test_o_buraco_da_escada_aparece_na_tela(qtbot, tmp_path):
    """O 'quiet' e mais economico que o 'balanced' e mesmo assim e
    barrado; o alcance nao e contiguo. Ver spec secao 2.8."""
    raiz = build_tree(tmp_path / "t", on_ac=False)
    p = pagina(qtbot, raiz)
    ligados = [n for n, b in p.buttons.items() if b.isEnabled()]
    assert ligados == ["low-power", "balanced"]


def test_o_perfil_corrente_fica_marcado(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", profile="quiet")
    p = pagina(qtbot, raiz)
    assert p.buttons["quiet"].isChecked() is True
    assert p.buttons["balanced"].isChecked() is False


def test_clicar_escreve_no_sysfs(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    p.buttons["quiet"].click()
    caminho = fake_root / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    assert caminho.read_text().strip() == "quiet"


def test_clicar_avisa_a_janela_para_reler(qtbot, fake_root):
    p = pagina(qtbot, fake_root)
    with qtbot.waitSignal(p.changed, timeout=1000):
        p.buttons["low-power"].click()


def test_escrita_recusada_vira_frase_na_tela_e_nao_excecao(qtbot, fake_root, monkeypatch):
    """Corrida real: o cabo sai entre o clique e a escrita. Relê o estado
    e corrige a tela, sem diálogo. Ver spec secao 9."""
    import errno

    p = pagina(qtbot, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    monkeypatch.setattr(p.controls.sysfs, "write", recusa)
    p.buttons["quiet"].click()
    assert "bateria" in p.message_label.text()


def test_sem_perfil_anunciado_a_secao_nao_tem_conteudo(qtbot, tmp_path):
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    s = Sysfs(vazia)
    p = PerformancePage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is False


def test_o_motivo_e_vazio_para_quem_esta_disponivel(fake_root):
    e = read_state(Sysfs(fake_root))
    assert unavailable_reason("balanced", e) == ""
```

`tests/python/test_window.py`:

```python
import subprocess

import pytest
from PySide6.QtCore import Signal
from PySide6.QtWidgets import QLabel, QWidget

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.window import Window
from nexus_sense.session import agent_active
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


class PaginaFalsa(QWidget):
    """Pagina de mentira que cumpre o protocolo."""

    changed = Signal()

    def __init__(self, conteudo=True):
        super().__init__()
        self._conteudo = conteudo
        self.aplicou = 0

    def has_content(self, state):
        return self._conteudo

    def apply_state(self, state):
        self.aplicou += 1


def janela(qtbot, raiz, paginas):
    s = Sysfs(raiz)
    j = Window(s, Controls(s), pages=paginas)
    qtbot.addWidget(j)
    return j


def test_a_barra_lateral_lista_as_secoes_com_conteudo(qtbot, fake_root):
    j = janela(qtbot, fake_root, (
        ("a", "Painel", PaginaFalsa()),
        ("b", "Bateria", PaginaFalsa()),
    ))
    j.refresh()
    assert [j.sidebar.item(i).text() for i in range(j.sidebar.count())] == ["Painel", "Bateria"]


def test_secao_sem_controle_algum_some_da_barra(qtbot, fake_root):
    """Numa maquina sem backlight_timeout a secao Teclado nao e exibida
    vazia: some. Ver spec secao 6.4."""
    j = janela(qtbot, fake_root, (
        ("a", "Painel", PaginaFalsa()),
        ("b", "Teclado", PaginaFalsa(conteudo=False)),
    ))
    j.refresh()
    assert [j.sidebar.item(i).text() for i in range(j.sidebar.count())] == ["Painel"]


def test_refresh_repassa_o_estado_a_cada_pagina(qtbot, fake_root):
    p = PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", p),))
    j.refresh()
    j.refresh()
    assert p.aplicou == 2


def test_trocar_de_secao_troca_a_pagina(qtbot, fake_root):
    a, b = PaginaFalsa(), PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", a), ("b", "Bateria", b)))
    j.refresh()
    j.sidebar.setCurrentRow(1)
    assert j.stack.currentWidget() is b


def test_o_sinal_da_pagina_faz_a_janela_reler(qtbot, fake_root):
    p = PaginaFalsa()
    j = janela(qtbot, fake_root, (("a", "Painel", p),))
    j.refresh()
    antes = p.aplicou
    p.changed.emit()
    assert p.aplicou > antes


def test_sem_o_modulo_a_janela_mostra_uma_tela_so(qtbot, tmp_path):
    """Modulo descarregado: nao adianta mostrar controles. Uma tela, com o
    comando para carregar. Ver spec secao 9."""
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    j = janela(qtbot, vazia, (("a", "Painel", PaginaFalsa()),))
    j.refresh()
    assert j.sidebar.count() == 0
    assert "modprobe" in j.stack.currentWidget().findChild(QLabel, "driver_missing").text()


def test_o_rodape_diz_se_o_agente_esta_de_pe(qtbot, fake_root):
    """A informacao que passa a importar quando nao ha mais daemon.
    Ver spec secao 6.1."""
    j = janela(qtbot, fake_root, (("a", "Painel", PaginaFalsa()),))
    j.refresh()
    assert j.agent_label.text() != ""


def test_agente_ativo_le_o_systemctl_do_usuario():
    chamadas = []

    def espiao(args, **kwargs):
        chamadas.append(args)
        return subprocess.CompletedProcess(args, 0, stdout="active\n", stderr="")

    assert agent_active(runner=espiao) is True
    assert chamadas[0][:3] == ["systemctl", "--user", "is-active"]


def test_agente_inativo_nao_derruba_nada():
    def espiao(args, **kwargs):
        return subprocess.CompletedProcess(args, 3, stdout="inactive\n", stderr="")

    assert agent_active(runner=espiao) is False


def test_sem_systemctl_o_agente_e_dado_como_fora():
    def explode(args, **kwargs):
        raise FileNotFoundError("systemctl")

    assert agent_active(runner=explode) is False
```

- [ ] **Step 5: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_window.py tests/python/test_performance.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.session'` e
`No module named 'nexus_sense.gui'`.

- [ ] **Step 6: Implementar o `session.py`**

`src/nexus_sense/session.py`:

```python
"""Fatos da sessao do usuario que nao estao no sysfs.

Ficam fora da GUI de proposito: o Diagnostico e o rodape da barra
lateral perguntam a mesma coisa, e nenhum dos dois deve chamar
subprocess por conta propria.
"""

import subprocess

AGENT_UNIT = "nexus-sense-agent.service"


def agent_active(runner=subprocess.run):
    """True quando o servico de usuario do agente esta no ar.

    Qualquer falha -- systemd ausente, unit inexistente, sessao sem
    barramento -- responde False. Nao saber e o mesmo que estar fora,
    para efeito do que a tela mostra.
    """
    try:
        saida = runner(
            ["systemctl", "--user", "is-active", "--quiet", AGENT_UNIT],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return saida.returncode == 0
```

- [ ] **Step 7: Implementar a página Desempenho**

`src/nexus_sense/gui/__init__.py`:

```python
"""A interface. Nenhum arquivo daqui abre caminho de sysfs."""
```

`src/nexus_sense/gui/pages/__init__.py`:

```python
"""As paginas da janela.

Cada pagina cumpre o mesmo protocolo, e a janela nao sabe nada alem
dele:

    apply_state(state)   recebe o DeviceState e se repinta
    has_content(state)   False faz a secao sumir da barra lateral
    changed              sinal; a janela rele o estado quando ele vem

Uma pagina nova entra registrando-se em build_pages, e so.
"""

from .performance import PerformancePage


def build_pages(controls):
    """As secoes, na ordem em que aparecem na barra lateral."""
    return (("desempenho", "Desempenho", PerformancePage(controls)),)
```

`src/nexus_sense/gui/pages/performance.py`:

```python
"""Desempenho: os perfis termicos.

A regra que manda nesta tela: as posicoes sao fixas. O que muda com a
fonte de energia e o estado de cada botao, nunca a quantidade nem a
ordem. Ver spec secao 6.2 e decisao D7.
"""

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QPainter, QPen
from PySide6.QtWidgets import (
    QGridLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from ... import model
from ...device import WriteError

# Quantos botoes por linha. Quatro perfis cabem numa linha so; com o
# quinto (atras do nitro_v4) a grade quebra sozinha.
COLUNAS = 4

SOMENTE_LEITURA = (
    "Os perfis estão em somente-leitura: a permissão de grupo não está "
    "aplicada nesta sessão. Confira o Diagnóstico."
)


def unavailable_reason(profile, state):
    """Por que este perfil nao pode ser usado agora. Vazio se pode."""
    if profile in state.available:
        return ""
    if state.on_ac is False and profile in model.AC_ONLY:
        return "o driver recusa este perfil na bateria"
    return "não disponível neste firmware"


class ProfileButton(QPushButton):
    """Botao de perfil que sabe se desenhar hachurado.

    O hachurado e pintado a mao porque QSS nao tem gradiente repetido: a
    alternativa seria uma imagem de fundo por tamanho de botao.
    """

    def __init__(self, profile, parent=None):
        super().__init__(parent)
        self.profile = profile
        self.unavailable = False
        self.reason = ""
        self.setCheckable(True)
        self.setMinimumHeight(64)

    def paintEvent(self, evento):
        super().paintEvent(evento)
        if not self.unavailable:
            return
        pintor = QPainter(self)
        caneta = QPen(self.palette().mid().color())
        caneta.setWidth(1)
        pintor.setPen(caneta)
        largura, altura = self.width(), self.height()
        # diagonais a cada 6 px, cobrindo a caixa inteira
        for x in range(-altura, largura, 6):
            pintor.drawLine(x, altura, x + altura, 0)


class PerformancePage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls
        self.buttons = {}
        self._grade = QGridLayout()
        self.message_label = QLabel("")
        self.message_label.setWordWrap(True)
        self.message_label.setObjectName("mensagem")

        raiz = QVBoxLayout(self)
        titulo = QLabel("Perfil térmico")
        titulo.setObjectName("titulo")
        raiz.addWidget(titulo)
        raiz.addLayout(self._grade)
        raiz.addWidget(self.message_label)
        raiz.addStretch(1)

    def has_content(self, state):
        return bool(state.choices)

    def apply_state(self, state):
        self._monta(state.choices)
        for nome, botao in self.buttons.items():
            motivo = unavailable_reason(nome, state)
            botao.unavailable = bool(motivo)
            botao.reason = motivo
            botao.setEnabled(not motivo and state.profile_writable)
            botao.setToolTip(motivo or model.LABELS.get(nome, nome))
            # setChecked dispara clicked? Nao: clicked so vem de interacao.
            botao.setChecked(nome == state.profile)
            botao.update()

        # So esta mensagem e gerida aqui. A de erro de escrita fica onde
        # esta: apaga-la a cada repintura a faria sumir antes de ser lida,
        # porque escrever emite changed e a janela repinta na hora.
        if not state.profile_writable and state.choices:
            self.message_label.setText(SOMENTE_LEITURA)
        elif self.message_label.text() == SOMENTE_LEITURA:
            self.message_label.setText("")

    def _monta(self, choices):
        """Cria os botoes uma vez so. A grade nunca e remontada: e
        exatamente isso que mantem as posicoes fixas."""
        if self.buttons or not choices:
            return
        anunciados = [p for p in model.PROFILES if p in set(choices)]
        for indice, nome in enumerate(anunciados):
            botao = ProfileButton(nome)
            botao.setText(f"{model.LABELS.get(nome, nome)}\n{nome}")
            botao.clicked.connect(lambda _=False, p=nome: self._escolhe(p))
            self._grade.addWidget(botao, indice // COLUNAS, indice % COLUNAS)
            self.buttons[nome] = botao

    def _escolhe(self, profile):
        self.message_label.setText("")
        try:
            self.controls.set_profile(profile)
        except WriteError as erro:
            # Acontece de verdade: o cabo sai entre o clique e a escrita.
            self.message_label.setText(erro.message)
        self.changed.emit()
```

- [ ] **Step 8: Implementar a janela**

`src/nexus_sense/gui/window.py`:

```python
"""A janela: barra lateral, paginas empilhadas e o rodape do agente."""

from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QListWidget,
    QMainWindow,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from ..device import read_state
from ..session import agent_active
from .pages import build_pages

CARREGAR = "sudo modprobe linuwu_sense"


class DriverMissingPage(QWidget):
    """A tela unica de quando o modulo nao esta carregado.

    Nao adianta mostrar controles cinzas: sem o modulo nao ha o que
    controlar. Uma tela, com o comando. Ver spec secao 9.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        leiaute = QVBoxLayout(self)
        rotulo = QLabel(
            "O driver não está carregado.\n\n"
            f"Para carregá-lo agora:\n    {CARREGAR}\n\n"
            "Se ele não volta sozinho no próximo boot, o instalador não "
            "chegou a escrever /etc/modules-load.d."
        )
        rotulo.setObjectName("driver_missing")
        rotulo.setWordWrap(True)
        leiaute.addStretch(1)
        leiaute.addWidget(rotulo)
        leiaute.addStretch(1)


class Window(QMainWindow):
    def __init__(self, sysfs, controls, pages=None):
        super().__init__()
        self.sysfs = sysfs
        self.controls = controls
        self.pages = tuple(build_pages(controls) if pages is None else pages)

        self.setWindowTitle("Nexus Sense")
        self.resize(920, 620)

        self.sidebar = QListWidget()
        self.sidebar.setFixedWidth(180)
        self.sidebar.currentRowChanged.connect(self._troca_pagina)

        self.agent_label = QLabel("")
        self.agent_label.setObjectName("agente")
        self.agent_label.setWordWrap(True)

        lateral = QVBoxLayout()
        lateral.addWidget(self.sidebar, 1)
        lateral.addWidget(self.agent_label)

        self.stack = QStackedWidget()
        self._driver_missing = DriverMissingPage()
        self.stack.addWidget(self._driver_missing)
        for _, _, pagina in self.pages:
            self.stack.addWidget(pagina)
            pagina.changed.connect(self.refresh)

        corpo = QHBoxLayout()
        corpo.addLayout(lateral)
        corpo.addWidget(self.stack, 1)

        central = QWidget()
        central.setLayout(corpo)
        self.setCentralWidget(central)

        # `_visiveis` guarda as chaves na ordem em que estao na barra, para
        # traduzir linha selecionada em pagina.
        self._visiveis = ()

    # ------------------------------------------------------------------

    def refresh(self):
        """Rele o aparelho e repinta tudo. E o unico caminho de
        atualizacao: nao ha cache, porque o sysfs e o estado."""
        estado = read_state(self.sysfs)
        self.agent_label.setText(
            "Agente: ativo" if agent_active() else "Agente: fora do ar"
        )

        if not estado.module_loaded:
            self.sidebar.clear()
            self._visiveis = ()
            self.stack.setCurrentWidget(self._driver_missing)
            return

        visiveis = []
        for chave, rotulo, pagina in self.pages:
            pagina.apply_state(estado)
            if pagina.has_content(estado):
                visiveis.append((chave, rotulo, pagina))

        anterior = self._chave_atual()
        self._visiveis = tuple(v[0] for v in visiveis)
        self.sidebar.blockSignals(True)
        self.sidebar.clear()
        for _, rotulo, _ in visiveis:
            self.sidebar.addItem(rotulo)
        self.sidebar.blockSignals(False)

        if not visiveis:
            self.stack.setCurrentWidget(self._driver_missing)
            return
        linha = self._visiveis.index(anterior) if anterior in self._visiveis else 0
        self.sidebar.setCurrentRow(linha)
        self.stack.setCurrentWidget(visiveis[linha][2])

    def _chave_atual(self):
        linha = self.sidebar.currentRow()
        if 0 <= linha < len(self._visiveis):
            return self._visiveis[linha]
        return None

    def _troca_pagina(self, linha):
        if not (0 <= linha < len(self._visiveis)):
            return
        chave = self._visiveis[linha]
        for c, _, pagina in self.pages:
            if c == chave:
                self.stack.setCurrentWidget(pagina)
                return
```

- [ ] **Step 9: Implementar o ponto de entrada**

`src/nexus_sense/gui/app.py`:

```python
"""Executavel da interface: nexus-sense."""

import argparse
import sys

from PySide6.QtWidgets import QApplication

from .. import __version__
from ..device import Controls
from ..sysfs import Sysfs
from .window import Window


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="nexus-sense",
        description="Controle e monitoramento para laptops Acer Nitro e Predator.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--root", default="/", help="raiz alternativa do sysfs")
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    app = QApplication([])
    app.setApplicationName("Nexus Sense")
    app.setDesktopFileName("nexus-sense")

    sysfs = Sysfs(args.root)
    janela = Window(sysfs, Controls(sysfs))
    janela.refresh()
    janela.show()
    return app.exec()
```

- [ ] **Step 10: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_window.py tests/python/test_performance.py -q
```

Esperado: `20 passed`.

- [ ] **Step 11: Abrir a janela de verdade, contra uma árvore de mentira**

Sem tocar no hardware: monte uma árvore, aponte a GUI para ela e veja.

```bash
cd /home/brunodobner/Claude/Nitrosense && PYTHONPATH=src:tests/python python3 -c "
from pathlib import Path
from conftest import build_tree
raiz = Path('/tmp/claude-1000/nexus-arvore'); raiz.mkdir(parents=True, exist_ok=True)
build_tree(raiz, on_ac=False, profile='balanced')
print('árvore em', raiz)
"
PYTHONPATH=src python3 -m nexus_sense.gui.app --root /tmp/claude-1000/nexus-arvore
```

Esperado: a janela abre com a seção Desempenho, quatro botões nas mesmas
posições, `Silencioso` e `Desempenho` hachurados e desligados — porque a
árvore diz que está na bateria — e `Equilibrado` marcado.

- [ ] **Step 12: Commit**

```bash
git add pyproject.toml tests/python/conftest.py src/nexus_sense/session.py \
        src/nexus_sense/gui tests/python/test_window.py tests/python/test_performance.py
git commit -m "feat: a janela, a barra lateral e a pagina Desempenho

A grade de perfis e montada uma vez so e nunca remontada -- e isso que
mantem as quatro posicoes fixas quando o cabo sai. O indisponivel fica
hachurado com o motivo escrito, em vez de sumir.

Secao sem nenhum controle nao aparece na barra lateral, e sem o modulo
carregado a janela mostra uma tela so, com o comando.

A suite roda offscreen: QT_QPA_PLATFORM entra no conftest antes de
qualquer import de Qt, porque o QPA e escolhido na primeira carga.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: A telemetria na tela, e o gráfico com eixo

**Files:**
- Create: `src/nexus_sense/gui/poller.py`
- Create: `src/nexus_sense/gui/graph.py`
- Modify: `src/nexus_sense/gui/window.py` (liga e desliga o poller)
- Test: `tests/python/test_poller.py`, `tests/python/test_graph.py`

**Interfaces:**
- Consumes: `telemetry` do plano 1; `Window` da Task 3.
- Produces:
  - `gui.poller.Sample` — `NamedTuple` com `fans: tuple[int, int] | None`, `acer_temps: tuple[int, ...]`, `cpu_temp: float | None`, `gpu: GpuReading | None`
  - `gui.poller.Poller(sysfs, interval_ms=2000, parent=None)` com sinal `sampled(object)`, `start()`, `stop()`, propriedade `active: bool` e `read_now() -> Sample`
  - `gui.graph.TEMP_MIN`, `gui.graph.TEMP_MAX`, `gui.graph.y_for_celsius(celsius, height) -> float`
  - `gui.graph.TemperatureGraph(maxlen=120)` com `add_sample(celsius)` e `.samples`
  - **protocolo opcional de página:** quem definir `apply_sample(sample)` recebe cada leitura

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_graph.py`:

```python
import pytest

from nexus_sense.gui.graph import TEMP_MAX, TEMP_MIN, TemperatureGraph, y_for_celsius


def test_o_minimo_da_escala_fica_no_pe_do_grafico():
    assert y_for_celsius(TEMP_MIN, 200) == pytest.approx(200.0)


def test_o_maximo_da_escala_fica_no_topo():
    assert y_for_celsius(TEMP_MAX, 200) == pytest.approx(0.0)


def test_o_meio_da_escala_fica_no_meio():
    meio = (TEMP_MIN + TEMP_MAX) / 2
    assert y_for_celsius(meio, 200) == pytest.approx(100.0)


def test_valor_acima_da_escala_e_grampeado_no_topo():
    """Uma CPU a 105 graus nao pode desenhar fora da caixa."""
    assert y_for_celsius(150, 200) == pytest.approx(0.0)


def test_valor_abaixo_da_escala_e_grampeado_no_pe():
    assert y_for_celsius(-40, 200) == pytest.approx(200.0)


def test_o_grafico_guarda_as_amostras_ate_o_limite(qtbot):
    g = TemperatureGraph(maxlen=5)
    qtbot.addWidget(g)
    for valor in range(10):
        g.add_sample(float(valor))
    assert list(g.samples) == [5.0, 6.0, 7.0, 8.0, 9.0]


def test_amostra_none_e_ignorada(qtbot):
    """Sem coretemp nao ha o que plotar, e a linha nao pode virar zero."""
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.add_sample(None)
    assert list(g.samples) == []


def test_o_grafico_desenha_sem_explodir(qtbot):
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.resize(300, 150)
    for valor in (40.0, 55.0, 61.5):
        g.add_sample(valor)
    assert not g.grab().isNull()


def test_desenha_tambem_sem_amostra_nenhuma(qtbot):
    """A janela abre antes da primeira leitura."""
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.resize(300, 150)
    assert not g.grab().isNull()
```

`tests/python/test_poller.py`:

```python
from PySide6.QtWidgets import QWidget
from PySide6.QtCore import Signal

from nexus_sense.device import Controls
from nexus_sense.gui.poller import Poller
from nexus_sense.gui.window import Window
from nexus_sense.sysfs import Sysfs


def test_a_leitura_traz_ventoinhas_e_temperaturas(fake_root):
    amostra = Poller(Sysfs(fake_root)).read_now()
    assert amostra.fans == (2079, 1870)
    assert amostra.acer_temps == (25, 43, 43)
    assert amostra.cpu_temp == 47.0


def test_com_a_gpu_dormindo_a_amostra_diz_adormecida(fake_root):
    """E nao chama nvidia-smi. A guarda esta em telemetry.read_gpu; aqui
    so se confirma que o poller nao a contorna. Ver spec secao 10.2."""
    caminho = fake_root / "sys/bus/pci/devices/0000:01:00.0/power/runtime_status"
    caminho.write_text("suspended\n")
    amostra = Poller(Sysfs(fake_root)).read_now()
    assert amostra.gpu.asleep is True
    assert amostra.gpu.temperature is None


def test_arvore_vazia_devolve_amostra_vazia(tmp_path):
    amostra = Poller(Sysfs(tmp_path)).read_now()
    assert amostra.fans is None
    assert amostra.acer_temps == ()
    assert amostra.gpu is None


def test_o_poller_emite_enquanto_ligado(qtbot, fake_root):
    p = Poller(Sysfs(fake_root), interval_ms=10)
    p.start()
    try:
        with qtbot.waitSignal(p.sampled, timeout=2000) as capturado:
            pass
    finally:
        p.stop()
    assert capturado.args[0].fans == (2079, 1870)


def test_parar_desliga_de_verdade(qtbot, fake_root):
    p = Poller(Sysfs(fake_root), interval_ms=10)
    p.start()
    assert p.active is True
    p.stop()
    assert p.active is False


class PaginaComAmostra(QWidget):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.amostras = 0

    def has_content(self, state):
        return True

    def apply_state(self, state):
        pass

    def apply_sample(self, sample):
        self.amostras += 1


def test_a_telemetria_so_roda_com_a_janela_aberta(qtbot, fake_root):
    """A regra da spec secao 10.2: fechou, para. Um painel que continua
    sondando escondido gasta bateria para nao mostrar nada."""
    s = Sysfs(fake_root)
    j = Window(s, Controls(s), pages=(("a", "Painel", PaginaComAmostra()),))
    qtbot.addWidget(j)
    j.refresh()

    assert j.poller.active is False
    j.show()
    assert j.poller.active is True
    j.hide()
    assert j.poller.active is False


def test_a_amostra_chega_as_paginas_que_a_querem(qtbot, fake_root):
    s = Sysfs(fake_root)
    pagina = PaginaComAmostra()
    j = Window(s, Controls(s), pages=(("a", "Painel", pagina),))
    qtbot.addWidget(j)
    j.refresh()
    j.poller.sampled.emit(j.poller.read_now())
    assert pagina.amostras == 1
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_poller.py tests/python/test_graph.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.gui.poller'`.

- [ ] **Step 3: Implementar o poller**

`src/nexus_sense/gui/poller.py`:

```python
"""A sondagem de sensores da janela.

Duas regras, as duas da spec secao 10.2:

  - so roda com a janela visivel. Quem liga e desliga e a Window, no
    showEvent e no hideEvent;
  - nunca acorda a dGPU. A guarda mora em telemetry.read_gpu, e este
    modulo nao a contorna.
"""

from typing import NamedTuple

from PySide6.QtCore import QObject, QTimer, Signal

from .. import telemetry

INTERVALO_PADRAO = 2000  # ms; o mesmo ritmo do agente


class Sample(NamedTuple):
    fans: tuple | None
    acer_temps: tuple
    cpu_temp: float | None
    gpu: object | None      # telemetry.GpuReading ou None


class Poller(QObject):
    sampled = Signal(object)

    def __init__(self, sysfs, interval_ms=INTERVALO_PADRAO, parent=None):
        super().__init__(parent)
        self.sysfs = sysfs
        self._timer = QTimer(self)
        self._timer.setInterval(interval_ms)
        self._timer.timeout.connect(self._passada)

    @property
    def active(self):
        return self._timer.isActive()

    def start(self):
        if not self._timer.isActive():
            self._timer.start()
            self._passada()      # nao esperar o primeiro intervalo

    def stop(self):
        self._timer.stop()

    def read_now(self):
        """Uma leitura sincrona. Usada pelo start e pelos testes."""
        return Sample(
            fans=telemetry.fan_rpm(self.sysfs),
            acer_temps=telemetry.acer_temperatures(self.sysfs),
            cpu_temp=telemetry.cpu_package_temp(self.sysfs),
            gpu=telemetry.read_gpu(self.sysfs),
        )

    def _passada(self):
        self.sampled.emit(self.read_now())
```

- [ ] **Step 4: Implementar o gráfico**

`src/nexus_sense/gui/graph.py`:

```python
"""Grafico de temperatura com eixo em graus.

A GUI antiga desenha as linhas sem referencia nenhuma: sobe e desce, e
nao se sabe entre que valores. Aqui a escala e fixa de 20 a 100 graus,
com marca a cada 20, e o valor e grampeado nas pontas -- uma CPU a 105
nao desenha fora da caixa. Ver spec secao 6.1.
"""

from collections import deque

from PySide6.QtCore import Qt
from PySide6.QtGui import QFontMetrics, QPainter, QPen
from PySide6.QtWidgets import QWidget

TEMP_MIN = 20
TEMP_MAX = 100
TICK = 20
MARGEM_ESQUERDA = 34


def y_for_celsius(celsius, height):
    """Onde este valor cai, em pixels, com 0 no topo da caixa."""
    fracao = (celsius - TEMP_MIN) / (TEMP_MAX - TEMP_MIN)
    fracao = max(0.0, min(1.0, fracao))
    return height * (1.0 - fracao)


class TemperatureGraph(QWidget):
    def __init__(self, maxlen=120, parent=None):
        super().__init__(parent)
        self.samples = deque(maxlen=maxlen)
        self.setMinimumHeight(140)

    def add_sample(self, celsius):
        """None e ignorado: sem sensor nao ha ponto, e zero seria mentira."""
        if celsius is None:
            return
        self.samples.append(float(celsius))
        self.update()

    def paintEvent(self, evento):
        pintor = QPainter(self)
        pintor.setRenderHint(QPainter.Antialiasing)
        altura = self.height()
        largura = self.width()
        area = largura - MARGEM_ESQUERDA

        cor_eixo = self.palette().mid().color()
        metrica = QFontMetrics(self.font())

        # eixo: uma marca a cada TICK graus, com o numero a esquerda
        pintor.setPen(QPen(cor_eixo, 1, Qt.DotLine))
        for grau in range(TEMP_MIN, TEMP_MAX + 1, TICK):
            y = y_for_celsius(grau, altura - 1)
            pintor.drawLine(MARGEM_ESQUERDA, int(y), largura, int(y))
            pintor.setPen(QPen(cor_eixo))
            pintor.drawText(
                0,
                int(y) + metrica.ascent() // 2,
                f"{grau}°",
            )
            pintor.setPen(QPen(cor_eixo, 1, Qt.DotLine))

        if len(self.samples) < 2 or area <= 1:
            return

        passo = area / (self.samples.maxlen - 1)
        pintor.setPen(QPen(self.palette().highlight().color(), 2))
        anterior = None
        # alinhado a direita: a amostra mais nova encosta na borda
        primeiro = self.samples.maxlen - len(self.samples)
        for indice, valor in enumerate(self.samples, start=primeiro):
            x = MARGEM_ESQUERDA + indice * passo
            y = y_for_celsius(valor, altura - 1)
            if anterior is not None:
                pintor.drawLine(int(anterior[0]), int(anterior[1]), int(x), int(y))
            anterior = (x, y)
```

- [ ] **Step 5: Ligar o poller à janela**

Em `src/nexus_sense/gui/window.py`, acrescente o import:

```python
from .poller import Poller
```

No fim do `__init__`, logo depois da linha `self._visiveis = ()`:

```python
        # A telemetria so roda com a janela visivel. Ver spec secao 10.2.
        self.poller = Poller(sysfs, parent=self)
        self.poller.sampled.connect(self._distribui_amostra)
```

E acrescente os três métodos ao fim da classe:

```python
    def _distribui_amostra(self, sample):
        """Entrega a leitura as paginas que a querem. apply_sample e
        protocolo opcional: quem nao tem, nao recebe."""
        for _, _, pagina in self.pages:
            metodo = getattr(pagina, "apply_sample", None)
            if metodo is not None:
                metodo(sample)

    def showEvent(self, evento):
        super().showEvent(evento)
        self.poller.start()

    def hideEvent(self, evento):
        super().hideEvent(evento)
        self.poller.stop()
```

- [ ] **Step 6: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_poller.py tests/python/test_graph.py -q
```

Esperado: `16 passed`.

- [ ] **Step 7: Confirmar que a GPU não é acordada pela janela**

Com a dGPU adormecida, abrir a janela contra o sysfs de verdade não pode
mudar o `runtime_status`:

```bash
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
PYTHONPATH=src timeout 8 python3 -c "
from nexus_sense.sysfs import Sysfs
from nexus_sense.gui.poller import Poller
p = Poller(Sysfs('/'))
for _ in range(4):
    print(p.read_now().gpu)
"
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```

Esperado: se o status era `suspended`, as quatro leituras dizem
`asleep=True` e o status **continua** `suspended` no fim. Se estava
`active`, as leituras trazem temperatura e uso — o que também está certo.

- [ ] **Step 8: Commit**

```bash
git add src/nexus_sense/gui/poller.py src/nexus_sense/gui/graph.py \
        src/nexus_sense/gui/window.py tests/python/test_poller.py tests/python/test_graph.py
git commit -m "feat: telemetria da janela e grafico com eixo em graus

O poller so roda com a janela visivel -- liga no showEvent, para no
hideEvent. Um painel que continua sondando escondido gasta bateria para
nao mostrar nada, e no caso da dGPU ainda a mantem acordada.

O grafico ganha escala fixa de 20 a 100 graus com marca a cada 20. A
GUI antiga desenha as linhas sem referencia nenhuma.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: O Painel

**Files:**
- Modify: `src/nexus_sense/telemetry.py` (acrescenta a leitura da bateria)
- Modify: `src/nexus_sense/gui/poller.py` (a bateria entra na amostra)
- Create: `src/nexus_sense/gui/pages/dashboard.py`
- Modify: `src/nexus_sense/gui/pages/__init__.py` (registra a página)
- Test: `tests/python/test_dashboard.py`

**Interfaces:**
- Consumes: `Sample` e `TemperatureGraph` da Task 4; `DeviceState` da Task 1.
- Produces:
  - `telemetry.BatteryReading` — `NamedTuple` com `capacity: int | None`, `status: str | None`
  - `telemetry.battery(sysfs) -> BatteryReading | None`
  - `telemetry.cpu_name(sysfs) -> str | None`
  - `telemetry.cpu_times(sysfs) -> tuple[int, int] | None` — `(ocioso, total)` em jiffies
  - `telemetry.cpu_usage(anterior, atual) -> float | None` — percentual entre duas leituras
  - `Sample` ganha os campos `battery: BatteryReading | None` e `cpu_usage: float | None`
  - `gui.pages.dashboard.LINHAS_POR_CARTAO = 3`
  - `gui.pages.dashboard.Card(title, fields)` com `set_value(chave, texto)` e `.rows: dict[str, QLabel]`
  - `gui.pages.dashboard.DashboardPage(controls)` com `.cards: dict[str, Card]`, `.graph` e `.header`

**Uso e modelo da CPU entram porque a decisão D1 pede paridade** com o que
a GUI binária entrega neste laptop, e a spec §2.4 lista `GetCpuUsage` e
`GetCpuName` entre o que ela mostra. As duas leituras saem de `/proc`,
por baixo da mesma raiz configurável — a regra de não abrir caminho
absoluto continua valendo, e a árvore de mentira ganha um `/proc`.

**Perfil e fonte não são cartão:** ficam numa linha de cabeçalho acima da
grade. Assim os três cartões de cima mantêm as mesmas três linhas, que é
o requisito de alinhamento.

**Por que a bateria entra na amostra e não no estado:** a carga muda a
cada minuto, como a temperatura, e não como o limite de carga. O
`DeviceState` guarda o que a interface controla; a `Sample`, o que ela
observa.

- [ ] **Step 1: A árvore de mentira ganha um `/proc`**

Em `tests/python/conftest.py`, dentro de `build_tree`, logo antes de
`# fonte de energia`:

```python
    # /proc por baixo da mesma raiz: uso e modelo da CPU saem daqui, e a
    # regra de nao abrir caminho absoluto continua valendo.
    escreve(root / "proc/cpuinfo", "processor\t: 0\nmodel name\t: Intel(R) Core(TM) i5-13420H")
    escreve(root / "proc/stat", "cpu  100 0 50 850 0 0 0 0 0 0")
```

- [ ] **Step 2: Escrever os testes que falham**

`tests/python/test_dashboard.py`:

```python
from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.dashboard import LINHAS_POR_CARTAO, DashboardPage
from nexus_sense.gui.poller import Poller
from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import battery

from conftest import build_tree

SUPERIORES = ("processador", "graficos", "ventoinhas")


def painel(qtbot, raiz):
    s = Sysfs(raiz)
    p = DashboardPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    p.apply_sample(Poller(s).read_now())
    return p


def test_le_a_bateria_do_power_supply(fake_root):
    leitura = battery(Sysfs(fake_root))
    assert leitura.capacity == 80
    assert leitura.status == "Not charging"


def test_sem_bateria_a_leitura_e_none(tmp_path):
    assert battery(Sysfs(tmp_path)) is None


def test_a_bateria_viaja_na_amostra(fake_root):
    assert Poller(Sysfs(fake_root)).read_now().battery.capacity == 80


def test_os_tres_cartoes_de_cima_tem_o_mesmo_numero_de_linhas(qtbot, fake_root):
    """Alinhamento de coluna e requisito, nao acabamento: hoje os cartoes
    da linha de cima tem alturas diferentes. Ver spec secao 6.1."""
    p = painel(qtbot, fake_root)
    for nome in SUPERIORES:
        assert len(p.cards[nome].rows) == LINHAS_POR_CARTAO


def test_os_tres_cartoes_de_cima_tem_a_mesma_altura(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    alturas = {p.cards[nome].sizeHint().height() for nome in SUPERIORES}
    assert len(alturas) == 1


def test_mostra_o_modelo_da_cpu(qtbot, fake_root):
    """Paridade com a GUI binaria, que tem GetCpuName. Ver decisao D1."""
    p = painel(qtbot, fake_root)
    assert "i5-13420H" in p.cards["processador"].rows["modelo"].text()


def test_a_primeira_amostra_nao_tem_uso_de_cpu(qtbot, fake_root):
    """Uso e diferenca entre duas leituras de /proc/stat: na primeira nao
    ha com o que comparar, e inventar um numero seria mentir."""
    p = painel(qtbot, fake_root)
    assert p.cards["processador"].rows["uso"].text() == "—"


def test_a_segunda_amostra_traz_o_uso(qtbot, fake_root):
    s = Sysfs(fake_root)
    poller = Poller(s)
    p = DashboardPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    p.apply_sample(poller.read_now())
    # 100 jiffies ocupados e 100 ociosos entre as duas leituras: 50%.
    (fake_root / "proc/stat").write_text("cpu  200 0 50 950 0 0 0 0 0 0\n")
    p.apply_sample(poller.read_now())
    assert "50" in p.cards["processador"].rows["uso"].text()


def test_mostra_a_temperatura_do_pacote_com_unidade(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert "47" in p.cards["processador"].rows["temperatura"].text()
    assert "°C" in p.cards["processador"].rows["temperatura"].text()


def test_mostra_a_rotacao_das_duas_ventoinhas(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert "2079" in p.cards["ventoinhas"].rows["cpu"].text()
    assert "1870" in p.cards["ventoinhas"].rows["gpu"].text()


def test_ventoinha_em_zero_e_automatica_e_nao_parada(qtbot, fake_root):
    """O atributo fan_speed e o setpoint: '0,0' quer dizer automatico.
    Chamar isso de 'parada' seria mentira. Ver spec secao 2.5."""
    p = painel(qtbot, fake_root)
    assert "automátic" in p.cards["ventoinhas"].rows["modo"].text().lower()


def test_setpoint_manual_aparece_como_manual(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text("70,80\n")
    p = painel(qtbot, raiz)
    texto = p.cards["ventoinhas"].rows["modo"].text()
    assert "70" in texto and "80" in texto


def test_gpu_adormecida_aparece_como_adormecida_e_sem_numeros(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / "sys/bus/pci/devices/0000:01:00.0/power/runtime_status").write_text("suspended\n")
    p = painel(qtbot, raiz)
    assert "adormecida" in p.cards["graficos"].rows["estado"].text().lower()
    assert p.cards["graficos"].rows["temperatura"].text() == "—"


def test_o_cabecalho_traz_o_perfil_com_o_nome_em_portugues(qtbot, tmp_path):
    """Fora dos cartoes de proposito: dentro deles quebraria as tres
    linhas iguais que o alinhamento exige."""
    raiz = build_tree(tmp_path / "t", profile="balanced-performance")
    p = painel(qtbot, raiz)
    assert "Desempenho" in p.header.text()


def test_o_cabecalho_traz_a_fonte_de_energia(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False)
    p = painel(qtbot, raiz)
    assert "bateria" in p.header.text().lower()


def test_le_o_uso_da_cpu_de_duas_leituras(fake_root):
    from nexus_sense.telemetry import cpu_times, cpu_usage

    antes = cpu_times(Sysfs(fake_root))
    assert antes == (850, 1000)
    assert cpu_usage(None, antes) is None
    assert cpu_usage(antes, (900, 1100)) == 50.0


def test_uso_sem_tempo_decorrido_e_none(fake_root):
    from nexus_sense.telemetry import cpu_usage

    assert cpu_usage((850, 1000), (850, 1000)) is None


def test_a_carga_da_bateria_aparece_com_o_limite(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert "80" in p.cards["bateria"].rows["carga"].text()
    assert "80" in p.cards["bateria"].rows["limite"].text()


def test_a_amostra_alimenta_o_grafico(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert list(p.graph.samples) == [47.0]


def test_o_painel_sempre_tem_conteudo(qtbot, fake_root):
    """Com o modulo carregado ha sempre o que mostrar: nem que seja so a
    bateria e a fonte."""
    p = painel(qtbot, fake_root)
    assert p.has_content(read_state(Sysfs(fake_root))) is True
```

- [ ] **Step 3: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_dashboard.py -q
```

Esperado: `ImportError: cannot import name 'battery' from 'nexus_sense.telemetry'`.

- [ ] **Step 4: Ler a bateria**

Ao **fim** de `src/nexus_sense/telemetry.py`:

```python
# Como no AC_NAMES do sysfs.py: o nome varia por firmware. Nesta maquina
# e BAT1, mas BAT0 e o mais comum por ai.
BATTERY_NAMES = ("BAT0", "BAT1", "BATT", "CMB0")


class BatteryReading(NamedTuple):
    capacity: int | None
    status: str | None


def battery(sysfs):
    """Carga e estado da bateria. None quando nao ha bateria nenhuma."""
    base = sysfs.root / "sys/class/power_supply"
    for nome in BATTERY_NAMES:
        pasta = base / nome
        if not (pasta / "capacity").is_file():
            continue
        try:
            carga = int(sysfs.read(pasta / "capacity"))
        except (OSError, ValueError):
            carga = None
        try:
            estado = sysfs.read(pasta / "status")
        except OSError:
            estado = None
        return BatteryReading(capacity=carga, status=estado)
    return None


def cpu_name(sysfs):
    """O 'model name' do primeiro nucleo, como o /proc/cpuinfo o escreve."""
    try:
        for linha in (sysfs.root / "proc/cpuinfo").read_text().splitlines():
            if linha.startswith("model name"):
                return linha.split(":", 1)[1].strip()
    except OSError:
        return None
    return None


def cpu_times(sysfs):
    """(ocioso, total) em jiffies, da primeira linha de /proc/stat."""
    try:
        primeira = (sysfs.root / "proc/stat").read_text().splitlines()[0]
    except (OSError, IndexError):
        return None
    campos = primeira.split()
    if campos[0] != "cpu" or len(campos) < 6:
        return None
    try:
        numeros = [int(c) for c in campos[1:]]
    except ValueError:
        return None
    # user nice system idle iowait irq softirq ... -- ocioso e idle+iowait
    return numeros[3] + numeros[4], sum(numeros)


def cpu_usage(anterior, atual):
    """Percentual entre duas leituras de cpu_times.

    None na primeira leitura, porque nao ha com o que comparar. Inventar
    um numero ali seria mentir sobre a unica coisa que este campo diz.
    """
    if anterior is None or atual is None:
        return None
    ocioso = atual[0] - anterior[0]
    total = atual[1] - anterior[1]
    if total <= 0:
        return None
    return max(0.0, min(100.0, 100.0 * (1.0 - ocioso / total)))
```

- [ ] **Step 5: Levar a bateria e o uso na amostra**

Em `src/nexus_sense/gui/poller.py`, acrescente os dois campos à `Sample`,
depois de `gpu`:

```python
    battery: object | None   # telemetry.BatteryReading ou None
    cpu_usage: float | None
```

guarde a leitura anterior, no fim do `__init__`:

```python
        # Uso de CPU e diferenca entre duas leituras de /proc/stat, entao
        # a passada anterior precisa sobreviver ate a proxima.
        self._cpu_anterior = None
```

e troque o corpo do `read_now` por:

```python
    def read_now(self):
        """Uma leitura sincrona. Usada pelo start e pelos testes."""
        cpu_agora = telemetry.cpu_times(self.sysfs)
        uso = telemetry.cpu_usage(self._cpu_anterior, cpu_agora)
        self._cpu_anterior = cpu_agora
        return Sample(
            fans=telemetry.fan_rpm(self.sysfs),
            acer_temps=telemetry.acer_temperatures(self.sysfs),
            cpu_temp=telemetry.cpu_package_temp(self.sysfs),
            gpu=telemetry.read_gpu(self.sysfs),
            battery=telemetry.battery(self.sysfs),
            cpu_usage=uso,
        )
```

- [ ] **Step 6: Implementar o Painel**

`src/nexus_sense/gui/pages/dashboard.py`:

```python
"""Painel: o que a maquina esta fazendo agora.

Alinhamento e requisito desta tela, nao acabamento. Os tres cartoes da
linha de cima tem o mesmo numero de linhas, na mesma ordem de campos, e
por isso a mesma altura -- e por isso os olhos varrem em coluna. Hoje a
GUI antiga tem tres alturas diferentes. Ver spec secao 6.1.

Campo sem valor mostra travessao, nunca zero: zero e um numero, e
numero errado engana.
"""

from PySide6.QtWidgets import (
    QFormLayout,
    QFrame,
    QGridLayout,
    QLabel,
    QVBoxLayout,
    QWidget,
)
from PySide6.QtCore import Signal

from ... import model, telemetry
from ..graph import TemperatureGraph

VAZIO = "—"

# Os tres cartoes de cima tem exatamente este numero de linhas. Cartao
# com menos informacao preenche com travessao em vez de encolher.
LINHAS_POR_CARTAO = 3


class Card(QFrame):
    """Cartao de titulo e linhas rotulo/valor, com altura previsivel."""

    def __init__(self, title, fields, parent=None):
        super().__init__(parent)
        self.setFrameShape(QFrame.StyledPanel)
        self.rows = {}

        leiaute = QVBoxLayout(self)
        titulo = QLabel(title)
        titulo.setObjectName("cartao_titulo")
        leiaute.addWidget(titulo)

        formulario = QFormLayout()
        formulario.setLabelAlignment(formulario.labelAlignment())
        for chave, rotulo in fields:
            valor = QLabel(VAZIO)
            valor.setObjectName(f"valor_{chave}")
            formulario.addRow(f"{rotulo}:", valor)
            self.rows[chave] = valor
        leiaute.addLayout(formulario)

    def set_value(self, chave, texto):
        self.rows[chave].setText(texto if texto else VAZIO)


class DashboardPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls
        self.graph = TemperatureGraph()

        self.header = QLabel("")
        self.header.setObjectName("painel_cabecalho")

        self.cards = {
            "processador": Card(
                "Processador",
                (("modelo", "Modelo"), ("uso", "Uso"), ("temperatura", "Temperatura")),
            ),
            "graficos": Card(
                "Gráficos",
                (("estado", "Estado"), ("temperatura", "Temperatura"), ("uso", "Uso")),
            ),
            "ventoinhas": Card(
                "Ventoinhas",
                (("cpu", "CPU"), ("gpu", "GPU"), ("modo", "Modo")),
            ),
            "bateria": Card(
                "Bateria",
                (("carga", "Carga"), ("estado", "Estado"), ("limite", "Limite de carga")),
            ),
        }

        grade = QGridLayout()
        for coluna, nome in enumerate(("processador", "graficos", "ventoinhas")):
            grade.addWidget(self.cards[nome], 0, coluna)
            grade.setColumnStretch(coluna, 1)

        temperatura = Card("Temperatura", ())
        temperatura.layout().addWidget(self.graph)
        grade.addWidget(temperatura, 1, 0, 1, 2)
        grade.addWidget(self.cards["bateria"], 1, 2)

        raiz = QVBoxLayout(self)
        raiz.addWidget(self.header)
        raiz.addLayout(grade)
        raiz.addStretch(1)

        # O modelo da CPU nao muda enquanto o programa roda: le uma vez.
        self._cpu_name = None

    def has_content(self, state):
        return True

    def apply_state(self, state):
        perfil = state.profile
        fonte = {True: "na tomada", False: "na bateria"}.get(state.on_ac, VAZIO)
        rotulo = f"{model.LABELS.get(perfil, perfil)} ({perfil})" if perfil else VAZIO
        self.header.setText(f"Perfil: {rotulo}   ·   {fonte}")

        if self._cpu_name is None:
            self._cpu_name = telemetry.cpu_name(self.controls.sysfs) or VAZIO
        self.cards["processador"].set_value("modelo", self._cpu_name)

        # O setpoint, nao a rotacao: "0,0" e automatico. Ver spec secao 2.5.
        if state.fan_speed is None:
            self.cards["ventoinhas"].set_value("modo", VAZIO)
        elif state.fan_speed == (0, 0):
            self.cards["ventoinhas"].set_value("modo", "automático")
        else:
            cpu, gpu = state.fan_speed
            self.cards["ventoinhas"].set_value("modo", f"manual — {cpu}% / {gpu}%")

        self.cards["bateria"].set_value(
            "limite",
            "80% (limitador ligado)" if state.battery_limiter else "sem limite",
        )

    def apply_sample(self, sample):
        self.cards["processador"].set_value(
            "temperatura",
            f"{sample.cpu_temp:.1f} °C" if sample.cpu_temp is not None else VAZIO,
        )
        self.cards["processador"].set_value(
            "uso",
            f"{sample.cpu_usage:.0f}%" if sample.cpu_usage is not None else VAZIO,
        )
        self.graph.add_sample(sample.cpu_temp)

        if sample.fans is None:
            self.cards["ventoinhas"].set_value("cpu", VAZIO)
            self.cards["ventoinhas"].set_value("gpu", VAZIO)
        else:
            cpu, gpu = sample.fans
            self.cards["ventoinhas"].set_value("cpu", f"{cpu} rpm")
            self.cards["ventoinhas"].set_value("gpu", f"{gpu} rpm")

        self._aplica_gpu(sample.gpu)

        if sample.battery is None:
            self.cards["bateria"].set_value("carga", VAZIO)
            self.cards["bateria"].set_value("estado", VAZIO)
        else:
            carga = sample.battery.capacity
            self.cards["bateria"].set_value(
                "carga", f"{carga}%" if carga is not None else VAZIO
            )
            self.cards["bateria"].set_value("estado", sample.battery.status or VAZIO)

    def _aplica_gpu(self, leitura):
        cartao = self.cards["graficos"]
        if leitura is None:
            cartao.set_value("estado", "ausente")
            cartao.set_value("temperatura", VAZIO)
            cartao.set_value("uso", VAZIO)
            return
        if leitura.asleep:
            # Nao sondamos, e dizer isso e melhor do que mostrar vazio sem
            # explicacao. Ver spec secao 10.2.
            cartao.set_value("estado", "adormecida")
            cartao.set_value("temperatura", VAZIO)
            cartao.set_value("uso", VAZIO)
            return
        cartao.set_value("estado", "ativa")
        cartao.set_value(
            "temperatura",
            f"{leitura.temperature:.0f} °C" if leitura.temperature is not None else VAZIO,
        )
        cartao.set_value(
            "uso", f"{leitura.utilization}%" if leitura.utilization is not None else VAZIO
        )
```

- [ ] **Step 7: Registrar a página**

Em `src/nexus_sense/gui/pages/__init__.py`, o import e a tupla:

```python
from .dashboard import DashboardPage
from .performance import PerformancePage


def build_pages(controls):
    """As secoes, na ordem em que aparecem na barra lateral."""
    return (
        ("painel", "Painel", DashboardPage(controls)),
        ("desempenho", "Desempenho", PerformancePage(controls)),
    )
```

- [ ] **Step 8: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_dashboard.py -q && python3 -m pytest -q
```

Esperado: `21 passed` no arquivo, e a suíte inteira verde.

- [ ] **Step 9: Ver o Painel contra o hardware**

```bash
PYTHONPATH=src python3 -m nexus_sense.gui.app
```

Esperado: Painel e Desempenho na barra lateral; os três cartões de cima
com a mesma altura e a mesma ordem de campos; a temperatura subindo no
gráfico a cada 2 s, entre as marcas de 20 e 100 °C. Compare a rotação
mostrada com:

```bash
cat /sys/devices/platform/acer-wmi/hwmon/hwmon*/fan1_input
```

- [ ] **Step 10: Commit**

```bash
git add src/nexus_sense/telemetry.py src/nexus_sense/gui/poller.py \
        src/nexus_sense/gui/pages/dashboard.py src/nexus_sense/gui/pages/__init__.py \
        tests/python/test_dashboard.py
git commit -m "feat: o Painel, com os cartoes de cima alinhados

Mesma quantidade de linhas, mesma ordem de campos e mesma altura nos
tres cartoes superiores -- e requisito da tela, e os testes verificam.

Campo sem valor mostra travessao, nunca zero. E a ventoinha em '0,0'
aparece como automatica, porque esse atributo e o setpoint: chamar de
'parada' seria mentira.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Bateria e Teclado

Duas páginas de uma linha por controle, e a regra que faz seção sem
recurso sumir. Vão juntas porque compartilham a mesma linha e a mesma
regra; um revisor que aprova uma aprova a outra.

**Files:**
- Create: `src/nexus_sense/gui/pages/rows.py`
- Create: `src/nexus_sense/gui/pages/battery.py`
- Create: `src/nexus_sense/gui/pages/keyboard.py`
- Modify: `src/nexus_sense/gui/pages/__init__.py`
- Test: `tests/python/test_battery_keyboard.py`

**Interfaces:**
- Consumes: `Controls`, `WriteError`, `DeviceState`.
- Produces:
  - `gui.pages.rows.ControlRow(title, subtitle, widget)` com `.widget`, `.set_reason(texto)`
  - `gui.pages.battery.BatteryPage(controls)` com `.rows: dict[str, ControlRow]` e `.message_label`
  - `gui.pages.keyboard.KeyboardPage(controls)` com `.rows: dict[str, ControlRow]` e `.message_label`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_battery_keyboard.py`:

```python
import errno

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.battery import BatteryPage
from nexus_sense.gui.pages.keyboard import KeyboardPage
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

SENSE = "sys/devices/platform/acer-wmi/nitro_sense"


def monta(qtbot, classe, raiz):
    s = Sysfs(raiz)
    p = classe(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    return p


def test_a_bateria_tem_as_tres_linhas(qtbot, fake_root):
    """Os tres cartoes de hoje viram tres linhas de uma lista.
    Ver spec secao 6.3."""
    p = monta(qtbot, BatteryPage, fake_root)
    assert tuple(p.rows) == ("battery_limiter", "usb_charging", "battery_calibration")


def test_o_aviso_da_calibracao_e_o_subtitulo_da_linha_dela(qtbot, fake_root):
    """Deixa de ser paragrafo solto e passa a pertencer ao controle a que
    se refere. Ver spec secao 6.3."""
    p = monta(qtbot, BatteryPage, fake_root)
    assert "tomada" in p.rows["battery_calibration"].subtitle.text().lower()


def test_o_estado_dos_controles_vem_do_sysfs(qtbot, fake_root):
    p = monta(qtbot, BatteryPage, fake_root)
    assert p.rows["battery_limiter"].widget.isChecked() is True
    assert p.rows["usb_charging"].widget.currentData() == 0


def test_aplicar_o_estado_nao_dispara_escrita(qtbot, fake_root):
    """Armadilha classica de Qt: setChecked emite toggled, e sem bloquear
    o sinal a tela escreveria no sysfs so por ter sido repintada."""
    escritas = []
    p = monta(qtbot, BatteryPage, fake_root)
    p.controls.sysfs.write = lambda caminho, valor: escritas.append((caminho, valor))
    p.apply_state(read_state(Sysfs(fake_root)))
    assert escritas == []


def test_desmarcar_o_limitador_escreve_zero(qtbot, fake_root):
    p = monta(qtbot, BatteryPage, fake_root)
    p.rows["battery_limiter"].widget.setChecked(False)
    assert (fake_root / SENSE / "battery_limiter").read_text().strip() == "0"


def test_escolher_a_carga_usb_escreve_o_nivel(qtbot, fake_root):
    p = monta(qtbot, BatteryPage, fake_root)
    combo = p.rows["usb_charging"].widget
    combo.setCurrentIndex(combo.findData(20))
    assert (fake_root / SENSE / "usb_charging").read_text().strip() == "20"


def test_linha_de_recurso_ausente_some(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "usb_charging").unlink()
    p = monta(qtbot, BatteryPage, raiz)
    assert p.rows["usb_charging"].isVisible() is False
    assert p.rows["battery_limiter"].isVisible() is True


def test_sem_nenhum_dos_tres_a_secao_nao_tem_conteudo(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    for nome in ("battery_limiter", "usb_charging", "battery_calibration"):
        (raiz / SENSE / nome).unlink()
    s = Sysfs(raiz)
    p = BatteryPage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is False


def test_o_teclado_tem_o_unico_controle_que_o_firmware_anuncia(qtbot, fake_root):
    """Um controle so. O RGB de quatro zonas esta fora de escopo.
    Ver spec secao 6.4 e secao 14."""
    p = monta(qtbot, KeyboardPage, fake_root)
    assert tuple(p.rows) == ("backlight_timeout",)


def test_sem_backlight_timeout_a_secao_teclado_some(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / SENSE / "backlight_timeout").unlink()
    s = Sysfs(raiz)
    p = KeyboardPage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is False


def test_o_teclado_escreve_ao_marcar(qtbot, fake_root):
    p = monta(qtbot, KeyboardPage, fake_root)
    p.rows["backlight_timeout"].widget.setChecked(True)
    assert (fake_root / SENSE / "backlight_timeout").read_text().strip() == "1"


def test_erro_de_escrita_vira_frase_na_pagina(qtbot, fake_root):
    p = monta(qtbot, KeyboardPage, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EACCES, "Permission denied")

    p.controls.sysfs.write = recusa
    p.rows["backlight_timeout"].widget.setChecked(True)
    assert "grupo" in p.message_label.text()


def test_sem_permissao_o_controle_fica_desligado_com_o_motivo(qtbot, tmp_path):
    import os
    import pytest

    if os.geteuid() == 0:
        pytest.skip("root ignora a permissão do arquivo")
    raiz = build_tree(tmp_path / "t")
    alvo = raiz / SENSE / "battery_limiter"
    alvo.chmod(0o444)
    try:
        p = monta(qtbot, BatteryPage, raiz)
    finally:
        alvo.chmod(0o644)
    linha = p.rows["battery_limiter"]
    assert linha.widget.isEnabled() is False
    assert "grupo" in linha.reason.text()
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_battery_keyboard.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.gui.pages.battery'`.

- [ ] **Step 3: Implementar a linha**

`src/nexus_sense/gui/pages/rows.py`:

```python
"""A linha de controle que Bateria e Teclado usam.

Titulo, subtitulo e o controle a direita. O subtitulo e onde mora o
aviso que pertence aquele controle -- e nao um paragrafo solto no fim da
tela, como na GUI antiga. Ver spec secao 6.3.
"""

from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout

# Frase unica para os dois motivos de nao poder escrever: estar fora do
# grupo, e estar nele numa sessao que ainda nao o herdou. O sintoma e o
# mesmo e a saida tambem. Ver spec secao 9.
SEM_PERMISSAO = (
    "somente leitura: a sessão não tem o grupo nexus_sense "
    "(se você acabou de entrar no grupo, relogue)"
)


class ControlRow(QFrame):
    def __init__(self, title, subtitle, widget, parent=None):
        super().__init__(parent)
        self.setFrameShape(QFrame.StyledPanel)
        self.widget = widget

        self.title = QLabel(title)
        self.title.setObjectName("linha_titulo")
        self.subtitle = QLabel(subtitle)
        self.subtitle.setObjectName("linha_subtitulo")
        self.subtitle.setWordWrap(True)
        self.subtitle.setVisible(bool(subtitle))
        self.reason = QLabel("")
        self.reason.setObjectName("linha_motivo")
        self.reason.setWordWrap(True)
        self.reason.setVisible(False)

        texto = QVBoxLayout()
        texto.addWidget(self.title)
        texto.addWidget(self.subtitle)
        texto.addWidget(self.reason)

        leiaute = QHBoxLayout(self)
        leiaute.addLayout(texto, 1)
        leiaute.addWidget(widget)

    def set_reason(self, texto):
        self.reason.setText(texto)
        self.reason.setVisible(bool(texto))
```

- [ ] **Step 4: Implementar a página Bateria**

`src/nexus_sense/gui/pages/battery.py`:

```python
"""Bateria: limite de carga, carregamento USB e calibracao."""

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QCheckBox, QComboBox, QLabel, QVBoxLayout, QWidget

from ... import model
from ...device import WriteError
from .rows import SEM_PERMISSAO, ControlRow

NIVEIS_USB = (
    (0, "desligado"),
    (10, "para de fornecer abaixo de 10%"),
    (20, "para de fornecer abaixo de 20%"),
    (30, "para de fornecer abaixo de 30%"),
)


class BatteryPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls
        self.message_label = QLabel("")
        self.message_label.setWordWrap(True)

        limitador = QCheckBox()
        limitador.toggled.connect(
            lambda ligado: self._escreve(self.controls.set_battery_limiter, ligado)
        )

        usb = QComboBox()
        for nivel, rotulo in NIVEIS_USB:
            usb.addItem(rotulo, nivel)
        usb.currentIndexChanged.connect(
            lambda _: self._escreve(self.controls.set_usb_charging, usb.currentData())
        )

        calibracao = QCheckBox()
        calibracao.toggled.connect(
            lambda ligado: self._escreve(self.controls.set_battery_calibration, ligado)
        )

        self.rows = {
            "battery_limiter": ControlRow(
                "Limite de carga",
                "para de carregar em 80% para preservar a bateria",
                limitador,
            ),
            "usb_charging": ControlRow(
                "Carregamento USB com a tampa fechada",
                "abaixo do nível escolhido, as portas param de fornecer energia",
                usb,
            ),
            "battery_calibration": ControlRow(
                "Calibração da bateria",
                "não tire da tomada durante a calibração: o ciclo precisa "
                "descarregar e carregar por completo",
                calibracao,
            ),
        }

        raiz = QVBoxLayout(self)
        titulo = QLabel("Bateria")
        titulo.setObjectName("titulo")
        raiz.addWidget(titulo)
        for linha in self.rows.values():
            raiz.addWidget(linha)
        raiz.addWidget(self.message_label)
        raiz.addStretch(1)

    def has_content(self, state):
        return bool(set(self.rows) & set(state.features))

    def apply_state(self, state):
        valores = {
            "battery_limiter": state.battery_limiter,
            "usb_charging": state.usb_charging,
            "battery_calibration": state.battery_calibration,
        }
        for nome, linha in self.rows.items():
            existe = nome in state.features
            linha.setVisible(existe)
            if not existe:
                continue
            gravavel = nome in state.writable
            linha.widget.setEnabled(gravavel)
            linha.set_reason("" if gravavel else SEM_PERMISSAO)

            # Bloquear o sinal e obrigatorio: setChecked emite toggled, e
            # sem isto repintar a tela escreveria no sysfs.
            linha.widget.blockSignals(True)
            if nome == "usb_charging":
                indice = linha.widget.findData(valores[nome])
                if indice >= 0:
                    linha.widget.setCurrentIndex(indice)
            else:
                linha.widget.setChecked(bool(valores[nome]))
            linha.widget.blockSignals(False)

    def _escreve(self, funcao, valor):
        self.message_label.setText("")
        try:
            funcao(valor)
        except (WriteError, ValueError) as erro:
            self.message_label.setText(getattr(erro, "message", str(erro)))
        self.changed.emit()
```

- [ ] **Step 5: Implementar a página Teclado**

`src/nexus_sense/gui/pages/keyboard.py`:

```python
"""Teclado: o unico recurso que este firmware anuncia.

O RGB de quatro zonas esta fora de escopo -- este laptop nao o tem
(has_four_zone_kb: false) e o codigo seria escrito sem poder ser
verificado. Ver spec secao 14.

Sai tambem o aviso laranja "This Section Requires Testing" da GUI
antiga: e nota de desenvolvimento vazando para a interface.
"""

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QCheckBox, QLabel, QVBoxLayout, QWidget

from ...device import WriteError
from .rows import SEM_PERMISSAO, ControlRow


class KeyboardPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls
        self.message_label = QLabel("")
        self.message_label.setWordWrap(True)

        caixa = QCheckBox()
        caixa.toggled.connect(self._escreve)

        self.rows = {
            "backlight_timeout": ControlRow(
                "Apagar a iluminação após inatividade",
                "apaga o teclado depois de 30 segundos sem uso",
                caixa,
            )
        }

        raiz = QVBoxLayout(self)
        titulo = QLabel("Teclado")
        titulo.setObjectName("titulo")
        raiz.addWidget(titulo)
        for linha in self.rows.values():
            raiz.addWidget(linha)
        raiz.addWidget(self.message_label)
        raiz.addStretch(1)

    def has_content(self, state):
        return "backlight_timeout" in state.features

    def apply_state(self, state):
        linha = self.rows["backlight_timeout"]
        existe = "backlight_timeout" in state.features
        linha.setVisible(existe)
        if not existe:
            return
        gravavel = "backlight_timeout" in state.writable
        linha.widget.setEnabled(gravavel)
        linha.set_reason("" if gravavel else SEM_PERMISSAO)
        linha.widget.blockSignals(True)
        linha.widget.setChecked(bool(state.backlight_timeout))
        linha.widget.blockSignals(False)

    def _escreve(self, ligado):
        self.message_label.setText("")
        try:
            self.controls.set_backlight_timeout(ligado)
        except WriteError as erro:
            self.message_label.setText(erro.message)
        self.changed.emit()
```

- [ ] **Step 6: Registrar as páginas**

`src/nexus_sense/gui/pages/__init__.py` — a tupla passa a ter quatro:

```python
from .battery import BatteryPage
from .dashboard import DashboardPage
from .keyboard import KeyboardPage
from .performance import PerformancePage


def build_pages(controls):
    """As secoes, na ordem em que aparecem na barra lateral."""
    return (
        ("painel", "Painel", DashboardPage(controls)),
        ("desempenho", "Desempenho", PerformancePage(controls)),
        ("bateria", "Bateria", BatteryPage(controls)),
        ("teclado", "Teclado", KeyboardPage(controls)),
    )
```

- [ ] **Step 7: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_battery_keyboard.py -q && python3 -m pytest -q
```

Esperado: `13 passed` no arquivo, e a suíte inteira verde.

- [ ] **Step 8: Commit**

```bash
git add src/nexus_sense/gui/pages tests/python/test_battery_keyboard.py
git commit -m "feat: paginas Bateria e Teclado

Tres linhas e uma linha, e a regra de sumir: recurso que o firmware nao
anuncia nao aparece cinza, some -- e a secao inteira some com ele.

O aviso da calibracao vira subtitulo da linha a que pertence, em vez de
paragrafo solto no fim da tela.

Os sinais sao bloqueados ao aplicar o estado. Sem isso, setChecked
emitiria toggled e repintar a tela escreveria no sysfs.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Diagnóstico — sistema e verificações

Esta tela existe para responder **"por que aquele botão está cinza?"**.
Ver spec §6.5.

**Files:**
- Modify: `src/nexus_sense/device.py` (acrescenta `SystemInfo` e `read_system`)
- Modify: `src/nexus_sense/session.py` (acrescenta `in_group` e `ppd_state`)
- Create: `src/nexus_sense/gui/pages/diagnostics.py`
- Modify: `src/nexus_sense/gui/pages/__init__.py`
- Modify: `tests/python/conftest.py` (a árvore ganha DMI e parâmetros do módulo)
- Test: `tests/python/test_diagnostics.py`

**Interfaces:**
- Consumes: `DeviceState`, `agent_active`.
- Produces:
  - `device.SystemInfo` — `NamedTuple` com `product: str | None`, `family: str | None`, `driver_version: str | None`, `module_params: dict[str, str]`
  - `device.read_system(sysfs) -> SystemInfo`
  - `session.in_group(name, groups=None) -> bool`
  - `session.PpdState` — `NamedTuple` com `present: bool`, `profile: str | None`, `drives_platform: bool`
  - `session.ppd_state(runner=subprocess.run) -> PpdState`
  - `gui.pages.diagnostics.Check` — `NamedTuple` com `label: str`, `ok: bool`, `detail: str`
  - `gui.pages.diagnostics.run_checks(state, *, agent, ppd, in_group) -> tuple[Check, ...]`
  - `gui.pages.diagnostics.DiagnosticsPage(controls)` com `.system_card`, `.checks_box`

- [ ] **Step 1: A árvore de mentira ganha DMI e parâmetros**

Em `tests/python/conftest.py`, dentro de `build_tree`, logo depois do bloco
`if module:`:

```python
    # DMI e o que a spec chama de "modelo" no Diagnostico.
    escreve(root / "sys/class/dmi/id/product_name", "Nitro ANV15-52")
    escreve(root / "sys/class/dmi/id/sys_vendor", "Acer")

    # Parametros do modulo em vigor. 'N' e como o kernel imprime um bool
    # desligado; e assim que este esta nesta maquina.
    if module:
        for parametro in ("nitro_v4", "predator_v4", "enable_all"):
            escreve(root / "sys/module" / module / "parameters" / parametro, "N")
```

- [ ] **Step 2: Escrever os testes que falham**

`tests/python/test_diagnostics.py`:

```python
import subprocess

from nexus_sense.device import Controls, read_state, read_system
from nexus_sense.gui.pages.diagnostics import DiagnosticsPage, run_checks
from nexus_sense.session import PpdState, in_group, ppd_state
from nexus_sense.sysfs import Sysfs

from conftest import build_tree

PPD_LIST = """  balanced:
    CpuDriver:      intel_pstate
    PlatformDriver: placeholder

* performance:
    CpuDriver:      intel_pstate
    PlatformDriver: placeholder
"""

PPD_LIST_DISPUTANDO = """  balanced:
    CpuDriver:      intel_pstate
    PlatformDriver: platform_profile
"""


def runner_ppd(saida_list, perfil="performance", codigo=0):
    def runner(args, **kwargs):
        texto = perfil + "\n" if args[-1] == "get" else saida_list
        return subprocess.CompletedProcess(args, codigo, stdout=texto, stderr="")

    return runner


# ---------------------------------------------------------------- sistema


def test_o_sistema_traz_modelo_versao_e_parametros(fake_root):
    s = read_system(Sysfs(fake_root))
    assert s.product == "Nitro ANV15-52"
    assert s.driver_version == "25.701"
    assert s.module_params["nitro_v4"] == "N"


def test_a_familia_vem_do_nome_do_grupo_de_atributos(tmp_path):
    """nitro_sense e predator_sense estao fixados no .c e nomeiam a
    familia do laptop, nao o projeto. Ver spec secao 2.13."""
    assert read_system(Sysfs(build_tree(tmp_path / "a"))).family == "nitro"
    outra = build_tree(tmp_path / "b", sense="predator_sense")
    assert read_system(Sysfs(outra)).family == "predator"


def test_arvore_vazia_nao_derruba_o_sistema(tmp_path):
    s = read_system(Sysfs(tmp_path))
    assert s.product is None and s.family is None and s.module_params == {}


# ------------------------------------------------------------------- ppd


def test_ppd_ausente_nao_e_erro():
    def explode(args, **kwargs):
        raise FileNotFoundError("powerprofilesctl")

    estado = ppd_state(runner=explode)
    assert estado.present is False
    assert estado.drives_platform is False


def test_ppd_com_placeholder_nao_disputa_o_perfil():
    """Medido nesta maquina: o ppd 0.30 dirige o intel_pstate e nao se
    ligou ao platform_profile. Por isso ele diz 'performance' enquanto o
    platform_profile diz 'balanced', sem conflito. Ver spec secao 2.11."""
    estado = ppd_state(runner=runner_ppd(PPD_LIST))
    assert estado.present is True
    assert estado.profile == "performance"
    assert estado.drives_platform is False


def test_ppd_ligado_ao_platform_profile_e_sinalizado():
    estado = ppd_state(runner=runner_ppd(PPD_LIST_DISPUTANDO))
    assert estado.drives_platform is True


# ----------------------------------------------------------------- grupo


def test_estar_no_grupo_e_lido_da_sessao():
    assert in_group("nexus_sense", groups=("wheel", "nexus_sense")) is True
    assert in_group("nexus_sense", groups=("wheel",)) is False


# ------------------------------------------------------------ as checagens


def base(fake_root):
    return read_state(Sysfs(fake_root))


def rotulos(checagens):
    return [c.label for c in checagens]


def test_as_quatro_verificacoes_aparecem_sempre(fake_root):
    c = run_checks(base(fake_root), agent=True, ppd=PpdState(False, None, False), in_group=True)
    assert len(c) == 4


def test_tudo_certo_da_quatro_verdes(fake_root):
    c = run_checks(base(fake_root), agent=True, ppd=PpdState(False, None, False), in_group=True)
    assert all(x.ok for x in c)


def test_fora_do_grupo_e_apontado_com_a_saida(fake_root):
    c = run_checks(base(fake_root), agent=True, ppd=PpdState(False, None, False), in_group=False)
    permissao = [x for x in c if "grupo" in x.label.lower()][0]
    assert permissao.ok is False
    assert "usermod" in permissao.detail


def test_no_grupo_mas_sem_permissao_aplicada_fala_de_relogar(tmp_path):
    """Sintoma identico ao de estar fora do grupo, causa diferente: quem
    acabou de entrar precisa relogar. Ver spec secao 9."""
    import os
    import pytest

    if os.geteuid() == 0:
        pytest.skip("root ignora a permissão do arquivo")
    raiz = build_tree(tmp_path / "t")
    alvo = raiz / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    alvo.chmod(0o444)
    try:
        estado = read_state(Sysfs(raiz))
    finally:
        alvo.chmod(0o644)
    c = run_checks(estado, agent=True, ppd=PpdState(False, None, False), in_group=True)
    permissao = [x for x in c if "grupo" in x.label.lower()][0]
    assert permissao.ok is False
    assert "relogar" in permissao.detail


def test_agente_fora_do_ar_e_apontado(fake_root):
    c = run_checks(base(fake_root), agent=False, ppd=PpdState(False, None, False), in_group=True)
    agente = [x for x in c if "agente" in x.label.lower()][0]
    assert agente.ok is False
    assert "systemctl --user" in agente.detail


def test_ppd_que_nao_disputa_passa_e_diz_por_que(fake_root):
    c = run_checks(
        base(fake_root),
        agent=True,
        ppd=PpdState(True, "performance", False),
        in_group=True,
    )
    linha = [x for x in c if "power-profiles" in x.label.lower()][0]
    assert linha.ok is True
    assert "não disputa" in linha.detail


def test_ppd_disputando_falha_a_verificacao(fake_root):
    c = run_checks(
        base(fake_root),
        agent=True,
        ppd=PpdState(True, "balanced", True),
        in_group=True,
    )
    linha = [x for x in c if "power-profiles" in x.label.lower()][0]
    assert linha.ok is False


def test_modulo_descarregado_falha_a_primeira(tmp_path):
    estado = read_state(Sysfs(tmp_path))
    c = run_checks(estado, agent=True, ppd=PpdState(False, None, False), in_group=True)
    assert c[0].ok is False
    assert "modprobe" in c[0].detail


# ------------------------------------------------------------------ tela


def test_a_pagina_desenha_as_verificacoes(qtbot, fake_root):
    s = Sysfs(fake_root)
    p = DiagnosticsPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    assert p.checks_box.layout().count() >= 4


def test_o_diagnostico_sempre_tem_conteudo(qtbot, tmp_path):
    """Justamente quando nada funciona e que ele precisa aparecer."""
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    s = Sysfs(vazia)
    p = DiagnosticsPage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is True
```

- [ ] **Step 3: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_diagnostics.py -q
```

Esperado: `ImportError: cannot import name 'read_system'`.

- [ ] **Step 4: Implementar o `read_system`**

Ao **fim** de `src/nexus_sense/device.py`:

```python
class SystemInfo(NamedTuple):
    product: str | None
    family: str | None                # 'nitro', 'predator' ou None
    driver_version: str | None
    module_params: dict


def read_system(sysfs):
    """Identidade da maquina e do driver, para o Diagnostico."""
    sense = sysfs.sense_dir()
    familia = None
    if sense is not None:
        familia = sense.name.split("_", 1)[0]

    parametros = {}
    for nome in ("nexus_sense", "linuwu_sense"):
        pasta = sysfs.root / "sys/module" / nome / "parameters"
        if not pasta.is_dir():
            continue
        for arquivo in sorted(pasta.iterdir()):
            valor = _read(sysfs, arquivo)
            if valor is not None:
                parametros[arquivo.name] = valor
        break

    return SystemInfo(
        product=_read(sysfs, sysfs.root / "sys/class/dmi/id/product_name"),
        family=familia,
        driver_version=_read(sysfs, sense / "version") if sense is not None else None,
        module_params=parametros,
    )
```

- [ ] **Step 5: Implementar o `in_group` e o `ppd_state`**

Ao **fim** de `src/nexus_sense/session.py`:

```python
import grp
import os
from typing import NamedTuple

GROUP = "nexus_sense"


def in_group(name, groups=None):
    """True quando a sessao corrente carrega este grupo.

    Repare: carregar o grupo e diferente de estar listado nele em
    /etc/group. Quem acabou de entrar so passa a carrega-lo depois de
    relogar, e e por isso que a tela precisa distinguir os dois casos.
    """
    if groups is None:
        try:
            groups = [grp.getgrgid(gid).gr_name for gid in os.getgroups()]
        except (KeyError, OSError):
            groups = []
    return name in set(groups)


class PpdState(NamedTuple):
    present: bool
    profile: str | None
    drives_platform: bool


def ppd_state(runner=subprocess.run):
    """O power-profiles-daemon esta ai? Esta disputando o platform_profile?

    Medido nesta maquina: o ppd 0.30 anuncia 'PlatformDriver: placeholder',
    ou seja, dirige so o intel_pstate. Por isso ele diz 'performance'
    enquanto o platform_profile diz 'balanced', sem conflito nenhum. Se
    numa versao futura ele passar a se ligar, esta verificacao acusa.
    Ver spec secao 2.11.
    """
    def chama(*argumentos):
        return runner(
            ["powerprofilesctl", *argumentos],
            capture_output=True,
            text=True,
            timeout=2,
        )

    try:
        listagem = chama("list")
    except (OSError, subprocess.SubprocessError):
        return PpdState(present=False, profile=None, drives_platform=False)

    plataformas = []
    for linha in (listagem.stdout or "").splitlines():
        if "PlatformDriver:" in linha:
            plataformas.append(linha.split(":", 1)[1].strip())

    try:
        perfil = (chama("get").stdout or "").strip() or None
    except (OSError, subprocess.SubprocessError):
        perfil = None

    return PpdState(
        present=True,
        profile=perfil,
        drives_platform=any(p and p != "placeholder" for p in plataformas),
    )
```

- [ ] **Step 6: Implementar a página**

`src/nexus_sense/gui/pages/diagnostics.py`:

```python
"""Diagnostico: por que aquele botao esta cinza.

Substitui o "System Settings" da GUI antiga. Saem os botoes "Check for
Updates" e "Issue/Feedback": apontam para as releases e o GitHub do
PXDiv, que nao sao mais a base deste fork. Ver spec secao 6.5.
"""

from typing import NamedTuple

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QFormLayout,
    QFrame,
    QGroupBox,
    QLabel,
    QVBoxLayout,
    QWidget,
)

from ... import session
from ...device import read_system
from ...session import AGENT_UNIT, GROUP

VAZIO = "—"


class Check(NamedTuple):
    label: str
    ok: bool
    detail: str


def run_checks(state, *, agent, ppd, in_group):
    """As quatro verificacoes, sempre as quatro e sempre nesta ordem.

    Funcao pura: recebe o estado e os fatos da sessao, devolve o que
    mostrar. Quem chama subprocess e a pagina.
    """
    checagens = [
        Check(
            "Módulo carregado",
            state.module_loaded,
            "" if state.module_loaded else "carregue com: sudo modprobe linuwu_sense",
        )
    ]

    graveis = state.profile_writable and bool(state.writable)
    if graveis:
        detalhe = ""
    elif not in_group:
        detalhe = (
            f"você não está no grupo {GROUP}. Para entrar: "
            f"sudo usermod -aG {GROUP} $USER — e relogue em seguida"
        )
    else:
        detalhe = (
            f"você está no grupo {GROUP}, mas esta sessão ainda não o carrega: "
            "é preciso relogar. Se já relogou, a regra udev não foi aplicada — "
            "confira /etc/udev/rules.d/60-nexus-sense.rules"
        )
    checagens.append(Check(f"Permissão de grupo ({GROUP})", graveis, detalhe))

    checagens.append(
        Check(
            "Agente ativo",
            agent,
            ""
            if agent
            else f"ligue com: systemctl --user enable --now {AGENT_UNIT}",
        )
    )

    if not ppd.present:
        linha = Check("power-profiles-daemon", True, "não instalado")
    elif ppd.drives_platform:
        linha = Check(
            "power-profiles-daemon",
            False,
            "ele se ligou ao platform_profile e está disputando o perfil com o "
            "Nexus Sense. Escolha um dos dois: desligue o ppd, ou desligue a "
            "troca automática do agente.",
        )
    else:
        linha = Check(
            "power-profiles-daemon",
            True,
            f"presente (perfil {ppd.profile or VAZIO}), mas não disputa o perfil "
            "térmico: dirige apenas o driver da CPU",
        )
    checagens.append(linha)

    return tuple(checagens)


class DiagnosticsPage(QWidget):
    changed = Signal()

    def __init__(self, controls, parent=None):
        super().__init__(parent)
        self.controls = controls

        self.system_card = QGroupBox("Sistema")
        self._sistema = QFormLayout(self.system_card)
        self._campos = {}
        for chave, rotulo in (
            ("product", "Modelo"),
            ("family", "Família"),
            ("driver_version", "Versão do driver"),
            ("module_params", "Parâmetros do módulo"),
            ("choices", "Perfis que o firmware anuncia"),
            ("features", "Recursos disponíveis"),
        ):
            valor = QLabel(VAZIO)
            valor.setWordWrap(True)
            self._sistema.addRow(f"{rotulo}:", valor)
            self._campos[chave] = valor

        self.checks_box = QGroupBox("Verificações")
        QVBoxLayout(self.checks_box)

        raiz = QVBoxLayout(self)
        raiz.addWidget(self.system_card)
        raiz.addWidget(self.checks_box)
        raiz.addStretch(1)

    def has_content(self, state):
        # Justamente quando nada funciona e que esta tela precisa aparecer.
        return True

    def apply_state(self, state):
        sistema = read_system(self.controls.sysfs)
        self._campos["product"].setText(sistema.product or VAZIO)
        self._campos["family"].setText(sistema.family or VAZIO)
        self._campos["driver_version"].setText(sistema.driver_version or VAZIO)
        self._campos["module_params"].setText(
            ", ".join(f"{k}={v}" for k, v in sorted(sistema.module_params.items()))
            or VAZIO
        )
        self._campos["choices"].setText(" ".join(state.choices) or VAZIO)
        self._campos["features"].setText(" ".join(sorted(state.features)) or VAZIO)

        # Chamado so em acao do usuario, nunca no ritmo do poller: sao
        # tres subprocessos, e ninguem quer isso a cada 2 s.
        self._desenha_checagens(
            run_checks(
                state,
                agent=session.agent_active(),
                ppd=session.ppd_state(),
                in_group=session.in_group(GROUP),
            )
        )

    def _desenha_checagens(self, checagens):
        leiaute = self.checks_box.layout()
        while leiaute.count():
            item = leiaute.takeAt(0)
            if item.widget() is not None:
                item.widget().deleteLater()

        for checagem in checagens:
            linha = QFrame()
            interno = QVBoxLayout(linha)
            titulo = QLabel(f"{'✓' if checagem.ok else '✗'}  {checagem.label}")
            titulo.setObjectName("check_ok" if checagem.ok else "check_falhou")
            interno.addWidget(titulo)
            if checagem.detail:
                detalhe = QLabel(checagem.detail)
                detalhe.setWordWrap(True)
                detalhe.setObjectName("check_detalhe")
                interno.addWidget(detalhe)
            leiaute.addWidget(linha)
```

- [ ] **Step 7: Registrar a página**

Em `src/nexus_sense/gui/pages/__init__.py`, acrescente o import e a quinta
entrada, no fim da tupla:

```python
        ("diagnostico", "Diagnóstico", DiagnosticsPage(controls)),
```

- [ ] **Step 8: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_diagnostics.py -q && python3 -m pytest -q
```

Esperado: `18 passed` no arquivo, e a suíte inteira verde.

- [ ] **Step 9: Conferir o Diagnóstico contra a máquina de verdade**

```bash
PYTHONPATH=src python3 -c "
from nexus_sense.sysfs import Sysfs
from nexus_sense.device import read_state, read_system
from nexus_sense.session import GROUP, agent_active, in_group, ppd_state
from nexus_sense.gui.pages.diagnostics import run_checks
s = Sysfs('/')
print(read_system(s))
for c in run_checks(read_state(s), agent=agent_active(), ppd=ppd_state(), in_group=in_group(GROUP)):
    print(('OK ' if c.ok else 'X  '), c.label, '|', c.detail)
"
```

Esperado nesta máquina, antes da virada: módulo carregado ✓; permissão de
grupo ✗ com a frase de relogar, enquanto a sessão não for renovada; agente
✗, porque a unit ainda não foi instalada; `power-profiles-daemon` ✓ com
"não disputa".

- [ ] **Step 10: Commit**

```bash
git add src/nexus_sense/device.py src/nexus_sense/session.py \
        src/nexus_sense/gui/pages tests/python/conftest.py tests/python/test_diagnostics.py
git commit -m "feat: Diagnostico -- sistema e as quatro verificacoes

A tela responde 'por que aquele botao esta cinza'. As quatro
verificacoes sao uma funcao pura que recebe o estado e os fatos da
sessao; a pagina so desenha.

Distingue os dois sintomas identicos de permissao: estar fora do grupo
e estar nele numa sessao que ainda nao o carrega -- as saidas sao
diferentes, e a frase diz qual e qual.

Saem os botoes 'Check for Updates' e 'Issue/Feedback': apontavam para o
GitHub do PXDiv, que nao e mais a base deste fork.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: O helper com `pkexec`, e a ação do Diagnóstico

O helper é a **única** coisa deste projeto que roda como root, e só é
chamada quando você clica. Ver spec §5.3 e decisão D3.

**Files:**
- Create: `packaging/nexus-sense-helper`
- Create: `packaging/com.nexussense.helper.policy`
- Create: `src/nexus_sense/privileged.py`
- Modify: `src/nexus_sense/gui/pages/diagnostics.py` (a última linha da tela)
- Create: `docs/VERIFICACAO-MANUAL.md`
- Test: `tests/python/test_privileged.py`

**Interfaces:**
- Consumes: `SystemInfo` da Task 7.
- Produces:
  - `privileged.HELPER_PATH = "/usr/lib/nexus-sense/nexus-sense-helper"`
  - `privileged.OPERATIONS = ("apply-param", "clear-param", "reload")`
  - `privileged.PARAMS = ("nitro_v4", "predator_v4", "enable_all")`
  - `privileged.run_helper(op, *args, runner=subprocess.run) -> tuple[bool, str]`
  - `gui.pages.diagnostics.forcing_param(system, state) -> str | None` — qual parâmetro faria sentido forçar, ou `None`
  - `DiagnosticsPage.action_row` e `DiagnosticsPage.action_button`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_privileged.py`:

```python
import subprocess

import pytest

from nexus_sense.device import Controls, read_state, read_system
from nexus_sense.gui.pages.diagnostics import DiagnosticsPage, forcing_param
from nexus_sense.privileged import HELPER_PATH, run_helper
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


def runner_ok(codigo=0, saida=""):
    chamadas = []

    def runner(args, **kwargs):
        chamadas.append(args)
        return subprocess.CompletedProcess(args, codigo, stdout=saida, stderr="")

    runner.chamadas = chamadas
    return runner


def test_monta_a_linha_de_comando_com_pkexec():
    r = runner_ok()
    ok, _ = run_helper("apply-param", "nitro_v4", runner=r)
    assert ok is True
    assert r.chamadas[0] == ["pkexec", HELPER_PATH, "apply-param", "nitro_v4"]


def test_operacao_fora_do_conjunto_fechado_e_recusada():
    """O helper aceita um conjunto fechado. Nao se passa caminho nem
    comando por ele. Ver spec secao 5.3."""
    with pytest.raises(ValueError):
        run_helper("rm", "-rf", runner=runner_ok())


def test_parametro_fora_do_conjunto_e_recusado():
    with pytest.raises(ValueError):
        run_helper("apply-param", "qualquer_coisa", runner=runner_ok())


def test_autenticacao_cancelada_da_frase_e_nao_erro():
    ok, mensagem = run_helper("reload", runner=runner_ok(codigo=126))
    assert ok is False
    assert "cancelada" in mensagem.lower()


def test_falha_do_helper_devolve_a_saida_de_erro():
    def runner(args, **kwargs):
        return subprocess.CompletedProcess(args, 1, stdout="", stderr="módulo em uso")

    ok, mensagem = run_helper("reload", runner=runner)
    assert ok is False
    assert "módulo em uso" in mensagem


def test_helper_nao_instalado_e_dito_com_todas_as_letras():
    def explode(args, **kwargs):
        raise FileNotFoundError("pkexec")

    ok, mensagem = run_helper("reload", runner=explode)
    assert ok is False
    assert "não está instalado" in mensagem


def test_sucesso_traz_a_frase_de_recarregado():
    ok, mensagem = run_helper("apply-param", "nitro_v4", runner=runner_ok())
    assert ok is True
    assert "recarregado" in mensagem.lower()


# ------------------------------------------------------------- a acao

def test_falta_o_performance_entao_ha_o_que_forcar(fake_root):
    """O firmware anuncia quatro perfis e existe um quinto atras do
    nitro_v4. Ver spec secao 2.10 e secao 6.5."""
    s = Sysfs(fake_root)
    assert forcing_param(read_system(s), read_state(s)) == "nitro_v4"


def test_num_predator_o_parametro_e_outro(tmp_path):
    raiz = build_tree(tmp_path / "t", sense="predator_sense")
    s = Sysfs(raiz)
    assert forcing_param(read_system(s), read_state(s)) == "predator_v4"


def test_com_os_cinco_perfis_anunciados_nao_ha_o_que_forcar(tmp_path):
    raiz = build_tree(
        tmp_path / "t",
        choices="low-power quiet balanced balanced-performance performance",
    )
    s = Sysfs(raiz)
    assert forcing_param(read_system(s), read_state(s)) is None


def test_a_acao_aparece_na_tela_quando_faz_sentido(qtbot, fake_root):
    s = Sysfs(fake_root)
    p = DiagnosticsPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    assert p.action_row.isVisible() is True
    assert "nitro_v4" in p.action_row.subtitle.text()


def test_a_acao_some_quando_nao_ha_o_que_forcar(qtbot, tmp_path):
    raiz = build_tree(
        tmp_path / "t",
        choices="low-power quiet balanced balanced-performance performance",
    )
    s = Sysfs(raiz)
    p = DiagnosticsPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    assert p.action_row.isVisible() is False
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_privileged.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.privileged'`.

- [ ] **Step 3: Implementar o lado do cliente**

`src/nexus_sense/privileged.py`:

```python
"""A conversa com o helper que roda como root.

Regra que define esta camada: o conjunto de operacoes e fechado e mora
aqui **e** no helper. Nao se passa caminho, nem comando, nem argumento
livre -- so um verbo da lista e, quando for o caso, um parametro da
lista. Ver spec secao 5.3.
"""

import subprocess

HELPER_PATH = "/usr/lib/nexus-sense/nexus-sense-helper"

OPERATIONS = ("apply-param", "clear-param", "reload")

# Os tres que o driver aceita (linuwu_sense.c:2372-2381). Qualquer outra
# coisa e recusada antes de chegar ao pkexec.
PARAMS = ("nitro_v4", "predator_v4", "enable_all")

# pkexec: 126 quando o dialogo e dispensado, 127 quando a autorizacao
# nao pode ser obtida. Os dois querem dizer a mesma coisa ao usuario.
CANCELADO = (126, 127)


def run_helper(op, *args, runner=subprocess.run):
    """Executa uma operacao privilegiada. Devolve (deu_certo, frase)."""
    if op not in OPERATIONS:
        raise ValueError(f"operação não permitida: {op!r}")
    if op == "apply-param":
        if len(args) != 1 or args[0] not in PARAMS:
            raise ValueError(f"parâmetro não permitido: {args!r}")
    elif args:
        raise ValueError(f"{op} não recebe argumento")

    try:
        saida = runner(
            ["pkexec", HELPER_PATH, op, *args],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except FileNotFoundError:
        return False, (
            f"o helper não está instalado em {HELPER_PATH}. "
            "Rode o instalador para colocá-lo lá."
        )
    except (OSError, subprocess.SubprocessError) as erro:
        return False, f"falha ao chamar o helper: {erro}"

    if saida.returncode in CANCELADO:
        return False, "autenticação cancelada ou negada."
    if saida.returncode != 0:
        detalhe = (saida.stderr or saida.stdout or "").strip()
        return False, f"o helper falhou: {detalhe or saida.returncode}"

    return True, "driver recarregado."
```

- [ ] **Step 4: Escrever o helper**

`packaging/nexus-sense-helper`:

```python
#!/usr/bin/python3
"""Operacoes privilegiadas do Nexus Sense.

Invocado por pkexec, com a regra polkit com.nexussense.helper.

O que ele faz, e nada mais: escrever ou apagar o parametro do modulo em
/etc/modprobe.d, e recarregar o modulo. Nao recebe caminho, nao recebe
comando, e valida o parametro contra uma lista fechada antes de tocar em
qualquer coisa. Ver spec secao 5.3.

Escrever /etc/modprobe.d e rodar rmmod nao viram permissao de grupo --
sao raros e pedir senha e o comportamento certo. Ver decisao D3.
"""

import os
import subprocess
import sys

CONF = "/etc/modprobe.d/nexus-sense.conf"
PARAMS = ("nitro_v4", "predator_v4", "enable_all")

# O modulo ainda se chama linuwu_sense nesta fase; a renomeacao e fase
# propria. Tenta os dois, na ordem do nome novo. Ver spec secao 12.
MODULES = ("nexus_sense", "linuwu_sense")


def modulo_carregado():
    for nome in MODULES:
        if os.path.isdir(f"/sys/module/{nome}"):
            return nome
    return None


def recarrega():
    """Descarrega e carrega de novo, para o parametro valer agora."""
    nome = modulo_carregado()
    if nome is not None:
        subprocess.run(["rmmod", nome], check=True)
        alvo = nome
    else:
        alvo = MODULES[1]
    subprocess.run(["modprobe", alvo], check=True)


def apply_param(parametro):
    if parametro not in PARAMS:
        raise SystemExit(f"parâmetro não permitido: {parametro}")
    nome = modulo_carregado() or MODULES[1]
    with open(CONF, "w") as arquivo:
        arquivo.write(
            "# Escrito pelo nexus-sense-helper. Apagar com: nexus-sense-helper clear-param\n"
            f"options {nome} {parametro}=1\n"
        )
    recarrega()


def clear_param():
    if os.path.exists(CONF):
        os.remove(CONF)
    recarrega()


def main(argv):
    if os.geteuid() != 0:
        raise SystemExit("este programa precisa de root; ele é chamado por pkexec.")
    if not argv:
        raise SystemExit("uso: nexus-sense-helper apply-param <parâmetro>|clear-param|reload")

    operacao, resto = argv[0], argv[1:]
    if operacao == "apply-param":
        if len(resto) != 1:
            raise SystemExit("apply-param recebe exatamente um parâmetro")
        apply_param(resto[0])
    elif operacao == "clear-param":
        clear_param()
    elif operacao == "reload":
        recarrega()
    else:
        raise SystemExit(f"operação não permitida: {operacao}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except subprocess.CalledProcessError as erro:
        raise SystemExit(f"comando falhou: {' '.join(erro.cmd)}") from erro
```

- [ ] **Step 5: Escrever a regra polkit**

`packaging/com.nexussense.helper.policy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">
<policyconfig>
  <vendor>Nexus Sense</vendor>

  <action id="com.nexussense.helper">
    <description>Alterar parâmetros do driver Nexus Sense</description>
    <description xml:lang="pt_BR">Alterar parâmetros do driver Nexus Sense</description>
    <message>É preciso autenticar para alterar o parâmetro do módulo e recarregar o driver.</message>
    <message xml:lang="pt_BR">É preciso autenticar para alterar o parâmetro do módulo e recarregar o driver.</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/lib/nexus-sense/nexus-sense-helper</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
```

- [ ] **Step 6: Acrescentar a ação ao Diagnóstico**

Em `src/nexus_sense/gui/pages/diagnostics.py`, acrescente os imports:

```python
from PySide6.QtWidgets import QPushButton

from ...privileged import run_helper
from .rows import ControlRow
```

a função pura, logo abaixo de `run_checks`:

```python
def forcing_param(system, state):
    """O parametro que faria o firmware anunciar os cinco perfis.

    O firmware desta maquina anuncia quatro; o driver so forca os cinco
    com nitro_v4, predator_v4 ou enable_all. Se os cinco ja estao ai,
    nao ha o que forcar. Ver spec secao 2.10.
    """
    if "performance" in state.choices:
        return None
    if system.family == "predator":
        return "predator_v4"
    if system.family == "nitro":
        return "nitro_v4"
    return None
```

no fim do `__init__`, antes do `raiz.addStretch(1)`:

```python
        self.action_button = QPushButton("Forçar")
        self.action_button.clicked.connect(self._forca)
        self.action_row = ControlRow(
            "Habilitar o perfil que falta",
            "",
            self.action_button,
        )
        self.action_row.setVisible(False)
        raiz.addWidget(self.action_row)

        self.action_message = QLabel("")
        self.action_message.setWordWrap(True)
        raiz.addWidget(self.action_message)
```

no fim do `apply_state`:

```python
        self._parametro = forcing_param(sistema, state)
        self.action_row.setVisible(self._parametro is not None)
        if self._parametro is not None:
            self.action_row.subtitle.setText(
                f"o firmware anuncia {len(state.choices)} perfis, e existe um a "
                f"mais atrás do parâmetro {self._parametro}. Forçar pede a senha "
                "de administrador e recarrega o driver."
            )
            self.action_row.subtitle.setVisible(True)
```

e o método, no fim da classe:

```python
    def _forca(self):
        if self._parametro is None:
            return
        ok, mensagem = run_helper("apply-param", self._parametro)
        self.action_message.setText(mensagem)
        if ok:
            # O modulo saiu e voltou: os caminhos sumiram e voltaram, e as
            # permissoes voltaram a 644 ate o udev reagir. Reler resolve.
            self.changed.emit()
```

- [ ] **Step 7: Escrever o roteiro de verificação manual**

`docs/VERIFICACAO-MANUAL.md`:

```markdown
# Verificação manual

O que não dá para automatizar, e por quê. Rode isto depois de instalar,
e depois de qualquer mexida nas partes citadas.

---

## 1. O helper e o `pkexec`

**Por que não é automatizável:** `pkexec` abre um diálogo de autenticação
do ambiente gráfico e espera uma senha digitada por uma pessoa. Não há
como um teste responder a ele sem desmontar a própria segurança que ele
existe para dar.

**O que fazer:**

1. Abra o Nexus Sense e vá em **Diagnóstico**.
2. Confira que a última linha diz que o firmware anuncia quatro perfis e
   oferece **Forçar**.
3. Clique em **Forçar**.

**O que esperar:**

- um diálogo de senha de administrador aparece;
- ao cancelar, a tela mostra "autenticação cancelada ou negada." e **nada
  muda**;
- ao autenticar, o driver recarrega e a tela relê sozinha. Em
  **Desempenho**, um quinto botão aparece.

**Como voltar atrás:**

```bash
sudo rm /etc/modprobe.d/nexus-sense.conf
pkexec /usr/lib/nexus-sense/nexus-sense-helper reload
```

**O que também precisa ser verdade:**

```bash
pkexec /usr/lib/nexus-sense/nexus-sense-helper rm -rf /
```

Tem de ser recusado com "operação não permitida" — o conjunto é fechado
dos dois lados, no cliente e no helper.
```

- [ ] **Step 8: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_privileged.py -q && python3 -m pytest -q
```

Esperado: `13 passed` no arquivo, e a suíte inteira verde.

- [ ] **Step 9: Conferir a sintaxe do helper e da regra**

Sem instalar nada:

```bash
python3 -m py_compile packaging/nexus-sense-helper && echo "helper compila"
xmllint --noout packaging/com.nexussense.helper.policy && echo "policy é XML válido"
python3 packaging/nexus-sense-helper reload; echo "saída sem root: $?"
```

Esperado: os dois primeiros confirmam; o terceiro imprime "este programa
precisa de root" e sai diferente de zero. Se `xmllint` não existir:
`sudo -A pacman -S --needed --noconfirm libxml2`.

- [ ] **Step 10: Commit**

```bash
git add packaging/nexus-sense-helper packaging/com.nexussense.helper.policy \
        src/nexus_sense/privileged.py src/nexus_sense/gui/pages/diagnostics.py \
        docs/VERIFICACAO-MANUAL.md tests/python/test_privileged.py
git commit -m "feat: helper com pkexec e a acao do Diagnostico

A unica coisa que roda como root, e so quando voce clica. Conjunto
fechado de operacoes, validado dos dois lados: nao se passa caminho,
comando nem argumento livre.

O antigo 'Internals Manager' deixa de ser porta sem placa: a acao
aparece so quando ha o que forcar, e ao lado do fato que a justifica --
o firmware anuncia quatro perfis e existe um quinto.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: O `StatusNotifierItem`

A parte mais chata do projeto, e a razão dela está medida: o
`QSystemTrayIcon` do Qt expõe `Trigger`, `DoubleClick`, `MiddleClick` e
`Context`, e **nenhum evento de roda**. O ícone de energia do Plasma tem
scroll porque é um SNI e o host chama um método DBus. Ver spec §7.1 e
decisão D6.

**Files:**
- Create: `src/nexus_sense/tray/__init__.py`
- Create: `src/nexus_sense/tray/sni.py`
- Create: `src/nexus_sense/tray/menu.py`
- Modify: `docs/VERIFICACAO-MANUAL.md` (acrescenta a seção da bandeja)
- Test: `tests/python/test_tray.py`

**Interfaces:**
- Consumes: `model` (a escada de perfis), `DeviceState`, `Sample`.
- Produces:
  - `tray.sni.scroll_target(current, choices, on_ac, delta) -> str` — o perfil de destino, já pulando os indisponíveis
  - `tray.sni.tooltip_text(state, sample) -> str`
  - `tray.sni.icon_name(profile) -> str`
  - `tray.sni.SERVICE_PREFIX`, `tray.sni.OBJECT_PATH`, `tray.sni.WATCHER`
  - `tray.sni.StatusNotifierItem(parent=None)` — sinais `activated()`, `secondary()`, `context_menu(int, int)`, `scrolled(int, str)`; atributos `icon`, `tooltip`; métodos `set_icon(nome)`, `set_tooltip(texto)`
  - `tray.sni.register(item, *, bus=None, watcher_factory=None) -> bool`
  - `tray.menu.build_menu(state, actions) -> QMenu` — `actions` é um dicionário com `set_profile`, `fan_auto`, `fan_max`, `open`, `quit`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_tray.py`:

```python
import pytest

from nexus_sense.device import read_state
from nexus_sense.gui.poller import Poller
from nexus_sense.sysfs import Sysfs
from nexus_sense.tray.menu import build_menu
from nexus_sense.tray.sni import (
    OBJECT_PATH,
    StatusNotifierItem,
    icon_name,
    register,
    scroll_target,
    tooltip_text,
)

from conftest import build_tree

QUATRO = ("low-power", "quiet", "balanced", "balanced-performance")


# ------------------------------------------------------------- o scroll


def test_roda_para_cima_sobe_um_degrau():
    assert scroll_target("balanced", QUATRO, True, +1) == "balanced-performance"


def test_roda_para_baixo_desce_um_degrau():
    assert scroll_target("balanced", QUATRO, True, -1) == "quiet"


def test_na_bateria_o_scroll_pula_o_degrau_barrado():
    """O buraco da escada: subindo do Economico na bateria, o Silencioso e
    pulado e o destino e o Equilibrado. Nunca se para num degrau que
    falharia. Ver spec secao 7.2."""
    assert scroll_target("low-power", QUATRO, False, +1) == "balanced"


def test_na_bateria_o_scroll_bate_no_teto_e_para():
    """Girar mais para cima nao faz nada: o Desempenho tambem esta
    barrado. Bate no limite e para, sem erro e sem escrita que falha."""
    assert scroll_target("balanced", QUATRO, False, +1) == "balanced"


def test_no_chao_o_scroll_tambem_para():
    assert scroll_target("low-power", QUATRO, True, -1) == "low-power"


def test_delta_zero_nao_move():
    assert scroll_target("balanced", QUATRO, True, 0) == "balanced"


def test_perfil_que_deixou_de_valer_cai_no_mais_proximo():
    """Caso real: o cabo saiu com a maquina em balanced-performance."""
    assert scroll_target("balanced-performance", QUATRO, False, +1) == "balanced"


def test_sem_perfil_disponivel_devolve_o_corrente():
    assert scroll_target("balanced", (), True, +1) == "balanced"


# ------------------------------------------------------------- o tooltip


def test_o_tooltip_traz_perfil_ventoinhas_e_temperatura(fake_root):
    s = Sysfs(fake_root)
    texto = tooltip_text(read_state(s), Poller(s).read_now())
    assert "Equilibrado" in texto
    assert "2079" in texto and "1870" in texto
    assert "47" in texto


def test_o_tooltip_aguenta_amostra_vazia(tmp_path):
    s = Sysfs(tmp_path)
    texto = tooltip_text(read_state(s), Poller(s).read_now())
    assert isinstance(texto, str) and texto


# --------------------------------------------------------------- o icone


def test_cada_perfil_tem_seu_icone():
    nomes = {icon_name(p) for p in QUATRO}
    assert len(nomes) == 4
    assert icon_name("balanced") == "nexus-sense-tray-balanced"


def test_perfil_desconhecido_cai_no_icone_base():
    assert icon_name(None) == "nexus-sense-tray"
    assert icon_name("inventado") == "nexus-sense-tray"


# ------------------------------------------------------------- o objeto


def test_o_item_guarda_icone_e_tooltip(qtbot):
    item = StatusNotifierItem()
    item.set_icon("nexus-sense-tray-quiet")
    item.set_tooltip("qualquer coisa")
    assert item.icon == "nexus-sense-tray-quiet"
    assert item.tooltip == "qualquer coisa"


def test_o_scroll_do_host_vira_sinal(qtbot):
    """E este metodo que o QSystemTrayIcon nao tem, e a razao de haver um
    SNI escrito a mao aqui. Ver spec secao 7.1."""
    item = StatusNotifierItem()
    with qtbot.waitSignal(item.scrolled, timeout=1000) as capturado:
        item.Scroll(120, "vertical")
    assert capturado.args == [120, "vertical"]


def test_os_outros_tres_metodos_tambem_viram_sinal(qtbot):
    item = StatusNotifierItem()
    with qtbot.waitSignal(item.activated, timeout=1000):
        item.Activate(0, 0)
    with qtbot.waitSignal(item.secondary, timeout=1000):
        item.SecondaryActivate(0, 0)
    with qtbot.waitSignal(item.context_menu, timeout=1000):
        item.ContextMenu(10, 20)


# ------------------------------------------------------------- registro


class BarramentoFalso:
    def __init__(self, servico=True, objeto=True):
        self._servico = servico
        self._objeto = objeto
        self.registrou = []

    def registerService(self, nome):
        self.registrou.append(nome)
        return self._servico

    def registerObject(self, caminho, objeto, opcoes):
        self.caminho = caminho
        return self._objeto


class WatcherFalso:
    def __init__(self, valido=True, erro=False):
        self._valido = valido
        self._erro = erro
        self.chamadas = []

    def isValid(self):
        return self._valido

    def call(self, metodo, *args):
        self.chamadas.append((metodo, args))
        return self

    def type(self):
        from PySide6.QtDBus import QDBusMessage

        return (
            QDBusMessage.MessageType.ErrorMessage
            if self._erro
            else QDBusMessage.MessageType.ReplyMessage
        )


def test_registrar_fala_com_o_watcher(qtbot):
    item = StatusNotifierItem()
    barramento = BarramentoFalso()
    watcher = WatcherFalso()
    assert register(item, bus=barramento, watcher_factory=lambda _: watcher) is True
    assert barramento.caminho == OBJECT_PATH
    assert watcher.chamadas[0][0] == "RegisterStatusNotifierItem"


def test_sem_watcher_no_barramento_o_registro_falha(qtbot):
    """Sem host SNI o app cai para o QSystemTrayIcon. Ver spec secao 7.3."""
    item = StatusNotifierItem()
    resultado = register(
        item, bus=BarramentoFalso(), watcher_factory=lambda _: WatcherFalso(valido=False)
    )
    assert resultado is False


def test_nome_de_servico_ocupado_nao_derruba(qtbot):
    item = StatusNotifierItem()
    resultado = register(
        item,
        bus=BarramentoFalso(servico=False),
        watcher_factory=lambda _: WatcherFalso(),
    )
    assert resultado is False


# ----------------------------------------------------------------- menu


def test_o_menu_lista_so_os_perfis_disponiveis(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False)
    estado = read_state(Sysfs(raiz))
    menu = build_menu(estado, {})
    qtbot.addWidget(menu)
    textos = [a.text() for a in menu.actions() if not a.isSeparator()]
    assert "Econômico" in textos
    assert "Silencioso" not in textos


def test_o_menu_marca_o_perfil_corrente(qtbot, fake_root):
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {})
    qtbot.addWidget(menu)
    marcadas = [a.text() for a in menu.actions() if a.isChecked()]
    assert marcadas == ["Equilibrado"]


def test_o_menu_tem_ventoinha_abrir_e_sair(qtbot, fake_root):
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {})
    qtbot.addWidget(menu)
    textos = [a.text() for a in menu.actions() if not a.isSeparator()]
    for esperado in ("Ventoinha automática", "Ventoinha no máximo", "Abrir", "Sair"):
        assert esperado in textos


def test_clicar_num_perfil_do_menu_chama_a_acao(qtbot, fake_root):
    escolhidos = []
    estado = read_state(Sysfs(fake_root))
    menu = build_menu(estado, {"set_profile": escolhidos.append})
    qtbot.addWidget(menu)
    for acao in menu.actions():
        if acao.text() == "Econômico":
            acao.trigger()
    assert escolhidos == ["low-power"]
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_tray.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.tray'`.

- [ ] **Step 3: Implementar as decisões puras e o item DBus**

`src/nexus_sense/tray/__init__.py`:

```python
"""A bandeja."""
```

`src/nexus_sense/tray/sni.py`:

```python
"""StatusNotifierItem escrito a mao.

Por que nao QSystemTrayIcon: ele expõe Trigger, DoubleClick, MiddleClick
e Context, e nenhum evento de roda. O icone de energia do Plasma tem
scroll porque e um SNI e o host chama Scroll(delta, orientacao) por
DBus. Introspeccao de um item vivo desta sessao confirmou os quatro
metodos. Ver spec secao 7.1 e decisao D6.

As decisoes ficam em funcoes puras no topo do arquivo, fora do objeto
DBus: e o que permite testar o comportamento da bandeja sem barramento,
sem host e sem sessao grafica.
"""

import os

from PySide6.QtCore import ClassInfo, Property, QObject, Signal, Slot
from PySide6.QtDBus import QDBusAbstractAdaptor, QDBusConnection, QDBusInterface, QDBusMessage

from .. import model

SERVICE_PREFIX = "org.kde.StatusNotifierItem"
OBJECT_PATH = "/StatusNotifierItem"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"

ICON_BASE = "nexus-sense-tray"


def scroll_target(current, choices, on_ac, delta):
    """Para onde o scroll leva. Ja pula o indisponivel.

    Anda sobre a lista de perfis permitidos agora, e por isso nunca
    devolve um degrau que a escrita recusaria: na bateria, subir a partir
    do Economico vai direto ao Equilibrado, e subir de novo nao faz nada.
    Ver spec secao 7.2.
    """
    if not delta:
        return current
    return model.neighbour(current, choices, on_ac, +1 if delta > 0 else -1)


def tooltip_text(state, sample):
    """Perfil, rotacao das duas ventoinhas e temperatura."""
    perfil = model.LABELS.get(state.profile, state.profile) or "perfil desconhecido"
    partes = [f"Nexus Sense — {perfil}"]
    if sample.fans is not None:
        partes.append(f"{sample.fans[0]} / {sample.fans[1]} rpm")
    if sample.cpu_temp is not None:
        partes.append(f"{sample.cpu_temp:.0f} °C")
    return "\n".join(partes)


def icon_name(profile):
    """O icone muda conforme o perfil. Ver spec secao 7.2."""
    if profile in model.PROFILES:
        return f"{ICON_BASE}-{profile}"
    return ICON_BASE


@ClassInfo({"D-Bus Interface": "org.kde.StatusNotifierItem"})
class SniAdaptor(QDBusAbstractAdaptor):
    """As propriedades e os sinais que o host lê e escuta.

    O ToolTip do padrao e uma struct (sa(iiay)ss), cujo empacotamento em
    PySide6 daria muito trabalho para pouco: o Plasma cai no Title quando
    o ToolTip esta vazio. Entao o texto do tooltip vai no Title, e o
    NewTitle avisa o host. O roteiro de verificacao manual confere como
    isso aparece na tela.
    """

    NewIcon = Signal()
    NewTitle = Signal()
    NewStatus = Signal(str)

    def __init__(self, parent):
        super().__init__(parent)
        self.item = parent

    @Property(str)
    def Category(self):
        return "Hardware"

    @Property(str)
    def Id(self):
        return "nexus-sense"

    @Property(str)
    def Title(self):
        return self.item.tooltip

    @Property(str)
    def Status(self):
        return "Active"

    @Property(str)
    def IconName(self):
        return self.item.icon

    @Property(bool)
    def ItemIsMenu(self):
        # False: o host deve chamar Activate no clique esquerdo em vez de
        # abrir menu. Sem isso o Plasma trata o item como so-menu.
        return False

    @Slot(int, int)
    def Activate(self, x, y):
        self.item.Activate(x, y)

    @Slot(int, int)
    def SecondaryActivate(self, x, y):
        self.item.SecondaryActivate(x, y)

    @Slot(int, int)
    def ContextMenu(self, x, y):
        self.item.ContextMenu(x, y)

    @Slot(int, str)
    def Scroll(self, delta, orientation):
        self.item.Scroll(delta, orientation)


class StatusNotifierItem(QObject):
    """O item em si. Traduz chamada do host em sinal do Qt."""

    activated = Signal()
    secondary = Signal()
    context_menu = Signal(int, int)
    scrolled = Signal(int, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.icon = ICON_BASE
        self.tooltip = "Nexus Sense"
        self._adaptor = SniAdaptor(self)

    # -------------------------------------------------- o que o host chama

    def Activate(self, x, y):
        self.activated.emit()

    def SecondaryActivate(self, x, y):
        self.secondary.emit()

    def ContextMenu(self, x, y):
        self.context_menu.emit(x, y)

    def Scroll(self, delta, orientation):
        self.scrolled.emit(delta, orientation)

    # ------------------------------------------------ o que o app escreve

    def set_icon(self, nome):
        if nome != self.icon:
            self.icon = nome
            self._adaptor.NewIcon.emit()

    def set_tooltip(self, texto):
        if texto != self.tooltip:
            self.tooltip = texto
            self._adaptor.NewTitle.emit()


def register(item, *, bus=None, watcher_factory=None):
    """Publica o item e se apresenta ao watcher. False se nao deu.

    Falhar aqui e um caminho previsto, nao um defeito: sem host SNI no
    barramento -- Sway, GNOME puro sem extensao -- o app cai para o
    QSystemTrayIcon. Ver spec secao 7.3.
    """
    if bus is None:
        bus = QDBusConnection.sessionBus()
    if watcher_factory is None:
        def watcher_factory(barramento):
            return QDBusInterface(WATCHER, WATCHER_PATH, WATCHER, barramento)

    nome = f"{SERVICE_PREFIX}-{os.getpid()}-1"
    if not bus.registerService(nome):
        return False
    if not bus.registerObject(OBJECT_PATH, item, QDBusConnection.ExportAllContents):
        return False

    watcher = watcher_factory(bus)
    if not watcher.isValid():
        return False
    resposta = watcher.call("RegisterStatusNotifierItem", nome)
    return resposta.type() != QDBusMessage.MessageType.ErrorMessage
```

- [ ] **Step 4: Implementar o menu**

`src/nexus_sense/tray/menu.py`:

```python
"""O menu do clique direito.

So os perfis disponiveis entram: um menu nao tem como hachurar, e um
item que falharia ao ser clicado e pior do que um item ausente. A tela
de Desempenho e que mostra o indisponivel com o motivo.
"""

from PySide6.QtGui import QAction
from PySide6.QtWidgets import QMenu

from .. import model


def build_menu(state, actions):
    """Monta o menu. `actions` pode vir vazio -- util em teste."""
    menu = QMenu()

    for perfil in state.available:
        acao = QAction(model.LABELS.get(perfil, perfil), menu)
        acao.setCheckable(True)
        acao.setChecked(perfil == state.profile)
        if "set_profile" in actions:
            acao.triggered.connect(lambda _=False, p=perfil: actions["set_profile"](p))
        menu.addAction(acao)

    menu.addSeparator()

    for chave, rotulo in (("fan_auto", "Ventoinha automática"), ("fan_max", "Ventoinha no máximo")):
        acao = QAction(rotulo, menu)
        if chave in actions:
            acao.triggered.connect(lambda _=False, c=chave: actions[c]())
        menu.addAction(acao)

    menu.addSeparator()

    for chave, rotulo in (("open", "Abrir"), ("quit", "Sair")):
        acao = QAction(rotulo, menu)
        if chave in actions:
            acao.triggered.connect(lambda _=False, c=chave: actions[c]())
        menu.addAction(acao)

    return menu
```

- [ ] **Step 5: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_tray.py -q
```

Esperado: `21 passed`.

- [ ] **Step 6: Acrescentar a seção da bandeja ao roteiro manual**

Ao fim de `docs/VERIFICACAO-MANUAL.md`:

```markdown

---

## 2. O ícone na bandeja

**Por que não é automatizável:** o `StatusNotifierItem` só existe se
houver um host SNI vivo no barramento de sessão, e o scroll é um gesto do
mouse sobre um painel desenhado pelo ambiente. Um teste sem sessão
gráfica não tem onde girar a roda.

**Antes de começar**, confirme que há host e watcher:

```bash
busctl --user list | grep -i statusnotifier
```

Tem de aparecer `org.kde.StatusNotifierWatcher` e um
`org.kde.StatusNotifierHost-*`.

**O que fazer, e o que esperar:**

| gesto | o que tem de acontecer |
|---|---|
| passar o mouse | tooltip com perfil, as duas rotações e a temperatura |
| clique esquerdo | a janela abre |
| clique direito | menu com os perfis disponíveis, ventoinha, Abrir e Sair |
| clique do meio | alterna entre o perfil atual e o anterior |
| roda para cima | sobe um perfil; o ícone muda |
| roda para baixo | desce um perfil |

**O teste que importa, e que só existe na bateria:** tire o cabo, ponha
no `Econômico` e gire para cima. Tem de ir direto ao **Equilibrado**,
pulando o `Silencioso`, e girar mais não pode fazer nada — nem mudar o
perfil, nem mostrar erro. É o buraco da escada da spec §2.8.

**Se o clique direito não abrir menu:** o Plasma não está chamando
`ContextMenu()` sem um menu DBus exportado. É o risco registrado na spec
§15, e a saída é implementar `com.canonical.dbusmenu` — mais trabalho,
mesmo resultado. Anote e siga; nada mais depende disso.

**Se o ícone não aparecer:** o app caiu para `QSystemTrayIcon` (menu sim,
scroll não) ou para janela direta. Confirme no terminal, que imprime qual
bandeja subiu.
```

- [ ] **Step 7: Commit**

```bash
git add src/nexus_sense/tray docs/VERIFICACAO-MANUAL.md tests/python/test_tray.py
git commit -m "feat: StatusNotifierItem proprio, com scroll

QSystemTrayIcon nao tem evento de roda -- e por isso que este arquivo
existe. O host chama Scroll(delta, orientacao) por DBus, e o item so
traduz para sinal do Qt.

As decisoes ficam em funcoes puras fora do objeto DBus: o scroll que
pula o degrau barrado, o texto do tooltip e o nome do icone sao testados
sem barramento, sem host e sem sessao grafica.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: A bandeja ligada, o fallback e os ícones por perfil

> **Correção posterior (2026-09-06):** este ANV15-52 anuncia quatro perfis.
> As instruções abaixo que falam em cinco níveis e barra inferior registram
> o desenho original e foram substituídas pelo N que enche verticalmente em
> quatro níveis, com contorno permanente e variantes para tema claro e escuro.
> A fonte vigente é `docs/INTERFACE.md`, seção 5.

**Files:**
- Create: `src/nexus_sense/tray/controller.py`
- Create: `src/nexus_sense/tray/fallback.py`
- Modify: `src/nexus_sense/tray/__init__.py` (o `build_tray`)
- Modify: `src/nexus_sense/gui/app.py` (monta a bandeja)
- Modify: `packaging/icons/gerar.sh` (as cinco variantes)
- Modify: `packaging/icons/README.md` (registra a decisão do canal)
- Test: `tests/python/test_tray_controller.py`

**Interfaces:**
- Consumes: `StatusNotifierItem`, `register`, `build_menu`, `scroll_target`, `tooltip_text`, `icon_name` da Task 9.
- Produces:
  - `tray.controller.INTERVALO_BANDEJA = 5000`
  - `tray.controller.TrayController(sysfs, controls, item, parent=None)` — sinais `open_requested()`, `quit_requested()`; métodos `refresh()`, `start()`, `stop()`, `apply_profile(profile)`; atributos `.state`, `.previous_profile`, `.active`
  - `tray.fallback.FallbackTray(parent=None)` — mesma superfície do `StatusNotifierItem`: sinais `activated`, `secondary`, `context_menu`, `scrolled` (nunca emitido) e `set_icon`/`set_tooltip`
  - `tray.build_tray(sysfs, controls) -> tuple[TrayController | None, str]` — o segundo item é `"sni"`, `"qsystemtrayicon"` ou `"nenhuma"`

**A bandeja lê pouco, e por isso pode ler sempre.** O poller da janela só
roda com ela visível, porque sonda a GPU. A bandeja tem o seu próprio
relógio, mais lento (5 s), e lê **apenas** hwmon — 0,23 ms, e não acorda
nada. Ver spec §10.2.

**O canal que distingue os cinco ícones:** barra de nível sob a marca,
monocromática. Decidido comparando as alternativas em 22 px contra ícones
reais do Breeze na mesma fita: cor lê mais rápido mas abandona a
recoloração pelo tema; barra vertical à direita colide com a haste do N e
vira pontuação. A barra horizontal usa a margem que já existe — o N
continua com os 16 px medidos e não encolhe.

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_tray_controller.py`:

```python
import pytest

from nexus_sense.device import Controls, read_state
from nexus_sense.sysfs import Sysfs
from nexus_sense.tray import build_tray
from nexus_sense.tray.controller import TrayController
from nexus_sense.tray.fallback import FallbackTray
from nexus_sense.tray.sni import StatusNotifierItem

from conftest import build_tree

PROFILE = "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"


def controlador(qtbot, raiz):
    s = Sysfs(raiz)
    item = StatusNotifierItem()
    c = TrayController(s, Controls(s), item)
    c.refresh()
    return c, item


def test_o_icone_segue_o_perfil(qtbot, tmp_path):
    c, item = controlador(qtbot, build_tree(tmp_path / "t", profile="quiet"))
    assert item.icon == "nexus-sense-tray-quiet"


def test_o_tooltip_traz_o_perfil_e_a_rotacao(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    assert "Equilibrado" in item.tooltip
    assert "2079" in item.tooltip


def test_a_bandeja_nao_sonda_a_gpu(qtbot, fake_root, monkeypatch):
    """A bandeja le so hwmon. Se ela chamasse read_gpu a cada 5 s,
    manteria a dGPU acordada de graca. Ver spec secao 10.2."""
    from nexus_sense import telemetry

    def explode(*args, **kwargs):
        raise AssertionError("a bandeja não pode sondar a GPU")

    monkeypatch.setattr(telemetry, "read_gpu", explode)
    c, item = controlador(qtbot, fake_root)
    c.refresh()


def test_a_roda_para_cima_escreve_o_perfil_de_cima(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    item.Scroll(120, "vertical")
    assert (fake_root / PROFILE).read_text().strip() == "balanced-performance"


def test_na_bateria_a_roda_pula_o_degrau_barrado(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", on_ac=False, profile="low-power")
    c, item = controlador(qtbot, raiz)
    item.Scroll(120, "vertical")
    assert (raiz / PROFILE).read_text().strip() == "balanced"


def test_na_bateria_a_roda_bate_no_teto_sem_escrever(qtbot, tmp_path):
    """Girar mais nao pode nem mudar o perfil nem tentar uma escrita que
    o driver recusaria."""
    raiz = build_tree(tmp_path / "t", on_ac=False, profile="balanced")
    c, item = controlador(qtbot, raiz)
    escritas = []
    c.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)
    item.Scroll(120, "vertical")
    assert escritas == []


def test_o_clique_do_meio_alterna_com_o_anterior(qtbot, fake_root):
    """O anterior e o de antes da ultima troca feita pela bandeja."""
    c, item = controlador(qtbot, fake_root)
    item.Scroll(120, "vertical")          # balanced -> balanced-performance
    assert (fake_root / PROFILE).read_text().strip() == "balanced-performance"
    item.SecondaryActivate(0, 0)          # volta ao balanced
    assert (fake_root / PROFILE).read_text().strip() == "balanced"


def test_o_clique_do_meio_sem_anterior_nao_faz_nada(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    escritas = []
    c.controls.sysfs.write = lambda caminho, valor: escritas.append(valor)
    item.SecondaryActivate(0, 0)
    assert escritas == []


def test_o_clique_esquerdo_pede_para_abrir(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    with qtbot.waitSignal(c.open_requested, timeout=1000):
        item.Activate(0, 0)


def test_escrita_recusada_pela_bandeja_nao_derruba_nada(qtbot, fake_root):
    """Sem janela aberta nao ha onde mostrar frase: engole, relê e segue."""
    import errno

    c, item = controlador(qtbot, fake_root)

    def recusa(caminho, valor):
        raise OSError(errno.EOPNOTSUPP, "Operation not supported")

    c.controls.sysfs.write = recusa
    item.Scroll(120, "vertical")     # não pode levantar


def test_o_relogio_da_bandeja_liga_e_desliga(qtbot, fake_root):
    c, item = controlador(qtbot, fake_root)
    c.start()
    assert c.active is True
    c.stop()
    assert c.active is False


# --------------------------------------------------------------- fallback


def test_o_fallback_tem_a_mesma_superficie_do_sni(qtbot):
    """Trocar um pelo outro nao pode exigir mudar o controlador."""
    f = FallbackTray()
    for nome in ("activated", "secondary", "context_menu", "scrolled"):
        assert hasattr(f, nome)
    f.set_icon("nexus-sense-tray-quiet")
    f.set_tooltip("texto")
    assert f.icon == "nexus-sense-tray-quiet"
    assert f.tooltip == "texto"


def test_o_fallback_serve_ao_controlador(qtbot, fake_root):
    s = Sysfs(fake_root)
    f = FallbackTray()
    c = TrayController(s, Controls(s), f)
    c.refresh()
    assert f.icon == "nexus-sense-tray-balanced"


def test_build_tray_diz_qual_bandeja_subiu(qtbot, fake_root):
    """Sem host SNI no barramento de teste, o resultado tem de ser um dos
    tres caminhos previstos -- nunca excecao. Ver spec secao 7.3."""
    s = Sysfs(fake_root)
    controlador_, modo = build_tray(s, Controls(s))
    assert modo in ("sni", "qsystemtrayicon", "nenhuma")
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
python3 -m pytest tests/python/test_tray_controller.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.tray.controller'`.

- [ ] **Step 3: Implementar o controlador**

`src/nexus_sense/tray/controller.py`:

```python
"""Liga os gestos da bandeja aos controles.

Ritmo proprio, mais lento que o da janela, e leitura barata: so hwmon,
nunca a GPU. Sao 0,23 ms a cada 5 s. Um nvidia-smi aqui manteria a dGPU
acordada o tempo todo para exibir um numero que ninguem esta olhando.
Ver spec secao 10.2.
"""

from PySide6.QtCore import QObject, QTimer, Signal

from .. import telemetry
from ..device import WriteError, read_state
from ..gui.poller import Sample
from .sni import icon_name, scroll_target, tooltip_text

INTERVALO_BANDEJA = 5000  # ms


class TrayController(QObject):
    open_requested = Signal()
    quit_requested = Signal()

    def __init__(self, sysfs, controls, item, parent=None):
        super().__init__(parent)
        self.sysfs = sysfs
        self.controls = controls
        self.item = item
        self.state = None
        self.previous_profile = None

        item.scrolled.connect(self._rolou)
        item.activated.connect(self.open_requested.emit)
        item.secondary.connect(self._alterna)

        self._timer = QTimer(self)
        self._timer.setInterval(INTERVALO_BANDEJA)
        self._timer.timeout.connect(self.refresh)

    @property
    def active(self):
        return self._timer.isActive()

    def start(self):
        if not self._timer.isActive():
            self._timer.start()
            self.refresh()

    def stop(self):
        self._timer.stop()

    def refresh(self):
        """Relê o barato e repinta o icone e o tooltip."""
        self.state = read_state(self.sysfs)
        amostra = Sample(
            fans=telemetry.fan_rpm(self.sysfs),
            acer_temps=(),
            cpu_temp=telemetry.cpu_package_temp(self.sysfs),
            gpu=None,          # de proposito: a bandeja nao acorda a GPU
            battery=None,
            cpu_usage=None,    # nao interessa ao tooltip, e evita ler /proc
        )
        self.item.set_icon(icon_name(self.state.profile))
        self.item.set_tooltip(tooltip_text(self.state, amostra))

    # ------------------------------------------------------------ gestos

    def _rolou(self, delta, orientation):
        if self.state is None:
            self.refresh()
        atual = self.state.profile
        destino = scroll_target(atual, self.state.choices, self.state.on_ac, delta)
        if destino == atual:
            # Bateu no limite. Nao escrever e o comportamento certo: uma
            # escrita que falharia daria erro sem nada para o usuario fazer.
            return
        self.apply_profile(destino)

    def _alterna(self):
        if self.previous_profile is None:
            return
        self.apply_profile(self.previous_profile)

    def apply_profile(self, profile):
        """Escreve o perfil e guarda o anterior. Publico: o menu usa."""
        anterior = self.state.profile
        try:
            self.controls.set_profile(profile)
        except WriteError:
            # Sem janela aberta nao ha onde mostrar frase. Relê e segue: a
            # proxima passada mostra o estado real no icone e no tooltip.
            self.refresh()
            return
        self.previous_profile = anterior
        self.refresh()
```

- [ ] **Step 4: Implementar o fallback**

`src/nexus_sense/tray/fallback.py`:

```python
"""Bandeja de reserva, quando nao ha host SNI no barramento.

Menu sim, scroll nao -- QSystemTrayIcon nao tem evento de roda. A
superficie e a mesma do StatusNotifierItem de proposito: o controlador
nao sabe com qual dos dois esta falando. Ver spec secao 7.3.
"""

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QSystemTrayIcon


class FallbackTray(QObject):
    """Embrulha um QSystemTrayIcon em vez de herdar dele.

    Herdar colidiria: QSystemTrayIcon ja tem um sinal `activated`, com
    outra assinatura -- ele emite um enum de razoes, e o controlador
    espera "clicaram com o esquerdo". Embrulhando, os quatro nomes ficam
    exatamente iguais aos do StatusNotifierItem.
    """

    activated = Signal()
    secondary = Signal()
    context_menu = Signal(int, int)
    scrolled = Signal(int, str)     # nunca emitido; existe pela simetria

    def __init__(self, parent=None):
        super().__init__(parent)
        self.icon = ""
        self.tooltip = ""
        self._tray = QSystemTrayIcon(self)
        self._tray.activated.connect(self._razao)

    def _razao(self, motivo):
        if motivo == QSystemTrayIcon.Trigger:
            self.activated.emit()
        elif motivo == QSystemTrayIcon.MiddleClick:
            self.secondary.emit()
        elif motivo == QSystemTrayIcon.Context:
            posicao = self._tray.geometry().center()
            self.context_menu.emit(posicao.x(), posicao.y())

    def show(self):
        self._tray.show()

    def set_icon(self, nome):
        self.icon = nome
        self._tray.setIcon(QIcon.fromTheme(nome))

    def set_tooltip(self, texto):
        self.tooltip = texto
        self._tray.setToolTip(texto)
```

- [ ] **Step 5: Implementar a escolha da bandeja**

`src/nexus_sense/tray/__init__.py`:

```python
"""A bandeja, e a escolha de qual delas.

Tres caminhos, na ordem de preferencia, e nenhum deles e erro:

  sni               ha host StatusNotifierItem: bandeja completa, com scroll
  qsystemtrayicon   nao ha: menu sim, scroll nao
  nenhuma           nem isso: o app abre a janela direto

Em nenhum dos tres a correcao de perfil e afetada -- ela mora no agente,
que nao sabe o que e Qt. Ver spec secao 7.3.
"""

from PySide6.QtWidgets import QSystemTrayIcon

from .controller import TrayController
from .fallback import FallbackTray
from .sni import StatusNotifierItem, register


def build_tray(sysfs, controls, parent=None):
    """Devolve (controlador, modo). O controlador e None no modo 'nenhuma'."""
    item = StatusNotifierItem(parent)
    if register(item):
        return TrayController(sysfs, controls, item, parent), "sni"

    if QSystemTrayIcon.isSystemTrayAvailable():
        reserva = FallbackTray(parent)
        controlador = TrayController(sysfs, controls, reserva, parent)
        reserva.show()
        return controlador, "qsystemtrayicon"

    return None, "nenhuma"
```

- [ ] **Step 6: Montar a bandeja no `app.py`**

Substitua o corpo do `main` em `src/nexus_sense/gui/app.py`, a partir da
linha `sysfs = Sysfs(args.root)`, por:

```python
    sysfs = Sysfs(args.root)
    controls = Controls(sysfs)
    janela = Window(sysfs, controls)
    janela.refresh()

    controlador, modo = build_tray(sysfs, controls)
    print(f"bandeja: {modo}")

    if controlador is None:
        janela.show()
    else:
        # Com bandeja, fechar a janela nao encerra o app: o icone continua.
        app.setQuitOnLastWindowClosed(False)
        controlador.open_requested.connect(lambda: _abre(janela))
        controlador.quit_requested.connect(app.quit)
        controlador.item.context_menu.connect(
            lambda x, y: _menu(controlador, janela, app, x, y)
        )
        controlador.start()
        if not args.tray_only:
            janela.show()

    return app.exec()


def _abre(janela):
    janela.show()
    janela.raise_()
    janela.activateWindow()


def _menu(controlador, janela, app, x, y):
    from PySide6.QtCore import QPoint

    from ..tray.menu import build_menu

    acoes = {
        "set_profile": controlador.apply_profile,
        "fan_auto": lambda: controlador.controls.set_fan_speed(0, 0),
        "fan_max": lambda: controlador.controls.set_fan_speed(100, 100),
        "open": lambda: _abre(janela),
        "quit": app.quit,
    }
    menu = build_menu(controlador.state, acoes)
    menu.exec(QPoint(x, y))
```

e acrescente o argumento novo, junto dos outros:

```python
    parser.add_argument(
        "--tray-only", action="store_true", help="começa só na bandeja, sem abrir a janela"
    )
```

além dos imports que passam a ser necessários no topo:

```python
from ..tray import build_tray
```

- [ ] **Step 7: Gerar os cinco ícones**

Ao **fim** de `packaging/icons/gerar.sh`, **antes** da linha `echo "==> pronto"`:

```bash
# ---------------------------------------------------------------------
# Variantes por perfil termico: a mesma marca, com uma barra de nivel na
# margem inferior. Ver spec secao 7.2.
#
# Por que barra e nao cor: comparadas em 22 px, numa fita com icones
# reais do Breeze ao lado. Cor le mais rapido, mas abandona a recoloracao
# pelo tema e destoa dos vizinhos monocromaticos do painel. Barra
# vertical a direita colide com a haste do N e vira pontuacao. A barra
# horizontal cabe na margem que ja existe -- o N continua com os 372/512
# medidos e nao encolhe.
#
# Geometria, em unidades do mestre de 512:
#   marca sobe 70            (3 px em 22, a margem superior que ja havia)
#   trilho x=70 w=372        exatamente a largura da marca
#   trilho y=442 h=70        as tres ultimas linhas de 22 px
#   preenchimento = i/5      posicao na escada canonica de cinco perfis
# ---------------------------------------------------------------------
echo "==> icones de bandeja por perfil"

# So o miolo do SVG da bandeja: o <g> com os paths, sem cabecalho.
sed -n '/<g transform/,/<\/g>/p' \
    "$RAIZ/scalable/status/nexus-sense-tray.svg" > "$TMP/miolo.svg"

i=0
for perfil in low-power quiet balanced balanced-performance performance; do
    i=$((i + 1))
    cheio=$((372 * i / 5))
    {
        echo '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">'
        echo '<g transform="translate(0,-70)">'
        cat "$TMP/miolo.svg"
        echo '</g>'
        echo '<rect x="70" y="442" width="372" height="70" fill="currentColor" opacity="0.35"/>'
        echo "<rect x=\"70\" y=\"442\" width=\"$cheio\" height=\"70\" fill=\"currentColor\"/>"
        echo '</svg>'
    } > "$RAIZ/scalable/status/nexus-sense-tray-$perfil.svg"

    sed 's/currentColor/#DCDFE3/g' "$RAIZ/scalable/status/nexus-sense-tray-$perfil.svg" \
        > "$TMP/v-claro.svg"
    sed 's/currentColor/#232629/g' "$RAIZ/scalable/status/nexus-sense-tray-$perfil.svg" \
        > "$TMP/v-escuro.svg"
    for n in $TAM_STATUS; do
        install -d "$RAIZ/${n}x${n}/status"
        rsvg-convert -w "$n" -h "$n" "$TMP/v-claro.svg" \
            -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-$perfil-claro.png"
        rsvg-convert -w "$n" -h "$n" "$TMP/v-escuro.svg" \
            -o "$RAIZ/${n}x${n}/status/nexus-sense-tray-$perfil-escuro.png"
    done
done
```

Rode e confira:

```bash
bash packaging/icons/gerar.sh
ls packaging/icons/22x22/status/
magick packaging/icons/22x22/status/nexus-sense-tray-low-power-claro.png \
       packaging/icons/22x22/status/nexus-sense-tray-balanced-claro.png \
       packaging/icons/22x22/status/nexus-sense-tray-performance-claro.png \
       +append -background '#232629' -flatten -filter point -resize 600% /tmp/claude-1000/tres.png
```

Esperado: cinco SVGs novos em `scalable/status/`, os PNGs por tamanho, e a
barra visivelmente mais longa em cada um dos três da comparação.

- [ ] **Step 8: Registrar a decisão no README dos ícones**

Em `packaging/icons/README.md`, substitua o parágrafo que começa com
"As **variantes por perfil térmico**" por:

```markdown
As **variantes por perfil térmico** (spec §7.2) são a marca com uma barra
de nível na margem inferior, uma por perfil, geradas pelo `gerar.sh`.

A escolha do canal foi feita comparando as alternativas em 22 px, numa
fita com ícones reais do Breeze ao lado para dar escala:

| alternativa | por que não |
|---|---|
| cor por perfil | lê mais rápido, mas abandona a recoloração pelo tema e destoa dos vizinhos monocromáticos do painel |
| barra vertical à direita | encosta na haste direita do N — que também é vertical — e o conjunto lê como "N⋮" ou como um N de haste grossa |
| quatro segmentos embaixo | contar quadrados de 3 px não funciona em tamanho real: dois e três ficam quase idênticos |
| **barra contínua embaixo** | **escolhida**: comprimento é canal forte, e a diferença se lê sem ampliar |

A marca **não encolheu** para abrir espaço: a barra ocupa a margem
inferior que já existia, e o N continua com os 372/512 — os 16 px na
caixa de 22 medidos contra os ícones do painel.

O trilho apagado (35%) fica sempre visível: sem ele não há como saber se
a barra cheia é "no máximo" ou "é só isso que existe".
```

- [ ] **Step 9: Rodar e confirmar que passa**

```bash
python3 -m pytest tests/python/test_tray_controller.py -q && python3 -m pytest -q
```

Esperado: `13 passed` no arquivo, e a suíte inteira verde.

- [ ] **Step 10: Ver a bandeja de verdade**

```bash
PYTHONPATH=src XDG_DATA_DIRS="$PWD/packaging:$XDG_DATA_DIRS" python3 -m nexus_sense.gui.app
```

O `XDG_DATA_DIRS` faz o tema achar os ícones sem instalá-los. Espera-se
`bandeja: sni` no terminal e o ícone no painel. Siga então o roteiro de
`docs/VERIFICACAO-MANUAL.md`, seção 2 — inclusive o teste do buraco da
escada, que exige o cabo fora.

- [ ] **Step 11: Commit**

```bash
git add src/nexus_sense/tray src/nexus_sense/gui/app.py \
        packaging/icons tests/python/test_tray_controller.py
git commit -m "feat: bandeja ligada, fallback e os cinco icones por perfil

O controlador tem relogio proprio, mais lento que o da janela, e le so
hwmon: 0,23 ms a cada 5 s, sem nunca acordar a dGPU. Um teste falha de
proposito se alguem chamar read_gpu daqui.

O fallback tem a mesma superficie do SNI, entao trocar um pelo outro nao
muda o controlador. Sem host e sem bandeja nenhuma, a janela abre
direto -- e a correcao de perfil segue igual, porque mora no agente.

Os icones por perfil sao a marca com barra de nivel embaixo, na margem
que ja existia. A marca nao encolheu.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Empacotamento e instalação

Instala tudo que é novo, **sem remover nada** do que está no ar. A
remoção é a Task 12.

**Files:**
- Create: `packaging/nexus-sense.desktop`
- Modify: `original/setup.sh` (acrescenta `install_nexus_sense` e a chamada)
- Create: `tests/test-instalacao-nexus.sh`
- Test: `tests/test-instalacao-nexus.sh` (entra na suíte shell)

**Interfaces:**
- Consumes: tudo que as tarefas anteriores criaram em `packaging/` e `src/`.
- Produces: a árvore instalada abaixo.

```
/usr/lib/nexus-sense/nexus_sense/…          o pacote Python
/usr/lib/nexus-sense/nexus-sense-helper     root por pkexec
/usr/lib/nexus-sense/apply-perms.sh         chamado pela regra udev
/usr/bin/nexus-sense                        lançador da GUI
/usr/bin/nexus-sense-agent                  lançador do agente
/usr/share/applications/nexus-sense.desktop
/usr/share/icons/hicolor/…                  ícones do app e da bandeja
/usr/share/polkit-1/actions/com.nexussense.helper.policy
/usr/lib/systemd/user/nexus-sense-agent.service
/etc/udev/rules.d/60-nexus-sense.rules
```

**Por que não `pip install`:** numa Arch, instalar pelo pip dentro de
`/usr` briga com o pacman pelos mesmos caminhos. O pacote vai inteiro para
`/usr/lib/nexus-sense` e os lançadores apontam `PYTHONPATH` para lá —
que é o estilo do instalador que já existe, e desinstala apagando uma
pasta. Empacotar por distribuição é trabalho posterior; ver spec §14.

- [ ] **Step 1: Escrever o `.desktop`**

`packaging/nexus-sense.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Nexus Sense
GenericName=Controle do laptop
Comment=Perfis térmicos, ventoinhas e bateria para laptops Acer Nitro e Predator
Exec=/usr/bin/nexus-sense
Icon=nexus-sense
Terminal=false
Categories=System;Settings;HardwareSettings;
Keywords=acer;nitro;predator;ventoinha;bateria;perfil;térmico;
StartupNotify=true
```

- [ ] **Step 2: Escrever o teste que falha**

`tests/test-instalacao-nexus.sh`:

```bash
#!/bin/bash
# Verifica que o instalador coloca o Nexus Sense no lugar certo.
#
# Como o resto da suite, este teste le o fonte do instalador em vez de
# rodar a instalacao: rodar exigiria root e mudaria a maquina. O que ele
# garante e que a proxima release do upstream, ao sobrescrever setup.sh,
# nao leve embora o que foi acrescentado.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="$RAIZ/original/setup.sh"
falhas=0

exigir() {
    [ -e "$1" ] || { echo "ERRO: alvo ausente: $1"; exit 3; }
}

exigir "$S"
exigir "$RAIZ/packaging/nexus-sense.desktop"
exigir "$RAIZ/packaging/nexus-sense-agent.service"
exigir "$RAIZ/packaging/60-nexus-sense.rules"
exigir "$RAIZ/packaging/apply-perms.sh"
exigir "$RAIZ/packaging/nexus-sense-helper"
exigir "$RAIZ/packaging/com.nexussense.helper.policy"

confere() {  # $1=descricao  $2=padrao
    if grep -q -- "$2" "$S"; then
        echo "  OK   $1"
    else
        echo "  FALHA $1"
        falhas=$((falhas + 1))
    fi
}

confere "tem a funcao de instalacao"        '^install_nexus_sense() {'
confere "chamada em perform_install"        'install_nexus_sense'
confere "instala o pacote Python"           '/usr/lib/nexus-sense'
confere "instala o lancador da GUI"         '/usr/bin/nexus-sense'
confere "instala o lancador do agente"      'nexus-sense-agent'
confere "instala a regra udev"              '60-nexus-sense.rules'
confere "instala a regra polkit"            'com.nexussense.helper.policy'
confere "instala a unit de usuario"         'systemd/user'
confere "cria o grupo"                      'groupadd'
confere "avisa sobre a permissao nova"      'ventoinhas e o perfil'
confere "recarrega o udev"                  'udevadm control'

# O helper tem de ser sintaticamente valido: ele roda como root.
if python3 -m py_compile "$RAIZ/packaging/nexus-sense-helper" 2>/dev/null; then
    echo "  OK   o helper compila"
else
    echo "  FALHA o helper nao compila"
    falhas=$((falhas + 1))
fi

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: o instalador coloca o Nexus Sense no lugar"
exit 0
```

Torne executável e rode:

```bash
chmod +x tests/test-instalacao-nexus.sh
./tests/test-instalacao-nexus.sh; echo "saida=$?"
```

Esperado: `ERRO: alvo ausente` com saída `3` — a regra udev e a unit já
existem do plano 1, mas o `.desktop` acabou de ser criado e as funções
ainda não estão no `setup.sh`, então as linhas `confere` vão falhar. Se
todos os arquivos existirem, esperado é saída `1` com as onze falhas.

- [ ] **Step 3: Acrescentar a instalação ao `setup.sh`**

Em `original/setup.sh`, logo **antes** de `configure_nitro_button()`,
acrescente:

```bash
# Instala o Nexus Sense: o pacote Python, os dois lancadores, os icones,
# a regra udev com o grupo, a regra polkit com o helper e a unit de
# usuario do agente.
#
# O pacote vai inteiro para /usr/lib/nexus-sense e os lancadores apontam
# PYTHONPATH para la. Instalar por pip dentro de /usr brigaria com o
# gerenciador de pacotes pelos mesmos caminhos.
install_nexus_sense() {
  echo -e "${YELLOW}Installing Nexus Sense...${NC}"

  local raiz pacote
  raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  pacote="${raiz}/src/nexus_sense"

  if [ ! -d "$pacote" ]; then
    echo -e "${RED}Error: src/nexus_sense not found at ${pacote}${NC}"
    return 1
  fi

  # --- o pacote e o helper
  install -d /usr/lib/nexus-sense
  rm -rf /usr/lib/nexus-sense/nexus_sense
  cp -r "$pacote" /usr/lib/nexus-sense/nexus_sense
  find /usr/lib/nexus-sense/nexus_sense -name '__pycache__' -type d -exec rm -rf {} +
  install -m 755 "${raiz}/packaging/nexus-sense-helper" /usr/lib/nexus-sense/nexus-sense-helper
  install -m 755 "${raiz}/packaging/apply-perms.sh" /usr/lib/nexus-sense/apply-perms.sh

  # --- os dois lancadores
  cat > /usr/bin/nexus-sense << 'EOL'
#!/bin/sh
PYTHONPATH=/usr/lib/nexus-sense exec /usr/bin/python3 -m nexus_sense.gui.app "$@"
EOL
  cat > /usr/bin/nexus-sense-agent << 'EOL'
#!/bin/sh
PYTHONPATH=/usr/lib/nexus-sense exec /usr/bin/python3 -m nexus_sense "$@"
EOL
  chmod +x /usr/bin/nexus-sense /usr/bin/nexus-sense-agent

  # --- icones, lancador e regra polkit
  cp -r "${raiz}/packaging/icons/"*x*/ /usr/share/icons/hicolor/ 2>/dev/null || true
  install -d /usr/share/icons/hicolor/scalable/apps /usr/share/icons/hicolor/scalable/status
  cp "${raiz}/packaging/icons/scalable/apps/"*.svg /usr/share/icons/hicolor/scalable/apps/
  cp "${raiz}/packaging/icons/scalable/status/"*.svg /usr/share/icons/hicolor/scalable/status/
  install -m 644 "${raiz}/packaging/nexus-sense.desktop" \
    "${DESKTOP_FILE_DIR}/nexus-sense.desktop"
  install -d /usr/share/polkit-1/actions
  install -m 644 "${raiz}/packaging/com.nexussense.helper.policy" \
    /usr/share/polkit-1/actions/com.nexussense.helper.policy

  # --- o grupo, e o aviso que ele exige
  if ! getent group nexus_sense > /dev/null; then
    groupadd -r nexus_sense
    echo -e "${YELLOW}Grupo nexus_sense criado.${NC}"
  fi
  local alvo
  alvo=$(detect_desktop_user)
  if [ -n "$alvo" ]; then
    usermod -aG nexus_sense "$alvo"
    echo -e "${BLUE}Usuário ${alvo} adicionado ao grupo nexus_sense.${NC}"
  fi
  # A spec exige que o instalador diga isto em voz alta ao criar o grupo.
  echo -e "${YELLOW}Atenção: quem estiver no grupo nexus_sense pode alterar${NC}"
  echo -e "${YELLOW}as ventoinhas e o perfil térmico sem senha. O driver limita${NC}"
  echo -e "${YELLOW}a ventoinha a 0-100 e 0 significa automático, então o pior${NC}"
  echo -e "${YELLOW}caso é modesto -- mas é uma permissão que antes não existia.${NC}"
  echo -e "${YELLOW}O grupo só vale depois de relogar.${NC}"

  # --- a regra udev que aplica o grupo aos seis atributos
  install -m 644 "${raiz}/packaging/60-nexus-sense.rules" \
    /etc/udev/rules.d/60-nexus-sense.rules
  udevadm control --reload
  udevadm trigger --subsystem-match=platform --action=change
  udevadm trigger --subsystem-match=platform-profile --action=change

  # --- a unit de usuario do agente
  install -d /usr/lib/systemd/user
  install -m 644 "${raiz}/packaging/nexus-sense-agent.service" \
    /usr/lib/systemd/user/nexus-sense-agent.service
  systemctl daemon-reload
  # --global habilita para todo usuario sem precisar de sessao ativa.
  systemctl --global enable nexus-sense-agent.service

  refresh_desktop_database
  echo -e "${GREEN}Nexus Sense instalado.${NC}"
  return 0
}
```

E em `perform_install`, logo **depois** da linha `install_gui` e do seu
`GUI_RESULT=$?`:

```bash
  install_nexus_sense
  NEXUS_RESULT=$?
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
./tests/test-instalacao-nexus.sh; echo "saida=$?"
./tests/run-all.sh
```

Esperado: `OK: o instalador coloca o Nexus Sense no lugar`, saída `0`; a
suíte shell com um teste a mais e nenhuma falha nova.

- [ ] **Step 5: Instalar de verdade e conferir**

```bash
export SUDO_ASKPASS=~/.local/bin/claude-askpass
cd /home/brunodobner/Claude/Nitrosense/original
sudo -A bash -c 'source ./setup.sh 2>/dev/null; install_nexus_sense' || \
  echo "se o source não funcionar, rode ./setup.sh e escolha a instalação completa"
```

Confira o que ficou:

```bash
ls -l /usr/bin/nexus-sense /usr/bin/nexus-sense-agent
ls /usr/lib/nexus-sense/
systemctl --user status nexus-sense-agent.service --no-pager | head -5
nexus-sense --version
```

Esperado: os dois lançadores executáveis, o pacote e o helper em
`/usr/lib/nexus-sense/`, a unit conhecida pelo systemd do usuário e
`0.1.0` na versão. **O agente ainda nasce com `auto_switch = false`** —
não disputa nada com o `damx-daemon`, que continua no ar.

- [ ] **Step 6: Commit**

```bash
git add packaging/nexus-sense.desktop original/setup.sh tests/test-instalacao-nexus.sh
git commit -m "feat: instalacao do Nexus Sense, sem remover nada ainda

O pacote vai inteiro para /usr/lib/nexus-sense e os lancadores apontam
PYTHONPATH para la: instalar por pip dentro de /usr brigaria com o
gerenciador de pacotes pelos mesmos caminhos, e desinstalar passa a ser
apagar uma pasta.

O instalador diz em voz alta o que o grupo novo permite, como a spec
exige, e lembra que ele so vale depois de relogar.

O damx-daemon continua no ar e o agente continua com auto_switch
desligado. A virada e a proxima tarefa.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: A virada

A única tarefa deste plano que **desliga** coisas. Até aqui tudo foi
acrescentado ao lado do que já rodava; agora o `damx-daemon` sai, a GUI
binária sai, e a correção automática do agente é ligada.

**Files:**
- Modify: `src/nexus_sense/config.py` (o padrão do `auto_switch`)
- Modify: `tests/python/test_config.py` (o teste que fixa esse padrão)
- Modify: `original/setup.sh` (remove a instalação antiga, religa o botão)
- Modify: `original/nitro-key-detection.sh` (aponta para o `nexus-sense`)
- Modify: `tests/test-nitro-key.sh` (os nomes das funções mudaram)
- Modify: `.gitignore` (os binários deixam de existir)
- Modify: `docs/ESTADO.md`, `README.md`
- Delete: `original/DAMX-Daemon/`, `original/DAMX-GUI/DivAcerManagerMax`

**Ordem importa.** Ligar o `auto_switch` com o `damx-daemon` ainda no ar
põe os dois disputando o perfil térmico: um devolve o que o outro
derruba. O passo 5 desliga o daemon **antes** do passo 6 ligar o agente.

- [ ] **Step 1: Virar o padrão do `auto_switch`**

Em `tests/python/test_config.py`, o primeiro teste passa a fixar o padrão
novo:

```python
def test_o_padrao_liga_a_troca_automatica():
    """Ligado desde a virada. Enquanto o damx-daemon existia, os dois
    disputariam o perfil; agora nao ha com quem disputar, e sem isto a
    maquina fica em balanced-performance na bateria por tempo
    indefinido -- um estado que ela recusaria assumir se pedido.
    Ver spec secao 2.9."""
    padrao = Config()
    assert padrao.auto_switch is True
    assert padrao.battery_profile == "balanced"
    assert padrao.saved_ac_profile is None
```

Rode e confirme que **falha**:

```bash
python3 -m pytest tests/python/test_config.py -q
```

Esperado: `assert False is True`.

Em `src/nexus_sense/config.py`, troque o campo e o comentário acima dele:

```python
    # Ligado desde a virada. Enquanto o damx-daemon existia isto ficava
    # desligado, para os dois nao disputarem o perfil; agora nao ha com
    # quem disputar. Ver spec secao 2.9.
    auto_switch: bool = True
```

E confirme que passa:

```bash
python3 -m pytest tests/python/test_config.py -q
```

Esperado: `9 passed`.

- [ ] **Step 2: Tirar a instalação antiga do `setup.sh`**

Três edições em `original/setup.sh`:

**(a)** Em `perform_install`, remova as quatro linhas que instalam o
daemon e a GUI antigos:

```bash
  install_daemon
  DAEMON_RESULT=$?

  install_gui
  GUI_RESULT=$?
```

e ajuste a verificação final, que as citava:

```bash
  if [ $DRIVER_RESULT -eq 0 ] && [ $NEXUS_RESULT -eq 0 ]; then
    echo -e "${GREEN}Nexus Sense installation completed successfully!${NC}"
    echo -e "You can now run the GUI using the ${BLUE}nexus-sense${NC} command or from your application launcher."
```

trocando também o `systemctl status ${DAEMON_SERVICE_NAME}` do fim por:

```bash
    echo -e "${BLUE}Agent status:${NC}"
    systemctl --user status nexus-sense-agent.service --no-pager -l 2>/dev/null || \
      echo "o agente é serviço de usuário: confira com 'systemctl --user status nexus-sense-agent'"
```

**(b)** Apague as funções `install_daemon()` e `install_gui()` inteiras.

**(c)** Em `comprehensive_cleanup`, acrescente a remoção do que sai — ao
lado das limpezas que já existem:

```bash
  # A virada: o daemon root e a GUI binaria saem. Ver spec, decisao D2.
  #
  # O socket em /var/run/DAMX.sock era modo 666, sem autenticacao:
  # qualquer processo da maquina podia recarregar o driver por ele.
  # Some junto e nao volta.
  if systemctl list-unit-files | grep -q '^damx-daemon.service'; then
    echo "Removendo o damx-daemon..."
    systemctl stop damx-daemon.service 2> /dev/null || true
    systemctl disable damx-daemon.service 2> /dev/null || true
    rm -f "${SYSTEMD_DIR}/damx-daemon.service"
    systemctl daemon-reload
  fi
  rm -rf /opt/damx /opt/DAMX
  rm -f /usr/local/bin/DAMX /var/run/DAMX.sock
  rm -f "${DESKTOP_FILE_DIR}/damx.desktop"
```

- [ ] **Step 3: Religar o botão N ao Nexus Sense**

Em `original/setup.sh`, as duas funções do botão passam a apontar para o
lançador novo. Renomeie `bind_button_to_damx` para `bind_button_to_nexus`
e `unbind_button_from_damx` para `unbind_button_from_nexus`, e **dentro
delas** troque:

| era | passa a ser |
|---|---|
| `--group damx.desktop` | `--group nexus-sense.desktop` |
| `--key _k_friendly_name "DAMX"` | `--key _k_friendly_name "Nexus Sense"` |
| `DAMX already has the shortcut` | `Nexus Sense already has the shortcut` |
| `Button bound to DAMX for user` | `Button bound to Nexus Sense for user` |
| `To open DAMX with the button` | `To open Nexus Sense with the button` |
| `add the DAMX application` | `add the Nexus Sense application` |
| `Removing the DAMX button shortcut` | `Removing the Nexus Sense button shortcut` |
| `Keeping the custom DAMX shortcut` | `Keeping the custom Nexus Sense shortcut` |

Atualize também as chamadas: `bind_button_to_damx` em
`configure_nitro_button`, e `unbind_button_from_damx` em
`comprehensive_cleanup`.

> O comentário sobre `"Launch (1)"` **fica como está**. Ele registra que
> escrever o nome do keysym faz o KWin apagar a entrada em silêncio, e
> isso continua verdade com qualquer `.desktop`.

Em `original/nitro-key-detection.sh`, a linha 117 e a 124:

```bash
    if ! pgrep -f "/usr/bin/nexus-sense" > /dev/null; then
```

```bash
            nexus-sense &
```

- [ ] **Step 4: Atualizar o teste do botão**

`tests/test-nitro-key.sh` procura os nomes antigos das funções e falharia.
Troque, nas linhas 98, 104, 111, 118 e 139:

| era | passa a ser |
|---|---|
| `bind_button_to_damx` | `bind_button_to_nexus` |
| `unbind_button_from_damx` | `unbind_button_from_nexus` |

E rode:

```bash
./tests/test-nitro-key.sh; echo "saida=$?"
```

Esperado: saída `0`. Se falhar apontando `damx.desktop`, ficou alguma
ocorrência para trocar — `grep -n damx original/setup.sh` mostra quais.

- [ ] **Step 5: Desligar o daemon e a GUI antiga nesta máquina**

```bash
export SUDO_ASKPASS=~/.local/bin/claude-askpass
systemctl is-active damx-daemon.service
sudo -A systemctl disable --now damx-daemon.service
sudo -A rm -f /etc/systemd/system/damx-daemon.service /usr/local/bin/DAMX \
              /usr/share/applications/damx.desktop
sudo -A rm -rf /opt/damx
sudo -A systemctl daemon-reload
systemctl is-active damx-daemon.service; echo "esperado: inactive ou não encontrado"
ls /opt/damx 2>&1 | head -1
```

Esperado: o serviço para e some, `/opt/damx` deixa de existir. **A partir
daqui a correção de perfil na troca de fonte não tem dono** — o passo 6
devolve o dono a ela.

- [ ] **Step 6: Ligar o agente**

```bash
systemctl --user enable --now nexus-sense-agent.service
systemctl --user is-active nexus-sense-agent.service
journalctl --user -u nexus-sense-agent.service -n 5 --no-pager
```

Esperado: `active`, e no log a linha "agente no ar, sondando a cada
2.0 s". Se disser que a unit não existe, a Task 11 não chegou a instalá-la:
`systemctl --global enable nexus-sense-agent.service` como root resolve.

- [ ] **Step 7: Verificar a correção de ponta a ponta**

Este é o teste que só existe com o cabo na mão, e é o que justifica o
projeto inteiro (spec §2.9).

```bash
cat /sys/devices/platform/acer-wmi/platform-profile/*/profile
```

1. Ponha o perfil em **Desempenho** pela janela ou pela bandeja.
2. **Tire o cabo da tomada.** Espere ~3 s.
3. Leia de novo o perfil: tem de estar em `balanced`.
4. **Ponha o cabo de volta.** Espere ~3 s.
5. Leia mais uma vez: tem de ter **voltado** para `balanced-performance`.

```bash
journalctl --user -u nexus-sense-agent.service -n 10 --no-pager
```

Esperado no log: uma linha `perfil -> balanced` ao desconectar e uma
`perfil -> balanced-performance (de volta na tomada: devolvendo ...)` ao
religar. **O passo 5 é o que o daemon antigo nunca fez:** ele derrubava e
não restaurava.

- [ ] **Step 8: Apagar os binários e a regra que os ignorava**

Eles nunca foram versionados — saíram do histórico na fase A e ficaram no
disco, ignorados pelo git. Some o objeto, some a regra.

```bash
du -sh original/DAMX-Daemon original/DAMX-GUI
rm -rf original/DAMX-Daemon
rm -f original/DAMX-GUI/DivAcerManagerMax
ls original/DAMX-GUI/
```

Esperado: ~121 MB liberados; sobram em `original/DAMX-GUI/` apenas os dois
PNGs, que **são** versionados e ficam como referência do ícone antigo.

Em `.gitignore`, substitua o bloco dos binários — o comentário inteiro,
das linhas `# Binarios distribuidos pelo upstream` até
`original/DAMX-Daemon/DAMX-Daemon` — por:

```
# Os binarios do upstream (DivAcerManagerMax e DAMX-Daemon) foram
# removidos na virada da GUI: nao ha mais o que ignorar. Se uma release
# nova do upstream os trouxer de volta ao extrair, apague-os -- este
# fork nao os instala nem os distribui.
```

- [ ] **Step 9: Rodar as duas suítes**

```bash
python3 -m pytest -q
./tests/run-all.sh
```

Esperado: pytest verde; na suíte shell, `test-instalacao-nexus.sh` e
`test-nitro-key.sh` passando, e `test-permissoes.sh` e
`test-perfil-bateria.sh` passando **se** a sessão já carregar o grupo.

- [ ] **Step 10: Atualizar o README e o ESTADO**

No `README.md`, onde ele descreve os componentes instalados, o par
"DAMX-Daemon + DAMX-GUI" passa a ser:

```markdown
| componente | o que é |
|---|---|
| `linuwu_sense` | o driver, um módulo do kernel |
| `nexus-sense` | a interface: janela e bandeja, PySide6 |
| `nexus-sense-agent` | serviço de usuário que corrige o perfil na troca de fonte |
| `nexus-sense-helper` | root por `pkexec`, só para recarregar o driver |

Não há daemon, não há socket e não há processo root permanente. A escrita
diária passa por permissão de grupo em `sysfs`.
```

Em `docs/ESTADO.md`: marque o plano 2 como concluído no roteiro, mova-o
para "Concluído" com o resumo das doze tarefas, e passe a vez para a
**renomeação para `nexus_sense`** (spec §12). Registre em "O que mudou na
máquina": o `damx-daemon` não existe mais, o agente está ativo com
`auto_switch` ligado, e o botão N abre o `nexus-sense`.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: a virada -- sai o daemon, entra o agente

O damx-daemon e a GUI binaria saem do instalador e da maquina. Com eles
sai o socket em /var/run/DAMX.sock, que era modo 666 e aceitava
recarregar o driver de qualquer processo sem autenticacao.

auto_switch passa a nascer ligado: nao ha mais com quem disputar o
perfil, e sem ele a maquina fica em balanced-performance na bateria por
tempo indefinido -- um estado que ela recusaria assumir se pedido.

O botao N passa a abrir o nexus-sense. Os ~121 MB de binario saem do
disco; do historico ja tinham saido na fase A.

Verificado na maquina: com o cabo fora o perfil cai para balanced, e ao
religar ele VOLTA ao anterior -- que e o defeito que o daemon antigo
nunca corrigiu.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## O que este plano entrega

- a janela com as cinco seções da spec §6, em pt-BR, com os perfis em
  posições fixas e o indisponível hachurado com o motivo;
- a bandeja `StatusNotifierItem` com scroll que pula o degrau barrado, e
  dois níveis de degradação previstos e testados;
- o helper com `pkexec`, conjunto fechado de operações, validado dos dois
  lados;
- os cinco ícones por perfil, gerados pelo `gerar.sh` a partir da mesma
  marca;
- a virada: sem daemon, sem socket, sem processo root permanente, e a
  correção de perfil que **devolve** o perfil ao religar o cabo;
- uma suíte que continua rodando sem hardware, sem root e sem sessão
  gráfica — o Qt roda offscreen.

## O que fica de fora, e por quê

- **Teclado RGB de quatro zonas.** Este laptop não o tem
  (`has_four_zone_kb: false`) e o código seria escrito sem poder ser
  verificado. Spec §14.
- **`lcd_override` e `boot_animation_sound`.** Existem no protocolo do
  daemon antigo e não constam dos recursos que este firmware anuncia.
- **Empacotamento por distribuição.** O app exige `pyside6` e `qt6-base`
  presentes. Spec §14.
- **A renomeação do módulo para `nexus_sense`.** Fase própria, com plano
  próprio: toca o instalador e cinco testes, e exige desinstalação limpa
  do DKMS antigo antes. Spec §12.

## Riscos que este plano carrega

| risco | onde aparece | saída |
|---|---|---|
| o Plasma pode não chamar `ContextMenu()` sem menu DBus exportado | Task 9, verificação manual §2 | implementar `com.canonical.dbusmenu`; mais trabalho, mesmo resultado |
| o `ToolTip` do SNI é uma struct que o PySide6 não empacota bem | Task 9 | o texto vai no `Title`, que o Plasma usa como tooltip; a verificação manual confere como aparece |
| a regra udev pode não disparar na ordem certa em todo boot | Task 11 | verificar depois de um boot; alternativa é aplicar no `ExecStart` da unit do módulo |
| o `ppd` pode passar a disputar o `platform_profile` numa versão futura | Task 7 | o Diagnóstico já acusa; a hipótese da spec §2.11 fica para medir |
| o agente passa a depender de sessão gráfica | Task 12 | regressão registrada e aceita na spec §8: a alternativa reintroduziria o processo root permanente |
