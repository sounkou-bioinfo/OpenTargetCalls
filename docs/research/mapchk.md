# Heng Li's mapchk empirical error statistic

## Source and scope

Heng Li's [11 September 2025 SBX post](https://lh3.github.io/2025/09/11/a-quick-look-at-roches-sbx)
links directly to `htsbox`'s `mapchk.c`. This assessment uses the MIT-licensed
[lite branch at r352, c901cb3a3324c119988f4bcd4412cbe48e1b5a38](https://github.com/lh3/htsbox/tree/c901cb3a3324c119988f4bcd4412cbe48e1b5a38),
including its vendored HTSlib. The relevant source is
[`mapchk.c`](https://github.com/lh3/htsbox/blob/c901cb3a3324c119988f4bcd4412cbe48e1b5a38/mapchk.c).

This is a source assessment and a small executable characterization. The blog's
complete analysis commands, inclusion regions and plotting workflow were not
recovered. The tests below do not reproduce its reported Q21/Q37 curves or
validate Roche data. Its Q5/Q22/Q39 interpretation describes that release's
basecaller, not every SBX chemistry or future version.

## What is counted

`mapchk` reads BAM and a reference FASTA and uses reference-position pileups.
The statistics array has axes:

```text
sequencing-oriented stored read position
  x reported/event quality (0..93)
  x read base (A, C, G, T, other)
  x reference base or event (A, C, G, T, other, insertion, deletion, clip)
```

For each eligible aligned A/C/G/T observation, it adds one match or mismatch.
An insertion or deletion attached to that anchor adds **one extra event**,
regardless of indel length. Deleted pileup positions are skipped, not counted
as substitutions. Clipping is not included in the reported rate. Ambiguous
reference sites are skipped; noncanonical read bases do not contribute to the
printed totals.

Let M be aligned matches, X substitutions, I insertion events and D deletion
events after filtering. `print_stat` computes approximately:

```text
N = M + X + I + D
E = X + I + D
Q = trunc(-4.343 * ln((E + 1e-6) / (N + 1e-6)))
```

The factor is an approximation to the Phred conversion. This is an
**event-augmented alignment discrepancy statistic**, not X divided by aligned
bases, an edit-distance-per-base rate, or a genotype error rate. The epsilon
makes zero-error outputs finite but is not an uncertainty model. Empty bins
also produce numeric-looking output and must not be interpreted as measured
accuracy.

The output contains an `ALL` row followed by one-based stored-read positions.
Each row has an overall Q, low/high observation totals split at `-q` (default
20), and base-specific Q/error-composition strings. Reverse alignments reverse
the stored query position and complement read/reference bases. Indel events
are assigned to the aligned anchor's position, not each inserted or deleted
base. Original machine cycles lost through trimming cannot be recovered.

## Variant exclusion and recurrent errors

This implementation does not accept a truth VCF. At each site it computes
high-quality support and heuristically skips a site when:

```text
n_high >= 3 and n_var / n_high > fthres
```

The default `fthres` is 0.35. This can remove many heterozygous/homozygous
variants, but also removes sufficiently frequent systematic errors. Low-depth
variants may survive. `-b` is an inclusion BED, not a known-variant mask.

An important r352 asymmetry: high-quality SNP/deletion observations increment
`n_var`; the insertion branch increments `n_high` and insertion support but
**does not increment `n_var`**. Thus this is not a uniform allele-frequency
filter across event types. It must not be described as truth-based error
identification.

`-d N` retains an observation/event only when its category has at least N
high-quality observations at that reference site. For example, `-q 30 -d 2`
selects categories with two or more Q30+ supports. This is a recurrence
heuristic, not independent molecule support. Insertions and deletions are
counted by event class, without distinguishing sequence or length. Low-quality
observations can also enter a supported category's low-quality bin. `-1` and
`-2` exclusions apply when filling statistics, after site support/filtering.

## The SBX insertion-quality adjustment

Two commits on the post's date implement the change:

- [r351, 3c207b0](https://github.com/lh3/htsbox/commit/3c207b0c49f5c79be2a11f07977ac2a17bc2af0a):
  give insertions their own quality, including a homopolymer adjustment.
- [r352, c901cb3](https://github.com/lh3/htsbox/commit/c901cb3a3324c119988f4bcd4412cbe48e1b5a38):
  extend the adjustment to tandem repeats in both directions.

For an insertion of length L after query position x, r352 starts with the
inserted query interval `[x+1, x+L+1)`. It extends left and right while sequence
characters agree at separation L, within read bounds. The insertion quality
is the minimum quality over that entire repeat interval. `-S` disables the
extension and takes the minimum over just the CIGAR-designated inserted bases.
Deletion quality remains the anchor base's quality.

This addresses alignment-placement ambiguity: the CIGAR can place an extra
homopolymer base at a Q39 position even when the basecaller placed the Q5
warning elsewhere in the equivalent run. Taking the interval minimum assigns
the event to the low-quality group. The code does not hardcode SBX quality
values, rewrite the BAM qualities or lower every base's Q in the run. Its
adjustment is an event-quality heuristic, not a posterior over alignments.

## Executable checks

The synthetic fixtures in `tests/fixtures/mapchk` are project-authored and
contain no biological sample data. The repeat example is:

```text
reference: CAAAAG
read:      CAAAAAG
CIGAR:     1M1I5M
qualities: 39 39 39 39 39 5 39
```

The CIGAR-designated inserted base is Q39; a later equivalent A is Q5. At
`-q 30`, the observed `ALL` totals are:

| Mode | Low observations | High observations | Overall Q |
|---|---:|---:|---|
| r352 default repeat adjustment | 2 | 5 | Q8 |
| `-S`, inserted interval only | 1 | 6 | Q8 |

The overall rate stays 1/7. Six aligned matches plus one insertion event enter
the denominator. Only the quality group assigned to the insertion changes.

Two additional reads align to `ACGT`, with either `1M1I3M` or `1M2I3M` and all
Q39 bases. Both give five high-quality observations and Q6: four matches and
one insertion event, not length-weighted insertion errors.

Reproduce with the pinned upstream executable:

```bash
git clone --branch lite https://github.com/lh3/htsbox.git /tmp/otc-htsbox
git -C /tmp/otc-htsbox checkout c901cb3a3324c119988f4bcd4412cbe48e1b5a38
make -C /tmp/otc-htsbox -j2
HTSBOX=/tmp/otc-htsbox/htsbox bash tests/reference/mapchk.sh
```

The characterization passed with that revision and samtools/HTSlib 1.23 for
SAM-to-BAM fixture generation. These optional reference tests are not part of
`cargo test`; they require the external tools and do not download them.

## Boundaries relevant to OpenTargetCalls

- The vendored pileup masks unmapped, secondary, QC-fail and duplicate records;
  `mapchk` additionally excludes supplementary records. It adds no MAPQ
  threshold and no explicit paired-overlap correction.
- The vendored pileup initializes `maxcnt` to 8000; `mapchk` does not override
  it. High-depth behavior needs explicit qualification.
- Quality array indexing assumes the 0..93 range. Missing BAM qualities require
  an explicit safe policy in a native implementation.
- Insertion events are grouped without their inserted sequence/length. The
  variant filter and recurrence threshold are diagnostic heuristics.
- Read placement errors, reference differences and real variants can be
  counted as sequencing discrepancies. A high estimated Q is conditional on
  these selection rules.

Keep a named `mapchk-r352` compatibility projection if useful for published
comparisons. The native model must expose separate substitution, insertion-
event, deletion-event and affected-base counts with explicit denominators.
Train on independent controls, retain repeat context and quality semantics,
and calibrate local haplotype likelihoods rather than treating this aggregate Q
as a universal base-error probability. See [the empirical model design](../error-model.md).
