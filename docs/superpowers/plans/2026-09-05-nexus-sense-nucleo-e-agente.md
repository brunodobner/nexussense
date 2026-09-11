# Nexus Sense — núcleo e agente — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir a camada de acesso a sysfs, o modelo de perfis e o agente de correção de energia — tudo que substitui o `DAMX-Daemon`, sem tocar na GUI.

**Architecture:** Todo acesso a sysfs passa por `Sysfs(root)`, que aceita uma raiz alternativa; com isso quase toda a suíte roda sem hardware, sem root e sem laptop Acer. Sobre essa camada ficam um modelo puro (perfis, disponibilidade, validação), leitores de telemetria e um agente sem interface que roda como serviço de usuário. Nenhum componente abre caminho absoluto, e nenhum precisa de privilégio permanente.

**Tech Stack:** Python 3.14 (stdlib), `tomli-w` para escrita de TOML, `pytest` para testes. Sem Qt neste plano.

**Spec:** `docs/superpowers/specs/2026-09-05-nexus-sense-gui-agente-design.md`

## Global Constraints

Valem para todas as tarefas. Valores copiados da spec.

- **Identificadores em inglês, comentários e docstrings em português, textos de usuário em pt-BR.** É a convenção já usada no `.c` do driver neste fork.
- **Nenhum acesso a caminho absoluto fora de `Sysfs`.** Toda leitura e escrita recebe a raiz. Spec §4.3.
- **hwmon nunca por índice.** O sensor `acer` vem de `/sys/devices/platform/acer-wmi/hwmon/hwmon*/`; os demais, procurando por `name`. Spec §10.1.
- **Nunca chamar `nvidia-smi` com a GPU adormecida.** Ler `power/runtime_status` antes; se for `suspended`, não sondar. Spec §10.2.
- **Os seis atributos graváveis** (spec §2.6), e nenhum outro:
  ```
  <acer-wmi>/nitro_sense/{fan_speed,battery_limiter,usb_charging,
                          backlight_timeout,battery_calibration}
  <acer-wmi>/platform-profile/platform-profile-0/profile
  ```
  Grupo `nexus_sense`, modo `664`. O atributo `version` continua `444`.
- **Perfis recusados na bateria pelo driver:** `quiet`, `balanced-performance`, `performance` (`linuwu_sense.c:2317`). O alcance permitido não é contíguo. Spec §2.8.
- **Formato do `fan_speed`:** `"%d,%d"`, ambos inteiros de 0 a 100 (`linuwu_sense.c:3651`, `:3681-3693`).
- **Níveis de `usb_charging`:** exatamente `0`, `10`, `20`, `30`.
- **Nomes** conforme spec §12.1. O módulo do kernel ainda se chama `linuwu_sense` nesta fase; a renomeação é fase própria, e o código já aceita os dois nomes.
- **Este plano não desliga nada.** O `damx-daemon.service` e a GUI antiga continuam no ar até o plano 2 fazer a virada. O agente é instalado com `auto_switch = false` por padrão, para não disputar a correção de perfil com o daemon ainda ativo.

---

## Estrutura de arquivos

| arquivo | responsabilidade |
|---|---|
| `src/nexus_sense/__init__.py` | versão do pacote |
| `src/nexus_sense/sysfs.py` | ancoragem da raiz, descoberta de caminhos, leitura e escrita, fonte de energia |
| `src/nexus_sense/model.py` | escada de perfis, disponibilidade por fonte, validação dos controles |
| `src/nexus_sense/telemetry.py` | hwmon, temperaturas, ventoinhas, GPU com guarda de sono |
| `src/nexus_sense/config.py` | `~/.config/nexus-sense/config.toml` |
| `src/nexus_sense/agent.py` | a decisão (pura) e o laço |
| `src/nexus_sense/__main__.py` | ponto de entrada do agente |
| `packaging/60-nexus-sense.rules` | regra udev do grupo |
| `packaging/nexus-sense-agent.service` | unit de usuário |
| `tests/python/conftest.py` | construtor da árvore de mentira |
| `tests/python/test_*.py` | suíte sem hardware |
| `tests/test-permissoes.sh` | teste com hardware, entra na suíte shell |
| `tests/test-perfil-bateria.sh` | teste com hardware, pula na tomada |

Os testes em shell seguem o contrato do `tests/run-all.sh`: saída `0` passou, `2` pulou, `3` alvo ausente, qualquer outra falhou.

---

### Task 1: Camada Sysfs com raiz configurável

**Files:**
- Create: `pyproject.toml`
- Create: `src/nexus_sense/__init__.py`
- Create: `src/nexus_sense/sysfs.py`
- Create: `tests/python/conftest.py`
- Test: `tests/python/test_sysfs.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `Sysfs(root: str | Path = "/")` com atributo `.root: Path`
  - `Sysfs.acer_base() -> Path`
  - `Sysfs.sense_dir() -> Path | None` — `nitro_sense` ou `predator_sense`
  - `Sysfs.profile_path() -> Path | None`
  - `Sysfs.choices_path() -> Path | None`
  - `Sysfs.module_loaded() -> bool`
  - `Sysfs.read(path: Path) -> str` — já sem espaços nas pontas
  - `Sysfs.write(path: Path, value: str) -> None`
  - `Sysfs.on_ac() -> bool | None` — `None` quando nenhum caminho de fonte existe
  - fixture `fake_root` do pytest, que devolve um `Path` de árvore ANV15-52 completa
  - função `build_tree(root, *, on_ac=True, profile="balanced", choices=..., hwmon_offset=0, sense="nitro_sense")`

- [ ] **Step 1: Instalar as dependências de teste**

```bash
export SUDO_ASKPASS=~/.local/bin/claude-askpass
sudo -A pacman -S --needed --noconfirm python-pytest python-tomli-w
```

Confirme:

```bash
python3 -c "import pytest, tomli_w; print(pytest.__version__)"
```

- [ ] **Step 2: Criar o `pyproject.toml`**

```toml
[project]
name = "nexus-sense"
version = "0.1.0"
description = "Controle e monitoramento para laptops Acer Nitro e Predator no Linux"
requires-python = ">=3.11"
dependencies = ["tomli-w>=1.0"]

[project.scripts]
nexus-sense-agent = "nexus_sense.__main__:main"

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
testpaths = ["tests/python"]
pythonpath = ["src"]
```

- [ ] **Step 3: Criar o pacote**

`src/nexus_sense/__init__.py`:

```python
"""Controle e monitoramento para laptops Acer Nitro e Predator."""

__version__ = "0.1.0"
```

- [ ] **Step 4: Escrever o construtor da árvore de mentira**

`tests/python/conftest.py`:

```python
"""Arvore sysfs falsa, para testar sem hardware, sem root e sem laptop Acer.

O indice do hwmon e deslocavel de proposito (hwmon_offset): o codigo de
producao nunca pode depender do numero, so do nome ou do dispositivo pai.
Ver spec secao 10.1.
"""

import pytest

CHOICES_PADRAO = "low-power quiet balanced balanced-performance"

ATRIBUTOS_SENSE = {
    "fan_speed": "0,0",
    "battery_limiter": "1",
    "usb_charging": "0",
    "backlight_timeout": "0",
    "battery_calibration": "0",
    "version": "25.701",
}


def build_tree(
    root,
    *,
    on_ac=True,
    profile="balanced",
    choices=CHOICES_PADRAO,
    hwmon_offset=0,
    sense="nitro_sense",
    module="linuwu_sense",
    fans=(2079, 1870),
    acer_temps=(25000, 43000, 43000),
    cpu_package=47000,
):
    """Monta uma arvore ANV15-52 completa sob `root` e devolve `root`."""

    def escreve(caminho, conteudo):
        caminho.parent.mkdir(parents=True, exist_ok=True)
        caminho.write_text(f"{conteudo}\n")

    acer = root / "sys/devices/platform/acer-wmi"

    for nome, valor in ATRIBUTOS_SENSE.items():
        escreve(acer / sense / nome, valor)

    escreve(acer / "platform-profile/platform-profile-0/profile", profile)
    escreve(acer / "platform-profile/platform-profile-0/choices", choices)
    escreve(acer / "platform-profile/platform-profile-0/name", "acer-wmi")

    if module:
        (root / "sys/module" / module).mkdir(parents=True, exist_ok=True)

    # hwmon do acer, ancorado no dispositivo
    n_acer = hwmon_offset + 5
    h_acer = acer / f"hwmon/hwmon{n_acer}"
    escreve(h_acer / "name", "acer")
    escreve(h_acer / "fan1_input", fans[0])
    escreve(h_acer / "fan2_input", fans[1])
    for i, t in enumerate(acer_temps, start=1):
        escreve(h_acer / f"temp{i}_input", t)

    # /sys/class/hwmon: links por indice, na ordem embaralhada
    classe = root / "sys/class/hwmon"
    classe.mkdir(parents=True, exist_ok=True)
    (classe / f"hwmon{n_acer}").symlink_to(h_acer)

    n_core = hwmon_offset + 6
    h_core = root / f"sys/devices/platform/coretemp.0/hwmon/hwmon{n_core}"
    escreve(h_core / "name", "coretemp")
    escreve(h_core / "temp1_label", "Package id 0")
    escreve(h_core / "temp1_input", cpu_package)
    escreve(h_core / "temp2_label", "Core 0")
    escreve(h_core / "temp2_input", cpu_package - 2000)
    (classe / f"hwmon{n_core}").symlink_to(h_core)

    # fonte de energia
    escreve(root / "sys/class/power_supply/ACAD/online", 1 if on_ac else 0)
    escreve(root / "sys/class/power_supply/BAT1/capacity", 80)
    escreve(root / "sys/class/power_supply/BAT1/status", "Not charging")

    # dGPU NVIDIA
    gpu = root / "sys/bus/pci/devices/0000:01:00.0"
    escreve(gpu / "vendor", "0x10de")
    escreve(gpu / "class", "0x030000")
    escreve(gpu / "power/runtime_status", "active")
    escreve(gpu / "power/control", "auto")

    return root


@pytest.fixture
def fake_root(tmp_path):
    """Arvore ANV15-52 padrao: na tomada, perfil balanced, quatro escolhas."""
    return build_tree(tmp_path)
```

- [ ] **Step 5: Escrever os testes que falham**

`tests/python/test_sysfs.py`:

```python
from pathlib import Path

import pytest

from nexus_sense.sysfs import Sysfs

