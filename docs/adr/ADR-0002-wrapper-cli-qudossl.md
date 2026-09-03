# ADR-0002 — Ship a `qudossl` wrapper, not a rebranded binary

**Status:** Accepted
**Date:** 2026-08-20

## Context

The product needs its own `qudossl` identity on the command line: a banner that
names QudoSSL Commercial and its ZENV support, and a product version distinct
from the OpenSSL base version. The obvious way to get that would be to rebrand
the OpenSSL binary — editing `openssl/VERSION.dat` or `openssl/include/openssl/
opensslv.h.in` so the binary reports itself as "QudoSSL".

That approach is closed off by two facts:

1. **It would falsify the pristine claim.** Editing any file under `openssl/`
   makes the tree no longer byte-for-byte upstream, breaking the invariant in
   [ADR-0001](ADR-0001-unmodified-upstream.md) and the `verify-pristine` gate
   that proves it.
2. **Those files sit inside the FIPS module source manifest.** `VERSION.dat` and
   `opensslv.h.in` are part of the source set that defines the FIPS module.
   Touching them carries certification and integrity consequences, not merely
   cosmetic ones — a further reason the binary must be left exactly as upstream
   ships it.

There is also a portability requirement. QudoSSL Community already exposes a
`qudossl` command; customers' scripts, demos and runbooks call `qudossl`.
Commercial should honour the same name so that material ports across editions
unchanged.

## Decision

Install **two** commands side by side into `$PREFIX/bin`:

- **`openssl`** — the genuine upstream binary, entirely unmodified.
  `openssl version` prints plain `OpenSSL 3.5.7 9 Jun 2026`, byte-identical to
  upstream, so parsers and audits see exactly what they should.
- **`qudossl`** — a thin banner-and-delegate wrapper (`build/qudossl`). It
  prints the product banner on `version` and on a bare invocation, and
  delegates every other invocation to the `openssl` binary unchanged. It never
  falls back to a system `openssl`, so it cannot misidentify which library is in
  use.

The exact banner printed by `qudossl version` (line 1's base version and the
final line are read from the real binary, so they can never drift from the
installed OpenSSL):

```
QudoSSL 1.0.0 (OpenSSL 3.5.7 base)
Copyright (c) ZENV Quantum Private Limited. Apache License 2.0.
Commercial build of unmodified upstream OpenSSL 3.5.7 LTS.
Post-quantum TLS 1.3: ML-KEM (FIPS 203) hybrid key exchange.
FIPS module: OpenSSL FIPS Provider  ·  https://zenv.ai/qudossl
OpenSSL 3.5.7 9 Jun 2026 (Library: OpenSSL 3.5.7 9 Jun 2026)
```

The product version (`QudoSSL 1.0.0`) and the OpenSSL base version (`3.5.7`,
release 9 Jun 2026) are kept distinct. `VERSION.dat` remains exactly upstream:
`MAJOR=3 MINOR=5 PATCH=7`, no `PRE_RELEASE_TAG`, no `BUILD_METADATA`,
`RELEASE_DATE="9 Jun 2026"`, `SHLIB_VERSION=3`.

## Consequences

- **The pristine invariant is preserved.** No file under `openssl/` is edited to
  achieve branding; `verify-pristine` stays meaningful
  ([ADR-0001](ADR-0001-unmodified-upstream.md)).
- **Audits see the truth.** `qudossl version` still falls through to the
  unchanged upstream `openssl version` line, so anything parsing that line reads
  plain `OpenSSL 3.5.7 9 Jun 2026`; an auditor can invoke `openssl` directly and
  see the genuine binary.
- **Scripts port across editions.** The `qudossl` name matches Community, so
  customer scripts and demos run unchanged on either edition.
- **The FIPS module source is untouched**, avoiding the certification and
  integrity consequences of editing manifest files
  ([ADR-0003](ADR-0003-fips-via-openssl-provider.md)).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
