#!/usr/bin/env bash
# Gate del estándar para un módulo de Go. Lo copia quality/sync.sh como scripts/verify-go.sh y
# no se edita en el repo. El host no tiene Go: todo corre en la imagen de golangci-lint, fijada
# por digest, con la memoria acotada y la caché de módulos y de build en un volumen compartido.
# Se llama envuelto en build-lock.sh, como cualquier gate pesado del server.
#
#   scripts/verify-go.sh
#
# scripts/layers es el chequeo de capas (go/layers): ningún archivo atiende HTTP y consulta la base a
# la vez; los que todavía mezclan van en .layers-pending, que sólo se achica.
#
# Un módulo con tests de integración le pasa la red de su base descartable en GO_VERIFY_NETWORK y
# los nombres de las variables que leen esos tests en GO_VERIFY_ENV (separados por espacios).
#
# Con GO_VERIFY_PACKAGES (paquetes separados por espacios, como ./internal/orders/...) corre sólo el
# formato, el lint y los tests de esos paquetes: es la validación de lo tocado de
# server-bin/validate-changes.sh. tidy, capas, cobertura y govulncheck son del módulo entero y quedan
# para el gate completo. GO_VERIFY_TESTS=false saca los tests: es para un módulo cuyos tests de
# integración necesitan la base que levanta el gate del repo.
set -euo pipefail

readonly GOLANGCI_IMAGE="golangci/golangci-lint:v2.15.0@sha256:fbfcfd12a6f8d7f1b97b3362ca80fc2a244d46863148c73cb88e7793af96c481"
readonly GOVULNCHECK_VERSION="v1.9.0"
readonly MEMORY_LIMIT="1500m"
readonly CACHE_VOLUME="go-quality-cache"
readonly VERIFY_CGROUP="builds.slice"

module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && { pwd -W 2>/dev/null || pwd; })"

integration_options=()
if [[ -n "${GO_VERIFY_NETWORK:-}" ]]; then
  integration_options+=(--network "${GO_VERIFY_NETWORK}")
fi
for variable in ${GO_VERIFY_ENV:-}; do
  integration_options+=(-e "${variable}")
done

readonly PACKAGE_PATTERN='^(\./[A-Za-z0-9_./-]*)( \./[A-Za-z0-9_./-]*)*$'

scoped_script() {
  if [[ ! "${GO_VERIFY_PACKAGES}" =~ ${PACKAGE_PATTERN} ]]; then
    echo "GO_VERIFY_PACKAGES tiene que ser una lista de paquetes relativos (./internal/x/...)" >&2
    exit 2
  fi
  printf '%s\n' "golangci-lint fmt --diff" "golangci-lint run ${GO_VERIFY_PACKAGES}"
  if [[ "${GO_VERIFY_TESTS:-true}" == true ]]; then
    printf '%s\n' "go test -race -shuffle=on -count=1 ${GO_VERIFY_PACKAGES}"
  fi
}

full_script() {
  cat <<GATE
    go mod verify
    go mod tidy -diff
    golangci-lint fmt --diff
    golangci-lint run
    if [ -d scripts/layers ]; then
      (cd scripts/layers && go build -o /tmp/layers .)
      /tmp/layers ./...
    fi
    go test -race -shuffle=on -count=1 -covermode=atomic -coverpkg=./... -coverprofile=/tmp/coverage.out ./...
    if [ -f scripts/check-go-coverage.sh ]; then bash scripts/check-go-coverage.sh /tmp/coverage.out; fi
    GOTOOLCHAIN=auto go run golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION} ./...
GATE
}

gate_script() {
  if [[ -n "${GO_VERIFY_PACKAGES:-}" ]]; then
    scoped_script
  else
    full_script
  fi
}

gate="$(gate_script)"

docker run --rm -m "${MEMORY_LIMIT}" --cgroup-parent="${VERIFY_CGROUP}" --log-driver=none \
  "${integration_options[@]}" \
  -v "${module_dir}:/src" -w /src \
  -v "${CACHE_VOLUME}:/cache" \
  -e GOMODCACHE=/cache/mod -e GOCACHE=/cache/build -e GOLANGCI_LINT_CACHE=/cache/golangci \
  -e GOFLAGS=-mod=readonly -e GOTOOLCHAIN=local \
  "${GOLANGCI_IMAGE}" sh -euc "${gate}"
