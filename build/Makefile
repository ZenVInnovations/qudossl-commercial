# QudoSSL Commercial — build wrapper.
#
# QudoSSL Commercial is unmodified upstream OpenSSL. openssl/ is a git subtree at
# tag openssl-3.5.7 and provides the libraries and the app. openssl-fips/ is a
# git submodule — a "thin fork" pinned to upstream tag openssl-3.5.4 (the version
# under CMVP validation) that we never modify — and provides the FIPS module only,
# which runs under the 3.5.7 libraries (ADR-0006). This wrapper adds no patches
# and no cryptography and keeps the Configure lines in one place.
#
# The 3.5.4 FIPS source is fetched on demand (git submodule update --init); a
# plain checkout of this repo does not pull it until a FIPS build needs it.
#
# That unmodified-upstream property is the product's defining property, so the
# build must not quietly erode it: `make verify-pristine` fails if anything under
# either tree has been modified away from its vendored upstream release.
#
#   make all       PREFIX=/opt/qudossl
#   make install   PREFIX=/opt/qudossl
#
# On a prefix outside your home directory the install targets need sudo.

SHELL      := /bin/bash
ROOT       := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
# openssl/      : libraries + app — git subtree, tag openssl-3.5.7
# openssl-fips/ : FIPS module only — git submodule (thin fork), tag openssl-3.5.4 (ADR-0006)
OPENSSL      := $(ROOT)/openssl
OPENSSL_FIPS := $(ROOT)/openssl-fips
PREFIX     ?= /opt/qudossl
LIBDIR     ?= lib
MODULESDIR := $(PREFIX)/$(LIBDIR)/ossl-modules
JOBS       ?= $(shell (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu || echo 4)

# FIPS module filename is OS-specific (fips.so / fips.dylib / fips.dll).
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
MODEXT := dylib
else ifeq ($(UNAME_S),Linux)
MODEXT := so
else
MODEXT := dll
endif

# Same FIPS enablement as the Community edition, so the two are comparable.
# No --with-qudo-pqc-* flags: there is no delegated mathematics here.
CONFIG_OPTS ?= enable-fips
EXTRA_FLAGS ?=

.PHONY: all help openssl openssl-config test install install_sw install_fips \
        fips-src fips-module verify-pristine clean distclean

all: openssl

help:
	@echo "QudoSSL Commercial — OpenSSL 3.5.7 libraries + OpenSSL 3.5.4 FIPS module (ADR-0006)"
	@echo
	@echo "  make all              configure and build the 3.5.7 libraries + app"
	@echo "  make install          libs, headers, CLI (qudossl + openssl), man pages"
	@echo "  make install_sw       as above without ~2000 man pages"
	@echo "  make fips-src         fetch the pinned 3.5.4 FIPS submodule (thin fork)"
	@echo "  make fips-module      build the 3.5.4 FIPS module (validated boundary)"
	@echo "  make install_fips     install the 3.5.4 module + fipsinstall (run after 'make install')"
	@echo "  make test             upstream's own test suite"
	@echo "  make verify-pristine  prove both vendored trees are unmodified upstream"
	@echo "  make clean|distclean"
	@echo
	@echo "  PREFIX=$(PREFIX)"
	@echo "  JOBS=$(JOBS)"

# ---------------------------------------------------------------- pristine gate
# The whole proposition is "we changed nothing", so prove it rather than assert
# it. QudoSSL Community patches exactly four files to delegate its PQC maths;
# those same files are the sharpest test that this tree is NOT that one.
verify-pristine:
	@echo "==> checking vendored trees carry no vendor modifications"
	@bad=0; \
	for tree in "$(OPENSSL)" "$(OPENSSL_FIPS)"; do \
	  if [ ! -f "$$tree/Configure" ]; then \
	    echo "  note: $$(basename $$tree) not materialised — skipped (run 'make fips-src')"; continue; fi; \
	  for f in Configure crypto/ml_kem/ml_kem.c crypto/ml_dsa/ml_dsa_key.c \
	           crypto/ml_dsa/ml_dsa_sign.c; do \
	    n=$$(grep -c QUDO "$$tree/$$f" 2>/dev/null || true); n=$${n:-0}; \
	    if [ "$$n" != "0" ]; then echo "  FAIL $$tree/$$f carries $$n QUDO references"; bad=1; fi; \
	  done; \
	  n=$$(grep -rl QUDO_PQC_DELEGATE "$$tree" 2>/dev/null | wc -l | tr -d ' '); \
	  if [ "$$n" != "0" ]; then echo "  FAIL $$tree: delegation guard present in $$n file(s)"; bad=1; fi; \
	  bm=$$(sed -n 's/^BUILD_METADATA=//p' "$$tree/VERSION.dat" 2>/dev/null); \
	  if [ -n "$$bm" ]; then echo "  FAIL $$tree: VERSION.dat BUILD_METADATA=$$bm (must be empty)"; bad=1; fi; \
	done; \
	if [ -f "$(OPENSSL_FIPS)/Configure" ] && ! git -C "$(OPENSSL_FIPS)" diff --quiet 2>/dev/null; then \
	  echo "  FAIL openssl-fips: submodule working tree differs from its pinned commit"; bad=1; fi; \
	if [ "$$bad" = "0" ]; then echo "  OK — vendored trees are unmodified upstream"; else exit 1; fi

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

# ---------------------------------------------------------------- FIPS module
# The FIPS module comes from openssl-fips/ (tag openssl-3.5.4, the version under
# CMVP validation), NOT from the 3.5.7 library tree. It runs under the 3.5.7
# libraries via OpenSSL's provider dispatch interface (ADR-0006). Build it once
# and keep it frozen; library re-vendors never move it.
#
# openssl-fips/ is a thin-fork submodule pinned to upstream tag openssl-3.5.4.
# Materialise it on demand — a bare checkout of this repo carries only the pin,
# not the 3.5.4 source. `Configure` existing is our proxy for "submodule present".
$(OPENSSL_FIPS)/Configure:
	@echo "==> materialising the pinned OpenSSL 3.5.4 FIPS submodule (upstream tag openssl-3.5.4)"
	cd $(ROOT) && git submodule update --init openssl-fips

fips-src: $(OPENSSL_FIPS)/Configure
	@echo "==> FIPS source ready: $$(cd $(OPENSSL_FIPS) && git describe --tags --always 2>/dev/null || echo openssl-3.5.4)"

$(OPENSSL_FIPS)/configdata.pm: $(OPENSSL_FIPS)/Configure
	@$(MAKE) --no-print-directory verify-pristine
	@echo "==> configuring OpenSSL 3.5.4 for the FIPS module (prefix $(PREFIX))"
	cd $(OPENSSL_FIPS) && ./Configure enable-fips \
	    --prefix=$(PREFIX) --libdir=$(LIBDIR) $(EXTRA_FLAGS)

fips-module: $(OPENSSL_FIPS)/configdata.pm
	@echo "==> building the 3.5.4 FIPS module with $(JOBS) jobs"
	$(MAKE) -C $(OPENSSL_FIPS) -j$(JOBS) build_generated
	$(MAKE) -C $(OPENSSL_FIPS) -j$(JOBS) providers/fips.$(MODEXT)

# install_fips overlays the 3.5.4 module into the install's module dir, then runs
# `openssl fipsinstall` with the installed 3.5.7 binary against the 3.5.4 module
# -- the cross-version step OpenSSL supports. It runs the module's power-on
# self-tests and writes fipsmodule.cnf with the MAC of this exact binary. Run
# `make install` first so the openssl binary and libraries are in place.
install_fips: fips-module
	@[ -x "$(PREFIX)/bin/openssl" ] || { \
	  echo "install_fips: no openssl at $(PREFIX)/bin -- run 'make install' first" >&2; exit 1; }
	install -d "$(MODULESDIR)"
	# `install_sw` does not create the ssl config dir (that is `install_ssldirs`),
	# so ensure it exists before fipsinstall writes fipsmodule.cnf into it.
	install -d "$(PREFIX)/ssl"
	install -m 0755 "$(OPENSSL_FIPS)/providers/fips.$(MODEXT)" "$(MODULESDIR)/fips.$(MODEXT)"
	"$(PREFIX)/bin/openssl" fipsinstall \
	    -module "$(MODULESDIR)/fips.$(MODEXT)" \
	    -out "$(PREFIX)/ssl/fipsmodule.cnf"
	@echo "==> FIPS module: OpenSSL 3.5.4 (validated boundary) installed in $(MODULESDIR)"

# The product's CLI is `qudossl`, installed as a wrapper next to the upstream
# `openssl` binary — the same two-name arrangement as QudoSSL Community, so a
# customer's scripts and demos that call `qudossl` work unchanged on either
# edition. See docs/adr/ADR-0002.
#
#   openssl  the real binary — byte-identical behaviour to upstream OpenSSL
#            3.5.7. `openssl version` prints plain "OpenSSL 3.5.7", so parsers
#            and audits see exactly what they should.
#   qudossl  a wrapper that prints the QudoSSL Commercial banner on `version`
#            and delegates everything else unchanged.
.PHONY: install-cli
install-cli:
	@bindir="$(PREFIX)/bin"; \
	if [ ! -x "$$bindir/openssl" ]; then \
	    echo "install-cli: no openssl at $$bindir -- did PREFIX change without a reconfigure?" >&2; \
	    exit 1; \
	fi; \
	install -m 0755 $(ROOT)/build/qudossl "$$bindir/qudossl"; \
	echo "==> CLI: openssl (binary) + qudossl (wrapper) installed in $$bindir"

clean:
	-$(MAKE) -C $(OPENSSL) clean
	-$(MAKE) -C $(OPENSSL_FIPS) clean

distclean:
	-$(MAKE) -C $(OPENSSL) distclean
	-$(MAKE) -C $(OPENSSL_FIPS) distclean
	-rm -f $(OPENSSL)/configdata.pm $(OPENSSL_FIPS)/configdata.pm
