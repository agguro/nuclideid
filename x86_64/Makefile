# x86_64/Makefile

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR)/../../)/
endif

ALL_DIRS := $(patsubst %/,%,$(dir $(wildcard */Makefile)))
SUBDIRS  := $(filter-out . ..,$(ALL_DIRS))

all: release

debug release clean test install:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) MODE=$(MODE) PREFIX=$(PREFIX) --no-print-directory $@ || exit 1; \
		fi \
	done

.PHONY: all debug release clean test install