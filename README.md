# QudoSSL Commercial

Upstream **OpenSSL 3.5.7 LTS**, exactly as published — built, packaged and
supported by ZENV Quantum, and driven through the same `qudossl` CLI as QudoSSL
Community.

This repository contains no ZENV cryptography. The ML-KEM, ML-DSA and SLH-DSA
implementations are OpenSSL's own, and a security team can diff `openssl/`
against the public upstream tree and find nothing changed. What the product
provides is the build, the provenance and the support — not modified code.

---

## What this is, and what it is not

| | |
|---|---|
| **Is** | A reproducible, supported build of unmodified upstream OpenSSL 3.5.7 |
| **Is** | Post-quantum capable today — ML-KEM key exchange and ML-DSA certificates are in upstream 3.5.7 |
| **Is** | Driven by the `qudossl` command, so scripts and demos written for QudoSSL work unchanged |
| **Is not** | A fork, a patch set, or a distribution carrying vendor cryptography |
| **Is not** | FIPS 140-3 validated. It runs in **FIPS mode** using the OpenSSL FIPS provider; no CMVP certificate exists for this artefact. Never describe it as *validated*. |
| **Is not** | QudoSSL Community. That is a different product, with ML-KEM and ML-DSA mathematics delegated to ZENV's own engine. The two are not comparable and are not compared. |

---

## Repository layout

```
qudossl-commercial/
├── openssl/            vendored upstream OpenSSL 3.5.7, unmodified (git subtree, tag openssl-3.5.7)
├── openssl-fips/       the 3.5.4 FIPS-module source (git submodule / "thin fork", tag openssl-3.5.4 — ADR-0006/0007);
│                       fetched on demand: git submodule update --init openssl-fips
├── build/
│   ├── Makefile        build wrapper — adds no patches and no cryptography
│   └── qudossl         the QudoSSL CLI: a banner-and-delegate wrapper around the openssl app
├── docs/               engineering, operations and FIPS-mode documentation
├── CLAUDE.md           project instructions and the one invariant (openssl/ stays pristine)
├── LICENSE  NOTICE     Apache-2.0, and the upstream attribution
└── .gitignore          keeps host build products out of the repository
```

`build/Makefile` exists only to keep the `Configure` line in one place. If you
deleted it and ran `./Configure` by hand in `openssl/`, you would get the same
artefacts.

---

## The CLI: `openssl` and `qudossl`

Installing this product puts **two** commands on your prefix's `bin/`:

| | |
|---|---|
| `openssl` | the real binary — behaviour and version string byte-identical to upstream OpenSSL 3.5.7 |
| `qudossl` | a thin wrapper that prints the QudoSSL Commercial banner on `version`, then delegates everything unchanged |

The `qudossl` name is deliberate: a customer's scripts, CI and demos written
against QudoSSL Community keep working here without edits. The wrapper never
patches the binary — see `docs/adr/ADR-0002` for why a wrapper rather than a
rebranded binary.

---

## Build

Requires a C toolchain and perl. **No CMake, and no other dependency** — there
is nothing here to delegate to.

### Get the source

```sh
git clone https://github.com/ZenVInnovations/qudossl-commercial.git
cd qudossl-commercial
```

The `openssl/` libraries come with the clone (a git subtree). The **3.5.4 FIPS
module source is a submodule** — a "thin fork" of upstream OpenSSL, fetched **on
demand**: the FIPS targets (`fips-src`, `install_fips`) run
`git submodule update --init` for you, or fetch it up front with
`make -C build fips-src`. A libraries-only build needs no submodule.

### Build

```sh
export PREFIX=/opt/qudossl            # or "$HOME/qudossl-commercial" for no sudo

make -C build all PREFIX="$PREFIX"     # configure + build the 3.5.7 libraries + app
```

Useful targets:

| Target | Does |
|---|---|
| `all` | configure and build |
| `install` | libraries, headers, both CLI names, and man pages |
| `install_sw` | as above, without ~2000 man pages |
| `fips-src` | fetch the pinned 3.5.4 FIPS submodule (thin fork) — network once |
| `install_fips` | the FIPS module and `fipsmodule.cnf` (fetches the 3.5.4 submodule if not already present) |
| `test` | upstream's own test suite |
| `verify-pristine` | prove the vendored trees carry no vendor modifications |
| `clean` / `distclean` | |

> **Linux: pin the runtime library path.** Distributions ship their own
> `libssl.so.3` under the *same* SONAME, because OpenSSL 3.5.7 is ABI-compatible
> with the 3.x line. Without an RPATH the loader can find the distribution's
> copy first. Build with:
>
> ```sh
> make -C build all PREFIX="$PREFIX" EXTRA_FLAGS="-Wl,-rpath,$PREFIX/lib"
> ```

### The pristine gate

The product's defining property is that nothing was changed, so the build
proves it rather than asserting it:

```sh
$ make -C build verify-pristine
==> checking vendored trees carry no vendor modifications
  note: openssl-fips not materialised — skipped (run 'make fips-src')
  OK — vendored trees are unmodified upstream
```

