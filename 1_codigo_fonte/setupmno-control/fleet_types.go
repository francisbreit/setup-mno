package main

import "time"

// FleetMode define os três modos de operação de uma VPS no Setup MNO.
type FleetMode string

const (
	// FleetModeDisabled representa o Modo Simples Padrão (Standalone), com zero overhead.
	FleetModeDisabled FleetMode = "disabled"

	// FleetModeMaster representa a Torre de Controle da Frota (com painel central e Co-piloto).
	FleetModeMaster FleetMode = "master"

	// FleetModeWorker representa um Nó subordinado gerenciado por uma Torre Master.
	FleetModeWorker FleetMode = "worker"

	// fleetProbeTimeout é o limite de tempo para requisições de probe a nós remotos.
	fleetProbeTimeout = 5 * time.Second

	// fleetHeartbeatTimeout define o tempo máximo sem comunicação antes de um nó Worker ser considerado offline.
	fleetHeartbeatTimeout = 60 * time.Second

	// fleetMonitorInterval define o intervalo de varredura periódica de saúde dos nós remotos pela Torre Master.
	fleetMonitorInterval = 20 * time.Second
)

// FleetNode representa uma VPS registrada na frota de servidores.
type FleetNode struct {
	ID            string          `json:"id"`
	Name          string          `json:"name"`
	Endpoint      string          `json:"endpoint"`
	Mode          FleetMode       `json:"mode"`
	Status        string          `json:"status"` // "online", "degraded", "offline", "unknown"
	Role          string          `json:"role,omitempty"`
	Tags          []string        `json:"tags,omitempty"`
	Token         string          `json:"token,omitempty"`
	Architecture  string          `json:"architecture,omitempty"`
	SetupVersion  string          `json:"setupVersion,omitempty"`
	MemoryTotalMB uint64          `json:"memoryTotalMB"`
	MemoryUsedMB  uint64          `json:"memoryUsedMB"`
	CPUUsagePct   float64         `json:"cpuUsagePercent"`
	ServiceCount  int             `json:"serviceCount"`
	TunnelHealthy bool            `json:"tunnelHealthy"`
	LastHeartbeat time.Time       `json:"lastHeartbeat"`
	Telemetry     *FleetTelemetry `json:"telemetry,omitempty"`
	Lock          *FleetNodeLock  `json:"lock,omitempty"`
}

// FleetActionRequest representa um comando remoto seguro enviado da Torre Master para um Worker.
type FleetActionRequest struct {
	ActionID  string         `json:"actionId"`
	Action    string         `json:"action"` // "ping", "healthcheck", "sync_status"
	TargetID  string         `json:"targetId,omitempty"`
	Payload   map[string]any `json:"payload,omitempty"`
	Signature string         `json:"signature,omitempty"`
	Timestamp int64          `json:"timestamp"`
}

// FleetActionResponse representa a resposta atômica do Worker após executar uma ação.
type FleetActionResponse struct {
	ActionID string         `json:"actionId"`
	Success  bool           `json:"success"`
	Output   string         `json:"output,omitempty"`
	Data     map[string]any `json:"data,omitempty"`
	Error    string         `json:"error,omitempty"`
}

// FleetTelemetry representa o resumo de telemetria retornado em tempo real pelo nó.
type FleetTelemetry struct {
	NodeID        string         `json:"nodeId"`
	Mode          FleetMode      `json:"mode"`
	Architecture  string         `json:"architecture,omitempty"`
	SetupVersion  string         `json:"setupVersion,omitempty"`
	UptimeSeconds int64          `json:"uptimeSeconds"`
	LoadAverage1m float64        `json:"loadAverage1m"`
	MemoryUsedMB  uint64         `json:"memoryUsedMB"`
	MemoryTotalMB uint64         `json:"memoryTotalMB"`
	DiskUsedGB    uint64         `json:"diskUsedGB"`
	DiskTotalGB   uint64         `json:"diskTotalGB"`
	ActiveSwarm   bool           `json:"activeSwarm"`
	HealthyApps   int            `json:"healthyApps"`
	UnhealthyApps int            `json:"unhealthyApps"`
	Timestamp     time.Time      `json:"timestamp"`
	Lock          *FleetNodeLock `json:"lock,omitempty"`
}

