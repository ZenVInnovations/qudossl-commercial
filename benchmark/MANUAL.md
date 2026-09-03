# Running the benchmarks by hand

Every command below has been run and its real output is shown. Nothing here needs
the `scripts/` wrappers — those exist only to repeat these commands, alternate
build order, and do the statistics.

Run everything from `qudossl/benchmark/`:

```bash
cd qudossl/benchmark
```

Set the two trees once per shell. Adjust if yours live elsewhere:

```bash
Q=$(cd ../openssl && pwd)
S=$(cd ../../openssl_source/openssl-3.5.7 && pwd)
```

`build.sh` must have been run once to produce the binaries, certificates and
configs. After that, none of the commands below touch the network, start a
server, or open a port.

---

## 1. TLS handshake — OpenSSL's own `perftools`

A combined in-memory client and server. `certs` holds the ML-DSA-44 certificate;
`1` is the thread count.

```bash
LD_LIBRARY_PATH=$Q OPENSSL_CONF=conf/hybrid.cnf ./build-qudo/handshake  certs 1
LD_LIBRARY_PATH=$S OPENSSL_CONF=conf/hybrid.cnf ./build-stock/handshake certs 1
```

```
qudossl   Average time per handshake: 663.746183us     Handshakes per second: 1506.60
stock     Average time per handshake: 1096.972356us    Handshakes per second:  911.60
```

`OPENSSL_CONF` chooses the key exchange — `handshake.c` never sets one itself, so
this is the only thing selecting it:

| config | key exchange | certificate | purpose |
|---|---|---|---|
| `conf/classical.cnf` | X25519 | ML-DSA-44 | classical KEX, PQC signature |
| `conf/hybrid.cnf` | X25519MLKEM768 | ML-DSA-44 | the deployment case |
| `conf/hybrid_p256.cnf` | SecP256r1MLKEM768 | ML-DSA-44 | second hybrid group |
| `conf/fips_qudo.cnf`, `conf/fips_stock.cnf` | X25519MLKEM768 | ML-DSA-44 | FIPS provider |

**Negative control** — classical key exchange *and* a classical certificate, so
no delegated code runs on either side. This one must come out even:

```bash
LD_LIBRARY_PATH=$Q OPENSSL_CONF=conf/classical.cnf ./build-qudo/handshake  certs-ecdsa 1
LD_LIBRARY_PATH=$S OPENSSL_CONF=conf/classical.cnf ./build-stock/handshake certs-ecdsa 1
```

Add `-t` for terse output (just the microseconds), which is what the scripts
parse.

---

## 2. Primitives — `openssl speed`

```bash
LD_LIBRARY_PATH=$Q $Q/apps/openssl speed -seconds 2 -kem-algorithms ML-KEM-768
LD_LIBRARY_PATH=$S $S/apps/openssl speed -seconds 2 -kem-algorithms ML-KEM-768
```

```
                       keygen    encaps    decaps keygens/s  encaps/s  decaps/s
     ML-KEM-768     0.000017s 0.000013s 0.000019s   59532.8   79907.0   53791.0
```

Signatures use a different flag:

```bash
LD_LIBRARY_PATH=$Q $Q/apps/openssl speed -seconds 2 -signature-algorithms ML-DSA-65
```

Algorithms available: `ML-KEM-512/768/1024`, `X25519MLKEM768`,
`SecP256r1MLKEM768`, `SecP384r1MLKEM1024`, `ML-DSA-44/65/87`.

For FIPS, add the provider config:

```bash
LD_LIBRARY_PATH=$Q OPENSSL_CONF=conf/fips_qudo.cnf \
  $Q/apps/openssl speed -seconds 2 -kem-algorithms ML-KEM-768
```

---

## 3. Resumption and memory — `ctz/openssl-bench`

These binaries have the library path baked in with `-rpath`, so no
`LD_LIBRARY_PATH` is needed. They resolve certificate paths relative to the
working directory, so run them from `openssl-bench/`:

