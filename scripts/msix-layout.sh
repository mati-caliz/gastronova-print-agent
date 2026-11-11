#!/usr/bin/env bash
# Arma la carpeta del paquete MSIX (los dos ejecutables, el manifiesto y los íconos) y un .zip con ella. La
# carpeta sirve para probar en una PC con el modo de programador (Add-AppxPackage -Register) y es la que se
# empaqueta para la Microsoft Store, que firma el paquete. Para la Store, la identidad sale de Partner Center:
# MSIX_IDENTITY_NAME, MSIX_PUBLISHER y MSIX_PUBLISHER_DISPLAY_NAME.
#
#   scripts/msix-layout.sh 2.3.0
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Uso: scripts/msix-layout.sh <versión>, por ejemplo scripts/msix-layout.sh 2.3.0" >&2
  exit 1
fi

readonly VERSION="$1"
readonly PACKAGE_VERSION="${VERSION}.0"
readonly IDENTITY_NAME="${MSIX_IDENTITY_NAME:-Gastronova.Impresion}"
readonly PUBLISHER="${MSIX_PUBLISHER:-CN=Gastronova}"
readonly PUBLISHER_DISPLAY_NAME="${MSIX_PUBLISHER_DISPLAY_NAME:-Gastronova}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_DIR
readonly OUTPUT_DIR="${REPO_DIR}/dist"
readonly LAYOUT_DIR="${OUTPUT_DIR}/msix"
readonly ARCHIVE="${OUTPUT_DIR}/gastronova-impresion-msix.zip"
readonly GO_IMAGE="golang:1.27.3-bookworm@sha256:d9b6a1beb9474adc2a1ce842573639b44b2a0dd49b6669f51d3821baf9ec37c9"
readonly GO_CACHE_VOLUME="go-quality-cache"
readonly CONTAINER_MEMORY="1500m"

rm -rf "${LAYOUT_DIR}" "${ARCHIVE}"
mkdir -p "${LAYOUT_DIR}/Assets"

docker run --rm -m "${CONTAINER_MEMORY}" \
  -v "${REPO_DIR}":/src:ro -w /src \
  -v "${GO_CACHE_VOLUME}":/cache \
  -v "${LAYOUT_DIR}":/out \
  -e GOMODCACHE=/cache/mod -e GOCACHE=/cache/build \
  -e GOFLAGS=-mod=readonly -e GOTOOLCHAIN=local -e CGO_ENABLED=0 -e GOOS=windows -e GOARCH=amd64 \
  "${GO_IMAGE}" bash -euc '
    go build -trimpath -buildvcs=false -ldflags "-s -w" -o /out/gastronova-print-host.exe ./cmd/gastronova-print-host
    go build -trimpath -buildvcs=false -ldflags "-s -w -H windowsgui" -o /out/gastronova-impresion.exe ./cmd/gastronova-register
    chown -R "$(stat -c %u:%g /out)" /out
  '

sed -e "s|__IDENTITY_NAME__|${IDENTITY_NAME}|" -e "s|__PUBLISHER__|${PUBLISHER}|" \
  -e "s|__PUBLISHER_DISPLAY_NAME__|${PUBLISHER_DISPLAY_NAME}|" -e "s|__VERSION__|${PACKAGE_VERSION}|" \
  "${REPO_DIR}/msix/AppxManifest.xml" >"${LAYOUT_DIR}/AppxManifest.xml"
cp "${REPO_DIR}"/msix/Assets/*.png "${LAYOUT_DIR}/Assets/"

(cd "${OUTPUT_DIR}" && python3 -I -m zipfile -c "${ARCHIVE}" msix)
echo "Paquete ${PACKAGE_VERSION} en ${LAYOUT_DIR} y ${ARCHIVE}."
