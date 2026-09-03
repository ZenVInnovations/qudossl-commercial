# Upstream defects — track, don't fork-patch

**Date:** 2026-08-20 · **Author:** ZENV Quantum

QudoSSL Commercial is unmodified upstream OpenSSL 3.5.7. That invariant is the
product — a security team can diff `openssl/` against the public upstream tree
and find nothing changed, and `make -C build verify-pristine` proves it stays
that way. The invariant is also a constraint on how we respond to problems:
**we never carry a local patch under `openssl/`.**

So when an upstream defect or a rough operational edge turns up, the response is
not a fork-patch. It is:

1. **Track it** — record the issue, its exposure for this product, and the
   upstream status.
2. **Work around it at the operational or configuration layer** where a
   workaround exists — the wrapper, the build recipe, the crypto-officer
   runbook, or the OpenSSL config — never by editing vendored source.
3. **Resolve it by re-vendoring** — when upstream ships a fix in a later
   OpenSSL 3.5.x LTS tag, we re-vendor that tag, and `verify-pristine` plus the
   reproducibility gate re-prove the tree is still pristine.

This is the same posture stated in
[docs/patch-management-policy.md](patch-management-policy.md): fixes go
upstream and come back to us as a new pin, never as a diff we hold privately.
The subtree pin that a given release was built from is recorded in
[docs/subtree-pins.md](subtree-pins.md).

> A corollary worth stating plainly: because there is no ZENV cryptography in
> this repository, none of the items below is a ZENV defect. They are
> operational characteristics of upstream OpenSSL and of running in FIPS mode —
> the behaviour is identical to a stock upstream build of the same tag. We
> document them because a supported product should not make its users
> rediscover them.

## Security advisories (CVEs)

When a genuine CVE is published against OpenSSL 3.5.x, we track it against this
product's pinned tag, note any operational mitigation, and — if the fix lands
in a later 3.5.x LTS release — re-vendor that tag. We do **not** print a CVE
number we have not verified against the advisory. Where this document needs to
refer to a security issue for which we do not have a confirmed identifier in
hand, it describes the **class** of issue rather than inventing a number. The
current pinned tag and its known-advisory status are maintained in
[docs/qudossl-commercial-current-state.md](qudossl-commercial-current-state.md).

## Tracked issues

These are operational characteristics, **not vendor defects**. Each is
reproducible on a real install and is handled at the config/operational layer,
because `openssl/` stays pristine.

| Issue | Nature | Operational handling | Upstream-fix status |
|---|---|---|---|
| OpenSSL config parser does not expand shell/environment variables. A literal `$PREFIX` in a `.include` line is not substituted, and a `.include` whose target file does not exist is **silently skipped** — so a mis-templated FIPS config runs with FIPS quietly not activated. | Config-parser semantics (`crypto/conf/conf_def.c`). Working as designed upstream; the hazard is user expectation, not a bug. | Use an **absolute literal path** to `fipsmodule.cnf` in `.include`, and set `config_diagnostics = 1` so a bad or missing include becomes a hard error instead of a silent no-FIPS run. Covered in [docs/fips-mode.md](fips-mode.md) and [docs/crypto-officer-guide.md](crypto-officer-guide.md). | By design; not a fix candidate. Tracked so operators do not rediscover it. |
| Under `fips = yes`, a bare `x25519` in a `Groups` / `-groups` list makes the **whole list fail to parse**. Standalone X25519 is not an approved key-establishment group in FIPS mode, so libssl rejects the token — and one unknown token fails the entire list, not just that entry. | FIPS policy expressed through TLS group availability. Standalone X25519 is absent by design; the hybrid `X25519MLKEM768` **is** offered (the hybrid is an approved construction). | Never list standalone `x25519` in a FIPS groups string. Use the six approved groups: `MLKEM512`, `MLKEM768`, `MLKEM1024`, `SecP256r1MLKEM768`, `X25519MLKEM768`, `SecP384r1MLKEM1024`. Listed in [docs/fips-mode.md](fips-mode.md). | By design; not a fix candidate. |
| `openssl s_client -brief` (and normal negotiation output) prints `Negotiated TLS1.3 group:` **only** for ML-KEM and ML-KEM-hybrid groups. For a purely classical group it prints `Peer Temp Key: X25519` instead — the same field under a different label. | CLI reporting path in `apps/lib/s_cb.c`: the "Negotiated TLS1.3 group" line is reached only when no classical peer temp key is available, which is exactly the ML-KEM/hybrid case. | Cosmetic. Do not parse `-brief` for a single fixed line to confirm PQC; match on the group **name** (`MLKEM…`, `…MLKEM…`) wherever it appears. Handshake-verification snippets in [docs/crypto-officer-guide.md](crypto-officer-guide.md) match on the name. | Cosmetic upstream behaviour; no fix needed. |
| `crypto/buildinf.h` bakes a **host platform and build-date string** (e.g. `PLATFORM "platform: darwin64-arm64"`, `DATE "built on: …"`) into the compiled library. A tree already built on one host must not seed a build for a different target — the stale string is copied into the artefact. | Generated build metadata, host-specific by design. Not a correctness defect; it is a reproducibility hazard for cross-host / container builds. | Build each target from a clean tree: run `make -C build distclean` (removes `configdata.pm`) before configuring for a new platform, and never copy a host-built `openssl/` into a container build context. The container recipe in `qudossl-banking-lab` builds from a clean checkout for this reason. See [docs/reproducibility.md](reproducibility.md). | By design; managed by build hygiene, not an upstream fix. |

### Reproducing the config-parser gotcha

The parser expands `$name` only against **config-file** variables, never the
process environment, and a missing include is swallowed unless diagnostics are
on:

```sh
# WRONG — $PREFIX is not shell-expanded; if the resolved path does not exist,
# the include is silently skipped and FIPS never activates.
.include $PREFIX/ssl/fipsmodule.cnf

# RIGHT — absolute literal path, plus a hard error on any bad include.
config_diagnostics = 1
.include /opt/qudossl/ssl/fipsmodule.cnf
```

Confirm FIPS actually came up rather than trusting the config loaded:

```sh
openssl list -providers
#   base   name: OpenSSL Base Provider
#   fips   name: OpenSSL FIPS Provider     <- both must be present
```

If only `base` (or only `default`) appears, the `.include` did not resolve.

### Reproducing the platform-string bake-in

```sh
grep -E '^#define (PLATFORM|DATE)' openssl/crypto/buildinf.h
#   #define PLATFORM "platform: darwin64-arm64"
#   #define DATE "built on: <host build time>"
```

The string reflects the host that last built the tree, not the target — which
is why a cross-host or container build must start from `make -C build distclean`.

## What this document is not

- It is not a CVE register with invented numbers. Confirmed advisories are
  tracked against the pinned tag in
  [docs/qudossl-commercial-current-state.md](qudossl-commercial-current-state.md);
  unverified ones are described by class here.
- It is not a patch changelog. There are no local patches — that is the point.
  See [CLAUDE.md](../CLAUDE.md) and
  [docs/patch-management-policy.md](patch-management-policy.md).
- It is not a statement about a validated module. This build **runs in FIPS
  mode** using the OpenSSL FIPS provider; it is **not** a CMVP-validated
  module. See [docs/fips-mode.md](fips-mode.md).
