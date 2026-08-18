package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
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
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	sessionCookie        = "mno_control_session"
	maxBodyBytes         = 32 << 10
	maxCatalogBytes      = 4 << 20
	runtimeSchema        = 1
	defaultSetupStateDir = "/runtime-control"
	defaultHostDiskPath  = "/runtime-control"
	panelIdleTimeout     = 15 * time.Minute
	terminalIdleTimeout  = 30 * time.Minute
	absoluteSessionTTL   = 8 * time.Hour
)

//go:embed web/* catalog.json
var embeddedFiles embed.FS

type session struct {
	User          string
	CSRF          string
	AccessSubject string
	AccessEmail   string
	Expires       time.Time
	IdleUntil     time.Time
	LastSeen      time.Time
	TerminalUntil time.Time
}

type loginWindow struct {
	Attempts int
	ResetAt  time.Time
	Blocked  time.Time
}

type webApp struct {
	adminUser        string
	passwordSalt     []byte
	passwordHash     []byte
	agentToken       string
	agentURL         string
	terminalURL      *url.URL
	assistantURL     string
	assistantMode    string
	assistantModel   string
	version          string
	cookieSecure     bool
	accessVerifier   *accessVerifier
	httpClient       *http.Client
	assistantClient  *http.Client
	blueprints       blueprintCatalogResponse
	blueprintBundles map[string]blueprintBundleDownload
	evals            evalReport
	quality          knowledgeQualityReport

	sessionMu sync.Mutex
	sessions  map[string]*session
	loginMu   sync.Mutex
	logins    map[string]*loginWindow
	auditMu   sync.Mutex
	audit     auditState

	providerEvalMu      sync.Mutex
	providerEvalRunning bool
	providerEvalLast    time.Time
	providerEvalRuns    map[string]providerEvalRunRecord

	feedbackMu     sync.Mutex
	feedback       feedbackState
	feedbackTokens map[string]feedbackTokenRecord
}

type blueprintMediaSummary struct {
	MediaID       string  `json:"mediaId"`
	Type          string  `json:"type"`
	Title         string  `json:"title"`
	Status        string  `json:"status"`
	HasTranscript bool    `json:"hasTranscript"`
	URL           *string `json:"url"`
}

type blueprintBundleDownload struct {
	Filename string
	SHA256   string
	Data     []byte
}

type blueprintCatalogItem struct {
	Aliases           []string                   `json:"aliases"`
	Architectures     []string                   `json:"architectures"`
	Author            string                     `json:"author"`
	BlueprintID       string                     `json:"blueprintId"`
	BlueprintVersion  string                     `json:"blueprintVersion"`
	BundleBytes       int64                      `json:"bundleBytes"`
	BundleSHA256      string                     `json:"bundleSHA256"`
	Components        []string                   `json:"components"`
	ComponentDetails  []blueprintComponentDetail `json:"componentDetails"`
	Deployable        bool                       `json:"deployable"`
	Editorial         blueprintEditorial         `json:"editorial"`
	Fictitious        bool                       `json:"fictitious"`
	Media             []blueprintMediaSummary    `json:"media"`
	Installation      blueprintInstallation      `json:"installation"`
	Validation        blueprintValidation        `json:"validation"`
	Rollback          blueprintRollback          `json:"rollback"`
	DownloadAvailable bool                       `json:"downloadAvailable"`
	Objective         string                     `json:"objective"`
	ResourceProfile   blueprintResourceProfile   `json:"resourceProfile"`
	Risk              string                     `json:"risk"`
	Status            string                     `json:"status"`
	Summary           string                     `json:"summary"`
	Tags              []string                   `json:"tags"`
	Title             string                     `json:"title"`
	UpdatedAt         string                     `json:"updatedAt"`
}

type blueprintCatalogResponse struct {
	SchemaVersion    int                    `json:"schemaVersion"`
	FactoryVersion   string                 `json:"factoryVersion"`
	SetupVersion     string                 `json:"setupVersion"`
	KnowledgeVersion string                 `json:"knowledgeVersion"`
	IndexSHA256      string                 `json:"indexSHA256"`
	Source           string                 `json:"source"`
	BlueprintCount   int                    `json:"blueprintCount"`
	ExampleCount     int                    `json:"exampleCount"`
	BetaCount        int                    `json:"betaCount"`
	HomologatedCount int                    `json:"homologatedCount"`
	ReviewCount      int                    `json:"reviewCount"`
	Items            []blueprintCatalogItem `json:"items"`
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

type setupRelease struct {
	SchemaVersion                int    `json:"schemaVersion"`
	SetupVersion                 string `json:"setupVersion"`
	CatalogVersion               string `json:"catalogVersion"`
	CatalogSHA256                string `json:"catalogSHA256"`
	CatalogEntries               int    `json:"catalogEntries"`
	Architecture                 string `json:"architecture"`
	KnowledgeVersion             string `json:"knowledgeVersion,omitempty"`
	KnowledgeArchiveSHA256       string `json:"knowledgeArchiveSHA256,omitempty"`
	KnowledgeEntries             int    `json:"knowledgeEntries,omitempty"`
	BlueprintFactoryVersion      string `json:"blueprintFactoryVersion,omitempty"`
	BlueprintSchemaVersion       int    `json:"blueprintSchemaVersion,omitempty"`
	BlueprintIndexSHA256         string `json:"blueprintIndexSHA256,omitempty"`
	BlueprintEntries             int    `json:"blueprintEntries,omitempty"`
	BlueprintKnowledgeEntries    int    `json:"blueprintKnowledgeEntries,omitempty"`
	BlueprintFixtureEntries      int    `json:"blueprintFixtureEntries,omitempty"`
	EvalSchemaVersion            int    `json:"evalSchemaVersion,omitempty"`
	EvalDatasetVersion           string `json:"evalDatasetVersion,omitempty"`
	EvalGraderVersion            string `json:"evalGraderVersion,omitempty"`
	EvalDatasetSHA256            string `json:"evalDatasetSHA256,omitempty"`
	EvalCaseEntries              int    `json:"evalCaseEntries,omitempty"`
	QualitySchemaVersion         int    `json:"qualitySchemaVersion,omitempty"`
	QualityReportSHA256          string `json:"qualityReportSHA256,omitempty"`
	QualitySetupEntries          int    `json:"qualitySetupEntries,omitempty"`
	QualityStructuralEntries     int    `json:"qualityStructuralEntries,omitempty"`
	QualitySourceReviewedEntries int    `json:"qualitySourceReviewedEntries,omitempty"`
	QualityScriptReviewedEntries int    `json:"qualityScriptReviewedEntries,omitempty"`
	QualityOperationalEntries    int    `json:"qualityOperationalEntries,omitempty"`
	QualityHomologatedEntries    int    `json:"qualityHomologatedEntries,omitempty"`
	QualityUnresolvedIssues      int    `json:"qualityUnresolvedIssues,omitempty"`
}

type runtimeSnapshot struct {
	Release setupRelease
	Items   []json.RawMessage
}

type setupStateResponse struct {
	SchemaVersion    int    `json:"schemaVersion"`
	SetupVersion     string `json:"setupVersion"`
	ControlVersion   string `json:"controlVersion,omitempty"`
	CatalogVersion   string `json:"catalogVersion"`
	CatalogSHA256    string `json:"catalogSHA256"`
	CatalogEntries   int    `json:"catalogEntries"`
	Architecture     string `json:"architecture"`
	Source           string `json:"source"`
	Stale            bool   `json:"stale"`
	Warning          string `json:"warning,omitempty"`
	Plan             string `json:"plan,omitempty"`
	InstallationType string `json:"installationType,omitempty"`
	LLMAllowed       bool   `json:"llmAllowed"`
}

type runtimeEnvironment struct {
	SchemaVersion    int    `json:"schemaVersion"`
	Plan             string `json:"plan"`
	InstallationType string `json:"installationType"`
}

type catalogResponse struct {
	Items          []json.RawMessage `json:"items"`
	SetupVersion   string            `json:"setupVersion"`
	CatalogVersion string            `json:"catalogVersion"`
	CatalogSHA256  string            `json:"catalogSHA256"`
	CatalogEntries int               `json:"catalogEntries"`
	Architecture   string            `json:"architecture"`
	Source         string            `json:"source"`
	Stale          bool              `json:"stale"`
	Warning        string            `json:"warning,omitempty"`
}

type knowledgeQualityResponse struct {
	knowledgeQualityReport
	Source  string `json:"source"`
	Stale   bool   `json:"stale"`
	Warning string `json:"warning,omitempty"`
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
	OperatingSystem   string      `json:"operatingSystem"`
	OSVersion         string      `json:"osVersion,omitempty"`
	OSType            string      `json:"osType"`
	KernelVersion     string      `json:"kernelVersion"`
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
	ServerVersion   string `json:"ServerVersion"`
	OperatingSystem string `json:"OperatingSystem"`
	OSVersion       string `json:"OSVersion"`
	OSType          string `json:"OSType"`
	KernelVersion   string `json:"KernelVersion"`
}

type dockerService struct {
	ID   string `json:"ID"`
	Spec struct {
		Name         string            `json:"Name"`
		Labels       map[string]string `json:"Labels"`
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

type assistantMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type assistantRequest struct {
	Question       string             `json:"question"`
	History        []assistantMessage `json:"history,omitempty"`
	Basic          bool               `json:"basic,omitempty"`
	FallbackReason string             `json:"fallbackReason,omitempty"`
}

type assistantApp struct {
	Name    string `json:"name"`
	Status  string `json:"status"`
	Running uint64 `json:"running"`
	Desired uint64 `json:"desired"`
}

type assistantContext struct {
	OperationalContextAvailable bool             `json:"operationalContextAvailable"`
	OperationalContextWarning   string           `json:"operationalContextWarning,omitempty"`
	KnowledgeDocumentEntries    int              `json:"knowledgeDocumentEntries"`
	CanonicalSetupEntries       int              `json:"canonicalSetupEntries"`
	InfrastructureEntries       int              `json:"infrastructureEntries"`
	BlueprintEntries            int              `json:"blueprintEntries"`
	BlueprintBetaEntries        int              `json:"blueprintBetaEntries"`
	BlueprintHomologatedEntries int              `json:"blueprintHomologatedEntries"`
	SetupTypeEntries            map[string]int   `json:"setupTypeEntries,omitempty"`
	ApplicationInventoryStatus  string           `json:"applicationInventoryStatus"`
	SetupVersion                string           `json:"setupVersion"`
	CatalogVersion              string           `json:"catalogVersion"`
	CatalogSHA256               string           `json:"catalogSHA256"`
	CatalogEntries              int              `json:"catalogEntries"`
	CatalogSource               string           `json:"catalogSource"`
	CatalogStale                bool             `json:"catalogStale"`
	Architecture                string           `json:"architecture"`
	OperatingSystem             string           `json:"operatingSystem"`
	OSVersion                   string           `json:"osVersion,omitempty"`
	OSType                      string           `json:"osType"`
	KernelVersion               string           `json:"kernelVersion"`
	EngineVersion               string           `json:"engineVersion"`
	CPUPercent                  float64          `json:"cpuPercent"`
	MemoryPercent               float64          `json:"memoryPercent"`
	MemoryAvailableGB           float64          `json:"memoryAvailableGB"`
	DiskPercent                 float64          `json:"diskPercent"`
	Services                    int              `json:"services"`
	DegradedServices            int              `json:"degradedServices"`
	SwarmNodes                  int              `json:"swarmNodes"`
	InstalledApps               []assistantApp   `json:"installedApps"`
	RelevantSetupCount          int              `json:"relevantSetupCount"`
	RelevantSetups              []map[string]any `json:"relevantSetups"`
}

type assistantService struct {
	provider              string
	model                 string
	baseURL               string
	apiKey                string
	agentURL              string
	agentToken            string
	httpClient            *http.Client
	agentClient           *http.Client
	knowledge             knowledgePackageState
	retriever             *knowledgeRetriever
	shadowMode            bool
	inspectionMode        bool
	promptMode            bool
	blueprintHomologation bool

	retrievalMu    sync.Mutex
	retrievalStats retrievalAggregate
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "evalcheck" {
		state, err := loadRuntimeKnowledgePackage()
		if err != nil {
			log.Printf("pacote de conhecimento inválido: %v", err)
			os.Exit(1)
		}
		report, err := runEvalSuite(state, state.Manifest.ControlVersion)
		if err != nil {
			log.Printf("suíte de evals inválida: %v", err)
			os.Exit(1)
		}
		if err := json.NewEncoder(os.Stdout).Encode(report); err != nil {
			os.Exit(1)
		}
		if report.Status != "passed" {
			os.Exit(1)
		}
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "knowledgecheck" {
		state, err := loadRuntimeKnowledgePackage()
		if err != nil {
			log.Printf("pacote de conhecimento inválido: %v", err)
			os.Exit(1)
		}
		if err := json.NewEncoder(os.Stdout).Encode(knowledgeCheckPayload(state)); err != nil {
			os.Exit(1)
		}
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		client := &http.Client{Timeout: 3 * time.Second}
		response, err := client.Get(envDefault("HEALTHCHECK_URL", "http://127.0.0.1:8080/health"))
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
	case "assistant":
		err = runAssistant()
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

	controlVersion := envDefault("APP_VERSION", "dev")
	feedback, err := loadFeedbackState(envDefault("FEEDBACK_STORE_PATH", "/feedback/feedback.json"))
	if err != nil {
		return fmt.Errorf("fila de feedback indisponível: %w", err)
	}
	audit, err := loadAuditState(envDefault("AUDIT_STORE_PATH", "/audit/audit.json"))
	if err != nil {
		return fmt.Errorf("trilha de auditoria indisponível ou íntegra não confirmada: %w", err)
	}
	blueprintKnowledge, err := loadEmbeddedKnowledgePackage()
	if err != nil {
		return fmt.Errorf("catálogo de Blueprints indisponível: %w", err)
	}
	if controlVersion != "dev" && blueprintKnowledge.Manifest.ControlVersion != controlVersion {
		return fmt.Errorf(
			"catálogo de Blueprints pertence ao Control Center %s, esperado %s",
			blueprintKnowledge.Manifest.ControlVersion,
			controlVersion,
		)
	}
	blueprints, err := blueprintCatalogFromKnowledge(blueprintKnowledge)
	if err != nil {
		return fmt.Errorf("catálogo de Blueprints inválido: %w", err)
	}
	blueprintBundles, err := blueprintBundlesFromKnowledge(blueprintKnowledge)
	if err != nil {
		return fmt.Errorf("bundles de Blueprints indisponíveis: %w", err)
	}
	evalReport, err := runEvalSuite(blueprintKnowledge, controlVersion)
	if err != nil {
		return fmt.Errorf("suíte de evals indisponível: %w", err)
	}
	if evalReport.Status != "passed" {
		return errors.New("suíte de evals bloqueou a inicialização do Control Center")
	}
	assistantMode, assistantModel, assistantURL := assistantConfigurationForPlan(
		os.Getenv("SETUPMNO_PLAN"),
		strings.ToLower(envDefault("ASSISTANT_MODE", "basic")),
		os.Getenv("ASSISTANT_MODEL"),
		strings.TrimRight(os.Getenv("ASSISTANT_URL"), "/"),
	)

	accessRequired, err := parseAccessRequired(os.Getenv("ACCESS_JWT_REQUIRED"))
	if err != nil {
		return fmt.Errorf("proteção Cloudflare Access inválida: %w", err)
	}
	accessHTTPClient := &http.Client{Timeout: 8 * time.Second}
	accessVerifier, err := newAccessVerifier(
		accessRequired,
		os.Getenv("ACCESS_TEAM_DOMAIN"),
		os.Getenv("ACCESS_POLICY_AUD"),
		os.Getenv("ACCESS_ALLOWED_EMAIL"),
		accessHTTPClient,
	)
	if err != nil {
		return fmt.Errorf("proteção Cloudflare Access inválida: %w", err)
	}

	app := &webApp{
		adminUser:        envDefault("ADMIN_USERNAME", "admin"),
		passwordSalt:     randomBytes(16),
		agentToken:       string(agentTokenBytes),
		agentURL:         strings.TrimRight(envDefault("AGENT_URL", "http://agent:9090"), "/"),
		terminalURL:      terminalURL,
		assistantURL:     assistantURL,
		assistantMode:    assistantMode,
		assistantModel:   assistantModel,
		version:          controlVersion,
		cookieSecure:     envDefault("COOKIE_SECURE", "true") != "false",
		accessVerifier:   accessVerifier,
		httpClient:       &http.Client{Timeout: 8 * time.Second},
		assistantClient:  &http.Client{Timeout: 2 * time.Minute},
		sessions:         make(map[string]*session),
		logins:           make(map[string]*loginWindow),
		audit:            audit,
		blueprints:       blueprints,
		blueprintBundles: blueprintBundles,
		evals:            evalReport,
		providerEvalRuns: make(map[string]providerEvalRunRecord),
		feedback:         feedback,
		quality:          blueprintKnowledge.Quality,
		feedbackTokens:   make(map[string]feedbackTokenRecord),
	}
	app.passwordHash = pbkdf2SHA256(passwordSecret, app.passwordSalt, 310000, 32)
	zero(passwordSecret)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", app.handleHealth)
	mux.HandleFunc("POST /api/login", app.handleLogin)
	mux.Handle("POST /api/terminal/reauth", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleTerminalReauth))))
	mux.Handle("GET /api/session", app.requireAuth(http.HandlerFunc(app.handleSession)))
	mux.Handle("POST /api/session/activity", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleSessionActivity))))
	mux.Handle("POST /api/logout", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleLogout))))
	mux.Handle("GET /api/overview", app.requireAuth(http.HandlerFunc(app.handleOverview)))
	mux.Handle("GET /api/apps", app.requireAuth(http.HandlerFunc(app.handleApps)))
	mux.Handle("GET /api/setup-state", app.requireAuth(http.HandlerFunc(app.handleSetupState)))
	mux.Handle("GET /api/catalog", app.requireAuth(http.HandlerFunc(app.handleCatalog)))
	mux.Handle("GET /api/quality", app.requireAuth(http.HandlerFunc(app.handleQuality)))
	mux.Handle("GET /api/blueprints", app.requireAuth(http.HandlerFunc(app.handleBlueprints)))
	mux.Handle("GET /api/blueprints/{blueprintId}/download", app.requireAuth(http.HandlerFunc(app.handleBlueprintDownload)))
	mux.Handle("GET /api/evals", app.requireAuth(http.HandlerFunc(app.handleEvals)))
	mux.Handle("POST /api/evals/provider", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleProviderEval))))
	mux.Handle("POST /api/evals/provider/review", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleProviderEvalReview))))
	mux.Handle("POST /api/blueprints/recommend", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleBlueprintRecommendation))))
	mux.Handle("GET /api/audit", app.requireAuth(http.HandlerFunc(app.handleAudit)))
	mux.Handle("GET /api/feedback", app.requireAuth(http.HandlerFunc(app.handleFeedbackList)))
	mux.Handle("POST /api/feedback", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFeedbackSubmit))))
	mux.Handle("POST /api/feedback/review", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFeedbackReview))))
	mux.Handle("POST /api/feedback/delete", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFeedbackDelete))))
	mux.Handle("POST /api/assistant", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleAssistant))))
	mux.Handle("/terminal/", app.requireAuth(app.terminalProxy()))

	webRoot, err := fs.Sub(embeddedFiles, "web")
	if err != nil {
		return err
	}
	mux.Handle("/", http.FileServer(http.FS(webRoot)))

	server := &http.Server{
		Addr:              ":8080",
		Handler:           app.securityHeaders(app.accessVerifier.middleware(mux)),
		ReadHeaderTimeout: 8 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      2 * time.Minute,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	go app.sessionJanitor()
	log.Printf("Setup MNO Control Center %s iniciado na porta 8080", app.version)
	return server.ListenAndServe()
}

