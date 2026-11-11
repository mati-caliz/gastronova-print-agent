#!/bin/bash
# Compila el host de impresión y arma los instaladores de cada sistema. Todo corre en contenedores:
# la máquina que lo corre sólo necesita Docker.
#
#   scripts/package.sh 2.1.0
#
# Salida en dist/:
#   gastronova-impresion.exe   Windows (instalador NSIS)
#   gastronova-impresion.ps1   Windows por PowerShell: baja ese .exe, lo verifica y lo instala sin preguntas
#   gastronova-impresion.deb   Debian, Ubuntu, Mint
#   gastronova-impresion.rpm   Fedora, RHEL, openSUSE
#   gastronova-impresion.zip   macOS (Intel y Apple Silicon, con install-native-host.sh)
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Uso: scripts/package.sh <versión>, por ejemplo scripts/package.sh 2.1.0" >&2
    exit 1
fi

VERSION="$1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${REPO_DIR}/dist"
PACKAGE_NAME="gastronova-impresion"
BINARY_NAME="gastronova-print-host"
GO_IMAGE="golang:1.27.4-bookworm@sha256:4fa7c968ba93f1635670522dbb01a2c78150443e1385746924566079f36570ea"
GO_CACHE_VOLUME="go-quality-cache"
CONTAINER_MEMORY="1500m"

mkdir -p "${OUTPUT_DIR}"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "${STAGING}/bin"

echo "Compilando el host de impresion..."
docker run --rm -m "${CONTAINER_MEMORY}" \
    -v "${REPO_DIR}":/src:ro -w /src \
    -v "${GO_CACHE_VOLUME}":/cache \
    -v "${STAGING}/bin":/out \
    -e GOMODCACHE=/cache/mod -e GOCACHE=/cache/build \
    -e GOFLAGS=-mod=readonly -e GOTOOLCHAIN=local -e CGO_ENABLED=0 \
    -e BINARY_NAME="${BINARY_NAME}" \
    "${GO_IMAGE}" bash -euc '
        compile() {
            GOOS="$1" GOARCH="$2" go build -trimpath -buildvcs=false -ldflags "-s -w" -o "/out/$3" ./cmd/gastronova-print-host
        }
        compile windows amd64 "$BINARY_NAME.exe"
        compile linux amd64 "$BINARY_NAME"
        compile darwin amd64 "$BINARY_NAME-amd64"
        compile darwin arm64 "$BINARY_NAME-arm64"
        chown -R "$(stat -c %u:%g /out)" /out
    '

LINUX_INSTALL_DIR="${STAGING}/linux/usr/lib/${PACKAGE_NAME}"
mkdir -p "${LINUX_INSTALL_DIR}" "${STAGING}/linux/DEBIAN" "${STAGING}/windows" "${STAGING}/macos"

cp "${STAGING}/bin/${BINARY_NAME}" "${REPO_DIR}/install-native-host.sh" "${LINUX_INSTALL_DIR}/"
chmod +x "${LINUX_INSTALL_DIR}/install-native-host.sh"

POSTINSTALL_MESSAGE="echo \"\"
echo \"Gastronova Impresion instalado en /usr/lib/${PACKAGE_NAME}\"
echo \"Para completar la instalacion ejecuta:\"
echo \"  /usr/lib/${PACKAGE_NAME}/install-native-host.sh\"
echo \"\""

cat > "${STAGING}/linux/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: cups-client
Maintainer: Gastronova <soporte@gastronova.com.ar>
Description: Agente de impresion termica para Gastronova
 Componente de escritorio que permite a la extension de Chrome de Gastronova
 comunicarse con impresoras termicas conectadas localmente.
EOF

printf '#!/bin/bash\nset -e\n%s\n' "${POSTINSTALL_MESSAGE}" > "${STAGING}/linux/DEBIAN/postinst"
chmod 755 "${STAGING}/linux/DEBIAN/postinst"

cp "${STAGING}/bin/${BINARY_NAME}.exe" "${STAGING}/windows/"

cp "${STAGING}/bin/${BINARY_NAME}-amd64" "${STAGING}/bin/${BINARY_NAME}-arm64" "${REPO_DIR}/install-native-host.sh" \
    "${STAGING}/macos/"
