"""Task 5b: o Painel como o desenho aprovado pede.

Ver docs/INTERFACE.md, secoes 4.2 e 2 (series do grafico).
"""

from nexus_sense.device import Controls, read_state
from nexus_sense.gui.graph import TemperatureGraph
from nexus_sense.gui.pages.dashboard import DashboardPage
from nexus_sense.gui.poller import Poller
from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import gpu_name

from conftest import build_tree

GPU_STATUS = "sys/bus/pci/devices/0000:01:00.0/power/runtime_status"


def painel(qtbot, raiz):
    s = Sysfs(raiz)
    p = DashboardPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    p.apply_sample(Poller(s).read_now())
    return p


# ------------------------------------------------------- o nome da GPU


def test_o_nome_da_gpu_sai_dos_ids_do_pci(fake_root):
    """Sem nvidia-smi e sem subprocesso: os dois atributos vem do cache da
    enumeracao, entao ler nao acorda a placa."""
    assert gpu_name(Sysfs(fake_root)) == "GeForce RTX 4050 Max-Q"


def test_o_nome_sai_mesmo_com_a_gpu_adormecida(tmp_path):
    """E o ponto todo: o modelo tem de aparecer sem acordar nada."""
    raiz = build_tree(tmp_path / "t")
    (raiz / GPU_STATUS).write_text("suspended\n")
    assert gpu_name(Sysfs(raiz)) == "GeForce RTX 4050 Max-Q"


def test_sem_a_base_de_nomes_sobra_o_id_cru(tmp_path):
    """Travessao esconderia informacao que existe. Mesmo principio do
    estado da bateria: o desconhecido continua visivel."""
    raiz = build_tree(tmp_path / "t")
    (raiz / "usr/share/hwdata/pci.ids").unlink()
    assert gpu_name(Sysfs(raiz)) == "10de:28a1"


def test_id_que_a_base_nao_conhece_tambem_sobra_cru(tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / "sys/bus/pci/devices/0000:01:00.0/device").write_text("0xffff\n")
    assert gpu_name(Sysfs(raiz)) == "10de:ffff"


def test_sem_gpu_o_nome_e_none(tmp_path):
    assert gpu_name(Sysfs(tmp_path)) is None


# ----------------------------------------------------------- os cartoes


