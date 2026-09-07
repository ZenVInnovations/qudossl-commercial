# Deploying HAProxy for post-quantum TLS on QudoSSL Commercial

HAProxy does its TLS through whatever OpenSSL it is linked against. To terminate
**post-quantum TLS 1.3** (ML-KEM hybrid key exchange) at HAProxy, you build
HAProxy against QudoSSL Commercial's OpenSSL 3.5.7 libraries and add one keyword
to the `global` section. No HAProxy source patch and no third-party provider are
needed — the ML-KEM groups come from upstream OpenSSL 3.5's own default provider.

**Prerequisite:** QudoSSL Commercial installed under a prefix (this guide uses
`$QUDOSSL_PREFIX`, e.g. `/opt/qudossl`). See [installation.md](installation.md).
Use a HAProxy version that supports `ssl-default-bind-curves` (2.8+, 3.x
recommended), built against OpenSSL 3.5.

> QudoSSL Commercial *runs in FIPS mode* using OpenSSL's own FIPS provider; it is
> **not** a CMVP-validated module. Fronting an app with it gives you post-quantum
> key exchange, not a validation certificate — see [fips-mode.md](fips-mode.md).

---

## 1. The one hard requirement: HAProxy must link QudoSSL's libraries

QudoSSL keeps the **same SONAMEs** as your distribution's OpenSSL
(`libssl.so.3`, `libcrypto.so.3`), because it *is* OpenSSL 3.5.7. The loader can
therefore bind HAProxy to the distro copy silently. Prevent it by recording an
RPATH at build time and verifying with `ldd` afterward. A stock distro HAProxy
package will **not** speak post-quantum TLS just because QudoSSL is installed — it
is linked against the distro OpenSSL. Build HAProxy against QudoSSL, or run an
image that already did.

---

## 2. Build HAProxy against QudoSSL

Building HAProxy from source needs a C toolchain and, for the flags below, the
PCRE2 and zlib development headers:

```sh
sudo apt-get install -y build-essential libpcre2-dev zlib1g-dev curl   # Debian/Ubuntu
```

Download and unpack the HAProxy source (2.8+; **3.x LTS recommended** for
`ssl-default-bind-curves`), then build it against QudoSSL's OpenSSL:

```sh
export QUDOSSL_PREFIX=/opt/qudossl

# Download the HAProxy source — pin the current patch release from haproxy.org:
HAPROXY_VER=3.0.6
curl -fsSLO "https://www.haproxy.org/download/3.0/src/haproxy-${HAPROXY_VER}.tar.gz"
tar xf "haproxy-${HAPROXY_VER}.tar.gz" && cd "haproxy-${HAPROXY_VER}"

make -j"$(nproc)" \
    TARGET=linux-glibc \
    USE_OPENSSL=1 USE_PCRE2=1 USE_PCRE2_JIT=1 USE_ZLIB=1 USE_THREAD=1 USE_PROMEX=1 \
    SSL_INC="${QUDOSSL_PREFIX}/include" \
    SSL_LIB="${QUDOSSL_PREFIX}/lib" \
    LDFLAGS="-Wl,-rpath,${QUDOSSL_PREFIX}/lib"
sudo make install-bin PREFIX=/usr/local

# GATE: fail loudly if HAProxy did not actually link QudoSSL
ldd "$(command -v haproxy || echo /usr/local/sbin/haproxy)" | grep -E 'libssl|libcrypto' \
  | grep -q "${QUDOSSL_PREFIX}/lib" \
  || { echo "FATAL: haproxy is not linked against QudoSSL"; exit 1; }
```

`SSL_INC`/`SSL_LIB` point HAProxy's build at QudoSSL's headers and libraries;
`LDFLAGS` records the RPATH so the resulting binary loads them at runtime. Confirm
the version reports OpenSSL 3.5.7:

```sh
haproxy -vv | grep -i openssl
# ... Running on OpenSSL version : OpenSSL 3.5.7 9 Jun 2026
```

