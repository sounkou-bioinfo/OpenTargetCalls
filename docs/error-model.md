# Empirical error model design

Status: proposed statistical and implementation contract. The current HBA
integer penalty is a prepared-evidence heuristic, not this model. No fitted
error model or platform accuracy claim is shipped.

## Objective

Estimate likelihood components for target evidence and report where they are
unsupported. Instrument identity describes the experiment; it does not grant
or deny eligibility. Calibration is tied to run/read group, chemistry,
basecaller and consensus version, preprocessing, aligner, reference and assay.
A model from one vendor, chemistry or run is not automatically transferable.

Separate four mechanisms:

| Channel | Observations and opportunities | Used for |
|---|---|---|
| Substitution | nonreference versus matching aligned bases in trusted controls | base/allele likelihoods |
| Insertion/deletion and repeat length | events and lengths per evaluable boundary or repeat-spanning fragment | local haplotype/junction likelihoods |
| Mapping/paralog assignment | placement alternatives and target-specific diagnostic evidence | uncertainty over homolog origin |
| Coverage and fragment structure | fragment depth, GC/mappability, library/capture and correlation | copy-number and evidence support |

A Phred base quality is not a mapping probability. Mapping quality is not a
sequencing-error measurement. Copy-number variation is not a high base-error
rate. PCR/duplex/UMI-derived observations are not independent simply because
they occupy distinct BAM records.

## Measurement before fitting

`otc-core::calibration` first accumulates inspectable integer counts. Every
artifact includes eligible opportunities, observed outcomes, excluded counts by
reason, and the policy/reference/control identities. Merge counts exactly with
checked arithmetic; fit only after the merge. Preserve raw reported qualities.

Report substitution rate X/A, where A is the number of eligible aligned
canonical bases; insertion and deletion event rates with their own opportunity
counts; and affected-base lengths separately. An indel event is not L
independent errors just because its length is L. Always name a denominator in
machine-readable output.

The [mapchk source assessment](research/mapchk.md) documents why this matters:
its reported empirical Q uses `(X + I + D) / (A + I + D)`, with event-counted
indels. Its repeat-aware insertion quality is useful, but that summary is not a
universal base-error probability. A `mapchk-r352` comparison view must be
separate from native calibration semantics.

### Opportunity definitions

- **Substitutions:** aligned A/C/G/T observations at reference-confirmed control
  positions, with known quality and eligibility. Unknown bases are missing,
  not a fifth true allele or a match.
- **Nonrepeat insertions:** read/fragment crossings of eligible reference
  boundaries with sufficient flanking support. Count one event presence and
  its length/sequence separately. Terminal/clipped ambiguous boundaries are
  unavailable, not negative insertion observations.
- **Deletions:** evaluable local reference windows with spanning support;
  specify the allowed length range and anchoring policy. Count a deletion once,
  not once per deleted pileup position. Missing coverage is not a deletion.
- **Repeats:** one observation per eligible fragment spanning a resource-defined
  repeat and its required flanks; outcome is the observed repeat-length change
  relative to the trusted control. Equivalent CIGAR placements share an event
  identity. Runs lacking reliable flanking support are not negative controls.

Resources define these opportunities before observing discrepancies. Otherwise
conditioning inclusion on a clean-looking alignment would hide the errors we
are trying to estimate. Initial isolated-event and repeat-span collectors need
synthetic oracles and truth-controlled examples before model fitting. Complex
local alignments require explicit uncertainty, not forced event labels.

## Calibration data and exclusion

Preferred training regions are independently established high-confidence,
uniquely mappable homozygous-reference controls in the same specimen, or a
matched truth-characterized calibration sample. Pin genotype/truth versions,
reference assembly and callable intervals. Establish control truth and inclusion
independently of the aligner/preprocessing pipeline being evaluated; selecting
only its apparently clean alignments would bias the measured error rate.
Exclude known variation, uncertain
truth, target loci and their homologous regions from the generic sequencing-
error fit. Independent truth may support additional genotype-conditioned
training, but that is a separate model.

When only a reference and known-site masks are available, report
**reference-discrepancy calibration**. Unmasked true variants remain confounded
with errors. An allele-frequency cutoff cannot establish truth and can hide
recurrent technical errors. Such data may support diagnostics; production
likelihood calibration requires validation of that approximation.

Use explicit filters for primary mapping, flags, MAPQ availability, sequence,
quality, clipping and reference context. Initial calibration excludes duplicate
and QC-fail records and unresolved overlapping mate bases. Target extraction
uses separate policies and may retain low-MAPQ or supplementary observations.
Do not remove paralog evidence just because it is unsuitable for training.

WES controls must be observable under the actual capture, with matching
library/batch metadata. High target depth does not compensate for narrow
context support. No automatic WGS-to-WES or cross-panel pooling is permitted.
Generic high-MAPQ calibration also cannot establish performance in ambiguous
paralog alignments; those require target-specific truth and likelihood checks.

## Covariates and quality semantics

Start with a small supported set and publish per-bin support:

- run/read group and library, with explicit sample association;
- reported quality as observed, including discrete/binned scores;
- read1/read2/single-end status;
- sequencing-oriented stored read position and distance from the other end;
- trusted reference context in a consistent orientation;
- event type, length, homopolymer/repeat motif and run length;
- declared consensus/duplex state where metadata supports it.

