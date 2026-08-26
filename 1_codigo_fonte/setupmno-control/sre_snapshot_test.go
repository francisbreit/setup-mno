package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (function roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return function(request)
}

func testSRESnapshot(setupVersion, controlVersion string) sreDiagnosticSnapshot {
	return sreDiagnosticSnapshot{
		SchemaVersion: sreSnapshotSchema, SnapshotVersion: sreSnapshotVersion,
		Maturity: sreSnapshotMaturity, Source: sreSnapshotSource,
		GeneratedAt: time.Now().UTC(), ReadOnly: true,
		Privacy: sreSnapshotPrivacy{
			Sanitized: true, MutationAllowed: false, RawLogsIncluded: false,
			ServiceNamesUsed: false,
			Excluded: []string{
				"hostname", "ip", "domain", "email", "image-reference", "environment",
				"secret", "credential", "command", "raw-log", "volume-content",
			},
		},
		Versions: sreSnapshotVersions{
			SetupVersion: setupVersion, ControlVersion: controlVersion,
			Architecture: "amd64", OperatingSystem: "Ubuntu 24.04",
			OSType: "linux", KernelVersion: "6.8.0", DockerVersion: "29.4.2",
		},
		Capacity: sreSnapshotCapacity{MemoryTotal: 8 << 30, MemoryUsed: 3 << 30},
		Swarm:    sreSnapshotSwarm{Nodes: 1, Applications: 1, Services: 1, HealthyServices: 1},
		Services: []sreSnapshotService{{
			Reference: "service-aabbccddeeff", Running: 1, Desired: 1, Status: "online",
		}},
		Events: []sreSnapshotEvent{{
			ServiceReference: "service-aabbccddeeff", State: "running", DesiredState: "running",
		}},
		Findings: []sreSnapshotFinding{{
			Kind: "observed", Severity: "info", Code: "services-converged",
			Observation: "Serviços convergidos.", Evidence: "healthyServices=1",
		}},
		Hypotheses:    []string{},
		Limitations:   []string{"Fotografia pontual."},
		Deterministic: sreDeterministicState{Status: "not-run"},
	}
}

func testSREDeterministicResult(generatedAt time.Time, complete bool) sreDeterministicResult {
	status := "incomplete"
	trivyStatus := "failed"
	if complete {
		status = "attention"
		trivyStatus = "completed"
	}
	return sreDeterministicResult{
		SchemaVersion: 1, EngineVersion: "1.0.0", Maturity: "beta",
		GeneratedAt: generatedAt.UTC(), ExpiresAt: generatedAt.UTC().Add(24 * time.Hour),
		Execution: "human-confirmed-terminal", ReadOnly: true, Complete: complete,
		OverallStatus: status, HostType: "wsl2",
		Privacy: sreDeterministicPrivacy{Sanitized: true},
		Engines: []sreDeterministicEngine{
			{ID: "trivy", Version: "0.73.0", Status: trivyStatus, Coverage: "Imagens locais.", Counts: map[string]int{"critical": 1}},
			{ID: "lynis", Version: "3.1.7", Status: "completed", Coverage: "Host Linux.", Counts: map[string]int{"warnings": 2}},
			{ID: "docker-bench", Version: "1.6.1", Status: "completed", Coverage: "Docker CIS.", Counts: map[string]int{"warn": 3}},
		},
		ObservedFacts: []sreSnapshotFinding{{
			Severity: "warning", Code: "audit-coverage-incomplete",
			Observation: "A auditoria determinística não concluiu toda a cobertura planejada.",
			Evidence:    "completedEngines=2",
		}},
		Limitations: []string{"Contagens exigem revisão humana."},
	}
}

func dockerLogFrame(stream byte, content string) []byte {
	payload := []byte(content)
	frame := make([]byte, 8+len(payload))
	frame[0] = stream
	binary.BigEndian.PutUint32(frame[4:8], uint32(len(payload)))
	copy(frame[8:], payload)
	return frame
}

