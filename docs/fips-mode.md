# FIPS mode — QudoSSL Commercial

*Author: ZENV Quantum · 2026-08-20*

This document describes the FIPS-mode posture of QudoSSL Commercial in full: what
"FIPS mode" means for this build, how to prove the FIPS provider is actually
active, which algorithms and post-quantum groups it exposes, and the
misconfigurations that silently drop you out of FIPS mode without any error.

QudoSSL Commercial is unmodified upstream **OpenSSL 3.5.7 LTS** (see `CLAUDE.md`
and `docs/adr/ADR-0001-unmodified-upstream.md`). Its FIPS module is OpenSSL's
own — `fips.so` / `fips.dylib` / `fips.dll` — not a ZENV module. There is no
ZENV cryptography in this repository.

---

## The one thing to get right: FIPS mode is not CMVP validation

> **This artefact runs in FIPS mode. It is not a CMVP-validated module, and it
> carries no CMVP certificate.**
>
> "FIPS mode" and "FIPS validated" are different claims, and only the first is
> true here. FIPS mode is a *runtime configuration*: the OpenSSL FIPS provider
> is loaded, its power-on self-tests pass, and cryptographic operations are
> routed through it with `default_properties = fips=yes`. CMVP validation is a
> *certification of one specific vendor build and cryptographic boundary*,
> awarded by the CMVP against a particular tested artefact.
>
> **A module you compile yourself from source is not the validated module —
> even when the source corresponds to a validated one.** The CMVP validates the
> exact build that a vendor submitted, on the exact operational environments
> that were tested, with an integrity check over that exact binary. Rebuilding
> the same source with a different compiler, on a different OS, with different
> flags, produces a different artefact that was never tested and is therefore
> outside the certificate. That is precisely what this repository does: it
> builds the FIPS provider from upstream source on your platform.

Correct ways to describe this build:

- "runs in FIPS mode"
- "uses the OpenSSL FIPS provider"
- "not a CMVP-validated module"

Never describe it as "FIPS validated", "FIPS certified", or "FIPS 140-3
certified", and never cite a CMVP certificate number for this artefact — none
applies to it. See `docs/adr/ADR-0005-no-cmvp-submission.md` for the decision
record.

> **If your compliance regime requires a validated module,** FIPS mode on this
> build does not satisfy it on its own. You must obtain a CMVP-certificated
> build and operate it within the scope of that certificate, under your own
> compliance process. QudoSSL Commercial gives you a reproducible, supported
> build that *runs in FIPS mode* using upstream's FIPS provider; it does not
> confer anyone else's certificate, and it cannot.

This is a legal distinction, not a stylistic one. The rest of this document is
about operating FIPS mode correctly; none of it changes the paragraph above.

---

## What "FIPS mode" means in this build

FIPS mode is active when three things are true in the running process:

1. **The FIPS provider is loaded** alongside the base provider. `list
   -providers` shows both `base` and `fips`.
2. **Its self-tests have passed.** `openssl fipsinstall` runs the module's
   power-on self-tests (POST) and known-answer tests once and records the
   result — together with an integrity MAC over the module — in
   `fipsmodule.cnf`. The provider re-checks integrity and runs POST on every
   load; a failure means the provider refuses to load, not that it loads
   degraded.
3. **Algorithms are fetched from the FIPS provider by default.** The active
   configuration sets `default_properties = fips=yes` in `[algorithm_sect]`, so
   an implicit algorithm fetch resolves to the FIPS implementation, and an
   algorithm the FIPS provider does not offer (MD5, ChaCha20-Poly1305, …) is
   simply unavailable rather than served from a non-FIPS provider.

The activating configuration — produced in `docs/crypto-officer-guide.md` and
the README — has this shape:

```ini
openssl_conf = openssl_init
.include /opt/qudossl/ssl/fipsmodule.cnf   # absolute path, see below

[openssl_init]
providers   = provider_sect
alg_section = algorithm_sect

[provider_sect]
fips = fips_sect          # from the .include above
base = base_sect          # encoders/decoders — without it, keys/certs won't read

[base_sect]
activate = 1

[algorithm_sect]
default_properties = fips=yes
```

`fips=yes` is the switch that makes this "FIPS mode" rather than "the FIPS
provider happens to be loaded". Without it, both providers are present and a
default fetch could resolve to a non-approved implementation.

---

## Proving FIPS is active

Verify by measurement, never by assumption. Every command here is reproducible
on a real install; run them in the *same shell* that has `OPENSSL_CONF` and
`OPENSSL_MODULES` exported.

**1 — Both providers present, FIPS included:**

```sh
qudossl list -providers
```
```
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider
```

If you see only `default`, FIPS mode is **not** active — jump to
*Misconfigurations* below. `default` appearing at all is itself the tell: the
FIPS configuration does not activate the default provider.

**2 — The FIPS provider reports itself active:**

```sh
qudossl list -providers -verbose
```

