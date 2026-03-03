package connection

import (
	"errors"
	"testing"

	"github.com/quic-go/quic-go"
	"github.com/stretchr/testify/require"
)

func TestConnectionErrorsUnwrap(t *testing.T) {
	t.Parallel()

	idleTimeoutErr := &quic.IdleTimeoutError{}

	testCases := []struct {
		name string
		err  error
		msg  string
	}{
		{
			name: "control stream",
			err:  &ControlStreamError{Cause: idleTimeoutErr},
			msg:  "control stream encountered a failure while serving",
		},
		{
			name: "stream listener",
			err:  &StreamListenerError{Cause: idleTimeoutErr},
			msg:  "accept stream listener encountered a failure while serving",
		},
		{
			name: "datagram manager",
			err:  &DatagramManagerError{Cause: idleTimeoutErr},
			msg:  "datagram manager encountered a failure while serving",
		},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			var unwrappedIdleTimeout *quic.IdleTimeoutError

			require.Equal(t, tc.msg, tc.err.Error())
			require.ErrorAs(t, tc.err, &unwrappedIdleTimeout)
			require.True(t, errors.Is(tc.err, idleTimeoutErr))
		})
	}
}
