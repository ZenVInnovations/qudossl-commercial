# Patch Management Policy

**QudoSSL Commercial** · maintenance and security-fix policy
Date: 2026-08-20 · Author: ZENV Quantum

---

## Policy in one sentence

QudoSSL Commercial is **not forked and not patched**. Security fixes reach
customers by **re-vendoring a later upstream OpenSSL 3.5.x LTS tag**, rebuilt
reproducibly, re-verified pristine, re-checked for zero `QUDO` symbols, and
re-released.

That is the whole maintenance model. Everything below explains how ZENV
operates it.

---

## Why there is no local patch

The product's value is the build, the provenance and the support — **not
modified code**. `openssl/` is a git subtree pinned byte-for-byte to the
upstream `openssl-3.5.7` tag, and a customer's security team can diff it against
the public OpenSSL tree and find nothing changed. A single local patch — even a
one-line "obvious" security fix — would break that proposition and would fail
the pristine gate:

```sh
make -C build verify-pristine
```
```
==> checking openssl/ carries no vendor modifications
  OK — openssl/ is unmodified upstream
```

`verify-pristine` must stay green on every release. It is not advisory; it is
the contract. The consequence is deliberate and worth stating plainly:

> **ZENV does not ship private source hotfixes.** Because we never fork, we
> cannot deliver a source-level fix *ahead of* upstream. When a fix is needed,
> our lever is the upstream release plus, in the interim, configuration-level
> mitigation and advisory guidance — never a local edit to `openssl/`. This
> trade is intentional: an unforkable tree is auditable; a privately patched one
> is not.

Fixes go **upstream**, and we re-vendor. See
[`docs/upstream-defects.md`](upstream-defects.md) for the same posture applied
to known non-security defects.

---

## Monitoring: what ZENV watches

| Source | What it tells us |
|---|---|
| `openssl-announce` mailing list | Pre-notification of forthcoming security releases — severity and release date, ahead of the fix landing |
| OpenSSL vulnerabilities page (`openssl.org/news/vulnerabilities.html`) | Published advisories, affected version ranges, CVE identifiers, fixed-in versions |
| OpenSSL release-strategy page | The 3.5 LTS support window and patch cadence |
| Public CVE / NVD feeds and git commit stream | Corroboration and early signal on issues not yet formally advised |

**LTS cadence.** OpenSSL 3.5 is a **Long-Term-Support** series; regular patch
releases (`3.5.x`) roll up fixes on OpenSSL's published schedule, and security
releases are issued out of band when severity warrants. ZENV tracks the 3.5 LTS
line for as long as upstream supports it; the authoritative end-of-life date is
the one OpenSSL publishes on its release-strategy page, not a date invented
here. When upstream moves the recommended LTS baseline, migration guidance is a
support deliverable — it is *not* an automatic re-vendor, because moving minor
series can change behaviour and must be a decision, not a side effect.

> We do not invent CVE numbers or fixed-in versions in ZENV documentation. A
> customer advisory always cites the upstream advisory and its own identifiers
> verbatim.

---

## Severity triage and response commitment

ZENV triages each relevant upstream advisory against the versions customers
actually run, using OpenSSL's own severity classification. The tiers below
describe the **process and intent** of the commercial support relationship. The
hour figures are **illustrative defaults**, not binding contractual terms — the
committed windows for any given customer are whatever their support agreement
states.

| Upstream severity | ZENV response tier | Illustrative default target (see note) |
|---|---|---|
| **Critical** | Out-of-band: acknowledge, assess exposure, mitigate, re-vendor on an accelerated track | Acknowledge same business day; re-vendored build in the shortest practical window once an upstream fix exists |
| **High** | Prioritised re-vendor at the next opportunity, ahead of routine work | Acknowledge within one business day; build to follow promptly |
| **Moderate** | Folded into the next scheduled re-vendor | Included in the next routine LTS roll-up |
| **Low** | Batched; noted in release notes | Next convenient re-vendor |

> **These numbers are defaults for illustration only.** They are not an SLA in
> themselves. Actual response and resolution windows are governed solely by the
> customer's support agreement. Nothing in this document creates a contractual
> commitment.

Triage output for each advisory is a short customer-facing note: does it affect
your deployed version and configuration, what is the exposure, is there a
configuration mitigation available now, and when will the re-vendored build
land.

---

## The re-vendor workflow

This is the only way a fix enters the product. Every step is a gate; a failure
at any step stops the release.

**1 — Select the target tag.** Choose the later `3.5.x` LTS tag from
`github.com/openssl/openssl` that carries the fix. Confirm the fix is present in
that tag (upstream advisory "fixed in" line), and that the tag is on the 3.5 LTS
line — we do **not** jump minor series to pick up a fix.

**2 — Re-vendor the subtree.** Update the `openssl/` subtree to the new tag as a
single squashed vendor commit, the same shape as the original vendor commit
`b1eb2c8`. The exact incantation and the pin record live in
[`docs/subtree-pins.md`](subtree-pins.md); `openssl/` is the one library subtree,
sourced from `https://github.com/openssl/openssl`. (The 3.5.4 FIPS-module source is
a separate, frozen submodule — [ADR-0007](adr/ADR-0007-fips-submodule-thin-fork.md)
— and is **not** re-vendored on library updates.) This is a re-vendor, not a merge
of local changes — nothing ZENV-authored lands in `openssl/`.