```bash
cd openssl-bench
../bench-qudo  handshake        TLS_AES_256_GCM_SHA384
../bench-qudo  handshake-resume TLS_AES_256_GCM_SHA384
../bench-qudo  handshake-ticket TLS_AES_256_GCM_SHA384
```

```
handshake         1622.49 hs/s (server)
handshake-resume  6651.08 hs/s (server)
handshake-ticket  5900.19 hs/s (server)
```

Each prints **two** lines — one for the server side, one for the client. The
server figure is what a deployment is limited by.

Memory per connection:

```bash
/usr/bin/time -f %M ../bench-qudo memory TLS_AES_256_GCM_SHA384 1000
```

```
82560          # peak RSS in KB for 1000 concurrent connections
```

Swap `bench-qudo` for `bench-stock` to compare. On macOS use
`/usr/bin/time -l` instead, which reports bytes.

---

## 4. Instruction counts — callgrind

The measurement that does not depend on the machine. Roughly 50x slower, so each
takes a few minutes.

```bash
LD_LIBRARY_PATH=$Q OPENSSL_CONF=conf/hybrid.cnf \
  valgrind --tool=callgrind --callgrind-out-file=/dev/null \
  ./build-qudo/handshake certs 1
```

```
Handshakes per second: 24.800000
==36== I   refs:      1,465,221,057
```

Both numbers are needed. The tool runs for a fixed 5 seconds, so:

```
handshakes      = 24.8 x 5              = 124
per handshake   = 1,465,221,057 / 124   = 11,816,299 instructions
```

Do the same for `build-stock`, then divide. Measured on this machine:

| | instructions per handshake |
|---|---|
| qudossl | 11,798,082 |
| stock | 16,426,094 |
| **ratio** | **1.392x** |

Same approach for a primitive — `speed` prints the three per-second rates, and
their sum over the one-second window is the operation count:

```bash
LD_LIBRARY_PATH=$Q valgrind --tool=callgrind --callgrind-out-file=/dev/null \
  $Q/apps/openssl speed -seconds 1 -kem-algorithms ML-KEM-768
```

| | instructions per ML-KEM-768 operation |
|---|---|
| qudossl | 223,452 |
| stock | 358,547 |
| **ratio** | **1.605x** |

Linux only — valgrind does not support Apple Silicon.

---

## 5. Before trusting any of it

Two things fail silently and produce numbers that look fine and mean nothing.

**Each binary must load its own libcrypto.** Both `openssl-bench` binaries
initially resolved the *system* libcrypto, which would have compared a tree
against itself:

```bash
ldd ./build-qudo/handshake  | grep libcrypto     # otool -L on macOS
ldd ./build-stock/handshake | grep libcrypto
ldd ./bench-qudo            | grep libcrypto
ldd ./bench-stock           | grep libcrypto
```

Each must point inside its own tree — never `/lib/x86_64-linux-gnu/`.

**The trees must actually differ.** The merged build carries qudo symbols; the
pristine one carries none:

```bash
strings -a $Q/libcrypto.so.3 | grep -ci qudo     # expect ~154
strings -a $S/libcrypto.so.3 | grep -ci qudo     # expect 0
```

**And `OPENSSL_CONF` must really be taking effect.** If it were ignored, every
"PQC" number would be a classical handshake with the wrong label. Compare the two
configs — hybrid must cost visibly more:

```bash
LD_LIBRARY_PATH=$Q OPENSSL_CONF=conf/classical.cnf ./build-qudo/handshake -t certs 1
LD_LIBRARY_PATH=$Q OPENSSL_CONF=conf/hybrid.cnf    ./build-qudo/handshake -t certs 1
```

```
553.771182     # classical
619.501920     # hybrid, +11.9%
```

`./scripts/verify.sh` runs all three checks in one go if you would rather not do
them by hand.

---

## 6. One run is not a result

Every wall-clock number above moves between runs, so a single measurement says
very little.

For a figure worth quoting, either:

- repeat 6 times with the build order alternating, which is what `run.sh` does,
  and apply the rules in `README.md` section 5; or
- use the **instruction counts**, which are exact and need no repetition at all.

The instruction counts are the primary evidence in the report for exactly this
reason.
