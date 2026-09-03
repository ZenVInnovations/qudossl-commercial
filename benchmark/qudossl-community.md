# qudossl crypto benchmark

qudossl (OpenSSL 3.5.7 with ML-KEM and ML-DSA delegated to qudo-pqc) against pristine OpenSSL 3.5.7, measured with the benchmark tools published by OpenSSL and by the rustls project, each built once against each tree.

## Instruction counts

`instructions.csv` absent - run `./scripts/run-instr.sh`.

## Primitives

`openssl speed`, the tool OpenSSL ship for this purpose. These cells isolate the delegated math: no classical algorithm is involved, so the whole measured difference is ML-KEM or ML-DSA.

| mode | algorithm | operation | qudossl op/s | openssl op/s | ratio |
|---|---|---|---|---|---|
| default | ML-KEM-1024 | keygen | 86,466 | 40,363 | 2.142x |
| default | ML-KEM-1024 | encaps | 110,321 | 78,106 | 1.413x |
| default | ML-KEM-1024 | decaps | 84,004 | 52,824 | 1.591x |
| default | ML-KEM-512 | keygen | 170,814 | 96,084 | 1.778x |
| default | ML-KEM-512 | encaps | 244,262 | 159,685 | 1.530x |
| default | ML-KEM-512 | decaps | 186,739 | 104,414 | 1.788x |
| default | ML-KEM-768 | keygen | 115,392 | 61,131 | 1.888x |
| default | ML-KEM-768 | encaps | 155,872 | 110,265 | 1.414x |
| default | ML-KEM-768 | decaps | 121,236 | 71,580 | 1.695x |
| default | SecP256r1MLKEM768 | keygen | 55,570 | 39,097 | 1.421x |
| default | SecP256r1MLKEM768 | encaps | 22,424 | 21,196 | 1.058x |
| default | SecP256r1MLKEM768 | decaps | 25,522 | 22,285 | 1.145x |
| default | SecP384r1MLKEM1024 | keygen | 2,639 | 2,521 | 1.047x |
| default | SecP384r1MLKEM1024 | encaps | 1,387 | 1,348 | 1.029x |
| default | SecP384r1MLKEM1024 | decaps | 2,707 | 2,593 | 1.044x |
| default | X25519MLKEM768 | keygen | 42,858 | 32,153 | 1.333x |
| default | X25519MLKEM768 | encaps | 27,253 | 25,543 | 1.067x |
| default | X25519MLKEM768 | decaps | 39,174 | 32,559 | 1.204x |
| default | ML-DSA-44 | keygen | 34,280 | 23,190 | 1.478x |
| default | ML-DSA-44 | sign | 10,940 | 4,151 | 2.636x |
| default | ML-DSA-44 | verify | 38,768 | 21,428 | 1.809x |
| default | ML-DSA-65 | keygen | 16,936 | 12,269 | 1.380x |
| default | ML-DSA-65 | sign | 7,030 | 2,566 | 2.740x |
| default | ML-DSA-65 | verify | 23,826 | 13,980 | 1.704x |
| default | ML-DSA-87 | keygen | 12,921 | 9,140 | 1.414x |
| default | ML-DSA-87 | sign | 5,648 | 2,157 | 2.619x |
| default | ML-DSA-87 | verify | 14,503 | 8,804 | 1.647x |
| fips | ML-KEM-1024 | keygen | 30,063 | 17,515 | 1.716x |
| fips | ML-KEM-1024 | encaps | 109,852 | 78,732 | 1.395x |
| fips | ML-KEM-1024 | decaps | 83,835 | 53,509 | 1.567x |
| fips | ML-KEM-512 | keygen | 63,418 | 37,797 | 1.678x |
| fips | ML-KEM-512 | encaps | 243,426 | 162,167 | 1.501x |
| fips | ML-KEM-512 | decaps | 186,141 | 104,625 | 1.779x |
| fips | ML-KEM-768 | keygen | 42,045 | 25,376 | 1.657x |
| fips | ML-KEM-768 | encaps | 155,459 | 110,507 | 1.407x |
| fips | ML-KEM-768 | decaps | 120,056 | 72,945 | 1.646x |
| fips | SecP256r1MLKEM768 | keygen | 12,014 | 10,024 | 1.199x |
| fips | SecP256r1MLKEM768 | encaps | 10,453 | 10,181 | 1.027x |
| fips | SecP256r1MLKEM768 | decaps | 25,729 | 22,433 | 1.148x |
| fips | SecP384r1MLKEM1024 | keygen | 564 | 545 | 1.037x |
| fips | SecP384r1MLKEM1024 | encaps | 475 | 473 | 1.004x |
| fips | SecP384r1MLKEM1024 | decaps | 2,684 | 2,623 | 1.023x |
| fips | X25519MLKEM768 | keygen | 27,033 | 18,874 | 1.432x |
| fips | X25519MLKEM768 | encaps | 27,672 | 25,888 | 1.069x |
| fips | X25519MLKEM768 | decaps | 40,619 | 33,182 | 1.224x |
| fips | ML-DSA-44 | keygen | 6,770 | 2,984 | 2.269x |
| fips | ML-DSA-44 | sign | 11,046 | 4,148 | 2.663x |
| fips | ML-DSA-44 | verify | 38,745 | 21,443 | 1.807x |
| fips | ML-DSA-65 | keygen | 4,111 | 1,797 | 2.289x |
| fips | ML-DSA-65 | sign | 7,087 | 2,541 | 2.790x |
| fips | ML-DSA-65 | verify | 23,934 | 13,907 | 1.721x |
| fips | ML-DSA-87 | keygen | 3,076 | 1,469 | 2.094x |
| fips | ML-DSA-87 | sign | 5,640 | 2,168 | 2.602x |
| fips | ML-DSA-87 | verify | 14,546 | 8,788 | 1.655x |

