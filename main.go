package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
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

type HabitStyle struct {
	ID   int64  `json:"id"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type Habit struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	StyleID   int64  `json:"style_id"`
	StyleSlug string `json:"style_slug"`
	Position  int    `json:"position"`
	CreatedMs int64  `json:"created_ms"`
}

type Session struct {
	ID       int64 `json:"id"`
	HabitID  int64 `json:"habit_id"`
	StartMs  int64 `json:"start"`
	EndMs    int64 `json:"end"`
	Duration int64 `json:"duration"`
}

type ActiveSession struct {
	HabitID int64 `json:"habit_id"`
	StartMs int64 `json:"start"`
}

type ActivityDay struct {
	ID      int64 `json:"id"`
	HabitID int64 `json:"habit_id"`
	DayMs   int64 `json:"day_ms"`
}

type WeekGoal struct {
	ID          int64   `json:"id"`
	HabitID     int64   `json:"habit_id"`
	WeekStartMs int64   `json:"week_start_ms"`
	Value       float64 `json:"value"`
}

type TodoItem struct {
	ID          int64  `json:"id"`
	HabitID     int64  `json:"habit_id"`
	Text        string `json:"text"`
	Checked     bool   `json:"checked"`
	WeekStartMs int64  `json:"week_start_ms"`
	CreatedMs   int64  `json:"created_ms"`
}

type DailyTarget struct {
	ID          int64   `json:"id"`
	HabitID     int64   `json:"habit_id"`
	Name        string  `json:"name"`
	Unit        string  `json:"unit"`
	TargetValue float64 `json:"target_value"`
	Step        float64 `json:"step"`
	Position    int     `json:"position"`
}

type DailyLog struct {
	ID       int64   `json:"id"`
	TargetID int64   `json:"target_id"`
	DayMs    int64   `json:"day_ms"`
	Value    float64 `json:"value"`
}

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "/data/takecharge.db?_journal_mode=WAL")
	if err != nil {
		log.Fatal(err)
	}

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

		CREATE TABLE IF NOT EXISTS habit_styles (
			id   INTEGER PRIMARY KEY,
			slug TEXT NOT NULL UNIQUE,
			name TEXT NOT NULL
		);
		INSERT OR IGNORE INTO habit_styles VALUES (1, 'timer', 'Timer');
		INSERT OR IGNORE INTO habit_styles VALUES (2, 'daily', 'Daily');
		INSERT OR IGNORE INTO habit_styles VALUES (3, 'todo', 'Todo');

		CREATE TABLE IF NOT EXISTS habits (
			id         INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id    INTEGER NOT NULL REFERENCES users(id),
			name       TEXT NOT NULL,
			style_id   INTEGER NOT NULL REFERENCES habit_styles(id),
			position   INTEGER NOT NULL DEFAULT 0,
			created_ms INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS sessions (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_id    INTEGER NOT NULL REFERENCES habits(id),
			start_ms    INTEGER NOT NULL,
			end_ms      INTEGER NOT NULL,
			duration_ms INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS active_sessions (
			habit_id INTEGER PRIMARY KEY REFERENCES habits(id),
			start_ms INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS activity_days (
			id       INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_id INTEGER NOT NULL REFERENCES habits(id),
			day_ms   INTEGER NOT NULL,
			UNIQUE(habit_id, day_ms)
		);

		CREATE TABLE IF NOT EXISTS week_goals (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_id      INTEGER NOT NULL REFERENCES habits(id),
			week_start_ms INTEGER NOT NULL,
			value         REAL NOT NULL,
			UNIQUE(habit_id, week_start_ms)
		);

		CREATE TABLE IF NOT EXISTS todo_items (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_id      INTEGER NOT NULL REFERENCES habits(id),
			text          TEXT NOT NULL,
			checked       INTEGER NOT NULL DEFAULT 0,
			week_start_ms INTEGER NOT NULL,
			created_ms    INTEGER NOT NULL
		);

		CREATE TABLE IF NOT EXISTS daily_targets (
			id           INTEGER PRIMARY KEY AUTOINCREMENT,
			habit_id     INTEGER NOT NULL REFERENCES habits(id),
			name         TEXT NOT NULL,
			unit         TEXT NOT NULL DEFAULT '',
			target_value REAL NOT NULL DEFAULT 1,
			step         REAL NOT NULL DEFAULT 1,
			position     INTEGER NOT NULL DEFAULT 0
		);

		CREATE TABLE IF NOT EXISTS daily_logs (
			id        INTEGER PRIMARY KEY AUTOINCREMENT,
			target_id INTEGER NOT NULL REFERENCES daily_targets(id),
			day_ms    INTEGER NOT NULL,
			value     REAL NOT NULL DEFAULT 0,
			UNIQUE(target_id, day_ms)
		);
	`)
	if err != nil {
		log.Fatal(err)
	}

	// Migrations — ignore errors if column already exists
	db.Exec("ALTER TABLE users ADD COLUMN profile_image BLOB")
	db.Exec("ALTER TABLE users ADD COLUMN profile_image_type TEXT")
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

