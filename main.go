package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

var db *sql.DB

type HabitType struct {
	ID   int64  `json:"id"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type Session struct {
	ID          int64  `json:"id"`
	HabitTypeID int64  `json:"habit_type_id"`
	StartMs     int64  `json:"start"`
	EndMs       int64  `json:"end"`
	Duration    int64  `json:"duration"`
}

type ActiveSession struct {
	HabitTypeID int64 `json:"habit_type_id"`
	StartMs     int64 `json:"start"`
}

type ActivityDay struct {
	ID          int64 `json:"id"`
	HabitTypeID int64 `json:"habit_type_id"`
	DayMs       int64 `json:"day_ms"`
}

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "/data/takecharge.db?_journal_mode=WAL")
	if err != nil {
		log.Fatal(err)
	}

	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS habit_types (
			id   INTEGER PRIMARY KEY AUTOINCREMENT,
			slug TEXT NOT NULL UNIQUE,
			name TEXT NOT NULL
		);
		INSERT OR IGNORE INTO habit_types (id, slug, name) VALUES (1, 'fasting', 'Fasting');
		INSERT OR IGNORE INTO habit_types (id, slug, name) VALUES (2, 'be-active', 'Be Active');

		CREATE TABLE IF NOT EXISTS sessions (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			start_ms      INTEGER NOT NULL,
			end_ms        INTEGER NOT NULL,
			duration_ms   INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS active_sessions (
			habit_type_id INTEGER PRIMARY KEY REFERENCES habit_types(id),
			start_ms      INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS activity_days (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			day_ms        INTEGER NOT NULL,
			UNIQUE(habit_type_id, day_ms)
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

func habitTypeID(slug string) (int64, error) {
	var id int64
	err := db.QueryRow("SELECT id FROM habit_types WHERE slug = ?", slug).Scan(&id)
	return id, err
}

// GET /api/habits
func handleHabits(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}
	rows, err := db.Query("SELECT id, slug, name FROM habit_types ORDER BY id")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	habits := []HabitType{}
	for rows.Next() {
		var h HabitType
		rows.Scan(&h.ID, &h.Slug, &h.Name)
		habits = append(habits, h)
	}
	writeJSON(w, 200, habits)
}

// /api/habits/:habit/sessions and /api/habits/:habit/sessions/:id
func handleHabitRouter(w http.ResponseWriter, r *http.Request) {
	// path after /api/habits/: "<slug>/sessions[/<id>]" or "<slug>/active"
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/habits/"), "/")
	if len(parts) < 2 {
		http.Error(w, "not found", 404)
		return
	}
	slug, resource := parts[0], parts[1]
	id := ""
	if len(parts) > 2 {
		id = parts[2]
	}

	switch resource {
	case "sessions":
		if id == "" {
			handleHabitSessions(w, r, slug)
		} else {
			handleHabitSessionByID(w, r, slug, id)
		}
	case "active":
		handleHabitActive(w, r, slug)
	case "days":
		if id == "" {
			handleHabitDays(w, r, slug)
		} else {
			handleHabitDayByID(w, r, slug, id)
		}
	default:
		http.Error(w, "not found", 404)
	}
}

// GET, POST /api/habits/:habit/sessions
func handleHabitSessions(w http.ResponseWriter, r *http.Request, slug string) {
	htID, err := habitTypeID(slug)
	if err == sql.ErrNoRows {
		http.Error(w, "habit not found", 404)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_type_id, start_ms, end_ms, duration_ms FROM sessions WHERE habit_type_id = ? ORDER BY start_ms DESC",
			htID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		sessions := []Session{}
		for rows.Next() {
			var s Session
			rows.Scan(&s.ID, &s.HabitTypeID, &s.StartMs, &s.EndMs, &s.Duration)
			sessions = append(sessions, s)
		}
		writeJSON(w, 200, sessions)

	case http.MethodPost:
		var s Session
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		s.HabitTypeID = htID
		s.Duration = s.EndMs - s.StartMs
		res, err := db.Exec(
			"INSERT INTO sessions (habit_type_id, start_ms, end_ms, duration_ms) VALUES (?, ?, ?, ?)",
			s.HabitTypeID, s.StartMs, s.EndMs, s.Duration,
		)
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

// PUT, DELETE /api/habits/:habit/sessions/:id
func handleHabitSessionByID(w http.ResponseWriter, r *http.Request, slug, id string) {
	htID, err := habitTypeID(slug)
	if err == sql.ErrNoRows {
		http.Error(w, "habit not found", 404)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	switch r.Method {
	case http.MethodPut:
		var s Session
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		s.Duration = s.EndMs - s.StartMs
		idInt, _ := strconv.ParseInt(id, 10, 64)
		res, err := db.Exec(
			"UPDATE sessions SET start_ms=?, end_ms=?, duration_ms=? WHERE id=? AND habit_type_id=?",
			s.StartMs, s.EndMs, s.Duration, id, htID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			http.Error(w, "not found", 404)
			return
		}
		s.ID = idInt
		s.HabitTypeID = htID
		writeJSON(w, 200, s)

	case http.MethodDelete:
		res, err := db.Exec("DELETE FROM sessions WHERE id=? AND habit_type_id=?", id, htID)
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

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET, POST, PUT, DELETE /api/habits/:habit/active
func handleHabitActive(w http.ResponseWriter, r *http.Request, slug string) {
	htID, err := habitTypeID(slug)
	if err == sql.ErrNoRows {
		http.Error(w, "habit not found", 404)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	switch r.Method {
	case http.MethodGet:
		var startMs int64
		err := db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_type_id = ?", htID).Scan(&startMs)
		if err == sql.ErrNoRows {
			http.Error(w, "no active session", 404)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, 200, ActiveSession{HabitTypeID: htID, StartMs: startMs})

	case http.MethodPost:
		var a ActiveSession
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		_, err := db.Exec(
			"INSERT OR REPLACE INTO active_sessions (habit_type_id, start_ms) VALUES (?, ?)",
			htID, a.StartMs,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		a.HabitTypeID = htID
		writeJSON(w, 201, a)

	case http.MethodPut:
		var a ActiveSession
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		res, err := db.Exec(
			"UPDATE active_sessions SET start_ms=? WHERE habit_type_id=?",
			a.StartMs, htID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			http.Error(w, "no active session", 404)
			return
		}
		a.HabitTypeID = htID
		writeJSON(w, 200, a)

	case http.MethodDelete:
		var startMs int64
		err := db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_type_id = ?", htID).Scan(&startMs)
		if err == sql.ErrNoRows {
			http.Error(w, "no active session", 404)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}

		endMs := nowMs()
		duration := endMs - startMs

		_, err = db.Exec(
			"INSERT INTO sessions (habit_type_id, start_ms, end_ms, duration_ms) VALUES (?, ?, ?, ?)",
			htID, startMs, endMs, duration,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}

		db.Exec("DELETE FROM active_sessions WHERE habit_type_id = ?", htID)

		writeJSON(w, 200, Session{HabitTypeID: htID, StartMs: startMs, EndMs: endMs, Duration: duration})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET, POST /api/habits/:habit/days
func handleHabitDays(w http.ResponseWriter, r *http.Request, slug string) {
	htID, err := habitTypeID(slug)
	if err == sql.ErrNoRows {
		http.Error(w, "habit not found", 404)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_type_id, day_ms FROM activity_days WHERE habit_type_id = ? ORDER BY day_ms DESC",
			htID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		days := []ActivityDay{}
		for rows.Next() {
			var d ActivityDay
			rows.Scan(&d.ID, &d.HabitTypeID, &d.DayMs)
			days = append(days, d)
		}
		writeJSON(w, 200, days)

	case http.MethodPost:
		var d ActivityDay
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		d.HabitTypeID = htID
		res, err := db.Exec(
			"INSERT OR IGNORE INTO activity_days (habit_type_id, day_ms) VALUES (?, ?)",
			htID, d.DayMs,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		d.ID, _ = res.LastInsertId()
		if d.ID == 0 {
			db.QueryRow("SELECT id FROM activity_days WHERE habit_type_id=? AND day_ms=?", htID, d.DayMs).Scan(&d.ID)
		}
		writeJSON(w, 201, d)

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// DELETE /api/habits/:habit/days/:id
func handleHabitDayByID(w http.ResponseWriter, r *http.Request, slug, id string) {
	htID, err := habitTypeID(slug)
	if err == sql.ErrNoRows {
		http.Error(w, "habit not found", 404)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", 405)
		return
	}

	res, err := db.Exec("DELETE FROM activity_days WHERE id=? AND habit_type_id=?", id, htID)
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

func nowMs() int64 {
	return time.Now().UnixMilli()
}

func main() {
	initDB()

	http.HandleFunc("/api/habits", handleHabits)
	http.HandleFunc("/api/habits/", handleHabitRouter)

	http.Handle("/", http.FileServer(http.Dir("frontend")))

	fmt.Println("TakeCharge running on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