func parseAccessRequired(value string) (bool, error) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "false":
		return false, nil
	case "true":
		return true, nil
	default:
		return false, errors.New("ACCESS_JWT_REQUIRED deve ser true ou false")
	}
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
	setupStateDir := envDefault("SETUP_STATE_DIR", defaultSetupStateDir)

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
	mux.HandleFunc("GET /setup-state", authorize(func(w http.ResponseWriter, _ *http.Request) {
		snapshot, err := readRuntimeSnapshot(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "estado do Setup MNO indisponível")
			return
		}
		environment, err := readRuntimeEnvironment(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "plano e tipo de instalação indisponíveis")
			return
		}
		state := stateFromSnapshot(snapshot, "runtime")
		state.Plan = environment.Plan
		state.InstallationType = environment.InstallationType
		state.LLMAllowed = environment.Plan == "pro"
		writeJSON(w, http.StatusOK, state)
	}))
	mux.HandleFunc("GET /catalog", authorize(func(w http.ResponseWriter, _ *http.Request) {
		snapshot, err := readRuntimeSnapshot(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "catálogo runtime indisponível")
			return
		}
		writeJSON(w, http.StatusOK, catalogFromSnapshot(snapshot, "runtime"))
	}))
	mux.HandleFunc("GET /quality", authorize(func(w http.ResponseWriter, _ *http.Request) {
		knowledge, err := loadRuntimeBlueprintKnowledge(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "qualidade runtime indisponível")
			return
		}
		writeJSON(w, http.StatusOK, knowledgeQualityResponse{
			knowledgeQualityReport: knowledge.Quality,
			Source:                 "runtime-read-only",
		})
	}))
	mux.HandleFunc("GET /blueprints", authorize(func(w http.ResponseWriter, _ *http.Request) {
		knowledge, err := loadRuntimeBlueprintKnowledge(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "índice runtime de Blueprints indisponível")
			return
		}
		catalog, err := blueprintCatalogFromKnowledge(knowledge)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "índice runtime de Blueprints inválido")
			return
		}
		writeJSON(w, http.StatusOK, catalog)
	}))
	mux.HandleFunc("GET /blueprints/{blueprintId}/download", authorize(func(w http.ResponseWriter, r *http.Request) {
		blueprintID := r.PathValue("blueprintId")
		if !validBlueprintID(blueprintID) {
			writeError(w, http.StatusNotFound, "Blueprint não encontrado")
			return
		}
		knowledge, err := loadRuntimeBlueprintKnowledge(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "bundle runtime de Blueprint indisponível")
			return
		}
		bundles, err := blueprintBundlesFromKnowledge(knowledge)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "bundle runtime de Blueprint inválido")
			return
		}
		bundle, ok := bundles[blueprintID]
		if !ok {
			writeError(w, http.StatusNotFound, "Blueprint não encontrado")
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/zip")
		w.Header().Set("Content-Disposition", `attachment; filename="`+bundle.Filename+`"`)
		w.Header().Set("X-Content-SHA256", bundle.SHA256)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(bundle.Data)
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

func runAssistant() error {
	if err := validateAssistantPromptRegistry(); err != nil {
		return fmt.Errorf("registro de prompts do Assistente inválido: %w", err)
	}
	knowledge, err := loadRuntimeKnowledgePackage()
	if err != nil {
		return fmt.Errorf("conhecimento do Assistente indisponível: %w", err)
	}
	if knowledge.Stale {
		log.Printf("Assistente MNO: usando fallback de conhecimento embutido")
	}
	provider := strings.ToLower(strings.TrimSpace(os.Getenv("ASSISTANT_PROVIDER")))
	if provider != "openai" && provider != "openrouter" &&
		provider != "deepseek" && provider != "ollama" {
		return errors.New("ASSISTANT_PROVIDER deve ser openai, openrouter, deepseek ou ollama")
	}
	model := strings.TrimSpace(os.Getenv("ASSISTANT_MODEL"))
	if model == "" {
		return errors.New("ASSISTANT_MODEL não configurado")
	}
	baseURL := strings.TrimRight(strings.TrimSpace(os.Getenv("ASSISTANT_BASE_URL")), "/")
	if baseURL == "" {
		switch provider {
		case "openai":
			baseURL = "https://api.openai.com/v1"
		case "openrouter":
			baseURL = "https://openrouter.ai/api/v1"
		case "deepseek":
			baseURL = "https://api.deepseek.com"
		default:
			return errors.New("ASSISTANT_BASE_URL não configurada para o Ollama")
		}
	}
	providerURL, err := url.Parse(baseURL)
	if err != nil || (providerURL.Scheme != "http" && providerURL.Scheme != "https") ||
		providerURL.Host == "" || providerURL.User != nil || providerURL.RawQuery != "" ||
		providerURL.Fragment != "" {
		return errors.New("ASSISTANT_BASE_URL inválida")
	}

	apiKey := ""
	if provider == "openai" || provider == "openrouter" || provider == "deepseek" {
		key, keyErr := readSecret(envDefault("LLM_API_KEY_FILE", "/run/secrets/llm_api_key"), true)
		if keyErr != nil {
			return fmt.Errorf("chave do provedor indisponível: %w", keyErr)
		}
		apiKey = string(key)
		zero(key)
	}
	agentToken, err := readSecret(envDefault("AGENT_TOKEN_FILE", "/run/secrets/agent_token"), true)
	if err != nil {
		return fmt.Errorf("token do agente indisponível: %w", err)
	}

	shadowMode := strings.EqualFold(
		envDefault("RETRIEVAL_SHADOW_ENABLED", "false"),
		"true",
	)
	inspectionMode := shadowMode && strings.EqualFold(
		envDefault("RETRIEVAL_INSPECTION_ENABLED", "false"),
		"true",
	)
	promptMode := inspectionMode && strings.EqualFold(
		envDefault("RETRIEVAL_PROMPT_ENABLED", "false"),
		"true",
	)
	blueprintHomologation := promptMode && strings.EqualFold(
		envDefault("BLUEPRINT_HOMOLOGATION_ENABLED", "false"),
		"true",
	)
	// Releases anteriores podiam persistir o modo de homologação de fixtures.
	// Quando o pacote já não transporta fixtures, a opção legada é simplesmente
	// desativada; os guias Beta revisados continuam disponíveis no fluxo normal.
	blueprintHomologation = blueprintHomologation && knowledge.Manifest.BlueprintFixtureEntries > 0
	var retriever *knowledgeRetriever
	if shadowMode {
		retriever, err = newKnowledgeRetriever(knowledge, blueprintHomologation)
		if err != nil {
			return fmt.Errorf("retrieval shadow indisponível: %w", err)
		}
	}
	service := &assistantService{
		provider:              provider,
		model:                 model,
		baseURL:               baseURL,
		apiKey:                apiKey,
		agentURL:              strings.TrimRight(envDefault("AGENT_URL", "http://agent:9090"), "/"),
		agentToken:            string(agentToken),
		httpClient:            &http.Client{Timeout: 2 * time.Minute},
		agentClient:           &http.Client{Timeout: 12 * time.Second},
		knowledge:             knowledge,
		retriever:             retriever,
		shadowMode:            shadowMode,
		inspectionMode:        inspectionMode,
		promptMode:            promptMode,
		blueprintHomologation: blueprintHomologation,
	}
	zero(agentToken)
	if err := service.validateProvider(); err != nil {
		return fmt.Errorf("provedor de IA indisponível: %w", err)
	}

	authorize := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			provided := r.Header.Get("X-SetupMNO-Agent-Token")
			if len(provided) != len(service.agentToken) ||
				subtle.ConstantTimeCompare([]byte(provided), []byte(service.agentToken)) != 1 {
				writeError(w, http.StatusUnauthorized, "não autorizado")
				return
			}
			next(w, r)
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":                    "ok",
			"provider":                  service.provider,
			"model":                     service.model,
			"knowledgeVersion":          service.knowledge.Manifest.KnowledgeVersion,
			"knowledgeSource":           service.knowledge.Source,
			"knowledgeStale":            service.knowledge.Stale,
			"knowledgeEntries":          service.knowledge.Manifest.DocumentEntries,
			"blueprintFactoryVersion":   service.knowledge.Manifest.BlueprintFactoryVersion,
			"blueprintEntries":          service.knowledge.Manifest.BlueprintEntries,
			"blueprintKnowledgeEntries": service.knowledge.Manifest.BlueprintKnowledgeEntries,
			"blueprintFixtureEntries":   service.knowledge.Manifest.BlueprintFixtureEntries,
			"qualitySummary":            service.knowledge.Manifest.QualitySummary,
			"blueprintHomologation":     service.blueprintHomologation,
			"promptRegistry": map[string]any{
				"version":                 assistantPromptRegistryVersion,
				"promptVersion":           assistantPromptVersion,
				"responseContractVersion": assistantResponseContractVersion,
				"specialists":             len(assistantPromptDefinitions),
			},
			"retrievalShadow": map[string]any{
				"enabled":    service.shadowMode,
				"inspection": service.inspectionMode,
				"prompt":     service.promptMode,
				"version":    service.knowledge.Manifest.RetrievalVersion,
				"metrics":    service.retrievalSnapshot(),
			},
		})
	})
	mux.HandleFunc("POST /chat", authorize(service.handleChat))
	mux.HandleFunc("POST /evals/provider", authorize(service.handleProviderEval))

	server := &http.Server{
		Addr:              ":7070",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       20 * time.Second,
		WriteTimeout:      2 * time.Minute,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	log.Printf(
		"Assistente MNO iniciado na porta 7070 com provedor %s, retrieval shadow=%t, inspeção=%t e prompt=%t",
		provider,
		shadowMode,
		inspectionMode,
		promptMode,
	)
	return server.ListenAndServe()
}

