# QudoSSL Commercial — Source Pins

_Last updated: 2026-09-03 · ZENV Quantum_

This product vendors its source from upstream OpenSSL in **two** pinned pieces,
each to a single upstream tag:

- **`openssl/`** — the libraries and the `openssl` app — as a **git subtree** at
  tag `openssl-3.5.7` ([ADR-0004](adr/ADR-0004-openssl-subtree-tag-3.5.7.md)).
- **`openssl-fips/`** — the FIPS-module source **only** — as a **git submodule**
  (a "thin fork") pinned to tag `openssl-3.5.4`
  ([ADR-0006](adr/ADR-0006-fips-module-3.5.4-boundary.md),
  [ADR-0007](adr/ADR-0007-fips-submodule-thin-fork.md)).

This page records both pins, explains why the two use different mechanisms, and
shows how to verify and how to update them.

---

## The pins

| Component | Mechanism | Upstream source | Pinned ref | Pinned commit | Licence |
|---|---|---|---|---|---|
| `openssl/` | git subtree | <https://github.com/openssl/openssl> | tag `openssl-3.5.7` | `b1eb2c8` (vendored-in) | Apache-2.0 |
| `openssl-fips/` | git submodule | <https://github.com/openssl/openssl> | tag `openssl-3.5.4` | `c1eeb9406b6142148f267594197d853403d10208` (gitlink) | Apache-2.0 |

`openssl/` is the unmodified upstream OpenSSL 3.5.7 LTS tree (release 9 Jun 2026).
It is the cryptographic surface of this product: ML-KEM (FIPS 203), ML-DSA
(FIPS 204) and SLH-DSA (FIPS 205) are OpenSSL's own implementations, and the FIPS
module is OpenSSL's own `fips.so`. Nothing under `openssl/` is ZENV's.

`openssl-fips/` is the unmodified upstream OpenSSL 3.5.4 tree — the version under
CMVP validation — carried as a submodule and used **only** to build the FIPS
module, which runs under the 3.5.7 libraries via provider dispatch
([ADR-0006](adr/ADR-0006-fips-module-3.5.4-boundary.md)). It is a **thin fork**:
never patched, and fetched on demand rather than copied into the repository.

> **No ZENV source.** QudoSSL Community pins a second subtree, `qudo-pqc-lib/`,
> because it delegates ML-KEM/ML-DSA mathematics to ZENV's engine. This product
> has no delegation and no ZENV cryptographic module — both pins above are
> upstream OpenSSL, nothing else.

---

## Why a subtree for `openssl/`, a submodule for `openssl-fips/`

`openssl/` is a **git subtree**: the upstream files are committed directly into
this repository at commit `b1eb2c8`. That is deliberate
([ADR-0004](adr/ADR-0004-openssl-subtree-tag-3.5.7.md)) and matters for the
product's proposition:

- **A plain `git clone` gets the libraries.** No second fetch is needed to build
  the core product; what you clone is what builds.
- **The tree is diffable against public OpenSSL.** A security team can compare
  `openssl/` against the upstream `openssl-3.5.7` tag and find nothing changed —
  the product's entire proposition.
- **The pin is a commit in this repo's history**, not a floating pointer.

`openssl-fips/` is a **git submodule** instead
([ADR-0007](adr/ADR-0007-fips-submodule-thin-fork.md)). The FIPS module is built
once from the 3.5.4 boundary and then frozen; vendoring a second, near-identical
full copy of OpenSSL as a subtree would duplicate ~158 MB for a tree we never
modify and never diff as part of "did we change OpenSSL?". A submodule keeps the
repository thin, still pins an **exact** upstream commit (verifiably unmodified),
and — unlike the untracked directory it replaced — makes the FIPS source
**reproducibly fetchable from a clone**. It is materialised on demand:

```sh
git submodule update --init openssl-fips     # or: make -C build fips-src
```

`make install_fips` and the FIPS build targets run this automatically, so a FIPS
build "just works"; a libraries-only build (`make all` / `install`) never fetches
it.

---

## Verifying the pins

**1. The versions the trees declare.** `openssl/VERSION.dat` records `3.5.7`
(`RELEASE_DATE="9 Jun 2026"`); once materialised, `openssl-fips/VERSION.dat`
records `3.5.4`. Both carry no pre-release tag and an empty `BUILD_METADATA` —
exactly what the upstream `openssl-3.5.7` and `openssl-3.5.4` tags ship.

**2. The submodule commit.** `git submodule status` shows `openssl-fips` pinned
to `c1eeb9406b6142148f267594197d853403d10208` (the peeled commit of upstream tag
`openssl-3.5.4`); `.gitmodules` records the URL and path.

**3. The pristine gate.** `make -C build verify-pristine` proves nothing was
patched into either tree. It greps the four files QudoSSL Community modifies to
delegate its PQC mathematics — `Configure`, `crypto/ml_kem/ml_kem.c`,
`crypto/ml_dsa/ml_dsa_key.c`, `crypto/ml_dsa/ml_dsa_sign.c` — for any `QUDO`
reference, plus any `QUDO_PQC_DELEGATE` guard, and **fails** if any appears. It
covers `openssl/` always and `openssl-fips/` once the submodule is materialised
(it prints a note and skips it otherwise), and for the submodule it additionally
**fails if the working tree differs from its pinned commit**.

```sh
make -C build verify-pristine
```

After a build, the same property holds at the binary level:
`nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO` must return **0**. Zero is
the pass condition — the exact opposite of Community, where a non-zero count
passes. It is the cleanest one-command way to tell the two editions apart.

For the full provenance-and-reproducibility story see
[`reproducibility.md`](reproducibility.md); for what the trees contain at
component granularity see [`sbom-inventory.md`](sbom-inventory.md).

---

## Updating the pins

Neither pin is **ever** advanced by patching a tree in place.

- **`openssl/` (libraries).** If upstream needs a change — a security release, a
  bug fix — the change goes upstream and this product **re-vendors a later
  upstream tag** as a new subtree commit, updating the table's ref/commit, the
  `VERSION.dat` values and the SBOM.
- **`openssl-fips/` (FIPS module).** The module is **frozen** at the 3.5.4
  validation boundary. Library re-vendors do **not** touch it. It moves only when
  a new validated boundary exists, by advancing the submodule gitlink — check out
  the new tag inside `openssl-fips/` and commit the updated gitlink — never by
  patching it.

The mechanics, cadence and the strict no-local-fork stance are governed by
[`patch-management-policy.md`](patch-management-policy.md); the decisions are
recorded in [`adr/ADR-0004-openssl-subtree-tag-3.5.7.md`](adr/ADR-0004-openssl-subtree-tag-3.5.7.md),
[`adr/ADR-0006-fips-module-3.5.4-boundary.md`](adr/ADR-0006-fips-module-3.5.4-boundary.md)
and [`adr/ADR-0007-fips-submodule-thin-fork.md`](adr/ADR-0007-fips-submodule-thin-fork.md).

---

_QudoSSL Commercial · unmodified upstream OpenSSL 3.5.7 LTS · built, packaged
and supported by ZENV Quantum Private Limited · Apache-2.0 ·
<https://zenv.ai/qudossl>_
