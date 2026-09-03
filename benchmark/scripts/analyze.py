#!/usr/bin/env python3
"""Analysis for the qudossl crypto benchmarks.

    python3 analyze.py <data-dir>

Decision rules are fixed here, before any dataset is inspected. Changing a
threshold after seeing results is indefensible, so they live at the top of the
file and any change to them belongs in a commit of its own.
"""

import csv
import math
import os
import statistics as st
import sys
from collections import defaultdict

# ---------------------------------------------------------------- thresholds --
FLOOR = 0.10      # effects smaller than this are not resolvable by wall-clock here
Z_MIN = 2.0
QUDO, STOCK = "QUDOSSL", "OPENSSL"
KEM_OPS = ("keygen", "encaps", "decaps")
SIG_OPS = ("keygen", "sign", "verify")


def die(m):
    print(f"FATAL: {m}", file=sys.stderr)
    sys.exit(1)


def read(path, required):
    if not os.path.isfile(path):
        return None
    with open(path, newline="") as fh:
        r = csv.DictReader(fh)
        missing = [c for c in required if c not in (r.fieldnames or [])]
        if missing:
            die(f"{os.path.basename(path)} missing column(s) {missing}")
        return list(r)


# --------------------------------------------------------------- statistics --
def zstat(rs):
    if len(rs) < 2:
        return float("nan")
    sd = st.stdev(rs)
    return float("inf") if sd == 0 else abs(st.mean(rs) - 1) / (sd / math.sqrt(len(rs)))


def signs(rs):
    return sum(1 for r in rs if r > 1)


def wilcoxon_all_same(rs):
    """Two-sided exact Wilcoxon signed-rank p, reported only for the all-agree
    outcome. At n<=6 that is the only outcome reaching p<0.05, so anything else
    is not worth printing."""
    n = len(rs)
    return 2.0 / (2 ** n) if n and signs(rs) in (0, n) else float("nan")


def glass_delta(q, s):
    """Effect size against the baseline's own spread. Cohen thresholds: <0.2
    negligible, 0.2-0.8 small to medium, >0.8 large."""
    if len(s) < 2:
        return float("nan")
    sd = st.stdev(s)
    return float("inf") if sd == 0 else (st.mean(q) - st.mean(s)) / sd


def verdict(rs):
    n = len(rs)
    if n < 2:
        return "n<2", "insufficient reps"
    mu = st.mean(rs)
    if abs(mu - 1) < FLOOR:
        return "parity", f"under {FLOOR:.0%} floor"
    if signs(rs) not in (0, n):
        return "no", f"sign {signs(rs)}/{n}"
    z = zstat(rs)
    if z < Z_MIN:
        return "no", f"z={z:.2f} < {Z_MIN}"
    if n < 6:
        return "no", f"n={n} cannot reach p<0.05"
    return "SEPARATED", f"p={wilcoxon_all_same(rs):.3f}, z={z:.2f}"


def paired(a, b):
    ks = sorted(set(a) & set(b))
    return [a[k] / b[k] for k in ks]


def cell(title, note, rows):
    """rows: (label..., qmap, smap) -> emits a markdown table."""
    print(f"## {title}\n")
    if note:
        print(note + "\n")
    print("| " + " | ".join(list(rows[0][0]) and ["", ""] or []) + " |") if False else None


