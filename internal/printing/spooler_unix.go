//go:build !windows

// Package printing manda los trabajos a la cola de impresión del sistema operativo.
package printing

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	listProgram    = "lpstat"
	listFlag       = "-e"
	printProgram   = "lp"
	rawOptionFlag  = "-o"
	rawOption      = "raw"
	commandTimeout = 30 * time.Second
)

// Spooler imprime por CUPS.
type Spooler struct {
	output         func(*exec.Cmd) ([]byte, error)
	combinedOutput func(*exec.Cmd) ([]byte, error)
}

// NewSpooler arma la cola de CUPS.
func NewSpooler() *Spooler {
	return &Spooler{output: (*exec.Cmd).Output, combinedOutput: (*exec.Cmd).CombinedOutput}
}

// Names lista las impresoras de CUPS.
func (spooler *Spooler) Names(ctx context.Context) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()

	output, err := spooler.output(exec.CommandContext(ctx, listProgram, listFlag))
	if err != nil {
		return nil, fmt.Errorf("listar impresoras: %w", err)
	}

	names := []string{}

	for line := range strings.Lines(string(output)) {
		name := strings.TrimSpace(line)
		if name != "" {
			names = append(names, name)
		}
	}

	return names, nil
}

// Print manda los bytes sin filtrar, tal como los espera una térmica. El destino va en LPDEST y no
// en un argumento: un nombre que empiece con guion no puede convertirse en una opción de lp.
func (spooler *Spooler) Print(ctx context.Context, printerName string, data []byte) error {
	ctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()

	command := exec.CommandContext(ctx, printProgram, rawOptionFlag, rawOption)

	command.Env = append(os.Environ(), "LPDEST="+printerName)
	command.Stdin = bytes.NewReader(data)

	output, err := spooler.combinedOutput(command)
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(output)))
	}

	return nil
}