**54 cells measured. 44 showed a consistent difference in every repetition, spanning 1.15x to 2.79x.**

## TLS handshake

OpenSSL's `perftools/handshake`: a combined in-memory client and server, no socket. Lower microseconds is better, so the ratio is inverted to keep "higher is better for qudossl" consistent with the other tables.

| mode | group | qudossl us | openssl us | ratio |
|---|---|---|---|---|
| default | SecP256r1MLKEM768+ML-DSA-44 | 384.9 | 587.9 | 1.528x |
| default | X25519+ECDSA | 243.7 | 241.9 | 0.993x |
| default | X25519+ML-DSA-44 | 322.4 | 498.8 | 1.547x |
| default | X25519MLKEM768+ML-DSA-44 | 358.0 | 557.4 | 1.557x |
| fips | X25519MLKEM768+ML-DSA-44 | 382.0 | 588.9 | 1.542x |

Cells are named `<key exchange>+<signature>`.

- **`X25519+ECDSA`** - the negative control. Nothing is delegated on either side, so it must read parity.
- **`X25519MLKEM768+ML-DSA-44`** - the deployment case: both the key exchange and the signature are delegated.
- `X25519+ML-DSA-44` isolates the signature. Note it still shows a large difference despite the classical key exchange, because the ML-DSA certificate is delegated - which is why it is not a control.

## Session resumption

`resumption.csv` absent.

## Memory

`memory.csv` absent.

---

## Limitations

| | measured on |
|---|---|
| CPU | Apple M4 |
| architecture | arm64 |
| SIMD available | neon |
| cores | 10 |
| OS | macos |
| kernel | Darwin 25.5.0 |
| measured | 2026-08-24T07:08:25Z |

### The two builds

Both report the same version, because qudossl **is** OpenSSL 3.5.7 with the ML-KEM and ML-DSA cores delegated to qudo-pqc; the version string is deliberately not rebranded. They are separate trees, built and linked independently.

| | qudossl | openssl |
|---|---|---|
| version | OpenSSL 3.5.7+qudo-1.0.0 9 Jun 2026 (Library: OpenSSL 3.5.7+qudo-1.0.0 9 Jun 2026) | OpenSSL 3.5.7 9 Jun 2026 (Library: OpenSSL 3.5.7 9 Jun 2026) |

- **Wall-clock figures are host-dependent.** CPU frequency, core type and thread placement all affect them and none is controlled here. The instruction counts are far more stable - about 2% - though not exact, for the reason given in that section.
- **No network is involved anywhere in this suite.** Every figure is an in-process measurement. Deployment behaviour under real traffic is not characterised here.
- **`openssl speed -seconds 2`** is used; upstream's default for this operation class is 10 s. More repetitions at 2 s were preferred to fewer at 10 s, because a disturbed window is a disturbed sample at either length.
- **arm64, SIMD available: neon.** qudo-pqc selects its backend at runtime, so only the path this CPU offers was exercised. Other architectures, and any SIMD level absent above, are not covered by these ratios.


## Provenance

| file | rows | sha256 |
|---|---|---|
| `environment.csv` | 13 | `9d8e3abace0575688dd44948739fac72d64db19a613781c7259ecd4206dd3ef6` |
| `handshake.csv` | 60 | `4e253ac5d0cc773770bf4b7e9bed494c37be514ea7081506817606cdc30ca66c` |
| `primitives.csv` | 216 | `52ef3b82ef1a08ce1d1e6c6aa00eaa55db687e4f6b1884b9730c912726fe8bc2` |

Tools: OpenSSL perftools and ctz/openssl-bench, both vendored under
`benchmark/`, each built once against each OpenSSL tree.

Generated 2026-08-24T07:38:44Z on Darwin 25.5.0 arm64.
