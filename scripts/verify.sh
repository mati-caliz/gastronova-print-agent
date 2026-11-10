#!/usr/bin/env bash
# Gate del componente: el estándar de infra/quality en el módulo de Go y en los scripts. Va envuelto en
# build-lock.sh. El workflow de release no lo corre: se valida acá antes de crear el tag.
#
#   scripts/verify.sh            todo
#   scripts/verify.sh go|shell
set -euo pipefail

case "${1:-all}" in
  go | shell | all) ;;
  *)
    printf 'Uso: %s [go|shell]\n' "$0" >&2
    exit 2
    ;;
esac
cd "$(dirname "$0")/.."

readonly TARGET="${1:-all}"
readonly SHELLCHECK_IMAGE="koalaman/shellcheck:stable"
readonly SHELLCHECK_MEMORY_LIMIT="768m"
readonly VERIFY_CGROUP="builds.slice"

check_go() {
  bash scripts/verify-go.sh
}

check_shell() {
  local tracked_scripts
  tracked_scripts="$(git ls-files '*.sh')"
  local -a shell_scripts
  mapfile -t shell_scripts <<<"${tracked_scripts}"
  docker run --rm -m "${SHELLCHECK_MEMORY_LIMIT}" --cgroup-parent="${VERIFY_CGROUP}" \
    -v "${PWD}:/mnt:ro" -w /mnt "${SHELLCHECK_IMAGE}" "${shell_scripts[@]}"
}

bash ../infra/quality/sync.sh . --check

case "${TARGET}" in
  go) check_go ;;
  shell) check_shell ;;
  all)
    check_go
    check_shell
    ;;
  *) exit 2 ;;
esac