---

## 3. Point the HAProxy process at the FIPS configuration

HAProxy reads OpenSSL's provider configuration from `OPENSSL_CONF` and finds the
FIPS module through `OPENSSL_MODULES`. Set both **in the service manager**.

**systemd** — drop-in `/etc/systemd/system/haproxy.service.d/qudossl.conf`:

```ini
[Service]
Environment=OPENSSL_CONF=/opt/qudossl/ssl/qudossl-fips.cnf
Environment=OPENSSL_MODULES=/opt/qudossl/lib/ossl-modules
```

**Kubernetes / containers** — the equivalent `env:`:

```yaml
env:
  - name: OPENSSL_CONF
    value: /opt/qudossl/ssl/qudossl-fips.cnf
  - name: OPENSSL_MODULES
    value: /opt/qudossl/lib/ossl-modules
```

`qudossl-fips.cnf` is the process-wide FIPS config from
[installation.md](installation.md) §5. For a non-FIPS deployment, point
`OPENSSL_CONF` at a config that activates only the `default` provider.

> If `OPENSSL_CONF` is wrong or unset, HAProxy still starts and still serves TLS —
> just **without** the FIPS provider. Verify (step 5); do not assume.

---

## 4. Configure post-quantum groups in HAProxy

HAProxy's keyword for the TLS group list is **`ssl-default-bind-curves`** (it
accepts the same names as OpenSSL, ML-KEM hybrids included). Set the shared
defaults in `global`, then bind normally:

```haproxy
global
    ssl-default-bind-options      ssl-min-ver TLSv1.2 prefer-client-ciphers
    ssl-default-bind-ciphersuites TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256
    ssl-default-bind-ciphers      ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    # Post-quantum key exchange: ML-KEM hybrids first, classical fallback last.
    ssl-default-bind-curves       X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1

frontend https_in
    bind :443 ssl crt /etc/haproxy/certs/server.pem alpn h2,http/1.1
    # Surface the negotiated group, protocol and cipher to the CLIENT for
    # verification. Use http-RESPONSE: http-request headers go to the backend,
    # so `curl -sI` (which reads the response) would never see them.
    http-response set-header X-TLS-Group    %[ssl_fc_curve]
    http-response set-header X-TLS-Protocol %[ssl_fc_protocol]
    http-response set-header X-TLS-Cipher   %[ssl_fc_cipher]
    default_backend app_servers

backend app_servers
    server app1 backend:8080 check
```

Notes that matter:

- **Certificate format.** HAProxy's `crt` wants the certificate **and** private
  key concatenated into one PEM file:
  ```sh
  cat server-rsa.crt server-rsa.key > /etc/haproxy/certs/server.pem
  chmod 600 /etc/haproxy/certs/server.pem
  ```
- **The certificate stays classical.** ML-KEM here is *key exchange*; an ordinary
  RSA/ECDSA certificate is unchanged. Only the key exchange faces
  harvest-now-decrypt-later.
- **TLS 1.3 is required for ML-KEM** — hence `ssl-min-ver TLSv1.2` with the PQC
  groups taking effect on 1.3 handshakes. Under FIPS there is no ChaCha20, so the
  ciphersuites are AES-GCM only (as above).
- **Under FIPS, do not name a bare `x25519`/`x448`/brainpool** in
  `ssl-default-bind-curves` — they are withdrawn and OpenSSL rejects the whole
  list, so HAProxy fails to start. The **hybrid** `X25519MLKEM768` is fine.
- **Per-bind override.** A specific listener can carry its own `curves …` on the
  `bind` line to differ from the global default (e.g. a pinned-classical bind
  using `curves secp256r1:secp384r1`).

---

## 5. Verify post-quantum TLS is actually being negotiated

From a QudoSSL client:

```sh
qudossl s_client -connect your.host:443 -groups X25519MLKEM768 -tls1_3 -brief </dev/null
# Negotiated TLS1.3 group: X25519MLKEM768
```

