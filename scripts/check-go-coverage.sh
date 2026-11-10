#!/usr/bin/env bash
# Falla si la cobertura de sentencias queda debajo del estándar, en total o en algún archivo.
#
# Go mide sentencias, no ramas: se exige el umbral de líneas de quality/coverage.conf al total
# y el piso por archivo a cada uno, para que un archivo sin tests no se esconda detrás del
# promedio. Lo genera quality/sync.sh con los umbrales: no se edita en el repo.
#
#   scripts/check-go-coverage.sh coverage.out
set -euo pipefail

readonly MIN_TOTAL=80
readonly MIN_PER_FILE=50

profile="${1:?uso: check-go-coverage.sh <coverage.out>}"
[[ -s "${profile}" ]] || {
  echo "No existe o está vacío: ${profile}" >&2
  exit 2
}

# Un mismo bloque aparece una vez por paquete de test que lo mide: cuenta como cubierto si
# alguno lo ejecutó, y sus sentencias se suman una sola vez.
awk -v min_total="${MIN_TOTAL}" -v min_file="${MIN_PER_FILE}" '
  NR == 1 && /^mode:/ { next }
  {
    block = $1
    statements[block] = $2
    if ($3 > 0) covered[block] = 1
  }
  END {
    for (block in statements) {
      file = block
      sub(/:[0-9.,]+$/, "", file)
      file_total[file] += statements[block]
      total += statements[block]
      if (block in covered) {
        file_covered[file] += statements[block]
        total_covered += statements[block]
      }
    }
    if (total == 0) {
      print "El reporte no tiene sentencias medidas" > "/dev/stderr"
      exit 2
    }
    failed = 0
    for (file in file_total) {
      percent = 100 * file_covered[file] / file_total[file]
      if (percent < min_file) {
        printf "%s: %.1f %% de sentencias (piso %d %%)\n", file, percent, min_file > "/dev/stderr"
        failed = 1
      }
    }
    percent = 100 * total_covered / total
    printf "Cobertura de sentencias: %.1f %% (mínimo %d %%)\n", percent, min_total
    if (percent < min_total) failed = 1
    exit failed
  }
' "${profile}"
