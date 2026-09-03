# QudoSSL Commercial — Branch & Release Model

_Last updated: 2026-08-20 · ZENV Quantum_

This product's branch model has one job: keep the released line provably
**pristine** and **green** at every point, while giving integration work a place
to land first. There are exactly two long-lived branches and one release
motion. For the underlying invariant see [`../CLAUDE.md`](../CLAUDE.md); for the
pinned source see [`subtree-pins.md`](subtree-pins.md).

---

## Branches

| Branch | Role | Guarantee |
|---|---|---|
| `main` | Released line | Always green and pristine. Every commit builds, passes the gates, and carries `openssl/` byte-for-byte at the pinned upstream tag. Releases are tagged here. |
| `dev` | Integration | Where work — a re-vendor, a build-wrapper change, a docs update — is assembled and proven before it reaches `main`. May be briefly red; `main` never is. |

Nothing lands on `main` except by a merge from `dev` that has already gone
green. Feature or fix work branches off `dev`, merges back to `dev`, and reaches
`main` only through the release flow below.

---

## Release flow

```
work on dev  →  verify-pristine + gates green  →  merge dev → main  →  tag
```

1. **Do the work on `dev`.** Build changes, a docs pass, or a re-vendor of a
   later upstream tag (see below) all integrate here first.
2. **Prove it.** The release gate is the same set the commercial lab image
   asserts (see [`qudossl-commercial-current-state.md`](qudossl-commercial-current-state.md)):

   ```
   make -C build verify-pristine
   nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO   # must print 0
   ```

   `verify-pristine` must pass and the symbol count must be **0** — zero is the
   pass condition, the exact opposite of Community — alongside the build,
   platform, runtime-path and provider/ML-KEM-group checks. If any gate is red,
   it is fixed on `dev`; `main` is never merged red.
3. **Merge `dev` → `main`.** A green, pristine integration state promotes to the
   released line.
4. **Tag the release on `main`.** The merge commit is tagged with a product
   release tag (below). The tag is what customers build from.

---

## Tag scheme

Two distinct tag spaces, kept apart the same way the product and base versions
are kept apart:

| Tag | Namespace | Example | Meaning |
|---|---|---|---|
| Product release | `qudossl-commercial-<major>.<minor>.<patch>` | `qudossl-commercial-1.0.0` | A released state of **this** repository on `main` (product **QudoSSL 1.0.0**). |
| Upstream pin | (recorded, not created here) | `openssl-3.5.7` | The upstream OpenSSL tag `openssl/` is vendored from — an OpenSSL tag, not ours. |

The product release tag names the QudoSSL Commercial artefact; the upstream pin
names the OpenSSL LTS release inside `openssl/`. `qudossl-commercial-1.0.0`
currently carries upstream `openssl-3.5.7`. Do not fold the OpenSSL base version
into the product tag or vice versa.

---

## Re-vendoring a new upstream LTS

The pin is **never** advanced by patching `openssl/` in place — that would break
`verify-pristine` and the diffability that is the whole product. When upstream
ships a later OpenSSL LTS tag, QudoSSL Commercial **re-vendors** it:

1. On `dev`, replace the `openssl/` subtree with the new upstream tag (e.g.
   `openssl-3.5.8`), updating `VERSION.dat`, the subtree pin and the SBOM.
2. Run the full gate set — `verify-pristine` still passes, because the new tree
   is again byte-for-byte upstream.
3. Merge `dev` → `main` and cut a new product release tag (e.g.
   `qudossl-commercial-1.0.1`).

The mechanics and the strict no-local-fork stance are governed by
[`patch-management-policy.md`](patch-management-policy.md); the decision to pin
the tree as a subtree is recorded in
[`adr/ADR-0004-openssl-subtree-tag-3.5.7.md`](adr/ADR-0004-openssl-subtree-tag-3.5.7.md).

---

## There is no cert / CMVP branch here

> **Unlike Community, this product has no certification branch.** QudoSSL
> Commercial pursues **no CMVP submission**, so there is no cert/validation
> branch to maintain, no boundary-freeze branch, and no certificate to track
> against a release. This build **runs in FIPS mode** using OpenSSL's own FIPS
> provider; it is **not a validated module** and must never be called "FIPS
> validated" or "certified". The branch model is therefore just `dev` → `main`
> plus tags — nothing more.

The rationale is recorded in
[`adr/ADR-0005-no-cmvp-submission.md`](adr/ADR-0005-no-cmvp-submission.md); the
no-fork-patch support posture that keeps the released line pristine is in
[`patch-management-policy.md`](patch-management-policy.md).

---

_QudoSSL Commercial · unmodified upstream OpenSSL 3.5.7 LTS · built, packaged
and supported by ZENV Quantum Private Limited · Apache-2.0 ·
<https://zenv.ai/qudossl>_