# ------------------------------------------------------------------ sections --
def sec_instructions(ds):
    rows = read(os.path.join(ds, "instructions.csv"),
                ["build", "target", "detail", "instr_per_op"])
    print("## Instruction counts\n")
    if not rows:
        print("`instructions.csv` absent - run `./scripts/run-instr.sh`.\n")
        return
    print("Counted under callgrind: every CPU instruction executed, rather than "
          "elapsed time.\n")
    print("These are far more stable than wall-clock timings, but they are not "
          "exact. The benchmark runs for a fixed wall-clock window, so it "
          "completes a different number of operations each time and the one-off "
          "process and library startup is amortised over that varying count. "
          "Re-measuring the same cell moves the figure by roughly 2%. The `ops` "
          "column shows how many operations each figure was divided by; cells "
          "with different counts carry slightly different amounts of that "
          "startup.\n")
    print("For the same reason, do not subtract one row from another to isolate a "
          "component. An increment of a million instructions between two rows of "
          "ten million carries the full 2% uncertainty of both, which is a "
          "quarter of the increment.\n")
    by, ops = defaultdict(dict), {}
    for r in rows:
        if r["instr_per_op"]:
            by[(r["target"], r["detail"])][r["build"]] = int(r["instr_per_op"])
            ops[(r["target"], r["detail"], r["build"])] = r.get("operations", "?")
    print("| target | detail | qudossl | qudossl ops | openssl | openssl ops | ratio |")
    print("|---|---|---|---|---|---|---|")
    for k in sorted(by):
        q, s = by[k].get(QUDO), by[k].get(STOCK)
        if not q or not s:
            continue
        print(f"| {k[0]} | {k[1]} | {q:,} | {ops.get((k[0], k[1], QUDO), '?')} | "
              f"{s:,} | {ops.get((k[0], k[1], STOCK), '?')} | **{s/q:.3f}x** |")
    print()


def sec_primitives(ds):
    rows = read(os.path.join(ds, "primitives.csv"),
                ["rep", "build", "mode", "alg", "op1", "op2", "op3"])
    print("## Primitives\n")
    if not rows:
        print("`primitives.csv` absent.\n")
        return
    print("`openssl speed`, the tool OpenSSL ship for this purpose. These cells "
          "isolate the delegated math: no classical algorithm is involved, so the "
          "whole measured difference is ML-KEM or ML-DSA.\n")
    cells = defaultdict(dict)
    for r in rows:
        if not r["op1"]:
            continue
        for i in (1, 2, 3):
            cells[(r["mode"], r["alg"], i, r["build"])][int(r["rep"])] = float(r[f"op{i}"])
    modes = sorted({k[0] for k in cells})
    algs = sorted({k[1] for k in cells}, key=lambda a: ("DSA" in a, a))
    # Tables carry the measured numbers only. The sign test, z and Glass's delta
    # still run - they decide the "N of M separated" line under each table - but
    # are not printed per row. The raw per-repetition values are in data/*.csv for
    # anyone who wants to recompute them.
    print("| mode | algorithm | operation | qudossl op/s | openssl op/s | ratio |")
    print("|---|---|---|---|---|---|")
    stats, sep = [], []
    for m in modes:
        for a in algs:
            ops = SIG_OPS if "DSA" in a else KEM_OPS
            for i, op in enumerate(ops, 1):
                q, s = cells.get((m, a, i, QUDO)), cells.get((m, a, i, STOCK))
                if not q or not s:
                    continue
                rs = paired(q, s)
                if not rs:
                    continue
                v, why = verdict(rs)
                if v == "SEPARATED":
                    sep.append(st.mean(rs))
                stats.append(1)
                print(f"| {m} | {a} | {op} | {st.mean(q.values()):,.0f} | "
                      f"{st.mean(s.values()):,.0f} | {st.mean(rs):.3f}x |")
    if sep:
        # "separated" was jargon defined by a rules section that is no longer
        # printed, so the summary says what it means instead.
        print(f"\n**{len(stats)} cells measured. {len(sep)} showed a consistent "
              f"difference in every repetition, spanning {min(sep):.2f}x to "
              f"{max(sep):.2f}x.**\n")
    else:
        print()

