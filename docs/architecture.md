# OpenTargetCalls architecture

## Mission and implementation status

OpenTargetCalls is an independent, vendor-neutral targeted-calling project for
short-read WGS and supported WES assays. Its scope is the DRAGEN v4.5 targeted
loci plus HLA and KIR. Instrument vendor is not an eligibility gate. Analytical
validation is specific to instrument, chemistry, library preparation, assay,
aligner, reference and target; accepting a file does not establish accuracy.

The executable currently consists of the `phase_tools` library and `phase-tools`
CLI: a target registry, an Unum HLA/KIR adapter, an HBA prepared-evidence solver,
and decision-record checks. Native alignment I/O and empirical calibration are
not implemented. The structure below is the implementation design, not a list
of available APIs. GitHub, package and executable renames are separate release
operations.

## Language decision

Use **Rust for application code, evidence extraction and statistical kernels**.
Keep a narrow adapter to established native libraries where that avoids
reimplementing file-format or numerical semantics. Start alignment I/O with
`rust-htslib`/HTSlib; qualify a pure-Rust backend before promoting it.

Rust's ownership and type system suit reusable read buffers, bounded parallel
workers, coordinate distinctions and explicit missing-data states. It does not
make a statistical model correct or eliminate unsafe code inside dependencies.
C would simplify direct HTSlib integration and a public C ABI, but would put
buffer lifetime and concurrency safety on this project. Neither a C ABI nor a
C-only deployment is currently required. A wholesale rewrite has no demonstrated
benefit for the existing Rust kernels.