func TestCollectSRESnapshotUsesOnlyFixedGETsAndDoesNotLeakIdentities(t *testing.T) {
	servicePayload := `[{
      "ID":"service-real-id-1",
      "Spec":{"Name":"cliente_wordpress","Labels":{"com.docker.stack.namespace":"cliente"},"TaskTemplate":{"ContainerSpec":{"Image":"registry.example/private/app:secret"}}},
      "ServiceStatus":{"RunningTasks":0,"DesiredTasks":1},
      "UpdatedAt":"2026-08-24T10:00:00Z"
    }]`
	taskPayload := `[{
      "ServiceID":"service-real-id-1","DesiredState":"running",
      "Status":{"State":"failed","Timestamp":"2026-08-24T10:01:00Z","Err":"password=segredo"}
    }]`
	logPayload := append(
		dockerLogFrame(2, "ERROR password=segredo admin@example.com https://private.example\n"),
		dockerLogFrame(1, "WARNING permission denied\n")...,
	)
	requested := make([]string, 0)
	client := &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
		if request.Method != http.MethodGet {
			t.Fatalf("método mutável usado no Docker: %s", request.Method)
		}
		requested = append(requested, request.URL.RequestURI())
		status := http.StatusOK
		var body []byte
		switch request.URL.Path {
		case "/info":
			body = []byte(`{"Name":"hostname-secreto","Architecture":"x86_64","MemTotal":8589934592,"ContainersRunning":2,"ContainersStopped":1,"Swarm":{"Nodes":1},"ServerVersion":"29.4.2","OperatingSystem":"Ubuntu 24.04","OSVersion":"24.04","OSType":"linux","KernelVersion":"6.8.0"}`)
		case "/services":
			body = []byte(servicePayload)
		case "/tasks":
			body = []byte(taskPayload)
		case "/services/service-real-id-1/logs":
			body = logPayload
		default:
			status = http.StatusNotFound
			body = []byte(`{"message":"not found"}`)
		}
		return &http.Response{
			StatusCode: status, Body: io.NopCloser(bytes.NewReader(body)), Header: make(http.Header),
		}, nil
	})}

	snapshot, err := collectSREDiagnosticSnapshot(client, setupRelease{SetupVersion: "7.33.0"}, "4.33.0")
	if err != nil {
		t.Fatal(err)
	}
	if err := validateSREDiagnosticSnapshot(snapshot); err != nil {
		t.Fatalf("snapshot válido foi recusado: %v", err)
	}
	if len(snapshot.Services) != 1 || snapshot.Services[0].Status != "degraded" ||
		!snapshot.Services[0].LogSignals.Inspected ||
		snapshot.Services[0].LogSignals.ErrorSignals != 1 ||
		snapshot.Services[0].LogSignals.WarningSignals != 1 ||
		snapshot.Services[0].LogSignals.PermissionSignals != 1 {
		t.Fatalf("sinais agregados incorretos: %#v", snapshot.Services)
	}
	serialized, _ := json.Marshal(snapshot)
	for _, forbidden := range []string{
		"hostname-secreto", "cliente_wordpress", "service-real-id-1",
		"registry.example", "segredo", "admin@example.com", "private.example",
	} {
		if strings.Contains(string(serialized), forbidden) {
			t.Fatalf("dado sensível vazou no snapshot: %q em %s", forbidden, serialized)
		}
	}
	if len(requested) != 6 {
		t.Fatalf("quantidade inesperada de leituras Docker: %#v", requested)
	}
	for _, endpoint := range requested {
		if !strings.HasPrefix(endpoint, "/info") && !strings.HasPrefix(endpoint, "/services") &&
			!strings.HasPrefix(endpoint, "/tasks") {
			t.Fatalf("endpoint Docker fora da allowlist: %s", endpoint)
		}
	}
}

func TestSRESnapshotRejectsMutationFlagsAndRawIdentityFields(t *testing.T) {
	snapshot := testSRESnapshot("7.33.0", "4.33.0")
	snapshot.Privacy.MutationAllowed = true
	if validateSREDiagnosticSnapshot(snapshot) == nil {
		t.Fatal("snapshot com mutação permitida foi aceito")
	}
	snapshot = testSRESnapshot("7.33.0", "4.33.0")
	snapshot.Privacy.RawLogsIncluded = true
	if validateSREDiagnosticSnapshot(snapshot) == nil {
		t.Fatal("snapshot com log bruto foi aceito")
	}
}

