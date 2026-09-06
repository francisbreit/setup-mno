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
	NodeID        string    `json:"nodeId"`
	Mode          FleetMode `json:"mode"`
	Architecture  string    `json:"architecture,omitempty"`
	SetupVersion  string    `json:"setupVersion,omitempty"`
	UptimeSeconds int64     `json:"uptimeSeconds"`
	LoadAverage1m float64   `json:"loadAverage1m"`
	MemoryUsedMB  uint64    `json:"memoryUsedMB"`
	MemoryTotalMB uint64    `json:"memoryTotalMB"`
	DiskUsedGB    uint64    `json:"diskUsedGB"`
	DiskTotalGB   uint64    `json:"diskTotalGB"`
	ActiveSwarm   bool      `json:"activeSwarm"`
	HealthyApps   int       `json:"healthyApps"`
	UnhealthyApps int       `json:"unhealthyApps"`
	Timestamp     time.Time `json:"timestamp"`
}

// FleetStatusResponse representa o resumo do status da frota para o Control Center.
type FleetStatusResponse struct {
	Mode           FleetMode      `json:"mode"`
	NodeID         string         `json:"nodeId"`
	FleetAllowed   bool           `json:"fleetAllowed"`
	IsMaster       bool           `json:"isMaster"`
	IsWorker       bool           `json:"isWorker"`
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
