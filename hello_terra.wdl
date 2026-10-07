version 1.0

## hello_terra.wdl
## Minimal Terra smoke-test workflow: localizes a file from GCS, does a little
## real computation on it (line/word/byte counts, a checksum, a numeric sum, and
## a short CPU burn), and returns a report plus a few scalar outputs that Terra
## can write back to the data table.
##
## Expected input: any small text file. The sample TSV points at public
## FASTA index (.fai) / sequence dictionary files in the Broad public
## references bucket, so no special bucket permissions are needed.

workflow hello_terra {
  input {
    String sample_id
    File input_file
    String greeting = "Hello from Terra"
  }

  call summarize_file {
    input:
      sample_id = sample_id,
      input_file = input_file,
      greeting = greeting
  }

  output {
    File report = summarize_file.report
    Int line_count = summarize_file.line_count
    String md5 = summarize_file.md5
    String column2_sum = summarize_file.column2_sum
  }

  meta {
    description: "Smoke test: proves a Terra workflow can read input data and run compute."
  }
}

task summarize_file {
  input {
    String sample_id
    File input_file
    String greeting

    # Runtime knobs (small and cheap by default)
    Int cpu = 1
    Int memory_gb = 2
    Int disk_gb = 10
    Int preemptible = 2
    String docker = "ubuntu:22.04"
  }

  command <<<
    set -euo pipefail

    in="~{input_file}"

    wc -l < "$in" | tr -d ' ' > line_count.txt
    md5sum "$in" | cut -d' ' -f1 > md5.txt

    # Sum the 2nd tab-separated column where it is numeric
    # (for a .fai this is the total sequence length of the reference).
    awk -F'\t' '$2 ~ /^[0-9]+$/ { s += $2 } END { printf "%d\n", s }' "$in" > column2_sum.txt

    # A deliberate bit of CPU work so the job shows measurable compute time.
    start=$(date +%s)
    burn=$(seq 1 2000000 | awk '{ s += $1 * $1 } END { printf "%d", s }')
    end=$(date +%s)

    {
      echo "~{greeting}, ~{sample_id}!"
      echo "========================================"
      echo "Input file    : $(basename "$in")"
      echo "Bytes         : $(wc -c < "$in" | tr -d ' ')"
      echo "Lines         : $(cat line_count.txt)"
      echo "Words         : $(wc -w < "$in" | tr -d ' ')"
      echo "MD5           : $(cat md5.txt)"
      echo "Column 2 sum  : $(cat column2_sum.txt)"
      echo "First 3 lines :"
      head -n 3 "$in" | sed 's/^/    /'
      echo "----------------------------------------"
      echo "Sum of squares 1..2,000,000 = ${burn} (took $((end - start))s)"
      echo "Host          : $(hostname)"
      echo "CPUs          : $(nproc)"
      echo "Memory        : $(free -h | awk '/^Mem:/ {print $2}')"
      echo "Kernel        : $(uname -sr)"
      echo "Finished at   : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "~{sample_id}.report.txt"

    cat "~{sample_id}.report.txt"
  >>>

  output {
    File report = "~{sample_id}.report.txt"
    Int line_count = read_int("line_count.txt")
    String md5 = read_string("md5.txt")
    String column2_sum = read_string("column2_sum.txt")
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GiB"
    disks: "local-disk ~{disk_gb} HDD"
    preemptible: preemptible
  }
}
