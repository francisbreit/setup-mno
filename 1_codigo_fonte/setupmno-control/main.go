package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"math"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	sessionCookie = "mno_control_session"
	maxBodyBytes  = 32 << 10
)

//go:embed web/* catalog.json
var embeddedFiles embed.FS

type session struct {
	User     string
	CSRF     string
	Expires  time.Time
	LastSeen time.Time
}

type auditEvent struct {
	Time    time.Time `json:"time"`
	Action  string    `json:"action"`
	Detail  string    `json:"detail"`
	Address string    `json:"address"`
}

type loginWindow struct {
	Attempts int
	ResetAt  time.Time
	Blocked  time.Time
}

type webApp struct {
	adminUser      string
	passwordSalt   []byte
	passwordHash   []byte
	agentToken     string
	agentURL       string
	terminalURL    *url.URL
	version        string
	cookieSecure   bool
	httpClient     *http.Client

	sessionMu sync.Mutex
	sessions  map[string]*session
	loginMu   sync.Mutex
	logins    map[string]*loginWindow
	auditMu   sync.Mutex
	audit     []auditEvent
}

type hostMetrics struct {
	CPUPercent    float64 `json:"cpuPercent"`
	MemoryPercent float64 `json:"memoryPercent"`
	MemoryUsed    uint64  `json:"memoryUsed"`
	MemoryTotal   uint64  `json:"memoryTotal"`
	DiskPercent   float64 `json:"diskPercent"`
	DiskUsed      uint64  `json:"diskUsed"`
	DiskTotal     uint64  `json:"diskTotal"`
	Load1         float64 `json:"load1"`
	Load5         float64 `json:"load5"`
	Load15        float64 `json:"load15"`
	UptimeSeconds float64 `json:"uptimeSeconds"`
}

type serviceSummary struct {
	Name     string `json:"name"`
	Stack    string `json:"stack"`
	Image    string `json:"image"`
	Running  uint64 `json:"running"`
	Desired  uint64 `json:"desired"`
	Status   string `json:"status"`
	Updated  string `json:"updated"`
	Replicas string `json:"replicas"`
}

type appSummary struct {
	Name     string           `json:"name"`
	Status   string           `json:"status"`
	Running  uint64           `json:"running"`
	Desired  uint64           `json:"desired"`
	Services []serviceSummary `json:"services"`
}

type overview struct {
	Metrics           hostMetrics `json:"metrics"`
	Apps              int         `json:"apps"`
	Services          int         `json:"services"`
	HealthyServices   int         `json:"healthyServices"`
	DegradedServices  int         `json:"degradedServices"`
	ContainersRunning int         `json:"containersRunning"`
	ContainersStopped int         `json:"containersStopped"`
	SwarmNodes        int         `json:"swarmNodes"`
	EngineVersion     string      `json:"engineVersion"`
	Architecture      string      `json:"architecture"`
	Hostname          string      `json:"hostname"`
	GeneratedAt       time.Time   `json:"generatedAt"`
}

type dockerInfo struct {
	Name              string `json:"Name"`
	Architecture      string `json:"Architecture"`
	NCPU              int    `json:"NCPU"`
	MemTotal          uint64 `json:"MemTotal"`
	ContainersRunning int    `json:"ContainersRunning"`
	ContainersStopped int    `json:"ContainersStopped"`
	Swarm             struct {
		Nodes int `json:"Nodes"`
	} `json:"Swarm"`
	ServerVersion string `json:"ServerVersion"`
}

type dockerService struct {
	ID   string `json:"ID"`
	Spec struct {
		Name   string            `json:"Name"`
		Labels map[string]string `json:"Labels"`
		TaskTemplate struct {
			ContainerSpec struct {
				Image string `json:"Image"`
			} `json:"ContainerSpec"`
		} `json:"TaskTemplate"`
	} `json:"Spec"`
	ServiceStatus *struct {
		RunningTasks uint64 `json:"RunningTasks"`
		DesiredTasks uint64 `json:"DesiredTasks"`
	} `json:"ServiceStatus"`
	UpdatedAt time.Time `json:"UpdatedAt"`
}

