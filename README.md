# QudoSSL Commercial

Upstream **OpenSSL 3.5.7**, exactly as published — built, packaged and supported
by ZENV Quantum.

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
| **Is not** | A fork, a patch set, or a distribution carrying vendor cryptography |
| **Is not** | FIPS 140-3 validated. It runs in **FIPS mode** using the OpenSSL FIPS provider; no CMVP certificate exists for this artefact. Never describe it as *validated*. |
| **Is not** | QudoSSL Community. That is a different product, with ML-KEM and ML-DSA mathematics delegated to ZENV's own engine. The two are not comparable and are not compared. |

---

## Repository layout

```
qudossl-commercial/
├── openssl/            vendored upstream OpenSSL 3.5.7, unmodified
├── build/
│   ├── Makefile        build wrapper — adds no patches and no cryptography
│   └── qudossl-commercial   branded CLI wrapper around the OpenSSL app
└── .gitignore          keeps host build products out of the repository
```

`build/Makefile` exists only to keep the `Configure` line in one place. If you
deleted it and ran `./Configure` by hand in `openssl/`, you would get the same
artefacts.

---

## Build

Requires a C toolchain and perl. No CMake, and no other dependency — there is
nothing here to delegate to.

```sh
make -C build all      PREFIX=/opt/qudossl-commercial
make -C build install  PREFIX=/opt/qudossl-commercial     # sudo if outside $HOME
```

Useful targets:

| Target | Does |
|---|---|
| `all` | configure and build |
| `install` | libraries, headers, CLI and man pages |
| `install_sw` | as above, without ~2000 man pages |
| `install_fips` | the FIPS module and `fipsmodule.cnf` |
| `test` | upstream's own test suite |
| `verify-pristine` | prove `openssl/` carries no vendor modifications |
| `clean` / `distclean` | |

### The pristine gate

The product's defining property is that nothing was changed, so the build
proves it rather than asserting it:

```sh
$ make -C build verify-pristine
==> checking openssl/ carries no vendor modifications
  OK — openssl/ is unmodified upstream
```

It greps the four files QudoSSL Community patches in order to delegate its
mathematics. Those are the sharpest available test that this tree is not that
one.

**Check the artefact too, not only the source.** A pristine tree built against
the wrong archive would pass `verify-pristine` and still be wrong:

```sh
$ nm -a /opt/qudossl-commercial/lib/libcrypto.so.3 | grep -c QUDO
0
```

Zero is the only acceptable answer for this product.

---

## Build in a container

The lab images build this tree for Linux and assert their own provenance. See
`qudossl-banking-lab/stack/commercial/Dockerfile`, which runs five gates during
the build:

1. `verify-pristine`
2. the built CLI reports a **Linux** platform
3. **zero** `QUDO` symbols in `libcrypto.so.3`
4. `ldd` resolves `libssl`/`libcrypto` only from the install prefix
5. the FIPS provider loads, ChaCha20 is absent, and all six ML-KEM groups are offered

> **Do not build the container from a tree you have already built on the host.**
> OpenSSL writes architecture-specific files into its own source directories.
> `crypto/buildinf.h` in particular contains a literal
> `#define PLATFORM "platform: darwin64-arm64"`, and `make` will not regenerate
> a copy that already looks current — so a macOS artefact can make a Linux
> container report macOS. `.gitignore` and the image's `.dockerignore` both
> exclude these; assertion 2 above exists to catch any that slip through.

---

## FIPS mode

```sh
openssl fipsinstall \
    -module /opt/qudossl-commercial/lib/ossl-modules/fips.so \
    -out    /opt/qudossl-commercial/ssl/fipsmodule.cnf \
    -provider_name fips
# INSTALL PASSED
```

Then point `OPENSSL_CONF` at a configuration that activates the `fips` and
`base` providers. **The `.include` path must be absolute** — OpenSSL's config
parser does not expand shell variables, and a literal `$PREFIX` leaves the FIPS
provider inactive with no error at all. `openssl list -providers` then shows
only `default`, which looks like success.

---

## Verification

Observed on this tree — reproduce them rather than take them on trust.

```sh
$ openssl version
OpenSSL 3.5.7 9 Jun 2026

$ openssl list -providers
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider

$ openssl ciphers -s -tls1_3
TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256
```

ChaCha20-Poly1305 is absent under FIPS because it is not an approved algorithm.
Standalone `x25519` is likewise not offered — but the **hybrid**
`X25519MLKEM768` is, because the hybrid is an approved key-establishment
construction while X25519 alone is not an approved scheme.

### Post-quantum TLS groups

All six, available in FIPS mode:

```
MLKEM512  MLKEM768  MLKEM1024
SecP256r1MLKEM768  X25519MLKEM768  SecP384r1MLKEM1024
```

### A real handshake

Server and client on this build, FIPS mode, serving a **classical RSA-3072**
certificate:

```
$ openssl s_client -connect localhost:4433 -groups X25519MLKEM768 -brief
CONNECTION ESTABLISHED
Protocol version: TLSv1.3
Ciphersuite: TLS_AES_256_GCM_SHA384
Negotiated TLS1.3 group: X25519MLKEM768
```

Post-quantum key exchange with an unchanged classical certificate: the
certificate and the key exchange are independent parts of TLS, and only the key
exchange is exposed to harvest-now-decrypt-later.

> **Reading the output correctly.** `-brief` prints
> `Negotiated TLS1.3 group:` for ML-KEM groups but **not** for classical ones —
> a classical handshake reports `Peer Temp Key: ECDH, prime256v1, 256 bits`
> instead. Tooling that greps only for the first form will report a working
> classical connection as broken.

---

## Licence

The contents of `openssl/` are distributed under the Apache License 2.0, as
published by the OpenSSL Project. This repository adds no code under any other
licence.