Read the `status: active` line under `fips`. `-verbose` also prints the
provider's build details, which is useful when recording exactly what an
environment is running.

**3 — A non-approved algorithm is refused (negative proof):**

```sh
printf 'x' | qudossl dgst -md5
```
```
... dgst: Unsupported algorithm: MD5
```

In FIPS mode MD5 is not fetchable, so this fails. If it instead prints a digest,
some non-FIPS provider is serving it and you are not in FIPS mode. (MD5 is a
convenient probe because it is memorable and unambiguously non-approved; the
same holds for any algorithm the FIPS provider does not offer.)

**4 — An approved operation succeeds:**

```sh
qudossl rand -hex 16      # DRBG from the FIPS provider
printf 'x' | qudossl dgst -sha256
```

Both must work; SHA-256 and the DRBG are approved.

> Run these checks *after every configuration change and in every new
> environment*, including under process managers and containers. The failure
> modes in the next section produce a process that looks fine but is not in FIPS
> mode, so a positive result from step 1 is the only thing that settles it.

---

## Approved algorithms

The authoritative list of what this build treats as approved is exactly what the
FIPS provider exposes. Enumerate it directly rather than trusting a printed
table:

```sh
qudossl list -digest-algorithms   -provider fips
qudossl list -cipher-algorithms   -provider fips
qudossl list -signature-algorithms -provider fips
qudossl list -kem-algorithms      -provider fips
qudossl list -key-exchange-algorithms -provider fips
```

Representative of what the OpenSSL 3.5.7 FIPS provider offers:

| Family | Examples |
|---|---|
| Block cipher / AEAD | AES-128/192/256 in ECB, CBC, CTR, GCM, CCM, XTS, KW |
| Hash | SHA-1 (legacy verify), SHA-2, SHA-3, SHAKE |
| MAC | HMAC, KMAC, CMAC, GMAC |
| DRBG | CTR-DRBG, Hash-DRBG, HMAC-DRBG |
| Signature (classical) | RSA, ECDSA, EdDSA (Ed25519 / Ed448) |
| Key agreement (classical) | ECDH, DH (safe-prime / FFC groups) |
| KDF | TLS 1.3 KDF, HKDF, PBKDF2, KBKDF, SSKDF, X9.63 |
| Post-quantum KEM | **ML-KEM** (FIPS 203) — the six TLS groups below |
| Post-quantum signature | **ML-DSA** (FIPS 204), **SLH-DSA** (FIPS 205) |

ML-KEM, ML-DSA and SLH-DSA are **OpenSSL's own implementations**, present in
upstream 3.5.7. None of the post-quantum mathematics in this product is ZENV's.

> **Notably absent under FIPS: ChaCha20-Poly1305.** It is not an approved
> algorithm, so the FIPS provider does not offer it and it cannot be selected
> for a TLS 1.3 ciphersuite in FIPS mode. This is expected, not a defect. If a
> handshake needs ChaCha20-Poly1305, that endpoint is not operating in FIPS
> mode.

---

## Post-quantum TLS groups in FIPS mode

Upstream 3.5.7 ships six ML-KEM key-exchange groups, and **all six are available
in FIPS mode**:

| TLS group | Construction | Kind |
|---|---|---|
| `MLKEM512` | ML-KEM-512 | pure ML-KEM |
| `MLKEM768` | ML-KEM-768 | pure ML-KEM |
| `MLKEM1024` | ML-KEM-1024 | pure ML-KEM |
| `SecP256r1MLKEM768` | ECDH P-256 + ML-KEM-768 | hybrid |
| `X25519MLKEM768` | X25519 + ML-KEM-768 | hybrid |
| `SecP384r1MLKEM1024` | ECDH P-384 + ML-KEM-1024 | hybrid |

Enumerate them on the install:

```sh
qudossl list -tls-groups | tr ':' '\n' | grep -i mlkem
```
```
MLKEM512  MLKEM768  MLKEM1024
SecP256r1MLKEM768  X25519MLKEM768  SecP384r1MLKEM1024
```

A worked end-to-end handshake (server + client on this build, FIPS mode) is in
the README and `docs/crypto-officer-guide.md`.

### Standalone X25519 vs the X25519 hybrid

This distinction trips people up, so state it plainly:

- **`x25519` is *not* offered as a standalone TLS group in FIPS mode.** X25519
  on its own is not an approved key-establishment method.
- **`X25519MLKEM768` *is* offered.** The hybrid combines X25519 with ML-KEM-768,
  and the hybrid is an approved key-establishment construction — the shared
  secret is derived from the ML-KEM component together with the X25519
  component, and it is the construction that is approved, not X25519 alone.

So the presence of `X25519MLKEM768` in the group list is not a contradiction of
`x25519`'s absence. The same reasoning is why the `SecP256r1MLKEM768` and
`SecP384r1MLKEM1024` ECDH hybrids appear: the classical half is carried inside
an approved hybrid, not offered as a standalone approved group.

