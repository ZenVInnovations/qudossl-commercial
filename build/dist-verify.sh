#!/usr/bin/env bash
#
# dist-verify.sh — build, install and acceptance-check a QudoSSL Commercial
# source tarball, exactly as a customer would receive it (no git, no submodule
# access, clean environment). This is the release gate: a tarball that fails
# here does not ship.
#
# Checks encoded from the public migration handbook's Phase 1 acceptance test
# plus the artefact-provenance lessons:
#   - `openssl version` is plain upstream (no +metadata stamp)
#   - `qudossl version` matches the tarball's product version
#   - libcrypto carries ZERO QUDO symbols (the Commercial fingerprint)
#   - the installed FIPS module identifies as "OpenSSL FIPS Provider" 3.5.4,
#     with no vendor stamp/brand
#   - under a FIPS config, base (3.5.7) + fips (3.5.4) are both active
#   - a post-quantum TLS 1.3 handshake negotiates X25519MLKEM768
#
# Usage: dist-verify.sh <path/to/qudossl-commercial-X.Y.Z-src.tar.gz>

set -euo pipefail

TARBALL=${1:?usage: dist-verify.sh <tarball>}
[ -f "$TARBALL" ] || { echo "dist-verify: no such tarball: $TARBALL (run 'make dist' first)" >&2; exit 1; }

# A previous install's exports must not leak into the build or fipsinstall.
unset OPENSSL_CONF OPENSSL_MODULES

VERSION=$(basename "$TARBALL" | sed -n 's/^qudossl-commercial-\(.*\)-src\.tar\.gz$/\1/p')
[ -n "$VERSION" ] || { echo "dist-verify: cannot parse version from $(basename "$TARBALL")" >&2; exit 1; }

JOBS=$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu || echo 4 )
case "$(uname -s)" in
  Darwin) LIBCRYPTO=libcrypto.3.dylib; MODEXT=dylib ;;
  *)      LIBCRYPTO=libcrypto.so.3;    MODEXT=so ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PREFIX="$WORK/prefix"

pass=0; fail=0
check() { # check <name> <ok:0|nonzero> <detail>
  if [ "$2" = 0 ]; then echo "  PASS  $1"; pass=$((pass+1));
  else echo "  FAIL  $1 — $3" >&2; fail=$((fail+1)); fi
}

echo "==> unpacking $(basename "$TARBALL") into $WORK"
tar -xzf "$TARBALL" -C "$WORK"
SRC="$WORK/qudossl-commercial-$VERSION"
[ -d "$SRC" ] || { echo "dist-verify: tarball did not unpack to qudossl-commercial-$VERSION/" >&2; exit 1; }
[ -f "$SRC/openssl-fips/Configure" ] || \
  { echo "dist-verify: tarball is missing the vendored openssl-fips/ source" >&2; exit 1; }

echo "==> verify-pristine (from the tarball, no git)"
make -C "$SRC/build" verify-pristine

echo "==> building (JOBS=$JOBS)"
make -C "$SRC/build" all PREFIX="$PREFIX" EXTRA_FLAGS="-Wl,-rpath,$PREFIX/lib" JOBS="$JOBS"
make -C "$SRC/build" install_sw   PREFIX="$PREFIX"
make -C "$SRC/build" install_fips PREFIX="$PREFIX"

echo "==> acceptance checks"
# Checks tally their own failures (the `fail` counter is the gate); disable
# errexit here so a false condition records a FAIL instead of aborting.
set +e
BASE=$("$PREFIX/bin/openssl" version | awk '{print $2}')
case "$BASE" in
  *+*) check "openssl version is plain upstream" 1 "got '$BASE' (stamped)" ;;
  *)   check "openssl version is plain upstream ($BASE)" 0 ;;
esac

PRODUCT=$("$PREFIX/bin/qudossl" version)
[ "$PRODUCT" = "QudoSSL $VERSION" ]; check "qudossl version == 'QudoSSL $VERSION'" $? "got '$PRODUCT'"

QUDO_SYMS=$(nm -a "$PREFIX/lib/$LIBCRYPTO" 2>/dev/null | grep -c QUDO || true)
[ "$QUDO_SYMS" = "0" ]; check "libcrypto carries 0 QUDO symbols" $? "count=$QUDO_SYMS"

