#!/usr/bin/env bash
# Licencias de las dependencias de producción de un repo, contra la lista común de licenses.json
# (QS-305). Lo corre sync.sh --check con la raíz del repo y su .quality: pnpm por cada lockfile,
# Python desde el lockfile de uv (sin instalar: la licencia sale de PyPI) y Go con go-licenses en la
# imagen del gate. Rust lo cubre cargo-deny con la misma lista, que sync.sh escribe en deny.toml.
#
#   verify-licenses.sh <repo> <manifiesto>
set -euo pipefail

LICENSES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LICENSES_DIR
readonly UV_IMAGE="ghcr.io/astral-sh/uv:0.13.5-python3.12-trixie-slim"
readonly GOLANGCI_IMAGE="golangci/golangci-lint:v2.15.0@sha256:fbfcfd12a6f8d7f1b97b3362ca80fc2a244d46863148c73cb88e7793af96c481"
readonly GO_LICENSES_VERSION="v2.0.1"
readonly MEMORY_LIMIT="1500m"
readonly VERIFY_CGROUP="builds.slice"
readonly GO_CACHE_VOLUME="go-quality-cache"

repo_dir="$1"
manifest="$2"
failures=0

listing="$(mktemp)"
trap 'rm -f "${listing}"' EXIT

# Corre el que arma la lista y la compara: si la herramienta misma falla, también cuenta como falla.
check() {
  local label="$1"
  shift
  if ! "$@" >"${listing}"; then
    echo "licencias: no se pudo armar la lista de ${label}" >&2
    failures=$((failures + 1))
    return
  fi
  if ! python3 -I "${LICENSES_DIR}/check_licenses.py" <"${listing}"; then
    echo "licencias: ${label} tiene dependencias con una licencia que no está en quality/licenses/licenses.json" >&2
    failures=$((failures + 1))
  fi
}

pnpm_licenses() {
  local directory="$1"
  (cd "${directory}" && pnpm licenses list --json --prod) | python3 -I -c '
import json, sys
for license_name, packages in json.load(sys.stdin).items():
    for package in packages:
        print(package["name"] + "\t" + license_name)
'
}

lockfile_owner() {
  local directory="$1"
  while [[ "${directory}" != "${repo_dir}" && ! -f "${directory}/pnpm-lock.yaml" ]]; do
    directory="$(dirname "${directory}")"
  done
  [[ -f "${directory}/pnpm-lock.yaml" ]] && echo "${directory}"
}

# Con uv.lock, lo que exporta sin las de desarrollo. Sin lockfile (los paquetes de labrecha, el
# requirements.txt de tarjetazo), lo que resuelve uv para cada paquete con dependencias: es lo mismo
# que instala la imagen. Sólo los requirements.txt de producción, no los -dev.
python_licenses() {
  local directory="$1"
  docker run --rm -m "${MEMORY_LIMIT}" --cgroup-parent="${VERIFY_CGROUP}" --log-driver=none \
    -v "${directory}:/src:ro" -w /src -e UV_PYTHON_DOWNLOADS=never "${UV_IMAGE}" sh -euc '
      if [ -f uv.lock ]; then
        uv export --frozen --no-dev --no-hashes --no-emit-project --no-header --quiet
        exit 0
      fi
      find . \( -name node_modules -o -name .venv -o -name venv \) -prune -o \
        \( -name pyproject.toml -o -name requirements.txt \) -print | sort |
        while read -r manifest; do
          case "${manifest}" in
            *pyproject.toml) grep -q "^dependencies" "${manifest}" || continue ;;
          esac
          uv pip compile --quiet --no-header --no-annotate "${manifest}"
        done
    ' | python3 -I "${LICENSES_DIR}/python_licenses.py"
}

go_licenses() {
  local directory="$1" module
  module="$(sed -n 's/^module //p' "${directory}/go.mod")"
  docker run --rm -m "${MEMORY_LIMIT}" --cgroup-parent="${VERIFY_CGROUP}" --log-driver=none \
    -v "${directory}:/src:ro" -w /src -v "${GO_CACHE_VOLUME}:/cache" \
    -e GOMODCACHE=/cache/mod -e GOCACHE=/cache/build -e GOFLAGS=-mod=readonly -e GOTOOLCHAIN=auto \
    "${GOLANGCI_IMAGE}" sh -euc \
    "go run github.com/google/go-licenses/v2@${GO_LICENSES_VERSION} report ./... --ignore '${module}' 2>/dev/null" |
    awk -F, '{print $1 "\t" $3}'
}

declare -A checked_lockfiles=()
while read -r stack subdir _; do
  [[ -z "${stack}" || "${stack}" == \#* ]] && continue
  target="${repo_dir}/${subdir:-.}"
  target="${target%/.}"
  case "${stack}" in
    typescript)
      owner="$(lockfile_owner "${target}")" || continue
      [[ -n "${checked_lockfiles[${owner}]:-}" ]] && continue
      checked_lockfiles[${owner}]=1
      check "pnpm en ${owner#"${repo_dir}"/}" pnpm_licenses "${owner}"
      ;;
    python) check "Python en ${subdir:-.}" python_licenses "${target}" ;;
    go) check "Go en ${subdir:-.}" go_licenses "${target}" ;;
    *) ;;
  esac
done <"${manifest}"

if ((failures > 0)); then
  exit 1
fi
echo "licencias: todas las dependencias de producción en la lista común"