// FleetStatusResponse representa o resumo do status da frota para o Control Center.
type FleetStatusResponse struct {
	Mode           FleetMode      `json:"mode"`
	NodeID         string         `json:"nodeId"`
	FleetAllowed   bool           `json:"fleetAllowed"`
	IsMaster       bool           `json:"isMaster"`
	IsWorker       bool           `json:"isWorker"`
	FleetToken     string         `json:"fleetToken,omitempty"`
	TotalNodes     int            `json:"totalNodes"`
	OnlineNodes    int            `json:"onlineNodes"`
	DegradedNodes  int            `json:"degradedNodes"`
	OfflineNodes   int            `json:"offlineNodes"`
	LocalTelemetry FleetTelemetry `json:"localTelemetry"`
	Warning        string         `json:"warning,omitempty"`
}

// FleetAddNodeRequest representa o payload de adição de um novo Worker à Torre Master.
type FleetAddNodeRequest struct {
	ID       string   `json:"id,omitempty"`
	Name     string   `json:"name"`
	Endpoint string   `json:"endpoint"`
	Token    string   `json:"token"`
	Role     string   `json:"role,omitempty"`
	Tags     []string `json:"tags,omitempty"`
}

// FleetPingResponse representa o resultado de um probe de conectividade.
type FleetPingResponse struct {
	NodeID    string         `json:"nodeId"`
	Mode      FleetMode      `json:"mode"`
	Pong      bool           `json:"pong"`
	LatencyMs int64          `json:"latencyMs"`
	Status    string         `json:"status"`
	Telemetry FleetTelemetry `json:"telemetry,omitempty"`
	Error     string         `json:"error,omitempty"`
}

// fleetConfigResponse representa a resposta interna do agent para a configuração do Fleet Hub.
type fleetConfigResponse struct {
	FleetMode      FleetMode `json:"fleetMode"`
	FleetNodeID    string    `json:"fleetNodeId,omitempty"`
	FleetMasterURL string    `json:"fleetMasterUrl,omitempty"`
	FleetToken     string    `json:"fleetToken,omitempty"`
}

// FleetVolumeInfo representa informações de tamanho e ponto de montagem de um volume Docker.
type FleetVolumeInfo struct {
	Name       string `json:"name"`
	Driver     string `json:"driver,omitempty"`
	SizeBytes  uint64 `json:"sizeBytes"`
	MountPoint string `json:"mountPoint,omitempty"`
}

// FleetAppStructure representa os metadados de uma aplicação instalada em um nó.
type FleetAppStructure struct {
	Name             string            `json:"name"`             // Nome da stack (ex: "wordpress", "n8n")
	Services         []string          `json:"services"`         // Lista de serviços na stack
	Images           []string          `json:"images"`           // Imagens dos containers
	Volumes          []FleetVolumeInfo `json:"volumes"`          // Volumes associados
	RequiredMemoryMB uint64            `json:"requiredMemoryMB"` // Memória mínima estimada
	Domains          []string          `json:"domains"`          // Subdomínios vinculados
	Status           string            `json:"status"`           // "online", "degraded", "paused"
}

