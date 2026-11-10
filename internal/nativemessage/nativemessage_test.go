package nativemessage_test

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/mati-caliz/gastronova-print-agent/internal/nativemessage"
)

const tooLong = 1024*1024 + 1

var errBrokenPipe = errors.New("pipe cerrado")

type brokenWriter struct{}

func (brokenWriter) Write([]byte) (int, error) {
	return 0, errBrokenPipe
}

func framed(t *testing.T, length uint32, body string) *bytes.Buffer {
	t.Helper()

	var frame bytes.Buffer

	err := binary.Write(&frame, binary.LittleEndian, length)
	if err != nil {
		t.Fatal(err)
	}

	frame.WriteString(body)

	return &frame
}

func TestWriteAndReadRoundTrip(t *testing.T) {
	t.Parallel()

	var frame bytes.Buffer

	err := nativemessage.Write(&frame, []byte(`{"type":"ñandú"}`))
	if err != nil {
		t.Fatal(err)
	}

	payload, err := nativemessage.Read(&frame)
	if err != nil || string(payload) != `{"type":"ñandú"}` {
		t.Errorf("leído: %q %v", payload, err)
	}
}

func TestReadReportsEndOfInput(t *testing.T) {
	t.Parallel()

	_, err := nativemessage.Read(strings.NewReader(""))
	if !errors.Is(err, io.EOF) {
		t.Errorf("error: %v", err)
	}
}

func TestReadRejectsInvalidLengths(t *testing.T) {
	t.Parallel()

	for _, length := range []uint32{0, tooLong} {
		_, err := nativemessage.Read(framed(t, length, ""))
		if !errors.Is(err, nativemessage.ErrInvalidLength) {
			t.Errorf("largo %d: %v", length, err)
		}
	}
}

func TestReadFailsOnTruncatedBody(t *testing.T) {
	t.Parallel()

	_, err := nativemessage.Read(framed(t, 10, "corto"))
	if !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Errorf("error: %v", err)
	}
}

func TestWriteRejectsOversizedMessage(t *testing.T) {
	t.Parallel()

	err := nativemessage.Write(io.Discard, make([]byte, tooLong))
	if !errors.Is(err, nativemessage.ErrInvalidLength) {
		t.Errorf("error: %v", err)
	}
}

func TestWriteReportsBrokenOutput(t *testing.T) {
	t.Parallel()

	err := nativemessage.Write(brokenWriter{}, []byte("{}"))
	if !errors.Is(err, errBrokenPipe) {
		t.Errorf("error: %v", err)
	}
}
