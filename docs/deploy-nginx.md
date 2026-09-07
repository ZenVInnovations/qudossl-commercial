# Deploying nginx for post-quantum TLS on QudoSSL Commercial

nginx does its TLS through whatever OpenSSL it is linked against. To terminate
**post-quantum TLS 1.3** (ML-KEM hybrid key exchange) at nginx, you build nginx
against QudoSSL Commercial's OpenSSL 3.5.7 libraries and add one directive to the
server block. No nginx source patch and no third-party provider are needed — the
ML-KEM groups are part of upstream OpenSSL 3.5's own default provider.

**Prerequisite:** QudoSSL Commercial installed under a prefix (this guide uses
`$QUDOSSL_PREFIX`, e.g. `/opt/qudossl`). See [installation.md](installation.md).

> QudoSSL Commercial *runs in FIPS mode* using OpenSSL's own FIPS provider; it is
> **not** a CMVP-validated module. Fronting an app with it gives you post-quantum
> key exchange, not a validation certificate — see [fips-mode.md](fips-mode.md).

---

## 1. The one hard requirement: nginx must link QudoSSL's libraries

QudoSSL keeps the **same SONAMEs** as your distribution's OpenSSL
(`libssl.so.3`, `libcrypto.so.3`), because it *is* OpenSSL 3.5.7. So the loader
can silently bind nginx to the distro copy — which has the ML-KEM groups only if
it happens to be 3.5+, and is not the build you support. Two things prevent that:

1. Build with `-Wl,-rpath,$QUDOSSL_PREFIX/lib` so the binary records where to find
   its libraries.
2. Verify with `ldd` after building (step 2) — never assume.

A stock distro nginx package will **not** do post-quantum TLS just because
QudoSSL is installed; it is linked against the distro OpenSSL. You must build
nginx against QudoSSL, or run an image that already did.

---

## 2. Build nginx against QudoSSL

Building nginx from source also needs its usual dependencies — a C toolchain plus
the PCRE2 and zlib development headers:

```sh
sudo apt-get install -y build-essential libpcre2-dev zlib1g-dev   # Debian/Ubuntu
```

Then build against QudoSSL's OpenSSL:

```sh
export QUDOSSL_PREFIX=/opt/qudossl

# from the nginx source tree (nginx >= 1.19.4 for ssl_conf_command)
./configure \
    --with-http_ssl_module --with-http_v2_module \
    --with-cc-opt="-I${QUDOSSL_PREFIX}/include -O2 -g" \
    --with-ld-opt="-L${QUDOSSL_PREFIX}/lib -lssl -lcrypto -Wl,-rpath,${QUDOSSL_PREFIX}/lib"
make -j"$(nproc)"
sudo make install        # a default source build installs under /usr/local/nginx

# GATE: fail loudly if nginx did not actually link QudoSSL.
# Point ldd at your nginx binary — /usr/local/nginx/sbin/nginx for a default
# source build, /usr/sbin/nginx for a distro package layout.
ldd /usr/local/nginx/sbin/nginx | grep -E 'libssl|libcrypto' \
  | grep -q "${QUDOSSL_PREFIX}/lib" \
  || { echo "FATAL: nginx is not linked against QudoSSL"; exit 1; }
```

**TCP / non-HTTP termination.** To proxy post-quantum TLS in front of a database
or other TCP service, add the stream modules at configure time:

```sh
--with-stream --with-stream_ssl_module --with-stream_ssl_preread_module
```

(The banking-lab Commercial image builds with exactly these, plus
`--with-http_auth_request_module`; the plain web demo omits them.)

---

## 3. Point the nginx process at the FIPS configuration

