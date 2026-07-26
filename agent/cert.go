package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

// resolveStateDir picks a directory that survives reboots so the generated
// certificate — and therefore the fingerprint the app has pinned — stays
// stable for the lifetime of the machine entry.
func resolveStateDir(override string) (string, error) {
	dir := override
	if dir == "" {
		if os.Geteuid() == 0 {
			dir = "/var/lib/aster-agent"
		} else {
			configDir, err := os.UserConfigDir()
			if err != nil {
				return "", fmt.Errorf("no user config dir, pass --state-dir: %w", err)
			}
			dir = filepath.Join(configDir, "aster-agent")
		}
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}

// ensureCertificate returns paths to a certificate/key pair, generating a
// self-signed pair under stateDir when no explicit paths are supplied.
func ensureCertificate(stateDir, certPath, keyPath string) (string, string, error) {
	if certPath == "" {
		certPath = filepath.Join(stateDir, "cert.pem")
	}
	if keyPath == "" {
		keyPath = filepath.Join(stateDir, "key.pem")
	}
	if _, err := os.Stat(certPath); err == nil {
		return certPath, keyPath, nil
	}
	certPEM, keyPEM, err := generateCertificate()
	if err != nil {
		return "", "", err
	}
	if err := os.WriteFile(certPath, certPEM, 0o600); err != nil {
		return "", "", err
	}
	if err := os.WriteFile(keyPath, keyPEM, 0o600); err != nil {
		return "", "", err
	}
	return certPath, keyPath, nil
}

func generateCertificate() ([]byte, []byte, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, nil, err
	}
	template := x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "aster-agent"},
		NotBefore:    time.Now().Add(-time.Minute),
		NotAfter:     time.Now().AddDate(10, 0, 0),
		// ECDSA certificates only sign; key encipherment is an RSA concept.
		KeyUsage:    x509.KeyUsageDigitalSignature,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:    []string{"localhost"},
	}
	certDER, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		return nil, nil, err
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return nil, nil, err
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
	return certPEM, keyPEM, nil
}

// certificateFingerprint hashes the DER encoding of the PEM certificate, which
// matches what the app computes from the TLS handshake's leaf certificate.
func certificateFingerprint(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	block, _ := pem.Decode(data)
	if block == nil {
		return "", fmt.Errorf("invalid certificate at %s", path)
	}
	sum := sha256.Sum256(block.Bytes)
	return hex.EncodeToString(sum[:]), nil
}
