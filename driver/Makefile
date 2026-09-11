obj-m := src/nexus_sense.o

MODNAME := nexus_sense

# Kernel alvo: o DKMS injeta KERNELRELEASE; fora dele, o kernel corrente.
#
# O 'override' e necessario: KERNELRELEASE chega pela linha de comando do
# make, e uma atribuicao comum nao vence outra variavel de linha de
# comando. Sem ele, um KVER solto redirecionaria o build para um kernel
# diferente daquele que o DKMS pediu -- silenciosamente, e com vermagic
# errado no .ko resultante.
ifeq ($(KERNELRELEASE),)
  KVER ?= $(shell uname -r)
else
  override KVER := $(KERNELRELEASE)
endif

KDIR := /lib/modules/$(KVER)/build
MDIR := /lib/modules/$(KVER)/kernel/drivers/platform/x86
PWD  := $(shell pwd)

# ---------------------------------------------------------------------
# Toolchain: decidido pelo kernel ALVO, nunca pelo kernel em execucao.
#
# Um modulo externo precisa do mesmo compilador do kernel para o qual e
# compilado. Forcar LLVM=1 globalmente quebra kernels GCC (ex.: o pacote
# "linux" do Arch); nao forcar nada quebra os kernels Clang com
# "unrecognized command-line option '-mstack-alignment=8'". Num sistema
# com os dois tipos instalados, so a deteccao por alvo funciona.
#
# O DKMS ja detecta clang sozinho e passa LLVM=1 na linha de comando;
# $(origin LLVM) preserva esse override.
# ---------------------------------------------------------------------
ifeq ($(origin LLVM),undefined)
  ifneq ($(shell grep -sh CONFIG_CC_IS_CLANG=y $(KDIR)/.config /boot/config-$(KVER)),)
    LLVM := 1
  endif
endif

ifeq ($(LLVM),1)
  TOOLCHAIN := LLVM=1 LLVM_IAS=1
  TOOLCHAIN_NAME := LLVM
else
  TOOLCHAIN :=
  TOOLCHAIN_NAME := GCC
endif

.PHONY: all clean install uninstall toolchain-info

all:
	@echo "Building $(MODNAME) for kernel $(KVER) [$(TOOLCHAIN_NAME)]..."
	$(MAKE) -C $(KDIR) M=$(PWD) $(TOOLCHAIN) modules

# Diagnostico: usado pelo test-toolchain.sh e util em suporte.
toolchain-info:
	@echo "KVER=$(KVER) TOOLCHAIN=$(TOOLCHAIN_NAME) KDIR=$(KDIR)"

clean:
	-$(MAKE) -C $(KDIR) M=$(PWD) clean
	@rm -f src/*.o src/*.mod src/*.mod.c src/.*.cmd
	@rm -f *.mod.c *.symvers *.order Module.markers modules.order Module.symvers

# Caminho manual, para quando nao ha DKMS. O setup.sh cuida de servicos,
# grupos e tmpfiles; este alvo so instala o modulo. Requer root -- sem
# sudo embutido, que quebraria build nao-interativo.
install: all
	install -d $(MDIR)
	install -m 644 src/$(MODNAME).ko $(MDIR)
	depmod -a $(KVER)
	@echo "$(MODNAME) instalado em $(MDIR)"

uninstall:
	rm -f $(MDIR)/$(MODNAME).ko
	depmod -a $(KVER)
	@echo "$(MODNAME) removido de $(MDIR)"
