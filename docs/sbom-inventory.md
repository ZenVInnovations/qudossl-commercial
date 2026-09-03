# SBOM — Software Bill of Materials

**QudoSSL Commercial** · Date: 2026-08-20 · Author: ZENV Quantum

This is the software bill of materials for QudoSSL Commercial. It is
deliberately, provably **minimal**: the only third-party component is
**OpenSSL 3.5.7**, under the **Apache License 2.0**. This repository adds no
code of its own under any licence except the `qudossl` CLI wrapper — a shell
script that contains no cryptography.

There is **no `qudo-pqc-lib`** here, and none of the bundled
`mlkem-native` / `mldsa-native` / `slhdsa-native` sources. Those belong to
QudoSSL Community, a different product in a different repository. In this
product the ML-KEM, ML-DSA and SLH-DSA implementations are OpenSSL's own — not
ZENV's — so there is nothing further to enumerate.

---

## Components

| Component | Version | Licence | Provenance |
|---|---|---|---|
| OpenSSL (libraries + app) | 3.5.7 (released 9 Jun 2026) | Apache-2.0 | Upstream tag `openssl-3.5.7` from `https://github.com/openssl/openssl`, vendored under `openssl/` as a git subtree in repo commit `b1eb2c8`. Unmodified — see `docs/subtree-pins.md`. |
| OpenSSL FIPS module | 3.5.4 (released 30 Sep 2025) | Apache-2.0 | Upstream tag `openssl-3.5.4` (the version under CMVP validation), carried under `openssl-fips/` as a git submodule pinned to commit `c1eeb9406b6142148f267594197d853403d10208`. Used only to build the FIPS module, which runs under the 3.5.7 libraries (ADR-0006/0007). Unmodified — see `docs/subtree-pins.md`. |

That is the entire third-party inventory: two upstream-OpenSSL entries and
nothing else — the 3.5.7 libraries and the 3.5.4 FIPS module, both Apache-2.0,
both unmodified.

> A machine-readable SBOM (SPDX or CycloneDX) generated from this tree would
> likewise carry exactly two component entries, both OpenSSL. Anything beyond
> these two upstream OpenSSL versions has been added that does not belong in this
> product.

### Deliberately absent

The following are part of **QudoSSL Community** and are intentionally **not**
present here. Listing them makes the boundary explicit for auditors comparing
the two editions:

| Not present | Where it lives instead |
|---|---|
| `qudo-pqc-lib` (ZENV PQC math engine) | QudoSSL Community only |
| Bundled `mlkem-native` / `mldsa-native` / `slhdsa-native` sources | QudoSSL Community only |
| A ZENV FIPS module (the "QudoSSL FIPS Provider") | QudoSSL Community only |

This product's FIPS module is OpenSSL's own `fips` provider; it carries no ZENV
cryptography of any kind.

---

## Shipped artefacts

Every installed binary is an output of building unmodified upstream OpenSSL
3.5.7 — **except** the `qudossl` wrapper, which is a ZENV-authored shell script
under Apache-2.0 that contains no cryptography. Library file names below are the
Linux SONAMEs; the same artefacts install as `*.3.dylib` on macOS and
`*-3-x64.dll` on Windows, and the FIPS module installs as `fips.so`,
`fips.dylib` or `fips.dll` per platform.

| Artefact | Origin | Licence | Notes |
|---|---|---|---|
| `lib/libcrypto.so.3` | Upstream OpenSSL 3.5.7 build output | Apache-2.0 | Core crypto library |
| `lib/libssl.so.3` | Upstream OpenSSL 3.5.7 build output | Apache-2.0 | TLS library |
| `lib/ossl-modules/fips.{so,dylib,dll}` | Upstream OpenSSL 3.5.7 build output | Apache-2.0 | OpenSSL FIPS provider; runs power-on self-tests, enables FIPS mode |
| `bin/openssl` (from `apps/openssl`) | Upstream OpenSSL 3.5.7 build output | Apache-2.0 | Genuine upstream CLI; `openssl version` prints plain "OpenSSL 3.5.7 9 Jun 2026" |
| `bin/qudossl` (from `build/qudossl`) | **ZENV Quantum** | Apache-2.0 | Banner-and-delegate wrapper. **No cryptography** — a shell script that prints the product banner on `version` and delegates every invocation to `bin/openssl` unchanged |

---

## Licence roll-up

**100% Apache-2.0.** Both the sole third-party component (OpenSSL) and the sole
ZENV-authored file (the `qudossl` wrapper) are licensed under the Apache License
2.0. There is no other licence anywhere in the shipped product.

| Licence | Share | Applies to |
|---|---|---|
| Apache-2.0 | 100% | OpenSSL 3.5.7; the `qudossl` wrapper |

The authoritative texts are `LICENSE` (Apache-2.0) and the per-file SPDX /
copyright headers within `openssl/`; the principal attribution is aggregated in
`NOTICE`.

---

## How to regenerate and verify

This inventory is verifiable by measurement on any real install — do not take it
on assertion.

**1. Prove the source tree is unmodified upstream** (so the "one component"
claim is honest at the source level):

```sh
$ make -C build verify-pristine
==> checking openssl/ carries no vendor modifications
  OK — openssl/ is unmodified upstream
```

**2. Prove the built artefact carries no ZENV cryptography** — zero is the only
acceptable answer for this product:

```sh
$ nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO
0
```

> This zero-`QUDO` result is the exact opposite of QudoSSL Community, where a
> non-zero count is the pass condition. It is the cleanest one-command way to
> confirm you are looking at the Commercial artefact — one with no delegated
> mathematics linked in.

**3. Confirm the pinned provenance** of the single component against
`docs/subtree-pins.md`:

```sh
$ git log --oneline -1 -- openssl/
b1eb2c8 feat: vendor upstream OpenSSL 3.5.7 as the QudoSSL Commercial source tree
```

A pristine tree, a zero-`QUDO` library and a matching subtree pin together
establish that the components table above is complete and correct.

---

## See also

- `NOTICE` — aggregated third-party attribution (OpenSSL only).
- `docs/subtree-pins.md` — the exact upstream tag and commit the `openssl/`
  subtree is pinned to, and how to verify it.
