# Alignment I/O design

Status: proposed implementation contract. No native reader is wired into the
current CLI. The first deliverable is a tested indexed reader and observation
stream, not a pileup engine or a new format implementation.

## Backend decision

Use `rust-htslib`/HTSlib for the first backend. It provides a mature compatibility
baseline for BAM, CRAM, references and indexes. Evaluate seqair with the same
fixtures and benchmark driver; use noodles as an additional independent reader
where helpful. Keep concrete adapters behind one small internal interface;
backend-specific record and pileup types must not enter `otc-core`.

Evidence reviewed:

- [rammap performance table](https://github.com/jwanglab/rammap/blob/a6ea7aa7423bbc878c7547995df2c49d4139a793/docs/performance.md):
  rammap 1.0.0 versus minimap2 2.31, eight threads on a Xeon Gold 6140. The
  authors report identical alignment output except program-identifying SAM
  headers for the tested cases. All six listed short-read workloads have
  higher rammap wall time; the listed long-read workloads favor rammap. These
  are workload-specific author measurements, not a language comparison or a
  universal compatibility guarantee.
- [rammap implementation](https://github.com/jwanglab/rammap/blob/a6ea7aa7423bbc878c7547995df2c49d4139a793/README.md):
  MIT-licensed Rust library/CLI, SIMD alignment and parallel execution. The
  associated [preprint](https://doi.org/10.64898/2026.05.26.726289) is a relevant
  engineering example, not validation of OpenTargetCalls.
- [seqair README](https://github.com/Softleif/seqair/blob/befc51f00b17984c87f774804288d3d619f994a2/README.md):
  MIT/Apache-2.0, slab records, bulk region I/O, forkable readers and BAM/CRAM
  support. It explicitly warns that extensive real-world testing is lacking.
  Its comparison/property tests are promising; performance for our extraction
  policy and CRAM corpus is unmeasured.
- [rust-htslib manifest](https://github.com/rust-bio/rust-htslib/blob/96afbc960fa9510f67db927d264dff296fecea59/Cargo.toml):
  version 1.0.2 at the inspected revision, with HTSlib bindings, native codec
  dependencies and default curl support. Native compilation and bindgen are
  deployment costs. This revision is evidence for the assessment, not a
  selected release dependency.

The first implementation must pin a tested release/native build, check the
workspace MSRV, and explicitly choose codecs and networking features. The
initial product supports local files and mounted filesystems. Disable optional
network transports unless a supported use case and security policy need them.
CRAM codecs required by the fixture matrix must remain available.

Seqair becomes eligible as a default backend only after format/error parity,
bounded memory and representative end-to-end gains are established. A pure-Rust
build can reduce native deployment burden; it is not itself a correctness gate.
Switching remains local to `otc-io`, but changing overlap or pileup semantics is
a model change and must not be hidden behind a backend switch.

## Input and reference contract

Production extraction starts with coordinate-sorted indexed BAM or CRAM and an
indexed FASTA. SAM supports small sequential fixtures and diagnostics. A
sequential mode is explicit; missing indexes do not silently trigger a WGS scan.
Use standard BAI/CSI/CRAI and FAI/GZI semantics through the chosen library.

Validate before extraction:

- readable alignment, usable index and consistent sorting/header metadata;
- an explicit sample selection from read groups, or an explicit single-sample
  declaration when read-group sample metadata is absent;
- complete read-group references: duplicate IDs, undeclared record RG tags and
  ambiguous sample assignment are errors;
- reference contig names, lengths and available sequence digests;
- assembly identity shared by alignment, reference, controls and target bundle;
- target intervals within bounds and a versioned explicit alias map if used.

A missing RG tag requires a declared fallback group; it is not silently pooled
with another library. Platform metadata can be unknown. It is not inferred from
read names and no vendor string is rejected merely for being unfamiliar.

CRAM decoding uses an explicit pinned reference and verifies available CRAM
reference checksums. Implicit network reference retrieval is disabled in the
local-file profile. A missing or mismatched reference is an error. CRAM can
preserve altered or lossy quality values; model identity must include quality
handling and available encoder/preprocessing metadata.

VCF/BCF output is added with target-specific schemas through a mature writer.
The first reader milestone emits inspectable counters, not a generic variant
call. FASTQ mapping is a separate upstream workflow; if FASTQ input is added,
use a standards-aware parser with multiline sequence/quality fixtures rather
than a four-lines-per-read assumption.

## Read and event semantics

`otc-io` supplies a borrowed record view whose lifetime ends before its reusable
reader buffer advances, or an owned bounded batch for queued work. Workers
never retain pointers into a mutable foreign record. Copy only fields needed
beyond that lifetime. Enforce this in signatures: synchronous accumulation
borrows the view; queued work owns its batch. Add compile-fail lifetime tests.
Readers own file handles. Share Rust-owned immutable reference/header data, or
backend objects with documented and tested thread safety; native handles and
mutable caches remain worker-local unless explicitly synchronized and bounded.

The normalized observation includes reference identity/contig, alignment and
query coordinates, flags, read group, mate identity, mapping quality, sequence,
qualities and CIGAR access. Preserve evidence-relevant auxiliary tags through
explicit typed access rather than copying every tag. Missing quality and MAPQ
255 are unavailable values, not high confidence or numerical zero.

Event rules follow [the SAM/BAM/CRAM specifications](https://samtools.github.io/hts-specs/):

| CIGAR operation | Reference consumption | Query consumption | Evidence meaning |
|---|---:|---:|---|
| M, =, X | yes | yes | aligned base; compare to reference, M is not a match claim |
| I | no | yes | insertion at a reference boundary |
| D | yes | no | deletion span; not a nucleotide mismatch |
| N | yes | no | skipped region, distinct from deletion |
| S | no | yes | clipped sequence, available for target-specific evidence |
| H, P | no | no | clipping/padding metadata, no base observation |

Insertions use between-base boundaries internally, including boundary zero.
Deletion intervals are half-open. VCF anchoring/normalization belongs to output,
not this stream. Ambiguous bases and absent sequence are marked unavailable for
base-error fitting. Do not use an MD tag as the sole reference authority.

Stored read orientation and sequencing orientation are distinct. For a
reverse-strand record, recover the sequencing-oriented position by reversing
the stored query index; include soft-clipped positions in stored read length.
Hard clipping and upstream trimming can make original machine cycle
unrecoverable. Label the recoverable covariate `read_position`, record trimming
provenance, and use a missing-cycle state rather than fabricate original cycles.
Reference context must be oriented consistently when used by calibration.

## Filtering and fragment accounting

There is no global high-MAPQ pileup from which all metrics are derived.
Calibration excludes ambiguous mapping; paralog inference often needs it.
Each consumer owns a versioned policy covering:

- mapped/unmapped, primary/secondary/supplementary, duplicate and QC-fail flags;
- MAPQ/quality missingness and thresholds;
- clipping, indel neighborhoods and base/context eligibility;
- record, fragment or UMI-family counting;
- overlap reconciliation and maximum state;
- selection/downsampling and effective coverage after filtering.

For the first base-error calibration baseline, exclude both base observations
where mates overlap, rather than arbitrarily counting a fragment twice or
assuming an uncalibrated consensus is truth. Target likelihoods need a separate
fragment-aware policy: agreement does not create two independent molecules;
disagreement is retained as uncertainty, not automatically resolved by choosing
the higher-quality base. UMI families require explicit library metadata and
consensus semantics before any error reduction is claimed.

Use read-group/sample plus template identity for pairing, account for multi-
alignments, and test name collisions. Bound mate state and declared span. Missing
mates or exceeded pairing limits must be reported and excluded from metrics
that require resolved overlap, never silently treated as independent support.
Distant-mate retrieval, supplementary records and unmapped reads are explicit
parts of a target extraction plan, not assumptions of an interval pileup.

## Interval planning and execution

Plan calibration controls and each target's genes, homologs, flanks, junction
windows and normalization controls together. A target BED alone cannot capture
all read recruitment requirements. Coalesce nearby intervals to reduce remote
filesystem seeks while retaining labels for consumer membership.

Workers own disjoint coordinate tiles with halos for reads/contexts. Count a
base/depth event only in the tile owning its reference position, an insertion
in its boundary-owner tile, and a fragment/junction in its explicitly assigned
owner. The query start or record start is not a valid owner rule for every
event. This prevents losses and double counts at shard boundaries. Query plans
must also prevent repeated records from overlapping interval fetches.

Use reusable buffers, independent file handles and bounded channels. Give each
run one thread budget, including HTSlib decompression and external Unum jobs.
Avoid multiplying a full decompression pool by a full per-target compute pool.

No silent pileup depth cap. A resource limit produces an explicit unsupported
result for the affected metric or a declared deterministic sampling plan with
selection probabilities and effective support. Sampling a base observation and
then treating its count as unsampled depth is invalid.

## Cache and provenance contract

Start with indexed source artifacts and a bounded in-memory reference/tile
cache. Do not require whole-BAM materialization or a new binary serving format.
Cache keys include source content identity, reference identity, interval,
schema and relevant decode/policy version. Changed sources invalidate caches;
mtime alone is insufficient. Derived artifacts are rebuildable, and disk
caching is opt-in until repeated-query benefit is measured.

A full source SHA-256 requires reading the full source, even for a tiny indexed
query. Report that cost separately. Distinguish a digest computed this run from
a trusted immutable-store digest or a user-supplied unverified identity. Record
index identity separately. Never label a checksum of fetched regions as the
checksum of the complete alignment file. Model/resource digests include schema,
parameters, policies and reference, not only numeric tables.

## Qualification and performance gates

Correctness precedes optimization. Fixtures cover:

- all CIGAR operations, reverse orientation, soft/hard clipping and contig ends;
- missing RG/qualities/MAPQ, ambiguous bases and inconsistent headers;
- overlapping mates, duplicates, supplementary/secondary mappings and orphans;
- overlapping queries, tile boundaries, high depth and deterministic sampling;
- BAM/CRAM equivalence with lossless fixtures and declared lossy differences;
- CRAM 3.0/3.1, reference failures, BAI/CSI/CRAI, long coordinates and no index;
- malformed/truncated records, auxiliary fields, corrupt BGZF/CRAM and I/O errors.

Compare decoded fields to pinned HTSlib and an independent reader where
available. Compare event counters to a small scalar fixture oracle. Compare
`samtools mpileup` only with matched filters, overlap handling, BAQ and depth
limits; its defaults are not the OpenTargetCalls specification.

Benchmark decoding, reference access, normalization, accumulation and output
separately, then the complete extraction. Report dataset identity, file/index
size, codec, CPU/SIMD, threads, storage, bytes read, wall/CPU time, peak RSS and
all policy settings. Include BAM and CRAM; sparse ten-target queries and control
panels; one whole-scan baseline; WGS/WES and high-depth cases; local SSD and a
high-latency filesystem. Separate cold/warm-cache and provenance-hashing costs.
Compare equivalent results, with repeated runs and dispersion. Do not set a
speedup target before this baseline exists.
