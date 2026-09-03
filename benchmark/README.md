# qudossl crypto benchmark

Measures **qudossl** (OpenSSL 3.5.7 with ML-KEM and ML-DSA delegated to qudo-pqc)
against **pristine OpenSSL 3.5.7**.

Nothing here opens a socket. Every measurement runs in-process, so there is no
server to start, no port to allocate, and no network to depend on.

---

## 1. What it uses, and why those tools

The benchmarks are **not ours**. They are the ones the projects themselves
publish, vendored here and built once against each OpenSSL tree. That removes the
obvious objection to a vendor-supplied performance number: nobody can say we
wrote a benchmark that flatters our own code.

| tool | origin | licence | measures |
|---|---|---|---|
| `openssl speed` | OpenSSL, already in the tree | Apache-2.0 | ML-KEM and ML-DSA primitives |
| `perftools/` | [openssl/perftools](https://github.com/openssl/perftools) | Apache-2.0 | full TLS 1.3 handshake, in memory |
| `openssl-bench/` | [ctz/openssl-bench](https://github.com/ctz/openssl-bench) | Apache-2.0 | resumption (full / session-id / ticket), memory per connection |
| `valgrind --tool=callgrind` | system package | GPL-2.0 | exact instruction counts |

OpenSSL's own README states the intended usage directly: *"we would expect the
apps to be built multiple times (once for each target OpenSSL version to be
tested)"* — which is exactly this comparison.

**Why not wrk, k6, vegeta, ab, siege?** None of them can negotiate
`X25519MLKEM768`; they ship their own TLS stacks. **Why not BoringSSL's `bssl
speed`, wolfSSL's `benchmark`, or liboqs `speed_kem`?** Each measures its own
library, not ours.

### Why instruction counts, not just timings

Callgrind counts instructions rather than elapsed time, so the result does not
depend on CPU frequency, core type or scheduling — the same reason the rustls
project uses it. Both are collected; the instruction counts are the primary
evidence and the timings are secondary.

---

## 2. Requirements

Two **already-built** OpenSSL trees, each configured with `enable-fips` and with
`fipsinstall` run:

```bash
perl Configure linux-x86_64 enable-fips && make -j$(nproc)
./apps/openssl fipsinstall -module providers/fips.so -out providers/fipsmodule.cnf
```

Tools:

```bash
sudo apt-get install -y cmake g++ valgrind python3 pandoc
```

`pandoc` is only needed for the PDF; the Markdown report works without it.

Paths are discovered automatically. Override if the trees live elsewhere:

```bash
export QUDOSSL_DIR=/path/to/qudossl/openssl
export STOCK_DIR=/path/to/openssl-3.5.7
```

---

## 3. Running it

To run the tools **directly**, one command at a time, see **[MANUAL.md](MANUAL.md)**
— every binary, its arguments, and its real output. The scripts below exist only
to repeat those commands, alternate the build order, and do the statistics.

```bash
./scripts/build.sh        # build both, generate certs and configs   ~2 min
./scripts/verify.sh       # confirm it measures what it claims       ~10 s
./scripts/run.sh          # wall-clock: primitives, handshake, ...   ~15 min
./scripts/run-instr.sh    # instruction counts under callgrind       ~25 min
./scripts/report.sh       # REPORT.md and REPORT.pdf                 ~5 s
```

`run.sh` and `run-instr.sh` are independent; either can be run alone, and
`report.sh` works on whatever data exists.

Repetitions default to 6 and can be changed:

```bash
REPS=12 ./scripts/run.sh
```

### Run `verify.sh` first, every time

It is not a formality. It checks the things that fail silently and produce
plausible-looking numbers that mean nothing:

- each binary resolves **its own** `libcrypto`, not the system one or the other
  tree's — this genuinely happened during development and was caught by `ldd`
- the merged tree really contains qudo symbols and the pristine tree really does
  not, checked by inspecting `libcrypto` rather than trusting directory names
- the two trees are not the same directory
- **`OPENSSL_CONF` really selects the key-exchange group.** `handshake.c` never
  sets a group itself, so if the config were ignored every "PQC" figure would be
  a classical X25519 handshake wearing the wrong label. The check measures a
  classical and a hybrid group and fails if they come out the same.

---

## 4. Output

| file | contents |
|---|---|
| `data/primitives.csv` | `openssl speed` per algorithm, operation, provider, build, repetition |
| `data/handshake.csv` | microseconds per in-memory TLS 1.3 handshake |
| `data/resumption.csv` | handshakes/s for full, session-id and ticket resumption |
| `data/memory.csv` | peak RSS at 100 / 1000 / 5000 connections |
| `data/instructions.csv` | instructions per operation, from callgrind |
| `REPORT.md`, `REPORT.pdf` | generated analysis |

---

## 5. How a result is decided

A cell is reported as **separated** only if all three hold. The thresholds are
fixed in `scripts/analyze.py` before any dataset is inspected; changing one after
seeing results would be indefensible.

1. **Exact sign test** — every repetition favours the same build. At n=6 the
   two-sided p is 0.031, and no distribution-free test reaches p<0.05 by any
   other outcome, so this is the nonparametric optimum for the sample size rather
   than a house rule.
2. **z >= 2** on the paired per-repetition ratio.
3. **Effect outside the 10% floor** — wall-clock on this class of host cannot
   resolve less. The instruction counts can, and are reported separately.

Glass's delta is reported as an effect size. Build order is reversed on alternate
repetitions so that run position cannot favour either build.

The `control_ecdsa` handshake row is the **negative control**: X25519 key
exchange with an ECDSA certificate, so no delegated code runs on either side. It
must read parity. If it separates, the comparison is measuring something other
than the delegated math and nothing else in the report should be believed.

Note the distinction the `*_mldsa` rows carry: they all use an ML-DSA-44
certificate, so each pays a PQC signature on top of its key exchange. A
classical-key-exchange row among them is therefore **not** a control - during
development all four moved together at ~1.38x for exactly that reason, which is
why the ECDSA row exists.

---

## 6. What this suite does not measure

Deliberately, and it should not be presented otherwise:

- **Deployment behaviour under real traffic.** There is no server, no network and
  no HTTP. A handshakes-per-second figure here is an upper bound obtained with
  the kernel, the scheduler and the network removed.
- **Maximum concurrent connections, sustained load, HTTP throughput.** These
  characterise nginx and the kernel rather than the delegated crypto — at
  realistic keepalive settings the PQC content of such a workload is a fraction
  of a percent.
- **Other architectures.** x86-64 with AVX2 only. qudo-pqc ships aarch64 NEON
  paths that are not exercised here, so these ratios do not transfer.

---

## 7. Portability

Runs from any directory. Nothing is hardcoded: paths are derived from the script
location, the OpenSSL trees are discovered by version and are overridable, and
per-OS differences go through a small set of helpers.

| what differs | Linux | macOS | handled by |
|---|---|---|---|
| resolved library of a binary | `ldd` | `otool -L` | `lib_of()` |
| peak resident set | `time -f %M` (KiB) | `time -l` (bytes) | `peak_rss_kb()` |
| FIPS module | `fips.so` | `fips.dylib` | `fips_module()` |
| libcrypto | `libcrypto.so.3` | `libcrypto*.dylib` | `qudo_symbols()` |
| version sort | — | no `sort -V` | numeric field sort |

### Platform support

| | Linux | macOS | Windows |
|---|---|---|---|
| `openssl speed` - primitives | yes | yes | yes |
| `perftools` - TLS handshake | yes | yes | yes |
| `openssl-bench` - resumption, memory | yes | yes | **no** |
| callgrind - instruction counts | yes | Intel only | **no** |
| **this harness** | **yes** | untested | **no** |

**Linux is the only fully supported platform.**

**macOS** is written for but not tested - the per-OS branches come from the
documented behaviour of those tools, not from a run on a Mac. Treat it as
untested until someone runs `./scripts/verify.sh` there.

Instruction counts depend on which Mac. Upstream valgrind does not support recent
macOS at all. A community fork
([LouisBrunner/valgrind-macos](https://github.com/LouisBrunner/valgrind-macos))
does, and is in Homebrew for Intel. On Apple Silicon that fork's arm64 support is
experimental: it requires setting `I_ACKNOWLEDGE_THIS_MIGHT_CRASH_OR_DAMAGE_MY_
COMPUTER=yes` and has open crash reports against macOS 15. Treat instruction
counts as available on Intel Macs and not available on Apple Silicon - not
because it cannot be made to run, but because an experimental fork carrying that
warning is not a basis for certification evidence.

Since the instruction counts are the primary evidence, an Apple Silicon Mac gives
you the weaker half of the suite.

**Windows is not supported.** Two of the four tools would build there -
`perftools` carries real `WIN32` support and `perflib` abstracts threads, time
and `basename` per platform - but `openssl-bench` has no Windows branches at all
(it needs `<sys/time.h>` and a GNU `time`), valgrind does not exist for Windows,
and this harness is POSIX shell that reads `/proc` and runs `ldd`. Making it
native would be a rewrite, not a patch. **Use WSL2**, which runs the full suite.

### Running from somewhere else

The suite finds the OpenSSL trees by looking two directories above itself. Copy
this folder anywhere and that guess is wrong, so say where they are:

```bash
export QUDOSSL_DIR=/path/to/qudossl/openssl
export STOCK_DIR=/path/to/openssl-3.5.7
./scripts/verify.sh
```

`BENCH_ROOT` overrides the guess itself if you would rather keep the discovery
behaviour with a different root. Everything else - data, certificates, configs,
binaries - lives inside this folder and moves with it.

---

## 8. If something fails

| symptom | cause |
|---|---|
| `no qudo symbols; not a merged build` | `QUDOSSL_DIR` points at a pristine tree |
| `both trees are the same directory` | `QUDOSSL_DIR` and `STOCK_DIR` are identical — the comparison would be vacuous |
| `handshake linked ... wrong tree` | rebuild; `build.sh` checks this and refuses to continue |
| `group selection ... config appears ignored` | the OpenSSL build lacks the hybrid group, or `OPENSSL_CONF` is being overridden |
| `perftools source missing` | `git clone https://github.com/openssl/perftools perftools` |
| FIPS cells absent from the report | that tree has no `providers/fipsmodule.cnf`; run `fipsinstall` |
| PDF missing, Markdown present | `pandoc` or `wkhtmltopdf` absent — harmless |