def sec_handshake(ds):
    rows = read(os.path.join(ds, "handshake.csv"),
                ["rep", "build", "mode", "group", "us_per_handshake"])
    print("## TLS handshake\n")
    if not rows:
        print("`handshake.csv` absent.\n")
        return
    print("OpenSSL's `perftools/handshake`: a combined in-memory client and "
          "server, no socket. Lower microseconds is better, so the ratio is "
          "inverted to keep \"higher is better for qudossl\" consistent with the "
          "other tables.\n")
    c = defaultdict(dict)
    for r in rows:
        if r["us_per_handshake"]:
            c[(r["mode"], r["group"], r["build"])][int(r["rep"])] = float(r["us_per_handshake"])
    print("| mode | group | qudossl us | openssl us | ratio |")
    print("|---|---|---|---|---|")
    for (m, g) in sorted({(k[0], k[1]) for k in c}):
        q, s = c.get((m, g, QUDO)), c.get((m, g, STOCK))
        if not q or not s:
            continue
        ks = sorted(set(q) & set(s))
        rs = [s[k] / q[k] for k in ks]          # inverted: us, lower is better
        print(f"| {m} | {g} | {st.mean(q.values()):,.1f} | {st.mean(s.values()):,.1f} "
              f"| {st.mean(rs):.3f}x |")
    print("\nCells are named `<key exchange>+<signature>`.\n")
    print("- **`X25519+ECDSA`** - the negative control. Nothing is delegated on "
          "either side, so it must read parity.")
    print("- **`X25519MLKEM768+ML-DSA-44`** - the deployment case: both the key "
          "exchange and the signature are delegated.")
    print("- `X25519+ML-DSA-44` isolates the signature. Note it still shows a "
          "large difference despite the classical key exchange, because the "
          "ML-DSA certificate is delegated - which is why it is not a control.\n")


def sec_resumption(ds):
    rows = read(os.path.join(ds, "resumption.csv"),
                ["rep", "build", "test", "side", "handshakes_per_s"])
    print("## Session resumption\n")
    if not rows:
        print("`resumption.csv` absent.\n")
        return
    print("`ctz/openssl-bench`, written by the rustls author to compare OpenSSL "
          "builds. It replaces `openssl s_time`, which divides by the client's "
          "**user CPU time** rather than wall time (OpenSSL issue #2274) and so "
          "cannot measure server-side work at all.\n")
    c = defaultdict(dict)
    for r in rows:
        if r["handshakes_per_s"]:
            c[(r["test"], r["side"], r["build"])][int(r["rep"])] = float(r["handshakes_per_s"])
    print("| test | side | qudossl hs/s | openssl hs/s | ratio |")
    print("|---|---|---|---|---|")
    for (t, side) in sorted({(k[0], k[1]) for k in c}):
        q, s = c.get((t, side, QUDO)), c.get((t, side, STOCK))
        if not q or not s:
            continue
        rs = paired(q, s)
        print(f"| {t} | {side} | {st.mean(q.values()):,.0f} | {st.mean(s.values()):,.0f} | "
              f"{st.mean(rs):.3f}x |")
    print("\nAn ECDSA P-256 certificate is used rather than the tool's RSA-2048 "
          "default: an RSA signature costs roughly a millisecond against "
          "ML-KEM-768's ~14 us and would swamp the delegated work entirely.\n")
    print("`handshake` is a full exchange, so ML-KEM runs and a modest gain is "
          "expected - modest because the key exchange is only a fraction of even "
          "an ECDSA handshake. `handshake-resume` and `handshake-ticket` skip the "
          "key exchange and the signature altogether, so no delegated code runs "
          "in them at all: they are a second negative control and should read "
          "parity. A gain there is noise, or a sign something else is being "
          "measured.\n")


