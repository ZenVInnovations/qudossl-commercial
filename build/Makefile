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
        fips-src fips-module verify-pristine clean distclean dist dist-verify

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
	@echo "  make dist             cut the source tarball from git HEADs (ADR-0008)"
	@echo "  make dist-verify      build + acceptance-check the tarball, as a customer would"
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
	if [ -f "$(OPENSSL_FIPS)/Configure" ] \
	    && git -C "$(OPENSSL_FIPS)" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
	    && ! git -C "$(OPENSSL_FIPS)" diff --quiet 2>/dev/null; then \
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
	@if ! grep -q -- '--prefix=$(PREFIX)' $(OPENSSL)/configdata.pm 2>/dev/null \
	    || grep -qE '\+qudo|QudoSSL' $(OPENSSL)/configdata.pm 2>/dev/null; then \
	  echo "==> PREFIX changed or foreign build metadata found; reconfiguring"; \
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

fips-module: $(OPENSSL_FIPS)/Configure
	@# A configdata.pm carrying a +qudo stamp or QudoSSL branding was generated
	@# by some other tree's configuration (paths alone always contain "qudo" —
	@# match only the stamp/brand). Discard it so the module rebuilds pristine.
	@if grep -qE '\+qudo|QudoSSL' "$(OPENSSL_FIPS)/configdata.pm" 2>/dev/null; then \
	  echo "==> foreign build metadata in openssl-fips/configdata.pm — discarding for a pristine reconfigure"; \
	  rm -f "$(OPENSSL_FIPS)/configdata.pm"; \
	fi
	@$(MAKE) --no-print-directory $(OPENSSL_FIPS)/configdata.pm
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
	# Sanitised environment: an inherited OPENSSL_CONF/OPENSSL_MODULES (e.g.
	# from a previous install's shell exports) makes fipsinstall auto-load
	# THAT install's providers and print their identity — confusing output,
	# and exactly the wrong thing during an install.
	env -u OPENSSL_CONF -u OPENSSL_MODULES \
	"$(PREFIX)/bin/openssl" fipsinstall \
	    -module "$(MODULESDIR)/fips.$(MODEXT)" \
	    -out "$(PREFIX)/ssl/fipsmodule.cnf"
	@# Artefact assertion — the pristine gate checks sources; this checks the
	@# BUILT module actually installed. Catches a stale/branded fips.$(MODEXT)
	@# left in the submodule build dir by an earlier foreign configuration.
	@strings "$(MODULESDIR)/fips.$(MODEXT)" | grep -q '^OpenSSL FIPS Provider$$' || \
	  { echo "FATAL: installed module does not identify as 'OpenSSL FIPS Provider' — stale artefact?" >&2; exit 1; }
	@strings "$(MODULESDIR)/fips.$(MODEXT)" | grep -q '^3\.5\.4$$' || \
	  { echo "FATAL: installed module does not carry version 3.5.4 (validated boundary)" >&2; exit 1; }
	@! strings "$(MODULESDIR)/fips.$(MODEXT)" | grep -qE '\+qudo|QudoSSL' || \
	  { echo "FATAL: installed module carries vendor stamping/branding — not a pristine build" >&2; exit 1; }
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

# ---------------------------------------------------------------- source dist
# OpenSSL-style source distribution (ADR-0008): an immutable tarball cut from
# git HEADs — the repo (with the 3.5.7 subtree) via `git archive`, plus the
# FIPS submodule's pinned 3.5.4 content exported the same way, because
# `git archive` emits submodules as empty directories. Cutting from HEADs
# means working-tree dirt and stale build artefacts can never leak into what
# a customer unpacks; the tarball is fully self-contained (no git, no
# submodule access needed). Deterministic where the host tar allows (GNU tar);
# the canonical release artefact is produced by the release workflow on Linux.
DIST_VERSION := $(shell sed -n 's/^QUDO_PRODUCT_VERSION="\(.*\)"/\1/p' $(ROOT)/build/qudossl)
DIST_NAME    := qudossl-commercial-$(DIST_VERSION)
DIST_DIR     := $(ROOT)/dist
SOURCE_EPOCH := $(shell git -C $(ROOT) log -1 --format=%ct 2>/dev/null || echo 0)