type dockerTask struct {
	ServiceID    string `json:"ServiceID"`
	DesiredState string `json:"DesiredState"`
	Status       struct {
		State string `json:"State"`
	} `json:"Status"`
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		client := &http.Client{Timeout: 3 * time.Second}
		response, err := client.Get("http://127.0.0.1:8080/health")
		if err != nil || response.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		_ = response.Body.Close()
		return
	}
	mode := strings.ToLower(envDefault("MODE", "web"))
	var err error
	switch mode {
	case "agent":
		err = runAgent()
	case "web":
		err = runWeb()
	default:
		err = fmt.Errorf("modo inválido: %s", mode)
	}
	if err != nil {
		log.Fatal(err)
	}
}

func runWeb() error {
	passwordSecret, err := readSecret(envDefault("ADMIN_PASSWORD_FILE", "/run/secrets/admin_password"), false)
	if err != nil {
		return fmt.Errorf("credencial administrativa indisponível: %w", err)
	}
	if len(passwordSecret) < 12 {
		return errors.New("a senha administrativa precisa ter pelo menos 12 caracteres")
	}
	agentTokenBytes, err := readSecret(envDefault("AGENT_TOKEN_FILE", "/run/secrets/agent_token"), true)
	if err != nil {
		return fmt.Errorf("token do agente indisponível: %w", err)
	}
	terminalURL, err := url.Parse(envDefault("TERMINAL_URL", "http://terminal:7681"))
	if err != nil {
		return fmt.Errorf("URL do terminal inválida: %w", err)
	}

	app := &webApp{
		adminUser:      envDefault("ADMIN_USERNAME", "admin"),
		passwordSalt:   randomBytes(16),
		agentToken:     string(agentTokenBytes),
		agentURL:       strings.TrimRight(envDefault("AGENT_URL", "http://agent:9090"), "/"),
		terminalURL:    terminalURL,
		version:        envDefault("APP_VERSION", "dev"),
		cookieSecure:   envDefault("COOKIE_SECURE", "true") != "false",
		httpClient:     &http.Client{Timeout: 8 * time.Second},
		sessions:       make(map[string]*session),
		logins:         make(map[string]*loginWindow),
		audit:          make([]auditEvent, 0, 200),
	}
	app.passwordHash = pbkdf2SHA256(passwordSecret, app.passwordSalt, 310000, 32)
	zero(passwordSecret)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", app.handleHealth)
	mux.HandleFunc("POST /api/login", app.handleLogin)
	mux.Handle("GET /api/session", app.requireAuth(http.HandlerFunc(app.handleSession)))
	mux.Handle("POST /api/logout", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleLogout))))
	mux.Handle("GET /api/overview", app.requireAuth(http.HandlerFunc(app.handleOverview)))
	mux.Handle("GET /api/apps", app.requireAuth(http.HandlerFunc(app.handleApps)))
	mux.Handle("GET /api/catalog", app.requireAuth(http.HandlerFunc(app.handleCatalog)))
	mux.Handle("GET /api/audit", app.requireAuth(http.HandlerFunc(app.handleAudit)))
	mux.Handle("POST /api/assistant", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleAssistant))))
	mux.Handle("/terminal/", app.requireAuth(app.terminalProxy()))

	webRoot, err := fs.Sub(embeddedFiles, "web")
	if err != nil {
		return err
	}
	mux.Handle("/", http.FileServer(http.FS(webRoot)))

	server := &http.Server{
		Addr:              ":8080",
		Handler:           app.securityHeaders(mux),
		ReadHeaderTimeout: 8 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      45 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	go app.sessionJanitor()
	log.Printf("Setup MNO Control Center %s iniciado na porta 8080", app.version)
	return server.ListenAndServe()
}