func (s *assistantService) validateProvider() error {
	endpoint := strings.TrimRight(s.baseURL, "/")
	switch s.provider {
	case "openai":
		if !strings.HasSuffix(endpoint, "/v1") {
			endpoint += "/v1"
		}
		endpoint += "/models/" + url.PathEscape(s.model)
	case "openrouter", "deepseek":
		endpoint += "/models"
	default:
		endpoint = strings.TrimSuffix(endpoint, "/v1") + "/api/tags"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	if s.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+s.apiKey)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d ao validar modelo", resp.StatusCode)
	}
	if s.provider == "ollama" {
		var tags struct {
			Models []struct {
				Name  string `json:"name"`
				Model string `json:"model"`
			} `json:"models"`
		}
		if err := json.NewDecoder(io.LimitReader(resp.Body, 2<<20)).Decode(&tags); err != nil {
			return errors.New("resposta inválida do Ollama")
		}
		for _, candidate := range tags.Models {
			if candidate.Name == s.model || candidate.Model == s.model {
				return nil
			}
		}
		return fmt.Errorf("modelo %q não está baixado no Ollama", s.model)
	}
	if s.provider == "openrouter" || s.provider == "deepseek" {
		var models struct {
			Data []struct {
				ID string `json:"id"`
			} `json:"data"`
		}
		if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&models); err != nil {
			return errors.New("resposta inválida ao consultar os modelos do provedor")
		}
		for _, candidate := range models.Data {
			if candidate.ID == s.model {
				return nil
			}
		}
		return fmt.Errorf("modelo %q não foi encontrado no provedor", s.model)
	}
	return nil
}