It greps the four files QudoSSL Community patches in order to delegate its
mathematics — the sharpest available test that a tree is not that one — across
`openssl/` and, once fetched, the `openssl-fips/` submodule. For the submodule it
additionally fails if the working tree differs from its pinned `openssl-3.5.4`
commit.

**Check the artefact too, not only the source.** A pristine tree built against
the wrong archive would pass `verify-pristine` and still be wrong:

```sh
$ nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO
0
```

Zero is the only acceptable answer for this product. (This is the exact
opposite of QudoSSL Community, where a non-zero count is the pass condition —
which is the cleanest one-command way to tell the two editions apart.)

---

## Install and put it on your PATH

```sh
make -C build install_sw PREFIX="$PREFIX"    # libs, headers, openssl + qudossl
make -C build install_fips PREFIX="$PREFIX"  # fips module + fipsmodule.cnf
                                             # first FIPS build fetches the 3.5.4 submodule (network once)
```

`install_sw` skips the ~2000 man pages that `install` would also copy. Use
`sudo` on both if your prefix is outside your home directory.

Put the prefix's `bin/` on your PATH so `qudossl` and `openssl` work as bare
commands:

```sh
export PATH="$PREFIX/bin:$PATH"
which -a qudossl openssl      # both must resolve under $PREFIX/bin first
```

> That directory supplies **both** names, so `openssl` now resolves to this
> build as well. That is the point when migrating an application — but it does
> shadow your distribution's or Homebrew's `openssl` in that shell. These lines
> must come **after** anything else that prepends to `PATH` (on macOS,
> Homebrew's `eval "$(brew shellenv)"` runs from `/etc/zprofile`, before
> `~/.zshrc`).

---

## Verify the install

```sh
qudossl version
```
```
QudoSSL 1.0.0 (OpenSSL 3.5.7 base)
Copyright (c) ZENV Quantum Private Limited. Apache License 2.0.
Commercial build of unmodified upstream OpenSSL 3.5.7 LTS.
Post-quantum TLS 1.3: ML-KEM (FIPS 203) hybrid key exchange.
FIPS module: OpenSSL FIPS Provider  ·  https://zenv.ai/qudossl
OpenSSL 3.5.7 9 Jun 2026 (Library: OpenSSL 3.5.7 9 Jun 2026)
```

The product identifies as **QudoSSL 1.0.0**; the last line is the unchanged
upstream `openssl version` output, so anything parsing it sees plain OpenSSL:

```sh
openssl version
```
```
OpenSSL 3.5.7 9 Jun 2026
```

```sh
openssl list -providers
```
```
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider
```

The providers are **OpenSSL's own** — this build ships no ZENV-branded module.

---

## FIPS mode

The FIPS module's filename differs by platform, so set it once:

```sh
case "$(uname -s)" in
  Darwin) export FIPS_MODULE=fips.dylib ;;
  *)      export FIPS_MODULE=fips.so    ;;   # fips.dll on Windows
esac
```

`make install_fips` **already ran** `fipsinstall` for you — it created
`$PREFIX/ssl/fipsmodule.cnf`, and the module's self-tests reported
`OpenSSL FIPS Provider, version 3.5.4` (the validated boundary, ADR-0006). Run it
by hand only if you installed the module some other way:

```sh
qudossl fipsinstall \
    -module "$PREFIX/lib/ossl-modules/$FIPS_MODULE" \
    -out    "$PREFIX/ssl/fipsmodule.cnf"
# INSTALL PASSED
```

Then write a configuration that activates the `fips` and `base` providers and
sets the post-quantum groups process-wide.

> **Leave the heredoc delimiter unquoted** (`<<EOF`, not `<<'EOF'`) so `$PREFIX`
> on the `.include` line is expanded **as the file is written**. OpenSSL's
> config parser does not expand shell variables; a literal `$PREFIX` leaves the
> FIPS provider inactive with no error at all, and `list -providers` then shows
> only `default` — which looks like success.

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

# base supplies encoders/decoders. Without it, key and certificate
# files cannot be read.
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

### Post-quantum TLS groups

All six, available in FIPS mode:

```sh
qudossl list -tls-groups | tr ':' '\n' | grep -i mlkem
```
```
MLKEM512  MLKEM768  MLKEM1024
SecP256r1MLKEM768  X25519MLKEM768  SecP384r1MLKEM1024
```

ChaCha20-Poly1305 is absent under FIPS because it is not an approved algorithm.
Standalone `x25519` is likewise not offered — but the **hybrid**
`X25519MLKEM768` is, because the hybrid is an approved key-establishment
construction while X25519 alone is not.

---

## A live post-quantum TLS 1.3 handshake

Server and client on this build, FIPS mode, serving a **classical RSA-3072**
certificate:

```sh
cd "$(mktemp -d)"
qudossl req -x509 -new -noenc -newkey rsa:3072 \
    -keyout s.key -out s.crt -days 2 -subj "/CN=localhost" 2>/dev/null

qudossl s_server -cert s.crt -key s.key -accept 4433 -www \
    -groups X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1 &
sleep 2

qudossl s_client -connect 127.0.0.1:4433 -groups X25519MLKEM768 -tls1_3 -brief </dev/null
```
```
CONNECTION ESTABLISHED
Protocol version: TLSv1.3
Ciphersuite: TLS_AES_256_GCM_SHA384
Negotiated TLS1.3 group: X25519MLKEM768      <- post-quantum key exchange
```

Post-quantum key exchange with an unchanged classical certificate: the
certificate and the key exchange are independent parts of TLS, and only the key
exchange is exposed to harvest-now-decrypt-later. Stop the server with
`kill %1`.

> **Reading the output correctly.** `-brief` prints `Negotiated TLS1.3 group:`
> for ML-KEM groups but **not** for classical ones — a classical handshake
> reports `Peer Temp Key: ECDH, prime256v1, 256 bits` instead. Tooling that
> greps only for the first form reports a working classical connection as
> broken.

---

## Test

```sh
env -u OPENSSL_CONF -u OPENSSL_MODULES make -C build test JOBS="$(nproc 2>/dev/null || echo 4)"
```

> **Unset `OPENSSL_CONF` for the test suite.** It builds its own configuration;
> a stray `OPENSSL_CONF` pointing at a FIPS-only file makes password-based and
> legacy-algorithm tests fail (`pkcs8`, `pkcs12`, `x509`, `store`) — every one a
> path FIPS correctly refuses. The failures look like real defects and are not.

And prove the tree is still pristine at any time:

```sh
make -C build verify-pristine
```

---

## Build in a container

The lab images build this tree for Linux and assert their own provenance. See
`qudossl-banking-lab/stack/commercial/Dockerfile`, which runs gates during the
build: `verify-pristine`, a **Linux** platform check on the CLI, **zero** `QUDO`
symbols in `libcrypto.so.3`, `ldd` resolving `libssl`/`libcrypto` only from the
install prefix, and a provider/ML-KEM-groups check.

> **Do not build the container from a tree you have already built on the host.**
> OpenSSL writes architecture-specific files into its own source directories
> (`crypto/buildinf.h` carries a literal `#define PLATFORM ...`), and a macOS
> artefact can make a Linux container report macOS. `.gitignore` and the image's
> `.dockerignore` both exclude these; the platform gate exists to catch any that
> slip through.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `qudossl: command not found` | `$PREFIX/bin` is not on `PATH`, or this shell started before you added it. Re-run the export, or open a new terminal. |
| `openssl version` reports 3.6.x, or `LibreSSL` on macOS | Another `openssl` is earlier on `PATH`. `which -a openssl` — `$PREFIX/bin/openssl` must be first. |
| `sudo qudossl …` → `command not found` | `sudo` resets `PATH`. Give the full path: `sudo "$PREFIX/bin/qudossl" …`. `sudo` also drops `OPENSSL_CONF`, so a sudo'd command runs **without** the FIPS provider. |
| ``version `OPENSSL_3.5.0' not found`` | The loader picked the distribution's `libssl.so.3`. Rebuild with the `-Wl,-rpath` flag above. |
| `list -providers` shows only `default` | `OPENSSL_CONF`/`OPENSSL_MODULES` not exported in *this* shell; the config's `.include` kept a literal `$PREFIX`; or you ran under `sudo`. |
| `make test` fails in `pkcs12` / `store` | An `OPENSSL_CONF` is set. Use the `env -u` form above. |
| `verify-pristine` FAILs | `openssl/` has been modified away from upstream. Restore it: this product must never carry a local patch — see `docs/patch-management-policy.md`. |

---

## Documentation

- `docs/qudossl-commercial-current-state.md` — **living project status**: what
  the product is today, build/CI state, support posture. Start here.
- `docs/crypto-officer-guide.md` — running the OpenSSL FIPS provider correctly.
- `docs/fips-mode.md` — the FIPS-mode posture in full, and why this artefact is
  *not* a validated module.
- `docs/patch-management-policy.md` — how ZENV tracks upstream OpenSSL security
  releases and re-vendors, without ever forking or patching locally.
- `docs/upstream-defects.md` — known upstream issues and the "we don't
  fork-patch" support posture.
- `docs/reproducibility.md`, `docs/subtree-pins.md` — reproducible-build notes
  and the pinned `openssl` subtree.
- `docs/sbom-inventory.md` — the software bill of materials (OpenSSL only).
- `docs/branching.md` — branch model and release/re-vendor flow.
- `docs/adr/` — architecture decision records for this product.

---

## Licence

The contents of `openssl/` are distributed under the Apache License 2.0, as
published by the OpenSSL Project. This repository adds no code under any other
licence. See `LICENSE` and `NOTICE`; upstream attribution in
`openssl/LICENSE.txt` is retained verbatim.