from conftest import build_tree


def test_encontra_o_diretorio_nitro_sense(fake_root):
    s = Sysfs(fake_root)
    assert s.sense_dir() == fake_root / "sys/devices/platform/acer-wmi/nitro_sense"


def test_encontra_predator_sense_quando_e_um_predator(tmp_path):
    build_tree(tmp_path, sense="predator_sense")
    s = Sysfs(tmp_path)
    assert s.sense_dir().name == "predator_sense"


def test_sense_dir_e_none_sem_o_driver(tmp_path):
    assert Sysfs(tmp_path).sense_dir() is None


def test_acha_o_profile_sem_depender_do_numero_do_dispositivo(fake_root):
    p = Sysfs(fake_root).profile_path()
    assert p.name == "profile"
    assert p.parent.name == "platform-profile-0"


def test_le_o_valor_sem_a_quebra_de_linha(fake_root):
    s = Sysfs(fake_root)
    assert s.read(s.profile_path()) == "balanced"


def test_le_as_escolhas_do_firmware(fake_root):
    s = Sysfs(fake_root)
    assert s.read(s.choices_path()).split() == [
        "low-power",
        "quiet",
        "balanced",
        "balanced-performance",
    ]


def test_escreve_e_le_de_volta(fake_root):
    s = Sysfs(fake_root)
    s.write(s.profile_path(), "quiet")
    assert s.read(s.profile_path()) == "quiet"


def test_reconhece_o_modulo_com_o_nome_antigo(tmp_path):
    build_tree(tmp_path, module="linuwu_sense")
    assert Sysfs(tmp_path).module_loaded() is True


def test_reconhece_o_modulo_com_o_nome_novo(tmp_path):
    build_tree(tmp_path, module="nexus_sense")
    assert Sysfs(tmp_path).module_loaded() is True


def test_modulo_ausente(tmp_path):
    build_tree(tmp_path, module=None)
    assert Sysfs(tmp_path).module_loaded() is False


def test_detecta_a_tomada(fake_root):
    assert Sysfs(fake_root).on_ac() is True


def test_detecta_a_bateria(tmp_path):
    build_tree(tmp_path, on_ac=False)
    assert Sysfs(tmp_path).on_ac() is False


def test_fonte_desconhecida_devolve_none(tmp_path):
    assert Sysfs(tmp_path).on_ac() is None
```

- [ ] **Step 6: Rodar os testes e confirmar que falham**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_sysfs.py -q
```

Esperado: erro de coleta, `ModuleNotFoundError: No module named 'nexus_sense.sysfs'`.

- [ ] **Step 7: Implementar**

`src/nexus_sense/sysfs.py`:

```python
"""Acesso a sysfs ancorado numa raiz.

Nenhum outro modulo abre caminho absoluto. Passar uma raiz alternativa e
o que permite testar sem hardware, sem root e sem laptop Acer.
Ver spec secao 4.3.
"""

from pathlib import Path

# Nos dois nomes: o modulo ainda se chama linuwu_sense nesta fase, e a
# renomeacao para nexus_sense e fase propria. Aceitar os dois evita que a
# GUI quebre no meio da troca. Ver spec secao 12.
MODULE_NAMES = ("nexus_sense", "linuwu_sense")

# Nomes que o driver da ao grupo de atributos, conforme a familia do
# laptop. Estao fixados em linuwu_sense.c:4052-4068 e nomeiam o hardware,
# nao o projeto -- a renomeacao nao os toca.
SENSE_DIRS = ("nitro_sense", "predator_sense")

# O daemon antigo tentava quatro nomes; nesta maquina existe so o ACAD.
AC_NAMES = ("AC", "ACAD", "ADP1", "AC0")


class Sysfs:
    """Le e escreve sysfs a partir de uma raiz configuravel."""

    def __init__(self, root="/"):
        self.root = Path(root)

    # ------------------------------------------------------------------
    # descoberta de caminhos
    # ------------------------------------------------------------------

    def acer_base(self):
        """O dispositivo de plataforma sob o qual tudo que importa mora."""
        return self.root / "sys/devices/platform/acer-wmi"

    def sense_dir(self):
        """nitro_sense ou predator_sense, o que existir. None se nenhum."""
        for nome in SENSE_DIRS:
            caminho = self.acer_base() / nome
            if caminho.is_dir():
                return caminho
        return None

    def _profile_device(self):
        base = self.acer_base() / "platform-profile"
        if not base.is_dir():
            return None
        for filho in sorted(base.iterdir()):
            if (filho / "profile").is_file():
                return filho
        return None

    def profile_path(self):
        """O perfil termico. Nao usamos /sys/firmware/acpi/platform_profile:
        aquele e apelido legado e fica fora do alcance do udev."""
        dispositivo = self._profile_device()
        return None if dispositivo is None else dispositivo / "profile"

    def choices_path(self):
        """Os perfis que o firmware anuncia. Quatro nesta maquina, e nao
        cinco: falta o 'performance'. Ver spec secao 2.10."""
        dispositivo = self._profile_device()
        return None if dispositivo is None else dispositivo / "choices"

    def module_loaded(self):
        for nome in MODULE_NAMES:
            if (self.root / "sys/module" / nome).is_dir():
                return True
        return False

    # ------------------------------------------------------------------
    # leitura e escrita
    # ------------------------------------------------------------------

    def read(self, path):
        return Path(path).read_text().strip()

    def write(self, path, value):
        Path(path).write_text(str(value))

    def on_ac(self):
        """True na tomada, False na bateria, None se nao houver como saber."""
        for nome in AC_NAMES:
            caminho = self.root / "sys/class/power_supply" / nome / "online"
            if caminho.is_file():
                return self.read(caminho) == "1"
        return None
```

- [ ] **Step 8: Rodar os testes e confirmar que passam**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_sysfs.py -q
```

Esperado: `13 passed`.

- [ ] **Step 9: Commit**

```bash
git add pyproject.toml src/nexus_sense/ tests/python/
git commit -m "feat: camada Sysfs ancorada numa raiz configuravel

Todo acesso a sysfs passa por aqui, e a raiz e um parametro. E o que
permite testar o resto sem hardware, sem root e sem laptop Acer.

A arvore de mentira dos testes desloca o indice do hwmon de proposito:
o codigo de producao nunca pode depender do numero.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Escada de perfis e disponibilidade por fonte

**Files:**
- Create: `src/nexus_sense/model.py`
- Test: `tests/python/test_model.py`

**Interfaces:**
- Consumes: nada de `sysfs.py` — este módulo é puro, recebe listas e devolve listas.
- Produces:
  - `PROFILES: tuple[str, ...]` — ordem canônica, do mais econômico ao mais agressivo
  - `LABELS: dict[str, str]` — rótulo em pt-BR de cada perfil
  - `AC_ONLY: frozenset[str]`
  - `available(choices: Sequence[str], on_ac: bool) -> tuple[str, ...]`
  - `nearest(current: str, options: Sequence[str]) -> str`
  - `neighbour(current: str, choices: Sequence[str], on_ac: bool, step: int) -> str`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_model.py`:

```python
import pytest

from nexus_sense.model import (
    AC_ONLY,
    LABELS,
    PROFILES,
    available,
    nearest,
    neighbour,
)

QUATRO = ["low-power", "quiet", "balanced", "balanced-performance"]
CINCO = QUATRO + ["performance"]


def test_ordem_canonica_vai_do_economico_ao_agressivo():
    assert PROFILES == (
        "low-power",
        "quiet",
        "balanced",
        "balanced-performance",
        "performance",
    )


def test_todo_perfil_tem_rotulo_em_portugues():
    assert set(LABELS) == set(PROFILES)
    assert LABELS["low-power"] == "Econômico"
    assert LABELS["balanced-performance"] == "Desempenho"


def test_na_tomada_todos_os_anunciados_estao_disponiveis():
    assert available(QUATRO, on_ac=True) == tuple(QUATRO)


def test_na_bateria_o_driver_recusa_tres():
    assert AC_ONLY == frozenset({"quiet", "balanced-performance", "performance"})
    assert available(QUATRO, on_ac=False) == ("low-power", "balanced")


def test_o_alcance_na_bateria_tem_buraco_no_meio():
    """O Silencioso fica entre dois validos e mesmo assim e barrado.
    Medido na maquina: -EOPNOTSUPP. Ver spec secao 2.8."""
    disponiveis = available(QUATRO, on_ac=False)
    assert "quiet" not in disponiveis
    assert disponiveis.index("low-power") == 0
    assert disponiveis.index("balanced") == 1


def test_ignora_perfil_que_o_firmware_nao_anuncia():
    assert "performance" not in available(QUATRO, on_ac=True)
    assert "performance" in available(CINCO, on_ac=True)


def test_a_ordem_devolvida_e_sempre_a_canonica():
    embaralhado = ["balanced", "low-power", "balanced-performance", "quiet"]
    assert available(embaralhado, on_ac=True) == tuple(QUATRO)


def test_scroll_sobe_um_degrau_na_tomada():
    assert neighbour("balanced", QUATRO, on_ac=True, step=+1) == "balanced-performance"


def test_scroll_desce_um_degrau_na_tomada():
    assert neighbour("balanced", QUATRO, on_ac=True, step=-1) == "quiet"


def test_scroll_pula_o_indisponivel_na_bateria():
    """Subir do Economico leva direto ao Equilibrado: o Silencioso e barrado."""
    assert neighbour("low-power", QUATRO, on_ac=False, step=+1) == "balanced"


def test_scroll_bate_no_limite_e_para():
    assert neighbour("balanced", QUATRO, on_ac=False, step=+1) == "balanced"
    assert neighbour("low-power", QUATRO, on_ac=False, step=-1) == "low-power"
    assert (
        neighbour("balanced-performance", QUATRO, on_ac=True, step=+1)
        == "balanced-performance"
    )


def test_scroll_a_partir_de_um_perfil_que_ficou_invalido():
    """Estava em balanced-performance e o cabo saiu: o perfil corrente nao
    esta mais na lista. Vai para o valido mais proximo, nao para a ponta."""
    assert neighbour("balanced-performance", QUATRO, on_ac=False, step=-1) == "balanced"


def test_nearest_escolhe_pela_distancia_na_escada():
    assert nearest("balanced-performance", ["low-power", "balanced"]) == "balanced"
    assert nearest("quiet", ["low-power", "balanced"]) in {"low-power", "balanced"}


