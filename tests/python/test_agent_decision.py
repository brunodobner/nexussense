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