func createDefaultHabits(userID int64) {
	now := nowMs()
	db.Exec("INSERT INTO habits (user_id, name, style_id, position, created_ms) VALUES (?, 'Fasting', 1, 0, ?)", userID, now)
	db.Exec("INSERT INTO habits (user_id, name, style_id, position, created_ms) VALUES (?, 'Be Active', 2, 1, ?)", userID, now)
	db.Exec("INSERT INTO habits (user_id, name, style_id, position, created_ms) VALUES (?, 'Things to Do', 3, 2, ?)", userID, now)
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
	createDefaultHabits(userID)
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

// --- Habit management ---

// GET /api/habits, POST /api/habits
func handleHabits(w http.ResponseWriter, r *http.Request) {
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(`
			SELECT h.id, h.name, h.style_id, hs.slug, h.position, h.created_ms
			FROM habits h
			JOIN habit_styles hs ON hs.id = h.style_id
			WHERE h.user_id = ?
			ORDER BY h.position, h.id`, userID)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		habits := []Habit{}
		for rows.Next() {
			var h Habit
			rows.Scan(&h.ID, &h.Name, &h.StyleID, &h.StyleSlug, &h.Position, &h.CreatedMs)
			habits = append(habits, h)
		}
		writeJSON(w, 200, habits)

	case http.MethodPost:
		var body struct {
			Name    string `json:"name"`
			StyleID int64  `json:"style_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		body.Name = strings.TrimSpace(body.Name)
		if body.Name == "" || body.StyleID == 0 {
			http.Error(w, "name and style_id required", 400)
			return
		}
		var styleSlug string
		err := db.QueryRow("SELECT slug FROM habit_styles WHERE id = ?", body.StyleID).Scan(&styleSlug)
		if err == sql.ErrNoRows {
			http.Error(w, "invalid style_id", 400)
			return
		}
		var maxPos int
		db.QueryRow("SELECT COALESCE(MAX(position), -1) FROM habits WHERE user_id = ?", userID).Scan(&maxPos)
		now := nowMs()
		res, err := db.Exec(
			"INSERT INTO habits (user_id, name, style_id, position, created_ms) VALUES (?, ?, ?, ?, ?)",
			userID, body.Name, body.StyleID, maxPos+1, now,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		id, _ := res.LastInsertId()
		writeJSON(w, 201, Habit{
			ID: id, Name: body.Name, StyleID: body.StyleID,
			StyleSlug: styleSlug, Position: maxPos + 1, CreatedMs: now,
		})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET /api/habits/styles
func handleHabitStyles(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}
	rows, err := db.Query("SELECT id, slug, name FROM habit_styles ORDER BY id")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	styles := []HabitStyle{}
	for rows.Next() {
		var s HabitStyle
		rows.Scan(&s.ID, &s.Slug, &s.Name)
		styles = append(styles, s)
	}
	writeJSON(w, 200, styles)
}

// DELETE /api/habits/:id (via handleHabitRouter)
func handleHabitDelete(w http.ResponseWriter, r *http.Request, habitID int64, userID int64) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", 405)
		return
	}
	var exists int
	db.QueryRow("SELECT 1 FROM habits WHERE id=? AND user_id=?", habitID, userID).Scan(&exists)
	if exists == 0 {
		http.Error(w, "not found", 404)
		return
	}
	db.Exec("DELETE FROM sessions WHERE habit_id=?", habitID)
	db.Exec("DELETE FROM active_sessions WHERE habit_id=?", habitID)
	db.Exec("DELETE FROM activity_days WHERE habit_id=?", habitID)
	db.Exec("DELETE FROM week_goals WHERE habit_id=?", habitID)
	db.Exec("DELETE FROM todo_items WHERE habit_id=?", habitID)
	db.Exec("DELETE FROM daily_logs WHERE target_id IN (SELECT id FROM daily_targets WHERE habit_id=?)", habitID)
	db.Exec("DELETE FROM daily_targets WHERE habit_id=?", habitID)
	db.Exec("DELETE FROM habits WHERE id=?", habitID)
	w.WriteHeader(204)
}

// /api/habits/:id/...
func handleHabitRouter(w http.ResponseWriter, r *http.Request) {
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}

	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/habits/"), "/")

	if parts[0] == "styles" {
		handleHabitStyles(w, r)
		return
	}

	habitID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		http.Error(w, "not found", 404)
		return
	}

	if len(parts) == 1 {
		handleHabitDelete(w, r, habitID, userID)
		return
	}

	var exists int
	db.QueryRow("SELECT 1 FROM habits WHERE id=? AND user_id=?", habitID, userID).Scan(&exists)
	if exists == 0 {
		http.Error(w, "habit not found", 404)
		return
	}

	resource := parts[1]
	subID := ""
	if len(parts) > 2 {
		subID = parts[2]
	}

	switch resource {
	case "sessions":
		if subID == "" {
			handleHabitSessions(w, r, habitID)
		} else {
			handleHabitSessionByID(w, r, habitID, subID)
		}
	case "active":
		handleHabitActive(w, r, habitID)
	case "days":
		if subID == "" {
			handleHabitDays(w, r, habitID)
		} else {
			handleHabitDayByID(w, r, habitID, subID)
		}
	case "goals":
		handleHabitGoals(w, r, habitID)
	case "todos":
		if subID == "" {
			handleHabitTodos(w, r, habitID)
		} else {
			handleHabitTodoByID(w, r, habitID, subID)
		}
	case "targets":
		if subID == "" {
			handleDailyTargets(w, r, habitID)
		} else {
			handleDailyTargetByID(w, r, habitID, subID)
		}
	case "logs":
		handleDailyLogs(w, r, habitID)
	default:
		http.Error(w, "not found", 404)
	}
}

// GET, POST /api/habits/:id/sessions
func handleHabitSessions(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_id, start_ms, end_ms, duration_ms FROM sessions WHERE habit_id = ? ORDER BY start_ms DESC",
			habitID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		sessions := []Session{}
		for rows.Next() {
			var s Session
			rows.Scan(&s.ID, &s.HabitID, &s.StartMs, &s.EndMs, &s.Duration)
			sessions = append(sessions, s)
		}
		writeJSON(w, 200, sessions)

	case http.MethodPost:
		var s Session
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		s.HabitID = habitID
		s.Duration = s.EndMs - s.StartMs
		res, err := db.Exec(
			"INSERT INTO sessions (habit_id, start_ms, end_ms, duration_ms) VALUES (?, ?, ?, ?)",
			habitID, s.StartMs, s.EndMs, s.Duration,
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

// PUT, DELETE /api/habits/:id/sessions/:sid
func handleHabitSessionByID(w http.ResponseWriter, r *http.Request, habitID int64, id string) {
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
			"UPDATE sessions SET start_ms=?, end_ms=?, duration_ms=? WHERE id=? AND habit_id=?",
			s.StartMs, s.EndMs, s.Duration, id, habitID,
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
		s.HabitID = habitID
		writeJSON(w, 200, s)

	case http.MethodDelete:
		res, err := db.Exec("DELETE FROM sessions WHERE id=? AND habit_id=?", id, habitID)
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

// GET, POST, PUT, DELETE /api/habits/:id/active
func handleHabitActive(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		var startMs int64
		err := db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_id = ?", habitID).Scan(&startMs)
		if err == sql.ErrNoRows {
			http.Error(w, "no active session", 404)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, 200, ActiveSession{HabitID: habitID, StartMs: startMs})

	case http.MethodPost:
		var a ActiveSession
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		_, err := db.Exec(
			"INSERT OR REPLACE INTO active_sessions (habit_id, start_ms) VALUES (?, ?)",
			habitID, a.StartMs,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		a.HabitID = habitID
		writeJSON(w, 201, a)

	case http.MethodPut:
		var a ActiveSession
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		res, err := db.Exec(
			"UPDATE active_sessions SET start_ms=? WHERE habit_id=?",
			a.StartMs, habitID,
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
		a.HabitID = habitID
		writeJSON(w, 200, a)

	case http.MethodDelete:
		var startMs int64
		err := db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_id = ?", habitID).Scan(&startMs)
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
			"INSERT INTO sessions (habit_id, start_ms, end_ms, duration_ms) VALUES (?, ?, ?, ?)",
			habitID, startMs, endMs, duration,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		db.Exec("DELETE FROM active_sessions WHERE habit_id = ?", habitID)
		writeJSON(w, 200, Session{HabitID: habitID, StartMs: startMs, EndMs: endMs, Duration: duration})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET, POST /api/habits/:id/days
func handleHabitDays(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_id, day_ms FROM activity_days WHERE habit_id = ? ORDER BY day_ms DESC",
			habitID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		days := []ActivityDay{}
		for rows.Next() {
			var d ActivityDay
			rows.Scan(&d.ID, &d.HabitID, &d.DayMs)
			days = append(days, d)
		}
		writeJSON(w, 200, days)

	case http.MethodPost:
		var d ActivityDay
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		d.HabitID = habitID
		res, err := db.Exec(
			"INSERT OR IGNORE INTO activity_days (habit_id, day_ms) VALUES (?, ?)",
			habitID, d.DayMs,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		d.ID, _ = res.LastInsertId()
		if d.ID == 0 {
			db.QueryRow("SELECT id FROM activity_days WHERE habit_id=? AND day_ms=?", habitID, d.DayMs).Scan(&d.ID)
		}
		writeJSON(w, 201, d)

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// DELETE /api/habits/:id/days/:did
func handleHabitDayByID(w http.ResponseWriter, r *http.Request, habitID int64, id string) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", 405)
		return
	}
	res, err := db.Exec("DELETE FROM activity_days WHERE id=? AND habit_id=?", id, habitID)
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

// GET, POST /api/habits/:id/goals
func handleHabitGoals(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_id, week_start_ms, value FROM week_goals WHERE habit_id = ? ORDER BY week_start_ms DESC",
			habitID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		goals := []WeekGoal{}
		for rows.Next() {
			var g WeekGoal
			rows.Scan(&g.ID, &g.HabitID, &g.WeekStartMs, &g.Value)
			goals = append(goals, g)
		}
		writeJSON(w, 200, goals)

	case http.MethodPost:
		var g WeekGoal
		if err := json.NewDecoder(r.Body).Decode(&g); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		g.HabitID = habitID
		res, err := db.Exec(
			"INSERT OR REPLACE INTO week_goals (habit_id, week_start_ms, value) VALUES (?, ?, ?)",
			habitID, g.WeekStartMs, g.Value,
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

// GET, POST /api/habits/:id/todos
func handleHabitTodos(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_id, text, checked, week_start_ms, created_ms FROM todo_items WHERE habit_id = ? ORDER BY created_ms ASC",
			habitID,
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
			rows.Scan(&t.ID, &t.HabitID, &t.Text, &checked, &t.WeekStartMs, &t.CreatedMs)
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
		t.HabitID = habitID
		t.CreatedMs = nowMs()
		res, err := db.Exec(
			"INSERT INTO todo_items (habit_id, text, checked, week_start_ms, created_ms) VALUES (?, ?, 0, ?, ?)",
			habitID, t.Text, t.WeekStartMs, t.CreatedMs,
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

// PUT, DELETE /api/habits/:id/todos/:tid
func handleHabitTodoByID(w http.ResponseWriter, r *http.Request, habitID int64, id string) {
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
			"UPDATE todo_items SET checked=? WHERE id=? AND habit_id=?",
			checked, id, habitID,
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
			"SELECT id, habit_id, text, checked, week_start_ms, created_ms FROM todo_items WHERE id=?", id,
		).Scan(&t.ID, &t.HabitID, &t.Text, &chk, &t.WeekStartMs, &t.CreatedMs)
		t.Checked = chk == 1
		writeJSON(w, 200, t)

	case http.MethodDelete:
		res, err := db.Exec("DELETE FROM todo_items WHERE id=? AND habit_id=?", id, habitID)
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

// GET, POST /api/habits/:id/targets
func handleDailyTargets(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query(
			"SELECT id, habit_id, name, unit, target_value, step, position FROM daily_targets WHERE habit_id=? ORDER BY position, id",
			habitID,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		targets := []DailyTarget{}
		for rows.Next() {
			var t DailyTarget
			rows.Scan(&t.ID, &t.HabitID, &t.Name, &t.Unit, &t.TargetValue, &t.Step, &t.Position)
			targets = append(targets, t)
		}
		writeJSON(w, 200, targets)

	case http.MethodPost:
		var body struct {
			Name        string  `json:"name"`
			Unit        string  `json:"unit"`
			TargetValue float64 `json:"target_value"`
			Step        float64 `json:"step"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		body.Name = strings.TrimSpace(body.Name)
		if body.Name == "" || body.TargetValue <= 0 || body.Step <= 0 {
			http.Error(w, "name, target_value and step are required and must be > 0", 400)
			return
		}
		var maxPos int
		db.QueryRow("SELECT COALESCE(MAX(position), -1) FROM daily_targets WHERE habit_id=?", habitID).Scan(&maxPos)
		res, err := db.Exec(
			"INSERT INTO daily_targets (habit_id, name, unit, target_value, step, position) VALUES (?, ?, ?, ?, ?, ?)",
			habitID, body.Name, body.Unit, body.TargetValue, body.Step, maxPos+1,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		id, _ := res.LastInsertId()
		writeJSON(w, 201, DailyTarget{
			ID: id, HabitID: habitID, Name: body.Name, Unit: body.Unit,
			TargetValue: body.TargetValue, Step: body.Step, Position: maxPos + 1,
		})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// DELETE /api/habits/:id/targets/:tid
func handleDailyTargetByID(w http.ResponseWriter, r *http.Request, habitID int64, id string) {
	switch r.Method {
	case http.MethodPut:
		var body struct {
			Name        string  `json:"name"`
			Unit        string  `json:"unit"`
			TargetValue float64 `json:"target_value"`
			Step        float64 `json:"step"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		body.Name = strings.TrimSpace(body.Name)
		if body.Name == "" || body.TargetValue <= 0 || body.Step <= 0 {
			http.Error(w, "name, target_value and step are required and must be > 0", 400)
			return
		}
		res, err := db.Exec(
			"UPDATE daily_targets SET name=?, unit=?, target_value=?, step=? WHERE id=? AND habit_id=?",
			body.Name, body.Unit, body.TargetValue, body.Step, id, habitID,
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
		idInt, _ := strconv.ParseInt(id, 10, 64)
		var pos int
		db.QueryRow("SELECT position FROM daily_targets WHERE id=?", id).Scan(&pos)
		writeJSON(w, 200, DailyTarget{
			ID: idInt, HabitID: habitID, Name: body.Name, Unit: body.Unit,
			TargetValue: body.TargetValue, Step: body.Step, Position: pos,
		})

	case http.MethodDelete:
		db.Exec("DELETE FROM daily_logs WHERE target_id=?", id)
		res, err := db.Exec("DELETE FROM daily_targets WHERE id=? AND habit_id=?", id, habitID)
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

// GET, POST /api/habits/:id/logs
// GET supports optional ?day=<ms> query param to filter to one day
func handleDailyLogs(w http.ResponseWriter, r *http.Request, habitID int64) {
	switch r.Method {
	case http.MethodGet:
		day := r.URL.Query().Get("day")
		var rows *sql.Rows
		var err error
		if day != "" {
			rows, err = db.Query(
				`SELECT dl.id, dl.target_id, dl.day_ms, dl.value
				 FROM daily_logs dl
				 JOIN daily_targets dt ON dt.id = dl.target_id
				 WHERE dt.habit_id=? AND dl.day_ms=?`,
				habitID, day,
			)
		} else {
			rows, err = db.Query(
				`SELECT dl.id, dl.target_id, dl.day_ms, dl.value
				 FROM daily_logs dl
				 JOIN daily_targets dt ON dt.id = dl.target_id
				 WHERE dt.habit_id=?
				 ORDER BY dl.day_ms DESC`,
				habitID,
			)
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()
		logs := []DailyLog{}
		for rows.Next() {
			var l DailyLog
			rows.Scan(&l.ID, &l.TargetID, &l.DayMs, &l.Value)
			logs = append(logs, l)
		}
		writeJSON(w, 200, logs)

	case http.MethodPost:
		var body struct {
			TargetID int64   `json:"target_id"`
			DayMs    int64   `json:"day_ms"`
			Value    float64 `json:"value"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		// verify target belongs to this habit
		var exists int
		db.QueryRow("SELECT 1 FROM daily_targets WHERE id=? AND habit_id=?", body.TargetID, habitID).Scan(&exists)
		if exists == 0 {
			http.Error(w, "target not found", 404)
			return
		}
		res, err := db.Exec(
			"INSERT INTO daily_logs (target_id, day_ms, value) VALUES (?, ?, ?) ON CONFLICT(target_id, day_ms) DO UPDATE SET value=excluded.value",
			body.TargetID, body.DayMs, body.Value,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		id, _ := res.LastInsertId()
		if id == 0 {
			db.QueryRow("SELECT id FROM daily_logs WHERE target_id=? AND day_ms=?", body.TargetID, body.DayMs).Scan(&id)
		}
		writeJSON(w, 200, DailyLog{ID: id, TargetID: body.TargetID, DayMs: body.DayMs, Value: body.Value})

	default:
		http.Error(w, "method not allowed", 405)
	}
}

// GET /api/profile/image  — returns the stored image or 404
// POST /api/profile/image — accepts multipart "image" field, stores in DB
func handleProfileImage(w http.ResponseWriter, r *http.Request) {
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	switch r.Method {
	case http.MethodGet:
		var imgData []byte
		var imgType sql.NullString
		err := db.QueryRow("SELECT profile_image, profile_image_type FROM users WHERE id=?", userID).Scan(&imgData, &imgType)
		if err != nil || len(imgData) == 0 {
			http.Error(w, "not found", 404)
			return
		}
		ct := "image/jpeg"
		if imgType.Valid && imgType.String != "" {
			ct = imgType.String
		}
		w.Header().Set("Content-Type", ct)
		w.Write(imgData)

	case http.MethodPost:
		if err := r.ParseMultipartForm(5 << 20); err != nil {
			http.Error(w, "image too large (max 5 MB)", 400)
			return
		}
		file, header, err := r.FormFile("image")
		if err != nil {
			http.Error(w, "image field required", 400)
			return
		}
		defer file.Close()
		ct := header.Header.Get("Content-Type")
		if ct == "" {
			ct = "image/jpeg"
		}
		data, err := io.ReadAll(file)
		if err != nil {
			http.Error(w, "read error", 500)
			return
		}
		_, err = db.Exec("UPDATE users SET profile_image=?, profile_image_type=? WHERE id=?", data, ct, userID)
		if err != nil {
			http.Error(w, err.Error(), 500)
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
	http.HandleFunc("/api/profile/image", handleProfileImage)
	http.HandleFunc("/api/habits", handleHabits)
	http.HandleFunc("/api/habits/", handleHabitRouter)

	http.Handle("/", http.FileServer(http.Dir("frontend")))

	fmt.Println("TakeCharge running on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
