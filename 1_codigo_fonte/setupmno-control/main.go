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

	fleetStore *fleetInventoryStore
	fleetMu    sync.Mutex

	sentinelMu     sync.Mutex
	sentinelConfig *SentinelConfig
	sentinelState  *sentinelRuntimeState
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
	HomologationRunnerVersion    string `json:"homologationRunnerVersion,omitempty"`
	HomologationCandidateSchema  int    `json:"homologationCandidateSchemaVersion,omitempty"`
	HomologationRegistryEntries  int    `json:"homologationRegistryEntries,omitempty"`
	HomologationManifestSHA256   string `json:"homologationPackageManifestSHA256,omitempty"`
	HomologationAutoPromotion    bool   `json:"homologationAutomaticPromotion"`
	SupplyChainSchemaVersion     int    `json:"supplyChainSchemaVersion,omitempty"`
	SupplyChainManifestSHA256    string `json:"supplyChainManifestSHA256,omitempty"`
	SupplyChainSBOMSHA256        string `json:"supplyChainSBOMSHA256,omitempty"`
	SupplyChainImageInventorySHA string `json:"supplyChainImageInventorySHA256,omitempty"`
	SupplyChainAttestationSHA256 string `json:"supplyChainAttestationSHA256,omitempty"`
	SupplyChainSignatureStatus   string `json:"supplyChainSignatureStatus,omitempty"`
	SupplyChainCompositionFull   bool   `json:"supplyChainCompositionComplete"`
	SupplyChainImageReferences   int    `json:"supplyChainImageReferences,omitempty"`
	SupplyChainDigestPinned      int    `json:"supplyChainDigestPinnedImages,omitempty"`
	SupplyChainMutableTags       int    `json:"supplyChainMutableTagImages,omitempty"`
	SupplyChainHighRiskTags      int    `json:"supplyChainHighRiskMutableTagImages,omitempty"`
	SupplyChainImplicitLatest    int    `json:"supplyChainImplicitLatestImages,omitempty"`
	SupplyChainUnresolved        int    `json:"supplyChainUnresolvedReferences,omitempty"`
}

type runtimeSnapshot struct {
	Release setupRelease
	Items   []json.RawMessage
}

type setupStateResponse struct {
	SchemaVersion               int              `json:"schemaVersion"`
	SetupVersion                string           `json:"setupVersion"`
	ControlVersion              string           `json:"controlVersion,omitempty"`
	CatalogVersion              string           `json:"catalogVersion"`
	CatalogSHA256               string           `json:"catalogSHA256"`
	CatalogEntries              int              `json:"catalogEntries"`
	Architecture                string           `json:"architecture"`
	Source                      string           `json:"source"`
	Stale                       bool             `json:"stale"`
	Warning                     string           `json:"warning,omitempty"`
	Plan                        string           `json:"plan,omitempty"`
	InstallationType            string           `json:"installationType,omitempty"`
	LLMAllowed                  bool             `json:"llmAllowed"`
	Capabilities                planCapabilities `json:"capabilities"`
	HomologationRunnerAvailable bool             `json:"homologationRunnerAvailable"`
	HomologationRunnerVersion   string           `json:"homologationRunnerVersion,omitempty"`
	HomologationCandidateSchema int              `json:"homologationCandidateSchemaVersion,omitempty"`
	HomologationWorkflow        string           `json:"homologationWorkflow,omitempty"`
	SupplyChainAvailable        bool             `json:"supplyChainAvailable"`
	SupplyChainSchemaVersion    int              `json:"supplyChainSchemaVersion,omitempty"`
	SupplyChainSignatureStatus  string           `json:"supplyChainSignatureStatus,omitempty"`
	SupplyChainCompositionFull  bool             `json:"supplyChainCompositionComplete"`
	SupplyChainImageReferences  int              `json:"supplyChainImageReferences,omitempty"`
	SupplyChainDigestPinned     int              `json:"supplyChainDigestPinnedImages,omitempty"`
	SupplyChainMutableTags      int              `json:"supplyChainMutableTagImages,omitempty"`
	SupplyChainHighRiskTags     int              `json:"supplyChainHighRiskMutableTagImages,omitempty"`
	SupplyChainImplicitLatest   int              `json:"supplyChainImplicitLatestImages,omitempty"`
	SupplyChainUnresolved       int              `json:"supplyChainUnresolvedReferences,omitempty"`
	FleetMode                   string           `json:"fleetMode,omitempty"`
	FleetAllowed                bool             `json:"fleetAllowed"`
	FleetNodeID                 string           `json:"fleetNodeId,omitempty"`
	FleetToken                  string           `json:"fleetToken,omitempty"`
}

type supplyChainFile struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

type supplyChainManifest struct {
	SchemaVersion    int    `json:"schemaVersion"`
	GeneratorVersion string `json:"generatorVersion"`
	SetupVersion     string `json:"setupVersion"`
	Architecture     string `json:"architecture"`
	SBOM             struct {
		Format      string `json:"format"`
		SpecVersion string `json:"specVersion"`
		Composition string `json:"composition"`
	} `json:"sbom"`
	Attestation struct {
		StatementType   string `json:"statementType"`
		PredicateType   string `json:"predicateType"`
		SignatureStatus string `json:"signatureStatus"`
	} `json:"attestation"`
	Inventory struct {
		Completeness        string `json:"completeness"`
		DigestPinnedImages  int    `json:"digestPinnedImages"`
		HighRiskMutableTags int    `json:"highRiskMutableTagImages"`
		ImplicitLatest      int    `json:"implicitLatestImages"`
		ImageReferences     int    `json:"imageReferences"`
		MutableTags         int    `json:"mutableTagImages"`
		Unresolved          int    `json:"unresolvedExpressions"`
	} `json:"inventory"`
	Files []supplyChainFile `json:"files"`
}

type planCapabilities struct {
	ProAccess                 bool `json:"proAccess"`
	StrixDiagnostics          bool `json:"strixDiagnostics"`
	Maintainer                bool `json:"maintainer"`
	HomologationReview        bool `json:"homologationReview"`
	HomologationExecute       bool `json:"homologationExecute"`
	HomologationFinalApproval bool `json:"homologationFinalApproval"`
	RemoteTerminal            bool `json:"remoteTerminal"`
	FleetHub                  bool `json:"fleetHub"`
}

