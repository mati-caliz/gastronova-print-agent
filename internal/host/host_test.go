package host_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"

	"github.com/mati-caliz/gastronova-print-agent/internal/host"
	"github.com/mati-caliz/gastronova-print-agent/internal/nativemessage"
)

const (
	thermalPrinter = "EPSON TM-T20"
	typeKey        = "type"
	requestKey     = "requestId"
	successKey     = "success"
	messageKey     = "message"
	printersKey    = "printers"
	printType      = "PRINT"
	listType       = "LIST_PRINTERS"
	printerNameKey = "printerName"
	dataKey        = "dataBase64"
	requestID      = "pedido-1"
	spoolFailure   = "cola detenida"
)

var errSpool = errors.New(spoolFailure)

type fakeSpooler struct {
	namesErr, printErr error
	printedTo          string
	names              []string
	printed            []byte
}

func (spooler *fakeSpooler) Names(context.Context) ([]string, error) {
	return spooler.names, spooler.namesErr
}

func (spooler *fakeSpooler) Print(_ context.Context, printerName string, data []byte) error {
	spooler.printedTo, spooler.printed = printerName, data

	return spooler.printErr
}

func spoolerWith(names []string, namesErr, printErr error) *fakeSpooler {
	return &fakeSpooler{namesErr: namesErr, printErr: printErr, printedTo: "", names: names, printed: nil}
}

func succeeded(answer map[string]any) bool {
	success, known := answer[successKey].(bool)

	return known && success
}

func frameOf(t *testing.T, requests ...map[string]any) *bytes.Buffer {
	t.Helper()

	var input bytes.Buffer

	for _, each := range requests {
		payload, err := json.Marshal(each)
		if err != nil {
			t.Fatal(err)
		}

		err = nativemessage.Write(&input, payload)
		if err != nil {
			t.Fatal(err)
		}
	}

	return &input
}

func serve(t *testing.T, spooler *fakeSpooler, input io.Reader) []map[string]any {
	t.Helper()

	var output bytes.Buffer

	err := host.New(spooler, &output).Serve(t.Context(), input)
	if err != nil {
		t.Fatalf("serve: %v", err)
	}

	answers := []map[string]any{}

	for output.Len() > 0 {
		payload, readErr := nativemessage.Read(&output)
		if readErr != nil {
			t.Fatal(readErr)
		}

		var answer map[string]any

		readErr = json.Unmarshal(payload, &answer)
		if readErr != nil {
			t.Fatal(readErr)
		}

		answers = append(answers, answer)
	}

	return answers
}

func printRequest(printerName, data string) map[string]any {
	return map[string]any{
		typeKey: printType, requestKey: requestID, printerNameKey: printerName, dataKey: data,
	}
}

func encoded(data string) string {
	return base64.StdEncoding.EncodeToString([]byte(data))
}

func TestListsPrintersEchoingTheRequest(t *testing.T) {
	t.Parallel()

	spooler := spoolerWith([]string{thermalPrinter}, nil, nil)
	answers := serve(t, spooler, frameOf(t, map[string]any{typeKey: listType, requestKey: requestID}))

	expected := map[string]any{
		typeKey:     "PRINTER_LIST",
		requestKey:  requestID,
		printersKey: []any{thermalPrinter},
	}
	if !reflect.DeepEqual(answers, []map[string]any{expected}) {
		t.Errorf("respuestas: %v", answers)
	}
}

func TestListIsEmptyWithoutRequestIDWhenTheSpoolerFails(t *testing.T) {
	t.Parallel()

	spooler := spoolerWith(nil, errSpool, nil)
	answers := serve(t, spooler, frameOf(t, map[string]any{typeKey: listType}))

	expected := map[string]any{typeKey: "PRINTER_LIST", requestKey: nil, printersKey: []any{}}
	if !reflect.DeepEqual(answers, []map[string]any{expected}) {
		t.Errorf("respuestas: %v", answers)
	}
}