func (s *assistantService) handleChat(w http.ResponseWriter, r *http.Request) {
	var input assistantRequest
	if err := decodeJSON(w, r, &input, maxBodyBytes); err != nil {
		return
	}
	if err := validateAssistantRequest(&input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	resolution := retrievalQueryResolution{Query: input.Question}
	if s.retriever != nil {
		resolution = s.retriever.resolveQuery(input.Question, input.History)
	}
	contextData, contextErr := s.collectContext(
		r.Context(), resolution.Query, resolution.CatalogName,
	)
	if contextErr != nil {
		log.Printf("Assistente MNO: contexto operacional indisponível; conhecimento canônico preservado: %v", contextErr)
		contextData = s.knowledgeOnlyContext()
	}
	route := routeAssistant(input.Question, resolution, contextData.Architecture)
	resolution.BlueprintRoute = route.Specialist == "blueprint_architect"
	resolution.SolutionRoute = route.Specialist == "solution_architect"
	var inspection *retrievalInspection
	var promptContext *retrievalPromptContext
	if s.shadowMode && s.retriever != nil {
		shadow := s.retriever.retrieveResolved(
			resolution,
			contextData.SetupVersion,
			contextData.Architecture,
		)
		if assistantCatalogContextAvailable(contextData) {
			shadow = s.retriever.attachCatalogEvidence(shadow, contextData)
		}
		s.recordRetrieval(shadow.Metrics)
		promptStatus := "feature-disabled"
		if s.promptMode {
			promptContext, promptStatus = buildRetrievalPrompt(
				shadow,
				retrievalPromptOptions{
					Quality:                     s.knowledge.Quality,
					Question:                    input.Question,
					AllowMissingCatalogEvidence: !assistantCatalogContextAvailable(contextData),
				},
			)
			if promptContext != nil && promptContext.Simulation &&
				(!s.blueprintHomologation || route.Specialist != "blueprint_architect") {
				promptContext = nil
				promptStatus = "blueprint-homologation-blocked"
			}
			if promptContext != nil && promptContext.Quality != nil &&
				promptContext.Quality.DeterministicAnswer {
				promptStatus = "quality-policy"
			}
		}
		if s.inspectionMode {
			snapshot := buildRetrievalInspection(
				shadow,
				contextData.SetupVersion,
				s.knowledge.Source,
				s.knowledge.Stale,
			)
			snapshot.PromptStatus = promptStatus
			if promptContext != nil &&
				(promptContext.Quality == nil || !promptContext.Quality.DeterministicAnswer) {
				snapshot.PromptSourceCount = len(promptContext.Sources)
				snapshot.PromptStatus = "citation-pending"
			}
			inspection = &snapshot
		}
	}

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	sendSSE(w, "meta", map[string]any{
		"mode":                        s.provider,
		"model":                       s.model,
		"knowledgeVersion":            s.knowledge.Manifest.KnowledgeVersion,
		"knowledgeSource":             s.knowledge.Source,
		"knowledgeStale":              s.knowledge.Stale,
		"knowledgeEntries":            s.knowledge.Manifest.DocumentEntries,
		"blueprintFactoryVersion":     s.knowledge.Manifest.BlueprintFactoryVersion,
		"blueprintEntries":            s.knowledge.Manifest.BlueprintEntries,
		"blueprintKnowledgeEntries":   s.knowledge.Manifest.BlueprintKnowledgeEntries,
		"blueprintFixtureEntries":     s.knowledge.Manifest.BlueprintFixtureEntries,
		"blueprintHomologation":       s.blueprintHomologation,
		"qualitySummary":              s.knowledge.Manifest.QualitySummary,
		"operationalContextAvailable": contextData.OperationalContextAvailable,
		"operationalContextWarning":   contextData.OperationalContextWarning,
	})
	sendSSE(w, "route", route)
	if inspection != nil {
		sendSSE(w, "retrieval", inspection)
	}
	if promptContext != nil && promptContext.Quality != nil {
		sendSSE(w, "quality", promptContext.Quality)
	}

	if promptContext != nil && promptContext.Simulation {
		sendSSE(w, "blueprint_simulation", map[string]any{
			"active":       true,
			"blueprintIds": promptContext.BlueprintIDs,
			"deployable":   false,
		})
		sendSSE(w, "delta", map[string]any{
			"delta": blueprintSimulationNotice + "\n\n",
		})
	}
	if promptContext != nil && promptContext.Quality != nil &&
		promptContext.Quality.DeterministicAnswer {
		answer := buildDeterministicQualityAnswer(*promptContext.Quality)
		sendSSE(w, "delta", map[string]any{"delta": answer})
		sendSSE(w, "done", map[string]any{
			"ok": true, "policy": "knowledge-quality",
		})
		return
	}
	if answer, ok := buildDeterministicEcosystemAnswer(input.Question, contextData); ok {
		sendSSE(w, "delta", map[string]any{"delta": answer})
		sendSSE(w, "done", map[string]any{
			"ok": true, "policy": "ecosystem-inventory",
		})
		return
	}
	answer, err := s.streamProvider(r.Context(), w, input, contextData, route, promptContext)
	if err != nil {
		sendSSE(w, "error", map[string]any{
			"error":  "O provedor de IA não concluiu a resposta.",
			"reason": "provider",
		})
		log.Printf("Assistente MNO: falha controlada no provedor %s: %v", s.provider, err)
		return
	}
	if promptContext != nil {
		sendSSE(w, "grounding", validateGroundingCitations(
			answer, len(promptContext.Sources),
		))
	}
	sendSSE(w, "done", map[string]any{"ok": true})
}

func ecosystemInventoryQuestion(question string) string {
	normalized := normalizeRetrievalPhrase(question)
	if normalized == "" {
		return ""
	}
	requestsCount := anyPhraseContained(normalized, []string{
		"quantos", "quantas", "quanto", "quanta", "total", "numero de", "quantidade de",
	})
	if requestsCount && anyPhraseContained(normalized, []string{"blueprint", "blueprints"}) {
		return "blueprints"
	}
	if requestsCount && anyPhraseContained(normalized, []string{"setup", "setups"}) &&
		!anyPhraseContained(normalized, []string{"documentado", "documentados", "homologado", "homologados", "cobertura"}) {
		return "setups"
	}
	if requestsCount && anyPhraseContained(normalized, []string{"aplicacao", "aplicacoes", "ferramenta", "ferramentas"}) &&
		!anyPhraseContained(normalized, []string{"documentada", "documentadas", "documentado", "documentados", "homologada", "homologadas"}) {
		if anyPhraseContained(normalized, []string{"instalada", "instaladas", "instalado", "instalados", "no servidor", "em execucao"}) {
			return "installed-applications"
		}
		return "applications"
	}
	if anyPhraseContained(normalized, []string{
		"diferenca entre aplicacao", "diferenca entre ferramenta", "diferenca entre setup",
		"aplicacao setup e blueprint", "ferramenta setup e blueprint",
		"o que e blueprint", "o que sao blueprints", "o que e um blueprint",
		"o que e setup no setup mno", "o que sao setups no setup mno",
	}) {
		return "taxonomy"
	}
	return ""
}

func buildDeterministicEcosystemAnswer(question string, contextData assistantContext) (string, bool) {
	subject := ecosystemInventoryQuestion(question)
	if subject == "" {
		return "", false
	}
	var answer strings.Builder
	answer.WriteString("**Conclusão**\n\n")
	switch subject {
	case "blueprints":
		fmt.Fprintf(&answer, "O Setup MNO possui atualmente **%d Blueprints**: **%d guias Beta** e **%d homologados**. ",
			contextData.BlueprintEntries, contextData.BlueprintBetaEntries, contextData.BlueprintHomologatedEntries)
		answer.WriteString("Eles são plantas baixas ou receitas digitais orientadas a um objetivo e não devem ser confundidos com os setups do catálogo.\n\n")
		answer.WriteString("**Diferença importante**\n\n")
		fmt.Fprintf(&answer, "Os **%d setups** são entradas instaláveis; não representam %d Blueprints. Um Blueprint pode combinar vários setups, configurações, integrações, validações, materiais e rollback em uma sequência guiada.\n\n",
			contextData.CanonicalSetupEntries, contextData.CanonicalSetupEntries)
		answer.WriteString("Você pode abrir a área **Blueprints** para visualizar os guias atuais e o passo a passo de cada um.")
	case "setups":
		fmt.Fprintf(&answer, "O catálogo canônico possui **%d setups instaláveis**. Um setup é uma entrada do instalador e pode representar uma aplicação individual, um utilitário, um banco de dados ou um combo com vários componentes.\n\n",
			contextData.CanonicalSetupEntries)
		if len(contextData.SetupTypeEntries) > 0 {
			answer.WriteString("**Tipos registrados no catálogo**\n\n")
			for _, kind := range []string{"Individual", "Combo", "Utilitário", "Banco de Dados"} {
				if count := contextData.SetupTypeEntries[kind]; count > 0 {
					fmt.Fprintf(&answer, "- **%s:** %d\n", kind, count)
				}
			}
			answer.WriteByte('\n')
		}
		fmt.Fprintf(&answer, "Blueprints são outro inventário: existem **%d**, e cada um pode orquestrar vários setups para entregar um sistema com finalidade definida.", contextData.BlueprintEntries)
	case "installed-applications":
		fmt.Fprintf(&answer, "O estado observado registra **%d aplicações ou stacks instaladas** acessíveis ao agente neste servidor. Esse número descreve o ambiente em execução e não o catálogo de %d setups disponíveis.\n\n",
			len(contextData.InstalledApps), contextData.CanonicalSetupEntries)
		answer.WriteString("Uma aplicação instalada pode possuir vários serviços Docker; por isso aplicações, serviços e containers também são contagens diferentes.")
	case "applications":
		answer.WriteString("O Setup MNO ainda não publica uma contagem canônica de **aplicações únicas**. O catálogo registra setups, e uma mesma aplicação pode aparecer em variantes ou combos diferentes; somar as entradas produziria um número incorreto.\n\n")
		fmt.Fprintf(&answer, "O que pode ser afirmado com exatidão hoje é: **%d setups instaláveis** e **%d Blueprints**. A futura normalização do registro de aplicações permitirá contar produtos únicos sem duplicar variantes e componentes de combos.",
			contextData.CanonicalSetupEntries, contextData.BlueprintEntries)
	case "taxonomy":
		answer.WriteString("No Setup MNO, **aplicação**, **setup** e **Blueprint** são conceitos diferentes e complementares.\n\n")
		answer.WriteString("- **Aplicação ou ferramenta:** produto de software que entrega uma capacidade, como automação, CRM, banco de dados ou observabilidade.\n")
		answer.WriteString("- **Setup:** unidade instalável do catálogo. Pode instalar uma aplicação, uma variante específica, um utilitário ou um combo de aplicações e dependências.\n")
		answer.WriteString("- **Blueprint:** planta baixa ou receita digital orientada a um resultado. Combina setups, ordem de instalação, configurações, integrações, validações, materiais e rollback.\n")
		answer.WriteString("- **Microssistema:** solução funcional resultante da aplicação de um Blueprint ou de uma arquitetura guiada, criada para resolver uma dor concreta.\n\n")
		fmt.Fprintf(&answer, "O inventário atual contém **%d setups** e **%d Blueprints**. Eles nunca devem ser somados ou tratados como a mesma coisa.",
			contextData.CanonicalSetupEntries, contextData.BlueprintEntries)
	}
	return answer.String(), true
}

const blueprintSimulationNotice = "⚠️ **Simulação de homologação:** esta análise usa um Blueprint fictício e não implantável para testar o mesmo fluxo RAG da produção. Ela não autoriza deploy."

func buildDeterministicQualityAnswer(quality retrievalQualityContext) string {
	names := strings.Join(quality.CatalogNames, ", ")
	if names == "" {
		names = strings.Join(quality.SetupIDs, ", ")
	}
	var answer strings.Builder
	answer.WriteString("**Conclusão**\n\n")
	answer.WriteString("A instalação de **")
	answer.WriteString(names)
	answer.WriteString("** pelo Setup MNO está **homologada pelo mantenedor**")
	if len(quality.TestedArchitectures) > 0 {
		answer.WriteString(" para **")
		answer.WriteString(strings.Join(quality.TestedArchitectures, " e "))
		answer.WriteString("**")
	}
	answer.WriteString(". Essa garantia do instalador é independente do nível de detalhe da documentação.\n\n")
	if quality.DefinitiveAnswerBlocked {
		answer.WriteString("Não consigo confirmar com segurança **o detalhe específico da pergunta**, porque a base de conhecimento registra uma informação ausente ou divergente. Isso não invalida o instalador.\n\n")
		answer.WriteString("**Ponto que precisa de confirmação**\n\n")
		for _, issue := range quality.BlockingIssueLabels {
			answer.WriteString("• ")
			answer.WriteString(issue)
			answer.WriteByte('\n')
		}
	} else {
		answer.WriteString("O conteúdo disponível está no nível **")
		answer.WriteString(quality.MaturityLabel)
		answer.WriteString("**. ")
		answer.WriteString(quality.ClaimPolicy)
		answer.WriteString("\n")
	}
	answer.WriteString("\n**Situação das três camadas**\n\n")
	answer.WriteString("• Instalação: **")
	answer.WriteString(quality.InstallationLabel)
	answer.WriteString("**\n")
	answer.WriteString("• Conhecimento: **")
	answer.WriteString(quality.MaturityLabel)
	answer.WriteString("**\n")
	answer.WriteString("• Integrações: **")
	answer.WriteString(quality.IntegrationLabel)
	answer.WriteString("**\n")
	if len(quality.IssueLabels) > 0 {
		answer.WriteString("• Pontos documentais em revisão: ")
		answer.WriteString(strings.Join(quality.IssueLabels, "; "))
		answer.WriteByte('\n')
	}
	answer.WriteString("\n**Próximo passo**\n\n")
	if quality.DefinitiveAnswerBlocked {
		answer.WriteString("Você pode usar o Instalador Seguro para o deploy homologado. Para decidir capacidade, arquitetura ou configuração com base no detalhe divergente, consulte a indicação exibida no catálogo ou peça ao suporte a confirmação específica.")
	} else {
		answer.WriteString("Se quiser instalar, abra o Instalador Seguro. Se quiser combinar esta ferramenta com outras, descreva o objetivo para receber uma sugestão consultiva de arquitetura.")
	}
	return answer.String()
}

func validateAssistantRequest(input *assistantRequest) error {
	input.Question = strings.TrimSpace(input.Question)
	if len(input.Question) < 3 {
		return errors.New("descreva o que deseja analisar")
	}
	if len(input.Question) > 2000 {
		return errors.New("pergunta muito longa")
	}
	if len(input.History) > 10 {
		input.History = input.History[len(input.History)-10:]
	}
	validHistory := input.History[:0]
	for _, message := range input.History {
		message.Role = strings.ToLower(strings.TrimSpace(message.Role))
		message.Content = strings.TrimSpace(message.Content)
		if (message.Role != "user" && message.Role != "assistant") ||
			message.Content == "" || len(message.Content) > 4000 {
			continue
		}
		validHistory = append(validHistory, message)
	}
	input.History = validHistory
	if !input.Basic {
		input.FallbackReason = ""
	} else {
		switch input.FallbackReason {
		case "provider", "context", "connector":
		default:
			input.FallbackReason = "connector"
		}
	}
	return nil
}

func (s *assistantService) collectContext(
	ctx context.Context,
	question string,
	exactCatalogName string,
) (assistantContext, error) {
	var current overview
	var appsPayload struct {
		Apps []appSummary `json:"apps"`
	}
	var setupState setupStateResponse
	var catalog catalogResponse
	type callResult struct {
		name string
		err  error
	}
	results := make(chan callResult, 4)
	requestErrors := make(map[string]error, 4)
	requests := []struct {
		name     string
		endpoint string
		target   any
	}{
		{"overview", "/overview", &current},
		{"apps", "/apps", &appsPayload},
		{"setup-state", "/setup-state", &setupState},
		{"catalog", "/catalog", &catalog},
	}
	for _, request := range requests {
		request := request
		go func() {
			results <- callResult{request.name, s.agentRequest(ctx, request.endpoint, request.target)}
		}()
	}
	for range requests {
		result := <-results
		if result.err != nil {
			requestErrors[result.name] = result.err
		}
	}
	if err := requestErrors["overview"]; err != nil {
		return assistantContext{}, fmt.Errorf("overview: %w", err)
	}

	warnings := make([]string, 0, 2)
	installed := make([]assistantApp, 0)
	if err := requestErrors["apps"]; err != nil {
		log.Printf("Assistente MNO: lista de aplicações indisponível; métricas preservadas: %v", err)
		warnings = append(warnings, "A lista de aplicações está temporariamente indisponível.")
	} else {
		installed = make([]assistantApp, 0, min(len(appsPayload.Apps), 60))
		for _, app := range appsPayload.Apps {
			if len(installed) == 60 {
				break
			}
			installed = append(installed, assistantApp{
				Name: app.Name, Status: app.Status, Running: app.Running, Desired: app.Desired,
			})
		}
	}

	catalogAvailable := requestErrors["setup-state"] == nil && requestErrors["catalog"] == nil
	if catalogAvailable {
		if err := validateAssistantCatalog(setupState, catalog); err != nil {
			requestErrors["catalog-validation"] = err
			catalogAvailable = false
		}
	}
	if !catalogAvailable {
		for _, name := range []string{"setup-state", "catalog", "catalog-validation"} {
			if err := requestErrors[name]; err != nil {
				log.Printf("Assistente MNO: %s indisponível; métricas preservadas: %v", name, err)
			}
		}
		warnings = append(warnings, "As métricas do servidor estão disponíveis, mas o catálogo runtime está temporariamente indisponível; a orientação usa o pacote canônico de conhecimento.")
	}

	available := uint64(0)
	if current.Metrics.MemoryTotal > current.Metrics.MemoryUsed {
		available = current.Metrics.MemoryTotal - current.Metrics.MemoryUsed
	}
	architecture := current.Architecture
	if architecture == "" {
		architecture = "unknown"
	}
	contextData := assistantContext{
		OperationalContextAvailable: true,
		OperationalContextWarning:   strings.Join(warnings, " "),
		SetupVersion:                s.knowledge.Manifest.SetupVersion,
		CatalogSource:               "unavailable",
		CatalogStale:                true,
		Architecture:                architecture,
		OperatingSystem:             current.OperatingSystem,
		OSVersion:                   current.OSVersion,
		OSType:                      current.OSType,
		KernelVersion:               current.KernelVersion,
		EngineVersion:               current.EngineVersion,
		CPUPercent:                  current.Metrics.CPUPercent,
		MemoryPercent:               current.Metrics.MemoryPercent,
		MemoryAvailableGB:           round(float64(available) / float64(1<<30)),
		DiskPercent:                 current.Metrics.DiskPercent,
		Services:                    current.Services,
		DegradedServices:            current.DegradedServices,
		SwarmNodes:                  current.SwarmNodes,
		InstalledApps:               installed,
	}
	if catalogAvailable {
		relevantSetups := relevantCatalogItems(catalog.Items, question, exactCatalogName, 12)
		contextData.SetupVersion = setupState.SetupVersion
		contextData.CatalogVersion = catalog.CatalogVersion
		contextData.CatalogSHA256 = catalog.CatalogSHA256
		contextData.CatalogEntries = catalog.CatalogEntries
		contextData.CatalogSource = catalog.Source
		contextData.CatalogStale = catalog.Stale
		contextData.Architecture = setupState.Architecture
		contextData.RelevantSetupCount = len(relevantSetups)
		contextData.RelevantSetups = relevantSetups
	}
	return s.attachKnowledgeInventory(contextData, catalog.Items), nil
}

func (s *assistantService) knowledgeOnlyContext() assistantContext {
	return s.attachKnowledgeInventory(assistantContext{
		OperationalContextAvailable: false,
		OperationalContextWarning:   "Métricas e catálogo runtime temporariamente indisponíveis; a resposta usa somente o pacote canônico de conhecimento.",
		SetupVersion:                s.knowledge.Manifest.SetupVersion,
		CatalogSource:               "unavailable",
		CatalogStale:                true,
		Architecture:                "unknown",
	}, nil)
}

func (s *assistantService) attachKnowledgeInventory(contextData assistantContext, catalogItems []json.RawMessage) assistantContext {
	contextData.KnowledgeDocumentEntries = s.knowledge.Manifest.DocumentEntries
	contextData.CanonicalSetupEntries = s.knowledge.Manifest.SetupEntries
	contextData.InfrastructureEntries = s.knowledge.Manifest.InfrastructureEntries
	contextData.BlueprintEntries = s.knowledge.Manifest.BlueprintEntries
	contextData.BlueprintBetaEntries = s.knowledge.Blueprints.Statuses["reviewed"]
	contextData.BlueprintHomologatedEntries = s.knowledge.Blueprints.Statuses["homologated"]
	contextData.ApplicationInventoryStatus = "not-normalized"
	if len(catalogItems) == 0 {
		return contextData
	}
	typeEntries := make(map[string]int)
	for _, raw := range catalogItems {
		var item struct {
			Type string `json:"type"`
		}
		if json.Unmarshal(raw, &item) == nil && strings.TrimSpace(item.Type) != "" {
			typeEntries[strings.TrimSpace(item.Type)]++
		}
	}
	contextData.SetupTypeEntries = typeEntries
	return contextData
}

func validateAssistantCatalog(state setupStateResponse, catalog catalogResponse) error {
	if state.SetupVersion == "" || catalog.SetupVersion == "" ||
		state.SetupVersion != catalog.SetupVersion ||
		state.CatalogVersion != catalog.CatalogVersion ||
		state.CatalogSHA256 != catalog.CatalogSHA256 ||
		state.CatalogEntries != catalog.CatalogEntries ||
		state.Architecture != catalog.Architecture ||
		catalog.CatalogEntries != len(catalog.Items) {
		return errors.New("manifesto e catálogo divergentes durante a coleta do contexto")
	}
	return nil
}

func assistantCatalogContextAvailable(contextData assistantContext) bool {
	return contextData.CatalogSource != "" && contextData.CatalogSource != "unavailable" &&
		validEvidenceSHA256(contextData.CatalogSHA256)
}

func (s *assistantService) agentRequest(ctx context.Context, endpoint string, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.agentURL+endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("X-SetupMNO-Agent-Token", s.agentToken)
	resp, err := s.agentClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("agente retornou HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(target)
}

func relevantCatalogItems(
	items []json.RawMessage,
	question string,
	exactCatalogName string,
	limit int,
) []map[string]any {
	type scoredItem struct {
		score int
		item  map[string]any
	}
	terms := assistantSearchTerms(question)
	scored := make([]scoredItem, 0, len(items))
	for _, raw := range items {
		var item map[string]any
		if json.Unmarshal(raw, &item) != nil {
			continue
		}
		name := strings.ToLower(fmt.Sprint(item["name"]))
		searchable := strings.ToLower(strings.Join([]string{
			name,
			fmt.Sprint(item["cats"]),
			fmt.Sprint(item["desc"]),
			fmt.Sprint(item["search"]),
		}, " "))
		score := 0
		if exactCatalogName != "" && strings.EqualFold(name, strings.ToLower(exactCatalogName)) {
			score += 1000
		}
		for _, term := range terms {
			if strings.Contains(name, term) {
				score += 4
			} else if strings.Contains(searchable, term) {
				score++
			}
		}
		if score > 0 {
			delete(item, "search")
			delete(item, "stars")
			scored = append(scored, scoredItem{score: score, item: item})
		}
	}
	for i := 0; i < len(scored); i++ {
		for j := i + 1; j < len(scored); j++ {
			if scored[j].score > scored[i].score ||
				(scored[j].score == scored[i].score &&
					fmt.Sprint(scored[j].item["name"]) < fmt.Sprint(scored[i].item["name"])) {
				scored[i], scored[j] = scored[j], scored[i]
			}
		}
	}
	if len(scored) > limit {
		scored = scored[:limit]
	}
	result := make([]map[string]any, 0, len(scored))
	for _, candidate := range scored {
		result = append(result, candidate.item)
	}
	return result
}

func assistantSearchTerms(question string) []string {
	stopWords := map[string]bool{
		"para": true, "como": true, "qual": true, "quais": true, "posso": true,
		"pode": true, "uma": true, "um": true, "que": true, "com": true,
		"setup": true, "aplicacao": true, "aplicação": true, "instalar": true,
		"servidor": true, "mno": true, "meu": true, "minha": true,
	}
	seen := make(map[string]bool)
	var terms []string
	for _, term := range strings.FieldsFunc(strings.ToLower(question), func(r rune) bool {
		return !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9') &&
			r != 'á' && r != 'à' && r != 'ã' && r != 'â' && r != 'é' &&
			r != 'ê' && r != 'í' && r != 'ó' && r != 'ô' && r != 'õ' &&
			r != 'ú' && r != 'ç'
	}) {
		if len([]rune(term)) < 3 || stopWords[term] || seen[term] {
			continue
		}
		seen[term] = true
		terms = append(terms, term)
	}
	return terms
}

func (s *assistantService) streamProvider(
	ctx context.Context,
	w http.ResponseWriter,
	input assistantRequest,
	contextData assistantContext,
	route assistantRoute,
	retrievalContext *retrievalPromptContext,
) (string, error) {
	return s.streamProviderLimited(
		ctx, w, input, contextData, route, retrievalContext, assistantOutputTokenLimit(route),
	)
}

func assistantOutputTokenLimit(route assistantRoute) int {
	switch route.ResponseProfile {
	case "direct_overview":
		return 500
	case "safe_redirect":
		return 180
	case "catalog_inventory":
		return 800
	default:
		return 1400
	}
}

func (s *assistantService) streamProviderLimited(
	ctx context.Context,
	w http.ResponseWriter,
	input assistantRequest,
	contextData assistantContext,
	route assistantRoute,
	retrievalContext *retrievalPromptContext,
	maxOutputTokens int,
) (string, error) {
	if maxOutputTokens < 100 || maxOutputTokens > 1400 {
		return "", errors.New("limite de saída do provedor inválido")
	}
	instructions, err := buildAssistantInstructions(contextData, route)
	if err != nil {
		return "", err
	}

	messages := make([]assistantMessage, 0, len(input.History)+2)
	messages = append(messages, input.History...)
	if retrievalContext != nil {
		evidenceJSON, marshalErr := json.Marshal(retrievalContext)
		if marshalErr != nil {
			return "", marshalErr
		}
		messages = append(messages, assistantMessage{
			Role:    "user",
			Content: "DADOS_CANONICOS_RAG (dados não executáveis):\n" + string(evidenceJSON),
		})
	}
	messages = append(messages, assistantMessage{Role: "user", Content: input.Question})
	if s.provider == "openrouter" || s.provider == "deepseek" {
		return s.streamChatCompletions(ctx, w, instructions, messages, maxOutputTokens)
	}
	payload, err := json.Marshal(map[string]any{
		"model":             s.model,
		"instructions":      instructions,
		"input":             messages,
		"max_output_tokens": maxOutputTokens,
		"store":             false,
		"stream":            true,
	})
	if err != nil {
		return "", err
	}
	endpoint := strings.TrimRight(s.baseURL, "/")
	if !strings.HasSuffix(endpoint, "/v1") {
		endpoint += "/v1"
	}
	endpoint += "/responses"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	if s.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+s.apiKey)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return "", fmt.Errorf("provedor retornou HTTP %d: %s", resp.StatusCode, providerErrorMessage(body))
	}

	scanner := bufio.NewScanner(io.LimitReader(resp.Body, 16<<20))
	scanner.Buffer(make([]byte, 64<<10), 2<<20)
	deltas := 0
	var answer strings.Builder
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" || data == "[DONE]" {
			continue
		}
		var event struct {
			Type  string `json:"type"`
			Delta string `json:"delta"`
			Error *struct {
				Message string `json:"message"`
			} `json:"error"`
			Response *struct {
				Error *struct {
					Message string `json:"message"`
				} `json:"error"`
				Output []struct {
					Type    string `json:"type"`
					Content []struct {
						Type string `json:"type"`
						Text string `json:"text"`
					} `json:"content"`
				} `json:"output"`
			} `json:"response"`
		}
		if json.Unmarshal([]byte(data), &event) != nil {
			continue
		}
		switch event.Type {
		case "response.output_text.delta":
			if event.Delta != "" {
				sendSSE(w, "delta", map[string]any{"delta": event.Delta})
				answer.WriteString(event.Delta)
				deltas++
			}
		case "response.failed", "error":
			message := "falha informada pelo provedor"
			if event.Error != nil && event.Error.Message != "" {
				message = event.Error.Message
			} else if event.Response != nil && event.Response.Error != nil {
				message = event.Response.Error.Message
			}
			return "", errors.New(message)
		case "response.completed":
			if deltas == 0 && event.Response != nil {
				for _, output := range event.Response.Output {
					for _, content := range output.Content {
						if content.Type == "output_text" && content.Text != "" {
							sendSSE(w, "delta", map[string]any{"delta": content.Text})
							answer.WriteString(content.Text)
							deltas++
						}
					}
				}
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if deltas == 0 {
		return "", errors.New("provedor não retornou texto")
	}
	return strings.TrimSpace(answer.String()), nil
}

func (s *assistantService) streamChatCompletions(
	ctx context.Context,
	w http.ResponseWriter,
	instructions string,
	messages []assistantMessage,
	maxOutputTokens int,
) (string, error) {
	providerMessages := make([]assistantMessage, 0, len(messages)+1)
	providerMessages = append(providerMessages, assistantMessage{
		Role:    "system",
		Content: instructions,
	})
	providerMessages = append(providerMessages, messages...)
	payload, err := json.Marshal(map[string]any{
		"model":      s.model,
		"messages":   providerMessages,
		"max_tokens": maxOutputTokens,
		"stream":     true,
	})
	if err != nil {
		return "", err
	}
	endpoint := strings.TrimRight(s.baseURL, "/") + "/chat/completions"
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		endpoint,
		bytes.NewReader(payload),
	)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return "", fmt.Errorf(
			"provedor retornou HTTP %d: %s",
			resp.StatusCode,
			providerErrorMessage(body),
		)
	}

	scanner := bufio.NewScanner(io.LimitReader(resp.Body, 16<<20))
	scanner.Buffer(make([]byte, 64<<10), 2<<20)
	deltas := 0
	var answer strings.Builder
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" || data == "[DONE]" {
			continue
		}
		var event struct {
			Choices []struct {
				Delta struct {
					Content string `json:"content"`
				} `json:"delta"`
			} `json:"choices"`
			Error *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal([]byte(data), &event) != nil {
			continue
		}
		if event.Error != nil {
			if event.Error.Message != "" {
				return "", errors.New(event.Error.Message)
			}
			return "", errors.New("falha informada pelo provedor")
		}
		for _, choice := range event.Choices {
			if choice.Delta.Content != "" {
				sendSSE(w, "delta", map[string]any{"delta": choice.Delta.Content})
				answer.WriteString(choice.Delta.Content)
				deltas++
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if deltas == 0 {
		return "", errors.New("provedor não retornou texto")
	}
	return strings.TrimSpace(answer.String()), nil
}

func providerErrorMessage(data []byte) string {
	var response struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(data, &response) == nil && response.Error.Message != "" {
		return response.Error.Message
	}
	return "resposta inválida"
}

func sendSSE(w http.ResponseWriter, event string, value any) {
	data, err := json.Marshal(value)
	if err != nil {
		return
	}
	_, _ = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, data)
	if flusher, ok := w.(http.Flusher); ok {
		flusher.Flush()
	}
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
	accessSubject := ""
	accessEmail := ""
	if identity := accessIdentityFromContext(r.Context()); identity != nil {
		accessSubject = identity.Subject
		accessEmail = identity.Email
	}
	a.sessionMu.Lock()
	a.sessions[id] = &session{
		User:          a.adminUser,
		CSRF:          csrf,
		AccessSubject: accessSubject,
		AccessEmail:   accessEmail,
		Expires:       now.Add(absoluteSessionTTL),
		IdleUntil:     now.Add(panelIdleTimeout),
		LastSeen:      now,
	}
	a.sessionMu.Unlock()

	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    id,
		Path:     "/",
		MaxAge:   int(absoluteSessionTTL.Seconds()),
		HttpOnly: true,
		Secure:   a.cookieSecure,
		SameSite: http.SameSiteStrictMode,
	})
	a.addAudit("login_success", "Sessão administrativa iniciada", address)
	writeJSON(w, http.StatusOK, map[string]any{
		"authenticated":  true,
		"user":           a.adminUser,
		"csrfToken":      csrf,
		"version":        a.version,
		"controlVersion": a.version,
		"assistantMode":  a.assistantMode,
		"assistantModel": a.assistantModel,
		"accessEmail":    accessEmail,
		"idleExpiresAt":  now.Add(panelIdleTimeout).UTC(),
	})
}

