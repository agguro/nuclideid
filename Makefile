# Makefile

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR))/
endif

SUBDIRS := kernels x86_64

# Default all Linux builds to release mode
MODE ?= release
export MODE

all: release

# Select the build mode from the requested target
debug: export MODE := debug
release: export MODE := release

# Forward standard actions to each component
debug release test install:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) MODE=$(MODE) PREFIX=$(PREFIX) --no-print-directory $@ || exit 1; \
		fi \
	done

clean:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) --no-print-directory clean || true; \
		fi \
	done
	rm -rf $(LAUNCH_ROOT)debug $(LAUNCH_ROOT)release *.deb

deb: release
	$(eval PKG_DIR := $(LAUNCH_ROOT)nuclideid-framework_1.0.0_amd64)
	@rm -rf $(PKG_DIR)
	@mkdir -p $(PKG_DIR)/DEBIAN
	@mkdir -p $(PKG_DIR)/usr/local/bin
	@# create CONTROL file for the package
	@echo "Package: nuclideid-framework" > $(PKG_DIR)/DEBIAN/control
	@echo "Version: 1.0.0" >> $(PKG_DIR)/DEBIAN/control
	@echo "Architecture: amd64" >> $(PKG_DIR)/DEBIAN/control
	@echo "Maintainer: agguro <agguro@vds>" >> $(PKG_DIR)/DEBIAN/control
	@echo "Description: Multi-architecture GPU accelerated nuclear data engine" >> $(PKG_DIR)/DEBIAN/control
	@echo "Depends: libc6, libssl3" >> $(PKG_DIR)/DEBIAN/control
	@# make install to package directory
	@$(MAKE) LAUNCH_ROOT=$(LAUNCH_ROOT) MODE=release PREFIX=$(PKG_DIR)/usr/local/bin --no-print-directory install
	@# create the .deb package
	@dpkg-deb --build $(PKG_DIR) > /dev/null
	@rm -rf $(PKG_DIR)

.PHONY: all debug release clean test install deb