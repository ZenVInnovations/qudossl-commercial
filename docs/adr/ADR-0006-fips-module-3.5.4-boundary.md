# ADR-0006 — FIPS module pinned to the 3.5.4 validation boundary; libraries at 3.5.7

**Status:** Accepted. **Amended 2026-09-03** — the 3.5.4 source is now vendored as
a git **submodule (a "thin fork"), not a subtree**; see
[ADR-0007](ADR-0007-fips-submodule-thin-fork.md). The decision below (build the
FIPS module from the 3.5.4 boundary, run it under the 3.5.7 libraries) is
unchanged; only how the 3.5.4 source is carried changed.
**Date:** 2026-08-27

## Context

The FIPS module that OpenSSL submitted to the CMVP is built from a **specific**
source version. Lightship Security and the OpenSSL Corporation submitted
**OpenSSL 3.5.4** for FIPS 140-3 validation on 9 October 2025; that submission
is code-complete and lab-reviewed, awaiting the certificate.

Until now this product built its FIPS provider from the same tree as its
libraries — the single `openssl/` subtree at tag `openssl-3.5.7`
([ADR-0004](ADR-0004-openssl-subtree-tag-3.5.7.md)). That is a defensible way to
run in FIPS mode, but it means the FIPS module is a **3.5.7** build, which is
**not** the version under validation. We measured the gap: comparing the two
releases' own `providers/fips-sources.checksums` manifests, **432 of 732 FIPS
source files differ** between 3.5.4 and 3.5.7 (plus one file templatized,
`crypto/params_idx.c` → `.c.in`). The FIPS boundary is **not** frozen across the
3.5 line — a module built from 3.5.7 is a materially different module from the
one at the validated boundary.

OpenSSL's design accommodates exactly this. Per the upstream `fips_module`
manual and `README-FIPS.md`:

> "A FIPS provider built from any validated version may be used together with an
> OpenSSL library built from any supported release from OpenSSL 3.0 onwards …
> backward and forward across these releases."

The mechanism is the provider dispatch-table interface: the module and libcrypto
communicate over versioned `OSSL_DISPATCH` function-ID tables, never a shared C
ABI, so the two can differ in patch version. This is how downstreams (Red Hat,
Ubuntu) ship a frozen validated module with a separately-patched library.

## Decision

Vendor OpenSSL as **two trees** (the vendoring mechanism is refined by
[ADR-0007](ADR-0007-fips-submodule-thin-fork.md) — `openssl-fips/` is a submodule,
not a subtree):

| Tree | Upstream tag | Vendoring | Role |
|---|---|---|---|
| `openssl/` | `openssl-3.5.7` | git subtree | libraries (`libcrypto`, `libssl`) and the `openssl` app |
| `openssl-fips/` | `openssl-3.5.4` | git submodule (thin fork) | the FIPS module (`fips.so` / `fips.dylib` / `fips.dll`) **only** |

The product's FIPS module is built from `openssl-fips/` (3.5.4 — the validated
boundary) and runs under the `openssl/` (3.5.7) libraries. `make install_fips`
overlays the 3.5.4 module into the install's module directory and runs
`openssl fipsinstall` — using the installed **3.5.7** `openssl` binary against
the **3.5.4** module — to run the module's power-on self-tests and write
`fipsmodule.cnf` with the integrity MAC of that binary.

The FIPS module is **frozen** at the validated boundary. Library re-vendors
(3.5.7 → a later 3.5.x) advance `openssl/` only; `openssl-fips/` stays at 3.5.4
until a new validated boundary exists. Neither tree is ever configured with a
custom `FIPS_VENDOR`, so the module reports the upstream name.

## Evidence (measured 2026-08-27, macOS arm64)

The 3.5.4 module was built from a pristine upstream clone and exercised under the
pristine 3.5.7 library in a clean environment (`OPENSSL_CONF=/dev/null`, isolated
`OPENSSL_MODULES`):

- `fipsinstall` → **INSTALL PASSED**; the module self-reports **"OpenSSL FIPS
  Provider, version 3.5.4"** and all KATs pass.
- `list -providers` → `base` = **3.5.7**, `fips` = **3.5.4**, both `status:
  active`.
- SHA-256, **ML-KEM-768 keygen** and **ML-DSA-65 keygen** all succeed through the
  3.5.4 module on 3.5.7 libraries.
- Negative control: **MD5 is rejected** under `fips=yes` — proving FIPS routing
  is real, not a silent fallback.

Remaining before release: the same check on Linux x86-64, Linux aarch64 and
Windows x64 (CI). OpenSSL's compatibility is by design; this product still proves
it by measurement per [ADR-0001](ADR-0001-unmodified-upstream.md).

## Consequences

- **Still not a validated module.** Pinning to 3.5.4 aligns with the version in
  validation, but this is a **build-from-source** module and the 3.5.4
  certificate is not yet issued. The wording constraints of
  [ADR-0003](ADR-0003-fips-via-openssl-provider.md) and
  [ADR-0005](ADR-0005-no-cmvp-submission.md) are unchanged: "runs in FIPS mode",
  "not a validated module", no invented certificate. What improves is provenance
  — the module is now the **exact source under CMVP validation**, not an
  unrelated 3.5.7 build.
- **[ADR-0004](ADR-0004-openssl-subtree-tag-3.5.7.md) is amended: a second
  upstream tree.** Its "exactly one subtree" statement no longer holds. The
  second tree carries no ZENV code — it is upstream OpenSSL 3.5.4 — and is
  vendored as a submodule, not a subtree
  ([ADR-0007](ADR-0007-fips-submodule-thin-fork.md)).
- **`verify-pristine` covers both trees, and is hardened.** The old 4-file QUDO
  grep would not have caught a rebranded `FIPS_VENDOR` or a stamped
  `VERSION.dat` (an early build shipped a "QudoSSL FIPS Provider" module tagged
  "3.5.7+qudo-1.0.0"). The gate now checks both trees and rejects a non-empty
  `BUILD_METADATA`. The controlled Configure line never sets a custom
  `FIPS_VENDOR`.
- **The module is not rebuilt on library updates.** Re-vendoring `openssl/`
  leaves `openssl-fips/` and the frozen module untouched; only a new validated
  boundary moves it.
- **SBOM lists two OpenSSL versions** — 3.5.7 (libraries) and 3.5.4 (FIPS
  module); see [`../sbom-inventory.md`](../sbom-inventory.md) and
  [`../subtree-pins.md`](../subtree-pins.md).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