chmod +x "${STAGING}/macos/install-native-host.sh"
cat > "${STAGING}/macos/LEEME.txt" << EOF
Gastronova - Agente de Impresion Termica v${VERSION}
=====================================================

Instalacion:
  1. Abrir Terminal.
  2. Navegar a la carpeta donde descomprimiste este archivo.
  3. Ejecutar: ./install-native-host.sh
  4. Reiniciar Chrome si estaba abierto.

Soporte: soporte@gastronova.com.ar
EOF

echo "Generando .deb, .exe y .zip..."
docker run --rm -m "${CONTAINER_MEMORY}" \
    -v "${STAGING}":/staging \
    -v "${REPO_DIR}/installer.nsi":/build/installer.nsi:ro \
    -v "${OUTPUT_DIR}":/output \
    -e PACKAGE_NAME="${PACKAGE_NAME}" \
    -e VERSION="${VERSION}" \
    debian:trixie-slim bash -c '
        set -euo pipefail
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends nsis zip > /dev/null
        dpkg-deb --root-owner-group --build /staging/linux "/output/$PACKAGE_NAME.deb"
        cd /build && makensis -V2 -DSTAGING=/staging/windows -DVERSION="$VERSION" installer.nsi
        mv "/build/$PACKAGE_NAME.exe" "/output/$PACKAGE_NAME.exe"
        rm -f "/output/$PACKAGE_NAME.zip"
        zip -j -q "/output/$PACKAGE_NAME.zip" /staging/macos/*
        chown "$(stat -c %u:%g /output)" /output/*
    '

echo "Generando el instalador por PowerShell..."
INSTALLER_SHA256="$(sha256sum "${OUTPUT_DIR}/${PACKAGE_NAME}.exe" | cut -d ' ' -f 1 | tr '[:lower:]' '[:upper:]')"
sed -e '1s/^\xEF\xBB\xBF//' -e "s/__VERSION__/${VERSION}/" -e "s/__INSTALLER_SHA256__/${INSTALLER_SHA256}/" \
    "${REPO_DIR}/install-windows.ps1" > "${OUTPUT_DIR}/${PACKAGE_NAME}.ps1"

echo "Generando .rpm..."
docker run --rm -m "${CONTAINER_MEMORY}" \
    -v "${STAGING}/linux/usr/lib/${PACKAGE_NAME}":/staging:ro \
    -v "${OUTPUT_DIR}":/output \
    -e PACKAGE_NAME="${PACKAGE_NAME}" \
    -e VERSION="${VERSION}" \
    -e BINARY_NAME="${BINARY_NAME}" \
    -e POSTINSTALL_MESSAGE="${POSTINSTALL_MESSAGE}" \
    fedora:45 bash -c '
        set -euo pipefail
        dnf install -y --quiet rpm-build > /dev/null
        mkdir -p /root/rpmbuild/SPECS
        cat > "/root/rpmbuild/SPECS/$PACKAGE_NAME.spec" << SPEC
%define debug_package %{nil}
Name:           $PACKAGE_NAME
Version:        $VERSION
Release:        1
Summary:        Agente de impresion termica para Gastronova
License:        MIT
BuildArch:      x86_64
Requires:       cups-client

%description
Componente de escritorio que permite a la extension de Chrome de Gastronova
comunicarse con impresoras termicas conectadas localmente.

%install
mkdir -p %{buildroot}/usr/lib/$PACKAGE_NAME
cp /staging/* %{buildroot}/usr/lib/$PACKAGE_NAME/

%files
/usr/lib/$PACKAGE_NAME/$BINARY_NAME
/usr/lib/$PACKAGE_NAME/install-native-host.sh

%post
$POSTINSTALL_MESSAGE

%changelog
* $(LC_ALL=C date -u "+%a %b %d %Y") Gastronova <soporte@gastronova.com.ar> - $VERSION-1
- Version $VERSION
SPEC
        rpmbuild -bb --quiet "/root/rpmbuild/SPECS/$PACKAGE_NAME.spec"
        cp "/root/rpmbuild/RPMS/x86_64/$PACKAGE_NAME-$VERSION-1.x86_64.rpm" "/output/$PACKAGE_NAME.rpm"
        chown "$(stat -c %u:%g /output)" "/output/$PACKAGE_NAME.rpm"
    '


echo "Instaladores en dist/:"
ls -lh "${OUTPUT_DIR}"
