package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newFeedbackTestApp(t *testing.T) *webApp {
	t.Helper()
	path := filepath.Join(t.TempDir(), "feedback.json")
	state, err := loadFeedbackState(path)
	if err != nil {
		t.Fatal(err)
	}
	return &webApp{
		version: "4.2.0", feedback: state,
		feedbackTokens: make(map[string]feedbackTokenRecord),
		audit:          make([]auditEvent, 0, 8),
	}
}

func feedbackRequest(t *testing.T, method, path string, body any) *http.Request {
	t.Helper()
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(method, path, strings.NewReader(string(data)))
	request.Header.Set("Content-Type", "application/json")
	return request
}

func TestFeedbackRequiresConsentAndStoresNoConversation(t *testing.T) {
	app := newFeedbackTestApp(t)
	tokenEvent := app.issueFeedbackToken("openai", "")
	token := tokenEvent["token"].(string)
	input := feedbackSubmission{
		Token: token, Rating: "unhelpful", Area: "security",
		Reason: "insufficient_evidence", Consent: false,
	}
	response := httptest.NewRecorder()
	app.handleFeedbackSubmit(response, feedbackRequest(t, http.MethodPost, "/api/feedback", input))
	if response.Code != http.StatusBadRequest || len(app.feedback.Records) != 0 {
		t.Fatalf("feedback sem consentimento foi aceito: HTTP %d", response.Code)
	}

	input.Consent = true
	response = httptest.NewRecorder()
	app.handleFeedbackSubmit(response, feedbackRequest(t, http.MethodPost, "/api/feedback", input))
	if response.Code != http.StatusCreated || len(app.feedback.Records) != 1 {
		t.Fatalf("feedback estruturado falhou: HTTP %d %s", response.Code, response.Body.String())
	}
	data, err := os.ReadFile(app.feedback.Path)
	if err != nil {
		t.Fatal(err)
	}
	stored := string(data)
	for _, forbidden := range []string{"question", "answer", "address", "hostname", "password"} {
		if strings.Contains(strings.ToLower(stored), forbidden) {
			t.Fatalf("campo proibido persistido no feedback: %s", forbidden)
		}
	}
	if !strings.Contains(stored, `"policyVersion":"1.0.0"`) ||
		!strings.Contains(stored, `"status":"pending_review"`) {
		t.Fatalf("contrato persistido inesperado: %s", stored)
	}

	replay := httptest.NewRecorder()
	app.handleFeedbackSubmit(replay, feedbackRequest(t, http.MethodPost, "/api/feedback", input))
	if replay.Code != http.StatusBadRequest || len(app.feedback.Records) != 1 {
		t.Fatalf("token de feedback foi reutilizado: HTTP %d", replay.Code)
	}
}

