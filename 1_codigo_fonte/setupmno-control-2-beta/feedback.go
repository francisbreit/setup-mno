package main

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	feedbackSchemaVersion = 1
	feedbackPolicyVersion = "1.0.0"
	feedbackMaxRecords    = 200
	feedbackMaxStoreBytes = 256 << 10
	feedbackTokenTTL      = 30 * time.Minute
	feedbackRetention     = 30 * 24 * time.Hour
)

var feedbackRatings = map[string]struct{}{
	"helpful": {}, "unhelpful": {},
}

var feedbackAreas = map[string]struct{}{
	"setup": {}, "infrastructure": {}, "capacity": {}, "security": {},
	"blueprint": {}, "troubleshooting": {}, "integration": {}, "other": {},
}

var feedbackReasons = map[string]map[string]struct{}{
	"helpful": {
		"accurate": {}, "clear": {}, "useful": {},
	},
	"unhelpful": {
		"incorrect": {}, "incomplete": {}, "unclear": {}, "outdated": {},
		"unsafe": {}, "insufficient_evidence": {},
	},
}

var feedbackModes = map[string]struct{}{
	"basic": {}, "catalog": {}, "openai": {}, "openrouter": {},
	"deepseek": {}, "ollama": {},
}

var feedbackFallbackReasons = map[string]struct{}{
	"": {}, "provider": {}, "connector": {}, "context": {},
}

var feedbackStatuses = map[string]struct{}{
	"pending_review": {}, "accepted_for_eval": {}, "dismissed": {},
}

type feedbackTokenRecord struct {
	Expires        time.Time
	AssistantMode  string
	FallbackReason string
	ControlVersion string
}

type feedbackSubmission struct {
	Token   string `json:"token"`
	Rating  string `json:"rating"`
	Area    string `json:"area"`
	Reason  string `json:"reason"`
	Consent bool   `json:"consent"`
}

type feedbackReviewRequest struct {
	FeedbackID string `json:"feedbackId"`
	Decision   string `json:"decision"`
}

type feedbackDeleteRequest struct {
	FeedbackID string `json:"feedbackId"`
}

type feedbackRecord struct {
	FeedbackID     string `json:"feedbackId"`
	CreatedAt      string `json:"createdAt"`
	ControlVersion string `json:"controlVersion"`
	AssistantMode  string `json:"assistantMode"`
	FallbackReason string `json:"fallbackReason,omitempty"`
	Rating         string `json:"rating"`
	Area           string `json:"area"`
	Reason         string `json:"reason"`
	Status         string `json:"status"`
	ReviewedAt     string `json:"reviewedAt,omitempty"`
}

type feedbackStoreDocument struct {
	SchemaVersion int              `json:"schemaVersion"`
	PolicyVersion string           `json:"policyVersion"`
	UpdatedAt     string           `json:"updatedAt"`
	Records       []feedbackRecord `json:"records"`
}

type feedbackState struct {
	Path    string
	Records []feedbackRecord
}

type feedbackReport struct {
	PolicyVersion  string         `json:"policyVersion"`
	ControlVersion string         `json:"controlVersion"`
	RetentionDays  int            `json:"retentionDays"`
	Total          int            `json:"total"`
	Helpful        int            `json:"helpful"`
	Unhelpful      int            `json:"unhelpful"`
	Pending        int            `json:"pending"`
	Accepted       int            `json:"accepted"`
	Dismissed      int            `json:"dismissed"`
	AreaCounts     map[string]int `json:"areaCounts"`
	ReasonCounts   map[string]int `json:"reasonCounts"`
	VersionCounts  map[string]int `json:"versionCounts"`
}

