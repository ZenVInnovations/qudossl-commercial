Unmodified upstream **OpenSSL 3.5.7** — the QudoSSL Commercial product (no Community/delegated build involved). Measured with OpenSSL's own `speed` and `perftools` handshake tools, median of 6 repetitions, single core. Higher is better.

## Environment

| | |
|---|---|
| CPU | Apple M4 (Linux arm64 container) |
| Architecture | aarch64 |
| SIMD | neon |
| Cores | 10 |
| OS | linux |
| Kernel | Linux 6.12.76-linuxkit |
| OpenSSL | OpenSSL 3.5.7 9 Jun 2026 (Library: OpenSSL 3.5.7 9 Jun 2026) |

## Primitives — FIPS provider (`openssl speed`, operations / sec)

**Key encapsulation — ML-KEM and hybrid groups**

| Group | keygen | encapsulate | decapsulate |
|---|--:|--:|--:|
| ML-KEM-512 | 40,175 | 177,007 | 109,199 |
| ML-KEM-768 | 27,592 | 132,512 | 80,420 |
| ML-KEM-1024 | 19,652 | 99,249 | 61,662 |
| X25519MLKEM768 | 20,399 | 25,966 | 33,176 |
| SecP256r1MLKEM768 | 10,549 | 10,520 | 23,816 |
| SecP384r1MLKEM1024 | 532 | 455 | 2,533 |

**Signatures — ML-DSA**

| Algorithm | keygen | sign | verify |
|---|--:|--:|--:|
| ML-DSA-44 | 2,355 | 3,304 | 17,600 |
| ML-DSA-65 | 1,486 | 2,003 | 11,447 |
| ML-DSA-87 | 1,177 | 1,752 | 7,338 |

## Primitives — default provider (`openssl speed`, operations / sec)

**Key encapsulation — ML-KEM and hybrid groups**

| Group | keygen | encapsulate | decapsulate |
|---|--:|--:|--:|
| ML-KEM-512 | 100,365 | 177,746 | 109,698 |
| ML-KEM-768 | 62,290 | 131,307 | 79,934 |
| ML-KEM-1024 | 40,737 | 100,080 | 61,510 |
| X25519MLKEM768 | 33,270 | 25,725 | 32,454 |
| SecP256r1MLKEM768 | 40,263 | 22,369 | 23,444 |
| SecP384r1MLKEM1024 | 2,421 | 1,315 | 2,529 |

**Signatures — ML-DSA**

| Algorithm | keygen | sign | verify |
|---|--:|--:|--:|
| ML-DSA-44 | 19,597 | 3,204 | 17,188 |
| ML-DSA-65 | 11,093 | 2,022 | 11,434 |
| ML-DSA-87 | 7,970 | 1,733 | 7,333 |

## TLS 1.3 handshake (`perftools`, in memory, single core, ML-DSA-44 certificate)

| Provider | Key exchange | µs / handshake | Handshakes / sec |
|---|---|--:|--:|
| fips | X25519MLKEM768 | 654.5 | 1,528 |
| default | X25519MLKEM768 | 633.0 | 1,580 |
| default | SecP256r1MLKEM768 | 659.3 | 1,517 |
| default | X25519 | 586.5 | 1,705 |

## Provenance

| file | rows | sha256 |
|---|--:|---|
| `primitives.csv` | 108 | `23643831068a0aee…` |
| `handshake.csv` | 24 | `0cc614a62658c495…` |
| `environment.csv` | 7 | `222289f92146a434…` |

## Notes

- QudoSSL runs in **FIPS mode**; the FIPS tables are the primary figures. Under the FIPS provider **key generation is materially slower** (mandatory pairwise-consistency test); encapsulation, decapsulation, signing and verification match the default-provider rates.
- Wall-clock and **indicative**: CPU frequency, core type and scheduling all affect it. The handshake harness runs in memory with no network, so its rate is an upper bound, not a deployment throughput.