// FleetNodeStructure representa o raio-X completo da infraestrutura de um nó.
type FleetNodeStructure struct {
	NodeID        string              `json:"nodeId"`
	Name          string              `json:"name"`
	Mode          FleetMode           `json:"mode"`
	Role          string              `json:"role,omitempty"`
	Architecture  string              `json:"architecture"` // "amd64" ou "arm64"
	SetupVersion  string              `json:"setupVersion"`
	MemoryTotalMB uint64              `json:"memoryTotalMB"`
	MemoryFreeMB  uint64              `json:"memoryFreeMB"`
	DiskTotalGB   uint64              `json:"diskTotalGB"`
	DiskFreeGB    uint64              `json:"diskFreeGB"`
	SwarmActive   bool                `json:"swarmActive"`
	TunnelHealthy bool                `json:"tunnelHealthy"`
	TunnelID      string              `json:"tunnelId,omitempty"`
	Apps          []FleetAppStructure `json:"apps"`
	Timestamp     time.Time           `json:"timestamp"`
}

// FleetNodeSummary representa um resumo sucinto de um nó para decisões de preflight.
type FleetNodeSummary struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Architecture  string `json:"architecture"`
	Endpoint      string `json:"endpoint,omitempty"`
	MemoryFreeMB  uint64 `json:"memoryFreeMB"`
	DiskFreeGB    uint64 `json:"diskFreeGB"`
}

// FleetTransferPreflightResult expressa o veredito dos gates de segurança antes de transferir.
type FleetTransferPreflightResult struct {
	Allowed           bool             `json:"allowed"`
	Mode              string           `json:"mode"` // "transfer", "clone", "backup_only"
	AppName           string           `json:"appName"`
	OriginNode        FleetNodeSummary `json:"originNode"`
	DestNode          FleetNodeSummary `json:"destNode"`
	SameArchitecture  bool             `json:"sameArchitecture"`
	HasCapacity       bool             `json:"hasCapacity"`
	RequiredMemoryMB  uint64           `json:"requiredMemoryMB"`
	AvailableMemoryMB uint64           `json:"availableMemoryMB"`
	RequiredDiskGB    uint64           `json:"requiredDiskGB"`
	AvailableDiskGB   uint64           `json:"availableDiskGB"`
	DNSAction         string           `json:"dnsAction"` // "update_cname_and_ingress", "none"
	BlockReason       string           `json:"blockReason,omitempty"`
	Recommendation    string           `json:"recommendation"`
	IsCombo           bool             `json:"isCombo"`
	ComboName         string           `json:"comboName,omitempty"`
	LinkedStacks      []string         `json:"linkedStacks,omitempty"`
	ComboChoice       string           `json:"comboChoice,omitempty"` // "1" (all) ou "2" (single)
	UsesMinio         bool             `json:"usesMinio"`
	DestHasMinio      bool             `json:"destHasMinio"`
	MinioPolicy       string           `json:"minioPolicy,omitempty"` // "migrate" ou "keep_origin"
}

// FleetTransferExecutionRequest representa os parâmetros de disparo da transferência ou clone.
type FleetTransferExecutionRequest struct {
	AppName            string `json:"appName"`
	OriginNodeID       string `json:"originNodeId"`
	DestNodeID         string `json:"destNodeId"`
	Mode               string `json:"mode"` // "transfer" ou "clone"
	UpdateDNS          bool   `json:"updateDns"`
	StopOriginStack    bool   `json:"stopOriginStack"`
	ComboChoice        string `json:"comboChoice,omitempty"`
	MinioPolicy        string `json:"minioPolicy,omitempty"`
	SafetyFreezeSuffix string `json:"safetyFreezeSuffix,omitempty"`
	NotifySentinel     bool   `json:"notifySentinel"`
}