def test_sem_nenhum_perfil_disponivel_o_atual_permanece():
    assert neighbour("balanced", [], on_ac=True, step=+1) == "balanced"
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_model.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.model'`.

- [ ] **Step 3: Implementar**

`src/nexus_sense/model.py`:

```python
"""Perfis termicos: ordem, disponibilidade e navegacao.

Modulo puro: recebe listas e devolve listas, nao toca em disco. Toda a
logica que a bandeja e a janela usam para decidir o que mostrar e o que
o scroll faz mora aqui.
"""

# Do mais economico ao mais agressivo. A ordem importa: e ela que define
# o que "subir" e "descer" significam no scroll da bandeja.
PROFILES = (
    "low-power",
    "quiet",
    "balanced",
    "balanced-performance",
    "performance",
)

LABELS = {
    "low-power": "Econômico",
    "quiet": "Silencioso",
    "balanced": "Equilibrado",
    "balanced-performance": "Desempenho",
    "performance": "Turbo",
}

# O driver devolve -EOPNOTSUPP para estes tres quando nao ha energia da
# tomada (linuwu_sense.c:2317). Medido na maquina, com o cabo fora.
#
# Repare que o alcance resultante NAO e contiguo: o 'quiet' fica entre
# dois permitidos e mesmo assim e barrado, apesar de ser mais economico
# que o 'balanced'. Ver spec secao 2.8.
AC_ONLY = frozenset({"quiet", "balanced-performance", "performance"})


def available(choices, on_ac):
    """Perfis que o driver aceita agora, na ordem canonica.

    `choices` e o que o firmware anuncia; nesta maquina sao quatro, sem o
    'performance'. Ver spec secao 2.10.
    """
    anunciados = set(choices)
    return tuple(
        perfil
        for perfil in PROFILES
        if perfil in anunciados and (on_ac or perfil not in AC_ONLY)
    )


def nearest(current, options):
    """O perfil de `options` mais proximo de `current` na escada."""
    if not options:
        return current
    if current in options:
        return current
    if current not in PROFILES:
        return options[0]
    alvo = PROFILES.index(current)
    return min(options, key=lambda p: abs(PROFILES.index(p) - alvo))


def neighbour(current, choices, on_ac, step):
    """Proximo perfil valido na direcao `step` (+1 sobe, -1 desce).

    Anda sobre a lista de disponiveis, o que faz o indisponivel ser
    pulado em vez de virar um degrau que falharia. Bate no limite e para.
    Se o perfil corrente nao estiver mais disponivel -- caso de quem
    estava em balanced-performance quando o cabo saiu -- vai para o
    valido mais proximo.
    """
    opcoes = available(choices, on_ac)
    if not opcoes:
        return current
    if current not in opcoes:
        return nearest(current, opcoes)
    destino = opcoes.index(current) + step
    destino = max(0, min(len(opcoes) - 1, destino))
    return opcoes[destino]
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_model.py -q
```

Esperado: `14 passed`.

- [ ] **Step 5: Commit**

```bash
git add src/nexus_sense/model.py tests/python/test_model.py
git commit -m "feat: escada de perfis e disponibilidade por fonte de energia

O driver recusa quiet, balanced-performance e performance na bateria
(linuwu_sense.c:2317, medido). O alcance permitido nao e contiguo: o
quiet fica entre dois validos e mesmo assim e barrado.

neighbour() anda sobre a lista de disponiveis, entao o scroll pula o
indisponivel em vez de parar num degrau que falharia.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Validação dos controles graváveis

**Files:**
- Modify: `src/nexus_sense/model.py` (acrescenta ao fim)
- Modify: `tests/python/test_model.py` (acrescenta ao fim)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `USB_LEVELS: tuple[int, ...]` — `(0, 10, 20, 30)`
  - `fan_speed_value(cpu: int, gpu: int) -> str` — devolve `"cpu,gpu"`, levanta `ValueError`
  - `parse_fan_speed(raw: str) -> tuple[int, int]`
  - `usb_charging_value(level: int) -> str` — levanta `ValueError`
  - `bool_value(ligado: bool) -> str` — `"1"` ou `"0"`
  - `parse_bool(raw: str) -> bool`

- [ ] **Step 1: Escrever os testes que falham**

Acrescente ao fim de `tests/python/test_model.py`:

```python
from nexus_sense.model import (
    USB_LEVELS,
    bool_value,
    fan_speed_value,
    parse_bool,
    parse_fan_speed,
    usb_charging_value,
)


def test_ventoinha_no_formato_que_o_driver_espera():
    """linuwu_sense.c:3651 imprime "%d,%d"; o store le com strsep na virgula."""
    assert fan_speed_value(0, 0) == "0,0"
    assert fan_speed_value(100, 100) == "100,100"
    assert fan_speed_value(55, 40) == "55,40"


@pytest.mark.parametrize(
    "cpu,gpu", [(-1, 50), (50, -1), (101, 50), (50, 101), (200, 200)]
)
def test_ventoinha_fora_de_0_100_e_recusada(cpu, gpu):
    with pytest.raises(ValueError, match="0 a 100"):
        fan_speed_value(cpu, gpu)


def test_le_a_ventoinha_de_volta():
    assert parse_fan_speed("0,0") == (0, 0)
    assert parse_fan_speed("55,40\n") == (55, 40)


def test_ventoinha_ilegivel_levanta_erro():
    with pytest.raises(ValueError):
        parse_fan_speed("automatico")


def test_carga_usb_so_aceita_os_quatro_niveis():
    assert USB_LEVELS == (0, 10, 20, 30)
    for nivel in USB_LEVELS:
        assert usb_charging_value(nivel) == str(nivel)


@pytest.mark.parametrize("nivel", [1, 5, 15, 40, -10])
def test_carga_usb_recusa_qualquer_outro(nivel):
    with pytest.raises(ValueError, match="0, 10, 20 ou 30"):
        usb_charging_value(nivel)


def test_booleanos_viram_um_e_zero():
    assert bool_value(True) == "1"
    assert bool_value(False) == "0"
    assert parse_bool("1") is True
    assert parse_bool("0\n") is False
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_model.py -q
```

Esperado: `ImportError: cannot import name 'fan_speed_value'`.

- [ ] **Step 3: Implementar**

Acrescente ao fim de `src/nexus_sense/model.py`:

```python
# ----------------------------------------------------------------------
# Validacao dos controles graveis
#
# A validacao aqui espelha a do driver de proposito: e melhor recusar na
# interface, com a razao escrita, do que mandar e receber -EINVAL.
# ----------------------------------------------------------------------

USB_LEVELS = (0, 10, 20, 30)


def fan_speed_value(cpu, gpu):
    """Formata a velocidade das duas ventoinhas para o sysfs.

    O driver le "%d,%d" com strsep na virgula e recusa fora de 0-100
    (linuwu_sense.c:3681-3693). Zero significa automatico, nao parado.
    """
    for valor in (cpu, gpu):
        if not isinstance(valor, int) or not 0 <= valor <= 100:
            raise ValueError(f"velocidade de ventoinha fora de 0 a 100: {valor!r}")
    return f"{cpu},{gpu}"


def parse_fan_speed(raw):
    """Le de volta o "%d,%d" que o driver imprime."""
    partes = raw.strip().split(",")
    if len(partes) != 2:
        raise ValueError(f"velocidade de ventoinha ilegivel: {raw!r}")
    try:
        return int(partes[0]), int(partes[1])
    except ValueError as erro:
        raise ValueError(f"velocidade de ventoinha ilegivel: {raw!r}") from erro


def usb_charging_value(level):
    """O nivel de bateria abaixo do qual a carga USB para de fornecer."""
    if level not in USB_LEVELS:
        raise ValueError(f"carga USB deve ser 0, 10, 20 ou 30: {level!r}")
    return str(level)


def bool_value(ligado):
    return "1" if ligado else "0"


def parse_bool(raw):
    return raw.strip() == "1"
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_model.py -q
```

Esperado: `29 passed`.

- [ ] **Step 5: Commit**

```bash
git add src/nexus_sense/model.py tests/python/test_model.py
git commit -m "feat: validacao dos controles graveis

Espelha a validacao do driver de proposito: recusar na interface, com a
razao escrita, e melhor que mandar e receber -EINVAL.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Telemetria — hwmon ancorado e por nome

**Files:**
- Create: `src/nexus_sense/telemetry.py`
- Test: `tests/python/test_telemetry.py`

**Interfaces:**
- Consumes: `Sysfs` da Task 1.
- Produces:
  - `acer_hwmon(sysfs: Sysfs) -> Path | None`
  - `hwmon_by_name(sysfs: Sysfs, name: str) -> Path | None`
  - `fan_rpm(sysfs: Sysfs) -> tuple[int, int] | None`
  - `acer_temperatures(sysfs: Sysfs) -> tuple[int, ...]` — em graus Celsius inteiros
  - `cpu_package_temp(sysfs: Sysfs) -> float | None` — Celsius com uma casa

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_telemetry.py`:

```python
import pytest

from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import (
    acer_hwmon,
    acer_temperatures,
    cpu_package_temp,
    fan_rpm,
    hwmon_by_name,
)

from conftest import build_tree


def test_acha_o_hwmon_do_acer_pelo_dispositivo_pai(fake_root):
    h = acer_hwmon(Sysfs(fake_root))
    assert h is not None
    assert (h / "name").read_text().strip() == "acer"


@pytest.mark.parametrize("offset", [0, 3, 11, 40])
def test_o_indice_do_hwmon_nao_importa(tmp_path, offset):
    """O numero muda entre boots conforme a ordem de carga dos modulos.
    Depender dele e bomba-relogio. Ver spec secao 10.1."""
    build_tree(tmp_path, hwmon_offset=offset)
    s = Sysfs(tmp_path)
    assert acer_hwmon(s) is not None
    assert hwmon_by_name(s, "coretemp") is not None


def test_hwmon_por_nome_nao_confunde_sensores(fake_root):
    s = Sysfs(fake_root)
    assert (hwmon_by_name(s, "coretemp") / "name").read_text().strip() == "coretemp"
    assert hwmon_by_name(s, "nao-existe") is None


def test_le_a_rotacao_das_duas_ventoinhas(fake_root):
    assert fan_rpm(Sysfs(fake_root)) == (2079, 1870)


def test_rotacao_e_none_sem_o_sensor(tmp_path):
    assert fan_rpm(Sysfs(tmp_path)) is None