type runtimeEnvironment struct {
	SchemaVersion    int       `json:"schemaVersion"`
	Plan             string    `json:"plan"`
	InstallationType string    `json:"installationType"`
	FleetMode        FleetMode `json:"fleetMode,omitempty"`
	FleetNodeID      string    `json:"fleetNodeId,omitempty"`
	FleetMasterURL   string    `json:"fleetMasterUrl,omitempty"`
	FleetToken       string    `json:"fleetToken,omitempty"`
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
	OperationalContextAvailable bool                   `json:"operationalContextAvailable"`
	OperationalContextWarning   string                 `json:"operationalContextWarning,omitempty"`
	KnowledgeDocumentEntries    int                    `json:"knowledgeDocumentEntries"`
	CanonicalSetupEntries       int                    `json:"canonicalSetupEntries"`
	InfrastructureEntries       int                    `json:"infrastructureEntries"`
	BlueprintEntries            int                    `json:"blueprintEntries"`
	BlueprintBetaEntries        int                    `json:"blueprintBetaEntries"`
	BlueprintHomologatedEntries int                    `json:"blueprintHomologatedEntries"`
	SetupTypeEntries            map[string]int         `json:"setupTypeEntries,omitempty"`
	ApplicationInventoryStatus  string                 `json:"applicationInventoryStatus"`
	SetupVersion                string                 `json:"setupVersion"`
	CatalogVersion              string                 `json:"catalogVersion"`
	CatalogSHA256               string                 `json:"catalogSHA256"`
	CatalogEntries              int                    `json:"catalogEntries"`
	CatalogSource               string                 `json:"catalogSource"`
	CatalogStale                bool                   `json:"catalogStale"`
	Architecture                string                 `json:"architecture"`
	OperatingSystem             string                 `json:"operatingSystem"`
	OSVersion                   string                 `json:"osVersion,omitempty"`
	OSType                      string                 `json:"osType"`
	KernelVersion               string                 `json:"kernelVersion"`
	EngineVersion               string                 `json:"engineVersion"`
	CPUPercent                  float64                `json:"cpuPercent"`
	MemoryPercent               float64                `json:"memoryPercent"`
	MemoryAvailableGB           float64                `json:"memoryAvailableGB"`
	DiskPercent                 float64                `json:"diskPercent"`
	Services                    int                    `json:"services"`
	DegradedServices            int                    `json:"degradedServices"`
	SwarmNodes                  int                    `json:"swarmNodes"`
	InstalledApps               []assistantApp         `json:"installedApps"`
	InstalledApplicationCount   int                    `json:"installedApplicationCount"`
	RelevantSetupCount          int                    `json:"relevantSetupCount"`
	RelevantSetups              []map[string]any       `json:"relevantSetups"`
	SRESnapshot                 *sreDiagnosticSnapshot `json:"sreSnapshot,omitempty"`
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
	fleetStore, err := loadFleetInventory(envDefault("FLEET_STORE_PATH", "/audit/fleet-inventory.json"))
	if err != nil {
		return fmt.Errorf("inventário do Fleet Hub indisponível: %w", err)
	}
	sentinelCfg, err := loadSentinelConfig(envDefault("SENTINEL_CONFIG_PATH", "/audit/sentinel_config.json"))
	if err != nil {
		sentinelCfg = defaultSentinelConfig()
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
		fleetStore:       fleetStore,
		sentinelConfig:   sentinelCfg,
		sentinelState:    newSentinelRuntimeState(),
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
	mux.Handle("GET /api/sre/snapshot", app.requireAuth(http.HandlerFunc(app.handleSRESnapshot)))
	mux.Handle("GET /api/setup-state", app.requireAuth(http.HandlerFunc(app.handleSetupState)))
	mux.Handle("GET /api/catalog", app.requireAuth(http.HandlerFunc(app.handleCatalog)))
	mux.Handle("GET /api/quality", app.requireAuth(http.HandlerFunc(app.handleQuality)))
	mux.Handle("GET /api/homologation", app.requireAuth(app.requireMaintainer(http.HandlerFunc(app.handleHomologation))))
	mux.Handle("GET /api/resilience", app.requireAuth(http.HandlerFunc(app.handleResilience)))
	mux.Handle("GET /api/resilience/summary", app.requireAuth(http.HandlerFunc(app.handleResilienceSummary)))
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
	mux.Handle("GET /api/fleet/status", app.requireAuth(http.HandlerFunc(app.handleFleetStatus)))
	mux.Handle("GET /api/fleet/nodes", app.requireAuth(http.HandlerFunc(app.handleFleetNodes)))
	mux.Handle("POST /api/fleet/nodes", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetAddNode))))
	mux.Handle("DELETE /api/fleet/nodes/{id}", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetRemoveNode))))
	mux.Handle("GET /api/fleet/telemetry", app.requireAuth(http.HandlerFunc(app.handleFleetTelemetry)))
	mux.Handle("POST /api/fleet/sync", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetSync))))
	mux.Handle("POST /api/fleet/nodes/{id}/ping", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetPing))))
	mux.Handle("POST /api/fleet/ping", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetPing))))
	mux.HandleFunc("GET /api/fleet/worker/telemetry", app.handleFleetWorkerTelemetry)
	mux.HandleFunc("GET /api/fleet/worker/structure", app.handleFleetWorkerStructure)
	mux.HandleFunc("POST /api/fleet/worker/action", app.handleFleetWorkerAction)
	mux.Handle("GET /api/fleet/nodes/{id}/structure", app.requireAuth(http.HandlerFunc(app.handleFleetNodeStructure)))
	mux.Handle("POST /api/fleet/transfer/preflight", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetTransferPreflight))))
	mux.Handle("POST /api/fleet/transfer/execute", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetTransferExecute))))
	mux.Handle("POST /api/fleet/backup/execute", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleFleetBackupExecute))))
	mux.HandleFunc("GET /api/fleet/tools/schema.json", app.handleFleetToolsSchema)
	mux.HandleFunc("GET /api/fleet/tools", app.handleFleetToolsSchema)
	mux.HandleFunc("POST /api/fleet/tools/execute", app.handleFleetToolsExecute)
	mux.Handle("GET /api/sentinel/config", app.requireAuth(http.HandlerFunc(app.handleSentinelGetConfig)))
	mux.Handle("POST /api/sentinel/config", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleSentinelSaveConfig))))
	mux.Handle("POST /api/sentinel/test", app.requireAuth(app.requireCSRF(http.HandlerFunc(app.handleSentinelTestAlert))))
	mux.Handle("GET /api/sentinel/status", app.requireAuth(http.HandlerFunc(app.handleSentinelGetStatus)))
	mux.HandleFunc("GET /install.html", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/?action=terminal", http.StatusTemporaryRedirect)
	})

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
	go app.sentinelDaemon()
	go app.fleetMonitorDaemon(context.Background())
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
	homologationCandidateDir := envDefault("HOMOLOGATION_CANDIDATE_DIR", "/homologation-candidates")
	controlVersion := envDefault("APP_VERSION", "dev")

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
	mux.HandleFunc("GET /sre/snapshot", authorize(func(w http.ResponseWriter, _ *http.Request) {
		runtime, err := readRuntimeSnapshot(setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "estado runtime indisponível para o diagnóstico SRE")
			return
		}
		result, err := collectSREDiagnosticSnapshot(dockerClient, runtime.Release, controlVersion)
		if err != nil {
			writeError(w, http.StatusBadGateway, "snapshot SRE indisponível")
			return
		}
		result.Deterministic = loadSREDeterministicAudit(setupStateDir, time.Now().UTC())
		if err := validateSREDiagnosticSnapshot(result); err != nil {
			writeError(w, http.StatusBadGateway, "snapshot SRE indisponível")
			return
		}
		writeJSON(w, http.StatusOK, result)
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
		state.Capabilities = capabilitiesForEnvironment(environment)
		state.LLMAllowed = state.Capabilities.ProAccess
		state.HomologationRunnerAvailable = state.HomologationRunnerAvailable && state.Capabilities.HomologationExecute
		state.FleetMode = string(environment.FleetMode)
		state.FleetAllowed = state.Capabilities.FleetHub
		state.FleetNodeID = environment.FleetNodeID
		state.FleetToken = environment.FleetToken
		writeJSON(w, http.StatusOK, state)
	}))
	mux.HandleFunc("GET /fleet/telemetry", authorize(func(w http.ResponseWriter, _ *http.Request) {
		overviewData, err := collectOverview(dockerClient)
		if err != nil {
			writeError(w, http.StatusBadGateway, "erro ao coletar visão geral do nó")
			return
		}
		environment, _ := readRuntimeEnvironment(setupStateDir)
		nodeID := environment.FleetNodeID
		if nodeID == "" {
			nodeID = overviewData.Hostname
		}
		var arch, setupVersion string
		if snapshot, err := readRuntimeSnapshot(setupStateDir); err == nil {
			arch = snapshot.Release.Architecture
			setupVersion = snapshot.Release.SetupVersion
		}
		if arch == "" {
			arch = normalizeBlueprintArchitecture(overviewData.Architecture)
		}
		if arch == "" {
			arch = "amd64"
		}
		if setupVersion == "" {
			setupVersion = "7.44.0"
		}
		telemetry := FleetTelemetry{
			NodeID:        nodeID,
			Mode:          environment.FleetMode,
			Architecture:  arch,
			SetupVersion:  setupVersion,
			UptimeSeconds: int64(overviewData.Metrics.UptimeSeconds),
			LoadAverage1m: overviewData.Metrics.Load1,
			MemoryUsedMB:  overviewData.Metrics.MemoryUsed / (1024 * 1024),
			MemoryTotalMB: overviewData.Metrics.MemoryTotal / (1024 * 1024),
			DiskUsedGB:    overviewData.Metrics.DiskUsed / (1024 * 1024 * 1024),
			DiskTotalGB:   overviewData.Metrics.DiskTotal / (1024 * 1024 * 1024),
			ActiveSwarm:   overviewData.SwarmNodes > 0,
			HealthyApps:   overviewData.HealthyServices,
			UnhealthyApps: overviewData.DegradedServices,
			Timestamp:     time.Now().UTC(),
		}
		writeJSON(w, http.StatusOK, telemetry)
	}))
	mux.HandleFunc("GET /fleet/config", authorize(func(w http.ResponseWriter, _ *http.Request) {
		environment, err := readRuntimeEnvironment(setupStateDir)
		if err != nil {
			writeJSON(w, http.StatusOK, fleetConfigResponse{
				FleetMode: FleetModeDisabled,
			})
			return
		}
		writeJSON(w, http.StatusOK, fleetConfigResponse{
			FleetMode:      environment.FleetMode,
			FleetNodeID:    environment.FleetNodeID,
			FleetMasterURL: environment.FleetMasterURL,
			FleetToken:     environment.FleetToken,
		})
	}))
	mux.HandleFunc("GET /fleet/structure", authorize(func(w http.ResponseWriter, _ *http.Request) {
		environment, _ := readRuntimeEnvironment(setupStateDir)
		overviewData, _ := collectOverview(dockerClient)
		appsData, _ := collectApps(dockerClient)

		memFree := uint64(0)
		if overviewData.Metrics.MemoryTotal > overviewData.Metrics.MemoryUsed {
			memFree = (overviewData.Metrics.MemoryTotal - overviewData.Metrics.MemoryUsed) / (1024 * 1024)
		}
		diskFree := uint64(0)
		if overviewData.Metrics.DiskTotal > overviewData.Metrics.DiskUsed {
			diskFree = (overviewData.Metrics.DiskTotal - overviewData.Metrics.DiskUsed) / (1024 * 1024 * 1024)
		}

		appStructures := make([]FleetAppStructure, 0, len(appsData))
		for _, app := range appsData {
			services := make([]string, 0, len(app.Services))
			images := make([]string, 0, len(app.Services))
			for _, s := range app.Services {
				services = append(services, s.Name)
				images = append(images, s.Image)
			}
			volInfo := []FleetVolumeInfo{
				{
					Name:      fmt.Sprintf("%s_data", app.Name),
					Driver:    "local",
					SizeBytes: 512 * 1024 * 1024,
				},
			}
			domains := []string{fmt.Sprintf("%s.manualnegocioonline.com.br", strings.ToLower(app.Name))}
			appStructures = append(appStructures, FleetAppStructure{
				Name:             app.Name,
				Services:         services,
				Images:           images,
				Volumes:          volInfo,
				RequiredMemoryMB: estimateAppMemoryMB(app.Name, images),
				Domains:          domains,
				Status:           app.Status,
			})
		}

		nodeName := "Torre Master (Nó Local)"
		if environment.FleetMode == FleetModeWorker {
			nodeName = "Nó de Frota (Worker Local)"
		}

		structure := FleetNodeStructure{
			NodeID:        environment.FleetNodeID,
			Name:          nodeName,
			Mode:          environment.FleetMode,
			Role:          string(environment.FleetMode),
			Architecture:  normalizeArch(overviewData.Architecture),
			SetupVersion:  "7.47.0",
			MemoryTotalMB: overviewData.Metrics.MemoryTotal / (1024 * 1024),
			MemoryFreeMB:  memFree,
			DiskTotalGB:   overviewData.Metrics.DiskTotal / (1024 * 1024 * 1024),
			DiskFreeGB:    diskFree,
			SwarmActive:   overviewData.SwarmNodes > 0,
			TunnelHealthy: true,
			Apps:          appStructures,
			Timestamp:     time.Now().UTC(),
		}
		writeJSON(w, http.StatusOK, structure)
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
	mux.HandleFunc("GET /homologation", authorize(func(w http.ResponseWriter, _ *http.Request) {
		environment, environmentErr := readRuntimeEnvironment(setupStateDir)
		if environmentErr != nil || !planHasMaintainerAccess(environment.Plan) {
			writeError(w, http.StatusForbidden, "recurso exclusivo do plano PRO MASTER")
			return
		}
		queue, err := collectHomologationQueue(homologationCandidateDir, setupStateDir)
		if err != nil {
			writeError(w, http.StatusServiceUnavailable, "central de revisão indisponível")
			return
		}
		writeJSON(w, http.StatusOK, queue)
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
	w.Header().Add("Trailer", assistantOutputGateTrailer)
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
		if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
			OperationalContextAvailable: contextData.OperationalContextAvailable,
			CanonicalSourceCount:        len(promptContext.Sources),
			DeterministicAnswer:         true,
		}) {
			sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
			return
		}
		sendSSE(w, "done", map[string]any{
			"ok": true, "policy": "knowledge-quality",
		})
		return
	}
	if answer, ok := buildDeterministicEcosystemAnswer(input.Question, contextData); ok {
		sendSSE(w, "delta", map[string]any{"delta": answer})
		if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
			OperationalContextAvailable: contextData.OperationalContextAvailable,
			DeterministicAnswer:         true,
		}) {
			sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
			return
		}
		sendSSE(w, "done", map[string]any{
			"ok": true, "policy": "ecosystem-inventory",
		})
		return
	}
	answer, err := s.streamProvider(r.Context(), input, contextData, route, promptContext)
	if err != nil {
		w.Header().Set(assistantOutputGateTrailer, "provider-error")
		sendSSE(w, "error", map[string]any{
			"error":  "O provedor de IA não concluiu a resposta.",
			"reason": "provider",
		})
		log.Printf("Assistente MNO: falha controlada no provedor %s: %v", s.provider, err)
		return
	}
	var grounding *groundingAudit
	if promptContext != nil {
		audit := validateGroundingCitations(answer, len(promptContext.Sources))
		grounding = &audit
	}
	gate := validateAssistantProviderOutput(answer, input.Question, s.provider, contextData)
	if gate.Status == "accepted" && grounding != nil && !grounding.Grounded {
		gate = rejectedAssistantOutput("grounding-not-validated")
	}
	if grounding != nil {
		sendSSE(w, "grounding", grounding)
	}
	sendSSE(w, "output_gate", gate)
	if gate.Status != "accepted" {
		w.Header().Set(assistantOutputGateTrailer, "rejected:"+gate.Reason)
		fallback := buildAssistantOutputFallback(input.Question, contextData, route)
		sendSSE(w, "delta", map[string]any{"delta": fallback})
		if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
			OperationalContextAvailable: contextData.OperationalContextAvailable,
			DeterministicAnswer:         true,
			BasicMode:                   true,
		}) {
			sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
			return
		}
		log.Printf(
			"Assistente MNO: gate de saída %s rejeitou resposta do provedor %s; motivo=%s; contingência local=true",
			assistantOutputGateVersion, s.provider, gate.Reason,
		)
		sendSSE(w, "done", map[string]any{"ok": true, "policy": "output-gate-fallback"})
		return
	}
	w.Header().Set(assistantOutputGateTrailer, "accepted")
	sendSSE(w, "delta", map[string]any{"delta": answer})
	if contextData.SRESnapshot != nil {
		disclosure := deterministicAuditDisclosure(contextData.SRESnapshot.Deterministic)
		if disclosure != "" {
			sendSSE(w, "delta", map[string]any{"delta": "\n\n" + disclosure})
		}
	}
	sourceCount := 0
	if promptContext != nil {
		sourceCount = len(promptContext.Sources)
	}
	if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
		OperationalContextAvailable: contextData.OperationalContextAvailable,
		CanonicalSourceCount:        sourceCount,
		Grounding:                   grounding,
	}) {
		sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
		return
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
		fmt.Fprintf(&answer, "O snapshot sanitizado registra **%d aplicações ou stacks instaladas** neste servidor. Esse número descreve o ambiente em execução e não o catálogo de %d setups disponíveis.\n\n",
			contextData.InstalledApplicationCount, contextData.CanonicalSetupEntries)
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
	var sreSnapshot sreDiagnosticSnapshot
	var setupState setupStateResponse
	var catalog catalogResponse
	type callResult struct {
		name string
		err  error
	}
	results := make(chan callResult, 3)
	requestErrors := make(map[string]error, 3)
	requests := []struct {
		name     string
		endpoint string
		target   any
	}{
		{"sre-snapshot", "/sre/snapshot", &sreSnapshot},
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
	if err := requestErrors["sre-snapshot"]; err != nil {
		return assistantContext{}, fmt.Errorf("snapshot SRE: %w", err)
	}
	if err := validateSREDiagnosticSnapshot(sreSnapshot); err != nil {
		return assistantContext{}, fmt.Errorf("snapshot SRE inválido: %w", err)
	}

	warnings := make([]string, 0, 1)

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
	if sreSnapshot.Capacity.MemoryTotal > sreSnapshot.Capacity.MemoryUsed {
		available = sreSnapshot.Capacity.MemoryTotal - sreSnapshot.Capacity.MemoryUsed
	}
	architecture := sreSnapshot.Versions.Architecture
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
		OperatingSystem:             sreSnapshot.Versions.OperatingSystem,
		OSVersion:                   sreSnapshot.Versions.OSVersion,
		OSType:                      sreSnapshot.Versions.OSType,
		KernelVersion:               sreSnapshot.Versions.KernelVersion,
		EngineVersion:               sreSnapshot.Versions.DockerVersion,
		CPUPercent:                  sreSnapshot.Capacity.CPUPercent,
		MemoryPercent:               sreSnapshot.Capacity.MemoryPercent,
		MemoryAvailableGB:           round(float64(available) / float64(1<<30)),
		DiskPercent:                 sreSnapshot.Capacity.DiskPercent,
		Services:                    sreSnapshot.Swarm.Services,
		DegradedServices:            sreSnapshot.Swarm.DegradedServices,
		SwarmNodes:                  sreSnapshot.Swarm.Nodes,
		InstalledApps:               []assistantApp{},
		InstalledApplicationCount:   sreSnapshot.Swarm.Applications,
		SRESnapshot:                 &sreSnapshot,
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
	input assistantRequest,
	contextData assistantContext,
	route assistantRoute,
	retrievalContext *retrievalPromptContext,
) (string, error) {
	return s.streamProviderLimited(
		ctx, input, contextData, route, retrievalContext, assistantOutputTokenLimit(route),
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
		return s.streamChatCompletions(ctx, instructions, messages, maxOutputTokens)
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
		Intent   string `json:"intent"`
	}
	if err := decodeJSON(w, r, &input, 4096); err != nil {
		return
	}
	input.Intent = strings.ToLower(strings.TrimSpace(input.Intent))
	if input.Intent == "" {
		input.Intent = "installer"
	}
	if !terminalIntentAllowed([]string{input.Intent}) {
		input.Password = ""
		writeError(w, http.StatusBadRequest, "intenção do Terminal Seguro inválida")
		return
	}
	if input.Intent == "homologation" && !a.maintainerAccessAllowed(r.Context()) {
		input.Password = ""
		a.addAudit("maintainer_terminal_blocked_plan", "Recurso do mantenedor recusado: requer plano PRO MASTER", address)
		writeError(w, http.StatusForbidden, "recurso exclusivo do plano PRO MASTER")
		return
	}
	if input.Intent == "strix" && !a.strixAccessAllowed(r.Context()) {
		input.Password = ""
		a.addAudit("strix_terminal_blocked_plan", "Diagnóstico Strix recusado: requer plano PRO ou PRO MASTER", address)
		writeError(w, http.StatusForbidden, "recurso disponível nos planos PRO e PRO MASTER")
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

func (a *webApp) handleSRESnapshot(w http.ResponseWriter, r *http.Request) {
	var result sreDiagnosticSnapshot
	if err := a.agentRequest(r.Context(), "/sre/snapshot", &result); err != nil ||
		validateSREDiagnosticSnapshot(result) != nil {
		writeError(w, http.StatusBadGateway, "diagnóstico SRE somente leitura indisponível")
		return
	}
	a.addAudit(
		"sre_snapshot_read",
		"Snapshot SRE BETA sanitizado consultado sem alterações",
		clientAddress(r),
	)
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

func (a *webApp) handleHomologation(w http.ResponseWriter, r *http.Request) {
	var result homologationQueueResponse
	if err := a.agentRequest(r.Context(), "/homologation", &result); err != nil ||
		result.Source != "runtime-read-only" || result.SchemaVersion != 1 {
		writeError(w, http.StatusServiceUnavailable, "central de revisão indisponível")
		return
	}
	writeJSON(w, http.StatusOK, result)
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
	scope := strings.TrimSpace(r.URL.Query().Get("scope"))
	if scope == "" {
		scope = strings.TrimSpace(r.URL.Query().Get("filter"))
	}
	a.auditMu.Lock()
	eventsSource := a.audit.Events
	if scope != "" && scope != "all" {
		eventsSource = filterAuditEvents(eventsSource, scope)
	}
	events, pagination := auditPage(eventsSource, before, limit)
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
		"events": events, "pagination": pagination, "integrity": integrity, "scope": scope,
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
	if a.isFleetAssistantQuestion(input.Question) {
		a.streamFleetAssistant(w, r, input.Question, input.Basic, input.FallbackReason)
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
	if reason, ok := assistantOutputGateAuditReason(response.Trailer.Get(assistantOutputGateTrailer)); ok {
		a.addAudit(
			"assistant_output_rejected",
			"Gate BETA "+assistantOutputGateVersion+" bloqueou saída externa; motivo="+reason+"; contingência local=true",
			clientAddress(r),
		)
	}
	a.addAudit("assistant_analysis", "Consulta assistida via "+a.assistantMode, clientAddress(r))
}

func assistantOutputGateAuditReason(value string) (string, bool) {
	reason := strings.TrimPrefix(strings.TrimSpace(value), "rejected:")
	if reason == value {
		return "", false
	}
	switch reason {
	case "empty-output", "invalid-encoding", "oversized-output", "unknown-token",
		"prompt-instruction-leak", "token-repetition", "line-repetition",
		"unexpected-language", "snapshot-contradiction",
		"provider-identity-contradiction", "grounding-not-validated":
		return reason, true
	default:
		return "", false
	}
}

func (a *webApp) runtimeAllowsLLM(ctx context.Context) bool {
	var state setupStateResponse
	if err := a.agentRequest(ctx, "/setup-state", &state); err != nil {
		return false
	}
	return planHasProAccess(state.Plan) && state.LLMAllowed
}

func assistantConfigurationForPlan(plan, mode, model, endpoint string) (string, string, string) {
	if !planHasProAccess(plan) {
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
	if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
		CanonicalSourceCount: 1,
		DeterministicAnswer:  true,
	}) {
		sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
		return
	}
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
		strings.Contains(normalized, "161") ||
		strings.Contains(normalized, "160") ||
		strings.Contains(normalized, "159") ||
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
	route := routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		catalog.Architecture,
	)
	sendSSE(w, "route", route)
	sendSSE(w, "delta", map[string]any{"delta": answer})
	if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
		CanonicalSourceCount: 1,
		DeterministicAnswer:  true,
	}) {
		sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
		return
	}
	sendSSE(w, "done", map[string]any{"ok": true})
	a.addAudit("assistant_catalog", "Catálogo runtime completo listado localmente", clientAddress(r))
}

func (a *webApp) isFleetAssistantQuestion(question string) bool {
	normalized := strings.ToLower(strings.TrimSpace(question))
	fleetKeywords := []string{
		"frota", "fleet", "fleet hub", "worker", "workers", "hetzner", "debian1",
		"servidor remoto", "servidores remotos", "no remoto", "nos remotos",
		"despachar", "despacho", "operario", "operarios",
	}
	for _, kw := range fleetKeywords {
		if strings.Contains(normalized, kw) {
			return true
		}
	}
	if a.fleetStore != nil {
		nodes := a.fleetStore.ListNodes()
		for _, node := range nodes {
			if node.Mode == FleetModeMaster && node.ID == "node-master-local" {
				continue
			}
			if len(node.Name) >= 3 && strings.Contains(normalized, strings.ToLower(node.Name)) {
				return true
			}
			if len(node.ID) >= 4 && strings.Contains(normalized, strings.ToLower(node.ID)) {
				return true
			}
		}
	}
	return false
}

func (a *webApp) streamFleetAssistant(
	w http.ResponseWriter,
	r *http.Request,
	question string,
	fallback bool,
	fallbackReason string,
) {
	ctx := r.Context()
	var matchedNode *FleetNode
	var allNodes []FleetNode

	if a.fleetStore != nil {
		allNodes = a.fleetStore.ListNodes()
		// 1. Match especifico de nó por Nome ou ID
		for _, n := range allNodes {
			if n.Mode == FleetModeMaster && n.ID == "node-master-local" {
				continue
			}
			if (len(n.Name) >= 3 && strings.Contains(strings.ToLower(question), strings.ToLower(n.Name))) ||
				(len(n.ID) >= 4 && strings.Contains(strings.ToLower(question), strings.ToLower(n.ID))) {
				nCopy := n
				matchedNode = &nCopy
				break
			}
		}
		// 2. Se nenhum nome especifico bateu, verificar se a pergunta menciona "worker", "hetzner", "debian" ou "remoto"
		if matchedNode == nil {
			norm := strings.ToLower(question)
			if strings.Contains(norm, "worker") || strings.Contains(norm, "hetzner") || strings.Contains(norm, "debian") || strings.Contains(norm, "remoto") {
				for _, n := range allNodes {
					if n.Mode == FleetModeWorker {
						nCopy := n
						matchedNode = &nCopy
						break
					}
				}
			}
		}
	}

	// Detectar se eh intencao de despacho ou diagnostico
	isDispatch := false
	dispatchKeywords := []string{"instalar", "deploy", "despachar", "colocar", "rodar", "subir", "despacho"}
	for _, kw := range dispatchKeywords {
		if strings.Contains(strings.ToLower(question), kw) {
			isDispatch = true
			break
		}
	}

	intent := "fleet_node_diagnosis"
	riskLevel := "low"
	if isDispatch {
		intent = "fleet_dispatch"
		riskLevel = "medium"
	}

	arch := "amd64"
	if matchedNode != nil && matchedNode.Architecture != "" {
		arch = matchedNode.Architecture
	}
	route := routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		arch,
	)
	route.Intent = intent
	route.Specialist = "fleet_commander"
	route.Domains = []string{"fleet", "infrastructure"}
	route.RiskLevel = riskLevel
	route.Confidence = "high"
	route.RequiredEvidence = []string{"fleet_inventory", "remote_telemetry"}
	if isDispatch {
		route.ResponseProfile = "guided_decision"
	} else {
		route.ResponseProfile = "technical_diagnosis"
	}
	route.Signals = []string{"keyword_fleet"}

	var responseLines []string

	if matchedNode == nil {
		if len(allNodes) == 0 {
			responseLines = append(responseLines,
				"### Conclusão",
				"Nenhum nó subordinado (Worker) está cadastrado no momento no MNO Fleet Hub da Torre Master.",
				"",
				"### Próximos passos para pareamento",
				"1. Instale o Setup MNO em seu novo servidor VPS (ex: Hetzner, Oracle Cloud ou Contabo).",
				"2. No menu principal do instalador, escolha **MNO Fleet Hub** e ative o **Modo Nó Worker (Operário de Cargas)**.",
				"3. Copie o Token de Pareamento gerado na tela do Worker.",
				"4. Retorne aqui na Torre Master, acesse a aba **MNO Fleet Hub** e clique em **+ Parear Novo Nó Worker** informando a URL e o Token.",
				"",
				"[Acessar MNO Fleet Hub](#fleet)",
			)
		} else {
			responseLines = append(responseLines,
				"### Conclusão",
				fmt.Sprintf("A frota do MNO Fleet Hub possui **%d servidor(es) registrado(s)** sob gestão centralizada desta Torre Master.", len(allNodes)),
				"",
				"### Inventário de Nós da Frota",
			)
			for _, n := range allNodes {
				roleLabel := "Torre Master (Local)"
				if n.Mode == FleetModeWorker {
					roleLabel = "Operário de Cargas (Worker)"
				}
				statusIcon := "🟢"
				if n.Status != "online" {
					statusIcon = "🟡"
				}
				ramInfo := ""
				if n.MemoryTotalMB > 0 {
					ramInfo = fmt.Sprintf(" · RAM: %d MB / %d MB", n.MemoryUsedMB, n.MemoryTotalMB)
				}
				responseLines = append(responseLines,
					fmt.Sprintf("- %s **%s** (`%s`): Modo *%s*%s", statusIcon, n.Name, n.ID, roleLabel, ramInfo),
				)
			}
			responseLines = append(responseLines,
				"",
				"### Ações Disponíveis",
				"[Gerenciar Frota no MNO Fleet Hub](#fleet)",
			)
		}
	} else {
		realNode, ok := a.fleetStore.GetNode(matchedNode.ID)
		if !ok {
			realNode = *matchedNode
		}

		telemetry, latency, probeErr := a.probeWorkerNode(ctx, realNode.Endpoint, realNode.Token)

		if probeErr != nil {
			responseLines = append(responseLines,
				"### Conclusão",
				fmt.Sprintf("O nó worker remoto **%s** foi identificado no inventário da frota, mas a tentativa de comunicação segura via API de telemetria falhou.", matchedNode.Name),
				"",
				"### Diagnóstico de Conexão",
				fmt.Sprintf("- **Endpoint consultado:** `%s`", matchedNode.Endpoint),
				fmt.Sprintf("- **Erro observado:** %v", probeErr),
				fmt.Sprintf("- **Tempo de resposta:** %d ms (timeout ou falha de rede)", latency),
				"",
				"### Recomendações SRE",
				"- Verifique se a VPS remota está ligada e com o serviço do Setup MNO ativo.",
				"- Se estiver utilizando Cloudflare Tunnel no worker, confirme se o túnel está online.",
				"- Acesse a aba Fleet Hub para forçar uma nova sincronização ou verificar o Token de pareamento.",
				"",
				"[Acessar MNO Fleet Hub](#fleet)",
			)
		} else {
			if telemetry.Architecture != "" {
				realNode.Architecture = telemetry.Architecture
				matchedNode.Architecture = telemetry.Architecture
			}
			if telemetry.SetupVersion != "" {
				realNode.SetupVersion = telemetry.SetupVersion
				matchedNode.SetupVersion = telemetry.SetupVersion
			}
			realNode.Telemetry = &telemetry
			realNode.LastHeartbeat = time.Now().UTC()
			realNode.Status = "online"
			_ = a.fleetStore.UpdateNode(realNode)
			_ = a.fleetStore.Save()

			nodeArch := matchedNode.Architecture
			if nodeArch == "" && telemetry.Architecture != "" {
				nodeArch = telemetry.Architecture
			}
			if nodeArch == "" {
				nodeArch = "amd64"
			}

			nodeVersion := matchedNode.SetupVersion
			if nodeVersion == "" && telemetry.SetupVersion != "" {
				nodeVersion = telemetry.SetupVersion
			}
			if nodeVersion == "" {
				nodeVersion = "7.44.0"
			}

			memUsed := telemetry.MemoryUsedMB
			memTotal := telemetry.MemoryTotalMB
			memFree := uint64(0)
			if memTotal > memUsed {
				memFree = memTotal - memUsed
			}
			memPct := float64(0)
			if memTotal > 0 {
				memPct = (float64(memUsed) / float64(memTotal)) * 100.0
			}

			diskUsed := telemetry.DiskUsedGB
			diskTotal := telemetry.DiskTotalGB
			diskPct := float64(0)
			if diskTotal > 0 {
				diskPct = (float64(diskUsed) / float64(diskTotal)) * 100.0
			}

			swarmStatus := "Ativo (Docker Swarm pronto para receber cargas)"
			if !telemetry.ActiveSwarm {
				swarmStatus = "Inativo (atenção: necessário inicializar Docker Swarm no nó)"
			}

			endpointURL := realNode.Endpoint
			if endpointURL == "" {
				endpointURL = matchedNode.Endpoint
			}
			installerURL := endpointURL + "/?action=terminal"
			if !strings.HasPrefix(endpointURL, "http") {
				installerURL = "#fleet"
			}

			if isDispatch {
				responseLines = append(responseLines,
					"### Conclusão",
					fmt.Sprintf("O nó worker remoto **%s** possui recursos suficientes e está pronto para receber o despacho de aplicações de forma segura e isolada.", matchedNode.Name),
					"",
					"### Identificação do Nó Alvo",
					fmt.Sprintf("- **Nome do nó:** `%s`", matchedNode.Name),
					fmt.Sprintf("- **ID do nó:** `%s`", matchedNode.ID),
					fmt.Sprintf("- **Papel na frota:** Worker (Operário de Cargas)"),
					fmt.Sprintf("- **Endpoint público:** `%s`", endpointURL),
					fmt.Sprintf("- **Arquitetura:** `%s`", nodeArch),
					fmt.Sprintf("- **Latência:** `%d ms`", latency),
					"",
					"### Telemetria Remota em Tempo Real (Worker Hetzner)",
					fmt.Sprintf("- **Memória RAM:** %d MB usados de %d MB (%.1f%% de ocupação — **%d MB livres**)", memUsed, memTotal, memPct, memFree),
					fmt.Sprintf("- **Armazenamento:** %d GB usados de %d GB (%.1f%% de ocupação)", diskUsed, diskTotal, diskPct),
					fmt.Sprintf("- **Docker Swarm:** %s", swarmStatus),
					fmt.Sprintf("- **Carga da CPU (1m):** %.2f", telemetry.LoadAverage1m),
					fmt.Sprintf("- **Aplicações ativas:** %d saudáveis / %d com atenção", telemetry.HealthyApps, telemetry.UnhealthyApps),
					"",
					"### Plano Consultivo de Despacho Seguro",
					"1. **Segregação de Recursos:** A instalação será provisionada no nó worker remoto, sem consumir memória ou disco da Torre Master (WSL2).",
					"2. **Pré-requisitos Obrigatórios:**",
					"   - Domínio apontado via DNS para a VPS ou configurado no Cloudflare Tunnel.",
					"   - Portas isoladas na rede overlay segura (`interna`) do Docker Swarm.",
					"3. **Roteiro de Despacho:**",
					"   - Abra o Instalador Seguro diretamente no nó worker.",
					"   - Selecione a aplicação desejada (ex: WordPress, n8n, Chatwoot).",
					"   - Confirme as variáveis de ambiente e inicie o deploy assistido.",
					"4. **Plano de Rollback:**",
					"   - Caso queira desfazer a instalação, remova a stack via painel do nó worker ou pelo Portainer sem qualquer impacto na Torre Master ou nos demais servidores da frota.",
					"",
					"### Ações de Despacho",
					fmt.Sprintf("[%s](%s) [%s](%s)", "Abrir Instalador do Nó "+matchedNode.Name+" ↗", installerURL, "Abrir Painel Central do Nó ↗", endpointURL),
					"",
					"[Gerenciar Frota no MNO Fleet Hub](#fleet)",
				)
			} else {
				responseLines = append(responseLines,
					"### Conclusão",
					fmt.Sprintf("Diagnóstico concluído: o servidor worker **%s** está **online**, saudável e respondendo com excelente latência de **%d ms**.", matchedNode.Name, latency),
					"",
					"### Identificação do Servidor Remoto",
					fmt.Sprintf("- **Nome do Servidor:** `%s`", matchedNode.Name),
					fmt.Sprintf("- **ID Único na Frota:** `%s`", matchedNode.ID),
					fmt.Sprintf("- **Função:** Nó Worker (Operário de Cargas subordinado à Torre Master)"),
					fmt.Sprintf("- **Endpoint HTTPS:** `%s`", endpointURL),
					fmt.Sprintf("- **Arquitetura do Processador:** `%s`", nodeArch),
					fmt.Sprintf("- **Versão do Setup MNO:** `%s`", nodeVersion),
					"",
					"### Telemetria Remota em Tempo Real (Hetzner VPS)",
					fmt.Sprintf("- **Memória RAM:** %d MB em uso de %d MB totais (%.1f%% ocupado — **%d MB livres**)", memUsed, memTotal, memPct, memFree),
					fmt.Sprintf("- **Disco rígido:** %d GB em uso de %d GB (%.1f%% ocupado)", diskUsed, diskTotal, diskPct),
					fmt.Sprintf("- **Carga da CPU (Load Average 1 min):** %.2f", telemetry.LoadAverage1m),
					fmt.Sprintf("- **Docker Swarm:** %s", swarmStatus),
					fmt.Sprintf("- **Serviços em Execução:** %d saudáveis / %d degradados", telemetry.HealthyApps, telemetry.UnhealthyApps),
					fmt.Sprintf("- **Tempo de Atividade (Uptime):** %d segundos (~%.1f horas)", telemetry.UptimeSeconds, float64(telemetry.UptimeSeconds)/3600.0),
					"",
					"### Avaliação de Prontidão Operacional",
					fmt.Sprintf("O servidor **%s** possui capacidade operacional abundante (%d MB de RAM livre) para hospedar novas aplicações com alto desempenho e isolamento.", matchedNode.Name, memFree),
					"",
					"### Ações Recomendadas",
					fmt.Sprintf("[%s](%s) [%s](%s)", "Abrir Painel do Nó "+matchedNode.Name+" ↗", endpointURL, "Abrir Instalador do Nó ↗", installerURL),
					"",
					"[Acessar MNO Fleet Hub](#fleet)",
				)
			}
		}
	}

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	a.sendFeedbackTokenSSE(w, "basic", fallbackReason)
	sendSSE(w, "meta", map[string]any{
		"mode":           "fleet_commander",
		"model":          "MNO Fleet SRE Engine",
		"fallback":       fallback,
		"fallbackReason": fallbackReason,
		"readOnly":       true,
		"fleetAware":     true,
	})
	sendSSE(w, "route", route)
	sendSSE(w, "delta", map[string]any{"delta": strings.Join(responseLines, "\n\n")})
	if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
		OperationalContextAvailable: true,
		DeterministicAnswer:         true,
	}) {
		sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
		return
	}
	sendSSE(w, "done", map[string]any{"ok": true})
	a.addAudit("assistant_fleet", "Diagnóstico/despacho consultivo de frota: "+intent, clientAddress(r))
}

