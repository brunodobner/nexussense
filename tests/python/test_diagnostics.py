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


def test_membro_que_ainda_nao_relogou_conta_como_membro(monkeypatch):
    """O caso que a maquina mostrou: consta em /etc/group, a sessao nao
    carrega. Se in_group olhasse so a sessao, a tela diria 'voce nao esta
    no grupo' para quem esta -- e mandaria rodar usermod de novo, que nao
    resolve nada. Ver spec secao 9."""
    import grp
    import os
    import pwd

    from nexus_sense import session

    entrada = grp.struct_group(("nexus_sense", "x", 950, ("alguem",)))
    monkeypatch.setattr(session.os, "getgroups", lambda: [])
    monkeypatch.setattr(session.os, "getgid", lambda: 1000)
    monkeypatch.setattr(session.grp, "getgrnam", lambda nome: entrada)
    monkeypatch.setattr(
        session.pwd, "getpwuid",
        lambda uid: pwd.struct_passwd(("alguem", "x", 1000, 1000, "", "/home/alguem", "/bin/sh")),
    )
    assert session.in_group("nexus_sense") is True


def test_quem_nao_consta_no_cadastro_nao_e_membro(monkeypatch):
    import grp
    import pwd

    from nexus_sense import session

    entrada = grp.struct_group(("nexus_sense", "x", 950, ("outro",)))
    monkeypatch.setattr(session.os, "getgroups", lambda: [])
    monkeypatch.setattr(session.os, "getgid", lambda: 1000)
    monkeypatch.setattr(session.grp, "getgrnam", lambda nome: entrada)
    monkeypatch.setattr(
        session.pwd, "getpwuid",
        lambda uid: pwd.struct_passwd(("alguem", "x", 1000, 1000, "", "/home/alguem", "/bin/sh")),
    )
    assert session.in_group("nexus_sense") is False


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


def test_fora_do_grupo_e_apontado_com_a_saida(tmp_path):
    """Estar fora do grupo e nao poder escrever andam juntos na maquina
    real: os seis sao 664 root:nexus_sense, entao quem esta fora nao
    escreve. O chmod reproduz isso -- sem ele a arvore de mentira daria
    arquivos do proprio usuario, gravaveis, e o estado seria impossivel."""
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
    c = run_checks(estado, agent=True, ppd=PpdState(False, None, False), in_group=False)
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
    assert "sudo modprobe nexus_sense" in c[0].detail


# ------------------------------------------------------------------ tela


def test_a_pagina_desenha_as_verificacoes(qtbot, fake_root):
    s = Sysfs(fake_root)
    p = DiagnosticsPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    assert p.checks_box.layout().count() >= 4


def test_todos_os_valores_ficam_abaixo_dos_rotulos(qtbot, fake_root):
    p = DiagnosticsPage(Controls(Sysfs(fake_root)))
    qtbot.addWidget(p)
    for chave, valor in p._campos.items():
        indice = p._sistema.indexOf(valor)
        linha, coluna, _linhas, colunas = p._sistema.getItemPosition(indice)
        assert coluna == 0 and colunas == 2
        indice_rotulo = p._sistema.indexOf(p._rotulos[chave])
        linha_rotulo, *_ = p._sistema.getItemPosition(indice_rotulo)
        assert linha == linha_rotulo + 1


def test_o_diagnostico_sempre_tem_conteudo(qtbot, tmp_path):
    """Justamente quando nada funciona e que ele precisa aparecer."""
    vazia = tmp_path / "vazia"
    vazia.mkdir()
    s = Sysfs(vazia)
    p = DiagnosticsPage(Controls(s))
    qtbot.addWidget(p)
    assert p.has_content(read_state(s)) is True
