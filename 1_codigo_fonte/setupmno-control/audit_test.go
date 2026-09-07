package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func newAuditTestApp(t *testing.T) *webApp {
	t.Helper()
	state, err := loadAuditState(filepath.Join(t.TempDir(), "audit.json"))
	if err != nil {
		t.Fatal(err)
	}
	return &webApp{version: "4.15.8", audit: state}
}

func TestAuditSurvivesRestartWithVerifiedChain(t *testing.T) {
	app := newAuditTestApp(t)
	app.addAudit("login_success", "Sessão administrativa iniciada", "198.51.100.10")
	app.addAudit("terminal_reauth_success", "Terminal Seguro autorizado por 2 minutos", "198.51.100.10")

	reloaded, err := loadAuditState(app.audit.Path)
	if err != nil {
		t.Fatal(err)
	}
	if len(reloaded.Events) != 2 || reloaded.Events[0].Sequence != 1 ||
		reloaded.Events[1].PreviousHash != reloaded.Events[0].EventHash ||
		reloaded.Events[1].ControlVersion != "4.15.8" {
		t.Fatalf("cadeia persistida inesperada: %#v", reloaded)
	}
}

func TestAuditRejectsTamperedEvent(t *testing.T) {
	app := newAuditTestApp(t)
	app.addAudit("login_success", "Sessão administrativa iniciada", "198.51.100.10")
	data, err := os.ReadFile(app.audit.Path)
	if err != nil {
		t.Fatal(err)
	}
	var document auditStoreDocument
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	document.Events[0].Detail = "Detalhe adulterado"
	modified, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(app.audit.Path, modified, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadAuditState(app.audit.Path); err == nil {
		t.Fatal("evento adulterado foi aceito")
	}
}

func TestAuditRetentionPreservesAnchor(t *testing.T) {
	state := auditState{AnchorHash: auditZeroHash, Events: make([]auditEvent, 0, 3)}
	for index, createdAt := range []time.Time{
		time.Now().UTC().Add(-auditRetention - time.Hour),
		time.Now().UTC().Add(-time.Hour),
		time.Now().UTC(),
	} {
		appendAuditEvent(&state, auditEvent{
			Time: createdAt.Format(time.RFC3339), Actor: "admin", Action: "assistant_analysis",
			Resource: "assistant", Outcome: "success", Detail: "Consulta local", Address: "198.51.100.10",
			ControlVersion: "4.15.8",
		})
		if state.Events[index].EventHash == "" {
			t.Fatal("hash de evento ausente")
		}
	}
	if !pruneAuditState(&state, time.Now().UTC()) || len(state.Events) != 2 ||
		state.AnchorSequence != 1 || state.Events[0].PreviousHash != state.AnchorHash {
		t.Fatalf("retenção não preservou a âncora: %#v", state)
	}
	if err := validateAuditState(state); err != nil {
		t.Fatalf("cadeia retida inválida: %v", err)
	}
}

func TestAuditAPIUsesCursorPagination(t *testing.T) {
	app := newAuditTestApp(t)
	for index := 0; index < 3; index++ {
		app.addAudit("assistant_analysis", "Consulta assistida via basic", "198.51.100.10")
	}
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/audit?limit=2", nil)
	app.handleAudit(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("primeira página recusada: %d", response.Code)
	}
	var first struct {
		Events     []auditEvent    `json:"events"`
		Pagination auditPagination `json:"pagination"`
		Integrity  auditIntegrity  `json:"integrity"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &first); err != nil {
		t.Fatal(err)
	}
	if len(first.Events) != 2 || !first.Pagination.HasMore || first.Pagination.NextBefore == 0 ||
		first.Integrity.Status != "verified" || first.Events[0].Sequence != 3 {
		t.Fatalf("primeira página inesperada: %#v", first)
	}
	response = httptest.NewRecorder()
	request = httptest.NewRequest(http.MethodGet, "/api/audit?limit=2&before=2", nil)
	app.handleAudit(response, request)
	if response.Code != http.StatusOK || !json.Valid(response.Body.Bytes()) ||
		string(response.Body.Bytes()) == "" {
		t.Fatalf("segunda página inválida: %d %s", response.Code, response.Body.String())
	}
}

func TestAuditActorAndResourceInference(t *testing.T) {
	cases := []struct {
		action           string
		expectedActor    string
		expectedResource string
	}{
		{"login_success", "admin", "login"},
		{"login_failed", "anonymous", "login"},
		{"terminal_reauth_success", "admin", "terminal"},
		{"fleet_tool_call", "vibe_ops_agent", "fleet"},
		{"fleet_tool_call_failed", "vibe_ops_agent", "fleet"},
		{"fleet_tool_call_rejected", "vibe_ops_agent", "fleet"},
		{"fleet_node_added", "fleet_controller", "fleet"},
		{"fleet_ping_executed", "fleet_controller", "fleet"},
		{"sentinel_alert_dispatched", "mno_sentinel", "sentinel"},
		{"sentinel_incident_resolved", "mno_sentinel", "sentinel"},
		{"sentinel_config_updated", "mno_sentinel", "sentinel"},
		{"assistant_analysis", "admin", "assistant"},
		{"blueprint_download", "admin", "blueprint"},
	}

	for _, c := range cases {
		actor := inferAuditActor(c.action)
		if actor != c.expectedActor {
			t.Errorf("inferAuditActor(%q) = %q; esperado %q", c.action, actor, c.expectedActor)
		}
		resource := inferAuditResource(c.action)
		if resource != c.expectedResource {
			t.Errorf("inferAuditResource(%q) = %q; esperado %q", c.action, resource, c.expectedResource)
		}
	}
}

func TestAuditScopeFiltering(t *testing.T) {
	app := newAuditTestApp(t)
	app.addAudit("login_success", "Sessão iniciada", "127.0.0.1")
	app.addAudit("fleet_tool_call", "Tool fleet_get_status executada", "10.0.3.50")
	app.addAudit("sentinel_alert_dispatched", "Alerta de RAM enviado", "sentinel-daemon")
	app.addAudit("terminal_reauth_success", "Terminal autorizado", "127.0.0.1")

	// Teste 1: Escopo vibe_ops deve retornar 2 eventos (fleet_tool_call e sentinel_alert_dispatched)
	req1 := httptest.NewRequest(http.MethodGet, "/api/audit?scope=vibe_ops", nil)
	rec1 := httptest.NewRecorder()
	app.handleAudit(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Fatalf("handleAudit com scope=vibe_ops falhou: %d", rec1.Code)
	}

	var res1 struct {
		Events []auditEvent `json:"events"`
		Scope  string       `json:"scope"`
	}
	if err := json.Unmarshal(rec1.Body.Bytes(), &res1); err != nil {
		t.Fatalf("decode JSON falhou: %v", err)
	}
	if len(res1.Events) != 2 || res1.Scope != "vibe_ops" {
		t.Errorf("esperava 2 eventos no escopo vibe_ops, obteve %d", len(res1.Events))
	}
	for _, ev := range res1.Events {
		if ev.Resource != "fleet" && ev.Resource != "sentinel" {
			t.Errorf("evento inesperado no escopo vibe_ops: %+v", ev)
		}
	}

	// Teste 2: Escopo sentinel deve retornar 1 evento
	req2 := httptest.NewRequest(http.MethodGet, "/api/audit?scope=sentinel", nil)
	rec2 := httptest.NewRecorder()
	app.handleAudit(rec2, req2)
	var res2 struct {
		Events []auditEvent `json:"events"`
	}
	_ = json.Unmarshal(rec2.Body.Bytes(), &res2)
	if len(res2.Events) != 1 || res2.Events[0].Action != "sentinel_alert_dispatched" {
		t.Errorf("esperava 1 evento sentinel, obteve %d", len(res2.Events))
	}

	// Teste 3: Escopo all (ou sem escopo) deve retornar todos os 4 eventos
	req3 := httptest.NewRequest(http.MethodGet, "/api/audit", nil)
	rec3 := httptest.NewRecorder()
	app.handleAudit(rec3, req3)
	var res3 struct {
		Events []auditEvent `json:"events"`
	}
	_ = json.Unmarshal(rec3.Body.Bytes(), &res3)
	if len(res3.Events) != 4 {
		t.Errorf("esperava 4 eventos sem escopo, obteve %d", len(res3.Events))
	}
}
