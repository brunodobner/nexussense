from nexus_sense.device import Controls, read_state
from nexus_sense.gui.pages.dashboard import LINHAS_POR_CARTAO, DashboardPage
from nexus_sense.gui.poller import Poller
from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import battery

from conftest import agente_no_ar, build_tree

SUPERIORES = ("cpu", "gpu", "ventoinhas")


def painel(qtbot, raiz):
    s = Sysfs(raiz)
    p = DashboardPage(Controls(s))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    p.apply_sample(Poller(s).read_now())
    return p


class MaximumFake:
    def __init__(self, active):
        self._active = active

    def active(self, _on_ac):
        return self._active


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
    assert "i5-13420H" in p.cards["cpu"].rows["modelo"].text()


def test_a_primeira_amostra_nao_tem_uso_de_cpu(qtbot, fake_root):
    """Uso e diferenca entre duas leituras de /proc/stat: na primeira nao
    ha com o que comparar, e inventar um numero seria mentir."""
    p = painel(qtbot, fake_root)
    assert p.cards["cpu"].rows["uso"].text() == "—"


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
    assert "50" in p.cards["cpu"].rows["uso"].text()


def test_mostra_a_temperatura_do_pacote_com_unidade(qtbot, fake_root):
    p = painel(qtbot, fake_root)
    assert "47" in p.cards["cpu"].rows["temperatura"].text()
    assert "°C" in p.cards["cpu"].rows["temperatura"].text()


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
    # Na escala da barra da tela Desempenho, que vale 20 a 100 no
    # firmware: os dois lugares mostram o mesmo numero.
    assert texto == "manual — 63% / 75%"


def test_o_par_da_curva_aparece_como_automatico(qtbot, tmp_path):
    """A curva grava pares como 25,24. Ate 2026-10-17 o painel os chamava de
    manual enquanto a tela Desempenho marcava Automatico -- o usuario viu os
    dois ao mesmo tempo."""
    raiz = build_tree(tmp_path / "t")
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text("25,24\n")
    agente_no_ar("25,24")
    p = painel(qtbot, raiz)
    assert p.cards["ventoinhas"].rows["modo"].text() == (
        "automático — o Nexus Sense decide pela temperatura"
    )


def test_um_par_que_a_curva_nao_registrou_segue_manual(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text("70,80\n")
    agente_no_ar("25,24")
    p = painel(qtbot, raiz)
    assert p.cards["ventoinhas"].rows["modo"].text() == "manual — 63% / 75%"


def test_com_o_agente_parado_o_par_e_manual(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t")
    (raiz / "sys/devices/platform/acer-wmi/nitro_sense/fan_speed").write_text("25,24\n")
    p = painel(qtbot, raiz)
    assert p.cards["ventoinhas"].rows["modo"].text().startswith("manual")


def test_o_cabecalho_traz_o_perfil_com_o_nome_em_portugues(qtbot, tmp_path):
    """Fora dos cartoes de proposito: dentro deles quebraria as tres
    linhas iguais que o alinhamento exige."""
    raiz = build_tree(tmp_path / "t", profile="balanced-performance")
    p = painel(qtbot, raiz)
    assert "Desempenho" in p.header.text()


def test_o_cabecalho_distingue_o_modo_maximo_do_perfil_do_firmware(qtbot, tmp_path):
    raiz = build_tree(tmp_path / "t", profile="balanced-performance")
    s = Sysfs(raiz)
    p = DashboardPage(Controls(s), maximum=MaximumFake(True))
    qtbot.addWidget(p)
    p.apply_state(read_state(s))
    assert "Desempenho máximo" in p.header.text()
    assert "CPU + GPU" in p.header.text()


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