The trade-off is a Rust toolchain plus native HTSlib build dependencies. Preserve
an offline-buildable dependency lock and an audited native feature set. Profile
before adding SIMD or custom allocation. See [the source assessment and I/O
qualification plan](io.md#backend-decision).

## Crate structure

Use a workspace with three crates, introduced with working code and tests:

```text
Cargo.toml                         workspace and shared build settings
crates/
  otc-core/                        no filesystem, processes or HTS dependencies
    src/
      lib.rs
      coordinates.rs               assembly-bound intervals and event positions
      observation.rs               backend-independent read/event views
      calibration/                 counts, fitting and frozen model evaluation
      evidence/                    target-specific sufficient statistics
      targets/                     registry and target-specific inference
      decision.rs                  calls, no-calls and evidence support
  otc-io/                          HTS and resource format boundaries
    src/
      lib.rs
      alignment.rs                 reader/header/query ownership
      reference.rs                 indexed reference identity and fetching
      htslib.rs                    initial alignment backend
      resources.rs                 versioned resources and model serialization
      output.rs                    structured results and run manifests
  opentargetcalls/                  binary, not a second algorithm library
    src/
      main.rs
      pipeline.rs                  planning, budgets and stage orchestration
      backends/unum.rs             external process boundary
PhaseTools.lean
PhaseTools/                        Lean models for research
examples/
tests/fixtures/                    licensed, bounded, reproducible fixtures
benches/                           decode, accumulation and end-to-end workloads
docs/
```

Dependency direction:

```text
opentargetcalls --> otc-io --> otc-core
       |______________________^
```

`otc-core` defines observation and decision types; `otc-io` implements readers
that supply them. Core models consume typed observations or sufficient
statistics, never HTSlib/seqair records or filesystem paths. Model fitting can
therefore be tested without a reader, and readers can be qualified without a
caller. This is the reason for three crates rather than one crate per target
or one undifferentiated executable.

Each crate owns its unit tests; integration fixtures live with the consuming
crate, using shared fixture data only where needed. End-to-end CLI tests belong
to `opentargetcalls`. No crate depends on the executable. Targets remain modules
until an independent consumer or dependency boundary justifies a split.

Application Rust remains safe Rust. The core forbids `unsafe`. The initial I/O
adapter uses the safe `rust-htslib` interface; any future local unsafe kernel
requires an isolated boundary, explicit lifetime/length contracts, scalar oracle
and independent review. Native dependencies remain outside Rust's safety proof.

### Migration boundaries

- `src/model.rs`, `src/registry.rs` and the pure part of `src/hba.rs` become core
  types and target modules.
- HBA TSV parsing/writing moves to `otc-io`; the scoring function stays pure.
- `src/unum.rs` is split between CLI process orchestration, I/O output parsing
  and core normalized results. Backend failures remain errors.
- Decision-record serialization, resource hashes and artifact loading belong
  to I/O; semantic decision checks belong to core.
- Define the `opentargetcalls` command and result contracts on their own merits.
  Command names, options, schemas and internal APIs may break compatibility;
  compatibility aliases and preservation of toolbox behavior are out of scope.
  Reuse kernels only where they satisfy the new evidence/model contracts.
  Workspace restructuring does not certify any new target.

Do not create empty crates or speculative public traits. The first workspace
change must migrate a working core and add a minimal reader fixture.

## Pipeline

```text
alignment + reference + assay/run metadata + versioned resources
                              |
                   validate and plan intervals
                              |
             +----------------+-----------------+
             |                                  |
   calibration controls                  target/homolog regions
             |                                  |
   raw counts + held-out split          raw target observations
             |                                  |
   fit and validate frozen model -------------->|
                                                |
                         target-specific evidence and likelihoods
                                                |
                           inference and calibrated decision gates
                                                |
                      calls / typed no-calls + manifest + diagnostics
```

The initial implementation uses two logical stages: fit on controls, then apply
a frozen model to target evidence. The physical scans may be separate indexed
queries. A supplied compatible model skips fitting. See [empirical error
modeling](error-model.md) for training assumptions, abstention and validation.

Reuse one decoding pass for consumers only when their interval, ordering,
filter and retained-state requirements agree. A permissive read stream can feed
separate calibration and evidence filters; counts remain independently
queryable and tested. HLA/KIR extraction remains owned by Unum until its library
interface and semantics justify embedding. No shared scan is claimed across
that external process boundary.

The first implementation may reread target intervals after fitting. This costs
I/O but avoids an unbounded read cache and prevents scoring early reads with a
different model from late reads. Retain raw sufficient statistics only where
they are sufficient for the eventual likelihood. A base-error lookup cannot
be retroactively applied to a depth-only total.

## Policies and reproducibility

- **Coordinates:** internal zero-based half-open intervals tied to a reference
  identity. File-specific conversions occur at I/O boundaries.
- **Read versus fragment:** the observation unit, overlap handling, duplicate
  policy and supplementary-alignment use are declared per metric.
- **Missingness:** zero evidence, unavailable data, incompatible calibration,
  biological ambiguity and software failure are distinct states.
- **Workers:** independent reader handles; bounded queues and tile ownership;
  one global budget for decode, compute and subprocess threads.
- **Reductions:** checked integer counts merge exactly. Fitting and floating
  inference use a fixed order with declared tolerances. Thread-count changes
  must not silently alter a call near a decision threshold.
- **Resources:** reference, controls, masks, hypotheses and model parameters
  have schema versions, content identities and derivation metadata.
- **Outputs:** expose evidence counts, effective support, rejected observations,
  model support and decision reasons separately. A software or format error is
  not an `insufficient-evidence` no-call.

## Lean and paper models

Keep Lean as a research specification and proof environment. Priority theorems
are count/reduction laws, probability bounds, scoring definitions, abstention
conditions and selection under stated assumptions. A paper must distinguish:

1. the mathematical model and its assumptions;
2. a theorem about that model;
3. the tested or proved connection to executable Rust;
4. empirical support on independent biological data.

The present decision-record checks are metadata consistency checks. They do not
recompute evidence or prove Rust/Lean equivalence. A content hash records
identity, not truth or authentication. See [the assurance boundary](certificates.md).

## Delivery order

1. Qualify I/O and reference semantics on small adversarial fixtures.
2. Collect inspectable calibration counts and fit a conservative baseline.
3. Validate model generalization across held-out loci, samples and runs.
4. Add HBA evidence extraction and evaluate depth and paralog likelihoods.
5. Extend targets after a target-specific validation gate.

Detailed acceptance criteria are in [the roadmap](roadmap.md). Mapping FASTQ to
whole-genome alignments, a new BAM/CRAM codec, and generic public utility
commands are outside this initial implementation.