def test_temperaturas_do_acer_vem_em_celsius(fake_root):
    """O sysfs entrega milicelsius; a interface mostra Celsius."""
    assert acer_temperatures(Sysfs(fake_root)) == (25, 43, 43)


def test_temperatura_do_pacote_da_cpu_vem_do_coretemp(fake_root):
    assert cpu_package_temp(Sysfs(fake_root)) == pytest.approx(47.0)


def test_temperatura_da_cpu_e_none_sem_coretemp(tmp_path):
    assert cpu_package_temp(Sysfs(tmp_path)) is None


def test_acha_o_pacote_pelo_rotulo_e_nao_pelo_numero(tmp_path):
    """temp1 costuma ser o pacote, mas a garantia e o rotulo."""
    build_tree(tmp_path)
    core = tmp_path / "sys/devices/platform/coretemp.0/hwmon/hwmon6"
    (core / "temp1_label").write_text("Core 0\n")
    (core / "temp1_input").write_text("31000\n")
    (core / "temp2_label").write_text("Package id 0\n")
    (core / "temp2_input").write_text("52000\n")
    assert cpu_package_temp(Sysfs(tmp_path)) == pytest.approx(52.0)
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_telemetry.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.telemetry'`.

- [ ] **Step 3: Implementar**

`src/nexus_sense/telemetry.py`:

```python
"""Leitura de sensores.

Regra que atravessa o modulo inteiro: hwmon nunca pelo indice.

O numero em /sys/class/hwmon/hwmonN depende da ordem de carga dos
modulos e muda entre boots. Nesta maquina o sensor do acer e o hwmon5
hoje, e pode ser outro amanha. O acer se acha pelo dispositivo pai; os
demais, procurando pelo conteudo de 'name'. Ver spec secao 10.1.
"""

PACKAGE_LABEL = "Package id 0"


def acer_hwmon(sysfs):
    """O sensor do acer-wmi, ancorado no dispositivo de plataforma."""
    base = sysfs.acer_base() / "hwmon"
    if not base.is_dir():
        return None
    for filho in sorted(base.iterdir()):
        if (filho / "name").is_file():
            return filho
    return None


def hwmon_by_name(sysfs, name):
    """Procura em /sys/class/hwmon pelo conteudo de 'name', nunca pelo numero."""
    base = sysfs.root / "sys/class/hwmon"
    if not base.is_dir():
        return None
    for filho in sorted(base.iterdir()):
        rotulo = filho / "name"
        try:
            if rotulo.read_text().strip() == name:
                return filho
        except OSError:
            continue
    return None


def fan_rpm(sysfs):
    """Rotacao real das duas ventoinhas, em rpm.

    Nao confundir com o atributo fan_speed do driver, que e o setpoint:
    ele devolve "0,0" para automatico. Ver spec secao 2.5.
    """
    hwmon = acer_hwmon(sysfs)
    if hwmon is None:
        return None
    try:
        return (
            int(sysfs.read(hwmon / "fan1_input")),
            int(sysfs.read(hwmon / "fan2_input")),
        )
    except (OSError, ValueError):
        return None


def acer_temperatures(sysfs):
    """As temperaturas do acer-wmi, em Celsius inteiros."""
    hwmon = acer_hwmon(sysfs)
    if hwmon is None:
        return ()
    valores = []
    for indice in range(1, 10):
        caminho = hwmon / f"temp{indice}_input"
        if not caminho.is_file():
            break
        try:
            valores.append(int(sysfs.read(caminho)) // 1000)
        except (OSError, ValueError):
            break
    return tuple(valores)


def cpu_package_temp(sysfs):
    """Temperatura do pacote da CPU, em Celsius com uma casa.

    Achada pelo rotulo 'Package id 0', nao pelo numero: temp1 costuma ser
    o pacote, mas a garantia esta no rotulo.
    """
    hwmon = hwmon_by_name(sysfs, "coretemp")
    if hwmon is None:
        return None
    for rotulo in sorted(hwmon.glob("temp*_label")):
        try:
            if rotulo.read_text().strip() != PACKAGE_LABEL:
                continue
            entrada = rotulo.with_name(rotulo.name.replace("_label", "_input"))
            return int(entrada.read_text().strip()) / 1000
        except (OSError, ValueError):
            continue
    return None
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_telemetry.py -q
```

Esperado: `12 passed`.

- [ ] **Step 5: Verificar contra o hardware de verdade**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -c "
import sys; sys.path.insert(0, 'src')
from nexus_sense.sysfs import Sysfs
from nexus_sense import telemetry as t
s = Sysfs('/')
print('ventoinhas:', t.fan_rpm(s))
print('temps acer:', t.acer_temperatures(s))
print('cpu pacote:', t.cpu_package_temp(s))
"
```

Esperado: duas rotações plausíveis (ordem de 1500-4000), três temperaturas e a do pacote. Compare com `cat /sys/devices/platform/acer-wmi/hwmon/hwmon*/fan1_input`.

- [ ] **Step 6: Registrar a armadilha 19**

Acrescente ao fim de `docs/ARMADILHAS.md`, seguindo o formato das 14
existentes. As de número 15 a 18 estão reservadas pela spec de melhorias
(§9), então a próxima livre é a 19.

```markdown
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
```

- [ ] **Step 7: Commit**

```bash
git add src/nexus_sense/telemetry.py tests/python/test_telemetry.py docs/ARMADILHAS.md
git commit -m "feat: leitura de sensores, nunca pelo indice do hwmon

O numero em /sys/class/hwmon/hwmonN muda entre boots conforme a ordem de
carga dos modulos. O acer se acha pelo dispositivo pai; os demais, pelo
conteudo de 'name'. A temperatura do pacote vem do rotulo
'Package id 0', nao de temp1.

Os testes deslocam o indice de proposito (0, 3, 11, 40) para provar que
o codigo nao depende dele.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Telemetria da GPU sem acordá-la

**Files:**
- Modify: `src/nexus_sense/telemetry.py` (acrescenta ao fim)
- Test: `tests/python/test_gpu.py`

**Interfaces:**
- Consumes: `Sysfs` da Task 1.
- Produces:
  - `nvidia_device(sysfs: Sysfs) -> str | None` — o BDF, ex.: `"0000:01:00.0"`
  - `gpu_asleep(sysfs: Sysfs, bdf: str) -> bool`
  - `GpuReading` — `NamedTuple` com `asleep: bool`, `temperature: float | None`, `utilization: int | None`
  - `read_gpu(sysfs: Sysfs, runner=subprocess.run) -> GpuReading | None`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_gpu.py`:

```python
import subprocess

import pytest

from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import gpu_asleep, nvidia_device, read_gpu

from conftest import build_tree


class RunnerEspiao:
    """Substitui subprocess.run e registra se foi chamado."""

    def __init__(self, stdout="42, 7 %\n"):
        self.chamadas = []
        self._stdout = stdout

    def __call__(self, args, **kwargs):
        self.chamadas.append(args)
        return subprocess.CompletedProcess(args, 0, stdout=self._stdout, stderr="")


def adormece(root, bdf="0000:01:00.0"):
    caminho = root / "sys/bus/pci/devices" / bdf / "power/runtime_status"
    caminho.write_text("suspended\n")


def test_acha_a_dgpu_pelo_vendor_e_pela_classe(fake_root):
    assert nvidia_device(Sysfs(fake_root)) == "0000:01:00.0"


def test_sem_dgpu_nvidia_devolve_none(tmp_path):
    build_tree(tmp_path)
    vendor = tmp_path / "sys/bus/pci/devices/0000:01:00.0/vendor"
    vendor.write_text("0x8086\n")
    assert nvidia_device(Sysfs(tmp_path)) is None


def test_reconhece_a_gpu_acordada(fake_root):
    assert gpu_asleep(Sysfs(fake_root), "0000:01:00.0") is False


def test_reconhece_a_gpu_adormecida(fake_root):
    adormece(fake_root)
    assert gpu_asleep(Sysfs(fake_root), "0000:01:00.0") is True


def test_com_a_gpu_dormindo_nao_chama_nvidia_smi(fake_root):
    """A regra central: o painel nunca pode ser o motivo de a GPU acordar.
    nvidia-smi custa 18 ms e acorda a dGPU. Ver spec secao 10.2."""
    adormece(fake_root)
    espiao = RunnerEspiao()
    leitura = read_gpu(Sysfs(fake_root), runner=espiao)
    assert espiao.chamadas == []
    assert leitura.asleep is True
    assert leitura.temperature is None
    assert leitura.utilization is None


def test_com_a_gpu_acordada_sonda_normalmente(fake_root):
    espiao = RunnerEspiao("42, 7 %\n")
    leitura = read_gpu(Sysfs(fake_root), runner=espiao)
    assert len(espiao.chamadas) == 1
    assert espiao.chamadas[0][0] == "nvidia-smi"
    assert leitura.asleep is False
    assert leitura.temperature == pytest.approx(42.0)
    assert leitura.utilization == 7


def test_nvidia_smi_ausente_nao_derruba_a_leitura(fake_root):
    def explode(args, **kwargs):
        raise FileNotFoundError("nvidia-smi")

    leitura = read_gpu(Sysfs(fake_root), runner=explode)
    assert leitura.asleep is False
    assert leitura.temperature is None


def test_saida_inesperada_do_nvidia_smi_nao_derruba(fake_root):
    espiao = RunnerEspiao("erro qualquer\n")
    leitura = read_gpu(Sysfs(fake_root), runner=espiao)
    assert leitura.temperature is None


def test_sem_gpu_a_leitura_e_none(tmp_path):
    assert read_gpu(Sysfs(tmp_path)) is None
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_gpu.py -q
```

Esperado: `ImportError: cannot import name 'gpu_asleep'`.

- [ ] **Step 3: Implementar**

Primeiro, no **topo** de `src/nexus_sense/telemetry.py`, logo abaixo da
docstring do módulo:

```python
import subprocess
from typing import NamedTuple
```

Depois, ao **fim** do mesmo arquivo:

```python
NVIDIA_VENDOR = "0x10de"
# 0x0300xx e VGA, 0x0302xx e "3D controller" -- as dGPUs de laptop
# aparecem numa das duas conforme o modo do Optimus.
GPU_CLASS_PREFIXES = ("0x0300", "0x0302")

NVIDIA_SMI_QUERY = "temperature.gpu,utilization.gpu"


class GpuReading(NamedTuple):
    """asleep=True significa que nao sondamos, nao que nao ha GPU."""

    asleep: bool
    temperature: float | None
    utilization: int | None