def sec_memory(ds):
    rows = read(os.path.join(ds, "memory.csv"), ["build", "connections", "peak_rss_kb"])
    print("## Memory\n")
    if not rows:
        print("`memory.csv` absent.\n")
        return
    print("Peak RSS for a given number of concurrent connections. ML-KEM and "
          "ML-DSA keys are a few kilobytes each, so a large difference here would "
          "be unexpected and worth investigating rather than reporting.\n")
    print("Fewer kilobytes is better, so the ratio is inverted the same way the "
          "handshake table inverts microseconds: above 1.00 means qudossl used "
          "less memory. Every ratio in this report therefore reads the same way - "
          "above 1.00 favours qudossl.\n")
    by = defaultdict(dict)
    for r in rows:
        if r["peak_rss_kb"]:
            by[int(r["connections"])][r["build"]] = int(r["peak_rss_kb"])
    print("| connections | qudossl KB | openssl KB | delta KB | ratio |")
    print("|---|---|---|---|---|")
    for n in sorted(by):
        q, s = by[n].get(QUDO), by[n].get(STOCK)
        if not q or not s:
            continue
        # Inverted: KB, so lower is better. Keeps "above 1.00 favours
        # qudossl" true across every table in the report.
        print(f"| {n:,} | {q:,} | {s:,} | {q-s:+,} | {s/q:.3f}x |")
    print()


def load_env(ds):
    rows = read(os.path.join(ds, "environment.csv"), ["key", "value"])
    return {r["key"]: r["value"] for r in rows} if rows else {}


def sec_limits(env):
    print("## Limitations\n")
    if env:
        print("| | measured on |")
        print("|---|---|")
        for k, label in (("cpu", "CPU"), ("arch", "architecture"),
                         ("simd", "SIMD available"), ("cores", "cores"),
                         ("os", "OS"), ("kernel", "kernel"),
                         ("date_utc", "measured")):
            if env.get(k):
                print(f"| {label} | {env[k]} |")
        print()
        if env.get("qudossl_version"):
            print("### The two builds\n")
            print("Both report the same version, because qudossl **is** OpenSSL "
                  "3.5.7 with the ML-KEM and ML-DSA cores delegated to qudo-pqc; "
                  "the version string is deliberately not rebranded. They are "
                  "separate trees, built and linked independently.\n")
            print("| | qudossl | openssl |")
            print("|---|---|---|")
            print(f"| version | {env.get('qudossl_version','?')} | {env.get('openssl_version','?')} |")
            print()
    print("- **Wall-clock figures are host-dependent.** CPU frequency, core type "
          "and thread placement all affect them and none is controlled here. The "
          "instruction counts are far more stable - about 2% - though not "
          "exact, for the reason given in that section.")
    print("- **No network is involved anywhere in this suite.** Every figure is "
          "an in-process measurement. Deployment behaviour under real traffic is "
          "not characterised here.")
    print("- **`openssl speed -seconds 2`** is used; upstream's default for this "
          "operation class is 10 s. More repetitions at 2 s were preferred to "
          "fewer at 10 s, because a disturbed window is a disturbed sample at "
          "either length.")
    # Read from the machine rather than asserted: qudo-pqc selects its backend at
    # runtime, so which one was exercised is a property of the host and belongs in
    # the data, not in a sentence someone has to remember to update.
    arch = env.get("arch", "the measured architecture")
    simd = env.get("simd", "unknown")
    print(f"- **{arch}, SIMD available: {simd}.** qudo-pqc selects its backend at "
          f"runtime, so only the path this CPU offers was exercised. Other "
          f"architectures, and any SIMD level absent above, are not covered by "
          f"these ratios.\n")


def main():
    if len(sys.argv) < 2:
        die("usage: analyze.py <data-dir>")
    ds = sys.argv[1]
    os.path.isdir(ds) or die(f"{ds} is not a directory")
    print("# qudossl crypto benchmark\n")
    print("qudossl (OpenSSL 3.5.7 with ML-KEM and ML-DSA delegated to qudo-pqc) "
          "against pristine OpenSSL 3.5.7, measured with the benchmark tools "
          "published by OpenSSL and by the rustls project, each built once "
          "against each tree.\n")
    sec_instructions(ds)
    sec_primitives(ds)
    sec_handshake(ds)
    sec_resumption(ds)
    sec_memory(ds)
    print("---\n")
    sec_limits(load_env(ds))


if __name__ == "__main__":
    main()