Or from `curl`, if you exported the header in step 4 — but note the value
depends on the **client's** capability:

```sh
curl -sI https://your.host/ | grep -i x-tls-group
# X-TLS-Group: SECP256R1        ← from a classical client such as curl/your browser
# X-TLS-Group: X25519MLKEM768   ← from a PQC-capable client
```

A classical client (curl, most browsers today) negotiates a classical curve, so
the header shows `SECP256R1` even though the server offered ML-KEM first — that
is post-quantum readiness with a safe classical fallback, not a misconfiguration.
Unlike nginx (whose `$ssl_curve` prints the IANA codepoint `0x11ec`), HAProxy's
`%[ssl_fc_curve]` prints the readable **name** `X25519MLKEM768` for the hybrid.

> **Curve name spelling.** HAProxy's `%[ssl_fc_curve]` prints the classical P-256
> curve as `SECP256R1`; nginx prints the same curve as `prime256v1`. Same curve,
> different spelling — not a bug.

Confirm FIPS is active in HAProxy's environment:

```sh
OPENSSL_CONF=/opt/qudossl/ssl/qudossl-fips.cnf \
OPENSSL_MODULES=/opt/qudossl/lib/ossl-modules \
  qudossl list -providers
#   base   name: OpenSSL Base Provider
#   fips   name: OpenSSL FIPS Provider
```

> **Runnable reference.** For a complete, self-contained example that performs
> every step above end to end — build HAProxy against QudoSSL, add the
> `ssl-default-bind-curves` line, and verify `X25519MLKEM768` is negotiated
> (standard *and* FIPS builds) — see the
> **[qudossl-haproxy-demo](https://github.com/ZenVInnovations/qudossl-migration-demos/tree/main/qudossl-haproxy-demo)**
> in the [qudossl-migration-demos](https://github.com/ZenVInnovations/qudossl-migration-demos)
> repo. Its `scripts/verify-qudossl.sh` runs exactly the checks in this section
> and prints a PASS/FAIL result. (Demonstration material only — not for production.)

---

## 6. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `haproxy: not linked against QudoSSL` (the `ldd` gate) | Built against distro OpenSSL. Rebuild with `SSL_INC`/`SSL_LIB`/`LDFLAGS` from §2, RPATH included. |
| `haproxy -vv` shows an OpenSSL other than 3.5.7 | Wrong `SSL_INC`/`SSL_LIB`, or the runtime loader picked the distro `libssl.so.3` (missing RPATH). Check `ldd $(command -v haproxy)`. |
| HAProxy fails to start after adding curves | A bare `x25519`/`x448`/brainpool in `ssl-default-bind-curves` under FIPS — OpenSSL rejects the whole list. Remove the standalone curve; keep the hybrid. |
| `unknown keyword 'ssl-default-bind-curves'` | HAProxy too old. Use 2.8+ (3.x recommended) built against OpenSSL 3.5. |
| No ML-KEM group negotiated | Client didn't offer one, or HAProxy bound the distro OpenSSL at runtime. Test with `qudossl s_client -groups X25519MLKEM768`. |
| FIPS not active (`list -providers` shows only `default`) | `OPENSSL_CONF`/`OPENSSL_MODULES` not set in the *service* environment, or the config's `.include` kept a literal `$PREFIX`. See [installation.md](installation.md) §5. |

---

## See also

- [installation.md](installation.md) — install QudoSSL Commercial and set up the FIPS config.
- [deploy-nginx.md](deploy-nginx.md) — the same, for nginx.
- [fips-mode.md](fips-mode.md) — the post-quantum groups and FIPS posture in full.
- [crypto-officer-guide.md](crypto-officer-guide.md) — operating the FIPS provider correctly.
- [qudossl-haproxy-demo](https://github.com/ZenVInnovations/qudossl-migration-demos/tree/main/qudossl-haproxy-demo) — a runnable, Dockerized reference for this whole procedure, with automated TLS-termination verification (demonstration material only).