func runAgent() error {
	agentToken, err := readSecret(envDefault("AGENT_TOKEN_FILE", "/run/secrets/agent_token"), true)
	if err != nil {
		return fmt.Errorf("token do agente indisponível: %w", err)
	}
	if _, err := os.Stat("/var/run/docker.sock"); err != nil {
		return fmt.Errorf("socket Docker indisponível: %w", err)
	}

	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 3 * time.Second}).DialContext(ctx, "unix", "/var/run/docker.sock")
		},
		DisableKeepAlives: false,
	}
	dockerClient := &http.Client{Transport: transport, Timeout: 10 * time.Second}
	token := string(agentToken)

	authorize := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			provided := r.Header.Get("X-SetupMNO-Agent-Token")
			if len(provided) != len(token) ||
				subtle.ConstantTimeCompare([]byte(provided), []byte(token)) != 1 {
				writeError(w, http.StatusUnauthorized, "não autorizado")
				return
			}
			next(w, r)
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
	})
	mux.HandleFunc("GET /overview", authorize(func(w http.ResponseWriter, _ *http.Request) {
		data, err := collectOverview(dockerClient)
		if err != nil {
			writeError(w, http.StatusBadGateway, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, data)
	}))
	mux.HandleFunc("GET /apps", authorize(func(w http.ResponseWriter, _ *http.Request) {
		apps, err := collectApps(dockerClient)
		if err != nil {
			writeError(w, http.StatusBadGateway, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"apps":        apps,
			"generatedAt": time.Now().UTC(),
		})
	}))

	server := &http.Server{
		Addr:              ":9090",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       12 * time.Second,
		WriteTimeout:      20 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	log.Printf("agente interno do Setup MNO iniciado na porta 9090")
	return server.ListenAndServe()
}

func (a *webApp) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"version": a.version,
	})
}

func (a *webApp) handleLogin(w http.ResponseWriter, r *http.Request) {
	if !a.sameOrigin(r) {
		writeError(w, http.StatusForbidden, "origem inválida")
		return
	}
	address := clientAddress(r)
	if wait := a.loginBlocked(address); wait > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(wait.Seconds()))))
		writeError(w, http.StatusTooManyRequests, "muitas tentativas; aguarde antes de tentar novamente")
		return
	}

	var input struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &input, 4096); err != nil {
		return
	}
	candidate := pbkdf2SHA256([]byte(input.Password), a.passwordSalt, 310000, 32)
	userOK := subtle.ConstantTimeCompare([]byte(input.Username), []byte(a.adminUser)) == 1
	passOK := subtle.ConstantTimeCompare(candidate, a.passwordHash) == 1
	zero(candidate)
	if !userOK || !passOK {
		a.recordLoginFailure(address)
		a.addAudit("login_failed", "Tentativa de autenticação recusada", address)
		time.Sleep(350 * time.Millisecond)
		writeError(w, http.StatusUnauthorized, "usuário ou senha inválidos")
		return
	}
	a.clearLoginFailures(address)

	id := randomToken(32)
	csrf := randomToken(24)
	now := time.Now()
	a.sessionMu.Lock()
	a.sessions[id] = &session{
		User:     a.adminUser,
		CSRF:     csrf,
		Expires:  now.Add(8 * time.Hour),
		LastSeen: now,
	}
	a.sessionMu.Unlock()

	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    id,
		Path:     "/",
		MaxAge:   int((8 * time.Hour).Seconds()),
		HttpOnly: true,
		Secure:   a.cookieSecure,
		SameSite: http.SameSiteStrictMode,
	})
	a.addAudit("login_success", "Sessão administrativa iniciada", address)
	writeJSON(w, http.StatusOK, map[string]any{
		"authenticated": true,
		"user":          a.adminUser,
		"csrfToken":     csrf,
		"version":       a.version,
	})
}

func (a *webApp) handleSession(w http.ResponseWriter, r *http.Request) {
	s := sessionFromContext(r.Context())
	writeJSON(w, http.StatusOK, map[string]any{
		"authenticated": true,
		"user":          s.User,
		"csrfToken":     s.CSRF,
		"expiresAt":     s.Expires.UTC(),
		"version":       a.version,
	})
}

func (a *webApp) handleLogout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(sessionCookie); err == nil {
		a.sessionMu.Lock()
		delete(a.sessions, cookie.Value)
		a.sessionMu.Unlock()
	}
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   a.cookieSecure,
		SameSite: http.SameSiteStrictMode,
	})
	a.addAudit("logout", "Sessão administrativa encerrada", clientAddress(r))
	writeJSON(w, http.StatusOK, map[string]any{"authenticated": false})
}

func (a *webApp) handleOverview(w http.ResponseWriter, r *http.Request) {
	var result overview
	if err := a.agentRequest(r.Context(), "/overview", &result); err != nil {
		writeError(w, http.StatusBadGateway, "agente de monitoramento indisponível")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"overview": result,
		"version":  a.version,
	})
}

func (a *webApp) handleApps(w http.ResponseWriter, r *http.Request) {
	var result map[string]any
	if err := a.agentRequest(r.Context(), "/apps", &result); err != nil {
		writeError(w, http.StatusBadGateway, "inventário Docker indisponível")
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (a *webApp) handleCatalog(w http.ResponseWriter, _ *http.Request) {
	catalog, err := embeddedFiles.ReadFile("catalog.json")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "catálogo indisponível")
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "private, max-age=300")
	_, _ = w.Write(catalog)
}

