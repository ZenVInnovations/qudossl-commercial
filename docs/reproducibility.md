# Reproducibility

**QudoSSL Commercial** · unmodified upstream OpenSSL 3.5.7 LTS
Author: ZENV Quantum · Date: 2026-08-20

QudoSSL Commercial adds no source changes to OpenSSL. `openssl/` is a git
subtree pinned byte-for-byte to the upstream `openssl-3.5.7` tag, and the build
applies no patches (`make -C build verify-pristine` proves it). So there is no
QudoSSL-specific reproducibility problem to solve: **reproducing this build is
reproducing upstream OpenSSL 3.5.7.** This document states how, and — just as
importantly — is honest about the limits of that claim.

## The method

The artefacts are a deterministic function of three inputs:

| Input | Pinned by | Where it lives |
|-------|-----------|----------------|
| Source | upstream tag `openssl-3.5.7`, vendored as a subtree | `openssl/` (see [subtree-pins.md](subtree-pins.md)) |
| Configure line | one place, not retyped per build | `build/Makefile` |
| Toolchain | **the operator's responsibility** — see caveats below | the build host |

The single Configure line kept in `build/Makefile` is:

```
./Configure enable-fips --prefix=$PREFIX --libdir=lib $(EXTRA_FLAGS)
```

Same source + same Configure line + same toolchain ⇒ the same artefacts.
Because the build carries no vendor patches, anyone can cross-check the result
against a plain upstream OpenSSL 3.5.7 built the same way and find no
difference attributable to QudoSSL. The wrapper adds exactly one file to the
install tree — the `qudossl` CLI shim (`build/qudossl`) — and touches nothing
inside the library.

## How to reproduce

```bash
# 1. Get the exact source. A plain clone gets openssl/ (a subtree) — enough to
#    build the libraries. A FIPS build also needs the 3.5.4 FIPS submodule:
git clone <this-repo-url> qudossl-commercial
cd qudossl-commercial
git submodule update --init openssl-fips      # only for the FIPS module (thin fork, ADR-0007)

# 2. Prove the source is unmodified upstream BEFORE building anything.
make -C build verify-pristine
#   OK — vendored trees are unmodified upstream

# 3. Build twice into separate prefixes, from a clean tree each time.
make -C build distclean
make -C build all install_sw install_fips PREFIX=$PWD/out-a
make -C build distclean
make -C build all install_sw install_fips PREFIX=$PWD/out-b

# 4. Compare. The libraries and modules should match; see the caveats for the
#    two fields that legitimately differ (embedded build date, and PREFIX,
#    which Configure bakes into paths).
diff -r out-a/lib out-b/lib
```

> Compare `PREFIX`-independent artefacts, or build both trees into the *same*
> `PREFIX`. `Configure` bakes the prefix into `configdata.pm` and into
> installed paths, so two installs under different prefixes will differ in
> those paths — that is expected, not a reproducibility failure.

## Caveat 1 — OpenSSL writes architecture files into its own source tree

OpenSSL configures and builds **in-tree**: it generates architecture-specific
files directly under `openssl/`. The one that bites is `crypto/buildinf.h`,
which embeds a literal platform string:

```c
#define PLATFORM "platform: darwin64-arm64"
#define DATE "built on: Thu Aug 13 09:42:02 2026 UTC"
```

Two consequences follow, and both are load-bearing:

- **Always build from a clean tree.** `make` will not regenerate a file that
  already looks current. If a `buildinf.h` (or generated assembly) from an
  earlier configuration survives, the new build silently inherits it. Run
  `make -C build distclean` between reconfigurations.

- **Never seed a container or cross-platform build from a host-built tree.**
  The vendored subtree may be checked out on, say, a macOS arm64 workstation.
  If those macOS build products travel into a Linux image's build context, the
  resulting Linux binary can report `platform: darwin64-arm64` — the code runs,
  but every piece of evidence stamped with that platform string is now wrong.
  The `qudossl-banking-lab` Dockerfile
  (`stack/commercial/Dockerfile`) excludes them via `.dockerignore` **and then
  asserts the exclusion worked** (see the gates below) rather than trusting it.

## Caveat 2 — byte-for-byte requires matching the toolchain, and this repo does not pin one

Be plain about scope: **this repository does not vendor a pinned-toolchain kit**
(no fixed compiler, assembler, linker, or libc image). Byte-for-byte identical
output is therefore only achievable when the toolchain matches. Two honest
knobs feed directly into the artefacts:

- **Compiler identity and flags.** `crypto/buildinf.h` also embeds the exact
  `CFLAGS` as a `compiler_flags[]` array, and the emitted object code depends on
  the compiler version. A different GCC/Clang/MSVC, or different default flags,
  yields different bytes.

- **Build timestamp.** `util/mkbuildinf.pl` writes the `DATE` field from the
  environment variable `SOURCE_DATE_EPOCH`, falling back to the current time.
  To pin the date, export `SOURCE_DATE_EPOCH` (a fixed UNIX timestamp) before
  building; otherwise two builds a minute apart differ in that one field.

So the reproducibility guarantee is precise, not absolute: *given the same
source, the same Configure line, the same toolchain, and a pinned
`SOURCE_DATE_EPOCH`, the build is reproducible.* We do not claim bit-identical
output across arbitrary toolchains, and we do not ship a hermetic build kit that
would make that claim true. Where a stronger guarantee is needed, pin the
toolchain yourself (a fixed container base image is the usual way).

## Provenance gates the lab build runs

The `qudossl-banking-lab` Commercial image
(`stack/commercial/Dockerfile`) turns the reproducibility story into checks that
fail the build if the artefact is not what it claims. These are the gates worth
copying into any downstream pipeline:

| Gate | What it proves | Command shape |
|------|----------------|---------------|
| `verify-pristine` (before build) | source carries no vendor modification | `make -C build verify-pristine` |
| Platform check | it was actually built for the target OS | `openssl version -a \| grep -i 'platform: linux'` |
| Zero QUDO symbols | the artefact contains no ZENV crypto | `nm -a lib/libcrypto.so.3 \| grep -c QUDO` → **must be 0** |
| Library resolution | the CLI links libssl/libcrypto from `$PREFIX/lib`, not the distro copy | `ldd $PREFIX/bin/openssl \| grep -E 'libssl\|libcrypto'` |
| Provider / ML-KEM check | FIPS provider loads and offers the ML-KEM groups under `fips=yes` | `openssl list -providers` · `openssl list -tls-groups \| grep -i mlkem` |

> The zero-QUDO-symbol count is the sharpest edition test. **Zero is the pass
> condition here** — the exact opposite of QudoSSL Community, where a non-zero
> count is the pass. `verify-pristine` checks the *source*; the symbol count
> checks the *built artefact*. They are different failures: a pristine source
> tree linked against the wrong archive would pass the first and fail the
> second.

## Relation to patching

There is nothing to reproduce beyond upstream because there is nothing added to
upstream. If a fix is ever required, it does **not** get patched into `openssl/`
— it goes upstream and we re-vendor a later tag, which becomes a new, equally
reproducible pin. That policy is what keeps this document short. See
[patch-management-policy.md](patch-management-policy.md) and
[subtree-pins.md](subtree-pins.md).

## What this is not

This build **runs in FIPS mode** using OpenSSL's own FIPS provider. It is **not
a CMVP-validated module** and carries no CMVP certificate — reproducing the
build does not confer validation, and a module you compile yourself from source
is not a validated module even when the source corresponds to one. Reproducibility
here means *you can rebuild the same software from the same pinned source*,
nothing more. See [fips-mode.md](fips-mode.md).