// handleTerminalReauth creates a short-lived authorization only for the
// Terminal Seguro. The password is checked locally against the same Docker
// Secret used at login and is never passed to the terminal service.
func (a *webApp) handleTerminalReauth(w http.ResponseWriter, r *http.Request) {
	if !a.terminalAccessAllowed(r.Context()) {
		a.addAudit("terminal_blocked_installation_type", "Terminal Seguro bloqueado: requer Cloudflare Tunnel", clientAddress(r))
		writeError(w, http.StatusForbidden, "recurso disponível apenas quando é usado Cloudflare Tunnel")
		return
	}
	address := clientAddress(r)
	if wait := a.loginBlocked(address); wait > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(wait.Seconds()))))
		writeError(w, http.StatusTooManyRequests, "muitas tentativas; aguarde antes de tentar novamente")
		return
	}

	var input struct {
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &input, 4096); err != nil {
		return
	}
	candidate := pbkdf2SHA256([]byte(input.Password), a.passwordSalt, 310000, 32)
	input.Password = ""
	passOK := subtle.ConstantTimeCompare(candidate, a.passwordHash) == 1
	zero(candidate)
	if !passOK {
		a.recordLoginFailure(address)
		a.addAudit("terminal_reauth_failed", "Confirmação do Terminal Seguro recusada", address)
		time.Sleep(350 * time.Millisecond)
		writeError(w, http.StatusUnauthorized, "senha administrativa inválida")
		return
	}

	cookie, err := r.Cookie(sessionCookie)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "sessão expirada")
		return
	}
	now := time.Now()
	a.sessionMu.Lock()
	s, ok := a.sessions[cookie.Value]
	if ok {
		s.TerminalUntil = now.Add(2 * time.Minute)
		s.IdleUntil = now.Add(terminalIdleTimeout)
		s.LastSeen = now
	}
	a.sessionMu.Unlock()
	if !ok {
		writeError(w, http.StatusUnauthorized, "sessão expirada")
		return
	}
	a.clearLoginFailures(address)
	a.addAudit("terminal_reauth_success", "Terminal Seguro autorizado por 2 minutos", address)
	writeJSON(w, http.StatusOK, map[string]any{
		"authorized": true,
		"expiresAt":  now.Add(2 * time.Minute).UTC(),
	})
}

func (a *webApp) handleSession(w http.ResponseWriter, r *http.Request) {
	s := sessionFromContext(r.Context())
	writeJSON(w, http.StatusOK, map[string]any{
		"authenticated":  true,
		"user":           s.User,
		"csrfToken":      s.CSRF,
		"expiresAt":      s.Expires.UTC(),
		"version":        a.version,
		"controlVersion": a.version,
		"assistantMode":  a.assistantMode,
		"assistantModel": a.assistantModel,
		"accessEmail":    s.AccessEmail,
		"idleExpiresAt":  s.IdleUntil.UTC(),
	})
}

// handleSessionActivity is the only endpoint that extends inactivity time.
// Background inventory polling deliberately does not keep an abandoned
// browser authenticated. Terminal output/input may request the longer window;
// disconnecting the browser never terminates the persistent tmux job.
func (a *webApp) handleSessionActivity(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Terminal bool `json:"terminal"`
	}
	if err := decodeJSON(w, r, &input, 1024); err != nil {
		return
	}
	cookie, err := r.Cookie(sessionCookie)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "sessão expirada")
		return
	}
	now := time.Now()
	idleTimeout := panelIdleTimeout
	if input.Terminal {
		idleTimeout = terminalIdleTimeout
	}
	a.sessionMu.Lock()
	s, ok := a.sessions[cookie.Value]
	if ok {
		s.LastSeen = now
		s.IdleUntil = now.Add(idleTimeout)
	}
	a.sessionMu.Unlock()
	if !ok {
		writeError(w, http.StatusUnauthorized, "sessão expirada")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"active":        true,
		"idleExpiresAt": now.Add(idleTimeout).UTC(),
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

func (a *webApp) handleSetupState(w http.ResponseWriter, r *http.Request) {
	var result setupStateResponse
	if err := a.agentRequest(r.Context(), "/setup-state", &result); err == nil {
		result.ControlVersion = a.version
		writeJSON(w, http.StatusOK, result)
		return
	}

	fallback, err := embeddedCatalogResponse()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "estado do Setup MNO indisponível")
		return
	}
	a.addAudit("setup_state_fallback", "Manifesto runtime indisponível; versão não confirmada", clientAddress(r))
	writeJSON(w, http.StatusOK, setupStateResponse{
		SchemaVersion:  runtimeSchema,
		SetupVersion:   "indisponível",
		ControlVersion: a.version,
		CatalogVersion: "embutido",
		CatalogSHA256:  fallback.CatalogSHA256,
		CatalogEntries: fallback.CatalogEntries,
		Source:         "embedded",
		Stale:          true,
		Warning:        "Não foi possível validar a versão instalada. Exibindo o catálogo de contingência do Control Center.",
	})
}

