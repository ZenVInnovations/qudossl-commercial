# QudoSSL Commercial — build wrapper.
#
# QudoSSL Commercial is upstream OpenSSL 3.5.7, unmodified. This wrapper exists
# to make the build reproducible and to keep the Configure line in one place; it
# adds no patches and no cryptography. If you removed this Makefile and ran
# ./Configure by hand in openssl/, you would get the same artifacts.
#
# That is the product's defining property, so the build must not quietly erode
# it: `make verify-pristine` fails if anything under openssl/ has been modified
# away from the vendored upstream release.
#
#   make all       PREFIX=/opt/qudossl-commercial
#   make install   PREFIX=/opt/qudossl-commercial
#
# On a prefix outside your home directory the install targets need sudo.

SHELL      := /bin/bash
ROOT       := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
OPENSSL    := $(ROOT)/openssl
PREFIX     ?= /opt/qudossl-commercial
LIBDIR     ?= lib
JOBS       ?= $(shell (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu || echo 4)

# Same FIPS enablement as the Community edition, so the two are comparable.
# No --with-qudo-pqc-* flags: there is no delegated mathematics here.
CONFIG_OPTS ?= enable-fips
EXTRA_FLAGS ?=

.PHONY: all help openssl openssl-config test install install_sw install_fips \
        verify-pristine clean distclean

all: openssl

help:
	@echo "QudoSSL Commercial — unmodified upstream OpenSSL 3.5.7"
	@echo
	@echo "  make all              configure and build"
	@echo "  make install          libs, headers, CLI, man pages"
	@echo "  make install_sw       as above without ~2000 man pages"
	@echo "  make install_fips     the FIPS module and its config"
	@echo "  make test             upstream's own test suite"
	@echo "  make verify-pristine  prove openssl/ is unmodified upstream"
	@echo "  make clean|distclean"
	@echo
	@echo "  PREFIX=$(PREFIX)"
	@echo "  JOBS=$(JOBS)"

# ---------------------------------------------------------------- pristine gate
# The whole proposition is "we changed nothing", so prove it rather than assert
# it. QudoSSL Community patches exactly four files to delegate its PQC maths;
# those same files are the sharpest test that this tree is NOT that one.
verify-pristine:
	@echo "==> checking openssl/ carries no vendor modifications"
	@bad=0; \
	for f in Configure crypto/ml_kem/ml_kem.c crypto/ml_dsa/ml_dsa_key.c \
	         crypto/ml_dsa/ml_dsa_sign.c; do \
	  n=$$(grep -c QUDO "$(OPENSSL)/$$f" 2>/dev/null || true); n=$${n:-0}; \
	  if [ "$$n" != "0" ]; then echo "  FAIL $$f carries $$n QUDO references"; bad=1; fi; \
	done; \
	n=$$(grep -rl QUDO_PQC_DELEGATE "$(OPENSSL)" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" != "0" ]; then echo "  FAIL delegation guard present in $$n file(s)"; bad=1; fi; \
	if [ "$$bad" = "0" ]; then echo "  OK — openssl/ is unmodified upstream"; else exit 1; fi

$(OPENSSL)/configdata.pm: | verify-pristine
	@echo "==> configuring OpenSSL 3.5.7 (prefix $(PREFIX))"
	cd $(OPENSSL) && ./Configure $(CONFIG_OPTS) \
	    --prefix=$(PREFIX) --libdir=$(LIBDIR) $(EXTRA_FLAGS)

openssl-config: $(OPENSSL)/configdata.pm

# Configure bakes PREFIX into configdata.pm, so a changed PREFIX must
# reconfigure or the install lands in the previous location.
openssl: openssl-config
	@if ! grep -q -- '--prefix=$(PREFIX)' $(OPENSSL)/configdata.pm 2>/dev/null; then \
	  echo "==> PREFIX changed; reconfiguring"; \
	  cd $(OPENSSL) && ./Configure $(CONFIG_OPTS) \
	      --prefix=$(PREFIX) --libdir=$(LIBDIR) $(EXTRA_FLAGS); \
	fi
	@echo "==> building with $(JOBS) jobs"
	$(MAKE) -C $(OPENSSL) -j$(JOBS)

test: openssl
	$(MAKE) -C $(OPENSSL) test

install: openssl
	$(MAKE) -C $(OPENSSL) install
	@$(MAKE) --no-print-directory install-cli

install_sw: openssl
	$(MAKE) -C $(OPENSSL) install_sw
	@$(MAKE) --no-print-directory install-cli

install_fips: openssl
	$(MAKE) -C $(OPENSSL) install_fips

.PHONY: install-cli
install-cli:
	@install -m 0755 $(ROOT)/build/qudossl-commercial $(PREFIX)/bin/qudossl-commercial
	@echo "==> installed $(PREFIX)/bin/qudossl-commercial"

clean:
	-$(MAKE) -C $(OPENSSL) clean

distclean:
	-$(MAKE) -C $(OPENSSL) distclean
	-rm -f $(OPENSSL)/configdata.pm