func (a *webApp) handleAudit(w http.ResponseWriter, _ *http.Request) {
	a.auditMu.Lock()
	events := make([]auditEvent, len(a.audit))
	copy(events, a.audit)
	a.auditMu.Unlock()
	for i, j := 0, len(events)-1; i < j; i, j = i+1, j-1 {
		events[i], events[j] = events[j], events[i]
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": events})
}

func (a *webApp) handleAssistant(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Question string `json:"question"`
	}
	if err := decodeJSON(w, r, &input, maxBodyBytes); err != nil {
		return
	}
	if len(strings.TrimSpace(input.Question)) < 3 {
		writeError(w, http.StatusBadRequest, "descreva o que deseja analisar")
		return
	}
	var current overview
	if err := a.agentRequest(r.Context(), "/overview", &current); err != nil {
		writeError(w, http.StatusBadGateway, "não foi possível consultar o servidor")
		return
	}
	suggestions := localInsights(current, input.Question)
	a.addAudit("assistant_analysis", "Diagnóstico local solicitado", clientAddress(r))
	writeJSON(w, http.StatusOK, map[string]any{
		"mode":        "local-insights",
		"answer":      strings.Join(suggestions, "\n\n"),
		"suggestions": suggestions,
	})
}

func (a *webApp) terminalProxy() http.Handler {
	proxy := httputil.NewSingleHostReverseProxy(a.terminalURL)
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalHost := req.Host
		originalDirector(req)
		req.Host = originalHost
		req.Header.Set("X-Forwarded-Host", originalHost)
		req.Header.Set("X-Forwarded-Proto", "https")
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		writeError(w, http.StatusBadGateway, "terminal seguro indisponível")
	}
	proxy.FlushInterval = 50 * time.Millisecond
	return proxy
}

func (a *webApp) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(sessionCookie)
		if err != nil || len(cookie.Value) < 32 {
			writeError(w, http.StatusUnauthorized, "autenticação necessária")
			return
		}
		now := time.Now()
		a.sessionMu.Lock()
		s, ok := a.sessions[cookie.Value]
		if ok && (now.After(s.Expires) || now.Sub(s.LastSeen) > 30*time.Minute) {
			delete(a.sessions, cookie.Value)
			ok = false
		}
		if ok {
			s.LastSeen = now
		}
		var snapshot session
		if ok {
			snapshot = *s
		}
		a.sessionMu.Unlock()
		if !ok {
			writeError(w, http.StatusUnauthorized, "sessão expirada")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), sessionContextKey{}, &snapshot)))
	})
}

func (a *webApp) requireCSRF(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !a.sameOrigin(r) {
			writeError(w, http.StatusForbidden, "origem inválida")
			return
		}
		s := sessionFromContext(r.Context())
		token := r.Header.Get("X-CSRF-Token")
		if len(token) != len(s.CSRF) ||
			subtle.ConstantTimeCompare([]byte(token), []byte(s.CSRF)) != 1 {
			writeError(w, http.StatusForbidden, "token CSRF inválido")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *webApp) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()")
		if strings.HasPrefix(r.URL.Path, "/terminal/") {
			w.Header().Set("X-Frame-Options", "SAMEORIGIN")
		} else {
			w.Header().Set("X-Frame-Options", "DENY")
			w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self' ws: wss:; frame-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
		}
		if a.cookieSecure {
			w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		next.ServeHTTP(w, r)
	})
}

func (a *webApp) sameOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	parsed, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return strings.EqualFold(parsed.Host, r.Host)
}

