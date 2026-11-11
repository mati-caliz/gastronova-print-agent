#!/usr/bin/env bash
# Arma los manifiestos de winget de una release ya publicada, para el PR a microsoft/winget-pkgs. El hash sale
# del .exe de la release, no de un build local: winget lo compara contra lo que baja.
#
#   scripts/winget-manifests.sh 2.2.0 <carpeta de salida>
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Uso: scripts/winget-manifests.sh <versión> <carpeta de salida>" >&2
  exit 1
fi

readonly VERSION="$1"
readonly OUTPUT_DIR="$2"
readonly PACKAGE_IDENTIFIER="Gastronova.Impresion"
readonly MANIFEST_VERSION="1.10.0"
readonly REPOSITORY_URL="https://github.com/mati-caliz/gastronova-print-agent"
readonly INSTALLER_URL="${REPOSITORY_URL}/releases/download/v${VERSION}/gastronova-impresion.exe"
readonly UNINSTALL_KEY="GastronovaImpresion"

installer_sha256="$(curl -fsSL --retry 3 "${INSTALLER_URL}" | sha256sum | cut -d ' ' -f 1 | tr '[:lower:]' '[:upper:]')"
readonly installer_sha256
release_date="$(gh release view "v${VERSION}" --repo mati-caliz/gastronova-print-agent --json publishedAt -q '.publishedAt[0:10]')"
readonly release_date

mkdir -p "${OUTPUT_DIR}"

cat >"${OUTPUT_DIR}/${PACKAGE_IDENTIFIER}.yaml" <<EOF
PackageIdentifier: ${PACKAGE_IDENTIFIER}
PackageVersion: ${VERSION}
DefaultLocale: es-AR
ManifestType: version
ManifestVersion: ${MANIFEST_VERSION}
EOF

cat >"${OUTPUT_DIR}/${PACKAGE_IDENTIFIER}.installer.yaml" <<EOF
PackageIdentifier: ${PACKAGE_IDENTIFIER}
PackageVersion: ${VERSION}
InstallerType: nullsoft
Scope: user
InstallModes:
- silent
- silentWithProgress
UpgradeBehavior: install
ProductCode: ${UNINSTALL_KEY}
ReleaseDate: ${release_date}
AppsAndFeaturesEntries:
- DisplayName: Gastronova Impresion
  Publisher: Gastronova
  DisplayVersion: ${VERSION}
  ProductCode: ${UNINSTALL_KEY}
Installers:
- Architecture: x64
  InstallerUrl: ${INSTALLER_URL}
  InstallerSha256: ${installer_sha256}
ManifestType: installer
ManifestVersion: ${MANIFEST_VERSION}
EOF

cat >"${OUTPUT_DIR}/${PACKAGE_IDENTIFIER}.locale.es-AR.yaml" <<EOF
PackageIdentifier: ${PACKAGE_IDENTIFIER}
PackageVersion: ${VERSION}
PackageLocale: es-AR
Publisher: Gastronova
PublisherUrl: https://gastronova.com.ar
PublisherSupportUrl: https://gastronova.com.ar/blog/como-conectar-impresora-termica-gastronova
PrivacyUrl: https://gastronova.com.ar/privacidad
PackageName: Gastronova Impresión
PackageUrl: ${REPOSITORY_URL}
License: MIT
LicenseUrl: ${REPOSITORY_URL}/blob/main/LICENSE
ShortDescription: Componente local para imprimir comandas y tickets de Gastronova en impresoras térmicas.
Description: Recibe los trabajos de la extensión de Chrome de Gastronova y los manda a la cola de impresión de Windows. No se conecta a internet ni guarda nada.
Moniker: gastronova-impresion
Tags:
- gastronova
- impresora-termica
- pos
- tickets
ReleaseNotesUrl: ${REPOSITORY_URL}/releases/tag/v${VERSION}
ManifestType: defaultLocale
ManifestVersion: ${MANIFEST_VERSION}
EOF

echo "Manifiestos de ${PACKAGE_IDENTIFIER} ${VERSION} en ${OUTPUT_DIR}."
