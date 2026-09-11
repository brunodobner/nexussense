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
