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
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	StyleID     int64  `json:"style_id"`
	StyleSlug   string `json:"style_slug"`
	VariantSlug string `json:"variant_slug"`
	Position    int    `json:"position"`
	CreatedMs   int64  `json:"created_ms"`
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
	Mode        string  `json:"mode"` // "target" or "limit"
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
			position     INTEGER NOT NULL DEFAULT 0,
			mode         TEXT NOT NULL DEFAULT 'target'
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
	db.Exec("ALTER TABLE daily_targets ADD COLUMN mode TEXT NOT NULL DEFAULT 'target'")
	db.Exec("ALTER TABLE habits ADD COLUMN variant_slug TEXT NOT NULL DEFAULT ''")
	db.Exec("UPDATE habits SET variant_slug = 'intermittent_fasting' WHERE name = 'Fasting' AND style_id = 1 AND variant_slug = ''")
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
	db.Exec("INSERT INTO habits (user_id, name, style_id, variant_slug, position, created_ms) VALUES (?, 'Fasting', 1, 'intermittent_fasting', 0, ?)", userID, now)
	db.Exec("INSERT INTO habits (user_id, name, style_id, variant_slug, position, created_ms) VALUES (?, 'Be Active', 2, '', 1, ?)", userID, now)
	db.Exec("INSERT INTO habits (user_id, name, style_id, variant_slug, position, created_ms) VALUES (?, 'Things to Do', 3, '', 2, ?)", userID, now)
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
	writeJSON(w, 201, struct {
		ID       int64  `json:"id"`
		Username string `json:"username"`
		Token    string `json:"token,omitempty"`
	}{ID: userID, Username: body.Username, Token: token})
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
	writeJSON(w, 200, struct {
		ID       int64  `json:"id"`
		Username string `json:"username"`
		Token    string `json:"token,omitempty"`
	}{ID: userID, Username: body.Username, Token: token})
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
			SELECT h.id, h.name, h.style_id, hs.slug, h.variant_slug, h.position, h.created_ms
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
			rows.Scan(&h.ID, &h.Name, &h.StyleID, &h.StyleSlug, &h.VariantSlug, &h.Position, &h.CreatedMs)
			habits = append(habits, h)
		}
		writeJSON(w, 200, habits)

	case http.MethodPost:
		var body struct {
			Name        string `json:"name"`
			StyleID     int64  `json:"style_id"`
			VariantSlug string `json:"variant_slug"`
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
			"INSERT INTO habits (user_id, name, style_id, variant_slug, position, created_ms) VALUES (?, ?, ?, ?, ?, ?)",
			userID, body.Name, body.StyleID, body.VariantSlug, maxPos+1, now,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		id, _ := res.LastInsertId()
		writeJSON(w, 201, Habit{
			ID: id, Name: body.Name, StyleID: body.StyleID,
			StyleSlug: styleSlug, VariantSlug: body.VariantSlug,
			Position: maxPos + 1, CreatedMs: now,
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

// PUT /api/habits/reorder
func handleHabitReorder(w http.ResponseWriter, r *http.Request, userID int64) {
	if r.Method != http.MethodPut {
		http.Error(w, "method not allowed", 405)
		return
	}
	var body struct {
		IDs []int64 `json:"ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid json", 400)
		return
	}
	tx, err := db.Begin()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	for i, id := range body.IDs {
		tx.Exec("UPDATE habits SET position=? WHERE id=? AND user_id=?", i, id, userID)
	}
	if err := tx.Commit(); err != nil {
		tx.Rollback()
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(204)
}

// GET /api/habits/:id/insight
func handleHabitInsight(w http.ResponseWriter, r *http.Request, habitID int64, userID int64) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}
	var variantSlug string
	err := db.QueryRow("SELECT variant_slug FROM habits WHERE id=? AND user_id=?", habitID, userID).Scan(&variantSlug)
	if err != nil {
		http.Error(w, "not found", 404)
		return
	}
	if variantSlug != "intermittent_fasting" {
		http.Error(w, "no insight for this habit type", 400)
		return
	}

	var startMs sql.NullInt64
	db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_id=?", habitID).Scan(&startMs)

	now := nowMs()
	isActive := startMs.Valid
	var elapsedMs int64
	if isActive {
		elapsedMs = now - startMs.Int64
	}

	const fatBurningThresholdMs = 12 * 3600 * 1000
	const kcalPerMs = 70.0 / 3600000.0

	fatBurning := isActive && elapsedMs >= fatBurningThresholdMs
	var fatBurningInMs int64
	var fatBurningStartsMs int64
	if isActive {
		fatBurningStartsMs = startMs.Int64 + fatBurningThresholdMs
		if !fatBurning {
			fatBurningInMs = fatBurningThresholdMs - elapsedMs
		}
	}

	kcalBurned := int64(float64(elapsedMs) * kcalPerMs)

	writeJSON(w, 200, map[string]interface{}{
		"is_active":             isActive,
		"elapsed_ms":            elapsedMs,
		"fat_burning":           fatBurning,
		"fat_burning_starts_ms": fatBurningStartsMs,
		"fat_burning_in_ms":     fatBurningInMs,
		"kcal_burned":           kcalBurned,
	})
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

	if parts[0] == "reorder" {
		handleHabitReorder(w, r, userID)
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
	case "insight":
		handleHabitInsight(w, r, habitID, userID)
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
			"SELECT id, habit_id, name, unit, target_value, step, position, mode FROM daily_targets WHERE habit_id=? ORDER BY position, id",
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
			rows.Scan(&t.ID, &t.HabitID, &t.Name, &t.Unit, &t.TargetValue, &t.Step, &t.Position, &t.Mode)
			targets = append(targets, t)
		}
		writeJSON(w, 200, targets)

	case http.MethodPost:
		var body struct {
			Name        string  `json:"name"`
			Unit        string  `json:"unit"`
			TargetValue float64 `json:"target_value"`
			Step        float64 `json:"step"`
			Mode        string  `json:"mode"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		body.Name = strings.TrimSpace(body.Name)
		if body.Mode != "limit" {
			body.Mode = "target"
		}
		if body.Name == "" || body.TargetValue <= 0 || body.Step <= 0 {
			http.Error(w, "name, target_value and step are required and must be > 0", 400)
			return
		}
		var count int
		db.QueryRow("SELECT COUNT(*) FROM daily_targets WHERE habit_id=?", habitID).Scan(&count)
		if count >= 4 {
			http.Error(w, "maximum of 4 targets per habit", 400)
			return
		}
		var maxPos int
		db.QueryRow("SELECT COALESCE(MAX(position), -1) FROM daily_targets WHERE habit_id=?", habitID).Scan(&maxPos)
		res, err := db.Exec(
			"INSERT INTO daily_targets (habit_id, name, unit, target_value, step, position, mode) VALUES (?, ?, ?, ?, ?, ?, ?)",
			habitID, body.Name, body.Unit, body.TargetValue, body.Step, maxPos+1, body.Mode,
		)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		id, _ := res.LastInsertId()
		writeJSON(w, 201, DailyTarget{
			ID: id, HabitID: habitID, Name: body.Name, Unit: body.Unit,
			TargetValue: body.TargetValue, Step: body.Step, Position: maxPos + 1, Mode: body.Mode,
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
			Mode        string  `json:"mode"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid json", 400)
			return
		}
		body.Name = strings.TrimSpace(body.Name)
		if body.Mode != "limit" {
			body.Mode = "target"
		}
		if body.Name == "" || body.TargetValue <= 0 || body.Step <= 0 {
			http.Error(w, "name, target_value and step are required and must be > 0", 400)
			return
		}
		res, err := db.Exec(
			"UPDATE daily_targets SET name=?, unit=?, target_value=?, step=?, mode=? WHERE id=? AND habit_id=?",
			body.Name, body.Unit, body.TargetValue, body.Step, body.Mode, id, habitID,
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
			TargetValue: body.TargetValue, Step: body.Step, Position: pos, Mode: body.Mode,
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

func weekMonday(t time.Time) time.Time {
	d := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
	offset := (int(d.Weekday()) + 6) % 7
	return d.AddDate(0, 0, -offset)
}

func ifPhase(elapsedMs int64) string {
	switch {
	case elapsedMs >= 24*3600*1000:
		return "Autophagy"
	case elapsedMs >= 18*3600*1000:
		return "Ketosis"
	case elapsedMs >= 12*3600*1000:
		return "Fat burning"
	default:
		return "Digesting"
	}
}

// GET /api/summary
func handleSummary(w http.ResponseWriter, r *http.Request) {
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", 405)
		return
	}

	rows, err := db.Query(`
		SELECT h.id, h.name, hs.slug, h.variant_slug
		FROM habits h
		JOIN habit_styles hs ON hs.id = h.style_id
		WHERE h.user_id = ?
		ORDER BY h.position, h.id`, userID)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()

	type habitInfo struct {
		ID          int64
		Name        string
		StyleSlug   string
		VariantSlug string
	}
	var habits []habitInfo
	for rows.Next() {
		var h habitInfo
		rows.Scan(&h.ID, &h.Name, &h.StyleSlug, &h.VariantSlug)
		habits = append(habits, h)
	}

	now := time.Now()
	todayMs := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC).UnixMilli()
	curMon := weekMonday(now)
	curWeekMs := curMon.UnixMilli()
	weekEndMs := curWeekMs + 7*24*3600*1000
	nowMillis := now.UnixMilli()

	// Last 6 week starts, oldest first
	weekStarts := make([]int64, 6)
	for i := 0; i < 6; i++ {
		weekStarts[5-i] = curMon.AddDate(0, 0, -i*7).UnixMilli()
	}

	type TodayStatus struct {
		IsActive     bool   `json:"is_active,omitempty"`
		ElapsedMs    int64  `json:"elapsed_ms,omitempty"`
		Phase        string `json:"phase,omitempty"`
		TargetsTotal int    `json:"targets_total,omitempty"`
		TargetsHit   int    `json:"targets_hit,omitempty"`
		WeekTotal    int    `json:"week_total,omitempty"`
		WeekChecked  int    `json:"week_checked,omitempty"`
	}
	type BarPoint struct {
		Ms    int64   `json:"ms"`
		Value float64 `json:"value"`
	}
	type HabitSummaryItem struct {
		ID          int64        `json:"id"`
		Name        string       `json:"name"`
		StyleSlug   string       `json:"style_slug"`
		VariantSlug string       `json:"variant_slug"`
		Today       TodayStatus  `json:"today"`
		WeekBars    []BarPoint   `json:"week_bars"`
		TrendBars   []BarPoint   `json:"trend_bars"`
	}

	var result []HabitSummaryItem

	for _, h := range habits {
		item := HabitSummaryItem{
			ID:          h.ID,
			Name:        h.Name,
			StyleSlug:   h.StyleSlug,
			VariantSlug: h.VariantSlug,
			WeekBars:    []BarPoint{},
			TrendBars:   []BarPoint{},
		}

		switch h.StyleSlug {
		case "timer":
			var startMs sql.NullInt64
			db.QueryRow("SELECT start_ms FROM active_sessions WHERE habit_id=?", h.ID).Scan(&startMs)
			if startMs.Valid {
				elapsed := nowMillis - startMs.Int64
				item.Today = TodayStatus{IsActive: true, ElapsedMs: elapsed, Phase: ifPhase(elapsed)}
			}

			// Week bars: sum duration per day Mon-Sun
			dayMap := map[int64]float64{}
			sRows, _ := db.Query(`SELECT (start_ms/86400000)*86400000, SUM(duration_ms)
				FROM sessions WHERE habit_id=? AND start_ms>=? AND start_ms<?
				GROUP BY 1`, h.ID, curWeekMs, weekEndMs)
			if sRows != nil {
				for sRows.Next() {
					var d int64
					var ms int64
					sRows.Scan(&d, &ms)
					dayMap[d] = float64(ms) / 3600000.0
				}
				sRows.Close()
			}
			for i := 0; i < 7; i++ {
				d := curWeekMs + int64(i)*86400000
				item.WeekBars = append(item.WeekBars, BarPoint{Ms: d, Value: dayMap[d]})
			}

			// Trend: total hours per week
			for _, ws := range weekStarts {
				var ms int64
				db.QueryRow(`SELECT COALESCE(SUM(duration_ms),0) FROM sessions WHERE habit_id=? AND start_ms>=? AND start_ms<?`,
					h.ID, ws, ws+7*24*3600*1000).Scan(&ms)
				item.TrendBars = append(item.TrendBars, BarPoint{Ms: ws, Value: float64(ms) / 3600000.0})
			}

		case "daily":
			type tgt struct {
				id  int64
				val float64
				mod string
			}
			var targets []tgt
			tRows, _ := db.Query("SELECT id, target_value, mode FROM daily_targets WHERE habit_id=?", h.ID)
			if tRows != nil {
				for tRows.Next() {
					var t tgt
					tRows.Scan(&t.id, &t.val, &t.mod)
					targets = append(targets, t)
				}
				tRows.Close()
			}

			// Today status
			hit := 0
			for _, t := range targets {
				var v float64
				db.QueryRow("SELECT COALESCE(value,0) FROM daily_logs WHERE target_id=? AND day_ms=?", t.id, todayMs).Scan(&v)
				if (t.mod == "limit" && v <= t.val) || (t.mod != "limit" && v >= t.val) {
					hit++
				}
			}
			item.Today = TodayStatus{TargetsTotal: len(targets), TargetsHit: hit}

			// Week bars: avg completion per day
			type dayAcc struct{ sum float64; n int }
			dayMap := map[int64]*dayAcc{}
			for _, t := range targets {
				lRows, _ := db.Query("SELECT day_ms, value FROM daily_logs WHERE target_id=? AND day_ms>=? AND day_ms<?",
					t.id, curWeekMs, weekEndMs)
				if lRows != nil {
					for lRows.Next() {
						var d int64
						var v float64
						lRows.Scan(&d, &v)
						c := v / t.val
						if c > 1 {
							c = 1
						}
						if dayMap[d] == nil {
							dayMap[d] = &dayAcc{}
						}
						dayMap[d].sum += c
						dayMap[d].n++
					}
					lRows.Close()
				}
			}
			for i := 0; i < 7; i++ {
				d := curWeekMs + int64(i)*86400000
				var v float64
				if a := dayMap[d]; a != nil && a.n > 0 {
					v = a.sum / float64(a.n)
				}
				item.WeekBars = append(item.WeekBars, BarPoint{Ms: d, Value: v})
			}

			// Trend: avg completion per week
			for _, ws := range weekStarts {
				var sum float64
				var cnt int
				for _, t := range targets {
					lRows, _ := db.Query("SELECT value FROM daily_logs WHERE target_id=? AND day_ms>=? AND day_ms<?",
						t.id, ws, ws+7*24*3600*1000)
					if lRows != nil {
						for lRows.Next() {
							var v float64
							lRows.Scan(&v)
							c := v / t.val
							if c > 1 {
								c = 1
							}
							sum += c
							cnt++
						}
						lRows.Close()
					}
				}
				var v float64
				if cnt > 0 {
					v = sum / float64(cnt)
				}
				item.TrendBars = append(item.TrendBars, BarPoint{Ms: ws, Value: v})
			}

		case "todo":
			var total, checked int
			db.QueryRow("SELECT COUNT(*), COALESCE(SUM(CASE WHEN checked THEN 1 ELSE 0 END),0) FROM todo_items WHERE habit_id=? AND week_start_ms=?",
				h.ID, curWeekMs).Scan(&total, &checked)
			item.Today = TodayStatus{WeekTotal: total, WeekChecked: checked}

			for _, ws := range weekStarts {
				var tot, chk int
				db.QueryRow("SELECT COUNT(*), COALESCE(SUM(CASE WHEN checked THEN 1 ELSE 0 END),0) FROM todo_items WHERE habit_id=? AND week_start_ms=?",
					h.ID, ws).Scan(&tot, &chk)
				var v float64
				if tot > 0 {
					v = float64(chk) / float64(tot)
				}
				item.TrendBars = append(item.TrendBars, BarPoint{Ms: ws, Value: v})
			}
		}

		result = append(result, item)
	}

	writeJSON(w, 200, map[string]interface{}{"habits": result})
}

// POST /api/dev/seed — inserts 6 weeks of test data for all habits
func handleDevSeed(w http.ResponseWriter, r *http.Request) {
	userID, ok := getUserID(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", 405)
		return
	}

	rows, _ := db.Query(`SELECT h.id, hs.slug FROM habits h JOIN habit_styles hs ON hs.id=h.style_id WHERE h.user_id=?`, userID)
	type hInfo struct {
		id   int64
		slug string
	}
	var habits []hInfo
	for rows.Next() {
		var h hInfo
		rows.Scan(&h.id, &h.slug)
		habits = append(habits, h)
	}
	rows.Close()

	now := time.Now()
	curMon := weekMonday(now)

	for _, h := range habits {
		switch h.slug {
		case "timer":
			// 6 weeks, 4-5 fasts/week, 14-19h each, starting at 20:00
			fastDaysPerWeek := [][]int{
				{0, 1, 3, 4, 6},
				{0, 2, 3, 5, 6},
				{1, 2, 4, 5},
				{0, 1, 3, 4, 6},
				{0, 2, 4, 5},
				{1, 3, 4, 5, 6},
			}
			durations := []int{16, 17, 14, 18, 15, 19, 16, 17, 14, 18}
			for week := 0; week < 6; week++ {
				mon := curMon.AddDate(0, 0, -week*7)
				for _, day := range fastDaysPerWeek[week] {
					d := mon.AddDate(0, 0, day)
					if d.After(now) {
						continue
					}
					startMs := time.Date(d.Year(), d.Month(), d.Day(), 20, 0, 0, 0, time.UTC).UnixMilli()
					durH := durations[(week*7+day)%len(durations)]
					endMs := startMs + int64(durH)*3600000
					if endMs > now.UnixMilli() {
						continue
					}
					db.Exec("INSERT OR IGNORE INTO sessions (habit_id, start_ms, end_ms, duration_ms) VALUES (?,?,?,?)",
						h.id, startMs, endMs, int64(durH)*3600000)
				}
			}

		case "daily":
			// Ensure 3 targets exist
			var tc int
			db.QueryRow("SELECT COUNT(*) FROM daily_targets WHERE habit_id=?", h.id).Scan(&tc)
			if tc == 0 {
				db.Exec("INSERT INTO daily_targets (habit_id,name,unit,target_value,step,position,mode) VALUES (?,?,?,?,?,?,?)",
					h.id, "Steps", "steps", 10000, 500, 0, "target")
				db.Exec("INSERT INTO daily_targets (habit_id,name,unit,target_value,step,position,mode) VALUES (?,?,?,?,?,?,?)",
					h.id, "Water", "glasses", 8, 1, 1, "target")
				db.Exec("INSERT INTO daily_targets (habit_id,name,unit,target_value,step,position,mode) VALUES (?,?,?,?,?,?,?)",
					h.id, "Exercise", "min", 30, 5, 2, "target")
			}
			type tInfo struct {
				id  int64
				val float64
			}
			var targets []tInfo
			tRows, _ := db.Query("SELECT id, target_value FROM daily_targets WHERE habit_id=?", h.id)
			for tRows.Next() {
				var t tInfo
				tRows.Scan(&t.id, &t.val)
				targets = append(targets, t)
			}
			tRows.Close()

			multipliers := []float64{1.0, 0.8, 0.9, 0.7, 1.0, 0.85, 0.95}
			for week := 0; week < 6; week++ {
				mon := curMon.AddDate(0, 0, -week*7)
				for day := 0; day < 7; day++ {
					d := mon.AddDate(0, 0, day)
					if d.After(now) {
						continue
					}
					if (day+week)%5 == 4 {
						continue // skip ~1 day/week
					}
					dayMs := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, time.UTC).UnixMilli()
					for ti, t := range targets {
						mul := multipliers[(day+week+ti)%len(multipliers)]
						db.Exec("INSERT OR IGNORE INTO daily_logs (target_id,day_ms,value) VALUES (?,?,?)",
							t.id, dayMs, t.val*mul)
					}
				}
			}

		case "todo":
			texts := []string{
				"Review weekly goals", "Clean workspace", "Call family",
				"Read 30 pages", "Meal prep Sunday", "Exercise 3x this week",
				"Journal entry",
			}
			checkedPatterns := []int{5, 6, 4, 7, 5, 3} // checked per week (out of 7)
			for week := 0; week < 6; week++ {
				mon := curMon.AddDate(0, 0, -week*7)
				ws := mon.UnixMilli()
				var cnt int
				db.QueryRow("SELECT COUNT(*) FROM todo_items WHERE habit_id=? AND week_start_ms=?", h.id, ws).Scan(&cnt)
				if cnt > 0 {
					continue
				}
				nChecked := checkedPatterns[week]
				if week == 0 {
					nChecked = 2 // current week in progress
				}
				for i, text := range texts {
					db.Exec("INSERT INTO todo_items (habit_id,text,checked,week_start_ms,created_ms) VALUES (?,?,?,?,?)",
						h.id, text, i < nChecked, ws, ws+int64(i)*3600000)
				}
			}
		}
	}

	w.WriteHeader(204)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if strings.Contains(origin, "localhost") {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	initDB()

	http.HandleFunc("/api/auth/", handleAuthRouter)
	http.HandleFunc("/api/profile/image", handleProfileImage)
	http.HandleFunc("/api/habits", handleHabits)
	http.HandleFunc("/api/habits/", handleHabitRouter)
	http.HandleFunc("/api/summary", handleSummary)
	http.HandleFunc("/api/dev/seed", handleDevSeed)

	http.Handle("/", http.FileServer(http.Dir("frontend")))

	fmt.Println("TakeCharge running on :8080")
	log.Fatal(http.ListenAndServe(":8080", corsMiddleware(http.DefaultServeMux)))
}
