# ==============================================================================
# ASM-LINUX-FRAMEWORK: PROJECT ROOT ORCHESTRATOR (WITH ROOT CLEAN)
# ==============================================================================

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR))/
endif

SUBDIRS := kernels x86_64

all: debug

debug release test install:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) --no-print-directory $@ || exit 1; \
		fi \
	done

# Breid clean uit zodat hij eerst de submappen leegt, en daarna de root-mappen sloopt
clean:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) --no-print-directory $@ || exit 1; \
		fi \
	done
	@echo "Schoonmaken hoofdmappen in $(LAUNCH_ROOT)..."
	rm -rf $(LAUNCH_ROOT)bin $(LAUNCH_ROOT)build

.PHONY: all debug release clean test install