# QudoSSL Commercial — Project Instructions

## What this product is

QudoSSL Commercial is a **reproducible, supported build of unmodified upstream
OpenSSL 3.5.7 LTS**. The value the product delivers is the build, the
provenance and the support — *not* modified code.

`openssl/` is a git subtree pinned to the upstream `openssl-3.5.7` tag. A
security team can diff it against the public OpenSSL tree and find nothing
changed. That is the entire proposition, so nothing in this repository may
erode it.

## The one invariant

**`openssl/` must remain byte-for-byte upstream OpenSSL 3.5.7.**

`make -C build verify-pristine` proves it and must stay green. It greps the
four files QudoSSL Community patches to delegate its PQC mathematics
(`Configure`, `crypto/ml_kem/ml_kem.c`, `crypto/ml_dsa/ml_dsa_key.c`,
`crypto/ml_dsa/ml_dsa_sign.c`) plus any `QUDO_PQC_DELEGATE` guard, and fails if
any appears. Never patch `openssl/` to add a feature or a fix; if upstream
needs a change, it goes upstream and we re-vendor a later tag
(see `docs/patch-management-policy.md`).

## This is NOT QudoSSL Community

QudoSSL Community is a **different product** in a different repository, with
ML-KEM and ML-DSA mathematics delegated to ZENV's own `qudo-pqc-lib` engine and
its own FIPS module (the "QudoSSL FIPS Provider"). This repository has **no
`qudo-pqc-lib` subtree, no delegation, and no ZENV cryptographic module**. Its
FIPS module is OpenSSL's own `fips.so`, built from the `openssl-fips/` submodule —
a "thin fork" pinned unmodified to upstream OpenSSL 3.5.4 (the CMVP validation
boundary), run under the 3.5.7 libraries via provider dispatch (ADR-0006/0007).

The two are not comparable and must never be compared or conflated. In
particular, this product carries none of Community's CAVP/ACVP, side-channel,
zeroization or boundary-disclosure story, because there is no ZENV crypto here
to analyse.

## Accuracy rules (these are legal, not stylistic)

- **Never** describe this product as FIPS 140-3 *validated* or *certified*. It
  runs in **FIPS mode** using the OpenSSL FIPS provider; no CMVP certificate
  exists for this artefact. "Runs in FIPS mode" and "not a validated module"
  are the correct forms.
- **Never** attribute any ML-KEM / ML-DSA / SLH-DSA implementation to ZENV. It
  is upstream OpenSSL's.
- **Never** frame Commercial as an upgrade, premium, pro or enterprise tier of
  Community. It is a licence-and-support proposition around upstream OpenSSL,
  not a more capable build.
- The product version is **QudoSSL 1.0.0**; the OpenSSL base is **3.5.7**. Keep
  the two distinct — `qudossl version` prints "QudoSSL 1.0.0 (OpenSSL 3.5.7
  base)" and then the unchanged upstream `openssl version` line.

## The CLI

The product ships two commands, installed side by side (see
`docs/adr/ADR-0002`):

- `openssl` — the genuine upstream binary. `openssl version` prints plain
  "OpenSSL 3.5.7", byte-identical to upstream, so scripts and audits are safe.
- `qudossl` — a thin banner-and-delegate wrapper (`build/qudossl`). It prints
  the QudoSSL Commercial banner on `version` and a bare invocation, and
  delegates everything else unchanged. It never patches the binary and never
  falls back to a system openssl.

## Engineering principles

- Change nothing under `openssl/`. Prove it with `verify-pristine`.
- Keep the build reproducible; the `Configure` line lives in one place
  (`build/Makefile`).
- Verify claims by measurement (run the command, read the symbol table), never
  by assertion. Every verification block in the docs must be reproducible on a
  real install.