nginx reads OpenSSL's provider configuration from `OPENSSL_CONF` and finds the
FIPS module through `OPENSSL_MODULES`. Set both **in the service manager**, not a
login shell (a `sudo`/service context does not inherit your shell's exports).

**systemd** — drop-in `/etc/systemd/system/nginx.service.d/qudossl.conf`:

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
[installation.md](installation.md) §5 (activates `fips`+`base`,
`default_properties = fips=yes`, and its `[system_default_sect] Groups` line sets
a default group list). For a non-FIPS deployment, point `OPENSSL_CONF` at a
config that activates only the `default` provider instead.

> If `OPENSSL_CONF` is wrong or unset, nginx still starts and still serves TLS —
> just **without** the FIPS provider and possibly without the ML-KEM groups.
> Verify (step 6); do not assume.

---

## 4. Configure post-quantum groups in nginx

The directive is **`ssl_conf_command Groups …`** — nginx passes it straight
through to OpenSSL's `SSL_CONF_cmd`. Put the hybrids first and classical curves
last as a fallback:

```nginx
server {
    listen       443 ssl;
    http2        on;

    ssl_certificate     /etc/nginx/certs/server-rsa.crt;
    ssl_certificate_key /etc/nginx/certs/server-rsa.key;

    ssl_protocols             TLSv1.2 TLSv1.3;   # ML-KEM requires TLS 1.3
    ssl_prefer_server_ciphers off;
    ssl_ciphers               ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

    # Post-quantum key exchange: ML-KEM hybrids first, classical fallback last.
    ssl_conf_command Groups   X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1;

    # Surface the negotiated group so you can see PQC working from the client side.
    add_header X-TLS-Protocol $ssl_protocol always;
    add_header X-TLS-Cipher   $ssl_cipher   always;
    add_header X-TLS-Group    $ssl_curve    always;
}
```

Notes that matter:

- **The certificate stays classical.** ML-KEM here is *key exchange*; an ordinary
  RSA or ECDSA certificate is unchanged. Only the key exchange is exposed to
  harvest-now-decrypt-later, so PQC key exchange with a classical certificate is
  the correct, deployable posture.
- **Group names are case-sensitive** and must match OpenSSL 3.5.7's spelling
  exactly: `X25519MLKEM768`, `SecP256r1MLKEM768`, `SecP384r1MLKEM1024` (hybrids),
  `MLKEM512`/`MLKEM768`/`MLKEM1024` (pure ML-KEM — not recommended as a default),
  `secp256r1`/`secp384r1` (classical fallback).
- **Under FIPS, do not name a bare `x25519`** (or `x448`/brainpool) in the group
  list — those are withdrawn in FIPS mode and OpenSSL rejects the *whole* list,
  so nginx fails to start. The **hybrid** `X25519MLKEM768` is fine (the hybrid is
  an approved key-establishment construction; X25519 alone is not).
- **Where to set the groups.** The `ssl_conf_command` above scopes them per
  server block, which is the clearest place. The `[system_default_sect] Groups`
  line in `qudossl-fips.cnf` sets a process-wide default; if you rely on that you
  can omit the nginx directive, but an explicit per-vhost directive is easier to
  review and to vary between vhosts. Do not fight the two — pick one as the source
  of truth per vhost.
- **A pinned-classical vhost** (e.g. for a legacy client) is just a different
  list: `ssl_conf_command Groups secp256r1:secp384r1;`.

---

## 5. nginx as a TLS client to an upstream

When nginx re-encrypts to a backend (`proxy_pass https://…`), it is the *client*
of that hop. Set the client-side groups with **`proxy_ssl_conf_command`**:

```nginx
location / {
    proxy_pass https://backend;
    proxy_ssl_conf_command Groups X25519MLKEM768:SecP384r1MLKEM1024:secp256r1;
}
```

The `stream {}` module has the analogous `ssl_conf_command` on the `server`/
`proxy` side for TCP TLS.

### TCP (stream) termination example

```nginx
stream {
    server {
        listen 5433 ssl;
        ssl_protocols TLSv1.3;
        ssl_conf_command Groups X25519MLKEM768:secp384r1;
        proxy_pass postgres:5432;
    }
}
```

---

## 6. Verify post-quantum TLS is actually being negotiated

From a QudoSSL client, connect and read the negotiated group:

```sh
qudossl s_client -connect your.host:443 -groups X25519MLKEM768 -tls1_3 -brief </dev/null
# Negotiated TLS1.3 group: X25519MLKEM768
```

The `qudossl s_client` output is the **authoritative** name check. If you
exported the header in step 4, `curl` shows the group too — but read it
carefully:

```sh
curl -sI https://your.host/ | grep -i x-tls-group
# X-TLS-Group: prime256v1   ← from a classical client such as curl/your browser
# X-TLS-Group: 0x11ec       ← from a PQC-capable client (0x11ec = X25519MLKEM768)
```

> **The header reflects the *client's* negotiated group, and `$ssl_curve` never
> prints the ML-KEM name.** A classical client (curl, most browsers today)
> negotiates a classical curve, so the header shows `prime256v1` even though the
> server offered ML-KEM first — that is post-quantum readiness working, with a
> safe classical fallback, not a misconfiguration. A PQC-capable client
> negotiates the hybrid, and nginx then prints its **IANA codepoint** `0x11ec`,
> not `X25519MLKEM768`. To read the group *name*, use `qudossl s_client` above.
>
> **Curve name spelling.** nginx's `$ssl_curve` prints the classical P-256 curve
> as `prime256v1`; HAProxy prints the same curve as `SECP256R1`. Same curve,
> different spelling — don't treat the difference as a bug.

Confirm FIPS is active in the nginx process's environment:

```sh
OPENSSL_CONF=/opt/qudossl/ssl/qudossl-fips.cnf \
OPENSSL_MODULES=/opt/qudossl/lib/ossl-modules \
  qudossl list -providers
#   base   name: OpenSSL Base Provider
#   fips   name: OpenSSL FIPS Provider
```

> **Runnable reference.** For a complete, self-contained example that performs
> every step above end to end — build nginx against QudoSSL, add the group line,
> and verify `X25519MLKEM768` is negotiated (standard *and* FIPS builds) — see the
> **[qudossl-nginx-demo](https://github.com/ZenVInnovations/qudossl-migration-demos/tree/main/qudossl-nginx-demo)**
> in the [qudossl-migration-demos](https://github.com/ZenVInnovations/qudossl-migration-demos)
> repo. Its `scripts/verify-qudossl.sh` runs exactly the checks in this section
> and prints a PASS/FAIL result. (Demonstration material only — not for production.)

---

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `nginx: not linked against QudoSSL` (the `ldd` gate) | Built against distro OpenSSL. Rebuild with the `--with-ld-opt` line from §2, RPATH included. |
| nginx starts but no ML-KEM group is ever negotiated | nginx bound to the distro `libssl.so.3` at runtime (missing RPATH), or the client didn't offer an ML-KEM group. Check `ldd $(command -v nginx)`; test with `qudossl s_client -groups X25519MLKEM768`. |
| nginx fails to start after adding groups | A bare `x25519`/`x448`/brainpool in the `Groups` list under FIPS — OpenSSL rejects the whole list. Remove the standalone curve; keep the hybrid. |
| `X-TLS-Group` shows `prime256v1` or `0x11ec`, not `X25519MLKEM768` | Expected — the header reflects the *client's* group, and `$ssl_curve` never prints the ML-KEM name: a classical client shows `prime256v1`, a PQC client shows codepoint `0x11ec`. Use `qudossl s_client -groups X25519MLKEM768` for the name. |
| FIPS not active (`list -providers` shows only `default`) | `OPENSSL_CONF`/`OPENSSL_MODULES` not set in the *service* environment, or the config's `.include` kept a literal `$PREFIX`. See [installation.md](installation.md) §5. |

---

## See also

- [installation.md](installation.md) — install QudoSSL Commercial and set up the FIPS config.
- [deploy-haproxy.md](deploy-haproxy.md) — the same, for HAProxy.
- [fips-mode.md](fips-mode.md) — the post-quantum groups and FIPS posture in full.
- [crypto-officer-guide.md](crypto-officer-guide.md) — operating the FIPS provider correctly.
- [qudossl-nginx-demo](https://github.com/ZenVInnovations/qudossl-migration-demos/tree/main/qudossl-nginx-demo) — a runnable, Dockerized reference for this whole procedure, with automated TLS-termination verification (demonstration material only).
