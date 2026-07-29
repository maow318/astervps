package main

import (
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"strconv"
	"time"
)

type server struct {
	token     string
	collector *collector
	services  *serviceCollector
}

func registerHandlers(mux *http.ServeMux, s *server) {
	mux.HandleFunc("/v1/meta", s.metaHandler)
	mux.HandleFunc("/v1/metrics", s.metricsHandler)
	mux.HandleFunc("/v1/history", s.historyHandler)
	mux.HandleFunc("/v1/services", s.servicesHandler)
	mux.HandleFunc("/v1/processes", s.processesHandler)
}

func (s *server) authorized(w http.ResponseWriter, r *http.Request) bool {
	// Constant-time comparison so response timing leaks nothing about the token.
	provided := r.Header.Get("Authorization")
	expected := "Bearer " + s.token
	if subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) != 1 {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return false
	}
	return true
}

func (s *server) metaHandler(w http.ResponseWriter, r *http.Request) {
	if !s.authorized(w, r) {
		return
	}
	writeJSON(w, http.StatusOK, s.collector.currentMeta())
}

func (s *server) metricsHandler(w http.ResponseWriter, r *http.Request) {
	if !s.authorized(w, r) {
		return
	}
	writeJSON(w, http.StatusOK, s.collector.currentMetrics())
}

func (s *server) historyHandler(w http.ResponseWriter, r *http.Request) {
	if !s.authorized(w, r) {
		return
	}
	var since int64
	if raw := r.URL.Query().Get("since"); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid since")
			return
		}
		since = parsed
	}
	writeJSON(w, http.StatusOK, s.collector.historySince(since))
}

func (s *server) servicesHandler(w http.ResponseWriter, r *http.Request) {
	if !s.authorized(w, r) {
		return
	}
	force := r.URL.Query().Get("refresh") == "1"
	writeJSON(w, http.StatusOK, s.services.current(force))
}

func (s *server) processesHandler(w http.ResponseWriter, r *http.Request) {
	if !s.authorized(w, r) {
		return
	}
	processes := s.collector.currentTopProcesses()
	if processes == nil {
		processes = []ProcessInfo{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"timestamp": time.Now().Unix(),
		"processes": processes,
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