func (a *webApp) handleCatalog(w http.ResponseWriter, r *http.Request) {
	var result catalogResponse
	if err := a.agentRequest(r.Context(), "/catalog", &result); err == nil {
		writeJSON(w, http.StatusOK, result)
		return
	}

	fallback, err := embeddedCatalogResponse()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "catálogo indisponível")
		return
	}
	a.addAudit("catalog_fallback", "Catálogo runtime inválido ou indisponível; contingência ativada", clientAddress(r))
	writeJSON(w, http.StatusOK, fallback)
}

func (a *webApp) handleQuality(w http.ResponseWriter, r *http.Request) {
	var result knowledgeQualityResponse
	if err := a.agentRequest(r.Context(), "/quality", &result); err == nil &&
		result.Source == "runtime-read-only" &&
		result.SetupVersion != "" &&
		len(result.Entries) == result.Summary.SetupEntries {
		writeJSON(w, http.StatusOK, result)
		return
	}

	a.addAudit(
		"quality_fallback",
		"Relatório runtime de homologação indisponível; contingência ativada",
		clientAddress(r),
	)
	writeJSON(w, http.StatusOK, knowledgeQualityResponse{
		knowledgeQualityReport: a.quality,
		Source:                 "control-image-fallback",
		Stale:                  true,
		Warning:                "O selo exibido pertence ao pacote embutido no Control Center.",
	})
}

func (a *webApp) handleBlueprints(w http.ResponseWriter, r *http.Request) {
	catalog, err := a.runtimeBlueprintCatalog(r.Context())
	if err == nil {
		writeJSON(w, http.StatusOK, catalog)
		return
	}
	fallback := a.blueprints
	fallback.Source = "control-image-fallback"
	a.addAudit("blueprint_fallback", "Índice runtime de Blueprints indisponível; contingência ativada", clientAddress(r))
	writeJSON(w, http.StatusOK, fallback)
}

func (a *webApp) handleBlueprintDownload(w http.ResponseWriter, r *http.Request) {
	blueprintID := r.PathValue("blueprintId")
	if !validBlueprintID(blueprintID) {
		writeError(w, http.StatusNotFound, "Blueprint não encontrado")
		return
	}
	bundle, status, err := a.agentBlueprintDownload(r.Context(), blueprintID)
	if err != nil {
		if status == http.StatusNotFound {
			writeError(w, http.StatusNotFound, "Blueprint não encontrado")
			return
		}
		writeError(w, http.StatusServiceUnavailable, "bundle runtime de Blueprint indisponível")
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", `attachment; filename="`+bundle.Filename+`"`)
	w.Header().Set("X-Content-SHA256", bundle.SHA256)
	a.addAudit("blueprint_download", "Bundle Beta baixado: "+blueprintID, clientAddress(r))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(bundle.Data)
}

func (a *webApp) handleEvals(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, a.evals)
}

func blueprintCatalogFromKnowledge(state knowledgePackageState) (blueprintCatalogResponse, error) {
	index := state.Blueprints
	if index.SchemaVersion != blueprintSchema ||
		index.FactoryVersion != state.Manifest.BlueprintFactoryVersion ||
		index.SetupVersion != state.Manifest.SetupVersion ||
		index.BlueprintCount != state.Manifest.BlueprintEntries ||
		len(index.Entries) != state.Manifest.BlueprintEntries {
		return blueprintCatalogResponse{}, errors.New("índice incompatível com o pacote validado")
	}

	response := blueprintCatalogResponse{
		SchemaVersion:    index.SchemaVersion,
		FactoryVersion:   index.FactoryVersion,
		SetupVersion:     index.SetupVersion,
		KnowledgeVersion: state.Manifest.KnowledgeVersion,
		IndexSHA256:      state.Manifest.BlueprintIndexSHA256,
		Source:           state.Source,
		BlueprintCount:   index.BlueprintCount,
		ExampleCount:     index.Statuses["example"],
		BetaCount:        index.Statuses["reviewed"],
		HomologatedCount: index.Statuses["homologated"],
		ReviewCount:      index.Statuses["draft"] + index.Statuses["deprecated"],
		Items:            make([]blueprintCatalogItem, 0, len(index.Entries)),
	}
	for _, entry := range index.Entries {
		media := make([]blueprintMediaSummary, 0, len(entry.Media))
		for _, item := range entry.Media {
			media = append(media, blueprintMediaSummary{
				MediaID:       item.MediaID,
				Type:          item.Type,
				Title:         item.Title,
				Status:        item.Status,
				HasTranscript: item.Transcript != nil,
				URL:           item.URL,
			})
		}
		response.Items = append(response.Items, blueprintCatalogItem{
			Aliases:           append([]string(nil), entry.Aliases...),
			Architectures:     append([]string(nil), entry.Architectures...),
			Author:            entry.Author,
			BlueprintID:       entry.BlueprintID,
			BlueprintVersion:  entry.BlueprintVersion,
			BundleBytes:       entry.BundleBytes,
			BundleSHA256:      entry.BundleSHA256,
			Components:        append([]string(nil), entry.Components...),
			ComponentDetails:  append([]blueprintComponentDetail(nil), entry.ComponentDetails...),
			Deployable:        entry.Deployable,
			Editorial:         entry.Editorial,
			Fictitious:        entry.Fictitious,
			Media:             media,
			Installation:      entry.Installation,
			Validation:        entry.Validation,
			Rollback:          entry.Rollback,
			DownloadAvailable: true,
			Objective:         entry.Objective,
			ResourceProfile:   entry.ResourceProfile,
			Risk:              entry.Risk,
			Status:            entry.Status,
			Summary:           entry.Summary,
			Tags:              append([]string(nil), entry.Tags...),
			Title:             entry.Title,
			UpdatedAt:         entry.UpdatedAt,
		})
	}
	return response, nil
}

func blueprintBundlesFromKnowledge(state knowledgePackageState) (map[string]blueprintBundleDownload, error) {
	bundles := make(map[string]blueprintBundleDownload, len(state.Blueprints.Entries))
	for _, entry := range state.Blueprints.Entries {
		data, ok := state.Files[entry.BundlePath]
		if !ok || int64(len(data)) != entry.BundleBytes || sha256String(data) != entry.BundleSHA256 {
			return nil, fmt.Errorf("bundle do Blueprint %s inválido", entry.BlueprintID)
		}
		bundles[entry.BlueprintID] = blueprintBundleDownload{
			Filename: entry.BlueprintID + "-v" + entry.BlueprintVersion + ".zip",
			SHA256:   entry.BundleSHA256,
			Data:     append([]byte(nil), data...),
		}
	}
	return bundles, nil
}

func loadRuntimeBlueprintKnowledge(setupStateDir string) (knowledgePackageState, error) {
	snapshot, err := readRuntimeSnapshot(setupStateDir)
	if err != nil {
		return knowledgePackageState{}, err
	}
	state, err := loadKnowledgePackageDirectory(filepath.Join(setupStateDir, "knowledge-package"))
	if err != nil {
		return knowledgePackageState{}, err
	}
	if state.Manifest.SetupVersion != snapshot.Release.SetupVersion ||
		state.Manifest.ArchiveSHA256 != snapshot.Release.KnowledgeArchiveSHA256 ||
		state.Manifest.BlueprintIndexSHA256 != snapshot.Release.BlueprintIndexSHA256 {
		return knowledgePackageState{}, errors.New("pacote de Blueprints diverge do manifesto runtime")
	}
	state.Source = "runtime-read-only"
	state.Stale = false
	return state, nil
}

func validBlueprintID(value string) bool {
	if len(value) < 3 || len(value) > 128 {
		return false
	}
	for _, character := range value {
		if (character < 'a' || character > 'z') &&
			(character < '0' || character > '9') && character != '-' {
			return false
		}
	}
	return true
}

func (a *webApp) handleAudit(w http.ResponseWriter, r *http.Request) {
	limit := 50
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100 {
			writeError(w, http.StatusBadRequest, "limite de auditoria inválido")
			return
		}
		limit = parsed
	}
	var before uint64
	if raw := r.URL.Query().Get("before"); raw != "" {
		parsed, err := strconv.ParseUint(raw, 10, 64)
		if err != nil || parsed == 0 {
			writeError(w, http.StatusBadRequest, "cursor de auditoria inválido")
			return
		}
		before = parsed
	}
	a.auditMu.Lock()
	events, pagination := auditPage(a.audit.Events, before, limit)
	integrity := auditIntegrity{
		Status: "verified", PolicyVersion: auditPolicyVersion,
		AnchorSequence: a.audit.AnchorSequence, RetainedEvents: len(a.audit.Events),
		RetentionDays: int(auditRetention / (24 * time.Hour)), ChainHead: auditChainHead(a.audit),
		PersistenceStatus: "healthy",
	}
	if a.audit.LastError != "" {
		integrity.Status = "degraded"
		integrity.PersistenceStatus = "unavailable"
	}
	a.auditMu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{
		"events": events, "pagination": pagination, "integrity": integrity,
	})
}

func (a *webApp) handleAssistant(w http.ResponseWriter, r *http.Request) {
	var input assistantRequest
	if err := decodeJSON(w, r, &input, maxBodyBytes); err != nil {
		return
	}
	if err := validateAssistantRequest(&input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if isKnowledgeStatusQuestion(input.Question) {
		a.streamKnowledgeStatus(w, r, input.Question)
		return
	}
	if isFullCatalogRequest(input.Question) {
		a.streamFullCatalog(w, r, input.Question)
		return
	}
	if input.Basic || a.assistantURL == "" || !assistantModeUsesLLM(a.assistantMode) || !a.runtimeAllowsLLM(r.Context()) {
		a.streamBasicAssistant(w, r, input.Question, input.Basic, input.FallbackReason)
		return
	}

	payload, err := json.Marshal(input)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "não foi possível preparar a solicitação")
		return
	}
	request, err := http.NewRequestWithContext(
		r.Context(), http.MethodPost, a.assistantURL+"/chat", bytes.NewReader(payload),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "não foi possível preparar a solicitação")
		return
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "text/event-stream")
	request.Header.Set("X-SetupMNO-Agent-Token", a.agentToken)
	response, err := a.assistantClient.Do(request)
	if err != nil || response.StatusCode != http.StatusOK {
		fallbackReason := "connector"
		if response != nil {
			if response.StatusCode == http.StatusBadGateway {
				fallbackReason = "context"
			}
			log.Printf(
				"Control Center: Assistente interno retornou HTTP %d; contingência %s ativada",
				response.StatusCode, fallbackReason,
			)
			_ = response.Body.Close()
		} else {
			log.Printf("Control Center: Assistente interno indisponível; contingência connector ativada: %v", err)
		}
		a.streamBasicAssistant(w, r, input.Question, true, fallbackReason)
		return
	}
	defer response.Body.Close()
	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	a.sendFeedbackTokenSSE(w, normalizeFeedbackMode(a.assistantMode, false), "")
	stream := io.LimitReader(response.Body, 16<<20)
	buffer := make([]byte, 4096)
	for {
		count, readErr := stream.Read(buffer)
		if count > 0 {
			if _, writeErr := w.Write(buffer[:count]); writeErr != nil {
				return
			}
			if flusher, ok := w.(http.Flusher); ok {
				flusher.Flush()
			}
		}
		if readErr != nil {
			break
		}
	}
	a.addAudit("assistant_analysis", "Consulta assistida via "+a.assistantMode, clientAddress(r))
}

func (a *webApp) runtimeAllowsLLM(ctx context.Context) bool {
	var state setupStateResponse
	if err := a.agentRequest(ctx, "/setup-state", &state); err != nil {
		return false
	}
	return state.Plan == "pro" && state.LLMAllowed
}

func assistantConfigurationForPlan(plan, mode, model, endpoint string) (string, string, string) {
	if strings.ToLower(strings.TrimSpace(plan)) != "pro" {
		return "basic", "", ""
	}
	return strings.ToLower(strings.TrimSpace(mode)), strings.TrimSpace(model), strings.TrimRight(strings.TrimSpace(endpoint), "/")
}

func assistantModeUsesLLM(mode string) bool {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "openai", "openrouter", "deepseek", "ollama":
		return true
	default:
		return false
	}
}

