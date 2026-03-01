package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

var db *sql.DB

type Session struct {
	ID       int64 `json:"id"`
	StartMs  int64 `json:"start"`
	EndMs    int64 `json:"end"`
	Duration int64 `json:"duration"`
}

type ActiveFast struct {
	StartMs int64 `json:"start"`
}

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "/data/fasting.db?_journal_mode=WAL")
	if err != nil {
		log.Fatal(err)
	}

	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS sessions (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			start_ms INTEGER NOT NULL,
			end_ms INTEGER NOT NULL,
			duration_ms INTEGER NOT NULL
		);
		CREATE TABLE IF NOT EXISTS active_fast (
			id INTEGER PRIMARY KEY CHECK(id=1),
			start_ms INTEGER NOT NULL
		);
	`)
	if err != nil {
		log.Fatal(err)
	}
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func handleSessions(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query("SELECT id, start_ms, end_ms, duration_ms FROM sessions ORDER BY start_ms DESC")
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()

		sessions := []Session{}
		for rows.Next() {
			var s Session
			rows.Scan(&s.ID, &s.StartMs, &s.EndMs, &s.Duration)
			sessions = append(sessions, s)
		}
		writeJSON(w, 200, sessions)

	case http.MethodPost:
		var s Session
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		s.Duration = s.EndMs - s.StartMs
		res, err := db.Exec("INSERT INTO sessions (start_ms, end_ms, duration_ms) VALUES (?, ?, ?)",
			s.StartMs, s.EndMs, s.Duration)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		s.ID, _ = res.LastInsertId()
		writeJSON(w, 201, s)

	default:
		http.Error(w, "method not allowed", 405)
	}
}

func handleSessionDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", 405)
		return
	}

	// Extract ID from /api/sessions/{id}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/sessions/"), "/")
	id := parts[0]

	res, err := db.Exec("DELETE FROM sessions WHERE id = ?", id)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		http.Error(w, "not found", 404)
		return
	}
	w.WriteHeader(204)
}

func handleActive(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		var startMs int64
		err := db.QueryRow("SELECT start_ms FROM active_fast WHERE id = 1").Scan(&startMs)
		if err == sql.ErrNoRows {
			http.Error(w, "no active fast", 404)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, 200, ActiveFast{StartMs: startMs})

	case http.MethodPost:
		var a ActiveFast
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		_, err := db.Exec("INSERT OR REPLACE INTO active_fast (id, start_ms) VALUES (1, ?)", a.StartMs)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, 201, a)

	case http.MethodPut:
		var a ActiveFast
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		res, err := db.Exec("UPDATE active_fast SET start_ms = ? WHERE id = 1", a.StartMs)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			http.Error(w, "no active fast", 404)
			return
		}
		writeJSON(w, 200, a)

	case http.MethodDelete:
		var startMs int64
		err := db.QueryRow("SELECT start_ms FROM active_fast WHERE id = 1").Scan(&startMs)
		if err == sql.ErrNoRows {
			http.Error(w, "no active fast", 404)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}

		endMs := nowMs()
		duration := endMs - startMs

		_, err = db.Exec("INSERT INTO sessions (start_ms, end_ms, duration_ms) VALUES (?, ?, ?)",
			startMs, endMs, duration)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}

		db.Exec("DELETE FROM active_fast WHERE id = 1")

		writeJSON(w, 200, Session{StartMs: startMs, EndMs: endMs, Duration: duration})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

func nowMs() int64 {
	return time.Now().UnixMilli()
}

func main() {
	initDB()

	// API routes
	http.HandleFunc("/api/sessions", handleSessions)
	http.HandleFunc("/api/sessions/", handleSessionDelete)
	http.HandleFunc("/api/active", handleActive)

	// Static files
	http.Handle("/", http.FileServer(http.Dir("frontend")))

	fmt.Println("Fasting Tracker running on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