def nvidia_device(sysfs):
    """BDF da dGPU NVIDIA, ex. '0000:01:00.0'. None se nao houver."""
    base = sysfs.root / "sys/bus/pci/devices"
    if not base.is_dir():
        return None
    for filho in sorted(base.iterdir()):
        try:
            if sysfs.read(filho / "vendor") != NVIDIA_VENDOR:
                continue
            classe = sysfs.read(filho / "class")
        except OSError:
            continue
        if classe.startswith(GPU_CLASS_PREFIXES):
            return filho.name
    return None


def gpu_asleep(sysfs, bdf):
    """True quando a gerencia de energia ja suspendeu a GPU.

    Ler este arquivo custa praticamente nada e NAO acorda a GPU. E o
    contrario de nvidia-smi, que custa 18 ms e acorda.
    """
    caminho = sysfs.root / "sys/bus/pci/devices" / bdf / "power/runtime_status"
    try:
        return sysfs.read(caminho) == "suspended"
    except OSError:
        return False


def read_gpu(sysfs, runner=subprocess.run):
    """Le a GPU sem nunca acorda-la.

    A ordem importa e e a razao de ser desta funcao: primeiro o
    runtime_status, que e um arquivo; so se ele disser 'active' e que o
    nvidia-smi entra. Um laco de 2 s sondando sem essa guarda manteria a
    dGPU acesa permanentemente, gastando bateria para exibir um numero.
    Ver spec secao 10.2.
    """
    bdf = nvidia_device(sysfs)
    if bdf is None:
        return None

    if gpu_asleep(sysfs, bdf):
        return GpuReading(asleep=True, temperature=None, utilization=None)

    try:
        saida = runner(
            ["nvidia-smi", f"--query-gpu={NVIDIA_SMI_QUERY}", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return GpuReading(asleep=False, temperature=None, utilization=None)

    try:
        bruto_temp, bruto_uso = saida.stdout.split(",")
        temperatura = float(bruto_temp.strip())
        utilizacao = int(bruto_uso.strip().rstrip(" %"))
    except (AttributeError, ValueError):
        return GpuReading(asleep=False, temperature=None, utilization=None)

    return GpuReading(asleep=False, temperature=temperatura, utilization=utilizacao)
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_gpu.py -q
```

Esperado: `9 passed`.

- [ ] **Step 5: Registrar a armadilha 20**

Acrescente ao fim de `docs/ARMADILHAS.md`:

```markdown
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
```

- [ ] **Step 6: Commit**

```bash
git add src/nexus_sense/telemetry.py tests/python/test_gpu.py docs/ARMADILHAS.md
git commit -m "feat: telemetria da GPU sem acorda-la

nvidia-smi custa 18 ms e acorda a dGPU adormecida; ler runtime_status
custa nada e nao acorda. read_gpu le o status primeiro e so entao decide
se sonda. O teste com o runner espiao prova que, com a GPU dormindo,
nvidia-smi nao e chamado nenhuma vez.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Configuração em TOML

**Files:**
- Create: `src/nexus_sense/config.py`
- Test: `tests/python/test_config.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `Config` — dataclass com `auto_switch: bool = False`, `battery_profile: str = "balanced"`, `saved_ac_profile: str | None = None`
  - `default_path() -> Path` — `~/.config/nexus-sense/config.toml`
  - `load(path: Path) -> Config` — devolve padrões se o arquivo não existir ou estiver corrompido
  - `save(config: Config, path: Path) -> None` — cria o diretório

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_config.py`:

```python
from nexus_sense.config import Config, default_path, load, save


def test_o_padrao_nao_liga_a_troca_automatica():
    """Enquanto o damx-daemon ainda estiver no ar, os dois disputariam o
    perfil. O plano 2 liga isto na virada."""
    padrao = Config()
    assert padrao.auto_switch is False
    assert padrao.battery_profile == "balanced"
    assert padrao.saved_ac_profile is None


def test_arquivo_ausente_devolve_os_padroes(tmp_path):
    assert load(tmp_path / "nao-existe.toml") == Config()


def test_grava_e_le_de_volta(tmp_path):
    alvo = tmp_path / "sub/config.toml"
    original = Config(
        auto_switch=True, battery_profile="low-power", saved_ac_profile="balanced-performance"
    )
    save(original, alvo)
    assert alvo.is_file()
    assert load(alvo) == original


def test_cria_o_diretorio_que_faltar(tmp_path):
    alvo = tmp_path / "a/b/c/config.toml"
    save(Config(), alvo)
    assert alvo.is_file()


def test_none_sobrevive_a_ida_e_volta(tmp_path):
    alvo = tmp_path / "config.toml"
    save(Config(saved_ac_profile=None), alvo)
    assert load(alvo).saved_ac_profile is None


def test_arquivo_corrompido_nao_derruba_o_agente(tmp_path):
    alvo = tmp_path / "config.toml"
    alvo.write_text("isto nao e toml [[[")
    assert load(alvo) == Config()


def test_chave_desconhecida_e_ignorada(tmp_path):
    alvo = tmp_path / "config.toml"
    alvo.write_text('auto_switch = true\ninventada = "x"\n')
    assert load(alvo).auto_switch is True


def test_tipo_errado_cai_para_o_padrao(tmp_path):
    alvo = tmp_path / "config.toml"
    alvo.write_text('auto_switch = "sim"\nbattery_profile = 7\n')
    resultado = load(alvo)
    assert resultado.auto_switch is False
    assert resultado.battery_profile == "balanced"


def test_o_caminho_padrao_fica_sob_config(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    assert default_path() == tmp_path / "nexus-sense/config.toml"
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_config.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.config'`.

- [ ] **Step 3: Implementar**

`src/nexus_sense/config.py`:

```python
"""Preferencias do usuario.

O sysfs guarda o estado; este arquivo guarda a intencao -- o que o
kernel nao tem como saber. Ver spec secao 4.1.

Nenhuma leitura daqui pode derrubar o agente: arquivo ausente,
corrompido ou com tipos errados cai para o padrao e segue.
"""

import os
import tomllib
from dataclasses import asdict, dataclass, fields
from pathlib import Path

import tomli_w


@dataclass(frozen=True)
class Config:
    # Fica desligado ate o plano 2 fazer a virada: com o damx-daemon
    # ainda no ar, os dois disputariam o perfil termico.
    auto_switch: bool = False

    # 'balanced' e 'low-power' sao os unicos que o driver aceita na
    # bateria. Ver spec secao 2.8.
    battery_profile: str = "balanced"

    # Em que perfil estava na tomada, para devolver ao religar. O daemon
    # antigo derrubava e nunca restaurava.
    saved_ac_profile: str | None = None


def default_path():
    base = os.environ.get("XDG_CONFIG_HOME")
    raiz = Path(base) if base else Path.home() / ".config"
    return raiz / "nexus-sense/config.toml"


def load(path):
    """Le a configuracao. Qualquer problema devolve os padroes."""
    try:
        with open(path, "rb") as arquivo:
            bruto = tomllib.load(arquivo)
    except (OSError, tomllib.TOMLDecodeError):
        return Config()

    padrao = Config()
    aceitos = {}
    for campo in fields(Config):
        if campo.name not in bruto:
            continue
        valor = bruto[campo.name]
        atual = getattr(padrao, campo.name)
        esperado = type(atual) if atual is not None else str
        if isinstance(valor, esperado) and not (
            esperado is int and isinstance(valor, bool)
        ):
            aceitos[campo.name] = valor

    return Config(**aceitos)


def save(config, path):
    """Grava a configuracao, criando o diretorio se faltar."""
    caminho = Path(path)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    # tomli_w nao serializa None; a ausencia da chave e o proprio None.
    dados = {k: v for k, v in asdict(config).items() if v is not None}
    with open(caminho, "wb") as arquivo:
        tomli_w.dump(dados, arquivo)
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_config.py -q
```

Esperado: `9 passed`.

- [ ] **Step 5: Commit**

```bash
git add src/nexus_sense/config.py tests/python/test_config.py
git commit -m "feat: configuracao em TOML, com padroes a prova de arquivo corrompido

O sysfs guarda o estado; este arquivo guarda a intencao. auto_switch
nasce desligado para nao disputar o perfil com o damx-daemon, que so sai
no plano 2.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: A decisão do agente

**Files:**
- Create: `src/nexus_sense/agent.py`
- Test: `tests/python/test_agent_decision.py`

**Interfaces:**
- Consumes: `Config` da Task 6; `available`, `nearest` da Task 2.
- Produces:
  - `Decision` — `NamedTuple` com `profile: str | None`, `config: Config`, `reason: str`
  - `decide(current_profile, was_on_ac, now_on_ac, config, choices) -> Decision`
    - `profile` é `None` quando nada deve ser escrito
    - `reason` é uma frase em pt-BR para o log

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_agent_decision.py`:

```python
from nexus_sense.agent import decide
from nexus_sense.config import Config

QUATRO = ["low-power", "quiet", "balanced", "balanced-performance"]
LIGADO = Config(auto_switch=True)


def test_sem_troca_de_fonte_nao_faz_nada():
    d = decide("balanced", was_on_ac=True, now_on_ac=True, config=LIGADO, choices=QUATRO)
    assert d.profile is None


def test_com_a_troca_desligada_nao_faz_nada():
    d = decide(
        "balanced-performance",
        was_on_ac=True,
        now_on_ac=False,
        config=Config(auto_switch=False),
        choices=QUATRO,
    )
    assert d.profile is None


def test_ao_desconectar_guarda_o_perfil_e_desce():
    d = decide(
        "balanced-performance",
        was_on_ac=True,
        now_on_ac=False,
        config=LIGADO,
        choices=QUATRO,
    )
    assert d.profile == "balanced"
    assert d.config.saved_ac_profile == "balanced-performance"


def test_ao_desconectar_respeita_o_perfil_de_bateria_escolhido():
    d = decide(
        "balanced-performance",
        was_on_ac=True,
        now_on_ac=False,
        config=Config(auto_switch=True, battery_profile="low-power"),
        choices=QUATRO,
    )
    assert d.profile == "low-power"


def test_perfil_de_bateria_invalido_recua_para_o_mais_proximo():
    """O usuario pediu 'quiet' na bateria, que o driver recusa. Em vez de
    tentar e falhar, o agente recua e diz por que."""
    d = decide(
        "balanced-performance",
        was_on_ac=True,
        now_on_ac=False,
        config=Config(auto_switch=True, battery_profile="quiet"),
        choices=QUATRO,
    )
    assert d.profile == "balanced"
    assert "quiet" in d.reason


def test_ao_desconectar_de_um_perfil_ja_permitido_nao_escreve():
    d = decide("low-power", was_on_ac=True, now_on_ac=False, config=LIGADO, choices=QUATRO)
    assert d.profile is None
    assert d.config.saved_ac_profile is None


def test_ao_religar_devolve_o_perfil_guardado():
    """O defeito do daemon antigo: ele derruba e nunca restaura."""
    guardado = Config(auto_switch=True, saved_ac_profile="balanced-performance")
    d = decide("balanced", was_on_ac=False, now_on_ac=True, config=guardado, choices=QUATRO)
    assert d.profile == "balanced-performance"
    assert d.config.saved_ac_profile is None


def test_ao_religar_sem_nada_guardado_nao_faz_nada():
    d = decide("balanced", was_on_ac=False, now_on_ac=True, config=LIGADO, choices=QUATRO)
    assert d.profile is None


def test_ao_religar_o_guardado_some_mesmo_se_o_firmware_mudou():
    guardado = Config(auto_switch=True, saved_ac_profile="performance")
    d = decide("balanced", was_on_ac=False, now_on_ac=True, config=guardado, choices=QUATRO)
    assert d.profile is None
    assert d.config.saved_ac_profile is None


def test_primeira_leitura_nao_dispara_nada():
    """was_on_ac=None e o estado de partida: ainda nao houve troca."""
    d = decide(
        "balanced-performance",
        was_on_ac=None,
        now_on_ac=False,
        config=LIGADO,
        choices=QUATRO,
    )
    assert d.profile is None


def test_a_razao_e_sempre_uma_frase_em_portugues():
    d = decide(
        "balanced-performance", was_on_ac=True, now_on_ac=False, config=LIGADO, choices=QUATRO
    )
    assert isinstance(d.reason, str) and d.reason
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_agent_decision.py -q
```

Esperado: `ModuleNotFoundError: No module named 'nexus_sense.agent'`.

- [ ] **Step 3: Implementar**

`src/nexus_sense/agent.py`:

```python
"""Correcao do perfil termico na troca de fonte de energia.

Por que isto existe: o driver recusa quiet, balanced-performance e
performance na bateria, mas NAO derruba um perfil ja ativo -- ele nao
tem notificador de fonte de energia nenhum. Sem alguem corrigindo, a
maquina fica em balanced-performance na bateria por tempo indefinido,
num estado que ela recusaria assumir se pedido. Ver spec secao 2.9.

`decide` e pura de proposito: recebe o estado, devolve o que escrever.
Todo o comportamento do agente e testavel sem hardware e sem relogio.
"""

import dataclasses
from typing import NamedTuple

from .config import Config
from .model import available, nearest


class Decision(NamedTuple):
    profile: str | None  # None significa "nao escreva nada"
    config: Config  # possivelmente atualizado em relacao ao recebido
    reason: str


def decide(current_profile, was_on_ac, now_on_ac, config, choices):
    """O que fazer quando a fonte de energia acabou de ser lida.

    `was_on_ac` e None na primeira leitura: nao houve troca ainda, entao
    nada dispara.
    """
    if was_on_ac is None or was_on_ac == now_on_ac:
        return Decision(None, config, "sem troca de fonte")

    if not config.auto_switch:
        return Decision(None, config, "troca automatica desligada")

    if not now_on_ac:
        return _on_unplug(current_profile, config, choices)
    return _on_plug(config, choices)


def _on_unplug(current_profile, config, choices):
    permitidos = available(choices, on_ac=False)
    if not permitidos:
        return Decision(None, config, "nenhum perfil permitido na bateria")

    if current_profile in permitidos:
        return Decision(None, config, "o perfil corrente ja e permitido na bateria")

    desejado = config.battery_profile
    if desejado in permitidos:
        alvo = desejado
        razao = f"na bateria: {current_profile} nao e permitido, indo para {alvo}"
    else:
        # Recua para o padrao, nao para o vizinho mais proximo. Se o
        # usuario pediu 'quiet' -- que o driver recusa na bateria --, o
        # vizinho mais proximo seria 'low-power', bem mais agressivo na
        # economia do que ele pediu. O padrao e a escolha menos
        # surpreendente. Ver spec secao 8.
        padrao = Config().battery_profile
        alvo = padrao if padrao in permitidos else nearest(desejado, permitidos)
        razao = (
            f"o perfil de bateria escolhido ({desejado}) e recusado pelo driver; "
            f"usando {alvo}"
        )

    novo = dataclasses.replace(config, saved_ac_profile=current_profile)
    return Decision(alvo, novo, razao)


def _on_plug(config, choices):
    guardado = config.saved_ac_profile
    limpo = dataclasses.replace(config, saved_ac_profile=None)

    if guardado is None:
        return Decision(None, config, "nada guardado para devolver")

    if guardado not in available(choices, on_ac=True):
        return Decision(
            None, limpo, f"o perfil guardado ({guardado}) nao esta mais disponivel"
        )

    return Decision(guardado, limpo, f"de volta na tomada: devolvendo {guardado}")
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_agent_decision.py -q
```

Esperado: `11 passed`.

- [ ] **Step 5: Commit**

```bash
git add src/nexus_sense/agent.py tests/python/test_agent_decision.py
git commit -m "feat: a decisao do agente na troca de fonte de energia

Pura de proposito: recebe estado, devolve o que escrever. Todo o
comportamento e testavel sem hardware e sem relogio.

Corrige de passagem o defeito do daemon antigo, que derruba o perfil ao
desconectar e nunca o devolve ao religar.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: O laço do agente, o executável e a unit

**Files:**
- Modify: `src/nexus_sense/agent.py` (acrescenta a classe `Agent`)
- Create: `src/nexus_sense/__main__.py`
- Create: `packaging/nexus-sense-agent.service`
- Test: `tests/python/test_agent_loop.py`

**Interfaces:**
- Consumes: `Sysfs` (Task 1), `Config`/`load`/`save` (Task 6), `decide` (Task 7).
- Produces:
  - `Agent(sysfs, config_path, interval=2.0, logger=None)`
  - `Agent.tick() -> Decision` — uma passada; lê a fonte, decide, escreve se preciso
  - `Agent.run(stop_event=None) -> None` — o laço
  - `main(argv=None) -> int` em `__main__.py`

- [ ] **Step 1: Escrever os testes que falham**

`tests/python/test_agent_loop.py`:

```python
import logging
import os

import pytest

from nexus_sense.agent import Agent
from nexus_sense.config import Config, load, save
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


def liga(tmp_path):
    caminho = tmp_path / "config.toml"
    save(Config(auto_switch=True), caminho)
    return caminho


def desconecta(root):
    (root / "sys/class/power_supply/ACAD/online").write_text("0\n")


def conecta(root):
    (root / "sys/class/power_supply/ACAD/online").write_text("1\n")


def perfil(root):
    caminho = root / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    return caminho.read_text().strip()


def test_a_primeira_passada_so_observa(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))
    agente.tick()
    assert perfil(raiz) == "balanced-performance"


def test_desconectar_derruba_o_perfil_no_sysfs(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))
    agente.tick()
    desconecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced"


