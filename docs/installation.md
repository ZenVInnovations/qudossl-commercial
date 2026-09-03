# Installing QudoSSL Commercial

This is the complete, operator-facing installation guide for **QudoSSL
Commercial** — a reproducible, supported build of **unmodified upstream OpenSSL
3.5.7 LTS**. Installing it puts two commands on your prefix's `bin/`: the genuine
`openssl` binary (byte-identical to upstream) and a thin `qudossl` wrapper.

The README carries the same flow in brief; this guide adds per-platform
prerequisites, the full FIPS-mode setup, container installs, verification and
uninstall. For running the module as a Crypto Officer see
[crypto-officer-guide.md](crypto-officer-guide.md); for the FIPS posture in full
see [fips-mode.md](fips-mode.md); to put it behind a web server or load balancer
see [deploy-nginx.md](deploy-nginx.md) and [deploy-haproxy.md](deploy-haproxy.md).

> **This is not a validated module.** QudoSSL Commercial *runs in FIPS mode*
> using OpenSSL's own FIPS provider. It is **not** FIPS 140-3 validated or
> certified; no CMVP certificate exists for this artefact (see
> [ADR-0005](adr/ADR-0005-no-cmvp-submission.md) and
> [fips-mode.md](fips-mode.md)).

---

## 1. Prerequisites

You need only a C toolchain, `perl`, and `git`. **There is no CMake and no other
dependency** — this product ships nothing to delegate to. The FIPS module source
is fetched from a git submodule on demand, so `git` must be able to reach GitHub
the first time you build FIPS.

| Platform | Install the toolchain with |
|---|---|
| Debian / Ubuntu | `sudo apt-get install -y build-essential perl git` |
| RHEL / Fedora / Rocky | `sudo dnf install -y gcc make perl-core git` |
| macOS | `xcode-select --install` (supplies `cc`, `make`, `perl`); `git` comes with it |
| Windows | Build through OpenSSL's own `nmake` flow (Strawberry Perl + NASM + MSVC); the FIPS module installs as `fips.dll`. See the Migration Handbook §4.3. |

> **Toolchain and reproducibility.** A byte-for-byte reproducible build requires
> matching the compiler and flags; this repository does not pin a toolchain. Any
> conformant toolchain produces a *correct* build — see
> [reproducibility.md](reproducibility.md) for what "reproducible" does and does
> not promise here.

---

## 2. Get the source

```sh
git clone https://github.com/ZenVInnovations/qudossl-commercial.git
cd qudossl-commercial
```

The `openssl/` libraries (3.5.7) come with the clone — they are a committed git
subtree. The **3.5.4 FIPS module source is a submodule** (a "thin fork" of
upstream, pinned unmodified to the `openssl-3.5.4` tag, the CMVP validation
boundary — [ADR-0006](adr/ADR-0006-fips-module-3.5.4-boundary.md),
[ADR-0007](adr/ADR-0007-fips-submodule-thin-fork.md)). It is fetched **on
demand**: the FIPS targets run `git submodule update --init` for you, or you can
fetch it up front:

```sh
make -C build fips-src        # optional: pull the 3.5.4 submodule now (network once)
```

A libraries-only build never needs the submodule.

---

## 3. Build

Pick an install prefix. Anything under your home directory needs no `sudo`.

```sh
export PREFIX=/opt/qudossl                 # or "$HOME/qudossl-commercial" for no sudo
make -C build all PREFIX="$PREFIX"         # configure + build the 3.5.7 libraries and app
```

`all` builds the libraries and the `openssl`/`qudossl` commands. The **FIPS
module** is a separate step: it is built from the 3.5.4 submodule and installed
by `install_fips` in §4 — that module is the one under the CMVP validation
boundary ([ADR-0006](adr/ADR-0006-fips-module-3.5.4-boundary.md)), not a
by-product of the 3.5.7 library build.

> **Linux: pin the runtime library path (RPATH).** Distributions ship their own
> `libssl.so.3` / `libcrypto.so.3` under the **same** SONAME, because OpenSSL
> 3.5.7 is ABI-compatible across the 3.x line. Without an RPATH the loader can
> bind to the distribution's copy first. Build with:
>
> ```sh
> make -C build all PREFIX="$PREFIX" EXTRA_FLAGS="-Wl,-rpath,$PREFIX/lib"
> ```
>
> This same RPATH requirement carries into every application you link against
> QudoSSL (nginx, HAProxy, your own binaries).

Useful targets:

| Target | Does |
|---|---|
| `all` | configure and build the 3.5.7 libraries and app |
| `install` | libraries, headers, both CLI names, **and** ~2000 man pages |
| `install_sw` | as above, without the man pages |
| `fips-src` | fetch the pinned 3.5.4 FIPS submodule — network once |
| `fips-module` | build the 3.5.4 FIPS module (the validated boundary) |
| `install_fips` | build + install the 3.5.4 FIPS module and run `fipsinstall` (do it after `install`/`install_sw`) |
| `test` | upstream's own test suite |
| `verify-pristine` | prove the vendored trees carry no vendor modifications |
| `clean` / `distclean` | remove build products |