func loadFeedbackState(path string) (feedbackState, error) {
	state := feedbackState{Path: path, Records: make([]feedbackRecord, 0, feedbackMaxRecords)}
	directory := filepath.Dir(path)
	info, err := os.Lstat(directory)
	if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return state, fmt.Errorf("diretório de feedback: %w", err)
		}
	} else if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return state, errors.New("diretório de feedback inválido")
	}
	data, err := readRegularFile(path, feedbackMaxStoreBytes)
	if errors.Is(err, os.ErrNotExist) {
		return state, nil
	}
	if err != nil {
		return state, fmt.Errorf("arquivo de feedback: %w", err)
	}
	var document feedbackStoreDocument
	if err := decodeStrictJSON(data, &document); err != nil {
		return state, errors.New("arquivo de feedback não possui JSON estrito")
	}
	if document.SchemaVersion != feedbackSchemaVersion ||
		document.PolicyVersion != feedbackPolicyVersion || len(document.Records) > feedbackMaxRecords {
		return state, errors.New("arquivo de feedback incompatível")
	}
	now := time.Now().UTC()
	for _, record := range document.Records {
		createdAt, err := validateFeedbackRecord(record)
		if err != nil {
			return state, err
		}
		if !createdAt.After(now.Add(5*time.Minute)) && now.Sub(createdAt) <= feedbackRetention {
			state.Records = append(state.Records, record)
		}
	}
	return state, nil
}

func validateFeedbackRecord(record feedbackRecord) (time.Time, error) {
	identifier, err := hex.DecodeString(record.FeedbackID)
	if err != nil || len(identifier) != 12 || !validSemanticVersion(record.ControlVersion) {
		return time.Time{}, errors.New("registro de feedback possui identidade inválida")
	}
	createdAt, err := time.Parse(time.RFC3339, record.CreatedAt)
	if err != nil {
		return time.Time{}, errors.New("registro de feedback possui data inválida")
	}
	if _, ok := feedbackModes[record.AssistantMode]; !ok {
		return time.Time{}, errors.New("registro de feedback possui modo inválido")
	}
	if _, ok := feedbackFallbackReasons[record.FallbackReason]; !ok {
		return time.Time{}, errors.New("registro de feedback possui fallback inválido")
	}
	if err := validateFeedbackClassification(record.Rating, record.Area, record.Reason); err != nil {
		return time.Time{}, err
	}
	if _, ok := feedbackStatuses[record.Status]; !ok {
		return time.Time{}, errors.New("registro de feedback possui status inválido")
	}
	if record.Status == "pending_review" && record.ReviewedAt != "" {
		return time.Time{}, errors.New("feedback pendente não pode possuir revisão")
	}
	if record.Status != "pending_review" {
		if _, err := time.Parse(time.RFC3339, record.ReviewedAt); err != nil {
			return time.Time{}, errors.New("feedback revisado possui data inválida")
		}
	}
	return createdAt, nil
}

func validateFeedbackClassification(rating, area, reason string) error {
	if _, ok := feedbackRatings[rating]; !ok {
		return errors.New("avaliação de feedback inválida")
	}
	if _, ok := feedbackAreas[area]; !ok {
		return errors.New("área de feedback inválida")
	}
	if _, ok := feedbackReasons[rating][reason]; !ok {
		return errors.New("motivo de feedback incompatível")
	}
	return nil
}

