import pytest

from nexus_sense.sysfs import Sysfs
from nexus_sense.telemetry import (
    acer_gpu_temp,
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


# ------------------------------------------- o canal GPU do acer, pelo rotulo

ACER = "sys/devices/platform/acer-wmi/hwmon/hwmon5"


def test_a_gpu_pelo_ec_vem_em_celsius_inteiros(tmp_path):
    build_tree(tmp_path, acer_temps=(61000, 79000, 45000))
    assert acer_gpu_temp(Sysfs(tmp_path)) == 79


def test_acha_o_canal_da_gpu_pelo_rotulo_e_nao_pelo_numero(tmp_path):
    """Hoje e o temp2. A garantia e o rotulo dizer GPU."""
    build_tree(tmp_path, acer_temps=(61000, 79000, 45000))
    acer = tmp_path / ACER
    (acer / "temp2_label").write_text("External 2\n")
    (acer / "temp3_label").write_text("GPU\n")
    assert acer_gpu_temp(Sysfs(tmp_path)) == 45


def test_com_a_placa_dormindo_o_canal_da_gpu_le_zero(tmp_path):
    """Zero e o que o EC responde, e nao falta de leitura: quem chama
    distingue os dois."""
    build_tree(tmp_path, acer_temps=(61000, 0, 45000))
    assert acer_gpu_temp(Sysfs(tmp_path)) == 0


def test_sem_canal_rotulado_gpu_nao_ha_leitura(tmp_path):
    build_tree(tmp_path)
    (tmp_path / ACER / "temp2_label").write_text("Outro\n")
    assert acer_gpu_temp(Sysfs(tmp_path)) is None


def test_sem_o_sensor_do_acer_nao_ha_leitura(tmp_path):
    assert acer_gpu_temp(Sysfs(tmp_path)) is None


def test_leitura_da_gpu_que_falha_nao_levanta(tmp_path):
    build_tree(tmp_path)
    (tmp_path / ACER / "temp2_input").write_text("lixo\n")
    assert acer_gpu_temp(Sysfs(tmp_path)) is None


def test_ler_a_gpu_pelo_ec_nao_le_os_outros_canais(tmp_path):
    """Cada temp*_input do acer e uma chamada ao firmware. O rotulo sai da
    memoria do driver; o valor, nao."""
    build_tree(tmp_path)
    s = Sysfs(tmp_path)
    lidos = []
    original = s.read
    s.read = lambda caminho: (lidos.append(caminho.name), original(caminho))[1]
    acer_gpu_temp(s)
    assert [nome for nome in lidos if nome.endswith("_input")] == ["temp2_input"]