Use read-length/end-position bins and marginal diagnostics before fitting a
large interaction table. Reported platform (`PL`) alone does not define a
pooling group. Missing MAPQ/quality/context/duplex information has explicit
missing states. Hard clipping or unknown trimming precludes claiming original
machine cycles; see [I/O semantics](io.md#read-and-event-semantics).

### SBX-style consensus qualities

The SBX data discussed in Heng Li's September 2025 post used Q39, Q22 and Q5
as consensus-support categories. A continuous Phred calibration curve is
therefore not the only meaningful starting point. Preserve categorical quality
and read-end position, and test their association with event errors.

If versioned metadata establishes those semantics, attach the corresponding
support category. An observed Q39 is not by itself proof of duplex support on
an unknown run. With only a BAM and no basecaller declaration, analyze Q as a
reported category and mark the biological interpretation unavailable.

For insertion events, retain the CIGAR interval, equivalent repeat interval,
inserted-base qualities and repeat minimum. The minimum is a diagnostic feature,
not a replacement for every base quality or an assumed event posterior. Learn
repeat-length/event likelihoods against controlled truth. Test left/right-
aligned equivalent insertions, a low-Q base at either end, reverse reads,
multibase motifs and varying read length. BAM-only analysis cannot recover raw
signals or reconstruct independent strands that were collapsed upstream.

## Conservative first fit

Use an interpretable, regularized count model before a high-dimensional learner.
For a substitution bin c with n opportunities and m errors, a baseline estimate
is:

```text
p_c = (m + kappa * p_parent) / (n + kappa)
```

Here `p_parent` is a supported coarser-bin estimate and `kappa > 0` controls
shrinkage. This is a regularized estimator; empirical parent fitting does not
by itself yield exact Bayesian credible intervals. Fit priors, binning and
shrinkage on training/development partitions, not the final evaluation set.

Use a versioned backoff path: group/quality with supported position/context
effects, then group/quality, then an explicitly validated pool. Do not force
monotonicity or manufacture support for unseen qualities/chemistries. An
unvalidated terminal pool means unavailable calibration, not a silently
borrowed Illumina model.

Estimate a conditional substitution spectrum as data allow. Assigning p/3 to
every alternate base is an explicit baseline assumption, not an empirical
result. Fit separate event-presence and length distributions for insertion,
deletion and repeat changes; each requires its opportunity definition. Do not
reuse substitution p as an indel-open or indel-extension probability.

Count intervals and uncertainty are essential at high Q: zero errors in a
small bin do not imply perfect accuracy. Use block/bootstrap assessments at
fragment and genomic-block levels, and replicate runs where possible, to expose
correlation. A binomial interval is only a diagnostic under its independence
assumption. Unsupported bins propagate to a model-support state and, where the
target requires them, an explicit no-call. Format corruption remains an error.

Persist a frozen model with counts, hyperparameters, support/backoff choices,
training exclusions, reference/resource identities and software version. Applying
it validates compatibility before reading target evidence. Apply/calibrate
stages may reread indexed regions; online adaptation must not make calls depend
on input order.

## Coverage and mapping are separate models

Copy-number work needs matched control-bin normalization and residual variance
by GC, mappability, capture and library. Start with inspectable robust
normalization; evaluate Poisson versus overdispersed count likelihoods on
held-out truth. Carry uncertainty from normalization into CN inference. Do not
label the current weighted HBA distance as a calibrated likelihood.

Paralog likelihoods must represent alternative origins rather than multiply
independent per-site scores for correlated reads. Fragment overlap, local
haplotypes, gene conversions and reference bias need target-specific tests.
A global MAPQ-to-error conversion is not sufficient. Target truth validation
must include rare structures and out-of-catalogue haplotypes.

## Validation and research gates

- Test count conservation, event/opportunity units, reverse orientation,
  missingness, repeat placement and deterministic merges.
- Split genomic blocks and fragments before fitting; reserve independent
  samples/runs for external evaluation. Randomly splitting bases from the same
  reads or loci is not an independent test.
- Report held-out predicted-versus-observed rates, log loss, Brier score,
  support/coverage and uncertainty, stratified by event, context, quality,
  position and platform/run. Include read-end and repeat-specific diagnostics.
- Evaluate recurrence by allele/event identity and independent fragments, not
  merely insertion/deletion class. Separate systematic errors from variants
  using truth where available.
- Compare reported-quality, uncalibrated and fitted baselines. Release a model
  only with predeclared target error/abstention criteria and compatible evidence.
- Seek matched truth material across Illumina, BGI/MGI, GeneMind and SBX. Data
  availability, permissions and chemistry/basecaller metadata remain to be
  established. Do not claim validation for platforms without suitable data.

Lean research can formalize sufficient-statistic merge laws, estimator bounds,
likelihood definitions and abstention/selection properties under explicit
assumptions. It cannot prove empirical representativeness or Rust equivalence
without a separate implementation connection. No paper theorem is claimed by
this design.

## Method references

- [GATK BQSR overview](https://gatk.broadinstitute.org/hc/en-us/articles/360035890531-Base-Quality-Score-Recalibration-BQSR):
  reference-mismatch calibration, known-site masking and quality covariates.
  This design does not claim GATK algorithm/output compatibility.
- [Heng Li's SBX post and pinned mapchk source](research/mapchk.md): event
  counting, tandem-repeat insertion-quality attribution and its limitations.
