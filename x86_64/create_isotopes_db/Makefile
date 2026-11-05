# Standalone assembly SQLite importer. Requires libsqlite3-dev (SQLite >= 3.37).
CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SRC_ROOT := $(abspath $(CURRENT_DIR)/../..)
MODE ?= release
PREFIX ?= /usr/local/bin
BIN_DIR = $(SRC_ROOT)/$(MODE)/bin/x86_64/create_isotopes_db
BUILD_DIR = $(SRC_ROOT)/$(MODE)/build/x86_64/create_isotopes_db
TARGET = $(BIN_DIR)/create_isotopes_db
OBJ = $(BUILD_DIR)/create_isotopes_db.o
AS := as
LD := ld
ASFLAGS := --64 -msyntax=att -mmnemonic=att
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
build: $(TARGET)
$(OBJ): $(CURRENT_DIR)/create_isotopes_db.s
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@
$(TARGET): $(OBJ)
	@mkdir -p $(BIN_DIR)
	$(LD) $(LDFLAGS) $(OBJ) $(LDLIBS) -o $@
test: build
	python3 $(SRC_ROOT)/tests/test_create_isotopes_db.py $(TARGET)
install: build
	install -D $(TARGET) $(PREFIX)/$(notdir $(SRC_ROOT))/create_isotopes_db
uninstall:
	rm -f $(PREFIX)/$(notdir $(SRC_ROOT))/create_isotopes_db
clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
.PHONY: all debug release build test install uninstall clean
