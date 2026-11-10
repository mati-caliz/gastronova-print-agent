//go:build windows

// Package printing manda los trabajos a la cola de impresión del sistema operativo.
package printing

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/alexbrainman/printer"
)

const documentName = "Gastronova"

// Spooler imprime por la cola de Windows.
type Spooler struct{}

// NewSpooler arma la cola de Windows.
func NewSpooler() *Spooler {
	return &Spooler{}
}

// Names lista las impresoras instaladas.
func (*Spooler) Names(context.Context) ([]string, error) {
	names, err := printer.ReadNames()
	if err != nil {
		return nil, fmt.Errorf("listar impresoras: %w", err)
	}

	return names, nil
}

// Print manda los bytes en modo RAW, sin pasar por el driver de gráficos: es lo que espera una térmica.
func (*Spooler) Print(ctx context.Context, printerName string, data []byte) error {
	opened, err := printer.Open(printerName)
	if err != nil {
		return fmt.Errorf("abrir la impresora: %w", err)
	}

	defer func() {
		closeErr := opened.Close()
		if closeErr != nil {
			slog.WarnContext(ctx, "no se pudo cerrar la impresora", "error", closeErr)
		}
	}()

	return writeDocument(opened, data)
}

func writeDocument(opened *printer.Printer, data []byte) error {
	err := opened.StartRawDocument(documentName)
	if err != nil {
		return fmt.Errorf("abrir el documento: %w", err)
	}

	err = opened.StartPage()
	if err == nil {
		_, err = opened.Write(data)
	}

	if err == nil {
		err = opened.EndPage()
	}

	endErr := opened.EndDocument()

	if err != nil {
		return fmt.Errorf("escribir el trabajo: %w", err)
	}

	if endErr != nil {
		return fmt.Errorf("cerrar el documento: %w", endErr)
	}

	return nil
}
