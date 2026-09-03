# ADR-0003 — FIPS mode via OpenSSL's own FIPS provider

**Status:** Accepted
**Date:** 2026-08-20

## Context

Customers deploying QudoSSL Commercial need to run in FIPS mode. There are two
ways ZENV could supply that: ship a ZENV-branded FIPS module, or use OpenSSL's
own FIPS provider that is already part of the upstream 3.5.7 source.

Shipping a ZENV module is not an option here. It would require code that is not
upstream OpenSSL, breaking the byte-for-byte invariant
([ADR-0001](ADR-0001-unmodified-upstream.md)), and it would mean attributing a
FIPS module to ZENV — which this product deliberately does not do. Delegating
cryptography to a ZENV engine and shipping a ZENV module is QudoSSL Community's
story, not this one.

## Decision

QudoSSL Commercial reaches FIPS mode using **OpenSSL's own FIPS provider**
(`fips.so` / `fips.dylib` / `fips.dll`), built from the unmodified upstream
source. No ZENV-branded module is shipped.

Operationally: `openssl fipsinstall` runs the module's power-on self-tests and
writes `fipsmodule.cnf`; a configuration then activates the `fips` and `base`
providers. `openssl list -providers` shows:

```
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider
```

In FIPS mode the product offers six ML-KEM TLS 1.3 groups — `MLKEM512`,
`MLKEM768`, `MLKEM1024`, `SecP256r1MLKEM768`, `X25519MLKEM768` and
`SecP384r1MLKEM1024`. ChaCha20-Poly1305 is absent under FIPS (not approved);
standalone `x25519` is not offered as a group, but the hybrid `X25519MLKEM768`
is, because the hybrid is an approved key-establishment construction while
X25519 alone is not. The ML-KEM, ML-DSA and SLH-DSA implementations behind these
are OpenSSL's own.

## Consequences

- **This build runs in FIPS mode, but is not a validated module.** No CMVP
  certificate exists for this artefact. It must **never** be called "FIPS
  validated" or "certified". A module you build yourself from source is not a
  CMVP-validated module even when the source corresponds to one, because CMVP
  validates a specific vendor build and boundary. Correct phrasings: "runs in
  FIPS mode", "uses the OpenSSL FIPS provider", "not a validated module". No
  CMVP certificate number or date may be invented for this build. The decision
  not to pursue validation is recorded in
  [ADR-0005](ADR-0005-no-cmvp-submission.md).
- **The FIPS module source stays exactly upstream.** This reinforces why the CLI
  is a wrapper and `VERSION.dat` / `opensslv.h.in` are never edited — those
  files are in the FIPS module source manifest
  ([ADR-0002](ADR-0002-wrapper-cli-qudossl.md)).
- **No PQC or FIPS module is attributed to ZENV.** Documentation and marketing
  describe the provider as OpenSSL's own
  ([`../../NOTICE`](../../NOTICE)).
- **Operator guidance is centralised.** The fipsinstall walkthrough, provider
  configuration and group list live in [`../fips-mode.md`](../fips-mode.md) and
  [`../crypto-officer-guide.md`](../crypto-officer-guide.md).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