func TestFeedbackRejectsFreeTextAndIncompatibleReason(t *testing.T) {
	app := newFeedbackTestApp(t)
	token := app.issueFeedbackToken("basic", "")["token"].(string)
	request := httptest.NewRequest(
		http.MethodPost, "/api/feedback",
		strings.NewReader(`{"token":"`+token+`","rating":"helpful","area":"setup","reason":"incorrect","consent":true,"question":"não persistir"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	app.handleFeedbackSubmit(response, request)
	if response.Code != http.StatusBadRequest || len(app.feedback.Records) != 0 {
		t.Fatalf("texto livre ou motivo incompatível foi aceito: HTTP %d", response.Code)
	}
}

func TestFeedbackHumanReviewPersistsAndDeleteIsExplicit(t *testing.T) {
	app := newFeedbackTestApp(t)
	token := app.issueFeedbackToken("basic", "provider")["token"].(string)
	input := feedbackSubmission{
		Token: token, Rating: "helpful", Area: "infrastructure",
		Reason: "useful", Consent: true,
	}
	submit := httptest.NewRecorder()
	app.handleFeedbackSubmit(submit, feedbackRequest(t, http.MethodPost, "/api/feedback", input))
	feedbackID := app.feedback.Records[0].FeedbackID

	review := httptest.NewRecorder()
	app.handleFeedbackReview(review, feedbackRequest(t, http.MethodPost, "/api/feedback/review", feedbackReviewRequest{
		FeedbackID: feedbackID, Decision: "accept_for_eval",
	}))
	if review.Code != http.StatusOK || app.feedback.Records[0].Status != "accepted_for_eval" ||
		app.feedback.Records[0].ReviewedAt == "" {
		t.Fatalf("revisão humana não foi registrada: HTTP %d", review.Code)
	}
	reloaded, err := loadFeedbackState(app.feedback.Path)
	if err != nil || len(reloaded.Records) != 1 || reloaded.Records[0].Status != "accepted_for_eval" {
		t.Fatalf("fila revisada não sobreviveu ao reload: %#v %v", reloaded, err)
	}

	remove := httptest.NewRecorder()
	app.handleFeedbackDelete(remove, feedbackRequest(t, http.MethodPost, "/api/feedback/delete", feedbackDeleteRequest{FeedbackID: feedbackID}))
	if remove.Code != http.StatusOK || len(app.feedback.Records) != 0 {
		t.Fatalf("exclusão explícita falhou: HTTP %d", remove.Code)
	}
}

func TestFeedbackReportAndRetentionAreBounded(t *testing.T) {
	now := time.Now().UTC()
	records := []feedbackRecord{
		{
			FeedbackID: strings.Repeat("a", 24), CreatedAt: now.Format(time.RFC3339),
			ControlVersion: "4.2.0", AssistantMode: "ollama", Rating: "helpful",
			Area: "setup", Reason: "accurate", Status: "pending_review",
		},
		{
			FeedbackID: strings.Repeat("b", 24), CreatedAt: now.Add(-feedbackRetention - time.Hour).Format(time.RFC3339),
			ControlVersion: "4.2.0", AssistantMode: "basic", Rating: "unhelpful",
			Area: "security", Reason: "unsafe", Status: "pending_review",
		},
	}
	pruned := pruneFeedbackRecords(records, now)
	if len(pruned) != 1 {
		t.Fatalf("retenção não removeu registro expirado: %d", len(pruned))
	}
	report := buildFeedbackReport(pruned, "4.2.0")
	if report.Total != 1 || report.Helpful != 1 || report.Pending != 1 ||
		report.AreaCounts["setup"] != 1 || report.VersionCounts["4.2.0"] != 1 || report.RetentionDays != 30 {
		t.Fatalf("relatório agregado divergente: %#v", report)
	}
}

func TestFeedbackSurvivesControlUpgradeWithoutConversationData(t *testing.T) {
	app := newFeedbackTestApp(t)
	token := app.issueFeedbackToken("catalog", "")["token"].(string)
	response := httptest.NewRecorder()
	app.handleFeedbackSubmit(response, feedbackRequest(t, http.MethodPost, "/api/feedback", feedbackSubmission{
		Token: token, Rating: "helpful", Area: "setup", Reason: "clear", Consent: true,
	}))
	if response.Code != http.StatusCreated {
		t.Fatalf("feedback inicial falhou: HTTP %d", response.Code)
	}
	reloaded, err := loadFeedbackState(app.feedback.Path)
	if err != nil || len(reloaded.Records) != 1 || reloaded.Records[0].ControlVersion != "4.2.0" {
		t.Fatalf("feedback anterior foi perdido no upgrade: %#v %v", reloaded, err)
	}
	report := buildFeedbackReport(reloaded.Records, "4.5.0")
	if report.ControlVersion != "4.5.0" || report.VersionCounts["4.2.0"] != 1 {
		t.Fatalf("relatório por versão divergente: %#v", report)
	}
}

func TestFeedbackRejectsUnsafeStorePath(t *testing.T) {
	directory := t.TempDir()
	target := filepath.Join(directory, "real.json")
	if err := os.WriteFile(target, []byte(`{"schemaVersion":1}`), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(directory, "feedback.json")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if _, err := loadFeedbackState(link); err == nil {
		t.Fatal("arquivo de feedback por symlink foi aceito")
	}
}