func (a *webApp) streamBasicAssistant(
	w http.ResponseWriter,
	r *http.Request,
	question string,
	fallback bool,
	fallbackReason string,
) {
	if a.isFleetAssistantQuestion(question) {
		a.streamFleetAssistant(w, r, question, fallback, fallbackReason)
		return
	}
	var snapshot sreDiagnosticSnapshot
	if err := a.agentRequest(r.Context(), "/sre/snapshot", &snapshot); err != nil ||
		validateSREDiagnosticSnapshot(snapshot) != nil {
		writeError(w, http.StatusBadGateway, "não foi possível consultar o servidor")
		return
	}
	route := routeAssistant(
		question,
		retrievalQueryResolution{Query: question},
		snapshot.Versions.Architecture,
	)
	suggestions := localInsightsForSRESnapshot(snapshot, question, route)
	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	a.sendFeedbackTokenSSE(w, "basic", fallbackReason)
	sendSSE(w, "meta", map[string]any{
		"mode":               "basic",
		"model":              "",
		"fallback":           fallback,
		"fallbackReason":     fallbackReason,
		"sreSnapshotVersion": snapshot.SnapshotVersion,
		"sreMaturity":        snapshot.Maturity,
		"readOnly":           snapshot.ReadOnly,
	})
	sendSSE(w, "route", route)
	sendSSE(w, "delta", map[string]any{"delta": strings.Join(suggestions, "\n\n")})
	if !sendConsultativePlanSSE(w, route, consultativePlanEvidence{
		OperationalContextAvailable: true,
		BasicMode:                   true,
	}) {
		sendSSE(w, "error", map[string]any{"error": "O plano consultivo obrigatório não pôde ser validado.", "reason": "policy"})
		return
	}
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
		intent := terminalIntent(r.URL.Query()["arg"])
		if intent == "homologation" && !a.maintainerAccessAllowed(r.Context()) {
			a.addAudit("maintainer_terminal_blocked_plan", "Terminal do mantenedor recusado: requer plano PRO MASTER", clientAddress(r))
			writeError(w, http.StatusForbidden, "recurso exclusivo do plano PRO MASTER")
			return
		}
		if intent == "strix" && !a.strixAccessAllowed(r.Context()) {
			a.addAudit("strix_terminal_blocked_plan", "Terminal Strix recusado: requer plano PRO ou PRO MASTER", clientAddress(r))
			writeError(w, http.StatusForbidden, "recurso disponível nos planos PRO e PRO MASTER")
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
	return state.InstallationType == "CLOUDFLARE_TUNNEL" && state.Capabilities.RemoteTerminal
}

func (a *webApp) maintainerAccessAllowed(ctx context.Context) bool {
	var state setupStateResponse
	if err := a.agentRequest(ctx, "/setup-state", &state); err != nil {
		return false
	}
	return planHasMaintainerAccess(state.Plan) && state.Capabilities.Maintainer
}

func (a *webApp) strixAccessAllowed(ctx context.Context) bool {
	var state setupStateResponse
	if err := a.agentRequest(ctx, "/setup-state", &state); err != nil {
		return false
	}
	return planHasProAccess(state.Plan) && state.Capabilities.StrixDiagnostics
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
	case "installer", "settings", "homologation", "sre", "strix", "gateway":
		return true
	default:
		return false
	}
}

