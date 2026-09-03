# QudoSSL Commercial — Current State

_Last updated: 2026-08-20 · ZENV Quantum_

**QudoSSL Commercial is a reproducible, supported build of unmodified upstream
OpenSSL 3.5.7 LTS — the value is the build, the provenance and the support, not
modified code.**

This is a living status page. It records what the product is _today_, how it is
built and verified, and what it deliberately does not contain. For the full
build and FIPS-mode walkthrough see [`../README.md`](../README.md); for the
non-negotiable rules see [`../CLAUDE.md`](../CLAUDE.md).

---

## Version & identity

| Field | Value |
|---|---|
| Product | **QudoSSL 1.0.0** |
| Base | **OpenSSL 3.5.7 LTS** (release 9 Jun 2026), unmodified upstream |
| Licence | **Apache-2.0** — this repository adds no code under any other licence |
| Built & supported by | ZENV Quantum Private Limited |
| Edition | **Commercial** — distinct from QudoSSL Community; not an upgrade, premium, pro or enterprise tier of it |
| CLI | `openssl` (genuine upstream binary) and `qudossl` (banner-and-delegate wrapper), installed side by side |
| Source pins | `openssl/` (libraries) — git subtree at tag `openssl-3.5.7`; `openssl-fips/` (FIPS-module source) — git submodule at tag `openssl-3.5.4`, a "thin fork" fetched on demand (ADR-0006/0007) |

The product version and the OpenSSL base version are kept distinct.
`qudossl version` prints `QudoSSL 1.0.0 (OpenSSL 3.5.7 base)` followed by the
unchanged upstream `openssl version` line, so anything parsing the latter sees
plain `OpenSSL 3.5.7 9 Jun 2026`.

> **Distinct from Community.** QudoSSL Community is a _different product_ in a
> different repository, with ML-KEM and ML-DSA mathematics delegated to ZENV's
> own `qudo-pqc-lib` engine and its own FIPS module. This product has no
> `qudo-pqc-lib` subtree, no delegation and no ZENV cryptographic module. The
> two are not comparable and are never compared or benchmarked against each
> other.

---

## Build & CI state

The tree builds single-stage from a C toolchain and perl — no CMake, because
there is nothing here to delegate to. The `Configure` line lives in one place,
`build/Makefile`.

The reference CI build is the commercial lab image:
`qudossl-banking-lab/stack/commercial/Dockerfile`, which builds this tree for
Linux and asserts its own provenance during the build. Its gates:

| Gate | Passes when |
|---|---|
| `make -C build verify-pristine` | the four files Community patches carry no `QUDO` references, and no `QUDO_PQC_DELEGATE` guard exists anywhere under `openssl/` |
| Platform check | the built CLI reports a **Linux** target |
| Zero vendor symbols | `nm -a libcrypto.so.3 | grep -c QUDO` returns **0** |
| Runtime path | `ldd` resolves `libssl`/`libcrypto` **only** from the install prefix |
| Provider / groups | `list -providers` shows base + fips, and the ML-KEM TLS groups are present |

> `nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO` returning **0** is the
> pass condition for this product — the exact opposite of Community, where a
> non-zero count passes. It is the cleanest one-command way to tell the two
> editions apart.

The pristine gate is the product's defining property expressed as a check: the
build _proves_ nothing was changed rather than asserting it. It must stay green.

---

## FIPS posture

This build **runs in FIPS mode** using OpenSSL's own FIPS provider
(`fips.so` / `fips.dylib` / `fips.dll`). `openssl fipsinstall` runs the module's
power-on self-tests and writes `fipsmodule.cnf`; a configuration activates the
`fips` and `base` providers. `openssl list -providers` then shows:

```
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider
```

The providers are OpenSSL's own — this build ships no ZENV-branded module.

> **Not a validated module.** No CMVP certificate exists for this artefact, and
> it must never be described as "FIPS validated" or "certified". A module you
> build yourself from source is not a CMVP-validated module even when the source
> corresponds to one, because CMVP validates a specific vendor build and
> boundary. The correct phrasings are "runs in FIPS mode", "uses the OpenSSL
> FIPS provider" and "not a validated module".

Six ML-KEM TLS groups are available in FIPS mode: `MLKEM512`, `MLKEM768`,
`MLKEM1024`, `SecP256r1MLKEM768`, `X25519MLKEM768`, `SecP384r1MLKEM1024`.
ChaCha20-Poly1305 is absent under FIPS (not approved); standalone `x25519` is
not offered as a group, but the hybrid `X25519MLKEM768` is. The ML-KEM, ML-DSA
and SLH-DSA implementations are OpenSSL's own — no PQC implementation here is
ZENV's.

Full detail: [`fips-mode.md`](fips-mode.md) and
[`crypto-officer-guide.md`](crypto-officer-guide.md).

---

## Support posture

ZENV tracks upstream OpenSSL security releases and re-vendors a later tag; it
never forks or patches `openssl/` locally. If upstream needs a change, the
change goes upstream and QudoSSL Commercial re-vendors — that is what keeps the
tree diffable against public OpenSSL and keeps `verify-pristine` meaningful.

- Policy: [`patch-management-policy.md`](patch-management-policy.md)
- Known upstream issues and the no-fork-patch stance:
  [`upstream-defects.md`](upstream-defects.md)
- Pinned subtree and reproducibility:
  [`subtree-pins.md`](subtree-pins.md), [`reproducibility.md`](reproducibility.md)
- Bill of materials (OpenSSL only): [`sbom-inventory.md`](sbom-inventory.md)

---

## What is deliberately NOT here

| Not present | Because |
|---|---|
| ZENV cryptography | ML-KEM, ML-DSA and SLH-DSA are OpenSSL's own implementations; no PQC implementation is attributed to ZENV |
| `qudo-pqc-lib` subtree | this product has no delegated mathematics and no ZENV FIPS module; that is Community's story, not this one |
| Any local patch to `openssl/` | the invariant is that `openssl/` stays byte-for-byte upstream 3.5.7; fixes go upstream and are re-vendored |
| A CMVP submission | this artefact is not submitted for validation and carries no certificate — see [`adr/ADR-0005-no-cmvp-submission.md`](adr/ADR-0005-no-cmvp-submission.md) |

Architecture decisions behind these choices are recorded in
[`adr/README.md`](adr/README.md).

---

_QudoSSL Commercial · unmodified upstream OpenSSL 3.5.7 LTS · built, packaged
and supported by ZENV Quantum Private Limited · Apache-2.0 ·
<https://zenv.ai/qudossl>_
