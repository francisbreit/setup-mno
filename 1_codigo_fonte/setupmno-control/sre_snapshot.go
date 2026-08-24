package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

const (
	sreSnapshotSchema     = 1
	sreSnapshotVersion    = "1.0.0"
	sreSnapshotMaturity   = "beta"
	sreSnapshotSource     = "agent-fixed-read-only"
	sreMaxServices        = 60
	sreMaxEvents          = 40
	sreMaxLogServices     = 8
	sreMaxServiceLogBytes = 64 << 10
	sreMaxServiceLogLines = 200
)

type sreSnapshotPrivacy struct {
	Sanitized        bool     `json:"sanitized"`
	MutationAllowed  bool     `json:"mutationAllowed"`
	RawLogsIncluded  bool     `json:"rawLogsIncluded"`
	ServiceNamesUsed bool     `json:"serviceNamesIncluded"`
	Excluded         []string `json:"excluded"`
}

type sreSnapshotVersions struct {
	SetupVersion    string `json:"setupVersion"`
	ControlVersion  string `json:"controlVersion"`
	Architecture    string `json:"architecture"`
	OperatingSystem string `json:"operatingSystem"`
	OSVersion       string `json:"osVersion,omitempty"`
	OSType          string `json:"osType"`
	KernelVersion   string `json:"kernelVersion"`
	DockerVersion   string `json:"dockerVersion"`
}

