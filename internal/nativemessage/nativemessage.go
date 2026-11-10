// Package nativemessage implementa el marco de native messaging de Chrome: cuatro bytes de largo en
// little endian seguidos del JSON.
package nativemessage

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
)

const (
	lengthPrefixBytes = 4
	maxMessageBytes   = 1024 * 1024
)

// ErrInvalidLength es un largo vacío o mayor al tope: el marco ya no se puede resincronizar.
var ErrInvalidLength = errors.New("largo de mensaje inválido")

// Read devuelve el próximo mensaje, o io.EOF cuando Chrome cerró la entrada.
func Read(reader io.Reader) ([]byte, error) {
	prefix := make([]byte, lengthPrefixBytes)

	_, err := io.ReadFull(reader, prefix)
	if err != nil {
		return nil, fmt.Errorf("largo del mensaje: %w", err)
	}

	length := binary.LittleEndian.Uint32(prefix)
	if length == 0 || length > maxMessageBytes {
		return nil, fmt.Errorf("%w: %d", ErrInvalidLength, length)
	}

	payload := make([]byte, length)

	_, err = io.ReadFull(reader, payload)
	if err != nil {
		return nil, fmt.Errorf("cuerpo del mensaje: %w", err)
	}

	return payload, nil
}

// Write manda un mensaje en una sola escritura.
func Write(writer io.Writer, payload []byte) error {
	frame := make([]byte, lengthPrefixBytes, lengthPrefixBytes+len(payload))

	length := len(payload)
	if length > maxMessageBytes {
		return fmt.Errorf("%w: %d", ErrInvalidLength, length)
	}

	binary.LittleEndian.PutUint32(frame, uint32(length))

	_, err := writer.Write(append(frame, payload...))
	if err != nil {
		return fmt.Errorf("escribir el mensaje: %w", err)
	}

	return nil
}
