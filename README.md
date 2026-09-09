# OpenTargetCalls

> **Open, vendor-independent targeted calling for difficult genomic loci.**

The project aims to call medically relevant loci from short-read WGS and
supported WES assays, with explicit no-calls when evidence is insufficient.
Instrument vendor is not an eligibility restriction; analytical accuracy must
be validated per platform, chemistry, library, assay and target.

The current package is `phase_tools-rs` and its executable is `phase-tools`.
The toolbox is available as the [v0.1.0 source release](https://github.com/sounkou-bioinfo/phase_tools-rs/releases/tag/v0.1.0).
OpenTargetCalls development does not preserve toolbox commands or compatibility
aliases. Native alignment I/O and empirical calibration are planned, not implemented.
See [the Rust workspace design](docs/architecture.md), [I/O contract](docs/io.md)
and [empirical error model](docs/error-model.md). The [mapchk source assessment](docs/research/mapchk.md)
explains Heng Li's SBX error measurements with executable synthetic fixtures.

## Closed target scope

The registry is finite. It contains HLA and KIR through the
[Unum](https://github.com/fg-labs/unum) Rust port of T1K, plus every target in
the Illumina DRAGEN v4.5 Targeted Caller set.

| Target | WGS | WES | Current backend | State |
|---|---:|---:|---|---|
| HLA | yes | capture-dependent | Unum/T1K lane | runnable |
| KIR | yes | capture-dependent | Unum/T1K lane | runnable |
| CYP2B6 | yes | no | native paralog lane | contract only |
| CYP2D6 | yes | no | native paralog lane | contract only |
| CYP21A2 | yes | no | native paralog lane | contract only |
| GBA | yes | no | native paralog lane | contract only |
| HBA | yes | validated enrichment only | native integer solver | solver kernel |
| LPA | yes | no | native repeat-CN lane | contract only |
| RH | yes | no | native blood-group/paralog lane | contract only |
| SMN | yes | validated enrichment only | native paralog lane | contract only |

“Closed” means that target-dependent code must exhaust this enum and the Lean
proof checks the same finite set. It does **not** mean that unfinished callers
are represented as finished. A `contract-only` target cannot issue a valid
`called` certificate.

The WES entries are observability contracts, not marketing labels. HBA and SMN
require a declared, validated target-enrichment profile. Every target still has
read/depth/evidence quality gates after this assay-level check.

## Two algorithmic lanes

### 1. HLA/KIR allele typing

`phase-tools unum` executes the maintained Unum backend without a shell. Unum
owns candidate-read extraction, allele k-mers, banded alignment, abundance
estimation, and allele inference. This repository owns:

- the HLA/KIR-only backend boundary;
- WGS/WES observability declarations;
- input, resource, and result hashes;
- normalized call cardinality;
- a decision record with metadata consistency checks.

This avoids copying the T1K port into a second codebase. Direct `unum-core`
embedding should wait for a stable end-to-end library API; the current
high-level driver lives in the Unum binary crate.

### 2. Copy-number/paralog/repeat targets

The native lane consumes typed evidence rather than pretending all loci share
one pileup caller. Its evidence vocabulary includes unique and total depth,
paralog-differentiating sites, junction reads, small variants, repeat-spanning
reads, and phase links.

The first executable kernel is HBA hypothesis selection. It takes a versioned,
resource-defined hypothesis catalogue and integer-valued evidence. Candidate
penalties are computed as:

```text
prior_penalty
  + sum(ceil(abs(observed - expected) / tolerance) * weight)
```

The unique minimum must beat the runner-up by the requested margin. Otherwise
the result is an explicit no-call. Integer arithmetic makes the exact decision
portable and suitable for deterministic tests and mathematical specification. Feature extraction,
normalization, population hypothesis resources, and analytical validation are
still separate work; the synthetic example is not a clinical HBA resource.

## Build and test

```bash
make test
make proof
make release
```

Lean is pinned in `lean-toolchain`; the current Rust package has no runtime
crate dependencies. Planned I/O dependencies are described in the design.

## Inspect the target contract

```bash
cargo run -- targets
cargo run -- targets --assay wes
cargo run -- targets --assay wes --validated-enrichment
```

## Run the synthetic HBA solver example

```bash
cargo run -- hba \
  --assay wgs \
  --evidence examples/hba/evidence.synthetic.tsv \
  --hypotheses examples/hba/hypotheses.synthetic.tsv \
  --min-margin 10 \
  --certificate /tmp/hba.cert

cargo run -- verify --certificate /tmp/hba.cert
```

## Run HLA/KIR through Unum

```bash
cargo run -- unum \
  --target HLA \
  --assay wgs \
  --unum /path/to/unum \
  --bam sample.bam \
  --ref-seq hla.ref.fa \
  --ref-coord hla.coord.fa \
  --bam-mode alignment \
  --output-prefix results/sample.hla \
  --threads 8 \
  --certificate results/sample.hla.cert
```

KIR uses the same command with a KIR reference. Resource construction and
versioning remain Unum responsibilities.

## Lean research and decision records

Lean specifies registry, assay and decision-state properties for research and
future paper models. The current proofs establish properties of that Lean
model, including the stated winner/margin inequality. They do not establish
Rust equivalence, recompute evidence, or prove the winner's optimality over
actual candidate scores.

The current `--certificate` and `verify` commands check supplied metadata
fields. `verify` does not reopen the hashed artifacts or rerun inference.
Hashes describe identity, not biological validity or authenticity. Calibration,
independent truth and implementation correspondence require separate evidence.

See [the architecture](docs/architecture.md),
[the closed scope](docs/scope.md), [the roadmap](docs/roadmap.md), and
[the assurance boundary](docs/certificates.md).
