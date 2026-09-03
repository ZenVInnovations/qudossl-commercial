# Shared setup for the qudossl crypto benchmarks.
#
# Deliberately small. The old harness needed 400 lines because it started nginx
# servers, waited for ports, verified handshakes over TCP and cleaned up after
# itself. None of that exists here: every measurement runs in-process with no
# socket, so there is nothing to start, wait for, or leak.

case "$(uname -s)" in
  Linux)  BENCH_OS=linux ;;
  Darwin) BENCH_OS=macos ;;
  *) echo "FATAL: unsupported OS $(uname -s) - Linux and macOS only." >&2
     echo "       On Windows use WSL2, which runs the full suite. A native port" >&2
     echo "       would be a rewrite: this harness is POSIX shell and reads /proc," >&2
     echo "       and neither valgrind nor openssl-bench exists for Windows." >&2
     exit 1 ;;
esac

_lib=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BENCH=$(cd "$_lib/.." && pwd)          # qudossl/benchmark
# Only used to guess where the two OpenSSL trees live. Overridable, because the
# guess is wrong the moment this folder is copied outside the repo - and
# QUDOSSL_DIR/STOCK_DIR override the guess entirely.
ROOT=${BENCH_ROOT:-$(cd "$BENCH/../.." 2>/dev/null && pwd)}
DATA=$BENCH/data
CERTS=$BENCH/certs
CERTS_EC=$BENCH/certs-ecdsa
CONF=$BENCH/conf
mkdir -p "$DATA" "$CERTS" "$CERTS_EC" "$CONF"

# Version numbers are discovered, never hardcoded: a literal openssl-3.5.7 goes
# stale the moment a different point release is unpacked.
_newest() { # $1=glob  $2=file that must exist inside
  local d best=""
  for d in $1; do
    [ -e "$d/$2" ] || continue
    # Not `sort -V`: BSD sort has no -V. The trailing version is split into
    # numeric fields and sorted on those, which behaves the same for the
    # x.y.z names these globs produce.
    best=$(printf '%s\n%s\n' "$best" "$d" | grep -v '^$' \
           | awk -F/ '{n=split($NF,v,/[^0-9]+/); printf "%09d%09d%09d\t%s\n", v[2], v[3], v[4], $0}' \
           | sort | tail -1 | cut -f2-)
  done
  printf '%s' "$best"
}

Q=${QUDOSSL_DIR:-$ROOT/qudossl/openssl}
S=${STOCK_DIR:-$(_newest "$ROOT/openssl_source/openssl-3.5.*" apps/openssl)}
S=${S:-$(_newest "$ROOT/openssl_source/openssl-3.*" apps/openssl)}

# Distinguishes the two trees by inspecting libcrypto, not by trusting directory
# names. Catches the worst possible misconfiguration: both variables pointing at
# the same build, which would compare a tree against itself and look plausible.
qudo_symbols() {
  local lib
  for lib in "$1/libcrypto.so.3" "$1/libcrypto.dylib" "$1/libcrypto.3.dylib"; do
    [ -f "$lib" ] && { strings -a "$lib" 2>/dev/null | grep -ci 'QUDO_\|qudo_pqc'; return; }
  done
  echo -1
}

bench_verify() {
  local nq ns rc=0
  for d in "$Q" "$S"; do
    [ -x "$d/apps/openssl" ] || {
      echo "FATAL: no openssl at ${d:-<unset>}/apps/openssl" >&2
      echo "       The two trees are guessed relative to $ROOT. If this folder" >&2
      echo "       has been copied elsewhere, point at them directly:" >&2
      echo "         export QUDOSSL_DIR=/path/to/qudossl/openssl" >&2
      echo "         export STOCK_DIR=/path/to/openssl-3.5.7" >&2
      rc=1; }
  done
  [ $rc -eq 0 ] || return 1
  nq=$(qudo_symbols "$Q"); ns=$(qudo_symbols "$S")
  [ "$(cd "$Q" && pwd)" = "$(cd "$S" && pwd)" ] && {
    echo "FATAL: both trees are the same directory - nothing to compare" >&2; rc=1; }
  [ "$nq" = 0 ] && { echo "FATAL: $Q has no qudo symbols; not a merged build" >&2; rc=1; }
  [ "$ns" != 0 ] && [ "$ns" != -1 ] && {
    echo "FATAL: $S has $ns qudo symbols; not a pristine tree" >&2; rc=1; }
  return $rc
}

# Runs a command against one tree with that tree's libraries and config.
with_tree() { # $1=qudo|stock  $2=config file  $3...=command
  local which=$1 cf=$2; shift 2
  local d; [ "$which" = qudo ] && d=$Q || d=$S
  LD_LIBRARY_PATH=$d OPENSSL_MODULES=$d/providers OPENSSL_CONF=$cf "$@"
}

