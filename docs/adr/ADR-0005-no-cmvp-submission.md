# ADR-0005 — No CMVP submission for this product

**Status:** Accepted
**Date:** 2026-08-20

## Context

A recurring question about any FIPS-capable build is whether it will be
submitted to the NIST/CCCS Cryptographic Module Validation Program (CMVP) and
earn its own certificate. QudoSSL Community follows a delegation model with its
own ZENV FIPS module, where a distinct validation story is meaningful. This
product is different: it ships OpenSSL's own FIPS provider, built from unmodified
upstream source ([ADR-0003](ADR-0003-fips-via-openssl-provider.md)), and its
commercial value lies in the build, the provenance and the support — not in a
certificate that ZENV holds.

Submitting this artefact for its own CMVP validation would misrepresent what the
product is. A self-built module from source is not the validated module even
when the source corresponds to one, because CMVP validates a specific vendor
build and boundary; a fresh submission would also imply ZENV had produced a
distinct cryptographic module, which it has not.

## Decision

QudoSSL Commercial does **not** pursue its own CMVP submission. It relies on
OpenSSL's FIPS provider to run in FIPS mode. The commercial offering is the
reproducible build, its verifiable provenance, and ZENV's support — explicitly
**not** a certificate.

## Consequences

- **How the product is described is constrained — this is legal, not
  stylistic.** This artefact must never be called "FIPS validated" or
  "certified", and no CMVP certificate number or date may be invented for it.
  The correct phrasings are "runs in FIPS mode", "uses the OpenSSL FIPS
  provider" and "not a validated module".
- **Where validation status matters to a customer**, they are pointed at
  OpenSSL's own FIPS provider and its validation status, not at a ZENV
  certificate — because there is none for this build.
- **The value proposition is stated as build + provenance + support.** Marketing
  and documentation lead with reproducibility and diffability against upstream
  ([ADR-0001](ADR-0001-unmodified-upstream.md),
  [`../reproducibility.md`](../reproducibility.md)), not with a certification
  claim.
- **Commercial is never framed as an upgrade, premium, pro or enterprise tier of
  Community**, and the two are never benchmarked against each other. They are
  different products with different FIPS and validation postures.
- **Operator-facing FIPS guidance** carries the same non-negotiable wording; see
  [`../fips-mode.md`](../fips-mode.md) and
  [`../crypto-officer-guide.md`](../crypto-officer-guide.md).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
