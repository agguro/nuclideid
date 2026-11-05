# kernels/Makefile

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR)/../../)/
endif

ALL_DIRS := $(patsubst %/,%,$(dir $(wildcard */Makefile)))
SUBDIRS  := $(filter-out . ..,$(ALL_DIRS))

all: release

# Forward only actions supported by the kernels
debug release clean test:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) MODE=$(MODE) PREFIX=$(PREFIX) --no-print-directory $@ || exit 1; \
		fi \
	done

# Handle installation locally without invoking kernel Makefiles
install:
	@true

.PHONY: all debug release clean test install uninstall