// FleetTransferExecutionResponse representa o resultado detalhado da execução da transferência.
type FleetTransferExecutionResponse struct {
	Success                bool     `json:"success"`
	TaskID                 string   `json:"taskId"`
	AppName                string   `json:"appName"`
	OriginNode             string   `json:"originNode"`
	DestNode               string   `json:"destNode"`
	Mode                   string   `json:"mode"`
	Status                 string   `json:"status,omitempty"`
	Message                string   `json:"message,omitempty"`
	TerminalIntent         string   `json:"terminalIntent,omitempty"`
	RequiredCommand        string   `json:"requiredCommand,omitempty"`
	ExecutionPlan          string   `json:"executionPlan,omitempty"`
	DNSUpdated             bool     `json:"dnsUpdated"`
	DNSRecords             []string `json:"dnsRecords,omitempty"`
	VolumesTransferred     int      `json:"volumesTransferred"`
	FrozenVolumes          []string `json:"frozenVolumes,omitempty"`
	OriginStackStopped     bool     `json:"originStackStopped"`
	NotificationDispatched bool     `json:"notificationDispatched"`
	DurationMs             int64    `json:"durationMs"`
	Error                  string   `json:"error,omitempty"`
}

// FleetBackupExecutionRequest representa os parâmetros de disparo de um backup de aplicação.
type FleetBackupExecutionRequest struct {
	AppName         string `json:"appName"`
	NodeID          string `json:"nodeId"`
	TargetDirectory string `json:"targetDirectory,omitempty"`
	NotifySentinel  bool   `json:"notifySentinel"`
}

// FleetBackupExecutionResponse representa o resultado da criação do backup portátil.
type FleetBackupExecutionResponse struct {
	Success      bool      `json:"success"`
	AppName      string    `json:"appName"`
	NodeID       string    `json:"nodeId"`
	Architecture string    `json:"architecture"`
	BackupFile   string    `json:"backupFile"`
	SizeBytes    int64     `json:"sizeBytes"`
	SHA256       string    `json:"sha256"`
	Timestamp    time.Time `json:"timestamp"`
	Error        string    `json:"error,omitempty"`
}

// FleetNodeLock representa a trava de ocupação atômica de um nó da frota (Node Lease / Lock).
type FleetNodeLock struct {
	Locked     bool      `json:"locked"`
	HolderID   string    `json:"holderId,omitempty"`
	HolderName string    `json:"holderName,omitempty"`
	Task       string    `json:"task,omitempty"`
	AcquiredAt time.Time `json:"acquiredAt,omitempty"`
	ExpiresAt  time.Time `json:"expiresAt,omitempty"`
}

// FleetLockRequest representa a requisição para adquirir, renovar ou liberar o lock do nó.
type FleetLockRequest struct {
	Action     string `json:"action"` // "acquire", "release", "status"
	HolderID   string `json:"holderId,omitempty"`
	HolderName string `json:"holderName,omitempty"`
	Task       string `json:"task,omitempty"`
	TTLSeconds int    `json:"ttlSeconds,omitempty"` // Default: 300 (5 min), Max: 1800 (30 min)
}

// FleetLockResponse representa a resposta do Worker sobre a trava.
type FleetLockResponse struct {
	Success bool          `json:"success"`
	Message string        `json:"message"`
	Lock    FleetNodeLock `json:"lock"`
}

// FleetImportInventoryRequest representa os parâmetros para importar nós de outra Torre Master.
type FleetImportInventoryRequest struct {
	MasterEndpoint string `json:"masterEndpoint"`
	MasterToken    string `json:"masterToken"`
	Strategy       string `json:"strategy,omitempty"` // "merge" (padrão) ou "replace"
}

// FleetImportInventoryResponse representa o resultado da importação entre Torres.
type FleetImportInventoryResponse struct {
	Success       bool        `json:"success"`
	Message       string      `json:"message"`
	ImportedCount int         `json:"importedCount"`
	Nodes         []FleetNode `json:"nodes,omitempty"`
}

// FleetExportInventoryResponse representa o pacote exportado pela Torre Master de origem.
type FleetExportInventoryResponse struct {
	SchemaVersion int         `json:"schemaVersion"`
	MasterNodeID  string      `json:"masterNodeId"`
	ExportedAt    time.Time   `json:"exportedAt"`
	Nodes         []FleetNode `json:"nodes"`
}
