package credentials

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	originCertFile = "cert.pem"
)

var nopLog = zerolog.Nop().With().Logger()

func TestLoadOriginCert(t *testing.T) {
	cert, err := decodeOriginCert([]byte{})
	assert.Equal(t, fmt.Errorf("cannot decode empty certificate"), err)
	assert.Nil(t, cert)

	blocks, err := os.ReadFile("test-cert-unknown-block.pem")
	require.NoError(t, err)
	cert, err = decodeOriginCert(blocks)
	assert.Equal(t, fmt.Errorf("unknown block RSA PRIVATE KEY in the certificate"), err)
	assert.Nil(t, cert)
}

func TestJSONArgoTunnelTokenEmpty(t *testing.T) {
	blocks, err := os.ReadFile("test-cert-no-token.pem")
	require.NoError(t, err)
	cert, err := decodeOriginCert(blocks)
	assert.Equal(t, fmt.Errorf("missing token in the certificate"), err)
	assert.Nil(t, cert)
}

func TestJSONArgoTunnelToken(t *testing.T) {
	// The given cert's Argo Tunnel Token was generated by base64 encoding this JSON:
	// {
	// "zoneID": "7b0a4d77dfb881c1a3b7d61ea9443e19",
	// "apiToken": "test-service-key",
	// "accountID": "abcdabcdabcdabcd1234567890abcdef"
	// }
	CloudflareTunnelTokenTest(t, "test-cloudflare-tunnel-cert-json.pem")
}

func CloudflareTunnelTokenTest(t *testing.T, path string) {
	blocks, err := os.ReadFile(path)
	require.NoError(t, err)
	cert, err := decodeOriginCert(blocks)
	require.NoError(t, err)
	assert.NotNil(t, cert)
	assert.Equal(t, "7b0a4d77dfb881c1a3b7d61ea9443e19", cert.ZoneID)
	key := "test-service-key"
	assert.Equal(t, key, cert.APIToken)
}

func TestFindOriginCert_Valid(t *testing.T) {
	file, err := os.ReadFile("test-cloudflare-tunnel-cert-json.pem")
	require.NoError(t, err)
	dir := t.TempDir()
	certPath := filepath.Join(dir, originCertFile)
	_ = os.WriteFile(certPath, file, fs.ModePerm)
	path, err := FindOriginCert(certPath, &nopLog)
	require.NoError(t, err)
	require.Equal(t, certPath, path)
}

func TestFindOriginCert_Missing(t *testing.T) {
	dir := t.TempDir()
	certPath := filepath.Join(dir, originCertFile)
	_, err := FindOriginCert(certPath, &nopLog)
	require.Error(t, err)
}

func TestEncodeDecodeOriginCert(t *testing.T) {
	cert := OriginCert{
		ZoneID:    "zone",
		AccountID: "account",
		APIToken:  "token",
		Endpoint:  "FED",
	}
	blocks, err := cert.EncodeOriginCert()
	require.NoError(t, err)
	decodedCert, err := DecodeOriginCert(blocks)
	require.NoError(t, err)
	assert.NotNil(t, cert)
	assert.Equal(t, "zone", decodedCert.ZoneID)
	assert.Equal(t, "account", decodedCert.AccountID)
	assert.Equal(t, "token", decodedCert.APIToken)
	assert.Equal(t, FedEndpoint, decodedCert.Endpoint)
}

func TestEncodeDecodeNilOriginCert(t *testing.T) {
	var cert *OriginCert
	blocks, err := cert.EncodeOriginCert()
	assert.Equal(t, fmt.Errorf("originCert cannot be nil"), err)
	require.Nil(t, blocks)
}
