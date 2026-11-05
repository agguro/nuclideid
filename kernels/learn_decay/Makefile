CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SRC_ROOT := $(abspath $(CURRENT_DIR)/../..)
NAME := $(notdir $(CURRENT_DIR))
MODE ?= release
GPU_ARCH ?= sm_61
BUILD_DIR = $(SRC_ROOT)/$(MODE)/build/kernels/$(NAME)
PTXAS := ptxas
FLAGS := --gpu-name=$(GPU_ARCH)
ifeq ($(MODE),debug)
FLAGS += --generate-line-info
else
FLAGS += -O3
endif
all: release
debug release:
	$(MAKE) --no-print-directory MODE=$@ build
build: $(BUILD_DIR)/$(NAME).cubin
$(BUILD_DIR)/$(NAME).cubin: $(CURRENT_DIR)/$(NAME).ptx
	@mkdir -p $(BUILD_DIR)
	$(PTXAS) $(FLAGS) $< -o $@
clean:
	rm -rf $(BUILD_DIR)
test: build
install uninstall:
	@true
.PHONY: all debug release build clean test install uninstall
