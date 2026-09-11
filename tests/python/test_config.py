from nexus_sense.config import Config, default_path, load, save


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
    assert padrao.maximum_mode is False


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
    # Comparado com o padrao, e nao com um literal: o teste diz "cai no
    # padrao", e prender o valor aqui o faria quebrar quando o padrao
    # mudasse -- foi o que aconteceu na virada.
    assert resultado.auto_switch is Config().auto_switch
    assert resultado.battery_profile == Config().battery_profile


def test_o_caminho_padrao_fica_sob_config(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    assert default_path() == tmp_path / "nexus-sense/config.toml"