type sreSnapshotCapacity struct {
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

type sreSnapshotSwarm struct {
	Nodes             int `json:"nodes"`
	Applications      int `json:"applications"`
	Services          int `json:"services"`
	HealthyServices   int `json:"healthyServices"`
	DegradedServices  int `json:"degradedServices"`
	PausedServices    int `json:"pausedServices"`
	ContainersRunning int `json:"containersRunning"`
	ContainersStopped int `json:"containersStopped"`
}

type sreLogSignals struct {
	Inspected         bool `json:"inspected"`
	Unavailable       bool `json:"unavailable"`
	LineCount         int  `json:"lineCount"`
	ErrorSignals      int  `json:"errorSignals"`
	WarningSignals    int  `json:"warningSignals"`
	OOMSignals        int  `json:"oomSignals"`
	PermissionSignals int  `json:"permissionSignals"`
}

type sreSnapshotService struct {
	Reference  string        `json:"reference"`
	Running    uint64        `json:"running"`
	Desired    uint64        `json:"desired"`
	Status     string        `json:"status"`
	UpdatedAt  string        `json:"updatedAt,omitempty"`
	LogSignals sreLogSignals `json:"logSignals"`
}

type sreSnapshotEvent struct {
	ServiceReference string `json:"serviceReference"`
	State            string `json:"state"`
	DesiredState     string `json:"desiredState"`
	ObservedAt       string `json:"observedAt,omitempty"`
}

type sreSnapshotFinding struct {
	Kind        string `json:"kind"`
	Severity    string `json:"severity"`
	Code        string `json:"code"`
	Observation string `json:"observation"`
	Evidence    string `json:"evidence"`
}

type sreDiagnosticSnapshot struct {
	SchemaVersion   int                  `json:"schemaVersion"`
	SnapshotVersion string               `json:"snapshotVersion"`
	Maturity        string               `json:"maturity"`
	Source          string               `json:"source"`
	GeneratedAt     time.Time            `json:"generatedAt"`
	ReadOnly        bool                 `json:"readOnly"`
	Privacy         sreSnapshotPrivacy   `json:"privacy"`
	Versions        sreSnapshotVersions  `json:"versions"`
	Capacity        sreSnapshotCapacity  `json:"capacity"`
	Swarm           sreSnapshotSwarm     `json:"swarm"`
	Services        []sreSnapshotService `json:"services"`
	Events          []sreSnapshotEvent   `json:"events"`
	Findings        []sreSnapshotFinding `json:"observedFacts"`
	Hypotheses      []string             `json:"hypotheses"`
	Limitations     []string             `json:"limitations"`
}

type sreDockerTask struct {
	ServiceID    string `json:"ServiceID"`
	DesiredState string `json:"DesiredState"`
	Status       struct {
		State     string    `json:"State"`
		Timestamp time.Time `json:"Timestamp"`
	} `json:"Status"`
}

func collectSREDiagnosticSnapshot(
	client *http.Client,
	release setupRelease,
	controlVersion string,
) (sreDiagnosticSnapshot, error) {
	current, err := collectOverview(client)
	if err != nil {
		return sreDiagnosticSnapshot{}, err
	}
	var services []dockerService
	if err := dockerJSON(client, "/services?status=true", &services); err != nil {
		return sreDiagnosticSnapshot{}, fmt.Errorf("inventário SRE de serviços: %w", err)
	}
	var tasks []sreDockerTask
	if err := dockerJSON(client, "/tasks", &tasks); err != nil {
		return sreDiagnosticSnapshot{}, fmt.Errorf("eventos SRE de tasks: %w", err)
	}

	generatedAt := time.Now().UTC()
	salt := make([]byte, 24)
	if _, err := rand.Read(salt); err != nil {
		return sreDiagnosticSnapshot{}, errors.New("não foi possível criar referências opacas")
	}
	references := make(map[string]string, len(services))
	serviceSummaries := make([]sreSnapshotService, 0, min(len(services), sreMaxServices))
	paused := 0
	logInspections := 0
	for _, service := range services {
		if len(serviceSummaries) == sreMaxServices {
			break
		}
		reference := sreOpaqueReference(service.ID, salt)
		references[service.ID] = reference
		var running, desired uint64
		if service.ServiceStatus != nil {
			running = service.ServiceStatus.RunningTasks
			desired = service.ServiceStatus.DesiredTasks
		}
		status := "online"
		if desired == 0 {
			status = "paused"
			paused++
		} else if running < desired {
			status = "degraded"
		}
		logSignals := sreLogSignals{}
		if status == "degraded" && logInspections < sreMaxLogServices {
			logInspections++
			logSignals.Inspected = true
			payload, logErr := dockerBytes(
				client,
				"/services/"+url.PathEscape(service.ID)+"/logs?stdout=1&stderr=1&tail=40&timestamps=0",
				sreMaxServiceLogBytes,
			)
			if logErr != nil {
				logSignals.Unavailable = true
			} else {
				logSignals = summarizeServiceLogs(payload)
				logSignals.Inspected = true
			}
		}
		updated := ""
		if !service.UpdatedAt.IsZero() {
			updated = service.UpdatedAt.UTC().Format(time.RFC3339)
		}
		serviceSummaries = append(serviceSummaries, sreSnapshotService{
			Reference: reference, Running: running, Desired: desired,
			Status: status, UpdatedAt: updated, LogSignals: logSignals,
		})
	}

	events := make([]sreSnapshotEvent, 0, min(len(tasks), sreMaxEvents))
	for _, task := range tasks {
		reference, ok := references[task.ServiceID]
		if !ok {
			continue
		}
		observedAt := ""
		if !task.Status.Timestamp.IsZero() {
			observedAt = task.Status.Timestamp.UTC().Format(time.RFC3339)
		}
		events = append(events, sreSnapshotEvent{
			ServiceReference: reference,
			State:            sreAllowedTaskState(task.Status.State),
			DesiredState:     sreAllowedTaskState(task.DesiredState),
			ObservedAt:       observedAt,
		})
	}
	sort.Slice(events, func(i, j int) bool { return events[i].ObservedAt > events[j].ObservedAt })
	if len(events) > sreMaxEvents {
		events = events[:sreMaxEvents]
	}

	snapshot := sreDiagnosticSnapshot{
		SchemaVersion: sreSnapshotSchema, SnapshotVersion: sreSnapshotVersion,
		Maturity: sreSnapshotMaturity, Source: sreSnapshotSource,
		GeneratedAt: generatedAt, ReadOnly: true,
		Privacy: sreSnapshotPrivacy{
			Sanitized: true, MutationAllowed: false, RawLogsIncluded: false,
			ServiceNamesUsed: false,
			Excluded: []string{
				"hostname", "ip", "domain", "email", "image-reference", "environment",
				"secret", "credential", "command", "raw-log", "volume-content",
			},
		},
		Versions: sreSnapshotVersions{
			SetupVersion: release.SetupVersion, ControlVersion: controlVersion,
			Architecture: current.Architecture, OperatingSystem: current.OperatingSystem,
			OSVersion: current.OSVersion, OSType: current.OSType,
			KernelVersion: current.KernelVersion, DockerVersion: current.EngineVersion,
		},
		Capacity: sreSnapshotCapacity{
			CPUPercent:    current.Metrics.CPUPercent,
			MemoryPercent: current.Metrics.MemoryPercent,
			MemoryUsed:    current.Metrics.MemoryUsed, MemoryTotal: current.Metrics.MemoryTotal,
			DiskPercent: current.Metrics.DiskPercent,
			DiskUsed:    current.Metrics.DiskUsed, DiskTotal: current.Metrics.DiskTotal,
			Load1: current.Metrics.Load1, Load5: current.Metrics.Load5,
			Load15: current.Metrics.Load15, UptimeSeconds: current.Metrics.UptimeSeconds,
		},
		Swarm: sreSnapshotSwarm{
			Nodes: current.SwarmNodes, Applications: current.Apps, Services: current.Services,
			HealthyServices: current.HealthyServices, DegradedServices: current.DegradedServices,
			PausedServices: paused, ContainersRunning: current.ContainersRunning,
			ContainersStopped: current.ContainersStopped,
		},
		Services: serviceSummaries, Events: events,
		Hypotheses: []string{},
		Limitations: []string{
			"Fotografia pontual; não substitui monitoramento histórico.",
			"Logs são reduzidos a contagens de sinais e nunca incluem conteúdo bruto.",
			"Nenhuma causa provável é promovida a fato sem evidência determinística.",
		},
	}
	snapshot.Findings = sreObservedFindings(snapshot)
	if err := validateSREDiagnosticSnapshot(snapshot); err != nil {
		return sreDiagnosticSnapshot{}, err
	}
	return snapshot, nil
}

func sreOpaqueReference(serviceID string, salt []byte) string {
	digest := sha256.Sum256(append(append([]byte(nil), salt...), []byte("|"+serviceID)...))
	return "service-" + hex.EncodeToString(digest[:])[:12]
}

func sreAllowedTaskState(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "new", "pending", "assigned", "accepted", "preparing", "ready", "starting",
		"running", "complete", "shutdown", "failed", "rejected", "remove", "orphaned":
		return strings.ToLower(strings.TrimSpace(value))
	default:
		return "unknown"
	}
}