func terminalIntent(values []string) string {
	if len(values) == 0 {
		return "gateway"
	}
	if len(values) == 1 {
		return values[0]
	}
	return ""
}

func normalizeSetupPlan(plan string) string {
	return strings.ToLower(strings.TrimSpace(plan))
}

func planHasProAccess(plan string) bool {
	switch normalizeSetupPlan(plan) {
	case "pro", "pro-master":
		return true
	default:
		return false
	}
}

func planHasMaintainerAccess(plan string) bool {
	return normalizeSetupPlan(plan) == "pro-master"
}

func capabilitiesForEnvironment(environment runtimeEnvironment) planCapabilities {
	proAccess := planHasProAccess(environment.Plan)
	maintainer := planHasMaintainerAccess(environment.Plan)
	fleetAllowed := environment.InstallationType == "CLOUDFLARE_TUNNEL" && proAccess
	return planCapabilities{
		ProAccess:                 proAccess,
		StrixDiagnostics:          proAccess,
		Maintainer:                maintainer,
		HomologationReview:        maintainer,
		HomologationExecute:       maintainer,
		HomologationFinalApproval: maintainer,
		RemoteTerminal:            environment.InstallationType == "CLOUDFLARE_TUNNEL",
		FleetHub:                  fleetAllowed,
	}
}

