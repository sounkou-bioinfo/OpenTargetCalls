#!/usr/bin/env bash
# Characterize htsbox r352 insertion-event counts and tandem-repeat quality.
set -euo pipefail

: "${HTSBOX:?Set HTSBOX to the pinned htsbox r352 executable}"
samtools=${SAMTOOLS:-samtools}
fixtures=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/mapchk" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/otc-mapchk.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

cp -- "$fixtures/"*.fa "$work/"
"$samtools" faidx "$work/sbx-repeat.fa"
"$samtools" faidx "$work/insertion-events.fa"
for name in sbx-repeat insertion-one insertion-two; do
    "$samtools" view -b -o "$work/$name.bam" "$fixtures/$name.sam"
done

"$HTSBOX" mapchk -q 30 "$work/sbx-repeat.bam" "$work/sbx-repeat.fa" > "$work/adjusted.tsv"
"$HTSBOX" mapchk -q 30 -S "$work/sbx-repeat.bam" "$work/sbx-repeat.fa" > "$work/unadjusted.tsv"
for name in insertion-one insertion-two; do
    "$HTSBOX" mapchk -q 30 "$work/$name.bam" "$work/insertion-events.fa" > "$work/$name.tsv"
done

assert_totals() {
    local file=$1 quality=$2 low=$3 high=$4
    awk -F '\t' -v q="$quality" -v low="$low" -v high="$high" '
        NR == 1 { ok = ($1 == "ALL" && $2 == q && $3 == low && $8 == high) }
        END { exit !ok }
    ' "$file" || {
        printf 'Unexpected mapchk totals: %s\n' "$file" >&2
        head -n 1 "$file" >&2
        return 1
    }
}

assert_totals "$work/adjusted.tsv" Q8 2 5
assert_totals "$work/unadjusted.tsv" Q8 1 6
assert_totals "$work/insertion-one.tsv" Q6 0 5
assert_totals "$work/insertion-two.tsv" Q6 0 5
printf 'PASS: repeat-adjusted insertion quality and length-independent event counts\n'
