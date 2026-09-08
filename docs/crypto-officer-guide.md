# Crypto Officer / User Guide — operating QudoSSL Commercial in FIPS mode

**Product:** QudoSSL Commercial (unmodified upstream OpenSSL 3.5.7 LTS)
**Date:** 2026-08-20 · **Author:** ZENV Quantum

This guide tells the person who installs and configures QudoSSL Commercial, and
the person who runs applications against it, how to bring up and confirm FIPS
mode correctly. It reuses the commands from `README.md` and organises them by
who does what.

> **This is not a CMVP Security Policy.** A Security Policy is a controlled
> document that belongs to a *validated* module and describes that module's
> boundary, approved services and formal roles as certified by CMVP. This
> artefact is **not** a validated module — it runs in FIPS mode using OpenSSL's
> own FIPS provider, and no CMVP certificate exists for a build you produce from
> this source tree. The "roles" below are operational descriptions for running
> this build, not the certified roles of a validated module. For the full
> posture and why this distinction is load-bearing, see `docs/fips-mode.md` and
> `docs/adr/ADR-0003-fips-via-openssl-provider.md`.

---

## 1. Audience and roles

Two operational roles, which may be the same person:

| Role | Does | Reads |
|---|---|---|
| **Crypto Officer** | Installs the build, runs `fipsinstall`, writes and owns the FIPS configuration, confirms the providers are active, responds to self-test failures. | Sections 2–6 |
| **User** | Runs applications (TLS servers/clients, `qudossl`/`openssl` commands) against a host the Crypto Officer has already put into FIPS mode. | Sections 4 and 6 |

These names mirror the everyday language of FIPS operation, but they carry **no
CMVP meaning here** — see the callout above. Nothing in this guide grants this
build a validation it does not have.

Commands are shown with the product CLI `qudossl`; the upstream `openssl` binary
installed alongside behaves identically for every one of them (`qudossl`
delegates unchanged — see `README.md` and
`docs/adr/ADR-0002-wrapper-cli-qudossl.md`).

---

## 2. `fipsinstall` — the Crypto Officer's per-host step

`fipsinstall` runs the FIPS module's **power-on self-tests** once and, on
success, writes `fipsmodule.cnf` — the module's integrity record (its MAC and
install status). It does not modify the module; it records that the module on
this host passed its self-tests.

> **Run it on every host — never copy `fipsmodule.cnf` between machines.**
> Upstream is explicit: *"The FIPS module must have the self tests run, and the
> FIPS module config file output generated on every machine that it is to be
> used on … you must not copy the FIPS module config file output data from one
> machine to another"* ([`README-FIPS.md`][readme-fips]). `fipsmodule.cnf`
> records the MAC of the module **as installed on this host** and the fact that
> *this* host ran the self-tests. A copied file attests to a machine that was
> never tested, and a golden image or container layer that bakes one in ships
> that false attestation to every host built from it. Generate it in the
> per-host provisioning step, not in the image build.

[readme-fips]: https://github.com/openssl/openssl/blob/master/README-FIPS.md

The module filename differs by platform, so set it once:

```sh
case "$(uname -s)" in
  Darwin) export FIPS_MODULE=fips.dylib ;;
  *)      export FIPS_MODULE=fips.so    ;;   # fips.dll on Windows
esac
```

Then:

```sh
qudossl fipsinstall \
    -module "$PREFIX/lib/ossl-modules/$FIPS_MODULE" \
    -out    "$PREFIX/ssl/fipsmodule.cnf" \
    -provider_name fips
# INSTALL PASSED
```

`INSTALL PASSED` is the only acceptable outcome. Anything else is a self-test
failure — see Section 7. `$PREFIX` is your install prefix (default
`/opt/qudossl`); use `sudo` if it is outside your home directory.

---

## 3. The FIPS configuration

Write a configuration that activates the **`fips`** and **`base`** providers,
makes `fips=yes` the default property so callers cannot silently reach a
non-approved implementation, and sets the six post-quantum groups process-wide.

