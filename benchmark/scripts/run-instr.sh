#!/usr/bin/env bash
# Instruction counts under callgrind. This is the measurement that does not care
# about the machine.
#
# Wall-clock on this class of host is unusable for small differences: CPU
# frequency, core type and scheduling all move it and none is controlled. rustls
# count instructions for exactly this reason - callgrind counts actual
# instructions rather than elapsed time, so the result does not depend on the
# machine it was measured on.
#
# Both tools here are time-bounded rather than fixed-iteration, so each is asked
# how much work it actually completed and the instruction total is divided by
# that. Callgrind slows execution by roughly 50x, so far fewer operations
# complete than would natively - which does not matter, because the per-operation
# count is what is being measured and it is exact.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
bench_banner
bench_verify || exit 1
bench_environment
command -v valgrind >/dev/null || {
  echo "FATAL: valgrind not installed - instruction counts unavailable." >&2
  if [ "$BENCH_OS" = macos ]; then
    echo "       Upstream valgrind does not support recent macOS. The community" >&2
    echo "       fork (LouisBrunner/valgrind-macos) is in Homebrew for Intel; on" >&2
    echo "       Apple Silicon its arm64 support is experimental and opt-in." >&2
    echo "       Run this phase on Linux. ./scripts/run.sh works here, but see" >&2
    echo "       README section 7." >&2
  fi
  exit 1; }

# Both overridable, so a smoke test can cover one of each without waiting for the
# full matrix at 50x slowdown.
ALGS=${ALGS:-"ML-KEM-512 ML-KEM-768 ML-KEM-1024 ML-DSA-44 ML-DSA-65 ML-DSA-87"}
# Not named GROUPS: that is a bash special variable holding the caller's group
# IDs, so assigning to it is silently ignored and the loop iterates over "1000".
# Each entry is <label>:<config>:<certdir>. The certificate matters as much as
# the group: with the ML-DSA certificate every cell pays a delegated signature,
# so a classical *key exchange* still shows a large difference and is not a
# control. control_ecdsa is classical on both counts - no delegated code runs in
# it at all - and is the row that must come out at 1.00.
KEX=${KEX:-"X25519+ECDSA:classical:ec \
           X25519+ML-DSA-44:classical:pq \
           X25519MLKEM768+ML-DSA-44:hybrid:pq \
           SecP256r1MLKEM768+ML-DSA-44:hybrid_p256:pq"}

OUT=$DATA/instructions.csv
LOGS=$DATA/callgrind-logs
mkdir -p "$LOGS"
echo "build,target,detail,instructions,operations,instr_per_op" > "$OUT"

# Callgrind prints its total to stderr as e.g. "==25== I   refs: 2,216,255,085".
irefs() { sed -n 's/.*I *refs: *\([0-9,]*\).*/\1/p' "$1" 2>/dev/null | tail -1 | tr -d ','; }

emit() { # $1=build $2=target $3=detail $4=instructions $5=operations
  local per=""
  [ -n "$4" ] && [ -n "$5" ] && [ "$5" != 0 ] && per=$(awk "BEGIN{printf \"%.0f\", $4/$5}")
  echo "$1,$2,$3,${4:-},${5:-},${per:-}" >> "$OUT"
  if [ -n "$per" ]; then
    echo "  $1 $3: $per instructions per operation" >&2
  else
    echo "  $1 $3: FAILED - see $LOGS" >&2
  fi
}

echo "== TLS handshake (perftools) ==" >&2
for t in qudo stock; do
  for spec in $KEX; do
    g=${spec%%:*}; rest=${spec#*:}; cfname=${rest%%:*}; ct=${rest##*:}
    cf=$CONF/$cfname.cnf
    [ -f "$cf" ] || { echo "  skip $t/$g: no $cf" >&2; continue; }
    [ "$ct" = ec ] && cdir=$CERTS_EC || cdir=$CERTS
    [ -s "$cdir/servercert.pem" ] || { echo "  skip $t/$g: no cert in $cdir" >&2; continue; }
    log=$LOGS/hs_${t}_$g
    # Redirections are applied to the whole command rather than through a nested
    # `bash -c`: the quoting in that form silently produced no rows at all.
    with_tree "$t" "$cf" valgrind --tool=callgrind --callgrind-out-file=/dev/null \
      "$BENCH/build-$t/handshake" "$cdir" 1 > "$log.out" 2> "$log.err"
    ins=$(irefs "$log.err")
    # perftools reports its own completed rate over a fixed 5-second window, so
    # the handshake count follows from it.
    hps=$(awk '/Handshakes per second/{print $NF}' "$log.out" 2>/dev/null)
    ops=$(awk "BEGIN{printf \"%.0f\", ${hps:-0}*5}")
    emit "$(bname "$t")" handshake "$g" "$ins" "$ops"
  done
done

echo "== primitives (openssl speed) ==" >&2
for t in qudo stock; do
  d=$(tree_dir "$t")
  for a in $ALGS; do
    case $a in *KEM*) flag=-kem-algorithms ;; *) flag=-signature-algorithms ;; esac
    log=$LOGS/sp_${t}_$a
    with_tree "$t" "$d/apps/openssl.cnf" valgrind --tool=callgrind \
      --callgrind-out-file=/dev/null "$d/apps/openssl" speed -seconds 1 "$flag" "$a" \
      > "$log.out" 2> "$log.err"
    ins=$(irefs "$log.err")
    # speed prints one row per algorithm ending in the three per-second rates;
    # their sum over the 1-second window is the operation count.
    ops=$(grep "^ *$a " "$log.out" 2>/dev/null | awk '{printf "%.0f", $(NF-2)+$(NF-1)+$NF}')
    emit "$(bname "$t")" primitive "$a" "$ins" "$ops"
  done
done

echo >&2
echo "INSTRUCTIONS DONE - $OUT" >&2
echo "  callgrind logs kept in $LOGS for any cell that failed" >&2