func summarizeServiceLogs(payload []byte) sreLogSignals {
	plain := decodeDockerLogFrames(payload)
	result := sreLogSignals{}
	for _, line := range strings.Split(string(plain), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if result.LineCount == sreMaxServiceLogLines {
			break
		}
		result.LineCount++
		lower := strings.ToLower(line)
		if containsAny(lower, "error", "fatal", "panic", "exception", "failed", "failure") {
			result.ErrorSignals++
		}
		if containsAny(lower, "warn", "warning", "deprecated") {
			result.WarningSignals++
		}
		if containsAny(lower, "out of memory", "oom", "killed process") {
			result.OOMSignals++
		}
		if containsAny(lower, "permission denied", "access denied", "operation not permitted") {
			result.PermissionSignals++
		}
	}
	return result
}

func containsAny(value string, terms ...string) bool {
	for _, term := range terms {
		if strings.Contains(value, term) {
			return true
		}
	}
	return false
}

func decodeDockerLogFrames(payload []byte) []byte {
	if len(payload) < 8 {
		return payload
	}
	var output bytes.Buffer
	remaining := payload
	decoded := false
	for len(remaining) >= 8 && (remaining[0] == 0 || remaining[0] == 1 || remaining[0] == 2) {
		length := int(binary.BigEndian.Uint32(remaining[4:8]))
		if length < 0 || length > len(remaining)-8 {
			return payload
		}
		output.Write(remaining[8 : 8+length])
		remaining = remaining[8+length:]
		decoded = true
	}
	if decoded && len(remaining) == 0 {
		return output.Bytes()
	}
	return payload
}

func dockerBytes(client *http.Client, endpoint string, limit int64) ([]byte, error) {
	req, err := http.NewRequest(http.MethodGet, "http://docker"+endpoint, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Docker retornou HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, errors.New("resposta do Docker excedeu o limite")
	}
	return data, nil
}