func TestPrintsOnTheMatchingPrinterIgnoringCase(t *testing.T) {
	t.Parallel()

	spooler := spoolerWith([]string{thermalPrinter}, nil, nil)
	answers := serve(t, spooler, frameOf(t, printRequest(strings.ToLower(thermalPrinter), encoded("ticket"))))

	if spooler.printedTo != thermalPrinter || string(spooler.printed) != "ticket" {
		t.Errorf("impreso: %q %q", spooler.printedTo, spooler.printed)
	}

	if len(answers) != 1 || !succeeded(answers[0]) || answers[0][typeKey] != "PRINT_RESULT" ||
		answers[0][requestKey] != requestID {
		t.Errorf("respuestas: %v", answers)
	}
}

func TestPrintFailuresAreReportedAsFailures(t *testing.T) {
	t.Parallel()

	cases := map[string]struct {
		spooler *fakeSpooler
		request map[string]any
		message string
	}{
		"sin impresora": {
			spooler: spoolerWith([]string{thermalPrinter}, nil, nil),
			request: printRequest("", encoded("x")),
			message: "Faltan",
		},
		"sin datos": {
			spooler: spoolerWith([]string{thermalPrinter}, nil, nil),
			request: printRequest(thermalPrinter, ""),
			message: "Faltan",
		},
		"base64 roto": {
			spooler: spoolerWith([]string{thermalPrinter}, nil, nil),
			request: printRequest(thermalPrinter, "%%%"),
			message: "base64",
		},
		"impresora desconocida": {
			spooler: spoolerWith([]string{thermalPrinter}, nil, nil),
			request: printRequest("Otra", encoded("x")),
			message: "No se encontró",
		},
		"no se pudo listar": {
			spooler: spoolerWith(nil, errSpool, nil),
			request: printRequest(thermalPrinter, encoded("x")),
			message: spoolFailure,
		},
		"falla la cola": {
			spooler: spoolerWith([]string{thermalPrinter}, nil, errSpool),
			request: printRequest(thermalPrinter, encoded("x")),
			message: spoolFailure,
		},
	}

	for name, each := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			answers := serve(t, each.spooler, frameOf(t, each.request))
			if len(answers) != 1 || succeeded(answers[0]) {
				t.Fatalf("respuestas: %v", answers)
			}

			message, known := answers[0][messageKey].(string)
			if !known || !strings.Contains(message, each.message) {
				t.Errorf("mensaje: %v", answers[0][messageKey])
			}
		})
	}
}

func TestBadRequestsAreSkippedAndTheNextOneIsServed(t *testing.T) {
	t.Parallel()

	input := frameOf(t, map[string]any{typeKey: "OTRO"})

	err := nativemessage.Write(input, []byte("no es json"))
	if err != nil {
		t.Fatal(err)
	}

	payload, err := json.Marshal(map[string]any{typeKey: listType})
	if err != nil {
		t.Fatal(err)
	}

	err = nativemessage.Write(input, payload)
	if err != nil {
		t.Fatal(err)
	}

	if answers := serve(t, spoolerWith(nil, nil, nil), input); len(answers) != 1 {
		t.Errorf("respuestas: %v", answers)
	}
}

func TestServeFailsOnABrokenOutputAndABrokenFrame(t *testing.T) {
	t.Parallel()

	spooler := spoolerWith(nil, nil, nil)

	err := host.New(spooler, failingWriter{}).
		Serve(t.Context(), frameOf(t, map[string]any{typeKey: listType}))
	if !errors.Is(err, errSpool) {
		t.Errorf("salida rota: %v", err)
	}

	err = host.New(spooler, io.Discard).Serve(t.Context(), strings.NewReader("ab"))
	if !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Errorf("marco roto: %v", err)
	}
}

type failingWriter struct{}

func (failingWriter) Write([]byte) (int, error) {
	return 0, errSpool
}