func saveFeedbackState(state feedbackState) error {
	if state.Path == "" {
		return nil
	}
	document := feedbackStoreDocument{
		SchemaVersion: feedbackSchemaVersion, PolicyVersion: feedbackPolicyVersion,
		UpdatedAt: time.Now().UTC().Format(time.RFC3339), Records: state.Records,
	}
	data, err := json.Marshal(document)
	if err != nil || len(data) > feedbackMaxStoreBytes {
		return errors.New("fila de feedback excedeu o contrato seguro")
	}
	temporary := state.Path + ".tmp-" + hex.EncodeToString(randomBytes(6))
	file, err := os.OpenFile(temporary, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	removeTemporary := true
	defer func() {
		_ = file.Close()
		if removeTemporary {
			_ = os.Remove(temporary)
		}
	}()
	if _, err := file.Write(data); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if info, err := os.Lstat(state.Path); err == nil &&
		(!info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0) {
		return errors.New("destino de feedback não é arquivo regular")
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.Rename(temporary, state.Path); err != nil {
		return err
	}
	removeTemporary = false
	return nil
}

func pruneFeedbackRecords(records []feedbackRecord, now time.Time) []feedbackRecord {
	filtered := make([]feedbackRecord, 0, len(records))
	for _, record := range records {
		createdAt, err := time.Parse(time.RFC3339, record.CreatedAt)
		if err == nil && !createdAt.After(now.Add(5*time.Minute)) && now.Sub(createdAt) <= feedbackRetention {
			filtered = append(filtered, record)
		}
	}
	if len(filtered) > feedbackMaxRecords {
		filtered = append([]feedbackRecord(nil), filtered[len(filtered)-feedbackMaxRecords:]...)
	}
	return filtered
}

func (a *webApp) issueFeedbackToken(mode, fallbackReason string) map[string]any {
	if _, ok := feedbackModes[mode]; !ok {
		mode = "basic"
	}
	if _, ok := feedbackFallbackReasons[fallbackReason]; !ok {
		fallbackReason = ""
	}
	controlVersion := a.version
	if !validSemanticVersion(controlVersion) {
		controlVersion = "0.0.0"
	}
	now := time.Now().UTC()
	token := hex.EncodeToString(randomBytes(24))
	a.feedbackMu.Lock()
	if a.feedbackTokens == nil {
		a.feedbackTokens = make(map[string]feedbackTokenRecord)
	}
	for candidate, record := range a.feedbackTokens {
		if now.After(record.Expires) {
			delete(a.feedbackTokens, candidate)
		}
	}
	a.feedbackTokens[token] = feedbackTokenRecord{
		Expires: now.Add(feedbackTokenTTL), AssistantMode: mode,
		FallbackReason: fallbackReason, ControlVersion: controlVersion,
	}
	a.feedbackMu.Unlock()
	return map[string]any{
		"token": token, "policyVersion": feedbackPolicyVersion,
		"expiresInMinutes": int(feedbackTokenTTL / time.Minute),
	}
}

func (a *webApp) sendFeedbackTokenSSE(w http.ResponseWriter, mode, fallbackReason string) {
	sendSSE(w, "feedback", a.issueFeedbackToken(mode, fallbackReason))
}

func (a *webApp) handleFeedbackSubmit(w http.ResponseWriter, r *http.Request) {
	var input feedbackSubmission
	if err := decodeJSON(w, r, &input, 4096); err != nil {
		return
	}
	if !input.Consent {
		writeError(w, http.StatusBadRequest, "consentimento explícito obrigatório")
		return
	}
	if err := validateFeedbackClassification(input.Rating, input.Area, input.Reason); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	now := time.Now().UTC()
	a.feedbackMu.Lock()
	tokenRecord, exists := a.feedbackTokens[input.Token]
	if !exists || now.After(tokenRecord.Expires) {
		delete(a.feedbackTokens, input.Token)
		a.feedbackMu.Unlock()
		writeError(w, http.StatusBadRequest, "feedback ausente, expirado ou já utilizado")
		return
	}
	record := feedbackRecord{
		FeedbackID: hex.EncodeToString(randomBytes(12)), CreatedAt: now.Format(time.RFC3339),
		ControlVersion: tokenRecord.ControlVersion, AssistantMode: tokenRecord.AssistantMode,
		FallbackReason: tokenRecord.FallbackReason, Rating: input.Rating,
		Area: input.Area, Reason: input.Reason, Status: "pending_review",
	}
	previous := append([]feedbackRecord(nil), a.feedback.Records...)
	a.feedback.Records = pruneFeedbackRecords(append(a.feedback.Records, record), now)
	if err := saveFeedbackState(a.feedback); err != nil {
		a.feedback.Records = previous
		a.feedbackMu.Unlock()
		writeError(w, http.StatusInternalServerError, "não foi possível armazenar o feedback seguro")
		return
	}
	delete(a.feedbackTokens, input.Token)
	a.feedbackMu.Unlock()
	a.addAudit("assistant_feedback", "Feedback estruturado recebido para revisão humana", "sessão autenticada")
	writeJSON(w, http.StatusCreated, map[string]any{
		"status": record.Status, "feedbackId": record.FeedbackID,
		"retentionDays": int(feedbackRetention / (24 * time.Hour)),
	})
}

func (a *webApp) handleFeedbackList(w http.ResponseWriter, _ *http.Request) {
	a.feedbackMu.Lock()
	records := append([]feedbackRecord(nil), a.feedback.Records...)
	a.feedbackMu.Unlock()
	sort.Slice(records, func(i, j int) bool { return records[i].CreatedAt > records[j].CreatedAt })
	writeJSON(w, http.StatusOK, map[string]any{
		"privacy": map[string]any{
			"conversationStored": false, "networkAddressStored": false,
			"freeTextAccepted": false, "humanReviewRequired": true,
		},
		"report": buildFeedbackReport(records, a.version), "records": records,
	})
}

func buildFeedbackReport(records []feedbackRecord, controlVersion string) feedbackReport {
	report := feedbackReport{
		PolicyVersion: feedbackPolicyVersion, ControlVersion: controlVersion,
		RetentionDays: int(feedbackRetention / (24 * time.Hour)),
		AreaCounts:    make(map[string]int), ReasonCounts: make(map[string]int),
		VersionCounts: make(map[string]int),
	}
	for _, record := range records {
		report.Total++
		if record.Rating == "helpful" {
			report.Helpful++
		} else {
			report.Unhelpful++
		}
		report.AreaCounts[record.Area]++
		report.ReasonCounts[record.Reason]++
		report.VersionCounts[record.ControlVersion]++
		switch record.Status {
		case "pending_review":
			report.Pending++
		case "accepted_for_eval":
			report.Accepted++
		case "dismissed":
			report.Dismissed++
		}
	}
	return report
}

func (a *webApp) handleFeedbackReview(w http.ResponseWriter, r *http.Request) {
	var input feedbackReviewRequest
	if err := decodeJSON(w, r, &input, 4096); err != nil {
		return
	}
	status := ""
	switch input.Decision {
	case "accept_for_eval":
		status = "accepted_for_eval"
	case "dismiss":
		status = "dismissed"
	default:
		writeError(w, http.StatusBadRequest, "decisão de revisão inválida")
		return
	}
	a.feedbackMu.Lock()
	index := -1
	for candidate := range a.feedback.Records {
		if a.feedback.Records[candidate].FeedbackID == input.FeedbackID {
			index = candidate
			break
		}
	}
	if index < 0 || a.feedback.Records[index].Status != "pending_review" {
		a.feedbackMu.Unlock()
		writeError(w, http.StatusBadRequest, "feedback ausente ou já revisado")
		return
	}
	previous := a.feedback.Records[index]
	a.feedback.Records[index].Status = status
	a.feedback.Records[index].ReviewedAt = time.Now().UTC().Format(time.RFC3339)
	updated := a.feedback.Records[index]
	if err := saveFeedbackState(a.feedback); err != nil {
		a.feedback.Records[index] = previous
		a.feedbackMu.Unlock()
		writeError(w, http.StatusInternalServerError, "não foi possível registrar a revisão")
		return
	}
	a.feedbackMu.Unlock()
	a.addAudit("assistant_feedback_review", "Feedback estruturado revisado: "+status, "sessão autenticada")
	writeJSON(w, http.StatusOK, updated)
}

func (a *webApp) handleFeedbackDelete(w http.ResponseWriter, r *http.Request) {
	var input feedbackDeleteRequest
	if err := decodeJSON(w, r, &input, 4096); err != nil {
		return
	}
	a.feedbackMu.Lock()
	index := -1
	for candidate := range a.feedback.Records {
		if a.feedback.Records[candidate].FeedbackID == input.FeedbackID {
			index = candidate
			break
		}
	}
	if index < 0 {
		a.feedbackMu.Unlock()
		writeError(w, http.StatusBadRequest, "feedback não encontrado")
		return
	}
	previous := append([]feedbackRecord(nil), a.feedback.Records...)
	a.feedback.Records = append(a.feedback.Records[:index], a.feedback.Records[index+1:]...)
	if err := saveFeedbackState(a.feedback); err != nil {
		a.feedback.Records = previous
		a.feedbackMu.Unlock()
		writeError(w, http.StatusInternalServerError, "não foi possível excluir o feedback")
		return
	}
	a.feedbackMu.Unlock()
	a.addAudit("assistant_feedback_delete", "Feedback estruturado excluído pelo administrador", "sessão autenticada")
	writeJSON(w, http.StatusOK, map[string]any{"status": "deleted"})
}

func normalizeFeedbackMode(mode string, fallback bool) string {
	mode = strings.ToLower(strings.TrimSpace(mode))
	if fallback {
		return "basic"
	}
	if _, ok := feedbackModes[mode]; ok {
		return mode
	}
	return "basic"
}