### The pristine gate

The product's defining property is that nothing was changed, so the build proves
it rather than asserting it. Run it any time:

```sh
$ make -C build verify-pristine
==> checking vendored trees carry no vendor modifications
  note: openssl-fips not materialised — skipped (run 'make fips-src')
  OK — vendored trees are unmodified upstream
```

It greps the four files QudoSSL Community patches to delegate its mathematics
(the sharpest test that a tree is *not* Community) across `openssl/` and, once
fetched, `openssl-fips/`. See [subtree-pins.md](subtree-pins.md).

---

## 4. Install and put it on your PATH

```sh
make -C build install_sw   PREFIX="$PREFIX"    # libs, headers, openssl + qudossl
make -C build install_fips PREFIX="$PREFIX"    # fips module + fipsmodule.cnf
                                               # first FIPS install fetches the 3.5.4 submodule (network once)
```

Use `sudo` on both if your prefix is outside your home directory. Then put the
prefix's `bin/` on your PATH:

```sh
export PATH="$PREFIX/bin:$PATH"
which -a qudossl openssl        # both must resolve under $PREFIX/bin first
```

> That directory supplies **both** names, so `openssl` now resolves to this build
> as well — the point when migrating an application, but it does shadow your
> distribution's or Homebrew's `openssl` in that shell. These lines must come
> **after** anything else that prepends to `PATH` (on macOS, Homebrew's
> `eval "$(brew shellenv)"` runs from `/etc/zprofile`, before `~/.zshrc`).

---

## 5. Enable FIPS mode

`make install_fips` **already ran** `fipsinstall` for you: it created
`$PREFIX/ssl/fipsmodule.cnf` (the module's integrity record) and its self-tests
reported `OpenSSL FIPS Provider, version 3.5.4`. Re-run it by hand only if you
installed the module some other way:

```sh
case "$(uname -s)" in
  Darwin) FIPS_MODULE=fips.dylib ;;
  *)      FIPS_MODULE=fips.so    ;;   # fips.dll on Windows
esac

qudossl fipsinstall \
    -module "$PREFIX/lib/ossl-modules/$FIPS_MODULE" \
    -out    "$PREFIX/ssl/fipsmodule.cnf"
# INSTALL PASSED
```

Now write a configuration that activates the `fips` and `base` providers and
sets the post-quantum groups process-wide.

> **Leave the heredoc delimiter unquoted** (`<<EOF`, not `<<'EOF'`) so `$PREFIX`
> on the `.include` line is expanded **as the file is written**. OpenSSL's config
> parser does not expand shell variables; a literal `$PREFIX` leaves the FIPS
> provider inactive with **no error at all**, and `list -providers` then shows
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

# base supplies encoders/decoders; without it, key and certificate files
# cannot be read.
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

Confirm the include expanded to an absolute path, then point the environment at
the config:

```sh
grep include "$PREFIX/ssl/qudossl-fips.cnf"
# .include /opt/qudossl/ssl/fipsmodule.cnf   <- must NOT show a literal $PREFIX

export OPENSSL_CONF="$PREFIX/ssl/qudossl-fips.cnf"
export OPENSSL_MODULES="$PREFIX/lib/ossl-modules"
```

For long-running services set these two variables in the unit file, not a login
shell — see [deploy-nginx.md](deploy-nginx.md) §3 and
[deploy-haproxy.md](deploy-haproxy.md) §3 for the `systemd` and Kubernetes forms.

---

## 6. Verify the install

Check the **library**, not the wrapper banner — scripts and audits parse
`openssl version`, which is byte-identical to upstream:

```sh
$ openssl version
OpenSSL 3.5.7 9 Jun 2026
```

`qudossl version` additionally prints the QudoSSL Commercial banner identifying
the product as **QudoSSL 1.0.0** on the OpenSSL 3.5.7 base.

Confirm the providers are OpenSSL's own (this build ships no ZENV-branded
module), and that FIPS is active:

```sh
$ openssl list -providers
  base   name: OpenSSL Base Provider
  fips   name: OpenSSL FIPS Provider
```

Confirm the post-quantum groups are available in FIPS mode:

```sh
$ qudossl list -tls-groups | tr ':' '\n' | grep -i mlkem
MLKEM512  MLKEM768  MLKEM1024
SecP256r1MLKEM768  X25519MLKEM768  SecP384r1MLKEM1024
```

And prove the artefact carries no ZENV cryptography — **zero** is the only
acceptable answer for this product (the exact opposite of Community):

```sh
$ nm -a "$PREFIX/lib/libcrypto.so.3" | grep -c QUDO
0
```