MOD="$PREFIX/lib/ossl-modules/fips.$MODEXT"
# grep WITHOUT -q: under pipefail, grep -q exits at first match and SIGPIPEs
# the strings writer (pipeline status 141). Plain grep reads all input.
strings "$MOD" | grep '^OpenSSL FIPS Provider$' >/dev/null; check "fips module identifies as 'OpenSSL FIPS Provider'" $? "name string missing"
strings "$MOD" | grep '^3\.5\.4$' >/dev/null;             check "fips module carries version 3.5.4" $? "version string missing"
! strings "$MOD" | grep -E '\+qudo|QudoSSL' >/dev/null;   check "fips module carries no vendor stamp/brand" $? "vendor strings present"

# FIPS configuration smoke — absolute .include, base + fips active.
cat > "$WORK/fips.cnf" <<EOF
openssl_conf = openssl_init
.include $PREFIX/ssl/fipsmodule.cnf
[openssl_init]
providers   = provider_sect
alg_section = algorithm_sect
[provider_sect]
fips = fips_sect
base = base_sect
[base_sect]
activate = 1
[algorithm_sect]
default_properties = fips=yes
EOF
PROVIDERS=$(OPENSSL_CONF="$WORK/fips.cnf" OPENSSL_MODULES="$PREFIX/lib/ossl-modules" \
  "$PREFIX/bin/qudossl" list -providers 2>&1 || true)
echo "$PROVIDERS" | grep -q "OpenSSL FIPS Provider"; check "FIPS config activates the OpenSSL FIPS Provider" $? "$PROVIDERS"
echo "$PROVIDERS" | grep -q "3.5.4";                 check "active fips provider reports 3.5.4" $? "$PROVIDERS"
echo "$PROVIDERS" | grep -q "OpenSSL Base Provider"; check "base provider active alongside fips" $? "$PROVIDERS"

# Post-quantum handshake proof (standard mode). install_sw does not install a
# default openssl.cnf (only full `install` does), so — exactly as the handbook
# has the operator do in Phase 1 — write a minimal standard config and point
# OPENSSL_CONF at it. This also proves the handbook's STANDARD_CONF template.
cat > "$WORK/std.cnf" <<CNF
openssl_conf = openssl_init
[openssl_init]
providers = provider_sect
ssl_conf  = ssl_sect
[provider_sect]
default = default_sect
[default_sect]
activate = 1
[ssl_sect]
system_default = system_default_sect
[system_default_sect]
Groups = X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1
[req]
distinguished_name = req_dn
[req_dn]
CNF
export OPENSSL_CONF="$WORK/std.cnf"
PORT=$(( 30000 + RANDOM % 2000 ))
"$PREFIX/bin/qudossl" req -x509 -new -noenc -newkey rsa:3072 \
  -keyout "$WORK/s.key" -out "$WORK/s.crt" -days 2 \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost" >/dev/null 2>&1
"$PREFIX/bin/qudossl" s_server -accept "$PORT" -cert "$WORK/s.crt" -key "$WORK/s.key" \
  -tls1_3 -www -quiet & SPID=$!
# Poll for the server to bind instead of guessing with a fixed sleep — a cold
# server on a freshly-built install can take longer than a second to listen.
HS=""
for _ in $(seq 1 30); do
  HS=$("$PREFIX/bin/qudossl" s_client -connect "127.0.0.1:$PORT" \
    -groups X25519MLKEM768 -tls1_3 -brief </dev/null 2>&1)
  case "$HS" in
    *"Negotiated TLS1.3 group: X25519MLKEM768"*) break ;;
    *"Connection refused"*) sleep 0.5 ;;
    *) break ;;
  esac
done
kill "$SPID" 2>/dev/null || true
unset OPENSSL_CONF
case "$HS" in
  *"Negotiated TLS1.3 group: X25519MLKEM768"*) check "PQ handshake negotiates X25519MLKEM768" 0 ;;
  *) check "PQ handshake negotiates X25519MLKEM768" 1 "$(echo "$HS" | tail -3)" ;;
esac

set -e
echo
echo "==> dist-verify: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
echo "==> $(basename "$TARBALL") is fit to ship"