func (a *webApp) agentRequest(ctx context.Context, endpoint string, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, a.agentURL+endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("X-SetupMNO-Agent-Token", a.agentToken)
	resp, err := a.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("agente retornou HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(target)
}

func (a *webApp) loginBlocked(address string) time.Duration {
	a.loginMu.Lock()
	defer a.loginMu.Unlock()
	item := a.logins[address]
	if item == nil || item.Blocked.IsZero() {
		return 0
	}
	if time.Now().After(item.Blocked) {
		delete(a.logins, address)
		return 0
	}
	return time.Until(item.Blocked)
}

func (a *webApp) recordLoginFailure(address string) {
	a.loginMu.Lock()
	defer a.loginMu.Unlock()
	now := time.Now()
	item := a.logins[address]
	if item == nil || now.After(item.ResetAt) {
		item = &loginWindow{ResetAt: now.Add(15 * time.Minute)}
		a.logins[address] = item
	}
	item.Attempts++
	if item.Attempts >= 5 {
		item.Blocked = now.Add(15 * time.Minute)
	}
}

func (a *webApp) clearLoginFailures(address string) {
	a.loginMu.Lock()
	delete(a.logins, address)
	a.loginMu.Unlock()
}

func (a *webApp) addAudit(action, detail, address string) {
	a.auditMu.Lock()
	defer a.auditMu.Unlock()
	a.audit = append(a.audit, auditEvent{
		Time:    time.Now().UTC(),
		Action:  action,
		Detail:  detail,
		Address: address,
	})
	if len(a.audit) > 200 {
		a.audit = append([]auditEvent(nil), a.audit[len(a.audit)-200:]...)
	}
}

func (a *webApp) sessionJanitor() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for now := range ticker.C {
		a.sessionMu.Lock()
		for id, s := range a.sessions {
			if now.After(s.Expires) || now.Sub(s.LastSeen) > 30*time.Minute {
				delete(a.sessions, id)
			}
		}
		a.sessionMu.Unlock()
	}
}

func collectOverview(client *http.Client) (overview, error) {
	var info dockerInfo
	if err := dockerJSON(client, "/info", &info); err != nil {
		return overview{}, fmt.Errorf("Docker indisponível: %w", err)
	}
	apps, err := collectApps(client)
	if err != nil {
		return overview{}, err
	}
	services := 0
	healthy := 0
	degraded := 0
	for _, app := range apps {
		services += len(app.Services)
		for _, service := range app.Services {
			if service.Status == "online" {
				healthy++
			} else {
				degraded++
			}
		}
	}
	metrics, _ := collectHostMetrics()
	if metrics.MemoryTotal == 0 {
		metrics.MemoryTotal = info.MemTotal
	}
	return overview{
		Metrics:           metrics,
		Apps:              len(apps),
		Services:          services,
		HealthyServices:   healthy,
		DegradedServices:  degraded,
		ContainersRunning: info.ContainersRunning,
		ContainersStopped: info.ContainersStopped,
		SwarmNodes:        info.Swarm.Nodes,
		EngineVersion:     info.ServerVersion,
		Architecture:      info.Architecture,
		Hostname:          info.Name,
		GeneratedAt:       time.Now().UTC(),
	}, nil
}

func collectApps(client *http.Client) ([]appSummary, error) {
	var services []dockerService
	if err := dockerJSON(client, "/services?status=true", &services); err != nil {
		return nil, fmt.Errorf("não foi possível listar serviços: %w", err)
	}
	var tasks []dockerTask
	_ = dockerJSON(client, "/tasks", &tasks)

	type taskCount struct {
		running uint64
		desired uint64
	}
	counts := make(map[string]*taskCount)
	for _, task := range tasks {
		item := counts[task.ServiceID]
		if item == nil {
			item = &taskCount{}
			counts[task.ServiceID] = item
		}
		if task.DesiredState == "running" {
			item.desired++
		}
		if task.Status.State == "running" {
			item.running++
		}
	}

	grouped := make(map[string]*appSummary)
	order := make([]string, 0)
	for _, service := range services {
		stack := service.Spec.Labels["com.docker.stack.namespace"]
		if stack == "" {
			stack = service.Spec.Name
		}
		app := grouped[stack]
		if app == nil {
			app = &appSummary{Name: stack, Status: "online"}
			grouped[stack] = app
			order = append(order, stack)
		}

		var running, desired uint64
		if service.ServiceStatus != nil {
			running = service.ServiceStatus.RunningTasks
			desired = service.ServiceStatus.DesiredTasks
		} else if count := counts[service.ID]; count != nil {
			running = count.running
			desired = count.desired
		}
		status := "online"
		if desired == 0 {
			status = "paused"
		} else if running < desired {
			status = "degraded"
		}
		if status != "online" {
			app.Status = "degraded"
		}
		app.Running += running
		app.Desired += desired
		app.Services = append(app.Services, serviceSummary{
			Name:     service.Spec.Name,
			Stack:    stack,
			Image:    service.Spec.TaskTemplate.ContainerSpec.Image,
			Running:  running,
			Desired:  desired,
			Status:   status,
			Updated:  service.UpdatedAt.UTC().Format(time.RFC3339),
			Replicas: fmt.Sprintf("%d/%d", running, desired),
		})
	}

	sortStrings(order)
	result := make([]appSummary, 0, len(order))
	for _, name := range order {
		result = append(result, *grouped[name])
	}
	return result, nil
}