> **Leave the heredoc delimiter unquoted** (`<<EOF`, not `<<'EOF'`) so `$PREFIX`
> on the `.include` line is expanded **as the file is written**. OpenSSL's
> config parser does not expand shell variables; a literal `$PREFIX` leaves the
> FIPS provider inactive with **no error at all**, and `list -providers` then
> shows only `default` — which looks like success. The `.include` path must end
> up **absolute**.

```sh
cat > "$PREFIX/ssl/qudossl-fips.cnf" <<EOF
openssl_conf = openssl_init

.include $PREFIX/ssl/fipsmodule.cnf

[openssl_init]
providers   = provider_sect
alg_section = algorithm_sect
ssl_conf    = ssl_sect

[provider_sect]
fips = fips_sect
base = base_sect

# base supplies encoders/decoders only — no cryptographic algorithms.
# Without it, key and certificate files cannot be read. It does not
# weaken the FIPS posture.
[base_sect]
activate = 1

[algorithm_sect]
default_properties = fips=yes

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
Groups = X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1
MinProtocol = TLSv1.2
EOF
```

Note there is **no `default` provider** in this configuration. Only `fips` and
`base` are activated, so every cryptographic operation is served by the FIPS
provider; `base` contributes only serialization (reading/writing keys and
certificates).

Confirm the include expanded to an absolute path before continuing:

```sh
grep include "$PREFIX/ssl/qudossl-fips.cnf"
# .include /opt/qudossl/ssl/fipsmodule.cnf   <- must NOT show a literal $PREFIX
```

Only then point the environment at it:

```sh
export OPENSSL_CONF="$PREFIX/ssl/qudossl-fips.cnf"
export OPENSSL_MODULES="$PREFIX/lib/ossl-modules"
```

---

## 4. Confirming FIPS mode is active

Anyone — Crypto Officer or User — can verify the current shell is in FIPS mode:

```sh
qudossl list -providers
```
```
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider
```

Both providers must appear, and the FIPS line must read **OpenSSL FIPS
Provider** — this build ships OpenSSL's own module, not a ZENV-branded one.

> **`default` alone means FIPS is not active.** If `list -providers` shows only
> `default`, one of three things is true: `OPENSSL_CONF` / `OPENSSL_MODULES` are
> not exported in *this* shell; the config's `.include` kept a literal `$PREFIX`
> (Section 3); or the command was run under `sudo`, which dropped the
> environment (Section 6). Fix the cause — never proceed on a `default`-only
> result and call it FIPS.

Confirm the post-quantum groups are present:

```sh
qudossl list -tls-groups | tr ':' '\n' | grep -i mlkem
```
```
MLKEM512  MLKEM768  MLKEM1024
SecP256r1MLKEM768  X25519MLKEM768  SecP384r1MLKEM1024
```

---

## 5. Approved algorithm posture

In this configuration every cryptographic operation is served by the OpenSSL
FIPS provider. The approved surface it offers includes:

| Class | Approved in this build |
|---|---|
| Symmetric | AES (CBC, CTR, GCM, and the other approved modes) |
| Hashing | SHA-2 and SHA-3 families |
| MAC | HMAC |
| Random | DRBG (deterministic random bit generation) |
| Signatures (classical) | RSA, ECDSA, EdDSA |
| Signatures (post-quantum) | ML-DSA (FIPS 204) — **upstream OpenSSL's implementation** |
| Key encapsulation (post-quantum) | ML-KEM (FIPS 203) — **upstream OpenSSL's implementation** |
| Signatures (hash-based) | SLH-DSA (FIPS 205, stateless) — **upstream OpenSSL's implementation** |

Every post-quantum algorithm above is **OpenSSL's own code**, vendored
unmodified. QudoSSL Commercial adds no cryptography; none of ML-KEM, ML-DSA or
SLH-DSA is a ZENV implementation. (This is the defining difference from QudoSSL
Community, and the two are never compared.)

What the FIPS provider **refuses**, and what a Crypto Officer should expect to
be unavailable:

- **ChaCha20-Poly1305 is absent** under FIPS — it is not an approved algorithm.
  A TLS 1.3 handshake will negotiate an AES-GCM ciphersuite instead.
- **Standalone `x25519` is not offered as a TLS group.** The **hybrid**
  `X25519MLKEM768` *is* offered, because the hybrid is an approved
  key-establishment construction while X25519 on its own is not. This is a
  deliberate distinction, not an omission.

The six ML-KEM TLS groups available in FIPS mode are `MLKEM512`, `MLKEM768`,
`MLKEM1024`, `SecP256r1MLKEM768`, `X25519MLKEM768` and `SecP384r1MLKEM1024`.

---

## 6. Operational cautions

These bite Users and Crypto Officers alike.

> **`OPENSSL_CONF` is process-wide and host-wide.** Exporting it in a shell
> changes the configuration for **every** `openssl` and `qudossl` invocation in
> that shell — including any other application on the host that spawns them.
> Scope it deliberately (a dedicated shell, a service unit's environment, a
> wrapper script), not in a global profile that every unrelated tool inherits.

> **`sudo` drops the environment.** A `sudo qudossl …` command runs **without**
> `OPENSSL_CONF` and `OPENSSL_MODULES`, so it runs **without the FIPS
> provider** — `list -providers` under `sudo` will show only `default`. `sudo`
> also resets `PATH`, so give the full path and pass the variables explicitly
> when you must elevate:
>
> ```sh
> sudo env OPENSSL_CONF="$OPENSSL_CONF" OPENSSL_MODULES="$OPENSSL_MODULES" \
>     "$PREFIX/bin/qudossl" list -providers
> ```

> **Do not set `OPENSSL_CONF` when running the upstream test suite.** It builds
> its own configuration; a stray FIPS-only `OPENSSL_CONF` makes password-based
> and legacy-algorithm tests fail on paths FIPS correctly refuses. Use the
> `env -u OPENSSL_CONF -u OPENSSL_MODULES …` form from `README.md`.

---

## 7. Power-on self-tests and self-test failure

The FIPS module runs power-on self-tests — a module integrity check plus
known-answer tests for its algorithms. `fipsinstall` (Section 2) exercises them
once and records the result in `fipsmodule.cnf`; the integrity check also runs
each time the provider is loaded into a process.

A self-test failure means the module refuses to initialise — `fipsinstall`
prints something other than `INSTALL PASSED`, or a later command errors when the
FIPS provider fails to load. The correct response:

1. **Do not edit `fipsmodule.cnf`** to force the MAC or install status. Hand-
   editing the integrity record to make a failing module load defeats the
   entire self-test mechanism.
2. **Do not patch `openssl/`.** The tree must stay byte-for-byte upstream — the
   product invariant, proved by `make -C build verify-pristine` (see `CLAUDE.md`
   and `docs/patch-management-policy.md`). A self-test failure is never fixed by
   changing the source.
3. **Rebuild the module from the pristine tree and re-run `fipsinstall`.** A
   corrupted or truncated `fips` module, or a `fipsmodule.cnf` that no longer
   matches the module on disk, is the usual cause. Rebuild
   (`make -C build all`), reinstall (`make -C build install_fips`) and repeat
   Section 2. If `INSTALL PASSED` still does not appear, the host or toolchain is
   suspect — escalate to ZENV support rather than working around it.

Never mask a self-test failure. A module that will not pass its self-tests is
not operating in FIPS mode, and no configuration change makes it do so.

---

## 8. What this guide is not

Once more, plainly: this is an **operations guide**, not a CMVP Security Policy.
It describes how to run QudoSSL Commercial's FIPS mode using the OpenSSL FIPS
provider. It does not — and cannot — confer validation. This artefact is not
CMVP-validated, must never be described as "FIPS validated" or "certified", and
carries no CMVP certificate number. For the complete posture, read
`docs/fips-mode.md` and `docs/adr/ADR-0003-fips-via-openssl-provider.md`.
