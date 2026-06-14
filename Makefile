# ==============================================================================
# ASM-LINUX-FRAMEWORK: SUBMODULE ROOT ORCHESTRATOR
# BPI-BLUEPRINT: .blueprints/submodule_root.mk
# ==============================================================================

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR))/
endif

ifeq ($(NVDISASM),)
    $(error CRITICAL: 'nvdisasm' not found in $$PATH. Please install nvidia-cuda-toolkit!)
endif

# 2. DYNAMIC DISCOVERY & PARAMETERS
# 2. DYNAMIC DISCOVERY & PARAMETERS
ALL_DISCOVERED := $(patsubst %/,%,$(dir $(shell find . -mindepth 2 -maxdepth 2 -name Makefile)))

# We filteren de kernels eruit en zetten ze ALTIJD vooraan in de rij!
KERNEL_DIRS    := $(filter ./kernels%,$(ALL_DISCOVERED))
OTHER_DIRS     := $(filter-out ./kernels%,$(ALL_DISCOVERED))
SUBDIRS        := $(KERNEL_DIRS) $(OTHER_DIRS)

# We zetten de wet voor de absolute project root vast en exporteren deze direct!
export PROJECT_ROOT := $(CURDIR)/

ifndef PARENTROOT
    export PARENTROOT := $(CURDIR)/
endif

GLOBAL_BUILD := $(PROJECT_ROOT)build
GLOBAL_BIN   := $(PROJECT_ROOT)bin

all: debug

debug release clean test install:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) $@ || exit 1; \
		fi \
	done

.PHONY: all debug release clean test install