func sreObservedFindings(snapshot sreDiagnosticSnapshot) []sreSnapshotFinding {
	findings := make([]sreSnapshotFinding, 0, 5)
	add := func(severity, code, observation, evidence string) {
		findings = append(findings, sreSnapshotFinding{
			Kind: "observed", Severity: severity, Code: code,
			Observation: observation, Evidence: evidence,
		})
	}
	if snapshot.Capacity.MemoryPercent >= 85 {
		add("critical", "memory-critical", "Uso de memória em nível crítico.", fmt.Sprintf("memoryPercent=%.1f", snapshot.Capacity.MemoryPercent))
	} else if snapshot.Capacity.MemoryPercent >= 70 {
		add("warning", "memory-warning", "Uso de memória exige atenção.", fmt.Sprintf("memoryPercent=%.1f", snapshot.Capacity.MemoryPercent))
	} else {
		add("info", "memory-normal", "Uso de memória abaixo do limite de atenção.", fmt.Sprintf("memoryPercent=%.1f", snapshot.Capacity.MemoryPercent))
	}
	if snapshot.Capacity.DiskPercent >= 85 {
		add("critical", "disk-critical", "Uso de disco em nível crítico.", fmt.Sprintf("diskPercent=%.1f", snapshot.Capacity.DiskPercent))
	} else if snapshot.Capacity.DiskPercent >= 70 {
		add("warning", "disk-warning", "Uso de disco exige atenção.", fmt.Sprintf("diskPercent=%.1f", snapshot.Capacity.DiskPercent))
	} else {
		add("info", "disk-normal", "Uso de disco abaixo do limite de atenção.", fmt.Sprintf("diskPercent=%.1f", snapshot.Capacity.DiskPercent))
	}
	if snapshot.Swarm.DegradedServices > 0 {
		add("warning", "services-degraded", "Existem serviços sem todas as réplicas desejadas.", fmt.Sprintf("degradedServices=%d", snapshot.Swarm.DegradedServices))
	} else {
		add("info", "services-converged", "Os serviços monitorados atendem às réplicas desejadas.", fmt.Sprintf("healthyServices=%d", snapshot.Swarm.HealthyServices))
	}
	return findings
}

func validateSREDiagnosticSnapshot(snapshot sreDiagnosticSnapshot) error {
	if snapshot.SchemaVersion != sreSnapshotSchema || snapshot.SnapshotVersion != sreSnapshotVersion ||
		snapshot.Maturity != sreSnapshotMaturity || snapshot.Source != sreSnapshotSource ||
		snapshot.GeneratedAt.IsZero() || !snapshot.ReadOnly || !snapshot.Privacy.Sanitized ||
		snapshot.Privacy.MutationAllowed || snapshot.Privacy.RawLogsIncluded ||
		snapshot.Privacy.ServiceNamesUsed || len(snapshot.Privacy.Excluded) < 8 ||
		!validSemanticVersion(snapshot.Versions.SetupVersion) ||
		!validSemanticVersion(snapshot.Versions.ControlVersion) ||
		len(snapshot.Services) > sreMaxServices || len(snapshot.Events) > sreMaxEvents ||
		len(snapshot.Hypotheses) != 0 {
		return errors.New("snapshot SRE incompatível com a política somente leitura")
	}
	seen := make(map[string]bool, len(snapshot.Services))
	for _, service := range snapshot.Services {
		if len(service.Reference) != len("service-")+12 || !strings.HasPrefix(service.Reference, "service-") ||
			seen[service.Reference] || (service.Status != "online" && service.Status != "degraded" && service.Status != "paused") ||
			service.LogSignals.LineCount > sreMaxServiceLogLines {
			return errors.New("serviço sanitizado inválido no snapshot SRE")
		}
		seen[service.Reference] = true
	}
	for _, event := range snapshot.Events {
		if !seen[event.ServiceReference] || event.State == "" || event.DesiredState == "" {
			return errors.New("evento não autorizado no snapshot SRE")
		}
	}
	for _, finding := range snapshot.Findings {
		if finding.Kind != "observed" || finding.Code == "" || finding.Observation == "" || finding.Evidence == "" {
			return errors.New("fato observado inválido no snapshot SRE")
		}
	}
	serialized, err := json.Marshal(snapshot)
	if err != nil {
		return err
	}
	lower := strings.ToLower(string(serialized))
	for _, forbidden := range []string{
		`"hostname":`, `"ip":`, `"domain":`, `"email":`, `"image":`,
		`"environment":`, `"secret":`, `"credential":`, `"command":`, `"rawlog":`,
	} {
		if strings.Contains(lower, forbidden) {
			return errors.New("campo sensível presente no snapshot SRE")
		}
	}
	return nil
}
