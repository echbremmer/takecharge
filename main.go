package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"golang.org/x/crypto/bcrypt"
)

var db *sql.DB

type User struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

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

type WeekGoal struct {
	ID          int64   `json:"id"`
	HabitTypeID int64   `json:"habit_type_id"`
	WeekStartMs int64   `json:"week_start_ms"`
	Value       float64 `json:"value"`
}

type TodoItem struct {
	ID          int64  `json:"id"`
	HabitTypeID int64  `json:"habit_type_id"`
	Text        string `json:"text"`
	Checked     bool   `json:"checked"`
	WeekStartMs int64  `json:"week_start_ms"`
	CreatedMs   int64  `json:"created_ms"`
}

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "/data/takecharge.db?_journal_mode=WAL")
	if err != nil {
		log.Fatal(err)
	}

	// Core tables
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
			password_hash TEXT NOT NULL,
			created_ms    INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS auth_sessions (
			token      TEXT PRIMARY KEY,
			user_id    INTEGER NOT NULL REFERENCES users(id),
			expires_ms INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS habit_types (
			id   INTEGER PRIMARY KEY AUTOINCREMENT,
			slug TEXT NOT NULL UNIQUE,
			name TEXT NOT NULL
		);
		INSERT OR IGNORE INTO habit_types (id, slug, name) VALUES (1, 'fasting', 'Fasting');
		INSERT OR IGNORE INTO habit_types (id, slug, name) VALUES (2, 'be-active', 'Be Active');
		INSERT OR IGNORE INTO habit_types (id, slug, name) VALUES (3, 'things-to-do', 'Things to Do');

		CREATE TABLE IF NOT EXISTS sessions (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			start_ms      INTEGER NOT NULL,
			end_ms        INTEGER NOT NULL,
			duration_ms   INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS activity_days (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			day_ms        INTEGER NOT NULL,
			UNIQUE(user_id, habit_type_id, day_ms)
		);

		CREATE TABLE IF NOT EXISTS week_goals (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			week_start_ms INTEGER NOT NULL,
			value         REAL NOT NULL,
			UNIQUE(user_id, habit_type_id, week_start_ms)
		);

		CREATE TABLE IF NOT EXISTS todo_items (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			text          TEXT NOT NULL,
			checked       INTEGER NOT NULL DEFAULT 0,
			week_start_ms INTEGER NOT NULL,
			created_ms    INTEGER NOT NULL
		);
	`)
	if err != nil {
		log.Fatal(err)
	}

	// Migration: add user_id to older table versions that lack it
	runMigrations()
}

func runMigrations() {
	hasCol := func(table, col string) bool {
		var name string
		db.QueryRow("SELECT name FROM pragma_table_info(?) WHERE name=?", table, col).Scan(&name)
		return name == col
	}

	// sessions: just add column if missing
	if !hasCol("sessions", "user_id") {
		db.Exec("ALTER TABLE sessions ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1")
	}

	// todo_items: just add column if missing
	if !hasCol("todo_items", "user_id") {
		db.Exec("ALTER TABLE todo_items ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1")
	}

	// activity_days: recreate with new UNIQUE constraint if user_id missing
	if !hasCol("activity_days", "user_id") {
		db.Exec(`CREATE TABLE activity_days_new (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			day_ms        INTEGER NOT NULL,
			UNIQUE(user_id, habit_type_id, day_ms)
		)`)
		db.Exec(`INSERT INTO activity_days_new (id, user_id, habit_type_id, day_ms)
			SELECT id, 1, habit_type_id, day_ms FROM activity_days`)
		db.Exec(`DROP TABLE activity_days`)
		db.Exec(`ALTER TABLE activity_days_new RENAME TO activity_days`)
	}

	// week_goals: recreate with new UNIQUE constraint if user_id missing
	if !hasCol("week_goals", "user_id") {
		db.Exec(`CREATE TABLE week_goals_new (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			week_start_ms INTEGER NOT NULL,
			value         REAL NOT NULL,
			UNIQUE(user_id, habit_type_id, week_start_ms)
		)`)
		db.Exec(`INSERT INTO week_goals_new (id, user_id, habit_type_id, week_start_ms, value)
			SELECT id, 1, habit_type_id, week_start_ms, value FROM week_goals`)
		db.Exec(`DROP TABLE week_goals`)
		db.Exec(`ALTER TABLE week_goals_new RENAME TO week_goals`)
	}

	// active_sessions: recreate with composite PK if user_id missing
	if !hasCol("active_sessions", "user_id") {
		db.Exec(`CREATE TABLE IF NOT EXISTS active_sessions (
			user_id       INTEGER NOT NULL DEFAULT 1,
			habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
			start_ms      INTEGER NOT NULL,
			PRIMARY KEY (user_id, habit_type_id)
		)`)
		// If old single-column PK table exists, migrate it
		var oldTable string
		db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='active_sessions_old'").Scan(&oldTable)
		if oldTable == "" {
			// rename old to old, create new, migrate
			db.Exec(`ALTER TABLE active_sessions RENAME TO active_sessions_old`)
			db.Exec(`CREATE TABLE active_sessions (
				user_id       INTEGER NOT NULL DEFAULT 1,
				habit_type_id INTEGER NOT NULL REFERENCES habit_types(id),
				start_ms      INTEGER NOT NULL,
				PRIMARY KEY (user_id, habit_type_id)
			)`)
			db.Exec(`INSERT OR IGNORE INTO active_sessions (user_id, habit_type_id, start_ms)
				SELECT 1, habit_type_id, start_ms FROM active_sessions_old`)
			db.Exec(`DROP TABLE active_sessions_old`)
		}
	}
}

// --- Auth helpers ---

func generateToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func getUserID(r *http.Request) (int64, bool) {
	cookie, err := r.Cookie("session")
	if err != nil {
		return 0, false
	}
	var userID, expiresMs int64
	err = db.QueryRow(
		"SELECT user_id, expires_ms FROM auth_sessions WHERE token = ?",
		cookie.Value,
	).Scan(&userID, &expiresMs)
	if err != nil {
		return 0, false
	}
	if nowMs() > expiresMs {
		db.Exec("DELETE FROM auth_sessions WHERE token = ?", cookie.Value)
		return 0, false
	}
	return userID, true
}

// --- Auth handlers ---

func handleAuthRouter(w http.ResponseWriter, r *http.Request) {
	action := strings.TrimPrefix(r.URL.Path, "/api/auth/")
	switch action {
	case "signup":
		handleAuthSignup(w, r)
	case "login":
		handleAuthLogin(w, r)
	case "logout":
		handleAuthLogout(w, r)
	case "me":
		handleAuthMe(w, r)
	default:
		http.Error(w, "not found", 404)
	}
}

func handleAuthSignup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid json", 400)
		return
	}
	body.Username = strings.TrimSpace(body.Username)
	if body.Username == "" || body.Password == "" {
		http.Error(w, "username and password required", 400)
		return
	}
	if len(body.Password) < 6 {
		http.Error(w, "password must be at least 6 characters", 400)
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, "internal error", 500)
		return
	}
	res, err := db.Exec(
		"INSERT INTO users (username, password_hash, created_ms) VALUES (?, ?, ?)",
		body.Username, string(hash), nowMs(),
	)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			http.Error(w, "username already taken", 409)
			return
		}
		http.Error(w, err.Error(), 500)
		return
	}
	userID, _ := res.LastInsertId()
	token := generateToken()
	expires := nowMs() + 30*24*60*60*1000
	db.Exec("INSERT INTO auth_sessions (token, user_id, expires_ms) VALUES (?, ?, ?)", token, userID, expires)
	http.SetCookie(w, &http.Cookie{
		Name:     "session",
		Value:    token,
		Path:     "/",
		MaxAge:   30 * 24 * 60 * 60,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	writeJSON(w, 201, User{ID: userID, Username: body.Username})
}

func handleAuthLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid json", 400)
		return
	}
	var userID int64
	var hash string
	err := db.QueryRow(
		"SELECT id, password_hash FROM users WHERE username = ? COLLATE NOCASE",
		body.Username,
	).Scan(&userID, &hash)
	if err == sql.ErrNoRows {
		http.Error(w, "invalid username or password", 401)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(body.Password)) != nil {
		http.Error(w, "invalid username or password", 401)
		return
	}
	token := generateToken()
	expires := nowMs() + 30*24*60*60*1000
	db.Exec("INSERT INTO auth_sessions (token, user_id, expires_ms) VALUES (?, ?, ?)", token, userID, expires)
	http.SetCookie(w, &http.Cookie{
		Name:     "session",
		Value:    token,
		Path:     "/",
		MaxAge:   30 * 24 * 60 * 60,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	writeJSON(w, 200, User{ID: userID, Username: body.Username})
}

func handleAuthLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}
	if cookie, err := r.Cookie("session"); err == nil {
		db.Exec("DELETE FROM auth_sessions WHERE token = ?", cookie.Value)
	}
	http.SetCookie(w, &http.Cookie{
		Name:   "session",
		Value:  "",
		Path:   "/",
		MaxAge: -1,
	})
	w.WriteHeader(204)
}

func handleAuthMe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	var username string
	db.QueryRow("SELECT username FROM users WHERE id = ?", userID).Scan(&username)
	writeJSON(w, 200, User{ID: userID, Username: username})
}

// --- Utility ---

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
	if _, ok := getUserID(r); !ok {
		http.Error(w, "unauthorized", 401)
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

// /api/habits/:habit/...
func handleHabitRouter(w http.ResponseWriter, r *http.Request) {
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}

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
			handleHabitSessions(w, r, slug, userID)
		} else {
			handleHabitSessionByID(w, r, slug, id, userID)
		}
	case "active":
		handleHabitActive(w, r, slug, userID)
	case "days":
		if id == "" {
			handleHabitDays(w, r, slug, userID)
		} else {
			handleHabitDayByID(w, r, slug, id, userID)
		}
	case "goals":
		handleHabitGoals(w, r, slug, userID)
	case "todos":
		if id == "" {
			handleHabitTodos(w, r, slug, userID)
		} else {
			handleHabitTodoByID(w, r, slug, id, userID)
		}
	default:
		http.Error(w, "not found", 404)
	}
}

// GET, POST /api/habits/:habit/sessions
func handleHabitSessions(w http.ResponseWriter, r *http.Request, slug string, userID int64) {
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
			"SELECT id, habit_type_id, start_ms, end_ms, duration_ms FROM sessions WHERE habit_type_id = ? AND user_id = ? ORDER BY start_ms DESC",
			htID, userID,
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
			"INSERT INTO sessions (user_id, habit_type_id, start_ms, end_ms, duration_ms) VALUES (?, ?, ?, ?, ?)",
			userID, s.HabitTypeID, s.StartMs, s.EndMs, s.Duration,
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
func handleHabitSessionByID(w http.ResponseWriter, r *http.Request, slug, id string, userID int64) {
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
			"UPDATE sessions SET start_ms=?, end_ms=?, duration_ms=? WHERE id=? AND habit_type_id=? AND user_id=?",
			s.StartMs, s.EndMs, s.Duration, id, htID, userID,
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
		res, err := db.Exec("DELETE FROM sessions WHERE id=? AND habit_type_id=? AND user_id=?", id, htID, userID)
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
func handleHabitActive(w http.ResponseWriter, r *http.Request, slug string, userID int64) {
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
		err := db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_type_id = ? AND user_id = ?", htID, userID).Scan(&startMs)
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
			"INSERT OR REPLACE INTO active_sessions (user_id, habit_type_id, start_ms) VALUES (?, ?, ?)",
			userID, htID, a.StartMs,
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
			"UPDATE active_sessions SET start_ms=? WHERE habit_type_id=? AND user_id=?",
			a.StartMs, htID, userID,
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
		err := db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_type_id = ? AND user_id = ?", htID, userID).Scan(&startMs)
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
			"INSERT INTO sessions (user_id, habit_type_id, start_ms, end_ms, duration_ms) VALUES (?, ?, ?, ?, ?)",
			userID, htID, startMs, endMs, duration,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		db.Exec("DELETE FROM active_sessions WHERE habit_type_id = ? AND user_id = ?", htID, userID)
		writeJSON(w, 200, Session{HabitTypeID: htID, StartMs: startMs, EndMs: endMs, Duration: duration})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET, POST /api/habits/:habit/days
func handleHabitDays(w http.ResponseWriter, r *http.Request, slug string, userID int64) {
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
			"SELECT id, habit_type_id, day_ms FROM activity_days WHERE habit_type_id = ? AND user_id = ? ORDER BY day_ms DESC",
			htID, userID,
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
			"INSERT OR IGNORE INTO activity_days (user_id, habit_type_id, day_ms) VALUES (?, ?, ?)",
			userID, htID, d.DayMs,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		d.ID, _ = res.LastInsertId()
		if d.ID == 0 {
			db.QueryRow("SELECT id FROM activity_days WHERE user_id=? AND habit_type_id=? AND day_ms=?", userID, htID, d.DayMs).Scan(&d.ID)
		}
		writeJSON(w, 201, d)

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// DELETE /api/habits/:habit/days/:id
func handleHabitDayByID(w http.ResponseWriter, r *http.Request, slug, id string, userID int64) {
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
	res, err := db.Exec("DELETE FROM activity_days WHERE id=? AND habit_type_id=? AND user_id=?", id, htID, userID)
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

// GET, POST /api/habits/:habit/goals
func handleHabitGoals(w http.ResponseWriter, r *http.Request, slug string, userID int64) {
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
			"SELECT id, habit_type_id, week_start_ms, value FROM week_goals WHERE habit_type_id = ? AND user_id = ? ORDER BY week_start_ms DESC",
			htID, userID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		goals := []WeekGoal{}
		for rows.Next() {
			var g WeekGoal
			rows.Scan(&g.ID, &g.HabitTypeID, &g.WeekStartMs, &g.Value)
			goals = append(goals, g)
		}
		writeJSON(w, 200, goals)

	case http.MethodPost:
		var g WeekGoal
		if err := json.NewDecoder(r.Body).Decode(&g); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		g.HabitTypeID = htID
		res, err := db.Exec(
			"INSERT OR REPLACE INTO week_goals (user_id, habit_type_id, week_start_ms, value) VALUES (?, ?, ?, ?)",
			userID, htID, g.WeekStartMs, g.Value,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		g.ID, _ = res.LastInsertId()
		writeJSON(w, 201, g)

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET, POST /api/habits/:habit/todos
func handleHabitTodos(w http.ResponseWriter, r *http.Request, slug string, userID int64) {
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
			"SELECT id, habit_type_id, text, checked, week_start_ms, created_ms FROM todo_items WHERE habit_type_id = ? AND user_id = ? ORDER BY created_ms ASC",
			htID, userID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		items := []TodoItem{}
		for rows.Next() {
			var t TodoItem
			var checked int
			rows.Scan(&t.ID, &t.HabitTypeID, &t.Text, &checked, &t.WeekStartMs, &t.CreatedMs)
			t.Checked = checked == 1
			items = append(items, t)
		}
		writeJSON(w, 200, items)

	case http.MethodPost:
		var t TodoItem
		if err := json.NewDecoder(r.Body).Decode(&t); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		t.HabitTypeID = htID
		t.CreatedMs = nowMs()
		res, err := db.Exec(
			"INSERT INTO todo_items (user_id, habit_type_id, text, checked, week_start_ms, created_ms) VALUES (?, ?, ?, 0, ?, ?)",
			userID, htID, t.Text, t.WeekStartMs, t.CreatedMs,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		t.ID, _ = res.LastInsertId()
		t.Checked = false
		writeJSON(w, 201, t)

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// PUT, DELETE /api/habits/:habit/todos/:id
func handleHabitTodoByID(w http.ResponseWriter, r *http.Request, slug, id string, userID int64) {
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
		var body struct {
			Checked bool `json:"checked"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		checked := 0
		if body.Checked {
			checked = 1
		}
		res, err := db.Exec(
			"UPDATE todo_items SET checked=? WHERE id=? AND habit_type_id=? AND user_id=?",
			checked, id, htID, userID,
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
		var t TodoItem
		var chk int
		db.QueryRow(
			"SELECT id, habit_type_id, text, checked, week_start_ms, created_ms FROM todo_items WHERE id=?", id,
		).Scan(&t.ID, &t.HabitTypeID, &t.Text, &chk, &t.WeekStartMs, &t.CreatedMs)
		t.Checked = chk == 1
		writeJSON(w, 200, t)

	case http.MethodDelete:
		res, err := db.Exec("DELETE FROM todo_items WHERE id=? AND habit_type_id=? AND user_id=?", id, htID, userID)
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

func nowMs() int64 {
	return time.Now().UnixMilli()
}

func main() {
	initDB()

	http.HandleFunc("/api/auth/", handleAuthRouter)
	http.HandleFunc("/api/habits", handleHabits)
	http.HandleFunc("/api/habits/", handleHabitRouter)

	http.Handle("/", http.FileServer(http.Dir("frontend")))

	fmt.Println("TakeCharge running on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
