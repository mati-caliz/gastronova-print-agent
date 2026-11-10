// Package host atiende los pedidos de la extensión de Chrome: listar impresoras e imprimir.
package host

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"slices"
	"strings"

	"github.com/mati-caliz/gastronova-print-agent/internal/nativemessage"
)

const (
	typeListPrinters = "LIST_PRINTERS"
	typePrinterList  = "PRINTER_LIST"
	typePrint        = "PRINT"
	typePrintResult  = "PRINT_RESULT"

	messageMissingFields = "Faltan la impresora o los datos del trabajo"
	messageInvalidData   = "Los datos del trabajo no son base64 válido"
)

// Spooler es la cola de impresión del sistema operativo.
type Spooler interface {
	Names(ctx context.Context) ([]string, error)
	Print(ctx context.Context, printerName string, data []byte) error
}

// Host responde a un cliente por su salida.
type Host struct {
	spooler Spooler
	output  io.Writer
}

// New arma el host.
func New(spooler Spooler, output io.Writer) *Host {
	return &Host{spooler: spooler, output: output}
}

type request struct {
	Type        string          `json:"type"`
	PrinterName string          `json:"printerName"`
	DataBase64  string          `json:"dataBase64"`
	RequestID   json.RawMessage `json:"requestId"`
}

type printerList struct {
	Type      string          `json:"type"`
	RequestID json.RawMessage `json:"requestId"`
	Printers  []string        `json:"printers"`
}

type printResult struct {
	Type      string          `json:"type"`
	Message   string          `json:"message"`
	RequestID json.RawMessage `json:"requestId"`
	Success   bool            `json:"success"`
}

type jobOutcome struct {
	message string
	success bool
}

func failedJob(message string) jobOutcome {
	return jobOutcome{message: message, success: false}
}

// Serve atiende hasta que Chrome cierra la entrada.
func (host *Host) Serve(ctx context.Context, input io.Reader) error {
	for {
		payload, err := nativemessage.Read(input)
		if errors.Is(err, io.EOF) {
			return nil
		}

		if err != nil {
			return fmt.Errorf("leer el pedido: %w", err)
		}

		err = host.handle(ctx, payload)
		if err != nil {
			return err
		}
	}
}

func (host *Host) handle(ctx context.Context, payload []byte) error {
	var incoming request

	err := json.Unmarshal(payload, &incoming)
	if err != nil {
		slog.WarnContext(ctx, "pedido que no es JSON", "error", err)

		return nil
	}

	switch incoming.Type {
	case typeListPrinters:
		return host.listPrinters(ctx, &incoming)
	case typePrint:
		return host.print(ctx, &incoming)
	default:
		slog.WarnContext(ctx, "tipo de pedido desconocido", "type", incoming.Type)

		return nil
	}
}

func (host *Host) listPrinters(ctx context.Context, incoming *request) error {
	names, err := host.spooler.Names(ctx)
	if err != nil {
		slog.WarnContext(ctx, "no se pudieron listar las impresoras", "error", err)
	}

	if names == nil {
		names = []string{}
	}

	return host.reply(&printerList{Type: typePrinterList, RequestID: incoming.RequestID, Printers: names})
}

func (host *Host) print(ctx context.Context, incoming *request) error {
	outcome := host.printJob(ctx, incoming)

	return host.reply(&printResult{
		Type:      typePrintResult,
		RequestID: incoming.RequestID,
		Message:   outcome.message,
		Success:   outcome.success,
	})
}

func (host *Host) printJob(ctx context.Context, incoming *request) jobOutcome {
	if incoming.PrinterName == "" || incoming.DataBase64 == "" {
		return failedJob(messageMissingFields)
	}

	data, err := base64.StdEncoding.DecodeString(incoming.DataBase64)
	if err != nil {
		return failedJob(messageInvalidData)
	}

	names, err := host.spooler.Names(ctx)
	if err != nil {
		return failedJob("No se pudieron listar las impresoras: " + err.Error())
	}

	position := slices.IndexFunc(names, func(name string) bool {
		return strings.EqualFold(name, incoming.PrinterName)
	})
	if position < 0 {
		return failedJob("No se encontró la impresora " + incoming.PrinterName)
	}

	err = host.spooler.Print(ctx, names[position], data)
	if err != nil {
		return failedJob("No se pudo imprimir en " + names[position] + ": " + err.Error())
	}

	return jobOutcome{message: "Trabajo enviado a " + names[position], success: true}
}

func (host *Host) reply(response any) error {
	payload, err := json.Marshal(response)
	if err != nil {
		return fmt.Errorf("armar la respuesta: %w", err)
	}

	err = nativemessage.Write(host.output, payload)
	if err != nil {
		return fmt.Errorf("mandar la respuesta: %w", err)
	}

	return nil
}
