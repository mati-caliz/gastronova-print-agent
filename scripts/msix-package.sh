#!/usr/bin/env bash
# Arma el .msix para la Microsoft Store con la identidad del producto en Partner Center. Sale sin firmar: la
# firma la pone la Store. Lo empaqueta makemsix (microsoft/msix-packaging), que en Linux hay que compilar: la
# imagen queda en Docker y sólo se rearma si falta.
#
#   scripts/msix-package.sh 2.3.0
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Uso: scripts/msix-package.sh <versión>, por ejemplo scripts/msix-package.sh 2.3.0" >&2
  exit 1
fi

readonly VERSION="$1"
readonly MAKEMSIX_IMAGE="gastronova-makemsix:local"
readonly BASE_IMAGE="ubuntu:26.04"
readonly CONTAINER_MEMORY="1500m"
readonly STORE_IDENTITY_NAME="Gastronova.GastronovaImpresin"
readonly STORE_PUBLISHER="CN=17D85A29-F27E-45DF-805E-71D9D020C94B"
readonly STORE_PUBLISHER_DISPLAY_NAME="Gastronova"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_DIR
readonly OUTPUT_DIR="${REPO_DIR}/dist"

build_makemsix_image() {
  # makemsix pide C++14 y el ICU de Ubuntu 26.04 necesita C++17: se sube el estándar antes de compilar.
  docker build -q -m "${CONTAINER_MEMORY}" -t "${MAKEMSIX_IMAGE}" - <<DOCKERFILE >/dev/null
FROM ${BASE_IMAGE}
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      git ca-certificates cmake clang make zlib1g-dev libicu-dev libssl-dev >/dev/null \
 && git clone -q --depth 1 https://github.com/microsoft/msix-packaging.git /src \
 && cd /src \
 && find . -name CMakeLists.txt -exec sed -i -E 's/set\(CMAKE_CXX_STANDARD 1[14]\)/set(CMAKE_CXX_STANDARD 17)/' {} + \
 && ./makelinux.sh --pack --skip-samples --skip-tests >/tmp/build.log 2>&1 \
 && install -m 755 .vs/bin/makemsix /usr/local/bin/makemsix \
 && install -m 644 .vs/lib/libmsix.so /usr/local/lib/libmsix.so \
 && ldconfig && rm -rf /src /tmp/build.log
DOCKERFILE
}

if ! docker image inspect "${MAKEMSIX_IMAGE}" >/dev/null 2>&1; then
  echo "Compilando makemsix (una sola vez)..."
  build_makemsix_image
fi

MSIX_IDENTITY_NAME="${STORE_IDENTITY_NAME}" MSIX_PUBLISHER="${STORE_PUBLISHER}" \
  MSIX_PUBLISHER_DISPLAY_NAME="${STORE_PUBLISHER_DISPLAY_NAME}" bash "${REPO_DIR}/scripts/msix-layout.sh" "${VERSION}"

docker run --rm -m "${CONTAINER_MEMORY}" -v "${OUTPUT_DIR}:/dist" "${MAKEMSIX_IMAGE}" sh -euc '
  rm -f /dist/gastronova-impresion.msix
  makemsix pack -d /dist/msix -p /dist/gastronova-impresion.msix >/dev/null
  makemsix unpack -p /dist/gastronova-impresion.msix -d /tmp/control -ss >/dev/null
  chown "$(stat -c %u:%g /dist)" /dist/gastronova-impresion.msix
'
echo "Paquete para la Store en ${OUTPUT_DIR}/gastronova-impresion.msix."