func collectHostMetrics() (hostMetrics, error) {
	firstTotal, firstIdle, err := readCPU()
	if err != nil {
		return hostMetrics{}, err
	}
	time.Sleep(180 * time.Millisecond)
	secondTotal, secondIdle, err := readCPU()
	if err != nil {
		return hostMetrics{}, err
	}
	totalDelta := secondTotal - firstTotal
	idleDelta := secondIdle - firstIdle
	cpu := 0.0
	if totalDelta > 0 {
		cpu = (1 - float64(idleDelta)/float64(totalDelta)) * 100
	}

	memTotal, memAvailable, _ := readMemory()
	memUsed := uint64(0)
	memPercent := 0.0
	if memTotal > memAvailable {
		memUsed = memTotal - memAvailable
		memPercent = float64(memUsed) / float64(memTotal) * 100
	}

	var stat syscall.Statfs_t
	diskTotal := uint64(0)
	diskUsed := uint64(0)
	diskPercent := 0.0
	if err := syscall.Statfs("/hostfs", &stat); err == nil {
		diskTotal = stat.Blocks * uint64(stat.Bsize)
		diskFree := stat.Bavail * uint64(stat.Bsize)
		if diskTotal > diskFree {
			diskUsed = diskTotal - diskFree
			diskPercent = float64(diskUsed) / float64(diskTotal) * 100
		}
	}

	load1, load5, load15 := readLoad()
	uptime := readUptime()
	return hostMetrics{
		CPUPercent:    round(cpu),
		MemoryPercent: round(memPercent),
		MemoryUsed:    memUsed,
		MemoryTotal:   memTotal,
		DiskPercent:   round(diskPercent),
		DiskUsed:      diskUsed,
		DiskTotal:     diskTotal,
		Load1:         load1,
		Load5:         load5,
		Load15:        load15,
		UptimeSeconds: uptime,
	}, nil
}

func readCPU() (uint64, uint64, error) {
	data, err := os.ReadFile("/host/proc/stat")
	if err != nil {
		return 0, 0, err
	}
	line := strings.SplitN(string(data), "\n", 2)[0]
	fields := strings.Fields(line)
	if len(fields) < 8 || fields[0] != "cpu" {
		return 0, 0, errors.New("estatística de CPU inválida")
	}
	var values []uint64
	for _, field := range fields[1:] {
		value, _ := strconv.ParseUint(field, 10, 64)
		values = append(values, value)
	}
	var total uint64
	for _, value := range values {
		total += value
	}
	idle := values[3]
	if len(values) > 4 {
		idle += values[4]
	}
	return total, idle, nil
}

func readMemory() (uint64, uint64, error) {
	data, err := os.ReadFile("/host/proc/meminfo")
	if err != nil {
		return 0, 0, err
	}
	var total, available uint64
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		value, _ := strconv.ParseUint(fields[1], 10, 64)
		switch strings.TrimSuffix(fields[0], ":") {
		case "MemTotal":
			total = value * 1024
		case "MemAvailable":
			available = value * 1024
		}
	}
	return total, available, nil
}

func readLoad() (float64, float64, float64) {
	data, err := os.ReadFile("/host/proc/loadavg")
	if err != nil {
		return 0, 0, 0
	}
	fields := strings.Fields(string(data))
	if len(fields) < 3 {
		return 0, 0, 0
	}
	one, _ := strconv.ParseFloat(fields[0], 64)
	five, _ := strconv.ParseFloat(fields[1], 64)
	fifteen, _ := strconv.ParseFloat(fields[2], 64)
	return one, five, fifteen
}

func readUptime() float64 {
	data, err := os.ReadFile("/host/proc/uptime")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0
	}
	value, _ := strconv.ParseFloat(fields[0], 64)
	return value
}

func dockerJSON(client *http.Client, endpoint string, target any) error {
	req, err := http.NewRequest(http.MethodGet, "http://docker"+endpoint, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 16<<20)).Decode(target)
}

