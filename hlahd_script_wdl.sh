#!/bin/bash

# $1 is the directory where all intermediate files will be written
# $2 is the directory final outputs should be written to
# $3 is the prefix that will be added to all files
# $4 is the location of the input cram file
# $5 is the reference file used to create the cram
# $6 is the number of cores that will be used by processes
# $7 is the total memory in the node
#bsub -R 'select[mem>64000] rusage[mem=64000]' -e <error_file_name> -o <output_file_name> -q research-hpc -a 'docker(johnegarza/immuno-testing:latest)' /bin/bash /usr/bin/optitype_script.sh <intermediate files directory> <final results directory> <output file prefix>  <cram path>

set -e -o pipefail

DEFAULT_THREADS=4
DEFAULT_MEM=8
MEM_UTIL=80 # percent

TEMPDIR="$1";
outdir="$2";
name="$3";
cram="$4";
reference="$5";
THREADS=${6:-$DEFAULT_THREADS}
if [ ${7:-$DEFAULT_MEM} -eq 1 ]; then MEM=1G; else MEM="$((${7:-$DEFAULT_MEM}*$MEM_UTIL/100))"G; fi

mkdir -p $TEMPDIR
mkdir -p $outdir

echo "Step 1: extracting hla region from chr6, reads to alternate HLA sequences, and all unmapped reads ..."

# filter out reads directly from an existing CRAM file of alignments, only those reads that align to this region: chr6:29836259-33148325
echo "[INFO] /opt/samtools/bin/samtools view -h -T $reference $cram chr6 >$TEMPDIR/reads.sam"
time /opt/samtools/bin/samtools view -h -T $reference $cram chr6:29836259-33148325 >$TEMPDIR/reads.sam

# pull out only the *header* lines from the CRAM with the -H parameter. then get the sequence names and for those that match the string "HLA" do the following
echo "[INFO] /opt/samtools/bin/samtools view -H -T $reference $cram | grep "^@SQ" | cut -f 2 | cut -f 2- -d : | grep -E 'HLA|HSCHR6_MHC|^chr6_.*_alt$' | while read chr;do ..."
time /opt/samtools/bin/samtools view -H -T $reference $cram | grep "^@SQ" | cut -f 2 | cut -f 2- -d : | grep -E 'HLA|HSCHR6_MHC|^chr6_.*_alt$' | while read chr;do 
# echo "checking $chr:1-9999999"
# grab all the reads that align to each alternate "HLA" sequence
/opt/samtools/bin/samtools view -T $reference $cram "$chr:1-9999999" >>$TEMPDIR/reads.sam
done

# grab all the reads that are unaligned
echo "[INFO]  /opt/samtools/bin/samtools view -f 4 -T $reference $cram >>$TEMPDIR/reads.sam"
time /opt/samtools/bin/samtools view -f 4 -T $reference $cram >>$TEMPDIR/reads.sam
# covert from .sam to .bam format
echo "[INFO] /opt/samtools/bin/samtools view -Sb -o $TEMPDIR/reads.bam $TEMPDIR/reads.sam"
time /opt/samtools/bin/samtools view -Sb -o $TEMPDIR/reads.bam $TEMPDIR/reads.sam 

echo "Step 2: running picard ..."
echo "[INFO] /usr/bin/java -Xmx6g -jar /usr/picard/picard.jar SamToFastq VALIDATION_STRINGENCY=LENIENT F=$TEMPDIR/$name.q.fwd.fastq.gz F2=$TEMPDIR/$name.q.rev.fastq.gz I=$TEMPDIR/reads.bam R=$reference FU=$TEMPDIR/unpaired.fastq.gz"
time /usr/bin/java -Xmx6g -jar /usr/picard/picard.jar SamToFastq VALIDATION_STRINGENCY=LENIENT F=$TEMPDIR/$name.q.fwd.fastq.gz F2=$TEMPDIR/$name.q.rev.fastq.gz I=$TEMPDIR/reads.bam R=$reference FU=$TEMPDIR/unpaired.fastq.gz

gzip -dc "$TEMPDIR/$name.q.fwd.fastq.gz" > "$outdir/$name.hla.fwd.fastq"
gzip -dc "$TEMPDIR/$name.q.rev.fastq.gz" > "$outdir/$name.hla.rev.fastq"

echo "Step 7: HLA-HD"
# ====== minimal required changes for Docker environment ======
# Use the HLA-HD installation baked into the image at /opt/hlahd
HLAHD_DIR="/opt/hlahd"

export PATH="$PATH:$HLAHD_DIR/bin"

# Use resources that live inside the image (mirror your conda layout)
GENE_SPLIT="$HLAHD_DIR/HLA_gene.split.txt"
DICT_DIR="$HLAHD_DIR/dictionary_3.55"
FREQ_DIR="$HLAHD_DIR/freq_data"

# Run with the original flags; only swap absolute host paths for in-image paths,
# and use the THREADS variable you already parsed above.
/opt/hlahd/bin/hlahd.sh -t "$THREADS" -m 100 -c 0.95 -f "$FREQ_DIR" \
  "$outdir/$name.hla.fwd.fastq" \
  "$outdir/$name.hla.rev.fastq" \
  "$GENE_SPLIT" \
  "$DICT_DIR" \
  "${name}_DNA" \
  "$outdir"
# =============================================================
# --- capture final outfile for WDL: $outdir/${name}_final.result.txt ---
final_native="$(find "$outdir" -maxdepth 3 -type f -name '*_final.result.txt' | head -n1 || true)"
if [[ -z "$final_native" ]]; then
  echo "[ERROR] HLA-HD final result not found under $outdir"
  find "$outdir" -maxdepth 3 -type f -printf "%p\t%k KB\n" || true
  exit 2
fi
# Make a stable handle that matches hlahd_dna.wdl
ln -sf "$final_native" "$outdir/${name}_final.result.txt"
echo "[OK] Linked $final_native -> $outdir/${name}_final.result.txt"
# -----------------------------------------------------------------------
