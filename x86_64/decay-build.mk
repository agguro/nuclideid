# Shared build rules for the generator and inference host tools.
CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))
SRC_ROOT := $(abspath $(CURRENT_DIR)/../..)
NAME := $(notdir $(CURRENT_DIR))
MODE ?= release
PREFIX ?= /usr/local/bin
GPU_ARCH ?= sm_61
BUILD_DIR = $(SRC_ROOT)/$(MODE)/build/x86_64/$(NAME)
BIN_DIR = $(SRC_ROOT)/$(MODE)/bin/x86_64/$(NAME)
KERNEL_BUILD = $(SRC_ROOT)/$(MODE)/build/kernels/$(NAME)
TARGET = $(BIN_DIR)/$(NAME)
CUBIN = $(KERNEL_BUILD)/$(NAME).cubin
AS := as
CC := gcc
LD := ld
ASFLAGS := --64 -I$(SRC_ROOT)/x86_64/include -I$(KERNEL_BUILD)
LDFLAGS := -no-pie
LDLIBS := -lc -lm -lcuda
OBJECTS = $(BUILD_DIR)/$(NAME).o $(BUILD_DIR)/decay_math.o $(BUILD_DIR)/decay_gpu.o
ifeq ($(NAME),learn_decay)
OBJECTS += $(BUILD_DIR)/decay_csv.o $(BUILD_DIR)/isotope_catalog.o
LDLIBS += -lsqlite3
endif
ifeq ($(MODE),debug)
ASFLAGS += -g
else
LDFLAGS += -s
endif
all: release
debug release:
	$(MAKE) --no-print-directory MODE=$@ GPU_ARCH=$(GPU_ARCH) build
build: $(TARGET)
$(CUBIN): $(SRC_ROOT)/kernels/$(NAME)/$(NAME).ptx
	$(MAKE) -C $(SRC_ROOT)/kernels/$(NAME) MODE=$(MODE) GPU_ARCH=$(GPU_ARCH) build
$(BUILD_DIR)/$(NAME).o: $(CURRENT_DIR)/$(NAME).s $(CUBIN) $(SRC_ROOT)/x86_64/include/decay.inc $(SRC_ROOT)/x86_64/include/isotope_catalog.inc
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD_DIR)/%.o: $(SRC_ROOT)/x86_64/lib/%.s $(SRC_ROOT)/x86_64/include/decay.inc
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD_DIR)/isotope_catalog.o: $(SRC_ROOT)/x86_64/isotope_catalog/isotope_catalog.s $(SRC_ROOT)/x86_64/include/isotope_catalog.inc
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@
$(TARGET): $(OBJECTS)
	@mkdir -p $(BIN_DIR)
	$(CC) $(LDFLAGS) $(OBJECTS) $(LDLIBS) -o $@
$(BUILD_DIR)/libdecay_math.so: $(BUILD_DIR)/decay_math.o $(BUILD_DIR)/decay_csv.o
	$(LD) -shared -z defs $^ -lc -lm -o $@
ifeq ($(NAME),learn_decay)
test: build $(BUILD_DIR)/libdecay_math.so
	$(MAKE) -C $(SRC_ROOT)/x86_64/create_decay_data MODE=$(MODE) GPU_ARCH=$(GPU_ARCH) build
	python3 $(SRC_ROOT)/tests/test_decay_pipeline.py $(TARGET) $(SRC_ROOT)/$(MODE)/bin/x86_64/create_decay_data/create_decay_data $(BUILD_DIR)/libdecay_math.so
else
test: build
	$(MAKE) -C $(SRC_ROOT)/x86_64/learn_decay MODE=$(MODE) GPU_ARCH=$(GPU_ARCH) test
endif
install: build
	install -D $(TARGET) $(PREFIX)/$(notdir $(SRC_ROOT))/$(NAME)
uninstall:
	rm -f $(PREFIX)/$(notdir $(SRC_ROOT))/$(NAME)
clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
.PHONY: all debug release build test install uninstall clean