def test_religar_devolve_o_perfil(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    agente = Agent(Sysfs(raiz), caminho)
    agente.tick()
    desconecta(raiz)
    agente.tick()
    conecta(raiz)
    agente.tick()
    assert perfil(raiz) == "balanced-performance"


def test_o_perfil_guardado_persiste_no_arquivo(tmp_path):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    agente = Agent(Sysfs(raiz), caminho)
    agente.tick()
    desconecta(raiz)
    agente.tick()
    assert load(caminho).saved_ac_profile == "balanced-performance"


def test_um_agente_novo_retoma_do_arquivo(tmp_path):
    """Se o agente for reiniciado enquanto voce esta na bateria, o
    perfil guardado tem de sobreviver."""
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    caminho = liga(tmp_path)
    primeiro = Agent(Sysfs(raiz), caminho)
    primeiro.tick()
    desconecta(raiz)
    primeiro.tick()

    segundo = Agent(Sysfs(raiz), caminho)
    segundo.tick()
    conecta(raiz)
    segundo.tick()
    assert perfil(raiz) == "balanced-performance"


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignora a permissão do arquivo")
def test_escrita_recusada_pelo_driver_nao_derruba_o_agente(tmp_path, caplog):
    raiz = build_tree(tmp_path / "raiz", profile="balanced-performance")
    agente = Agent(Sysfs(raiz), liga(tmp_path))
    agente.tick()
    desconecta(raiz)

    alvo = raiz / "sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile"
    alvo.chmod(0o444)
    try:
        with caplog.at_level(logging.WARNING):
            agente.tick()
    finally:
        alvo.chmod(0o644)
    assert "não foi possível" in caplog.text.lower() or "nao foi possivel" in caplog.text.lower()


def test_sem_driver_o_agente_nao_explode(tmp_path):
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    agente = Agent(Sysfs(vazia), liga(tmp_path))
    assert agente.tick().profile is None


def test_run_para_quando_o_evento_e_sinalizado(tmp_path):
    import threading

    raiz = build_tree(tmp_path / "raiz")
    agente = Agent(Sysfs(raiz), liga(tmp_path), interval=0.01)
    parar = threading.Event()
    fio = threading.Thread(target=agente.run, args=(parar,))
    fio.start()
    parar.set()
    fio.join(timeout=2)
    assert not fio.is_alive()
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_agent_loop.py -q
```

Esperado: `ImportError: cannot import name 'Agent'`.

- [ ] **Step 3: Implementar o laço**

Primeiro, no **topo** de `src/nexus_sense/agent.py`, junto dos imports que
já estão lá:

```python
import logging
import threading

from .config import Config, load, save
```

(o `Config` já foi importado na Task 7; acrescente `load` e `save` à mesma
linha.)

Depois, ao **fim** do mesmo arquivo:

```python
LOG = logging.getLogger("nexus-sense-agent")

# Sondagem simples: um arquivo de 4 bytes, modo 444. As alternativas --
# netlink do udev, UPower via DBus -- sao mais elegantes e mais frageis,
# e trariam dependencia. Ver spec secao 4.2.
DEFAULT_INTERVAL = 2.0


class Agent:
    """Vigia a fonte de energia e corrige o perfil termico."""

    def __init__(self, sysfs, config_path, interval=DEFAULT_INTERVAL, logger=None):
        self.sysfs = sysfs
        self.config_path = config_path
        self.interval = interval
        self.log = logger or LOG
        self._was_on_ac = None

    def _read_choices(self):
        caminho = self.sysfs.choices_path()
        if caminho is None:
            return []
        try:
            return self.sysfs.read(caminho).split()
        except OSError:
            return []

    def _read_profile(self):
        caminho = self.sysfs.profile_path()
        if caminho is None:
            return None
        try:
            return self.sysfs.read(caminho)
        except OSError:
            return None

    def tick(self):
        """Uma passada: le a fonte, decide, escreve se preciso."""
        now_on_ac = self.sysfs.on_ac()
        perfil = self._read_profile()

        if now_on_ac is None or perfil is None:
            return Decision(None, load(self.config_path), "driver ou fonte ausente")

        # Recarregado a cada passada de proposito: a GUI escreve neste
        # arquivo, e o agente nao tem outro jeito de saber.
        config = load(self.config_path)

        decisao = decide(
            perfil,
            was_on_ac=self._was_on_ac,
            now_on_ac=now_on_ac,
            config=config,
            choices=self._read_choices(),
        )
        self._was_on_ac = now_on_ac

        if decisao.config != config:
            try:
                save(decisao.config, self.config_path)
            except OSError as erro:
                self.log.warning("não foi possível gravar a configuração: %s", erro)

        if decisao.profile is not None:
            try:
                self.sysfs.write(self.sysfs.profile_path(), decisao.profile)
                self.log.info("perfil -> %s (%s)", decisao.profile, decisao.reason)
            except OSError as erro:
                # Acontece de verdade: sem a regra udev aplicada, ou numa
                # corrida em que o cabo volta entre a decisao e a escrita.
                self.log.warning(
                    "não foi possível escrever o perfil %s: %s", decisao.profile, erro
                )

        return decisao

    def run(self, stop_event=None):
        """O laco. Para quando `stop_event` for sinalizado."""
        parar = stop_event or threading.Event()
        self.log.info("agente no ar, sondando a cada %.1f s", self.interval)
        while not parar.is_set():
            try:
                self.tick()
            except Exception:  # nunca deixar o laco morrer por um tick ruim
                self.log.exception("falha inesperada numa passada")
            parar.wait(self.interval)
        self.log.info("agente encerrado")
```

- [ ] **Step 4: Escrever o ponto de entrada**

`src/nexus_sense/__main__.py`:

```python
"""Executavel do agente: nexus-sense-agent."""

import argparse
import logging
import signal
import threading

from . import __version__
from .agent import DEFAULT_INTERVAL, Agent
from .config import default_path
from .sysfs import Sysfs


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="nexus-sense-agent",
        description="Corrige o perfil térmico na troca de fonte de energia.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--root", default="/", help="raiz alternativa do sysfs")
    parser.add_argument("--config", default=None, help="caminho do config.toml")
    parser.add_argument(
        "--interval", type=float, default=DEFAULT_INTERVAL, help="segundos entre leituras"
    )
    parser.add_argument("--once", action="store_true", help="uma passada e sai")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )

    sysfs = Sysfs(args.root)
    if not sysfs.module_loaded():
        logging.error("o módulo do driver não está carregado; nada a fazer")
        return 1

    agente = Agent(sysfs, args.config or default_path(), interval=args.interval)

    if args.once:
        agente.tick()
        return 0

    parar = threading.Event()
    for sinal in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sinal, lambda *_: parar.set())
    agente.run(parar)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Escrever a unit de usuário**