Finally, a live post-quantum TLS 1.3 handshake, server and client on this build
in FIPS mode with a classical RSA-3072 certificate:

```sh
cd "$(mktemp -d)"
qudossl req -x509 -new -noenc -newkey rsa:3072 \
    -keyout s.key -out s.crt -days 2 -subj "/CN=localhost" 2>/dev/null

qudossl s_server -cert s.crt -key s.key -accept 4433 -www \
    -groups X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1 &
sleep 2

qudossl s_client -connect 127.0.0.1:4433 -groups X25519MLKEM768 -tls1_3 -brief </dev/null
# Negotiated TLS1.3 group: X25519MLKEM768      <- post-quantum key exchange
kill %1
```

> **Reading `-brief` correctly.** It prints `Negotiated TLS1.3 group:` for
> ML-KEM groups but **not** for classical ones — a classical handshake reports
> `Peer Temp Key: ECDH, prime256v1, 256 bits` instead. Match the group **name**
> (`MLKEM…`), not a fixed line, when scripting a check.

---

## 7. Install for Linux in a container

The lab images build this tree for Linux and assert their own provenance during
the build. `qudossl-banking-lab/stack/commercial/Dockerfile` runs
`verify-pristine`, a Linux platform check on the CLI, a **zero** `QUDO`-symbols
check on `libcrypto.so.3`, an `ldd` check that `libssl`/`libcrypto` resolve only
from the install prefix, and a provider/ML-KEM-groups check.

> **Do not build the container from a tree you have already built on the host.**
> OpenSSL writes architecture-specific files into its own source directories
> (`crypto/buildinf.h` bakes in a literal `#define PLATFORM …`), so a macOS
> artefact can make a Linux container report macOS. `.gitignore` and the image's
> `.dockerignore` exclude these; the platform gate catches any that slip through.

A minimal image is: install the toolchain from §1, `git clone`, `make -C build
all install_sw install_fips PREFIX=/opt/qudossl`, then write the FIPS config from
§5 and set `OPENSSL_CONF` / `OPENSSL_MODULES` in the image environment.

---

## 8. Run the test suite (optional)

```sh
env -u OPENSSL_CONF -u OPENSSL_MODULES make -C build test JOBS="$(nproc 2>/dev/null || echo 4)"
```

> **Unset `OPENSSL_CONF` for the test suite.** It builds its own configuration; a
> stray `OPENSSL_CONF` pointing at a FIPS-only file makes password-based and
> legacy-algorithm tests (`pkcs8`, `pkcs12`, `x509`, `store`) fail — every one a
> path FIPS correctly refuses. The failures look like real defects and are not.

---

## 9. Uninstall / multiple installs

The product is self-contained under `$PREFIX`. To remove it, drop that prefix
and the PATH/env lines that reference it:

```sh
rm -rf "$PREFIX"
# then remove the PATH / OPENSSL_CONF / OPENSSL_MODULES exports from your shell rc
```

Several installs can coexist under different prefixes; the one first on `PATH`
(and the `OPENSSL_CONF` you export) decides which is active in a given shell or
unit.

---

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `qudossl: command not found` | `$PREFIX/bin` is not on `PATH`, or the shell started before you added it. Re-run the export or open a new terminal. |
| `openssl version` reports 3.6.x, or `LibreSSL` on macOS | Another `openssl` is earlier on `PATH`. `which -a openssl` — `$PREFIX/bin/openssl` must be first. |
| `sudo qudossl …` → `command not found` | `sudo` resets `PATH`. Use the full path: `sudo "$PREFIX/bin/qudossl" …`. `sudo` also drops `OPENSSL_CONF`, so a sudo'd command runs **without** the FIPS provider. |
| `` version `OPENSSL_3.5.0' not found `` | The loader picked the distribution's `libssl.so.3`. Rebuild with `EXTRA_FLAGS="-Wl,-rpath,$PREFIX/lib"` (§3). |
| `list -providers` shows only `default` | `OPENSSL_CONF`/`OPENSSL_MODULES` not exported in *this* shell; the config's `.include` kept a literal `$PREFIX`; or you ran under `sudo`. |
| `make test` fails in `pkcs12` / `store` | An `OPENSSL_CONF` is set. Use the `env -u` form in §8. |
| `verify-pristine` FAILs | `openssl/` was modified away from upstream. Restore it — this product must never carry a local patch. See [patch-management-policy.md](patch-management-policy.md). |

---

## See also

- [deploy-nginx.md](deploy-nginx.md) — put nginx in front for post-quantum TLS.
- [deploy-haproxy.md](deploy-haproxy.md) — put HAProxy in front for post-quantum TLS.
- [crypto-officer-guide.md](crypto-officer-guide.md) — operating the FIPS provider.
- [fips-mode.md](fips-mode.md) — the full FIPS-mode posture, and why this is not a validated module.
- [qudossl-commercial-current-state.md](qudossl-commercial-current-state.md) — living project status.