func localInsights(current overview, question string) []string {
	result := []string{
		"Diagnóstico local concluído para: “" + strings.TrimSpace(question) + "”.",
	}
	if current.Metrics.MemoryPercent >= 85 {
		result = append(result, fmt.Sprintf("Memória em nível crítico (%.1f%%). Evite novos setups e revise os serviços mais pesados.", current.Metrics.MemoryPercent))
	} else if current.Metrics.MemoryPercent >= 70 {
		result = append(result, fmt.Sprintf("Memória sob atenção (%.1f%%). Há espaço limitado para aplicações acima de 2 GB.", current.Metrics.MemoryPercent))
	} else {
		result = append(result, fmt.Sprintf("Memória saudável (%.1f%% em uso). Ainda valide o requisito de RAM do próximo setup.", current.Metrics.MemoryPercent))
	}
	if current.Metrics.DiskPercent >= 85 {
		result = append(result, fmt.Sprintf("Disco em nível crítico (%.1f%%). Priorize limpeza de imagens, logs e backups antigos após conferência.", current.Metrics.DiskPercent))
	} else {
		result = append(result, fmt.Sprintf("Disco com %.1f%% de utilização.", current.Metrics.DiskPercent))
	}
	if current.DegradedServices > 0 {
		result = append(result, fmt.Sprintf("%d serviço(s) estão degradados. Abra Aplicações instaladas antes de iniciar outro deploy.", current.DegradedServices))
	} else {
		result = append(result, fmt.Sprintf("Todos os %d serviços monitorados estão atendendo às réplicas desejadas.", current.Services))
	}
	result = append(result, "Ações destrutivas e instalações continuam exigindo confirmação humana no Instalador Seguro.")
	return result
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any, limit int64) error {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		writeError(w, http.StatusUnsupportedMediaType, "Content-Type deve ser application/json")
		return errors.New("content type inválido")
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(w, http.StatusBadRequest, "JSON inválido")
		return err
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{"error": message})
}

func readSecret(filename string, trim bool) ([]byte, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	if trim {
		data = []byte(strings.TrimSpace(string(data)))
	}
	if len(data) == 0 {
		return nil, errors.New("secret vazio")
	}
	return data, nil
}

func pbkdf2SHA256(password, salt []byte, iterations, keyLength int) []byte {
	hashLength := sha256.Size
	blocks := (keyLength + hashLength - 1) / hashLength
	result := make([]byte, 0, blocks*hashLength)
	buffer := make([]byte, len(salt)+4)
	copy(buffer, salt)
	for block := 1; block <= blocks; block++ {
		binary.BigEndian.PutUint32(buffer[len(salt):], uint32(block))
		mac := hmac.New(sha256.New, password)
		_, _ = mac.Write(buffer)
		u := mac.Sum(nil)
		t := append([]byte(nil), u...)
		for i := 1; i < iterations; i++ {
			mac = hmac.New(sha256.New, password)
			_, _ = mac.Write(u)
			u = mac.Sum(nil)
			for j := range t {
				t[j] ^= u[j]
			}
		}
		result = append(result, t...)
	}
	return result[:keyLength]
}

func randomBytes(size int) []byte {
	value := make([]byte, size)
	if _, err := rand.Read(value); err != nil {
		panic(err)
	}
	return value
}

func randomToken(size int) string {
	return base64.RawURLEncoding.EncodeToString(randomBytes(size))
}

func zero(data []byte) {
	for i := range data {
		data[i] = 0
	}
}

func envDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func clientAddress(r *http.Request) string {
	for _, header := range []string{"CF-Connecting-IP", "X-Real-IP"} {
		if value := strings.TrimSpace(r.Header.Get(header)); value != "" {
			return value
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func sortStrings(values []string) {
	for i := 1; i < len(values); i++ {
		for j := i; j > 0 && strings.ToLower(values[j]) < strings.ToLower(values[j-1]); j-- {
			values[j], values[j-1] = values[j-1], values[j]
		}
	}
}

func round(value float64) float64 {
	return math.Round(value*10) / 10
}

type sessionContextKey struct{}

func sessionFromContext(ctx context.Context) *session {
	value, _ := ctx.Value(sessionContextKey{}).(*session)
	return value
}

func safeJoin(base, requested string) string {
	return path.Join(base, path.Clean("/"+requested))
}