`packaging/nexus-sense-agent.service`:

```ini
[Unit]
Description=Nexus Sense — correção de perfil na troca de fonte de energia
Documentation=file:/usr/share/doc/nexus-sense/README.md
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/nexus-sense-agent
Restart=always
RestartSec=3
# Não precisa de privilégio: escreve pelo grupo nexus_sense, aplicado
# pela regra udev 60-nexus-sense.rules.
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 6: Rodar e confirmar que passa**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest tests/python/test_agent_loop.py -q
```

Esperado: `8 passed`.

- [ ] **Step 7: Verificar o executável contra o hardware, sem alterar nada**

O `--once` com a troca desligada por padrão apenas observa:

```bash
cd /home/brunodobner/Claude/Nitrosense && PYTHONPATH=src python3 -m nexus_sense --once -v
```

Esperado: `agente no ar` não aparece (é o modo `--once`), nenhum erro, e o perfil em `/sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile` **inalterado**. Confirme:

```bash
cat /sys/devices/platform/acer-wmi/platform-profile/platform-profile-0/profile
```

- [ ] **Step 8: Rodar a suíte inteira**

```bash
cd /home/brunodobner/Claude/Nitrosense && python3 -m pytest -q
```

Esperado: `91 passed`.

- [ ] **Step 9: Commit**

```bash
git add src/nexus_sense/agent.py src/nexus_sense/__main__.py packaging/ tests/python/test_agent_loop.py
git commit -m "feat: laco do agente, executavel e unit de usuario

A unit e de usuario, nao de sistema: o agente escreve pelo grupo, nao
por privilegio. Restart=always cobre queda; a configuracao e relida a
cada passada, porque a GUI escreve nela.

Uma escrita recusada nao derruba o laco -- acontece de verdade, numa
corrida em que o cabo volta entre a decisao e a escrita.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Regra udev, grupo e teste de permissões no hardware

**Files:**
- Create: `packaging/60-nexus-sense.rules`
- Create: `tests/test-permissoes.sh`

**Interfaces:**
- Consumes: nada do Python.
- Produces: a regra udev instalável e um teste que entra na suíte shell existente.

- [ ] **Step 1: Escrever a regra udev**

`packaging/60-nexus-sense.rules`:

```
# Nexus Sense -- permissao de escrita para o grupo nexus_sense.
#
# Por que existe: os atributos que a interface precisa escrever nascem
# root:root 644. Dar o grupo a eles dispensa o daemon root que o upstream
# usava, e estreita o acesso -- o socket do daemon era modo 666, aceitando
# comando de qualquer processo da maquina. Ver spec secao 5.
#
# Exatamente seis atributos. 'version' fica de fora, e permanece 444.
#
# udev nao altera permissao de atributo sysfs por ATTR{}; e preciso RUN.
# O caminho vem de $sys/$devpath para nao supor a montagem em /sys.

ACTION=="add|change", SUBSYSTEM=="platform", KERNEL=="acer-wmi", \
  RUN+="/usr/lib/nexus-sense/apply-perms.sh"

ACTION=="add|change", SUBSYSTEM=="platform-profile", KERNEL=="platform-profile-*", \
  RUN+="/usr/lib/nexus-sense/apply-perms.sh"
```

- [ ] **Step 2: Escrever o script que a regra chama**

`packaging/apply-perms.sh`:

```bash
#!/bin/sh
# Aplica grupo e permissao nos seis atributos graveis do Nexus Sense.
#
# Chamado pela regra udev 60-nexus-sense.rules. Roda cedo, quando o
# dispositivo aparece; um atributo que ainda nao exista e simplesmente
# pulado, e a regra dispara de novo no 'change' seguinte.
#
# Silencioso de proposito: udev nao e lugar de imprimir.
set -u

GRUPO=nexus_sense
BASE=/sys/devices/platform/acer-wmi

getent group "$GRUPO" >/dev/null 2>&1 || exit 0

for alvo in \
    "$BASE"/nitro_sense/fan_speed \
    "$BASE"/nitro_sense/battery_limiter \
    "$BASE"/nitro_sense/usb_charging \
    "$BASE"/nitro_sense/backlight_timeout \
    "$BASE"/nitro_sense/battery_calibration \
    "$BASE"/predator_sense/fan_speed \
    "$BASE"/predator_sense/battery_limiter \
    "$BASE"/predator_sense/usb_charging \
    "$BASE"/predator_sense/backlight_timeout \
    "$BASE"/predator_sense/battery_calibration \
    "$BASE"/platform-profile/platform-profile-*/profile
do
    [ -f "$alvo" ] || continue
    chgrp "$GRUPO" "$alvo" 2>/dev/null && chmod g+w "$alvo" 2>/dev/null
done

exit 0
```

- [ ] **Step 3: Escrever o teste de hardware**

`tests/test-permissoes.sh`:

```bash
#!/bin/bash
# Verifica que os seis atributos graveis estao com grupo e permissao, e
# que a escrita como usuario comum passa -- que e o resultado que
# dispensa o daemon root. Ver spec secao 2.7.
#
# Saidas, conforme o contrato do run-all.sh:
#   0 passou   2 pulou (sem driver ou fora do grupo)   3 alvo ausente
set -u

BASE=/sys/devices/platform/acer-wmi
GRUPO=nexus_sense

falhas=0

# Sem driver carregado nao ha o que testar.
[ -d "$BASE" ] || { echo "PULOU: acer-wmi ausente"; exit 2; }

SENSE=""
for nome in nitro_sense predator_sense; do
    [ -d "$BASE/$nome" ] && SENSE="$BASE/$nome"
done
[ -n "$SENSE" ] || { echo "ERRO: nem nitro_sense nem predator_sense"; exit 3; }

PROFILE=$(echo "$BASE"/platform-profile/platform-profile-*/profile)
[ -f "$PROFILE" ] || { echo "ERRO: profile ausente"; exit 3; }

# O grupo tem de existir e o usuario tem de estar nele. Se nao estiver,
# o teste pula em vez de falhar: quem acabou de entrar no grupo precisa
# relogar, e isso nao e defeito do codigo.
getent group "$GRUPO" >/dev/null || { echo "PULOU: grupo $GRUPO nao existe"; exit 2; }
id -nG | tr ' ' '\n' | grep -qx "$GRUPO" || {
    echo "PULOU: sessao fora do grupo $GRUPO (relogar?)"; exit 2; }

ALVOS="$SENSE/fan_speed $SENSE/battery_limiter $SENSE/usb_charging \
       $SENSE/backlight_timeout $SENSE/battery_calibration $PROFILE"