def test_os_cartoes_se_chamam_cpu_e_gpu(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert p.cards["cpu"].title.text() == "CPU"
    assert p.cards["gpu"].title.text() == "GPU"


def test_cpu_e_gpu_tem_os_mesmos_campos_na_mesma_ordem(qtbot, fake_root):
    """E o que faz o olho varrer a coluna. Ver INTERFACE.md secao 4.2."""
    p = painel(qtbot, fake_root)
    assert tuple(p.cards["cpu"].rows) == ("modelo", "uso", "temperatura")
    assert tuple(p.cards["gpu"].rows) == ("modelo", "uso", "temperatura")


def test_a_gpu_nao_tem_mais_linha_de_estado(qtbot, fake_root):
    """Se ha temperatura e uso na tela, a placa esta acordada -- dizer de
    novo e redundancia."""
    p = painel(qtbot, fake_root)
    assert "estado" not in p.cards["gpu"].rows


def test_o_cartao_da_gpu_traz_o_modelo(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert "RTX 4050" in p.cards["gpu"].rows["modelo"].text()


def test_gpu_acordada_nao_mostra_selo(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert p.cards["gpu"].badge.isVisible() is False


def test_gpu_adormecida_mostra_selo_e_apaga_os_valores(qtbot, tmp_path):
    """O estado so aparece quando e anormal. Ver INTERFACE.md secao 4.2."""
    raiz = build_tree(tmp_path / "t")
    (raiz / GPU_STATUS).write_text("suspended\n")
    p = painel(qtbot, raiz)
    p.show()
    assert p.cards["gpu"].badge.isVisible() is True
    assert "adormecida" in p.cards["gpu"].badge.text().lower()
    assert p.cards["gpu"].rows["uso"].text() == "—"
    assert p.cards["gpu"].rows["temperatura"].text() == "—"
    # o modelo continua: le-lo nao depende de a placa estar acordada
    assert "RTX 4050" in p.cards["gpu"].rows["modelo"].text()


def amostra_com_gpu(leitura):
    from nexus_sense.gui.poller import Sample

    return Sample(fans=None, cpu_temp=47.0, gpu=leitura, battery=None, cpu_usage=None)


def test_gpu_ociosa_mostra_selo_e_mantem_o_ultimo_valor(qtbot, fake_root):
    """Enquanto a sonda se cala para a placa poder dormir, o cartao fica
    com o ultimo valor lido e o selo diz por que ele parou de andar.
    Escolha do usuario em 2026-10-10, contra travessao: com outro
    programa segurando a placa a pausa volta a cada cinco minutos, e
    apagar os numeros toda vez chamaria mais atencao que o motivo."""
    from nexus_sense.telemetry import GpuReading

    p = painel(qtbot, fake_root)
    p.show()
    p.apply_sample(
        amostra_com_gpu(GpuReading(asleep=False, temperature=45.0, utilization=0, idle=True))
    )

    assert p.cards["gpu"].badge.isVisible() is True
    assert "ociosa" in p.cards["gpu"].badge.text().lower()
    assert p.cards["gpu"].rows["uso"].text() == "0%"
    assert p.cards["gpu"].rows["temperatura"].text() == "45 °C"


def test_gpu_ociosa_nao_interrompe_a_linha_do_grafico(qtbot, fake_root):
    """A outra metade da mesma escolha: a serie segue reta, sem buraco."""
    from nexus_sense.telemetry import GpuReading

    p = painel(qtbot, fake_root)
    p.apply_sample(
        amostra_com_gpu(GpuReading(asleep=False, temperature=45.0, utilization=0, idle=True))
    )
    assert list(p.graph.gpu_samples)[-1] == 45.0


def test_o_selo_de_ociosa_some_quando_a_sonda_volta_a_ler(qtbot, fake_root):
    from nexus_sense.telemetry import GpuReading

    p = painel(qtbot, fake_root)
    p.show()
    p.apply_sample(
        amostra_com_gpu(GpuReading(asleep=False, temperature=45.0, utilization=0, idle=True))
    )
    p.apply_sample(
        amostra_com_gpu(GpuReading(asleep=False, temperature=46.0, utilization=12))
    )
    assert p.cards["gpu"].badge.isVisible() is False
    assert p.cards["gpu"].rows["uso"].text() == "12%"


def test_os_tres_cartoes_de_cima_continuam_com_a_mesma_altura(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    alturas = {p.cards[n].sizeHint().height() for n in ("cpu", "gpu", "ventoinhas")}
    assert len(alturas) == 1


# ------------------------------------------------- o grafico de duas series


def test_o_grafico_guarda_as_duas_series(qtbot):
    g = TemperatureGraph(maxlen=4)
    qtbot.addWidget(g)
    g.add_sample(60.0, 40.0)
    g.add_sample(62.0, 41.0)
    assert list(g.samples) == [60.0, 62.0]
    assert list(g.gpu_samples) == [40.0, 41.0]


def test_a_serie_da_gpu_aceita_buraco(qtbot):
    """Adormecida no meio da janela: o ponto e None, e a linha se
    interrompe em vez de cair a zero."""
    g = TemperatureGraph(maxlen=4)
    qtbot.addWidget(g)
    g.add_sample(60.0, 40.0)
    g.add_sample(62.0, None)
    assert list(g.gpu_samples) == [40.0, None]


def test_as_duas_series_tem_cores_diferentes(qtbot):
    g = TemperatureGraph()
    qtbot.addWidget(g)
    assert g.cor_cpu != g.cor_gpu


def test_o_grafico_desenha_com_as_duas_series(qtbot):
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.resize(320, 160)
    for i in range(5):
        g.add_sample(60.0 + i, 40.0 + i)
    assert not g.grab().isNull()


def test_o_grafico_desenha_com_a_gpu_ausente(qtbot):
    g = TemperatureGraph()
    qtbot.addWidget(g)
    g.resize(320, 160)
    for i in range(5):
        g.add_sample(60.0 + i, None)
    assert not g.grab().isNull()


def test_a_amostra_alimenta_as_duas_series(qtbot, fake_root, monkeypatch):
    """A leitura da GPU e fixada aqui de proposito: com a arvore dizendo
    'active', o read_gpu chamaria o nvidia-smi de verdade e o teste
    passaria a depender da temperatura da maquina que o roda."""
    from nexus_sense import telemetry

    monkeypatch.setattr(
        telemetry,
        "read_gpu",
        lambda *a, **k: telemetry.GpuReading(asleep=False, temperature=42.0, utilization=7),
    )
    p = painel(qtbot, fake_root)
    assert list(p.graph.samples) == [47.0]
    assert list(p.graph.gpu_samples) == [42.0]


def test_com_a_gpu_dormindo_a_serie_dela_recebe_none(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / GPU_STATUS).write_text("suspended\n")
    p = painel(qtbot, raiz)
    assert list(p.graph.gpu_samples) == [None]


# ------------------------------------------------- o estado da bateria


def test_o_estado_da_bateria_e_traduzido(qtbot, fake_root):
    """A arvore diz 'Not charging'. Ver INTERFACE.md secao 5, decisao 2."""
    p = painel(qtbot, fake_root)
    assert p.cards["bateria"].rows["estado"].text() == "não carregando"


def test_estado_desconhecido_fica_cru_e_nao_vira_travessao():
    """Esconder o que o driver disse apagaria informacao que existe."""
    from nexus_sense.gui.pages.dashboard import battery_status

    assert battery_status("Charging") == "carregando"
    assert battery_status("Algo Novo") == "Algo Novo"
    assert battery_status(None) is None
