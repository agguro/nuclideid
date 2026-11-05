# SQLite catalog loader. The name is retained for existing build orchestration.
CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SRC_ROOT := $(abspath $(CURRENT_DIR)/../..)
MODE ?= release
PREFIX ?= /usr/local/bin
BIN_DIR = $(SRC_ROOT)/$(MODE)/bin/x86_64/isotopes_bitonic_sort
BUILD_DIR = $(SRC_ROOT)/$(MODE)/build/x86_64/isotopes_bitonic_sort
TARGET = $(BIN_DIR)/isotopes_bitonic_sort
OBJ = $(BUILD_DIR)/isotopes_bitonic_sort.o
CATALOG_OBJ = $(BUILD_DIR)/isotope_catalog.o
CATALOG_SHARED = $(BUILD_DIR)/libisotope_catalog.so
CATALOG_STATIC = $(BUILD_DIR)/libisotope_catalog.a
AS := as
LD := ld
AR := ar
ASFLAGS := --64 -msyntax=att -mmnemonic=att -I$(SRC_ROOT)/x86_64/include
LDFLAGS := -m elf_x86_64 -dynamic-linker /lib64/ld-linux-x86-64.so.2
LDLIBS := -lc -lsqlite3
ifeq ($(MODE),debug)
ASFLAGS += -g
else
LDFLAGS += -s
endif
all: release
debug release:
	$(MAKE) --no-print-directory MODE=$@ build
build: $(TARGET) $(CATALOG_SHARED) $(CATALOG_STATIC)
$(BUILD_DIR)/%.o: $(CURRENT_DIR)/%.s $(SRC_ROOT)/x86_64/include/isotope_catalog.inc
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@
$(TARGET): $(OBJ) $(CATALOG_OBJ)
	@mkdir -p $(BIN_DIR)
	$(LD) $(LDFLAGS) $(OBJ) $(CATALOG_OBJ) $(LDLIBS) -o $@
$(CATALOG_SHARED): $(CATALOG_OBJ)
	$(LD) -shared -z defs $(CATALOG_OBJ) $(LDLIBS) -o $@
$(CATALOG_STATIC): $(CATALOG_OBJ)
	$(AR) rcs $@ $<
test: build
	python3 $(SRC_ROOT)/tests/test_isotope_catalog.py $(TARGET) $(CATALOG_SHARED)
install: build
	install -D $(TARGET) $(PREFIX)/$(notdir $(SRC_ROOT))/isotopes_bitonic_sort
uninstall:
	rm -f $(PREFIX)/$(notdir $(SRC_ROOT))/isotopes_bitonic_sort
clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
.PHONY: all debug release build test install uninstall clean