---

## Misconfigurations that silently disable FIPS

The dangerous property of every failure below is that it **fails open, not
closed**: the process starts, commands run, and nothing errors — but the FIPS
provider was never loaded, and cryptography ran through a non-FIPS path. There
is no warning to catch. The only defence is to run the *Proving FIPS is active*
checks after any change.

**1 — A literal `$PREFIX` on the `.include` line.**

OpenSSL's config parser does **not** expand shell variables. If the FIPS config
was written with a *quoted* heredoc delimiter (`<<'EOF'`), the line
`.include $PREFIX/ssl/fipsmodule.cnf` is stored verbatim, the include silently
fails to resolve, the `fips` provider section is never defined, and `list
-providers` shows only `default`. Write the config with an **unquoted**
delimiter (`<<EOF`) so `$PREFIX` expands *as the file is written*, then confirm:

```sh
grep '\.include' "$OPENSSL_CONF"
# .include /opt/qudossl/ssl/fipsmodule.cnf   <- absolute path, no literal $PREFIX
```

**2 — `OPENSSL_MODULES` not exported (or pointing at the wrong directory).**

The config names the FIPS provider, but the runtime still has to *find*
`fips.so` / `fips.dylib` / `fips.dll` on disk. If `OPENSSL_MODULES` is unset or
wrong, the module can't be located and the provider does not come up. Export it
alongside `OPENSSL_CONF`, in the same shell:

```sh
export OPENSSL_CONF="$PREFIX/ssl/qudossl-fips.cnf"
export OPENSSL_MODULES="$PREFIX/lib/ossl-modules"
```

Both variables are per-process. A new terminal, a different user, a service
started by systemd, or a container that doesn't inherit them is **not** in FIPS
mode until they are set in that context.

**3 — `sudo`.**

`sudo` sanitises the environment: it resets `PATH` and drops `OPENSSL_CONF` and
`OPENSSL_MODULES` (they are not on its default `env_keep` list). So `sudo
qudossl …` may find a different `openssl` and, crucially, runs **without the
FIPS configuration** — no FIPS provider, no error. If you must run privileged,
pass the full paths and preserve the variables explicitly:

```sh
sudo env \
  OPENSSL_CONF="$OPENSSL_CONF" \
  OPENSSL_MODULES="$OPENSSL_MODULES" \
  "$PREFIX/bin/qudossl" list -providers
```

Then re-verify with the proof commands — do not assume the `env` passthrough
worked.

| Symptom | Cause | Fix |
|---|---|---|
| `list -providers` shows only `default` | `OPENSSL_CONF`/`OPENSSL_MODULES` not set in this shell, or literal `$PREFIX` in the `.include`, or running under `sudo` | Export both in this shell; regenerate the config with an unquoted heredoc; use the `sudo env` form |
| MD5 / ChaCha20 unexpectedly *works* | A non-FIPS provider is active — you are not in FIPS mode | Fix the configuration; re-run the proof checks |
| Provider loads but keys/certs won't read | `base` provider not activated | Add `[base_sect] activate = 1` |
| Works interactively, not under a service/container | Env vars not inherited by that context | Set `OPENSSL_CONF`/`OPENSSL_MODULES` in the unit/image environment |

---

## Summary

- This build **runs in FIPS mode** using OpenSSL's own FIPS provider; it is
  **not a CMVP-validated module** and carries no certificate. A source build is
  not the validated artefact even when the source corresponds to one. A
  requirement for a validated module must be met by a CMVP-certificated build
  under your own compliance process.
- FIPS mode is active only when `list -providers` shows `base` **and** `fips`,
  self-tests have passed, and `default_properties = fips=yes` is set. Prove it
  by measurement every time.
- The FIPS provider offers the approved algorithm set including ML-KEM (FIPS
  203), ML-DSA (FIPS 204) and SLH-DSA (FIPS 205) — all OpenSSL's own. All six
  ML-KEM TLS groups are available; ChaCha20-Poly1305 is not.
- Standalone `x25519` is not an approved group; the hybrid `X25519MLKEM768` is.
- The common ways to silently leave FIPS mode — a literal `$PREFIX` in the
  `.include`, a missing `OPENSSL_MODULES`, and `sudo` — all fail open, so the
  proof checks are the only reliable safeguard.

## See also

- `docs/crypto-officer-guide.md` — the full operator procedure for standing up
  FIPS mode and running a post-quantum handshake.
- `docs/adr/ADR-0003-fips-via-openssl-provider.md` — why FIPS is provided by
  OpenSSL's own provider, with no ZENV module.
- `docs/adr/ADR-0005-no-cmvp-submission.md` — the decision not to submit this
  artefact for CMVP validation, and what that means for customers.
- `docs/qudossl-commercial-current-state.md` — current product and support
  posture.
- `README.md`, `CLAUDE.md` — product overview and the accuracy rules that govern
  every FIPS claim in this repository.
