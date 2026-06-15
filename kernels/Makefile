# kernels/Makefile

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR)/../../)/
endif

ALL_DIRS := $(patsubst %/,%,$(dir $(wildcard */Makefile)))
SUBDIRS  := $(filter-out . ..,$(ALL_DIRS))

all: release

# Alleen de acties doorsturen die de kernels daadwerkelijk ondersteunen
debug release clean test:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) MODE=$(MODE) PREFIX=$(PREFIX) --no-print-directory $@ || exit 1; \
		fi \
	done

# Vang install en uninstall hier lokaal geruisloos op zonder sub-Makefiles aan te roepen
install:
	@true

.PHONY: all debug release clean test install uninstall