func knowledgeStatusMarkdown(catalog catalogResponse, state knowledgePackageState) (string, error) {
	manifest := state.Manifest
	if catalog.Stale || state.Stale ||
		!validSemanticVersion(catalog.SetupVersion) ||
		catalog.CatalogVersion != catalog.SetupVersion ||
		catalog.CatalogEntries < 1 ||
		catalog.CatalogEntries != len(catalog.Items) ||
		manifest.SetupVersion != catalog.SetupVersion ||
		manifest.SetupEntries < 0 ||
		manifest.SetupEntries > catalog.CatalogEntries ||
		manifest.DocumentEntries < manifest.SetupEntries ||
		manifest.DocumentTypeEntries["setup"] != manifest.SetupEntries ||
		manifest.DocumentTypeEntries["infrastructure"] != manifest.InfrastructureEntries ||
		manifest.DocumentTypeEntries["blueprint"] != manifest.BlueprintKnowledgeEntries ||
		manifest.QualitySummary.SetupEntries != manifest.SetupEntries ||
		manifest.QualitySummary.InstallationStatuses["maintainer-homologated"] != manifest.SetupEntries ||
		manifest.QualitySummary.IntegrationMaturityLevels["not-mapped"]+
			manifest.QualitySummary.IntegrationMaturityLevels["suggested"]+
			manifest.QualitySummary.IntegrationMaturityLevels["documented"]+
			manifest.QualitySummary.IntegrationMaturityLevels["validated"] != manifest.SetupEntries {
		return "", errors.New("inventário canônico inconsistente")
	}
	missing := catalog.CatalogEntries - manifest.SetupEntries
	coverage := float64(manifest.SetupEntries) * 100 / float64(catalog.CatalogEntries)
	var answer strings.Builder
	answer.WriteString("## Conclusão\n\n")
	fmt.Fprintf(
		&answer,
		"A base canônica do **Setup MNO v%s** documenta **%d dos %d setups do catálogo (%.2f%%)**.",
		manifest.SetupVersion, manifest.SetupEntries, catalog.CatalogEntries, coverage,
	)
	if missing == 0 {
		answer.WriteString(" A cobertura estrutural dedicada do catálogo está **completa**.\n\n")
	} else {
		fmt.Fprintf(&answer, " Restam **%d setups** sem documentação dedicada.\n\n", missing)
	}
	answer.WriteString("## Inventário validado\n\n")
	fmt.Fprintf(
		&answer,
		"- **%d documentos canônicos** no total: %d de setups, %d de infraestrutura e %d de Blueprints.\n",
		manifest.DocumentEntries, manifest.SetupEntries, manifest.InfrastructureEntries,
		manifest.BlueprintKnowledgeEntries,
	)
	fmt.Fprintf(
		&answer,
		"- Conhecimento **v%s** · dataset de avaliações **v%s** com **%d casos**.\n\n",
		manifest.KnowledgeVersion, manifest.EvalDatasetVersion, manifest.EvalCaseEntries,
	)
	answer.WriteString("## Instalação homologada\n\n")
	fmt.Fprintf(
		&answer,
		"- **%d instaladores homologados pelo mantenedor**, com cobertura por arquitetura registrada individualmente no catálogo.\n\n",
		manifest.QualitySummary.InstallationStatuses["maintainer-homologated"],
	)
	answer.WriteString("## Maturidade do conhecimento\n\n")
	fmt.Fprintf(
		&answer,
		"- **%d com conhecimento básico**, **%d com fontes enriquecidas**, **%d com conteúdo técnico revisado**, **%d com guia operacional** e **%d com conhecimento completo**.\n",
		manifest.QualitySummary.MaturityLevels["structural"],
		manifest.QualitySummary.MaturityLevels["source-reviewed"],
		manifest.QualitySummary.MaturityLevels["script-reviewed"],
		manifest.QualitySummary.MaturityLevels["operational-reviewed"],
		manifest.QualitySummary.MaturityLevels["homologated"],
	)
	fmt.Fprintf(
		&answer,
		"- **%d fontes oficiais declaradas** e **%d pendências documentais rastreadas**.\n\n",
		manifest.QualitySummary.OfficialSourceEntries,
		manifest.QualitySummary.UnresolvedIssueCount,
	)
	answer.WriteString("## Maturidade das integrações\n\n")
	fmt.Fprintf(
		&answer,
		"- **%d setups com integrações ainda em mapeamento**, %d com combinações sugeridas, %d com integrações documentadas e %d com integrações validadas.\n\n",
		manifest.QualitySummary.IntegrationMaturityLevels["not-mapped"],
		manifest.QualitySummary.IntegrationMaturityLevels["suggested"],
		manifest.QualitySummary.IntegrationMaturityLevels["documented"],
		manifest.QualitySummary.IntegrationMaturityLevels["validated"],
	)
	answer.WriteString("Fonte: manifesto interno versionado e catálogo runtime validados localmente. Nenhuma contagem foi inferida a partir dos resultados do RAG.")
	return answer.String(), nil
}

func (a *webApp) streamKnowledgeStatus(w http.ResponseWriter, r *http.Request, question string) {
	var catalog catalogResponse
	if err := a.agentRequest(r.Context(), "/catalog", &catalog); err != nil {
		writeError(w, http.StatusServiceUnavailable, "catálogo runtime indisponível")
		return
	}
	state, err := loadRuntimeKnowledgePackage()
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "base canônica indisponível")
		return
	}
	answer, err := knowledgeStatusMarkdown(catalog, state)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "inventário canônico inconsistente")
		return
	}
	route := routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		catalog.Architecture,
	)
	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	a.sendFeedbackTokenSSE(w, "basic", "")
	sendSSE(w, "meta", map[string]any{
		"mode":             "knowledge",
		"model":            "",
		"setupVersion":     state.Manifest.SetupVersion,
		"knowledgeVersion": state.Manifest.KnowledgeVersion,
		"knowledgeEntries": state.Manifest.DocumentEntries,
		"documentedSetups": state.Manifest.SetupEntries,
		"catalogEntries":   catalog.CatalogEntries,
		"knowledgeStale":   state.Stale,
		"qualitySummary":   state.Manifest.QualitySummary,
	})
	sendSSE(w, "route", route)
	sendSSE(w, "delta", map[string]any{"delta": answer})
	sendSSE(w, "done", map[string]any{"ok": true})
	a.addAudit("assistant_knowledge_status", "Inventário canônico consultado localmente", clientAddress(r))
}

func isFullCatalogRequest(question string) bool {
	normalized := strings.ToLower(strings.TrimSpace(question))
	mentionsCatalog := strings.Contains(normalized, "setup") ||
		strings.Contains(normalized, "catálogo") ||
		strings.Contains(normalized, "catalogo")
	requestsAll := strings.Contains(normalized, "todos") ||
		strings.Contains(normalized, "todas") ||
		strings.Contains(normalized, "completo") ||
		strings.Contains(normalized, "completa") ||
		strings.Contains(normalized, "158") ||
		strings.Contains(normalized, "157") ||
		strings.Contains(normalized, "155") ||
		strings.Contains(normalized, "151")
	listIntent := strings.Contains(normalized, "list") ||
		strings.Contains(normalized, "mostr") ||
		strings.Contains(normalized, "exib") ||
		strings.Contains(normalized, "quais") ||
		strings.Contains(normalized, "catálogo completo") ||
		strings.Contains(normalized, "catalogo completo")
	return mentionsCatalog && requestsAll && listIntent
}

func fullCatalogMarkdown(catalog catalogResponse) (string, error) {
	if !validSemanticVersion(catalog.SetupVersion) ||
		catalog.CatalogVersion != catalog.SetupVersion ||
		catalog.CatalogEntries < 1 ||
		catalog.CatalogEntries != len(catalog.Items) ||
		catalog.Stale {
		return "", errors.New("catálogo runtime inconsistente")
	}

	names := make([]string, 0, len(catalog.Items))
	for _, raw := range catalog.Items {
		var identity struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(raw, &identity); err != nil {
			return "", errors.New("item inválido no catálogo runtime")
		}
		name := strings.Join(strings.Fields(identity.Name), " ")
		if name == "" {
			return "", errors.New("setup sem nome no catálogo runtime")
		}
		name = strings.ReplaceAll(name, "**", "* *")
		name = strings.ReplaceAll(name, "`", "'")
		names = append(names, name)
	}
	sortStrings(names)

	var answer strings.Builder
	fmt.Fprintf(&answer, "**Setup MNO v%s — catálogo completo**\n\n", catalog.SetupVersion)
	fmt.Fprintf(&answer, "**%d de %d setups validados:**\n\n", len(names), catalog.CatalogEntries)
	for index, name := range names {
		fmt.Fprintf(&answer, "%d. %s\n", index+1, name)
	}
	answer.WriteString("\nPara descrições, requisitos de RAM, arquitetura e filtros, abra **Catálogo de setups** no menu lateral.")
	return answer.String(), nil
}

func (a *webApp) streamFullCatalog(w http.ResponseWriter, r *http.Request, question string) {
	var catalog catalogResponse
	if err := a.agentRequest(r.Context(), "/catalog", &catalog); err != nil {
		writeError(w, http.StatusServiceUnavailable, "catálogo runtime indisponível")
		return
	}
	answer, err := fullCatalogMarkdown(catalog)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "catálogo runtime inconsistente")
		return
	}

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	a.sendFeedbackTokenSSE(w, "catalog", "")
	sendSSE(w, "meta", map[string]any{
		"mode":           "catalog",
		"model":          "",
		"setupVersion":   catalog.SetupVersion,
		"catalogEntries": catalog.CatalogEntries,
	})
	sendSSE(w, "route", routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		catalog.Architecture,
	))
	sendSSE(w, "delta", map[string]any{"delta": answer})
	sendSSE(w, "done", map[string]any{"ok": true})
	a.addAudit("assistant_catalog", "Catálogo runtime completo listado localmente", clientAddress(r))
}

func (a *webApp) streamBasicAssistant(
	w http.ResponseWriter,
	r *http.Request,
	question string,
	fallback bool,
	fallbackReason string,
) {
	var current overview
	if err := a.agentRequest(r.Context(), "/overview", &current); err != nil {
		writeError(w, http.StatusBadGateway, "não foi possível consultar o servidor")
		return
	}
	route := routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		current.Architecture,
	)
	suggestions := localInsightsForRoute(current, question, route)
	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	a.sendFeedbackTokenSSE(w, "basic", fallbackReason)
	sendSSE(w, "meta", map[string]any{
		"mode":           "basic",
		"model":          "",
		"fallback":       fallback,
		"fallbackReason": fallbackReason,
	})
	sendSSE(w, "route", route)
	sendSSE(w, "delta", map[string]any{"delta": strings.Join(suggestions, "\n\n")})
	sendSSE(w, "done", map[string]any{"ok": true})
	action := "assistant_basic"
	detail := "Diagnóstico básico solicitado"
	if fallback {
		action = "assistant_fallback"
		detail = "Diagnóstico básico usado como contingência: " + fallbackReason
	}
	a.addAudit(action, detail, clientAddress(r))
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
	proxy.ModifyResponse = func(resp *http.Response) error {
		resp.Header.Set("Cache-Control", "no-store, no-cache, must-revalidate")
		resp.Header.Set("Pragma", "no-cache")
		resp.Header.Set("Expires", "0")
		return nil
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		writeError(w, http.StatusBadGateway, "terminal seguro indisponível")
	}
	proxy.FlushInterval = 50 * time.Millisecond
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !terminalIntentAllowed(r.URL.Query()["arg"]) {
			writeError(w, http.StatusBadRequest, "intenção do Terminal Seguro inválida")
			return
		}
		if !a.terminalAccessAllowed(r.Context()) {
			writeError(w, http.StatusForbidden, "recurso disponível apenas quando é usado Cloudflare Tunnel")
			return
		}
		if !a.terminalAuthorized(r) {
			writeError(w, http.StatusForbidden, "confirme a senha administrativa antes de abrir o Terminal Seguro")
			return
		}
		proxy.ServeHTTP(w, r)
	})
}

func (a *webApp) terminalAccessAllowed(ctx context.Context) bool {
	var state setupStateResponse
	if err := a.agentRequest(ctx, "/setup-state", &state); err != nil {
		return false
	}
	return state.InstallationType == "CLOUDFLARE_TUNNEL"
}

func (a *webApp) terminalAuthorized(r *http.Request) bool {
	cookie, err := r.Cookie(sessionCookie)
	if err != nil {
		return false
	}
	now := time.Now()
	a.sessionMu.Lock()
	defer a.sessionMu.Unlock()
	s, ok := a.sessions[cookie.Value]
	if !ok {
		return false
	}
	if now.After(s.TerminalUntil) {
		s.TerminalUntil = time.Time{}
		return false
	}
	return true
}

