# ADR-0008 — Source tarball releases (OpenSSL-style)

## Status

Accepted — 2026-09-07.

## Context

Customers obtain QudoSSL Commercial as a source distribution and build it
themselves (the migration handbook's Phase 1 begins
`tar xf qudossl-commercial-1.0.0-src.tar.*`). We need a release artefact with
OpenSSL's own properties: an immutable tarball cut from a signed tag, with a
checksum and signature, and download-verify-build instructions.

Two repository facts shape the mechanics:

1. `openssl-fips/` is a git **submodule**, and `git archive` emits submodules
   as empty directories. Customers may have no access to the thin-fork
   repository, so the tarball must vendor the 3.5.4 source itself.
2. The trees build **in place**, so the working directory accumulates
   host-specific build products — including, at worst, a stale `fips` module
   built under a foreign configuration. A tarball must be immune to all of it.

## Decision

- **Release from a signed annotated tag on `main`** named
  `qudossl-commercial-X.Y.Z`, matching the wrapper's `QUDO_PRODUCT_VERSION`
  (`make dist` enforces the match and refuses a mismatched tag). No standing
  release branch: `release/X.Y.x` is created **lazily from the tag** when the
  first maintenance / re-vendored release of that line is needed.
- **`make dist` cuts the tarball from git HEADs only** — `git archive` of the
  repository (which carries the 3.5.7 subtree as ordinary tracked content)
  plus `git archive` of the submodule's pinned 3.5.4 commit into
  `openssl-fips/`. Working-tree dirt and stale build artefacts cannot leak,
  and the result is fully self-contained: no git, no submodule access, no
  network needed to build it.
- **Deterministic packing** where the host tar allows: contents get the HEAD
  commit's timestamp (UTC), entries are sorted, ownership is `0:0`. The
  canonical artefact is produced by the release workflow on Linux (GNU tar).
- **A `.sha256` sidecar always; a detached signature on releases.** The
  signing key is held by ZENV release engineering and is *not* stored in CI —
  signing is a manual step on the downloaded artefact.
- **`make dist-verify` is the release gate**: it unpacks the tarball into a
  scratch directory and, with a sanitised environment, runs the handbook's own
  path — `verify-pristine`, build, `install_sw`, `install_fips` — then asserts
  the artefacts by measurement: plain upstream `openssl version` (no
  `+metadata`), `QudoSSL X.Y.Z` from the wrapper, zero `QUDO` symbols in
  libcrypto, an installed FIPS module identifying as `OpenSSL FIPS Provider`
  version `3.5.4` with no vendor stamp or brand, base + fips active under a
  FIPS config, and a TLS 1.3 handshake negotiating `X25519MLKEM768`.
  A tarball that fails any check does not ship.
- **Distribution**: GitHub Release assets on the tag (tarball, `.sha256`,
  signature). Not the portal repository — a ~40 MB source archive does not
  belong in a web repo's history.

## Consequences

- The handbook's "obtain the source distribution from ZENV" step gains a
  concrete artefact with OpenSSL-style verification
  (`shasum -a 256 -c qudossl-commercial-X.Y.Z-src.tar.gz.sha256`).
- `verify-pristine` (sources) is now paired with artefact assertions
  (`install_fips` and `dist-verify`) — the pristine claim is checked at both
  ends of the build, closing the stale-artefact gap this ADR was born from.
- Snapshot tarballs from untagged commits are possible for internal testing
  and are labelled as such by `make dist`; only tagged, verified, signed
  tarballs are customer artefacts.
