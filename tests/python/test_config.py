import dataclasses
import tomllib

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


def test_quem_le_durante_a_gravacao_nunca_ve_arquivo_pela_metade(tmp_path):
    """Dois processos mexem neste arquivo: a janela grava a intencao e o
    agente rele a cada passada. Abrir com 'wb' trunca antes de escrever, e
    quem lesse nesse intervalo recebia os PADROES -- com o modo maximo
    desligado e a troca automatica religada -- sem erro nenhum.

    Medido em 2026-10-09 neste mesmo formato de teste: 57% das leituras
    voltavam erradas.
    """
    import threading
    import time

    alvo = tmp_path / "config.toml"
    real = Config(
        auto_switch=False,
        battery_profile="low-power",
        maximum_mode=True,
        maximum_saved_profile="balanced-performance",
        maximum_saved_ppd="balanced",
    )
    save(real, alvo)

    parar = threading.Event()

    def escritor():
        while not parar.is_set():
            save(real, alvo)

    fio = threading.Thread(target=escritor)
    fio.start()
    try:
        erradas = leituras = 0
        fim = time.monotonic() + 0.5
        while time.monotonic() < fim:
            leituras += 1
            if load(alvo) != real:
                erradas += 1
    finally:
        parar.set()
        fio.join()

    assert leituras > 100
    assert erradas == 0


def test_a_gravacao_nao_deixa_temporario_para_tras(tmp_path):
    alvo = tmp_path / "nexus-sense/config.toml"
    save(Config(maximum_mode=True), alvo)
    save(Config(maximum_mode=False), alvo)
    assert [p.name for p in alvo.parent.iterdir()] == ["config.toml"]


def test_gravar_por_um_link_preserva_o_link(tmp_path):
    """Quem guarda a configuracao num repositorio de dotfiles tem um link
    aqui. Trocar o arquivo no lugar nao pode substituir o link por uma
    copia."""
    verdadeiro = tmp_path / "dotfiles/config.toml"
    verdadeiro.parent.mkdir()
    save(Config(), verdadeiro)
    link = tmp_path / "config.toml"
    link.symlink_to(verdadeiro)

    save(Config(battery_profile="low-power"), link)

    assert link.is_symlink()
    assert load(verdadeiro).battery_profile == "low-power"


# ─── o que esta versao nao conhece fica ─────────────────────────────


def test_gravar_preserva_a_chave_que_esta_versao_nao_conhece(tmp_path):
    caminho = tmp_path / "config.toml"
    caminho.write_text('auto_switch = true\ncampo_de_uma_versao_futura = 7\n')
    save(dataclasses.replace(load(caminho), maximum_mode=True), caminho)
    bruto = tomllib.loads(caminho.read_text())
    assert bruto["campo_de_uma_versao_futura"] == 7
    assert bruto["maximum_mode"] is True


def test_um_processo_antigo_nao_apaga_o_campo_novo(tmp_path):
    """Em 2026-10-16 a bandeja que subiu antes da instalacao regravou o
    arquivo sem fan_curve, e a curva se desligou sozinha. Um Config de
    antes do campo faz o papel dela."""

    @dataclasses.dataclass(frozen=True)
    class ConfigDeAntes:
        auto_switch: bool = True
        maximum_mode: bool = False

    caminho = tmp_path / "config.toml"
    save(Config(fan_curve=True), caminho)
    save(ConfigDeAntes(maximum_mode=True), caminho)
    assert load(caminho).fan_curve is True
    assert load(caminho).maximum_mode is True


def test_um_campo_conhecido_que_vira_none_sai_do_arquivo(tmp_path):
    caminho = tmp_path / "config.toml"
    save(Config(saved_ac_profile="balanced-performance"), caminho)
    save(Config(saved_ac_profile=None), caminho)
    assert "saved_ac_profile" not in tomllib.loads(caminho.read_text())


def test_arquivo_corrompido_nao_impede_a_gravacao(tmp_path):
    caminho = tmp_path / "config.toml"
    caminho.write_text("isto nao e toml = = =\n")
    save(Config(fan_curve=True), caminho)
    assert load(caminho).fan_curve is True


# ─── fan_curve: ninguem escolheu, ligada, desligada ─────────────────
#
# Desde 2026-10-16 a curva e o Automatico nos modelos medidos. O config
# distingue "ninguem escolheu" (None: vale o padrao do modelo) de uma
# escolha -- inclusive o false que o agente grava quando a rede dispara.


def test_sem_fan_curve_no_arquivo_ninguem_escolheu(tmp_path):
    caminho = tmp_path / "config.toml"
    caminho.write_text('battery_profile = "balanced"\n')
    assert load(caminho).fan_curve is None
    assert Config().fan_curve is None


def test_fan_curve_escrito_e_escolha(tmp_path):
    caminho = tmp_path / "config.toml"
    for valor, esperado in (("true", True), ("false", False)):
        caminho.write_text(f"fan_curve = {valor}\n")
        assert load(caminho).fan_curve is esperado


def test_ninguem_escolheu_nao_vira_escolha_ao_gravar(tmp_path):
    """Gravar o config por outro motivo -- o modo maximo, o perfil de
    tomada -- nao pode fixar o padrao de hoje como escolha do usuario."""
    caminho = tmp_path / "config.toml"
    save(Config(maximum_mode=True), caminho)
    with open(caminho, "rb") as arquivo:
        assert "fan_curve" not in tomllib.load(arquivo)


def test_fan_curve_de_tipo_errado_e_ninguem_escolheu(tmp_path):
    caminho = tmp_path / "config.toml"
    caminho.write_text('fan_curve = "sim"\n')
    assert load(caminho).fan_curve is None
