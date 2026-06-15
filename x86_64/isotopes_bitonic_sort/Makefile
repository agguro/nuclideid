# x86_64/create_decay_data/Makefile

CURRENT_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME          := $(notdir $(CURRENT_DIR))
SRC_ROOT      := $(patsubst %/x86_64/$(NAME)/,%,$(CURRENT_DIR)/)
PROJECT_NAME := $(notdir $(abspath $(SRC_ROOT)))

PREFIX ?= /usr/local/bin

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURRENT_DIR)/../../)/
endif

MODE          ?= release
ARCH          := x86_64

BIN_DIR       = $(SRC_ROOT)/$(MODE)/bin/$(ARCH)/$(NAME)
BUILD_DIR     = $(SRC_ROOT)/$(MODE)/build/$(ARCH)/$(NAME)
KERNEL_BUILD  = $(SRC_ROOT)/$(MODE)/build/kernels/$(NAME)

KERNEL_DIR   := $(SRC_ROOT)/kernels/$(NAME)
INC_DIR      := $(SRC_ROOT)/$(ARCH)/include
LIB_DIR      := $(SRC_ROOT)/$(ARCH)/lib

AS           := as
LD           := ld

ASFLAGS      := --64 -msyntax=att -mmnemonic=att -I$(BUILD_DIR) -I$(INC_DIR) -I$(LIB_DIR) -I$(KERNEL_DIR) -I$(KERNEL_BUILD)
LDFLAGS      := -m elf_x86_64 -dynamic-linker /lib64/ld-linux-x86-64.so.2 -L/usr/local/cuda/lib64 -L/usr/lib/x86_64-linux-gnu -lcuda -lc -lcrypto -lssl

ifeq ($(MODE),debug)
    ASFLAGS    += -g
    LDFLAGS    += -g
else
    LDFLAGS    += -s
endif

SRC_HOST  := $(CURRENT_DIR)/$(NAME).s
OBJ       := $(BUILD_DIR)/$(NAME).o
LST       := $(BUILD_DIR)/$(NAME).lst
TARGET    := $(BIN_DIR)/$(NAME)

-include $(CURRENT_DIR)/MakefileLists.mk
LIB_SOURCES_BARE := $(notdir $(LIB_SOURCES))
LIB_SOURCES_FULL := $(addprefix $(LIB_DIR)/,$(LIB_SOURCES_BARE))
EXTRA_OBJS   := $(patsubst $(LIB_DIR)/%.s,$(BUILD_DIR)/obj_%.o,$(LIB_SOURCES_FULL))
ALL_OBJS     := $(OBJ) $(EXTRA_OBJS)

all: release

debug release: directories info $(TARGET)

info:

$(OBJ): $(SRC_HOST) | directories
	$(AS) $(ASFLAGS) -c $(SRC_HOST) -o $(OBJ) -a=$(LST)

$(BUILD_DIR)/obj_%.o: $(LIB_DIR)/%.s | directories
	$(AS) $(ASFLAGS) -c $< -o $@

$(TARGET): $(ALL_OBJS) | directories
	$(LD) $(LDFLAGS) $(ALL_OBJS) -o $(TARGET)

directories:
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
	@if [ -d $(KERNEL_DIR) ] && [ -f $(KERNEL_DIR)/Makefile ]; then \
            $(MAKE) -C $(KERNEL_DIR) LAUNCH_ROOT=$(LAUNCH_ROOT) clean; \
	fi

test:
	@$(TARGET)

install:
	@test -f $(TARGET) || exit 1
	@mkdir -p $(PREFIX)/$(PROJECT_NAME)
	@cp $(TARGET) $(PREFIX)/$(PROJECT_NAME)/$(NAME)

uninstall:
	@rm -f $(PREFIX)/$(NAME)/$(NAME)
	@rmdir $(PREFIX)/$(NAME) 2>/dev/null || true
	@if [ "$(PREFIX)" != "/usr/local/bin" ] && [ "$(PREFIX)" != "/usr/bin" ]; then \
		rmdir $(PREFIX) 2>/dev/null || true; \
	fi

.PHONY: all debug release clean test install uninstall info directories
