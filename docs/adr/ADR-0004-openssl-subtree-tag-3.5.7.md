# ADR-0004 — Vendor OpenSSL as a git subtree pinned to tag `openssl-3.5.7`

**Status:** Accepted — applies to `openssl/`. The separate 3.5.4 FIPS-module
source is vendored as a submodule instead (a "thin fork"), see
[ADR-0007](ADR-0007-fips-submodule-thin-fork.md).
**Date:** 2026-08-20

## Context

The product's source has to be pinned to a single, verifiable upstream release
and be trivially auditable. Several mechanisms could carry the OpenSSL source
into this repository:

- a **git submodule** — a pointer to an external repository, fetched
  separately;
- a **tracking branch** — following a moving upstream branch;
- a **fork** — a ZENV-owned copy of OpenSSL that could diverge;
- a **git subtree** — the upstream files committed directly into this
  repository at a chosen ref.

A submodule adds a second fetch that can fail or drift and depends on an
external pointer that could be re-tagged or force-pushed elsewhere. A tracking
branch has no stable pin at all. A fork invites local divergence — the exact
thing this product forbids ([ADR-0001](ADR-0001-unmodified-upstream.md)). None
of these give the clean "clone this repo, get exactly what builds" property the
proposition needs.

## Decision

Vendor `openssl/` as a single **git subtree**, pinned to the upstream tag
`openssl-3.5.7`. The upstream tree's files are committed directly into this
repository — source `https://github.com/openssl/openssl`, vendored in repo
commit `b1eb2c8` (_"feat: vendor upstream OpenSSL 3.5.7 as the QudoSSL
Commercial source tree"_). It is **not** a submodule, **not** a tracking
branch and **not** a fork.

There is exactly **one** subtree: `openssl/`. QudoSSL Community pins two
(`openssl/` and `qudo-pqc-lib/`); this product has no delegated mathematics and
no ZENV cryptographic module, so there is no second subtree to pin.

Updating the pin is never done by patching `openssl/` in place. If upstream
needs a change — a security release, a bug fix — the change goes upstream and
this product **re-vendors a later upstream tag** as a new subtree commit.

## Consequences

- **A plain `git clone` gets everything.** There is no `.gitmodules`, no
  `git submodule update --init`, no second fetch that can fail or drift. What
  you clone is exactly what builds.
- **The pin is a commit in this repo's history**, not a floating pointer in
  another repository that could be re-tagged or force-pushed elsewhere.
- **The tree is diffable against public OpenSSL.** A security team can compare
  `openssl/` against the upstream `openssl-3.5.7` tag and find nothing changed —
  the machine check for this is `verify-pristine`
  ([ADR-0001](ADR-0001-unmodified-upstream.md)).
- **Updates are re-vendors, not patches.** Advancing to a later release replaces
  the subtree commit, `VERSION.dat` values and the SBOM, and nothing else about
  the invariant changes. The mechanics and no-local-fork stance are governed by
  [`../patch-management-policy.md`](../patch-management-policy.md); the pin
  itself is recorded in [`../subtree-pins.md`](../subtree-pins.md), and the full
  provenance story in [`../reproducibility.md`](../reproducibility.md).

---

_Part of the QudoSSL Commercial ADR set — see [README.md](README.md)._
