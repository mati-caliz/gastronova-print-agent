//go:build windows

// Command gastronova-register es la app «Gastronova Impresión» del paquete MSIX: al abrirla registra el host
// de impresión en Chrome y en Edge. Un paquete MSIX no puede correr nada al instalarse: se abre una vez.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"

	"github.com/mati-caliz/gastronova-print-agent/internal/registration"
)

const (
	windowTitle    = "Gastronova Impresión"
	successMessage = "Listo: el componente de impresión quedó conectado a Chrome.\n\n" +
		"Cerrá Chrome del todo y volvé a abrirlo. " +
		"En Gastronova, la tarjeta de Impresoras va a pasar a «Conectado»."
	failureMessage = "No se pudo conectar el componente de impresión a Chrome:\n\n%v\n\n" +
		"Si vuelve a pasar, escribinos a soporte@gastronova.com.ar."
	manifestDirMode  = 0o700
	manifestFileMode = 0o600
	exitFailure      = 1
)

var errMissingLocalAppData = errors.New("falta la variable LOCALAPPDATA")

func main() {
	text, style := successMessage, uint32(windows.MB_OK|windows.MB_ICONINFORMATION)

	registerErr := register()
	if registerErr != nil {
		text, style = fmt.Sprintf(failureMessage, registerErr), windows.MB_OK|windows.MB_ICONERROR
	}

	showErr := showMessage(text, style)
	if registerErr != nil || showErr != nil {
		os.Exit(exitFailure)
	}
}

func register() error {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		return errMissingLocalAppData
	}

	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("ubicar el programa: %w", err)
	}

	content, err := registration.Manifest(
		registration.HostPath(localAppData, filepath.Dir(executable), exists),
	)
	if err != nil {
		return fmt.Errorf("manifiesto del host: %w", err)
	}

	err = writeManifest(localAppData, content)
	if err != nil {
		return err
	}

	manifestPath := registration.ManifestPath(localAppData)
	for _, keyPath := range registration.BrowserKeys() {
		err = pointKeyTo(keyPath, manifestPath)
		if err != nil {
			return err
		}
	}

	return nil
}

// writeManifest escribe adentro de LOCALAPPDATA y no puede salirse de esa carpeta.
func writeManifest(localAppData string, content []byte) (err error) {
	root, err := os.OpenRoot(localAppData)
	if err != nil {
		return fmt.Errorf("abrir LOCALAPPDATA: %w", err)
	}

	defer func() {
		closeErr := root.Close()
		if err == nil && closeErr != nil {
			err = fmt.Errorf("cerrar LOCALAPPDATA: %w", closeErr)
		}
	}()

	relativePath := registration.ManifestRelativePath()

	err = root.MkdirAll(filepath.Dir(relativePath), manifestDirMode)
	if err != nil {
		return fmt.Errorf("crear la carpeta del manifiesto: %w", err)
	}

	err = root.WriteFile(relativePath, content, manifestFileMode)
	if err != nil {
		return fmt.Errorf("guardar el manifiesto: %w", err)
	}

	return nil
}

func pointKeyTo(keyPath, manifestPath string) (err error) {
	key, _, err := registry.CreateKey(registry.CURRENT_USER, keyPath, registry.SET_VALUE)
	if err != nil {
		return fmt.Errorf("abrir %s: %w", keyPath, err)
	}

	defer func() {
		closeErr := key.Close()
		if err == nil && closeErr != nil {
			err = fmt.Errorf("cerrar %s: %w", keyPath, closeErr)
		}
	}()

	err = key.SetStringValue("", manifestPath)
	if err != nil {
		return fmt.Errorf("escribir %s: %w", keyPath, err)
	}

	return nil
}

// exists usa Lstat porque el alias de ejecución es un punto de reanálisis que Stat no puede seguir.
func exists(path string) bool {
	_, err := os.Lstat(path)

	return err == nil
}

func showMessage(text string, style uint32) error {
	textPointer, err := windows.UTF16PtrFromString(text)
	if err != nil {
		return fmt.Errorf("preparar el mensaje: %w", err)
	}

	titlePointer, err := windows.UTF16PtrFromString(windowTitle)
	if err != nil {
		return fmt.Errorf("preparar el título: %w", err)
	}

	_, err = windows.MessageBox(0, textPointer, titlePointer, style)
	if err != nil {
		return fmt.Errorf("mostrar el mensaje: %w", err)
	}

	return nil
}
