# ADR-0001 — `openssl/` stays byte-for-byte unmodified upstream

**Status:** Accepted
**Date:** 2026-08-20

## Context

QudoSSL Commercial exists to give organisations a reproducible, supported build
of OpenSSL 3.5.7 LTS whose provenance they can verify for themselves. The whole
commercial proposition is that the cryptographic source is **exactly** upstream
OpenSSL — nothing added, nothing removed, nothing patched. An auditor or
security team must be able to diff `openssl/` against the public
`openssl-3.5.7` tag and find no difference.

This is a deliberate contrast with QudoSSL Community, a _different_ product that
patches OpenSSL to delegate its ML-KEM and ML-DSA mathematics to ZENV's
`qudo-pqc-lib` engine. Community patches exactly four files to do so:
`Configure`, `crypto/ml_kem/ml_kem.c`, `crypto/ml_dsa/ml_dsa_key.c` and
`crypto/ml_dsa/ml_dsa_sign.c`. If any equivalent modification leaked into this
repository, the Commercial proposition would be false — and it could be false
silently.

## Decision

`openssl/` is vendored as byte-for-byte unmodified upstream OpenSSL 3.5.7 LTS
(release 9 Jun 2026), and it stays that way. This repository adds **no ZENV
cryptography**: ML-KEM (FIPS 203), ML-DSA (FIPS 204) and SLH-DSA (FIPS 205) are
OpenSSL's own implementations, and the FIPS module is OpenSSL's own.

The invariant is **proved, not asserted.** `make -C build verify-pristine`
greps the four files Community patches for any `QUDO` reference, plus any
`QUDO_PQC_DELEGATE` guard anywhere under `openssl/`, and **fails** if any is
found. On this product it must find none. The same property holds at the binary
level after a build: `nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO` must
return **0** — zero is the pass condition, the exact opposite of Community,
where a non-zero count passes. It is the cleanest one-command way to tell the
two editions apart.

No change is ever made to `openssl/` in place. If upstream needs a fix, the fix
goes upstream and this product re-vendors a later tag (see
[ADR-0004](ADR-0004-openssl-subtree-tag-3.5.7.md) and
[`../patch-management-policy.md`](../patch-management-policy.md)).

## Consequences

- **The claim is machine-checkable.** `verify-pristine` gates configuration in
  `build/Makefile`, so a modified tree cannot be built and shipped unnoticed.
  The check must stay green; it is the product's defining property expressed as
  a test.
- **The product cannot carry local features.** Anything that would require
  editing `openssl/` — including rebranding the binary — is out of bounds. This
  is precisely why the CLI is a wrapper rather than a modified binary
  ([ADR-0002](ADR-0002-wrapper-cli-qudossl.md)).
- **No PQC implementation may be attributed to ZENV.** The post-quantum
  algorithms shipped here are OpenSSL's; documentation and marketing must say so
  ([`../../NOTICE`](../../NOTICE)).
- **Diffability is a support feature.** Because the tree matches the public tag,
  customers can independently verify provenance
  ([`../reproducibility.md`](../reproducibility.md),
  [`../subtree-pins.md`](../subtree-pins.md)).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
