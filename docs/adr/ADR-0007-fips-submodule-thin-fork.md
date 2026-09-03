# ADR-0007 — Vendor the 3.5.4 FIPS source as a submodule (thin fork), not a subtree

**Status:** Accepted
**Date:** 2026-09-03
**Amends:** [ADR-0004](ADR-0004-openssl-subtree-tag-3.5.7.md) (subtree vendoring) ·
[ADR-0006](ADR-0006-fips-module-3.5.4-boundary.md) (two-tree FIPS split)

## Context

[ADR-0006](ADR-0006-fips-module-3.5.4-boundary.md) introduced a second OpenSSL
tree, `openssl-fips/` at tag `openssl-3.5.4`, to build the FIPS module at the CMVP
validation boundary while the libraries stay at 3.5.7. It described that tree as a
git **subtree**, by analogy with `openssl/` ([ADR-0004](ADR-0004-openssl-subtree-tag-3.5.7.md)).

In practice that never held. `openssl-fips/` was an **untracked ~158 MB local
directory** — `git status` showed `?? openssl-fips/`, zero files tracked. A fresh
`git clone` got the 3.5.7 libraries but **not** the 3.5.4 FIPS source, so
`make fips-module` only worked where that tree happened to already exist on disk.
The "two subtrees" design was documented but not implemented, and it was not
reproducible.

Vendoring 3.5.4 as a full subtree would also commit a near-complete **second copy
of OpenSSL** (~99% identical to the 3.5.7 tree) into the repository — for a module
we build once, freeze at the boundary, and never modify.

## Decision

Vendor the 3.5.4 FIPS source as a **git submodule** pinned to the upstream tag
`openssl-3.5.4` (commit `c1eeb9406b6142148f267594197d853403d10208`), mounted at
`openssl-fips/`. It is a **thin fork**: an unmodified pointer to upstream, never
patched. Only the FIPS module (`fips.so` / `fips.dylib` / `fips.dll`) is built
from it; it runs under the 3.5.7 libraries via provider dispatch — ADR-0006's
boundary decision is unchanged, only *how the 3.5.4 source is carried* changes.

- **`openssl/` stays a git subtree** at `openssl-3.5.7`. It is the product's
  entire cryptographic surface and must be diffable in-repo; a plain clone must
  build the product. None of ADR-0004's reasoning is weakened for it.
- **`openssl-fips/` is a submodule**, materialised on demand
  (`git submodule update --init openssl-fips`, driven by `make fips-src` and the
  FIPS build targets). The repository carries only the pin — `.gitmodules` plus
  the gitlink commit.

## Why a submodule is acceptable here (ADR-0004 argued against one)

ADR-0004 rejected a submodule for `openssl/` because a second fetch can fail or
drift and the pin is a pointer to an external repository. Those concerns are much
weaker for a **frozen, build-once FIPS module**:

- The module is **frozen** at the validated boundary; the source is fetched once
  and never tracks upstream (`--remote` is never used), so there is nothing to
  drift.
- The pin is an **exact commit** recorded in `.gitmodules` and the gitlink;
  upstream release tags are stable, and provenance stays verifiable — the
  materialised tree diffs empty against `openssl-3.5.4`.
- It removes a 158 MB duplicate OpenSSL tree from the repo and, unlike the old
  untracked directory, makes the FIPS source **reproducibly fetchable from a
  clone** — a net improvement over the prior state.

`openssl/` keeps every property ADR-0004 wanted; only the freeze-and-forget FIPS
source, which is never diffed as part of "did we change OpenSSL?", moves to a
submodule.

## Consequences

- **A FIPS build needs the submodule once:** `git submodule update --init
  openssl-fips` (network once). `make fips-src` and the FIPS targets run it
  automatically; an offline builder must have fetched it beforehand. A
  libraries-only build (`make all` / `install`) does **not** need it.
- **`verify-pristine` is submodule-aware.** When the submodule is materialised it
  checks it like before (QUDO markers, empty `BUILD_METADATA`) **and** fails if
  the submodule working tree differs from its pinned commit; when it is not
  checked out it prints a note and skips it rather than silently passing.
- **`.gitmodules` is the second pin record**, alongside the `openssl/` subtree
  pin; see [`../subtree-pins.md`](../subtree-pins.md).
- **No other invariant changes.** Still "runs in FIPS mode", still **not** a
  validated module ([ADR-0003](ADR-0003-fips-via-openssl-provider.md) /
  [ADR-0005](ADR-0005-no-cmvp-submission.md)), still no ZENV cryptography, still
  no custom `FIPS_VENDOR`. The SBOM still lists two OpenSSL versions — 3.5.7
  (libraries, subtree) and 3.5.4 (FIPS module, submodule).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
