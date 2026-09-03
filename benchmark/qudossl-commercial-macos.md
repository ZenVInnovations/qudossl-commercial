Unmodified upstream **OpenSSL 3.5.7** — the QudoSSL Commercial product (no Community/delegated build involved). Measured with OpenSSL's own `speed` and `perftools` handshake tools, median of 6 repetitions, single core. Higher is better.

## Environment

| | |
|---|---|
| CPU | Apple M4 |
| Architecture | arm64 |
| SIMD | neon |
| Cores | 10 |
| OS | macos |
| Kernel | Darwin 25.5.0 |
| OpenSSL | OpenSSL 3.5.7 9 Jun 2026 (Library: OpenSSL 3.5.7 9 Jun 2026) |

## Primitives — FIPS provider (`openssl speed`, operations / sec)

**Key encapsulation — ML-KEM and hybrid groups**

| Group | keygen | encapsulate | decapsulate |
|---|--:|--:|--:|
| ML-KEM-512 | 37,832 | 162,415 | 104,838 |
| ML-KEM-768 | 25,390 | 110,618 | 72,993 |
| ML-KEM-1024 | 17,513 | 78,903 | 53,515 |
| X25519MLKEM768 | 18,885 | 25,926 | 33,326 |
| SecP256r1MLKEM768 | 10,028 | 10,202 | 22,714 |
| SecP384r1MLKEM1024 | 554 | 478 | 2,636 |

**Signatures — ML-DSA**

| Algorithm | keygen | sign | verify |
|---|--:|--:|--:|
| ML-DSA-44 | 2,989 | 4,160 | 21,433 |
| ML-DSA-65 | 1,795 | 2,543 | 13,912 |
| ML-DSA-87 | 1,473 | 2,172 | 8,783 |

## Primitives — default provider (`openssl speed`, operations / sec)

**Key encapsulation — ML-KEM and hybrid groups**

| Group | keygen | encapsulate | decapsulate |
|---|--:|--:|--:|
| ML-KEM-512 | 96,771 | 160,008 | 104,620 |
| ML-KEM-768 | 61,303 | 110,372 | 72,286 |
| ML-KEM-1024 | 40,462 | 78,226 | 53,230 |
| X25519MLKEM768 | 32,162 | 25,590 | 32,741 |
| SecP256r1MLKEM768 | 39,080 | 21,241 | 22,330 |
| SecP384r1MLKEM1024 | 2,516 | 1,347 | 2,582 |

**Signatures — ML-DSA**

| Algorithm | keygen | sign | verify |
|---|--:|--:|--:|
| ML-DSA-44 | 23,262 | 4,162 | 21,468 |
| ML-DSA-65 | 12,263 | 2,563 | 13,980 |
| ML-DSA-87 | 9,131 | 2,157 | 8,835 |

## TLS 1.3 handshake (`perftools`, in memory, single core, ML-DSA-44 certificate)

| Provider | Key exchange | µs / handshake | Handshakes / sec |
|---|---|--:|--:|
| fips | X25519MLKEM768 | 586.4 | 1,705 |
| default | X25519MLKEM768 | 556.3 | 1,797 |
| default | SecP256r1MLKEM768 | 582.1 | 1,718 |
| default | X25519 | 497.6 | 2,010 |

## Provenance

| file | rows | sha256 |
|---|--:|---|
| `primitives.csv` | 216 | `52ef3b82ef1a08ce…` |
| `handshake.csv` | 60 | `4e253ac5d0cc7737…` |
| `environment.csv` | 13 | `9d8e3abace057568…` |

## Notes

- QudoSSL runs in **FIPS mode**; the FIPS tables are the primary figures. Under the FIPS provider **key generation is materially slower** (mandatory pairwise-consistency test); encapsulation, decapsulation, signing and verification match the default-provider rates.
- Wall-clock and **indicative**: CPU frequency, core type and scheduling all affect it. The handshake harness runs in memory with no network, so its rate is an upper bound, not a deployment throughput.
