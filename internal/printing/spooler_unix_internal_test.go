//go:build !windows

package printing

import (
	"errors"
	"io"
	"os/exec"
	"reflect"
	"slices"
	"strings"
	"testing"
)

const printerName = "EPSON TM-T20"

var errCommand = errors.New("el comando falló")

func answering(output string, failure error) func(*exec.Cmd) ([]byte, error) {
	return func(*exec.Cmd) ([]byte, error) {
		return []byte(output), failure
	}
}

func TestNewSpoolerRunsTheRealCommands(t *testing.T) {
	t.Parallel()

	spooler := NewSpooler()
	if spooler.output == nil || spooler.combinedOutput == nil {
		t.Errorf("cola: %+v", spooler)
	}
}

func TestNamesParsesTheListAndSkipsBlankLines(t *testing.T) {
	t.Parallel()

	var asked []string

	spooler := &Spooler{combinedOutput: nil, output: func(command *exec.Cmd) ([]byte, error) {
		asked = command.Args

		return []byte(printerName + "\n\n  Cocina \n"), nil
	}}

	names, err := spooler.Names(t.Context())
	if err != nil {
		t.Fatal(err)
	}

	if !reflect.DeepEqual(names, []string{printerName, "Cocina"}) {
		t.Errorf("nombres: %q", names)
	}

	if !reflect.DeepEqual(asked, []string{"lpstat", "-e"}) {
		t.Errorf("comando: %q", asked)
	}
}

func TestNamesReportsAFailingCommand(t *testing.T) {
	t.Parallel()

	spooler := &Spooler{combinedOutput: nil, output: answering("", errCommand)}

	_, err := spooler.Names(t.Context())
	if !errors.Is(err, errCommand) {
		t.Errorf("error: %v", err)
	}
}

func TestPrintSendsRawBytesToTheDestination(t *testing.T) {
	t.Parallel()

	var (
		arguments, environment []string
		received               []byte
	)

	spooler := &Spooler{output: nil, combinedOutput: func(command *exec.Cmd) ([]byte, error) {
		arguments, environment = command.Args, command.Env

		content, err := io.ReadAll(command.Stdin)
		if err != nil {
			t.Errorf("entrada: %v", err)
		}

		received = content

		return nil, nil
	}}

	err := spooler.Print(t.Context(), printerName, []byte("ticket\x1b"))
	if err != nil {
		t.Fatal(err)
	}

	if !reflect.DeepEqual(arguments, []string{"lp", "-o", "raw"}) {
		t.Errorf("comando: %q", arguments)
	}

	if !slices.Contains(environment, "LPDEST="+printerName) {
		t.Errorf("sin destino: %q", environment)
	}

	if string(received) != "ticket\x1b" {
		t.Errorf("recibido: %q", received)
	}
}

func TestPrintIncludesWhatTheCommandSaid(t *testing.T) {
	t.Parallel()

	spooler := &Spooler{output: nil, combinedOutput: answering("destino inexistente\n", errCommand)}

	err := spooler.Print(t.Context(), printerName, []byte("x"))
	if !errors.Is(err, errCommand) || !strings.Contains(err.Error(), "destino inexistente") {
		t.Errorf("error: %v", err)
	}
}
