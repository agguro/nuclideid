# kernels/[kernel_name]/Makefile

CURRENT_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME          := $(notdir $(CURRENT_DIR))
SRC_ROOT      := $(patsubst %/kernels/$(NAME)/,%,$(CURRENT_DIR)/)

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURRENT_DIR)/../../)/
endif

MODE ?= release

BUILD_DIR     = $(SRC_ROOT)/$(MODE)/build/kernels/$(NAME)

PTXAS         := ptxas
NVDISASM      := nvdisasm

DETECTED_CC := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d '.')

ifneq ($(DETECTED_CC),)
    GPU_ARCH := sm_$(DETECTED_CC)
else
    GPU_ARCH := sm_61
endif

PTXASFLAGS    := -v --gpu-name=$(GPU_ARCH)

ifeq ($(MODE),debug)
    PTXASFLAGS += --generate-line-info
else
    PTXASFLAGS += -O3
endif

PTX_SRC   := $(CURRENT_DIR)/$(NAME).ptx
PTX_OBJ   := $(BUILD_DIR)/$(NAME).cubin
SASS_DUMP := $(BUILD_DIR)/$(NAME).sass

all: release

install: @true 

debug release: directories info $(PTX_OBJ) $(SASS_DUMP)

info:

$(PTX_OBJ): $(PTX_SRC) | directories
	$(PTXAS) $(PTXASFLAGS) $(PTX_SRC) -o $(PTX_OBJ)

$(SASS_DUMP): $(PTX_OBJ)
	$(NVDISASM) -g $(PTX_OBJ) > $(SASS_DUMP)

directories:
	@mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all debug release clean info directories install uninstall