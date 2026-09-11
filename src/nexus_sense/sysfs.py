"""Acesso a sysfs ancorado numa raiz.

Nenhum outro modulo abre caminho absoluto. Passar uma raiz alternativa e
o que permite testar sem hardware, sem root e sem laptop Acer.
Ver spec secao 4.3.
"""

from pathlib import Path

# Nos dois nomes. O modulo passou a se chamar nexus_sense na fase de
# renomeacao; o nome antigo fica aceito porque uma maquina que ainda nao
# rodou o instalador novo continua com o linuwu_sense carregado, e a
# janela precisa funcionar nela. Ver spec secao 12.
MODULE_NAMES = ("nexus_sense", "linuwu_sense")

# Nomes que o driver da ao grupo de atributos, conforme a familia do
# laptop. Estao fixados em linuwu_sense.c:4052-4068 e nomeiam o hardware,
# nao o projeto -- a renomeacao nao os toca.
SENSE_DIRS = ("nitro_sense", "predator_sense")

# O daemon antigo tentava quatro nomes; nesta maquina existe so o ACAD.
AC_NAMES = ("AC", "ACAD", "ADP1", "AC0")


class Sysfs:
    """Le e escreve sysfs a partir de uma raiz configuravel."""

    def __init__(self, root="/"):
        self.root = Path(root)

    # ------------------------------------------------------------------
    # descoberta de caminhos
    # ------------------------------------------------------------------

    def acer_base(self):
        """O dispositivo de plataforma sob o qual tudo que importa mora."""
        return self.root / "sys/devices/platform/acer-wmi"

    def sense_dir(self):
        """nitro_sense ou predator_sense, o que existir. None se nenhum."""
        for nome in SENSE_DIRS:
            caminho = self.acer_base() / nome
            if caminho.is_dir():
                return caminho
        return None

    def _profile_device(self):
        base = self.acer_base() / "platform-profile"
        if not base.is_dir():
            return None
        for filho in sorted(base.iterdir()):
            if (filho / "profile").is_file():
                return filho
        return None

    def profile_path(self):
        """O perfil termico. Nao usamos /sys/firmware/acpi/platform_profile:
        aquele e apelido legado e fica fora do alcance do udev."""
        dispositivo = self._profile_device()
        return None if dispositivo is None else dispositivo / "profile"

    def choices_path(self):
        """Os perfis que o firmware anuncia. Quatro nesta maquina, e nao
        cinco: falta o 'performance'. Ver spec secao 2.10."""
        dispositivo = self._profile_device()
        return None if dispositivo is None else dispositivo / "choices"

    def module_loaded(self):
        for nome in MODULE_NAMES:
            if (self.root / "sys/module" / nome).is_dir():
                return True
        return False

    # ------------------------------------------------------------------
    # leitura e escrita
    # ------------------------------------------------------------------

    def read(self, path):
        return Path(path).read_text().strip()

    def write(self, path, value):
        Path(path).write_text(str(value))

    def on_ac(self):
        """True na tomada, False na bateria, None se nao houver como saber."""
        for nome in AC_NAMES:
            caminho = self.root / "sys/class/power_supply" / nome / "online"
            if caminho.is_file():
                return self.read(caminho) == "1"
        return None
