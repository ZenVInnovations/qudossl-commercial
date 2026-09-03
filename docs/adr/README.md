# QudoSSL Commercial — Architecture Decision Records

_Last updated: 2026-09-03 · ZENV Quantum_

This directory records the architecture decisions **specific to QudoSSL
Commercial** — a reproducible, supported build of unmodified upstream OpenSSL
3.5.7 LTS, built, packaged and supported by ZENV Quantum Private Limited. The
value of the product is the build, the provenance and the support, **not**
modified code: this repository contains no ZENV cryptography, and ML-KEM
(FIPS 203), ML-DSA (FIPS 204) and SLH-DSA (FIPS 205) are OpenSSL's own
implementations.

Each ADR uses the standard format — Title, Status, Date, Context, Decision,
Consequences — and captures one decision that shapes what this product is and,
just as importantly, what it deliberately is not. Read together they explain why
`openssl/` stays byte-for-byte upstream, why the CLI is a wrapper rather than a
rebranded binary, how FIPS mode is reached without shipping a ZENV module, how
the source is pinned, and why this artefact carries no CMVP certificate.

These decisions are **Accepted** and current. When one is superseded, its status
is updated in place and a later ADR references it; the record is never rewritten
to hide the earlier choice.

---

## Index

| ADR | Title | Summary |
|---|---|---|
| [ADR-0001](ADR-0001-unmodified-upstream.md) | Unmodified upstream OpenSSL | `openssl/` stays byte-for-byte upstream OpenSSL 3.5.7; the claim is proved by `make verify-pristine`, not asserted. The product's defining decision. |
| [ADR-0002](ADR-0002-wrapper-cli-qudossl.md) | Wrapper CLI `qudossl` | Ship a thin `qudossl` banner-and-delegate wrapper next to the genuine `openssl` binary rather than rebrand it — rebranding would falsify the pristine claim and touch FIPS-manifest files. |
| [ADR-0003](ADR-0003-fips-via-openssl-provider.md) | FIPS via the OpenSSL provider | FIPS mode is reached with OpenSSL's own `fips` provider; no ZENV module ships. This build runs in FIPS mode but is not a validated module. |
| [ADR-0004](ADR-0004-openssl-subtree-tag-3.5.7.md) | OpenSSL as a subtree at tag 3.5.7 | Vendor `openssl/` as a single git subtree pinned to upstream tag `openssl-3.5.7`; a plain clone builds the libraries. (The separate 3.5.4 FIPS-module source is a submodule instead — ADR-0007.) |
| [ADR-0005](ADR-0005-no-cmvp-submission.md) | No CMVP submission | This product pursues no CMVP submission of its own; it relies on the OpenSSL FIPS provider. The commercial value is build + provenance + support, never a certificate. |
| [ADR-0006](ADR-0006-fips-module-3.5.4-boundary.md) | FIPS module at the 3.5.4 boundary | Build the FIPS module from OpenSSL 3.5.4 (the version under CMVP validation) and run it under the 3.5.7 libraries via provider dispatch; the libraries stay at 3.5.7. |
| [ADR-0007](ADR-0007-fips-submodule-thin-fork.md) | 3.5.4 FIPS source as a submodule (thin fork) | Vendor the 3.5.4 FIPS source as a git submodule pinned to tag `openssl-3.5.4`, fetched on demand — not a subtree; `openssl/` stays a subtree. Amends ADR-0004/0006. |

---

## Related documentation

- Living status: [`../qudossl-commercial-current-state.md`](../qudossl-commercial-current-state.md)
- Build and FIPS-mode walkthrough: [`../../README.md`](../../README.md), [`../fips-mode.md`](../fips-mode.md)
- Non-negotiable rules: [`../../CLAUDE.md`](../../CLAUDE.md)
- Provenance and reproducibility: [`../reproducibility.md`](../reproducibility.md), [`../subtree-pins.md`](../subtree-pins.md)
- Support and update policy: [`../patch-management-policy.md`](../patch-management-policy.md)

---

_QudoSSL Commercial · unmodified upstream OpenSSL 3.5.7 LTS · built, packaged
and supported by ZENV Quantum Private Limited · Apache-2.0 ·
<https://zenv.ai/qudossl>_