func terminalIntentAllowed(values []string) bool {
	if len(values) == 0 {
		return true
	}
	if len(values) != 1 {
		return false
	}
	switch values[0] {
	case "installer", "settings", "gateway":
		return true
	default:
		return false
	}
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
		identity := accessIdentityFromContext(r.Context())
		if ok && s.AccessSubject != "" && (identity == nil ||
			identity.Subject != s.AccessSubject || !strings.EqualFold(identity.Email, s.AccessEmail)) {
			delete(a.sessions, cookie.Value)
			ok = false
		}
		if ok && (now.After(s.Expires) || now.After(s.IdleUntil)) {
			delete(a.sessions, cookie.Value)
			ok = false
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
		if r.Method == http.MethodGet && !strings.HasPrefix(r.URL.Path, "/api/") {
			w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate")
			w.Header().Set("Pragma", "no-cache")
			w.Header().Set("Expires", "0")
		}
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

func (a *webApp) runtimeBlueprintCatalog(ctx context.Context) (blueprintCatalogResponse, error) {
	var catalog blueprintCatalogResponse
	if err := a.agentRequest(ctx, "/blueprints", &catalog); err != nil {
		return blueprintCatalogResponse{}, err
	}
	if catalog.Source != "runtime-read-only" || catalog.SetupVersion == "" ||
		catalog.BlueprintCount <= 0 || catalog.BlueprintCount != len(catalog.Items) {
		return blueprintCatalogResponse{}, errors.New("índice runtime de Blueprints inconsistente")
	}
	return catalog, nil
}

func (a *webApp) agentBlueprintDownload(
	ctx context.Context,
	blueprintID string,
) (blueprintBundleDownload, int, error) {
	if !validBlueprintID(blueprintID) {
		return blueprintBundleDownload{}, http.StatusNotFound, errors.New("identificador inválido")
	}
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodGet,
		a.agentURL+"/blueprints/"+url.PathEscape(blueprintID)+"/download",
		nil,
	)
	if err != nil {
		return blueprintBundleDownload{}, 0, err
	}
	req.Header.Set("X-SetupMNO-Agent-Token", a.agentToken)
	resp, err := a.httpClient.Do(req)
	if err != nil {
		return blueprintBundleDownload{}, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return blueprintBundleDownload{}, resp.StatusCode, fmt.Errorf("agente retornou HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxKnowledgeFileBytes+1))
	if err != nil || len(data) == 0 || int64(len(data)) > maxKnowledgeFileBytes {
		return blueprintBundleDownload{}, resp.StatusCode, errors.New("bundle fora do limite")
	}
	expectedSHA := strings.TrimSpace(resp.Header.Get("X-Content-SHA256"))
	if len(expectedSHA) != 64 || sha256String(data) != expectedSHA {
		return blueprintBundleDownload{}, resp.StatusCode, errors.New("hash do bundle divergente")
	}
	return blueprintBundleDownload{
		Filename: blueprintID + ".zip",
		SHA256:   expectedSHA,
		Data:     data,
	}, resp.StatusCode, nil
}

func readRuntimeSnapshot(directory string) (runtimeSnapshot, error) {
	info, err := os.Lstat(directory)
	if err != nil {
		return runtimeSnapshot{}, fmt.Errorf("diretório de estado: %w", err)
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return runtimeSnapshot{}, errors.New("diretório de estado inválido")
	}

	releaseData, err := readRegularFile(filepath.Join(directory, "release.json"), 32<<10)
	if err != nil {
		return runtimeSnapshot{}, fmt.Errorf("manifesto: %w", err)
	}
	var release setupRelease
	decoder := json.NewDecoder(strings.NewReader(string(releaseData)))
	if err := decoder.Decode(&release); err != nil {
		return runtimeSnapshot{}, fmt.Errorf("manifesto JSON: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return runtimeSnapshot{}, errors.New("manifesto JSON contém dados adicionais")
	}
	if release.SchemaVersion != runtimeSchema {
		return runtimeSnapshot{}, fmt.Errorf("schema %d não suportado", release.SchemaVersion)
	}
	if !validSemanticVersion(release.SetupVersion) ||
		release.CatalogVersion != release.SetupVersion ||
		release.CatalogEntries < 1 ||
		(release.Architecture != "amd64" && release.Architecture != "arm64") {
		return runtimeSnapshot{}, errors.New("manifesto inconsistente")
	}
	if err := validateReleaseKnowledge(release); err != nil {
		return runtimeSnapshot{}, err
	}
	expectedHash, err := hex.DecodeString(release.CatalogSHA256)
	if err != nil || len(expectedHash) != sha256.Size {
		return runtimeSnapshot{}, errors.New("SHA-256 do catálogo inválido")
	}

	catalogData, err := readRegularFile(filepath.Join(directory, "catalog.json"), maxCatalogBytes)
	if err != nil {
		return runtimeSnapshot{}, fmt.Errorf("catálogo: %w", err)
	}
	actualHash := sha256.Sum256(catalogData)
	if subtle.ConstantTimeCompare(expectedHash, actualHash[:]) != 1 {
		return runtimeSnapshot{}, errors.New("SHA-256 do catálogo divergente")
	}
	items, err := decodeCatalog(catalogData)
	if err != nil {
		return runtimeSnapshot{}, err
	}
	if len(items) != release.CatalogEntries {
		return runtimeSnapshot{}, errors.New("quantidade do catálogo divergente")
	}
	return runtimeSnapshot{Release: release, Items: items}, nil
}

func readRuntimeEnvironment(directory string) (runtimeEnvironment, error) {
	data, err := readRegularFile(filepath.Join(directory, "environment.json"), 4<<10)
	if err != nil {
		return runtimeEnvironment{}, fmt.Errorf("ambiente runtime: %w", err)
	}
	var environment runtimeEnvironment
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&environment); err != nil {
		return runtimeEnvironment{}, fmt.Errorf("ambiente runtime JSON: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return runtimeEnvironment{}, errors.New("ambiente runtime contém dados adicionais")
	}
	if environment.SchemaVersion != 1 {
		return runtimeEnvironment{}, errors.New("schema do ambiente runtime inválido")
	}
	switch environment.Plan {
	case "pro", "free", "free1", "free2":
	default:
		return runtimeEnvironment{}, errors.New("plano runtime inválido")
	}
	switch environment.InstallationType {
	case "CLOUDFLARE_TUNNEL", "TRADICIONAL":
	default:
		return runtimeEnvironment{}, errors.New("tipo de instalação runtime inválido")
	}
	return environment, nil
}

func validateReleaseKnowledge(release setupRelease) error {
	hasKnowledgeMetadata := release.KnowledgeVersion != "" ||
		release.KnowledgeArchiveSHA256 != "" ||
		release.KnowledgeEntries != 0
	if !hasKnowledgeMetadata {
		return nil
	}
	if !validSemanticVersion(release.KnowledgeVersion) ||
		release.KnowledgeEntries < 1 {
		return errors.New("metadados do conhecimento inconsistentes")
	}
	knowledgeHash, err := hex.DecodeString(release.KnowledgeArchiveSHA256)
	if err != nil || len(knowledgeHash) != sha256.Size {
		return errors.New("SHA-256 do conhecimento inválido")
	}
	hasQualityMetadata := release.QualitySchemaVersion != 0 ||
		release.QualityReportSHA256 != "" || release.QualitySetupEntries != 0
	if hasQualityMetadata {
		qualityHash, hashErr := hex.DecodeString(release.QualityReportSHA256)
		maturityTotal := release.QualityStructuralEntries +
			release.QualitySourceReviewedEntries + release.QualityScriptReviewedEntries +
			release.QualityOperationalEntries + release.QualityHomologatedEntries
		if (release.QualitySchemaVersion != 1 && release.QualitySchemaVersion != 2) || hashErr != nil || len(qualityHash) != sha256.Size ||
			release.QualitySetupEntries < 1 || release.QualitySetupEntries > release.KnowledgeEntries ||
			maturityTotal != release.QualitySetupEntries || release.QualityUnresolvedIssues < 0 {
			return errors.New("metadados de qualidade inconsistentes")
		}
	}
	hasBlueprintMetadata := release.BlueprintFactoryVersion != "" ||
		release.BlueprintSchemaVersion != 0 ||
		release.BlueprintIndexSHA256 != "" ||
		release.BlueprintEntries != 0 ||
		release.BlueprintKnowledgeEntries != 0 ||
		release.BlueprintFixtureEntries != 0
	if !hasBlueprintMetadata {
		return nil
	}
	if release.BlueprintSchemaVersion != blueprintSchema ||
		!validSemanticVersion(release.BlueprintFactoryVersion) ||
		release.BlueprintEntries < 1 ||
		release.BlueprintKnowledgeEntries < 1 ||
		release.BlueprintKnowledgeEntries > release.BlueprintEntries ||
		release.BlueprintFixtureEntries < 0 ||
		release.BlueprintFixtureEntries > release.BlueprintKnowledgeEntries {
		return errors.New("metadados dos Blueprints inconsistentes")
	}
	blueprintHash, err := hex.DecodeString(release.BlueprintIndexSHA256)
	if err != nil || len(blueprintHash) != sha256.Size {
		return errors.New("SHA-256 dos Blueprints inválido")
	}
	if release.EvalSchemaVersion != evalSchemaVersion ||
		release.EvalDatasetVersion != evalDatasetVersion ||
		release.EvalGraderVersion != evalGraderVersion ||
		release.EvalCaseEntries != evalExpectedCases {
		return errors.New("metadados de evals inconsistentes")
	}
	evalHash, err := hex.DecodeString(release.EvalDatasetSHA256)
	if err != nil || len(evalHash) != sha256.Size {
		return errors.New("SHA-256 do dataset de evals inválido")
	}
	return nil
}

func readRegularFile(filename string, limit int64) ([]byte, error) {
	info, err := os.Lstat(filename)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("arquivo não regular")
	}
	if info.Size() < 2 || info.Size() > limit {
		return nil, errors.New("tamanho de arquivo inválido")
	}
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, errors.New("arquivo excede o limite")
	}
	return data, nil
}

func decodeCatalog(data []byte) ([]json.RawMessage, error) {
	var items []json.RawMessage
	if err := json.Unmarshal(data, &items); err != nil {
		return nil, fmt.Errorf("catálogo JSON: %w", err)
	}
	if len(items) == 0 {
		return nil, errors.New("catálogo vazio")
	}
	for _, item := range items {
		var identity struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(item, &identity); err != nil || strings.TrimSpace(identity.Name) == "" {
			return nil, errors.New("item inválido no catálogo")
		}
	}
	return items, nil
}

func validSemanticVersion(value string) bool {
	parts := strings.Split(value, ".")
	if len(parts) != 3 {
		return false
	}
	for _, part := range parts {
		if part == "" {
			return false
		}
		if _, err := strconv.ParseUint(part, 10, 31); err != nil {
			return false
		}
	}
	return true
}

func stateFromSnapshot(snapshot runtimeSnapshot, source string) setupStateResponse {
	release := snapshot.Release
	return setupStateResponse{
		SchemaVersion:  release.SchemaVersion,
		SetupVersion:   release.SetupVersion,
		CatalogVersion: release.CatalogVersion,
		CatalogSHA256:  release.CatalogSHA256,
		CatalogEntries: release.CatalogEntries,
		Architecture:   release.Architecture,
		Source:         source,
		Stale:          false,
	}
}

func catalogFromSnapshot(snapshot runtimeSnapshot, source string) catalogResponse {
	release := snapshot.Release
	return catalogResponse{
		Items:          snapshot.Items,
		SetupVersion:   release.SetupVersion,
		CatalogVersion: release.CatalogVersion,
		CatalogSHA256:  release.CatalogSHA256,
		CatalogEntries: release.CatalogEntries,
		Architecture:   release.Architecture,
		Source:         source,
		Stale:          false,
	}
}

func embeddedCatalogResponse() (catalogResponse, error) {
	data, err := embeddedFiles.ReadFile("catalog.json")
	if err != nil {
		return catalogResponse{}, err
	}
	items, err := decodeCatalog(data)
	if err != nil {
		return catalogResponse{}, err
	}
	sum := sha256.Sum256(data)
	return catalogResponse{
		Items:          items,
		CatalogVersion: "embutido",
		CatalogSHA256:  hex.EncodeToString(sum[:]),
		CatalogEntries: len(items),
		Source:         "embedded",
		Stale:          true,
		Warning:        "Catálogo runtime indisponível. Exibindo a cópia de contingência incluída no Control Center.",
	}, nil
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
	previous := a.audit
	previous.Events = append([]auditEvent(nil), a.audit.Events...)
	controlVersion := a.version
	if !validSemanticVersion(controlVersion) {
		controlVersion = "0.0.0"
	}
	appendAuditEvent(&a.audit, auditEvent{
		Time: time.Now().UTC().Format(time.RFC3339), Actor: inferAuditActor(action), Action: action,
		Resource: inferAuditResource(action), Outcome: inferAuditOutcome(action), Detail: detail,
		Address: address, ControlVersion: controlVersion,
	})
	pruneAuditState(&a.audit, time.Now().UTC())
	if err := saveAuditState(a.audit); err != nil {
		a.audit = previous
		a.audit.LastError = "persistência local indisponível"
		log.Printf("Control Center: evento de auditoria não persistido: %v", err)
		return
	}
	a.audit.LastError = ""
}

func (a *webApp) sessionJanitor() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for now := range ticker.C {
		a.sessionMu.Lock()
		for id, s := range a.sessions {
			if now.After(s.Expires) || now.After(s.IdleUntil) {
				delete(a.sessions, id)
			}
		}
		a.sessionMu.Unlock()

		a.feedbackMu.Lock()
		for token, record := range a.feedbackTokens {
			if now.After(record.Expires) {
				delete(a.feedbackTokens, token)
			}
		}
		previousCount := len(a.feedback.Records)
		a.feedback.Records = pruneFeedbackRecords(a.feedback.Records, now.UTC())
		if len(a.feedback.Records) != previousCount {
			if err := saveFeedbackState(a.feedback); err != nil {
				log.Printf("Control Center: retenção do feedback não pôde ser persistida: %v", err)
			}
		}
		a.feedbackMu.Unlock()

		a.auditMu.Lock()
		if pruneAuditState(&a.audit, now.UTC()) {
			if err := saveAuditState(a.audit); err != nil {
				a.audit.LastError = "persistência local indisponível"
				log.Printf("Control Center: retenção da auditoria não pôde ser persistida: %v", err)
			} else {
				a.audit.LastError = ""
			}
		}
		a.auditMu.Unlock()
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
		OperatingSystem:   info.OperatingSystem,
		OSVersion:         info.OSVersion,
		OSType:            info.OSType,
		KernelVersion:     info.KernelVersion,
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

	diskTotal, diskUsed, diskPercent := readDiskUsage(
		envDefault("HOST_DISK_PATH", defaultHostDiskPath),
	)

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

func readDiskUsage(path string) (uint64, uint64, float64) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, 0, 0
	}
	total := stat.Blocks * uint64(stat.Bsize)
	free := stat.Bavail * uint64(stat.Bsize)
	if total <= free {
		return total, 0, 0
	}
	used := total - free
	return total, used, float64(used) / float64(total) * 100
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
	route := routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		current.Architecture,
	)
	return localInsightsForRoute(current, question, route)
}

func localInsightsForRoute(current overview, question string, route assistantRoute) []string {
	if route.Intent == "scope_redirect" {
		return []string{
			"Sou especializado em Setup MNO e infraestrutura; não respondo a assuntos gerais fora desse escopo.",
			"Pergunte sobre setups, servidor, Docker, Swarm, capacidade, segurança, integrações ou Blueprints MNO.",
		}
	}
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
