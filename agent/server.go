package main

import (
	"encoding/json"
	"net/http"
	"strconv"
)

type server struct {
	token     string
	collector *collector
}

func registerHandlers(mux *http.ServeMux, s *server) {
	mux.HandleFunc("/v1/meta", s.metaHandler)
	mux.HandleFunc("/v1/metrics", s.metricsHandler)
	mux.HandleFunc("/v1/history", s.historyHandler)
}

func (s *server) authorized(w http.ResponseWriter, r *http.Request) bool {
	if r.Header.Get("Authorization") != "Bearer "+s.token {
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

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
