"""O power-profiles-daemon pelo barramento, sem tocar na maquina.

As respostas abaixo sao copia do que o `busctl` devolveu nesta maquina em
2026-10-09, com o ppd 0.30. Repare que o perfil 'performance' nao traz
PlatformDriver nenhum: a chave falta, nao vem vazia.
"""

import json
import subprocess

from nexus_sense import ppd

ATIVO = '{"type":"s","data":"performance"}'

PERFIS = json.dumps(
    {
        "type": "aa{sv}",
        "data": [
            {
                "Profile": {"type": "s", "data": "power-saver"},
                "CpuDriver": {"type": "s", "data": "intel_pstate"},
                "PlatformDriver": {"type": "s", "data": "placeholder"},
                "Driver": {"type": "s", "data": "multiple"},
            },
            {
                "Profile": {"type": "s", "data": "balanced"},
                "CpuDriver": {"type": "s", "data": "intel_pstate"},
                "PlatformDriver": {"type": "s", "data": "placeholder"},
                "Driver": {"type": "s", "data": "multiple"},
            },
            {
                "Profile": {"type": "s", "data": "performance"},
                "CpuDriver": {"type": "s", "data": "intel_pstate"},
                "Driver": {"type": "s", "data": "intel_pstate"},
            },
        ],
    }
)


def responde(stdout, codigo=0, anotar=None):
    def runner(args, **kwargs):
        if anotar is not None:
            anotar.append(list(args))
        return subprocess.CompletedProcess(args, codigo, stdout=stdout, stderr="")

    return runner


def test_a_leitura_vai_pelo_busctl_e_nao_pelo_script_python():
    """`powerprofilesctl` e um script Python de 135 ms por chamada; o
    `busctl` devolve a mesma propriedade em 3,9 ms. O agente pergunta a
    cada passada em modo maximo -- medido, eram 7,8% de um nucleo."""
    chamadas = []
    assert ppd.active_profile(responde(ATIVO, anotar=chamadas)) == "performance"
    assert chamadas == [
        [
            "busctl", "--system", "--json=short", "get-property",
            "org.freedesktop.UPower.PowerProfiles",
            "/org/freedesktop/UPower/PowerProfiles",
            "org.freedesktop.UPower.PowerProfiles",
            "ActiveProfile",
        ]
    ]


def test_a_escrita_usa_a_mesma_propriedade():
    assert ppd.set_argv("balanced") == [
        "busctl", "--system", "set-property",
        "org.freedesktop.UPower.PowerProfiles",
        "/org/freedesktop/UPower/PowerProfiles",
        "org.freedesktop.UPower.PowerProfiles",
        "ActiveProfile", "s", "balanced",
    ]


def test_servico_fora_do_ar_e_none_e_nao_excecao():
    # busctl sai 1 com "The name is not activatable" no stderr.
    assert ppd.active_profile(responde("", codigo=1)) is None
    assert ppd.platform_drivers(responde("", codigo=1)) is None


def test_busctl_ausente_e_none_e_nao_excecao():
    def explode(args, **kwargs):
        raise FileNotFoundError("busctl")

    assert ppd.active_profile(explode) is None
    assert ppd.platform_drivers(explode) is None


def test_resposta_ilegivel_e_none_e_nao_excecao():
    assert ppd.active_profile(responde("isto nao e json")) is None
    assert ppd.active_profile(responde('{"type":"s"}')) is None
    assert ppd.platform_drivers(responde('{"type":"s","data":"texto"}')) is None


def test_os_drivers_de_plataforma_saem_so_de_quem_os_tem():
    assert ppd.platform_drivers(responde(PERFIS)) == ["placeholder", "placeholder"]
