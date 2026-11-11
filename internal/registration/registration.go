// Package registration arma lo que Chrome necesita para encontrar el host de impresión en Windows cuando
// se instala desde el paquete MSIX: el manifiesto de native messaging, dónde se guarda y a qué apunta.
package registration

import (
	"encoding/json"
	"fmt"
	"path/filepath"
)

const (
	// HostName es el nombre con el que la extensión llama al host.
	HostName = "com.gastronova.print_host"
	// ExecutionAlias es el alias que declara el paquete: Windows lo deja siempre en la misma ruta, aunque la
	// carpeta del paquete cambie con cada actualización.
	ExecutionAlias  = "gastronova-print-host.exe"
	hostExecutable  = "gastronova-print-host.exe"
	extensionOrigin = "chrome-extension://hjhbknickakeacelnjfldbbhnobdibjc/"
	hostDescription = "Gastronova - Host de impresion termica"
	manifestFolder  = "GastroNova"
	vendorFolder    = "Microsoft"
	aliasFolder     = "WindowsApps"
	transportType   = "stdio"
)

// BrowserKeys son las claves de HKCU donde Chrome y Edge buscan el manifiesto del host.
func BrowserKeys() []string {
	return []string{
		`Software\Google\Chrome\NativeMessagingHosts\` + HostName,
		`Software\Microsoft\Edge\NativeMessagingHosts\` + HostName,
	}
}

type nativeHostManifest struct {
	Name           string   `json:"name"`
	Description    string   `json:"description"`
	Path           string   `json:"path"`
	Type           string   `json:"type"`
	AllowedOrigins []string `json:"allowed_origins"`
}

// Manifest es el manifiesto de native messaging que apunta a hostPath y sólo deja hablar a la extensión
// publicada.
func Manifest(hostPath string) ([]byte, error) {
	content, err := json.MarshalIndent(nativeHostManifest{
		Name:           HostName,
		Description:    hostDescription,
		Path:           hostPath,
		Type:           transportType,
		AllowedOrigins: []string{extensionOrigin},
	}, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("armar el manifiesto: %w", err)
	}

	return content, nil
}

// ManifestRelativePath es dónde queda el manifiesto, relativo a LOCALAPPDATA.
func ManifestRelativePath() string {
	return filepath.Join(manifestFolder, HostName+".json")
}

// ManifestPath es la ruta completa del manifiesto, la que se anota en el registro para el navegador.
func ManifestPath(localAppData string) string {
	return filepath.Join(localAppData, ManifestRelativePath())
}

// HostPath prefiere el alias de ejecución, que sobrevive a las actualizaciones; si el usuario lo apagó en la
// configuración de Windows, usa el ejecutable dentro de la carpeta del paquete.
func HostPath(localAppData, packageDir string, exists func(path string) bool) string {
	alias := filepath.Join(localAppData, vendorFolder, aliasFolder, ExecutionAlias)
	if exists(alias) {
		return alias
	}

	return filepath.Join(packageDir, hostExecutable)
}
