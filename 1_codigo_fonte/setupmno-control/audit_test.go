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
