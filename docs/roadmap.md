# OpenTargetCalls implementation roadmap

Native I/O and empirical models are planned, not implemented. Existing runnable
code provides the registry, the external Unum adapter and the prepared-evidence
HBA scoring kernel. Every milestone below requires executable acceptance tests.

## 1. Workspace and qualified I/O

- Introduce `otc-core`, `otc-io` and `opentargetcalls` with the dependency
  boundaries in [the architecture](architecture.md).
- Test the OpenTargetCalls API directly, with pure scoring separated from
  parsing and process execution. No compatibility CLI or schema layer is
  required; toolbox users build the frozen source release.
- Pin and build the first `rust-htslib` backend with an explicit feature set.
- Validate reference, sample/read-group selection and indexed BAM/CRAM queries.
- Emit normalized base/event observations and inspectable integer counters.
- Pass [the I/O fixture matrix](io.md#qualification-and-performance-gates),
  including repeat anchors, overlap, missing quality and malformed inputs.
- Establish decode and end-to-end extraction baselines before qualifying seqair.

Deliverable: a bounded, correct observation stream with no inferred genotype.

## 2. Error measurement and calibration baseline

- Specify substitution, insertion/deletion-event and repeat-span opportunities.
- Acquire versioned truth/control/mask resources and document permissions.
- Accumulate counts by run/group, quality, read position and supported context.
- Keep [mapchk-r352 characterization](research/mapchk.md) separate from native
  denominators; extend reference fixtures before claiming compatibility.
- Include SBX-style discrete-quality/repeat-placement fixtures from the start.
- Fit a frozen, regularized baseline with sparse-bin support/backoff reporting.
- Validate held-out calibration and uncertainty before target likelihood use.
- Write and reload a versioned model artifact with compatibility rejection tests.

Deliverable: reproducible empirical diagnostics and a validated model for the
specific training/evaluation domain. Insufficient truth or support blocks the
model release, not diagnostic data collection.

## 3. HBA extraction and likelihoods

- Collect unique/total fragment depth and matched control-bin normalization.
- Collect HBA1/HBA2 differentiating sites, junctions and local haplotype evidence.
- Model depth dispersion, fragment correlation and paralog-origin uncertainty
  separately from sequencing errors.
- Compare the prepared-evidence solver against calibrated likelihood models.
- Version chromosome haplotypes, including explicit out-of-catalogue behavior.
- Establish WGS and validated-enrichment WES truth benchmarks and no-call gates.

Deliverable: a target-specific caller only after truth-set acceptance, not on
the strength of an evidence interface or synthetic example.

## Parallel lane: HLA/KIR backend qualification

- Pin Unum and reference-resource versions and capture backend options.
- Add public or shareable WGS/WES end-to-end fixtures.
- Parse strict per-locus allele/abundance output with malformed-output errors.
- Define locus-level support and no-call rules; distinguish backend concordance
  from biological accuracy.

The external backend keeps its extraction semantics until a stable library API
and equivalence tests justify embedding.

## Target expansion

Follow demonstrated evidence reuse: SMN, GBA/CYP21A2, CYP2D6/CYP2B6, RH, then
LPA. Each target needs its own structural truth, observable assay domain and
resource completeness assessment. Registry presence is not implementation.

## Research and Lean

Retain Lean for paper/model work. Formalize merge laws, probability bounds,
score definitions and decision/abstention properties under stated assumptions.
State separately whether Rust correspondence is tested or formally established.
Metadata checks and hashes are not proof of biological or executable correctness.

## Acceptance for each platform and target

- Synthetic/adversarial invariants and deterministic reduction tests.
- Independent truth with identifiable sample, chemistry and basecaller versions.
- Held-out sample/run and genomic-block performance; no train/test leakage.
- WGS/WES/capture, ancestry, GC/repeat, depth and rare-structure stratification.
- Explicit abstention/error taxonomy and calibration-support reporting.
- Reproducibility across thread count and valid input orderings.
- Benchmarked memory, I/O, wall time and artifact construction costs.
- DRAGEN comparison where legally available, without making it the sole truth.

The vendor-neutral goal includes Illumina, GeneMind, BGI/MGI and SBX. Suitable
cross-platform data, use permissions and target truth remain acquisition tasks.
