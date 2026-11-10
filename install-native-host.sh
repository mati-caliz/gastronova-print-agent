#!/usr/bin/env bash
# Registra el host de impresión de Gastronova en Chrome y Chromium, en Linux y macOS.
#
#   ./install-native-host.sh [ID_DE_LA_EXTENSION]
set -euo pipefail

readonly HOST_NAME="com.gastronova.print_host"
readonly BINARY_NAME="gastronova-print-host"
readonly DEFAULT_EXTENSION_ID="hjhbknickakeacelnjfldbbhnobdibjc"
readonly INSTALL_DIR="${HOME}/.gastronova"

script_dir="$(cd "$(dirname "$0")" && pwd)"
extension_id="${1:-${DEFAULT_EXTENSION_ID}}"

case "$(uname -s)" in
  Linux*)
    chrome_dir="${HOME}/.config/google-chrome/NativeMessagingHosts"
    chromium_dir="${HOME}/.config/chromium/NativeMessagingHosts"
    ;;
  Darwin*)
    chrome_dir="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    chromium_dir="${HOME}/Library/Application Support/Chromium/NativeMessagingHosts"
    ;;
  *)
    echo "Este script es para Linux y macOS. En Windows usá el instalador .exe." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64 | aarch64) architecture="arm64" ;;
  *) architecture="amd64" ;;
esac

source_binary="${script_dir}/${BINARY_NAME}"
if [[ ! -f "${source_binary}" ]]; then
  source_binary="${script_dir}/${BINARY_NAME}-${architecture}"
fi

mkdir -p "${INSTALL_DIR}"
installed_binary="${INSTALL_DIR}/${BINARY_NAME}"
install -m 755 "${source_binary}" "${installed_binary}"

if [[ "$(uname -s)" == Darwin* ]]; then
  xattr -d com.apple.quarantine "${installed_binary}" 2>/dev/null || true
fi

write_manifest() {
  mkdir -p "$1"
  cat > "$1/${HOST_NAME}.json" << EOF
{
  "name": "${HOST_NAME}",
  "description": "Gastronova - Host de impresion termica",
  "path": "${installed_binary}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${extension_id}/"
  ]
}
EOF
  echo "Registrado en $1"
}

write_manifest "${chrome_dir}"

if [[ -d "$(dirname "${chromium_dir}")" ]]; then
  write_manifest "${chromium_dir}"
fi

echo "Instalación completa. Reiniciá Chrome si estaba abierto."