for alvo in $ALVOS; do
    [ -f "$alvo" ] || { echo "FALHA: ausente: $alvo"; falhas=$((falhas + 1)); continue; }
    dono=$(stat -c '%G' "$alvo")
    modo=$(stat -c '%a' "$alvo")
    [ "$dono" = "$GRUPO" ] || { echo "FALHA: grupo $dono em $alvo"; falhas=$((falhas + 1)); }
    [ "$modo" = "664" ]    || { echo "FALHA: modo $modo em $alvo"; falhas=$((falhas + 1)); }
done

# version tem de continuar somente-leitura.
if [ -f "$SENSE/version" ]; then
    modo=$(stat -c '%a' "$SENSE/version")
    [ "$modo" = "444" ] || { echo "FALHA: version com modo $modo, esperado 444"; falhas=$((falhas + 1)); }
fi

# A escrita de verdade, como usuario comum. backlight_timeout e o mais
# inocuo dos seis; restaura o valor original em seguida.
alvo="$SENSE/backlight_timeout"
if [ -w "$alvo" ]; then
    antes=$(cat "$alvo")
    outro=$([ "$antes" = "1" ] && echo 0 || echo 1)
    if echo "$outro" > "$alvo" 2>/dev/null; then
        agora=$(cat "$alvo")
        [ "$agora" = "$outro" ] || { echo "FALHA: escreveu $outro, leu $agora"; falhas=$((falhas + 1)); }
        echo "$antes" > "$alvo" 2>/dev/null
    else
        echo "FALHA: escrita como usuario comum recusada em $alvo"
        falhas=$((falhas + 1))
    fi
else
    echo "FALHA: $alvo nao esta gravavel"
    falhas=$((falhas + 1))
fi

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: seis atributos com grupo $GRUPO, escrita sem root confirmada"
exit 0
```

- [ ] **Step 4: Tornar os scripts executáveis e rodar o teste**

```bash
cd /home/brunodobner/Claude/Nitrosense
chmod +x tests/test-permissoes.sh packaging/apply-perms.sh
./tests/test-permissoes.sh; echo "saida=$?"
```

Esperado nesta máquina, **antes** de instalar a regra: `PULOU: grupo nexus_sense nao existe`, saída `2`. Isso é o resultado correto — o teste pula, não falha.

- [ ] **Step 5: Instalar o grupo e a regra, e rodar de novo**

> **Se você é um agente:** `groupadd` e `usermod` alteram contas do
> sistema, e o classificador do harness já bloqueou exatamente estes dois
> comandos nesta sessão. Se for bloqueado, **não contorne** — mostre as
> duas linhas ao usuário para que ele as rode, e siga a partir do
> `install`. Os demais comandos deste passo não têm esse problema.

```bash
export SUDO_ASKPASS=~/.local/bin/claude-askpass
cd /home/brunodobner/Claude/Nitrosense
sudo -A groupadd -r nexus_sense
sudo -A usermod -aG nexus_sense "$USER"
sudo -A install -d /usr/lib/nexus-sense
sudo -A install -m 755 packaging/apply-perms.sh /usr/lib/nexus-sense/apply-perms.sh
sudo -A install -m 644 packaging/60-nexus-sense.rules /etc/udev/rules.d/60-nexus-sense.rules
sudo -A udevadm control --reload
sudo -A udevadm trigger --subsystem-match=platform --action=change
sudo -A udevadm trigger --subsystem-match=platform-profile --action=change
stat -c '%a %U:%G %n' /sys/devices/platform/acer-wmi/nitro_sense/* \
                      /sys/devices/platform/acer-wmi/platform-profile/*/profile
```

Esperado: os cinco de `nitro_sense` mais o `profile` em `664 root:nexus_sense`, e `version` em `444 root:root`.

Como a sessão atual ainda não tem o grupo novo, rode o teste dentro dele:

```bash
sg nexus_sense -c './tests/test-permissoes.sh'; echo "saida=$?"
```

Esperado: `OK: seis atributos com grupo nexus_sense, escrita sem root confirmada`, saída `0`.

- [ ] **Step 6: Confirmar que a suíte shell inteira continua verde**

```bash
cd /home/brunodobner/Claude/Nitrosense && ./tests/run-all.sh
```

Esperado: os 9 anteriores no mesmo estado de antes, mais `test-permissoes.sh`. O novo aparece como `PULOU` fora do `sg`, o que é correto.

- [ ] **Step 7: Commit**

```bash
git add packaging/60-nexus-sense.rules packaging/apply-perms.sh tests/test-permissoes.sh
git commit -m "feat: regra udev do grupo nexus_sense e teste de permissoes

Seis atributos em root:nexus_sense 664; version continua 444. udev nao
altera permissao de atributo sysfs por ATTR{}, entao a regra chama um
script.

O teste pula, em vez de falhar, quando o grupo nao existe ou a sessao
esta fora dele -- quem acabou de entrar no grupo precisa relogar, e isso
nao e defeito do codigo.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Teste de hardware da recusa na bateria

**Files:**
- Create: `tests/test-perfil-bateria.sh`

**Interfaces:**
- Consumes: nada.
- Produces: um teste que verifica no hardware o que a Task 2 assume no modelo.

- [ ] **Step 1: Escrever o teste**

`tests/test-perfil-bateria.sh`:

```bash
#!/bin/bash
# Verifica no hardware o que o modelo assume: na bateria o driver recusa
# quiet, balanced-performance e performance, e aceita balanced e
# low-power. Ver spec secao 2.8 e linuwu_sense.c:2317.
#
# Este teste PULA quando a maquina esta na tomada -- nao ha como
# verificar a recusa com o cabo ligado, e desligar o cabo nao e coisa que
# um teste faca.
#
# Saidas: 0 passou   2 pulou   3 alvo ausente
set -u

BASE=/sys/devices/platform/acer-wmi
PROFILE=$(echo "$BASE"/platform-profile/platform-profile-*/profile)
CHOICES=$(echo "$BASE"/platform-profile/platform-profile-*/choices)

[ -f "$PROFILE" ] || { echo "ERRO: profile ausente"; exit 3; }
[ -f "$CHOICES" ] || { echo "ERRO: choices ausente"; exit 3; }

AC=""
for nome in AC ACAD ADP1 AC0; do
    [ -f "/sys/class/power_supply/$nome/online" ] && AC="/sys/class/power_supply/$nome/online"
done
[ -n "$AC" ] || { echo "PULOU: nenhuma fonte de energia encontrada"; exit 2; }

[ "$(cat "$AC")" = "0" ] || { echo "PULOU: na tomada; este teste so roda na bateria"; exit 2; }
[ -w "$PROFILE" ] || { echo "PULOU: sem permissao de escrita no profile"; exit 2; }

anunciados=$(cat "$CHOICES")
original=$(cat "$PROFILE")
falhas=0

restaura() { echo "$original" > "$PROFILE" 2>/dev/null; }
trap restaura EXIT

# Os que o driver tem de recusar na bateria.
for perfil in quiet balanced-performance performance; do
    case " $anunciados " in *" $perfil "*) ;; *) continue ;; esac
    if echo "$perfil" > "$PROFILE" 2>/dev/null; then
        echo "FALHA: $perfil foi ACEITO na bateria; esperado -EOPNOTSUPP"
        falhas=$((falhas + 1))
        restaura
    fi
done

# Os que o driver tem de aceitar.
for perfil in low-power balanced; do
    case " $anunciados " in *" $perfil "*) ;; *) continue ;; esac
    if echo "$perfil" > "$PROFILE" 2>/dev/null; then
        agora=$(cat "$PROFILE")
        [ "$agora" = "$perfil" ] || {
            echo "FALHA: escreveu $perfil, leu $agora"; falhas=$((falhas + 1)); }
    else
        echo "FALHA: $perfil foi RECUSADO na bateria; esperado aceitar"
        falhas=$((falhas + 1))
    fi
done

[ "$falhas" -eq 0 ] || { echo "FALHA: $falhas problema(s)"; exit 1; }
echo "OK: na bateria o driver recusa quiet e balanced-performance, aceita balanced e low-power"
exit 0
```

- [ ] **Step 2: Rodar na tomada e confirmar que pula**

```bash
cd /home/brunodobner/Claude/Nitrosense
chmod +x tests/test-perfil-bateria.sh
./tests/test-perfil-bateria.sh; echo "saida=$?"
```

Esperado com o cabo ligado: `PULOU: na tomada; este teste so roda na bateria`, saída `2`.

- [ ] **Step 3: Rodar na bateria e confirmar que passa**

Peça ao usuário para desconectar o cabo, e então:

```bash
cd /home/brunodobner/Claude/Nitrosense
sg nexus_sense -c './tests/test-perfil-bateria.sh'; echo "saida=$?"
```

Esperado: `OK: na bateria o driver recusa quiet e balanced-performance, aceita balanced e low-power`, saída `0`. Confirme que o perfil voltou ao original:

```bash
cat /sys/devices/platform/acer-wmi/platform-profile/*/profile
```

- [ ] **Step 4: Rodar a suíte inteira, Python e shell**

```bash
cd /home/brunodobner/Claude/Nitrosense
python3 -m pytest -q
./tests/run-all.sh
```

Esperado: `91 passed` no pytest; no shell, os 9 originais no mesmo estado, mais os dois novos.

- [ ] **Step 5: Commit**

```bash
git add tests/test-perfil-bateria.sh
git commit -m "test: recusa de perfil na bateria, verificada no hardware

Confirma no driver o que o modelo assume: quiet, balanced-performance e
performance sao recusados na bateria; balanced e low-power passam.

Pula quando a maquina esta na tomada -- nao ha como verificar a recusa
com o cabo ligado, e tirar o cabo nao e coisa que um teste faca.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## O que este plano entrega

Ao fim das dez tarefas existe software funcionando e testável, e nada do
que está no ar foi desligado:

- a camada de acesso, o modelo, a telemetria e a configuração, com suíte
  Python que roda sem hardware, sem root e sem laptop Acer;
- o agente instalado como serviço de usuário, com a troca automática
  **desligada** por padrão — o `damx-daemon` continua fazendo esse
  trabalho, e os dois não se atrapalham;
- o grupo `nexus_sense` e a regra udev aplicados, com teste no hardware
  provando que a escrita sem root passa;
- dois testes novos na suíte shell existente.

## O que fica para o plano 2

A GUI PySide6 (as quatro telas da spec §6), a bandeja `StatusNotifierItem`
(§7), o `nexus-sense-helper` com `pkexec` (§5.3), e a **virada**: ligar
`auto_switch`, desinstalar o `damx-daemon` e a GUI antiga, e apontar o
`setup.sh` para os artefatos novos.
