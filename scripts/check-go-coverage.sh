#!/usr/bin/env bash
# Falla si la cobertura de sentencias queda debajo del estándar, en total o en algún archivo.
#
# Go mide sentencias, no ramas: se exige el umbral de líneas de quality/coverage.conf al total
# y el piso por archivo a cada uno, para que un archivo sin tests no se esconda detrás del
# promedio. Cada archivo debajo de la vara siguiente lista las líneas que ningún test ejecutó, para
# saber qué probar sin volver a correr la suite. Lo genera quality/sync.sh con los umbrales: no se
# edita en el repo.
#
#   scripts/check-go-coverage.sh coverage.out
set -euo pipefail

readonly MIN_TOTAL=80
readonly MIN_PER_FILE=50
readonly NEXT_TOTAL=90
readonly NEXT_PER_FILE=70

profile="${1:?uso: check-go-coverage.sh <coverage.out>}"
[[ -s "${profile}" ]] || {
  echo "No existe o está vacío: ${profile}" >&2
  exit 2
}

# Un mismo bloque aparece una vez por paquete de test que lo mide: cuenta como cubierto si
# alguno lo ejecutó, y sus sentencias se suman una sola vez.
awk -v min_total="${MIN_TOTAL}" -v min_file="${MIN_PER_FILE}" -v next_total="${NEXT_TOTAL}" \
  -v next_file="${NEXT_PER_FILE}" '
  NR == 1 && /^mode:/ { next }
  {
    block = $1
    statements[block] = $2
    if ($3 > 0) covered[block] = 1
  }
  function uncovered_lines(target,    block, file, range, count, starts, finish, ends, parts, order, i, j, moved, listed) {
    count = 0
    for (block in statements) {
      if (block in covered) continue
      file = block
      sub(/:[0-9.,]+$/, "", file)
      if (file != target) continue
      range = substr(block, length(file) + 2)
      split(range, ends, ",")
      count++
      split(ends[1], parts, ".")
      starts[count] = parts[1] + 0
      order[count] = count
      split(ends[2], parts, ".")
      finish[count] = parts[1] + 0
    }
    for (i = 2; i <= count; i++) {
      for (j = i; j > 1 && starts[order[j]] < starts[order[j - 1]]; j--) {
        moved = order[j]; order[j] = order[j - 1]; order[j - 1] = moved
      }
    }
    listed = ""
    for (i = 1; i <= count; i++) {
      range = starts[order[i]] == finish[order[i]] ? starts[order[i]] : starts[order[i]] "-" finish[order[i]]
      listed = listed (listed == "" ? "" : ", ") range
    }
    return listed
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
      } else if (percent < next_file) {
        printf "vara siguiente (QS-303): %s con %.1f %% de sentencias (piso %d %%)\n", file, percent, next_file
        printf "  sin cubrir: %s\n", uncovered_lines(file)
      }
    }
    percent = 100 * total_covered / total
    printf "Cobertura de sentencias: %.1f %% (mínimo %d %%)\n", percent, min_total
    if (percent < min_total) failed = 1
    if (percent < next_total) printf "vara siguiente (QS-303): total por debajo de %d %%\n", next_total
    exit failed
  }
' "${profile}"
