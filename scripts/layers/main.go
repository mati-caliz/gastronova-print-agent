// Command layers chequea que ningún archivo de Go atienda HTTP y consulte la base a la vez
// (QS-203): el handler decodifica, llama y responde; la consulta vive en otro archivo del paquete.
// Así cada feature queda partida en transporte y acceso a datos aunque comparta paquete, y el SQL se
// prueba sin HTTP. Lo copia quality/sync.sh a scripts/layers/ de cada módulo y lo corre
// scripts/verify-go.sh; no se edita en el repo.
//
//	layers [-pending .layers-pending] ./...
//
// Los archivos que todavía mezclan van en el archivo de pendientes, uno por línea, con la ruta
// relativa al módulo: la lista sólo se achica, porque un archivo listado que ya no mezcla también es
// un error.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

const (
	exitClean    = 0
	exitFindings = 1
	exitBroken   = 2
)

func main() {
	os.Exit(execute(os.Args[1:], os.Stdout, os.Stderr))
}

// execute corre el chequeo en el directorio actual y devuelve el código de salida.
func execute(arguments []string, output, errorOutput io.Writer) int {
	flags := flag.NewFlagSet("layers", flag.ContinueOnError)
	flags.SetOutput(errorOutput)
	pendingPath := flags.String("pending", ".layers-pending", "archivos que todavía mezclan HTTP y base")

	err := flags.Parse(arguments)
	if err != nil {
		return exitBroken
	}

	problems, err := runHere(*pendingPath, flags.Args())
	if err != nil {
		return report(errorOutput, err.Error(), exitBroken)
	}

	if len(problems) == 0 {
		return exitClean
	}

	return report(output, strings.Join(problems, "\n"), exitFindings)
}

// report escribe el texto y devuelve code, o exitBroken si no pudo escribirlo.
func report(writer io.Writer, text string, code int) int {
	_, err := fmt.Fprintln(writer, text)
	if err != nil {
		return exitBroken
	}

	return code
}

func runHere(pendingPath string, patterns []string) ([]string, error) {
	moduleDir, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("layers: %w", err)
	}

	return run(moduleDir, pendingPath, patterns)
}