func TestHandleSRESnapshotUsesAuthenticatedFixedAgentEndpoint(t *testing.T) {
	snapshot := testSRESnapshot("7.33.0", "4.33.0")
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet || request.URL.Path != "/sre/snapshot" ||
			request.Header.Get("X-SetupMNO-Agent-Token") != "token-teste" {
			t.Fatalf("requisição não autorizada ao agente: %s %s", request.Method, request.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(snapshot)
	}))
	defer agent.Close()
	app := webApp{
		agentURL: agent.URL, agentToken: "token-teste", httpClient: agent.Client(),
		audit: auditState{Path: filepath.Join(t.TempDir(), "audit.json"), AnchorHash: auditZeroHash},
	}
	recorder := httptest.NewRecorder()
	app.handleSRESnapshot(recorder, httptest.NewRequest(http.MethodGet, "/api/sre/snapshot", nil))
	if recorder.Code != http.StatusOK || !strings.Contains(recorder.Body.String(), `"source":"agent-fixed-read-only"`) {
		t.Fatalf("proxy SRE falhou: HTTP %d: %s", recorder.Code, recorder.Body.String())
	}
}

func TestAssistantContextContainsOnlyValidatedSRESnapshot(t *testing.T) {
	snapshot := testSRESnapshot("7.33.0", "4.33.0")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/sre/snapshot" {
			_ = json.NewEncoder(w).Encode(snapshot)
			return
		}
		writeError(w, http.StatusServiceUnavailable, "catálogo indisponível")
	}))
	defer server.Close()
	service := assistantService{
		agentURL: server.URL, agentToken: "token-teste", agentClient: server.Client(),
		knowledge: knowledgePackageState{Manifest: knowledgeManifest{SetupVersion: "7.33.0"}},
	}
	contextData, err := service.collectContext(context.Background(), "Analise o servidor", "")
	if err != nil {
		t.Fatal(err)
	}
	if contextData.SRESnapshot == nil || contextData.SRESnapshot.Source != sreSnapshotSource ||
		len(contextData.InstalledApps) != 0 || contextData.InstalledApplicationCount != 1 {
		t.Fatalf("contexto SRE sanitizado ausente: %#v", contextData)
	}
}

func TestSREDeterministicAuditRejectsTamperAndPreservesIncompleteState(t *testing.T) {
	directory := t.TempDir()
	engineDirectory := filepath.Join(directory, "sre-engine")
	if err := os.Mkdir(engineDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	generatedAt := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)
	result := testSREDeterministicResult(generatedAt, false)
	payload, _ := json.Marshal(result)
	filename := filepath.Join(engineDirectory, "latest.json")
	if err := os.WriteFile(filename, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	state := loadSREDeterministicAudit(directory, generatedAt.Add(time.Hour))
	if state.Status != "available" || state.Result == nil || state.Result.Complete ||
		state.Result.OverallStatus != "incomplete" {
		t.Fatalf("cobertura incompleta foi ocultada: %#v", state)
	}
	disclosure := deterministicAuditDisclosure(state)
	if !strings.Contains(disclosure, "cobertura completa: `false`") ||
		!strings.Contains(disclosure, "trivy 0.73.0: `failed`") {
		t.Fatalf("bloco fixo não preservou a falha: %s", disclosure)
	}
	if err := os.Chmod(filename, 0o644); err != nil {
		t.Fatal(err)
	}
	if state = loadSREDeterministicAudit(directory, generatedAt.Add(time.Hour)); state.Status != "invalid" {
		t.Fatalf("resultado com permissão insegura foi aceito: %#v", state)
	}
}

func TestSREDeterministicAuditExpiresAndDoesNotBecomeApproval(t *testing.T) {
	directory := t.TempDir()
	engineDirectory := filepath.Join(directory, "sre-engine")
	if err := os.Mkdir(engineDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	generatedAt := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)
	result := testSREDeterministicResult(generatedAt, true)
	result.ObservedFacts = nil
	payload, _ := json.Marshal(result)
	if err := os.WriteFile(filepath.Join(engineDirectory, "latest.json"), payload, 0o600); err != nil {
		t.Fatal(err)
	}
	state := loadSREDeterministicAudit(directory, generatedAt.Add(25*time.Hour))
	if state.Status != "expired" || !strings.Contains(deterministicAuditDisclosure(state), "Resultado vencido") {
		t.Fatalf("resultado vencido não foi bloqueado: %#v", state)
	}
}
