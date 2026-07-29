// aster-agent exposes local system metrics over an authenticated HTTPS API.
//
// The agent is installed on machines that should appear in the Aster macOS
// app. The app polls /v1/metrics for live data and /v1/history to backfill
// gaps after it was offline. See docs/aster-protocol.md for the contract.
package main

import (
	"crypto/tls"
	"flag"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const version = "0.6.0"

func main() {
	listen := flag.String("listen", ":9977", "HTTPS listen address")
	token := flag.String("token", "", "bearer token (prefer --token-file, which keeps it out of the process list)")
	tokenFile := flag.String("token-file", "", "file containing the bearer token")
	historyMinutes := flag.Int("history-minutes", 360, "in-memory history retention in minutes")
	stateDir := flag.String("state-dir", "", "directory for TLS state (default: /var/lib/aster-agent for root, user config dir otherwise)")
	certPath := flag.String("cert", "", "certificate path (generated under state dir when omitted)")
	keyPath := flag.String("key", "", "private key path (generated under state dir when omitted)")
	servicesInterval := flag.Int("services-interval", 60, "service inspection refresh interval in seconds")
	dockerSock := flag.String("docker-sock", "/var/run/docker.sock", "docker unix socket path")
	flag.Parse()

	if *tokenFile != "" {
		content, err := os.ReadFile(*tokenFile)
		if err != nil {
			log.Fatalf("reading --token-file: %v", err)
		}
		*token = strings.TrimSpace(string(content))
	}
	if *token == "" {
		log.Fatal("--token or --token-file is required")
	}

	collector := newCollector(*historyMinutes)
	collector.start()
	services := newServiceCollector(*servicesInterval, *dockerSock)
	services.start()

	dir, err := resolveStateDir(*stateDir)
	if err != nil {
		log.Fatalf("resolving state dir: %v", err)
	}
	certFile, keyFile, err := ensureCertificate(dir, *certPath, *keyPath)
	if err != nil {
		log.Fatalf("preparing certificate: %v", err)
	}
	fingerprint, err := certificateFingerprint(certFile)
	if err != nil {
		log.Fatalf("reading certificate: %v", err)
	}

	mux := http.NewServeMux()
	registerHandlers(mux, &server{token: *token, collector: collector, services: services})

	log.Printf("aster-agent %s listening on https://%s", version, *listen)
	log.Printf("TLS state dir: %s", dir)
	log.Printf("TLS SHA-256 fingerprint: %s", fingerprint)

	httpServer := &http.Server{
		Addr:              *listen,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		TLSConfig:         &tls.Config{MinVersion: tls.VersionTLS13},
	}
	log.Fatal(httpServer.ListenAndServeTLS(certFile, keyFile))
}