**3 — Prove the tree is still pristine.**

```sh
make -C build verify-pristine
# OK — openssl/ is unmodified upstream
```

**4 — Reproducible build.** Rebuild from the new tag using the fixed `Configure`
line held in `build/Makefile`, following
[`docs/reproducibility.md`](reproducibility.md) so the artefact is byte-stable
across the four platforms (Linux x86-64, Linux aarch64, macOS arm64, Windows
x64).

```sh
make -C build all      PREFIX="$PREFIX"
make -C build install  PREFIX="$PREFIX"
make -C build install_fips PREFIX="$PREFIX"
```

**5 — Run the release gates.** All must pass:

```sh
# a) zero vendor cryptography in the artefact — ZERO is the pass condition
nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO
# 0

# b) the base version reports plain upstream (updated to the new tag)
openssl version
# OpenSSL 3.5.x <date>

# c) providers are OpenSSL's own — no ZENV-branded module
openssl list -providers
#   base   name: OpenSSL Base Provider
#   fips   name: OpenSSL FIPS Provider

# d) the six ML-KEM TLS groups are present in FIPS mode
qudossl list -tls-groups | tr ':' '\n' | grep -i mlkem
```

The banking-lab container build runs the same gates during its image build —
`verify-pristine`, a platform check, zero `QUDO` symbols, `ldd` resolving
`libssl`/`libcrypto` only from the install prefix, and the provider/ML-KEM
check — so the re-vendor is validated in a clean environment, not only on a
maintainer's laptop.

**6 — Update the banner, the pin and the SBOM.** Bump the OpenSSL base in the
`qudossl` banner and in `VERSION.dat` to the new tag (the base moves; the
**product** version — `QudoSSL 1.0.0` — bumps on ZENV's own cadence and stays
distinct from the OpenSSL base). Record the new pin in
[`docs/subtree-pins.md`](subtree-pins.md) and refresh `docs/sbom-inventory.md`.

**7 — Tag and release.** Cut the release on the release branch and tag it per
[`docs/branching.md`](branching.md). Ship customer release notes that cite the
upstream advisory and its CVE identifiers verbatim.

> The re-vendored build **is not** a CMVP-validated module, and re-vendoring
> does not make it one — it runs in FIPS mode using OpenSSL's own FIPS provider.
> Never describe a re-vendored release as "validated" or "certified", and never
> attach a CMVP certificate number to it.

---

## Emergency / out-of-band process

For a **Critical** advisory, the routine cadence is bypassed:

1. **Acknowledge and scope** — same business day: which customers, which
   deployed versions and configurations are exposed.
2. **Mitigate now, at configuration level.** Where the exposure is in an
   algorithm, group or protocol path that a customer does not require, ship a
   configuration change that closes it (for example, removing an affected group
   from the process-wide `Groups` line, or disabling an affected protocol
   version) — no source edit, no fork. This is the only fix we can deliver
   before upstream does.
3. **Re-vendor the moment an upstream fix exists.** When OpenSSL publishes the
   emergency `3.5.x` tag, run the full re-vendor workflow above on an
   accelerated track and release out of band.

> **If upstream has not yet released, we do not have a source fix — and we say
> so.** ZENV's role in that window is monitoring, honest exposure assessment,
> and configuration mitigation. Manufacturing a private patch would break the
> pristine invariant and the audit story customers bought. We do not do it.

---

## Commercial relationship vs self-serving from upstream

Everything in `openssl/` is upstream OpenSSL under Apache-2.0. A team can fetch
the same tag from `github.com/openssl/openssl` and build it themselves for free.
What the commercial relationship provides is the work **around** that source:

| | Self-serve from upstream | QudoSSL Commercial |
|---|---|---|
| Watching advisories / pre-notifications | You do it | ZENV does it, and triages against *your* deployed version |
| Severity assessment for your config | You do it | Delivered as a customer-facing note per advisory |
| The rebuilt artefact | You build it | Rebuilt reproducibly, on a schedule, across four platforms |
| Provenance | You establish it | `verify-pristine` green, zero `QUDO` symbols proven, SBOM refreshed each release |
| Cross-platform testing | You do it | Linux x86-64 / aarch64, macOS arm64, Windows x64 |
| Response commitment | None | Governed by your support agreement |
| Migration guidance on the LTS line | You research it | A support deliverable |

The proposition is **provenance and support around unmodified upstream**, not a
more capable or premium build. QudoSSL Commercial is not a tier of, an upgrade
to, or a comparison against QudoSSL Community — Community is a different product
that delegates its PQC mathematics to ZENV's own engine and ships its own FIPS
module. This product carries none of that and is maintained by re-vendoring
alone.

---

## Related documents

- [`docs/subtree-pins.md`](subtree-pins.md) — the pinned `openssl` subtree, its
  source and the exact re-vendor incantation.
- [`docs/reproducibility.md`](reproducibility.md) — reproducible-build method the
  re-vendor step relies on.
- [`docs/branching.md`](branching.md) — branch model and the release/re-vendor
  flow steps 6–7 refer to.
- [`docs/upstream-defects.md`](upstream-defects.md) — known upstream issues and
  the "we don't fork-patch" posture applied beyond security fixes.