dist: $(OPENSSL_FIPS)/Configure
	@test -n "$(DIST_VERSION)" || \
	  { echo "dist: cannot read QUDO_PRODUCT_VERSION from build/qudossl" >&2; exit 1; }
	@if tag=$$(git -C $(ROOT) describe --tags --exact-match 2>/dev/null); then \
	  if [ "$$tag" != "$(DIST_NAME)" ]; then \
	    echo "dist: HEAD tag '$$tag' != '$(DIST_NAME)' (from the wrapper's QUDO_PRODUCT_VERSION)" >&2; \
	    exit 1; fi; \
	else \
	  echo "==> note: HEAD is untagged — building a SNAPSHOT (tag $(DIST_NAME) for a release)"; \
	fi
	@if [ -n "$$(git -C $(ROOT) status --porcelain)" ]; then \
	  echo "==> note: working tree is dirty; the tarball is cut from committed HEADs and ignores it"; \
	fi
	@git -C $(ROOT) submodule status openssl-fips | grep -q '^ ' || \
	  { echo "dist: openssl-fips checkout is not at the pinned commit" >&2; exit 1; }
	@echo "==> staging $(DIST_NAME) from git HEADs"
	rm -rf "$(DIST_DIR)/$(DIST_NAME)"
	mkdir -p "$(DIST_DIR)/$(DIST_NAME)"
	git -C $(ROOT) archive --format=tar HEAD | tar -x -C "$(DIST_DIR)/$(DIST_NAME)"
	mkdir -p "$(DIST_DIR)/$(DIST_NAME)/openssl-fips"
	git -C $(OPENSSL_FIPS) archive --format=tar HEAD | tar -x -C "$(DIST_DIR)/$(DIST_NAME)/openssl-fips"
	@echo "==> normalising timestamps to the HEAD commit date"
	@stamp=$$(perl -e '@t = gmtime($(SOURCE_EPOCH)); \
	  printf "%04d%02d%02d%02d%02d.%02d", $$t[5]+1900, $$t[4]+1, $$t[3], $$t[2], $$t[1], $$t[0]'); \
	TZ=UTC find "$(DIST_DIR)/$(DIST_NAME)" -exec touch -t "$$stamp" {} +
	@echo "==> packing $(DIST_NAME)-src.tar.gz"
	@if tar --version 2>/dev/null | grep -q GNU; then \
	  tar --sort=name --owner=0 --group=0 --numeric-owner \
	      -C "$(DIST_DIR)" -czf "$(DIST_DIR)/$(DIST_NAME)-src.tar.gz" "$(DIST_NAME)"; \
	else \
	  (cd "$(DIST_DIR)" && find "$(DIST_NAME)" | sort | \
	    COPYFILE_DISABLE=1 tar -czf "$(DIST_NAME)-src.tar.gz" --uid 0 --gid 0 -n -T -); \
	fi
	(cd "$(DIST_DIR)" && shasum -a 256 "$(DIST_NAME)-src.tar.gz" > "$(DIST_NAME)-src.tar.gz.sha256")
	rm -rf "$(DIST_DIR)/$(DIST_NAME)"
	@echo "==> $(DIST_DIR)/$(DIST_NAME)-src.tar.gz"
	@cat "$(DIST_DIR)/$(DIST_NAME)-src.tar.gz.sha256"

# Build + install + acceptance-check FROM THE TARBALL — the artefact customers
# actually receive — into a scratch prefix, with a sanitised environment.
dist-verify:
	@bash "$(ROOT)/build/dist-verify.sh" "$(DIST_DIR)/$(DIST_NAME)-src.tar.gz"
