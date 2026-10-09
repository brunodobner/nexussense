import json
import subprocess

from nexus_sense.config import Config, load, save
from nexus_sense.device import Controls, read_state
from nexus_sense.maximum import MaximumMode
from nexus_sense.sysfs import Sysfs

from conftest import build_tree


class Runtime:
    def __init__(self, ppd="balanced", powermizer="0"):
        self.ppd = ppd
        self.powermizer = powermizer
        self.calls = []

    def hold(self):
        self.powermizer = "1"

    def close(self):
        self.powermizer = "0"

    def __call__(self, args, **_kwargs):
        self.calls.append(tuple(args))
        if args[:1] == ["busctl"] and "get-property" in args:
            resposta = json.dumps({"type": "s", "data": self.ppd})
            return subprocess.CompletedProcess(args, 0, resposta, "")
        if args[:1] == ["busctl"] and "set-property" in args:
            self.ppd = args[-1]
            return subprocess.CompletedProcess(args, 0, "", "")
        raise AssertionError(args)


def test_ativa_o_modo_composto_e_guarda_o_estado(tmp_path):
    root = build_tree(tmp_path / "root", profile="balanced")
    sysfs = Sysfs(root)
    config_path = tmp_path / "config.toml"
    runtime = Runtime()
    maximum = MaximumMode(Controls(sysfs), config_path, runner=runtime, gpu=runtime)

    assert maximum.enable(read_state(sysfs)) == ()
    config = load(config_path)
    assert config.maximum_mode is True
    assert config.maximum_saved_profile == "balanced"
    assert config.maximum_saved_ppd == "balanced"
    assert config.maximum_saved_powermizer is None
    assert read_state(sysfs).profile == "balanced-performance"
    assert read_state(sysfs).fan_speed == (0, 0)
    assert runtime.ppd == "performance"
    assert runtime.powermizer == "1"


def test_desativar_restaura_perfil_cpu_e_gpu(tmp_path):
    root = build_tree(tmp_path / "root", profile="balanced-performance")
    sysfs = Sysfs(root)
    config_path = tmp_path / "config.toml"
    save(
        Config(
            maximum_mode=True,
            maximum_saved_profile="quiet",
            maximum_saved_ppd="balanced",
            maximum_saved_powermizer="0",
        ),
        config_path,
    )
    runtime = Runtime(ppd="performance", powermizer="1")
    maximum = MaximumMode(Controls(sysfs), config_path, runner=runtime, gpu=runtime)

    assert maximum.disable() == ()
    assert load(config_path).maximum_mode is False
    assert read_state(sysfs).profile == "quiet"
    assert runtime.ppd == "balanced"
    assert runtime.powermizer == "0"


def test_na_bateria_o_modo_nao_ativa(tmp_path):
    root = build_tree(tmp_path / "root", on_ac=False)
    sysfs = Sysfs(root)
    maximum = MaximumMode(Controls(sysfs), tmp_path / "config.toml", Runtime())
    assert "tomada" in maximum.enable(read_state(sysfs))[0]
    assert maximum.requested() is False
