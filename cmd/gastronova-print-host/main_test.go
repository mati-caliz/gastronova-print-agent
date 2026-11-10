package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"strings"
	"testing"
)

type noPrinters struct{}

func (noPrinters) Names(context.Context) ([]string, error) {
	return []string{}, nil
}

func (noPrinters) Print(context.Context, string, []byte) error {
	return nil
}

func TestRunEndsCleanlyWhenChromeClosesTheInput(t *testing.T) {
	t.Parallel()

	var output bytes.Buffer

	if code := run(strings.NewReader(""), &output, noPrinters{}); code != exitSuccess {
		t.Errorf("salida: %d", code)
	}
}

func TestRunFailsOnABrokenFrame(t *testing.T) {
	t.Parallel()

	var (
		output bytes.Buffer
		frame  bytes.Buffer
	)

	err := binary.Write(&frame, binary.LittleEndian, uint32(0))
	if err != nil {
		t.Fatal(err)
	}

	if code := run(&frame, &output, noPrinters{}); code != exitFailure {
		t.Errorf("salida: %d", code)
	}
}