# Shared-library path a binary actually resolves, per OS. This is the check that
# catches two binaries silently loading the same libcrypto, which would make the
# whole comparison vacuous - so it has to work everywhere, not just on Linux.
lib_of() { # $1=binary  -> path of the libcrypto it will load
  case $BENCH_OS in
    linux) ldd "$1" 2>/dev/null | awk '/libcrypto/{print $3; exit}' ;;
    macos) otool -L "$1" 2>/dev/null | awk '/libcrypto/{print $1; exit}' ;;
  esac
}

# Peak resident set of a command, in KiB. GNU time and BSD time share neither the
# flag nor the unit: GNU -f %M reports KiB, BSD -l reports bytes on a labelled
# line.
peak_rss_kb() { # $1... = command
  case $BENCH_OS in
    linux) /usr/bin/time -f %M "$@" 2>&1 >/dev/null | tail -1 ;;
    macos) /usr/bin/time -l "$@" 2>&1 >/dev/null \
             | awk '/maximum resident set size/{printf "%d", $1/1024; exit}' ;;
  esac
}

# The FIPS module and its file extension differ per platform.
fips_module() { # $1=tree -> path if present, empty otherwise
  local f
  for f in "$1/providers/fips.so" "$1/providers/fips.dylib"; do
    [ -f "$f" ] && { printf '%s' "$f"; return; }
  done
}

# Canonical build label used in every CSV. Kept in one place because the CSV
# column and the analysis have to agree exactly, and "QUDO" vs "QUDOSSL" is the
# kind of mismatch that produces an empty report rather than an error.
bname() { [ "$1" = qudo ] && printf 'QUDOSSL' || printf 'OPENSSL'; }

tree_dir() { [ "$1" = qudo ] && printf '%s' "$Q" || printf '%s' "$S"; }

# Records what actually produced the measurements. Written by the run scripts so
# the report describes the machine the data came from, not whichever machine the
# report happens to be generated on - and so a claim like "x86-64 with AVX2" is
# read from the CPU rather than asserted.
bench_environment() {
  local arch cpu simd
  arch=$(uname -m)
  case $BENCH_OS in
    linux)
      cpu=$(awk -F': *' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
      [ -z "$cpu" ] && cpu=$(awk -F': *' '/^CPU part|^Model/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
      for f in avx512f avx2 sha_ni asimd sve; do
        grep -qm1 " $f" /proc/cpuinfo 2>/dev/null && simd="$simd${simd:+ }$f"
      done ;;
    macos)
      cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
      [ "$(sysctl -n hw.optional.avx2_0 2>/dev/null)" = 1 ] && simd="$simd${simd:+ }avx2"
      [ "$(sysctl -n hw.optional.avx512f 2>/dev/null)" = 1 ] && simd="$simd${simd:+ }avx512f"
      [ "$(sysctl -n hw.optional.neon 2>/dev/null)" = 1 ] && simd="$simd${simd:+ }neon" ;;
  esac
  {
    echo "key,value"
    echo "os,$BENCH_OS"
    echo "kernel,$(uname -sr | tr ',' ' ')"
    echo "arch,$arch"
    echo "cpu,$(printf '%s' "$cpu" | tr ',' ' ')"
    echo "simd,${simd:-none detected}"
    echo "cores,$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
    # Both report the same version string, because qudossl IS OpenSSL 3.5.7 with
    # the ML-KEM and ML-DSA cores delegated - the version is deliberately not
    # rebranded. That makes the two indistinguishable on version alone, so the
    # qudo symbol count is recorded as the thing that actually tells them apart.
    echo "qudossl_version,$(with_tree qudo "$Q/apps/openssl.cnf" "$Q/apps/openssl" version 2>/dev/null | tr ',' ' ')"
    echo "openssl_version,$(with_tree stock "$S/apps/openssl.cnf" "$S/apps/openssl" version 2>/dev/null | tr ',' ' ')"
    echo "qudossl_path,$Q"
    echo "openssl_path,$S"
    echo "qudossl_qudo_symbols,$(qudo_symbols "$Q")"
    echo "openssl_qudo_symbols,$(qudo_symbols "$S")"
    echo "date_utc,$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$DATA/environment.csv"
}

bench_banner() {
  [ -n "$BENCH_BANNER_SHOWN" ] && return 0
  export BENCH_BANNER_SHOWN=1
  {
    echo "=== qudossl crypto benchmark ==="
    echo "  benchmark dir : $BENCH"
    echo "  qudossl       : $Q  ($(qudo_symbols "$Q") qudo symbols)"
    echo "  stock         : $S  ($(qudo_symbols "$S") qudo symbols)"
    echo "  os/cores      : $BENCH_OS / $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo ?)"
  } >&2
}
