#!/usr/bin/env bash
# Builds OpenSSL's perftools once against each OpenSSL tree, and generates the
# certificate and provider configs the benchmarks need.
#
# Building the same benchmark source twice is the method OpenSSL themselves
# document: "we would expect the apps to be built multiple times (once for each
# target OpenSSL version to be tested)". Using their benchmark rather than one of
# our own also removes the obvious objection to a vendor-supplied number.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
set -e
bench_banner
bench_verify || exit 1

command -v cmake >/dev/null || { echo "FATAL: cmake not installed" >&2; exit 1; }
[ -f "$BENCH/perftools/source/CMakeLists.txt" ] || {
  echo "FATAL: perftools source missing at $BENCH/perftools" >&2
  echo "       git clone https://github.com/openssl/perftools $BENCH/perftools" >&2
  exit 1; }

for t in qudo stock; do
  d=$(tree_dir $t)
  echo "building perftools against $t ($d)" >&2
  cmake -S "$BENCH/perftools/source" -B "$BENCH/build-$t" \
        -DOPENSSL_ROOT_DIR="$d" > "$BENCH/build-$t.log" 2>&1
  cmake --build "$BENCH/build-$t" --config Release >> "$BENCH/build-$t.log" 2>&1
  # The linkage check is the point of building twice; if both binaries resolve to
  # the same libcrypto the whole comparison is vacuous.
  lib=$(lib_of "$BENCH/build-$t/handshake")
  # Verify by content, not path. On macOS the binary records its libcrypto's
  # install_name (the tree's *install* dir), not the source dir, so a path-prefix
  # check gives a false negative. What the check is really for is that build-qudo
  # and build-stock load libcryptos with different qudo-symbol status - i.e.
  # genuinely different builds - which qudo_symbols confirms on either OS.
  n=$(qudo_symbols "$(dirname "$lib")" || true)   # grep -c exits 1 on zero matches; do not let set -e abort
  if { [ "$t" = qudo ] && [ "$n" -gt 0 ]; } || { [ "$t" = stock ] && [ "$n" = 0 ]; }; then
    echo "  ok: $t handshake -> $lib ($n qudo symbols)" >&2
  else
    echo "FATAL: $t handshake -> $lib has $n qudo symbols, wrong for tree $t" >&2; exit 1
  fi
done

# handshake wants servercert.pem and serverkey.pem in one directory. An ML-DSA-44
# chain is used so the signature side of the handshake exercises the delegated
# code too, not only the key exchange.
if [ ! -s "$CERTS/servercert.pem" ]; then
  echo "generating ML-DSA-44 certificate" >&2
  ( cd "$CERTS"
    with_tree qudo "$Q/apps/openssl.cnf" "$Q/apps/openssl" req -x509 -new \
      -newkey ML-DSA-44 -noenc -keyout serverkey.pem -out servercert.pem \
      -days 3650 -subj "/CN=qudossl-benchmark" 2>/dev/null )
  [ -s "$CERTS/servercert.pem" ] || { echo "FATAL: certificate generation failed" >&2; exit 1; }
fi

# A second, entirely classical certificate directory. The negative control needs
# both a classical key exchange and a classical signature: with only the ML-DSA
# certificate available, every cell carries an ML-DSA sign and verify, so a
# "classical" row measures PQC signing and is not a control at all.
if [ ! -s "$CERTS_EC/servercert.pem" ]; then
  echo "generating ECDSA P-256 certificate (negative control)" >&2
  mkdir -p "$CERTS_EC"
  ( cd "$CERTS_EC"
    with_tree qudo "$Q/apps/openssl.cnf" "$Q/apps/openssl" ecparam \
      -name prime256v1 -genkey -noout -out serverkey.pem 2>/dev/null
    with_tree qudo "$Q/apps/openssl.cnf" "$Q/apps/openssl" req -x509 -new \
      -key serverkey.pem -out servercert.pem -days 3650 \
      -subj "/CN=qudossl-benchmark-control" 2>/dev/null )
  [ -s "$CERTS_EC/servercert.pem" ] || { echo "FATAL: control certificate failed" >&2; exit 1; }
fi

# One config per key-exchange group. handshake.c does not select a group itself,
# so it is chosen through OPENSSL_CONF, exactly as a server would. That this
# actually takes effect is not assumed: verify.sh measures both a classical and a
# hybrid group and fails if they come out the same.
mkcnf() {
  printf 'openssl_conf = init\n[init]\nssl_conf = s\n[s]\nsystem_default = d\n[d]\nGroups = %s\n' \
    "$1" > "$CONF/$2.cnf"
}
mkcnf X25519             classical
mkcnf X25519MLKEM768     hybrid
mkcnf SecP256r1MLKEM768  hybrid_p256

# FIPS variants need the module config included and fips=yes as the default.
for t in qudo stock; do
  d=$(tree_dir $t)
  if [ -f "$d/providers/fipsmodule.cnf" ]; then
    printf 'openssl_conf = init\n.include %s/providers/fipsmodule.cnf\n[init]\nproviders = prov\nalg_section = algs\nssl_conf = s\n[prov]\nfips = fips_sect\nbase = base_sect\n[base_sect]\nactivate = 1\n[algs]\ndefault_properties = fips=yes\n[s]\nsystem_default = d\n[d]\nGroups = X25519MLKEM768\n' \
      "$d" > "$CONF/fips_$t.cnf"
  else
    echo "WARNING: $d has no providers/fipsmodule.cnf; FIPS cells will be skipped" >&2
    echo "         build that tree with enable-fips and run fipsinstall" >&2
  fi
done

echo >&2
echo "BUILD OK" >&2
echo "  binaries : $BENCH/build-{qudo,stock}/handshake" >&2
echo "  certs    : $CERTS" >&2
echo "  configs  : $CONF" >&2
echo >&2
echo "next: ./scripts/verify.sh     # confirm the setup measures what it claims" >&2
echo "      ./scripts/run.sh        # wall-clock, ~15 min" >&2
echo "      ./scripts/run-instr.sh  # instruction counts, ~25 min" >&2
echo "      ./scripts/report.sh     # analysis" >&2