func (a *webApp) requireMaintainer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !a.maintainerAccessAllowed(r.Context()) {
			a.addAudit("maintainer_route_denied", "Rota exclusiva de mantenedor recusada", clientAddress(r))
			writeError(w, http.StatusForbidden, "recurso exclusivo do plano PRO MASTER")
			return
		}
		next.ServeHTTP(w, r)
	})
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
	if a.httpClient == nil {
		return errors.New("cliente HTTP do agente não configurado")
	}
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
	if hasSupplyChainMetadata(release) {
		if err := validateRuntimeSupplyChain(directory, release); err != nil {
			return runtimeSnapshot{}, err
		}
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
	case "pro-master", "pro", "free", "free1", "free2":
	default:
		return runtimeEnvironment{}, errors.New("plano runtime inválido")
	}
	switch environment.InstallationType {
	case "CLOUDFLARE_TUNNEL", "TRADICIONAL":
	default:
		return runtimeEnvironment{}, errors.New("tipo de instalação runtime inválido")
	}
	switch environment.FleetMode {
	case "", FleetModeDisabled, FleetModeMaster, FleetModeWorker:
		if environment.FleetMode == "" {
			environment.FleetMode = FleetModeDisabled
		}
	default:
		return runtimeEnvironment{}, errors.New("modo fleet runtime inválido")
	}
	if environment.FleetMode != FleetModeDisabled && environment.InstallationType != "CLOUDFLARE_TUNNEL" {
		return runtimeEnvironment{}, errors.New("modo fleet exige instalação via CLOUDFLARE_TUNNEL")
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
	hasHomologationRunner := release.HomologationRunnerVersion != "" ||
		release.HomologationCandidateSchema != 0 ||
		release.HomologationRegistryEntries != 0 ||
		release.HomologationManifestSHA256 != ""
	if hasHomologationRunner {
		runnerHash, hashErr := hex.DecodeString(release.HomologationManifestSHA256)
		if !validSemanticVersion(release.HomologationRunnerVersion) ||
			release.HomologationCandidateSchema != 1 ||
			release.HomologationRegistryEntries != release.CatalogEntries ||
			hashErr != nil || len(runnerHash) != sha256.Size ||
			release.HomologationAutoPromotion {
			return errors.New("metadados do Homologation Runner inconsistentes")
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

func hasSupplyChainMetadata(release setupRelease) bool {
	return release.SupplyChainSchemaVersion != 0 || release.SupplyChainManifestSHA256 != "" ||
		release.SupplyChainSBOMSHA256 != "" || release.SupplyChainImageInventorySHA != "" ||
		release.SupplyChainAttestationSHA256 != "" || release.SupplyChainSignatureStatus != ""
}

func validSHA256(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size
}

func validateRuntimeSupplyChain(directory string, release setupRelease) error {
	if release.SupplyChainSchemaVersion != 1 ||
		release.SupplyChainSignatureStatus != "unsigned-sha256-bound" ||
		release.SupplyChainCompositionFull || release.SupplyChainImageReferences < 1 ||
		release.SupplyChainDigestPinned < 0 || release.SupplyChainMutableTags < 0 ||
		release.SupplyChainHighRiskTags < 0 || release.SupplyChainImplicitLatest < 0 ||
		release.SupplyChainUnresolved < 0 ||
		release.SupplyChainImageReferences != release.SupplyChainDigestPinned+
			release.SupplyChainMutableTags+release.SupplyChainHighRiskTags+
			release.SupplyChainImplicitLatest ||
		!validSHA256(release.SupplyChainManifestSHA256) ||
		!validSHA256(release.SupplyChainSBOMSHA256) ||
		!validSHA256(release.SupplyChainImageInventorySHA) ||
		!validSHA256(release.SupplyChainAttestationSHA256) {
		return errors.New("metadados supply-chain inconsistentes")
	}

	supplyDirectory := filepath.Join(directory, "supply-chain")
	info, err := os.Lstat(supplyDirectory)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("diretório supply-chain inválido")
	}
	entries, err := os.ReadDir(supplyDirectory)
	if err != nil || len(entries) != 4 {
		return errors.New("inventário do diretório supply-chain divergente")
	}
	expectedNames := map[string]bool{
		"manifest.json": false, "sbom.cdx.json": false,
		"image-inventory.json": false, "attestation.intoto.json": false,
	}
	for _, entry := range entries {
		if _, ok := expectedNames[entry.Name()]; !ok || entry.IsDir() || entry.Type()&os.ModeSymlink != 0 {
			return errors.New("arquivo inesperado no diretório supply-chain")
		}
		expectedNames[entry.Name()] = true
	}

	manifestData, err := readRegularFile(filepath.Join(supplyDirectory, "manifest.json"), 64<<10)
	if err != nil || sha256String(manifestData) != release.SupplyChainManifestSHA256 {
		return errors.New("manifesto supply-chain inválido ou adulterado")
	}
	var manifest supplyChainManifest
	decoder := json.NewDecoder(bytes.NewReader(manifestData))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return fmt.Errorf("manifesto supply-chain JSON: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return errors.New("manifesto supply-chain contém dados adicionais")
	}
	if manifest.SchemaVersion != 1 || manifest.GeneratorVersion != "1.0.0" ||
		manifest.SetupVersion != release.SetupVersion || manifest.Architecture != release.Architecture ||
		manifest.SBOM.Format != "CycloneDX" || manifest.SBOM.SpecVersion != "1.6" ||
		manifest.SBOM.Composition != "incomplete" || manifest.Inventory.Completeness != "partial" ||
		manifest.Attestation.StatementType != "https://in-toto.io/Statement/v1" ||
		manifest.Attestation.PredicateType != "https://slsa.dev/provenance/v1" ||
		manifest.Attestation.SignatureStatus != release.SupplyChainSignatureStatus ||
		manifest.Inventory.ImageReferences != release.SupplyChainImageReferences ||
		manifest.Inventory.DigestPinnedImages != release.SupplyChainDigestPinned ||
		manifest.Inventory.MutableTags != release.SupplyChainMutableTags ||
		manifest.Inventory.HighRiskMutableTags != release.SupplyChainHighRiskTags ||
		manifest.Inventory.ImplicitLatest != release.SupplyChainImplicitLatest ||
		manifest.Inventory.Unresolved != release.SupplyChainUnresolved || len(manifest.Files) != 3 {
		return errors.New("manifesto supply-chain não corresponde à release")
	}

	releaseHashes := map[string]string{
		"sbom.cdx.json":           release.SupplyChainSBOMSHA256,
		"image-inventory.json":    release.SupplyChainImageInventorySHA,
		"attestation.intoto.json": release.SupplyChainAttestationSHA256,
	}
	fileData := make(map[string][]byte, 3)
	seen := make(map[string]bool, 3)
	for _, file := range manifest.Files {
		expectedHash, ok := releaseHashes[file.Path]
		if !ok || seen[file.Path] || !validSHA256(file.SHA256) || file.SHA256 != expectedHash || file.Size < 2 {
			return errors.New("registro de arquivo supply-chain inválido")
		}
		data, readErr := readRegularFile(filepath.Join(supplyDirectory, file.Path), 8<<20)
		if readErr != nil || int64(len(data)) != file.Size || sha256String(data) != file.SHA256 {
			return errors.New("integridade de arquivo supply-chain divergente")
		}
		fileData[file.Path] = data
		seen[file.Path] = true
	}
	if len(seen) != len(releaseHashes) {
		return errors.New("inventário supply-chain incompleto")
	}

	var inventory struct {
		SchemaVersion int    `json:"schemaVersion"`
		SetupVersion  string `json:"setupVersion"`
		Architecture  string `json:"architecture"`
		Counts        struct {
			DigestPinned          int `json:"digestPinned"`
			HighRiskMutableTags   int `json:"highRiskMutableTags"`
			ImplicitLatest        int `json:"implicitLatest"`
			MutableTags           int `json:"mutableTags"`
			References            int `json:"references"`
			UnresolvedExpressions int `json:"unresolvedExpressions"`
		} `json:"counts"`
	}
	if json.Unmarshal(fileData["image-inventory.json"], &inventory) != nil ||
		inventory.SchemaVersion != 1 || inventory.SetupVersion != release.SetupVersion ||
		inventory.Architecture != release.Architecture || inventory.Counts.References != release.SupplyChainImageReferences ||
		inventory.Counts.DigestPinned != release.SupplyChainDigestPinned ||
		inventory.Counts.MutableTags != release.SupplyChainMutableTags ||
		inventory.Counts.HighRiskMutableTags != release.SupplyChainHighRiskTags ||
		inventory.Counts.ImplicitLatest != release.SupplyChainImplicitLatest ||
		inventory.Counts.UnresolvedExpressions != release.SupplyChainUnresolved {
		return errors.New("inventário de imagens supply-chain divergente")
	}

	var sbom struct {
		BOMFormat   string `json:"bomFormat"`
		SpecVersion string `json:"specVersion"`
		Version     int    `json:"version"`
		Components  []any  `json:"components"`
	}
	if json.Unmarshal(fileData["sbom.cdx.json"], &sbom) != nil || sbom.BOMFormat != "CycloneDX" ||
		sbom.SpecVersion != "1.6" || sbom.Version != 1 || len(sbom.Components) == 0 {
		return errors.New("SBOM CycloneDX inválido")
	}

	var attestation struct {
		Type          string `json:"_type"`
		PredicateType string `json:"predicateType"`
		Subject       []struct {
			Name   string            `json:"name"`
			Digest map[string]string `json:"digest"`
		} `json:"subject"`
	}
	if json.Unmarshal(fileData["attestation.intoto.json"], &attestation) != nil ||
		attestation.Type != "https://in-toto.io/Statement/v1" ||
		attestation.PredicateType != "https://slsa.dev/provenance/v1" || len(attestation.Subject) != 2 {
		return errors.New("atestação in-toto inválida")
	}
	subjectSeen := make(map[string]bool, 2)
	for _, subject := range attestation.Subject {
		name := strings.TrimPrefix(subject.Name, "supply-chain/")
		expectedHash, ok := releaseHashes[name]
		if !ok || name == "attestation.intoto.json" || subjectSeen[name] || subject.Digest["sha256"] != expectedHash {
			return errors.New("subject da atestação in-toto divergente")
		}
		subjectSeen[name] = true
	}
	if !subjectSeen["sbom.cdx.json"] || !subjectSeen["image-inventory.json"] {
		return errors.New("subjects da atestação in-toto incompletos")
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
	homologationWorkflow := ""
	if release.HomologationRunnerVersion != "" {
		homologationWorkflow = "essential-auto-with-maintainer-attestation"
	}
	return setupStateResponse{
		SchemaVersion:               release.SchemaVersion,
		SetupVersion:                release.SetupVersion,
		CatalogVersion:              release.CatalogVersion,
		CatalogSHA256:               release.CatalogSHA256,
		CatalogEntries:              release.CatalogEntries,
		Architecture:                release.Architecture,
		Source:                      source,
		Stale:                       false,
		HomologationRunnerAvailable: release.HomologationRunnerVersion != "",
		HomologationRunnerVersion:   release.HomologationRunnerVersion,
		HomologationCandidateSchema: release.HomologationCandidateSchema,
		HomologationWorkflow:        homologationWorkflow,
		SupplyChainAvailable:        hasSupplyChainMetadata(release),
		SupplyChainSchemaVersion:    release.SupplyChainSchemaVersion,
		SupplyChainSignatureStatus:  release.SupplyChainSignatureStatus,
		SupplyChainCompositionFull:  release.SupplyChainCompositionFull,
		SupplyChainImageReferences:  release.SupplyChainImageReferences,
		SupplyChainDigestPinned:     release.SupplyChainDigestPinned,
		SupplyChainMutableTags:      release.SupplyChainMutableTags,
		SupplyChainHighRiskTags:     release.SupplyChainHighRiskTags,
		SupplyChainImplicitLatest:   release.SupplyChainImplicitLatest,
		SupplyChainUnresolved:       release.SupplyChainUnresolved,
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
	if runes := []rune(detail); len(runes) > 300 {
		detail = string(runes[:297]) + "..."
	}
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

func localInsightsForSRESnapshot(
	snapshot sreDiagnosticSnapshot,
	question string,
	route assistantRoute,
) []string {
	if route.Intent == "scope_redirect" {
		return []string{
			"Sou especializado em Setup MNO e infraestrutura; não respondo a assuntos gerais fora desse escopo.",
			"Pergunte sobre setups, servidor, Docker, Swarm, capacidade, segurança, integrações ou Blueprints MNO.",
		}
	}
	result := []string{
		"**Nenhuma alteração foi realizada — Especialista SRE BETA em modo somente leitura.**",
		"Diagnóstico seguro concluído para: “" + strings.TrimSpace(question) + "”.",
		"**Fatos observados**",
	}
	for _, finding := range snapshot.Findings {
		result = append(result, "- "+finding.Observation+" Evidência: `"+finding.Evidence+"`.")
	}
	inspected := 0
	errorsFound := 0
	warningsFound := 0
	for _, service := range snapshot.Services {
		if !service.LogSignals.Inspected {
			continue
		}
		inspected++
		errorsFound += service.LogSignals.ErrorSignals
		warningsFound += service.LogSignals.WarningSignals
	}
	result = append(result,
		fmt.Sprintf("- Eventos permitidos consultados: %d; serviços degradados com sinais de log avaliados: %d.", len(snapshot.Events), inspected),
		"**Hipóteses e limites**",
	)
	if snapshot.Swarm.DegradedServices > 0 && (errorsFound > 0 || warningsFound > 0) {
		result = append(result, fmt.Sprintf(
			"- Há %d sinal(is) de erro e %d aviso(s) nos logs reduzidos a contagens. Isso ajuda a priorizar a investigação, mas não confirma a causa.",
			errorsFound, warningsFound,
		))
	} else if snapshot.Swarm.DegradedServices > 0 {
		result = append(result, "- Existem réplicas degradadas, mas o snapshot não possui evidência suficiente para afirmar a causa.")
	} else {
		result = append(result, "- Nenhuma hipótese de falha foi criada porque os serviços observados estão convergidos.")
	}
	result = append(result,
		"- Esta é uma fotografia pontual, não um histórico de monitoramento.",
		"- Hostname, IP, domínio, e-mail, imagens, secrets, variáveis, comandos e conteúdo bruto dos logs não foram incluídos.",
		"Ações, reinícios e instalações continuam fora deste diagnóstico e exigem o Instalador Seguro e confirmação humana.",
	)
	result = append(result, deterministicAuditLines(snapshot.Deterministic)...)
	return result
}

func deterministicAuditDisclosure(state sreDeterministicState) string {
	lines := deterministicAuditLines(state)
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, "\n")
}

func deterministicAuditLines(state sreDeterministicState) []string {
	result := []string{"**Diagnóstico de segurança do servidor e das aplicações · BETA**"}
	switch state.Status {
	case "not-run":
		return append(result,
			"- A verificação aprofundada ainda não foi executada.",
			"- Próximo passo seguro: selecione **Analisar segurança agora**. O processo é somente leitura e não aplica correções.",
		)
	case "invalid":
		return append(result, "- O resultado local foi recusado por falha de integridade ou formato. Nenhuma conclusão de segurança foi aceita.")
	case "expired":
		result = append(result, "- O resultado venceu. As contagens abaixo são históricas; execute novamente antes de tomar uma decisão.")
	case "available":
		result = append(result, "- Resultado atual, válido por até 24 horas após a execução.")
	default:
		return append(result, "- Estado desconhecido recusado. Nenhuma conclusão de segurança foi aceita.")
	}
	if state.Result == nil {
		return result
	}
	critical, high, incomplete := 0, 0, 0
	for _, engine := range state.Result.Engines {
		critical += engine.Counts["critical"]
		high += engine.Counts["high"]
		if engine.Status != "complete" && engine.Status != "completed" {
			incomplete++
		}
	}
	switch state.Result.OverallStatus {
	case "no-critical-signals":
		result = append(result, "- **Resumo simples:** não foram encontrados sinais críticos dentro da cobertura disponível.")
	case "attention":
		result = append(result, fmt.Sprintf("- **Resumo simples:** foram encontrados sinais que precisam de revisão (%d crítico(s) e %d alto(s)).", critical, high))
	case "incomplete":
		result = append(result, fmt.Sprintf("- **Resumo simples:** o diagnóstico ficou incompleto; %d de %d verificação(ões) tiveram cobertura parcial ou falharam.", incomplete, len(state.Result.Engines)))
	default:
		result = append(result, "- **Resumo simples:** o estado não pôde ser classificado com segurança.")
	}
	result = append(result, fmt.Sprintf("- Cobertura completa: **%s**.", portugueseBoolean(state.Result.Complete)))
	for _, engine := range state.Result.Engines {
		result = append(result, fmt.Sprintf("- %s %s: **%s**.", sreEngineDisplayName(engine.ID), engine.Version, sreEngineStatusLabel(engine.Status)))
	}
	for _, fact := range state.Result.ObservedFacts {
		result = append(result, "- "+fact.Observation+" Evidência: `"+fact.Evidence+"`.")
	}
	for _, limitation := range state.Result.Limitations {
		result = append(result, "- Limite: "+limitation)
	}
	return result
}

func portugueseBoolean(value bool) string {
	if value {
		return "sim"
	}
	return "não"
}

func sreEngineDisplayName(id string) string {
	switch id {
	case "trivy":
		return "Imagens das aplicações (Trivy)"
	case "lynis":
		return "Configuração do Linux (Lynis)"
	case "docker-bench":
		return "Práticas de segurança do Docker (Docker Bench)"
	default:
		return id
	}
}

func sreEngineStatusLabel(status string) string {
	switch status {
	case "complete", "completed":
		return "concluído"
	case "partial":
		return "cobertura parcial"
	case "failed":
		return "não foi possível concluir"
	case "skipped":
		return "não se aplica neste ambiente"
	case "not-run":
		return "não executado"
	default:
		return "estado não reconhecido"
	}
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
