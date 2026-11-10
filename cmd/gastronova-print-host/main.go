// Command gastronova-print-host es el host nativo que la extensión de Chrome lanza para imprimir.
package main

import (
	"context"
	"io"
	"log/slog"
	"os"

	"github.com/mati-caliz/gastronova-print-agent/internal/host"
	"github.com/mati-caliz/gastronova-print-agent/internal/printing"
)

const (
	exitSuccess = 0
	exitFailure = 1
)

func main() {
	os.Exit(run(os.Stdin, os.Stdout, printing.NewSpooler()))
}

func run(input io.Reader, output io.Writer, spooler host.Spooler) int {
	err := host.New(spooler, output).Serve(context.Background(), input)
	if err != nil {
		slog.Error("el host de impresión se detuvo", "error", err)

		return exitFailure
	}

	return exitSuccess
}
