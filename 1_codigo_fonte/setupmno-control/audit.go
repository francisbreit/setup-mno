package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	auditSchemaVersion = 1
	auditPolicyVersion = "1.0.0"
	auditMaxRecords    = 2000
	auditMaxStoreBytes = 1024 << 10
	auditRetention     = 90 * 24 * time.Hour
)

var auditZeroHash = strings.Repeat("0", sha256.Size*2)

type auditEvent struct {
	Sequence       uint64 `json:"sequence"`
	Time           string `json:"time"`
	Actor          string `json:"actor"`
	Action         string `json:"action"`
	Resource       string `json:"resource"`
	Outcome        string `json:"outcome"`
	Detail         string `json:"detail"`
	Address        string `json:"address"`
	ControlVersion string `json:"controlVersion"`
	PreviousHash   string `json:"previousHash"`
	EventHash      string `json:"eventHash"`
}

type auditStoreDocument struct {
	SchemaVersion  int          `json:"schemaVersion"`
	PolicyVersion  string       `json:"policyVersion"`
	UpdatedAt      string       `json:"updatedAt"`
	AnchorSequence uint64       `json:"anchorSequence"`
	AnchorHash     string       `json:"anchorHash"`
	Events         []auditEvent `json:"events"`
}

type auditState struct {
	Path           string
	AnchorSequence uint64
	AnchorHash     string
	Events         []auditEvent
	LastError      string
}

type auditPagination struct {
	Limit      int    `json:"limit"`
	NextBefore uint64 `json:"nextBefore,omitempty"`
	HasMore    bool   `json:"hasMore"`
}

type auditIntegrity struct {
	Status            string `json:"status"`
	PolicyVersion     string `json:"policyVersion"`
	AnchorSequence    uint64 `json:"anchorSequence"`
	RetainedEvents    int    `json:"retainedEvents"`
	RetentionDays     int    `json:"retentionDays"`
	ChainHead         string `json:"chainHead"`
	PersistenceStatus string `json:"persistenceStatus"`
}

func loadAuditState(path string) (auditState, error) {
	state := auditState{
		Path:       path,
		AnchorHash: auditZeroHash,
		Events:     make([]auditEvent, 0, auditMaxRecords),
	}
	directory := filepath.Dir(path)
	info, err := os.Lstat(directory)
	if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return state, fmt.Errorf("diretório de auditoria: %w", err)
		}
	} else if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return state, errors.New("diretório de auditoria inválido")
	}

	data, err := readRegularFile(path, auditMaxStoreBytes)
	if errors.Is(err, os.ErrNotExist) {
		return state, nil
	}
	if err != nil {
		return state, fmt.Errorf("arquivo de auditoria: %w", err)
	}
	var document auditStoreDocument
	if err := decodeStrictJSON(data, &document); err != nil {
		return state, errors.New("arquivo de auditoria não possui JSON estrito")
	}
	if document.SchemaVersion != auditSchemaVersion ||
		document.PolicyVersion != auditPolicyVersion ||
		len(document.Events) > auditMaxRecords ||
		!validAuditHash(document.AnchorHash) {
		return state, errors.New("arquivo de auditoria incompatível")
	}
	state.AnchorSequence = document.AnchorSequence
	state.AnchorHash = document.AnchorHash
	state.Events = append(state.Events, document.Events...)
	if err := validateAuditState(state); err != nil {
		return auditState{}, err
	}
	if pruneAuditState(&state, time.Now().UTC()) {
		if err := saveAuditState(state); err != nil {
			return auditState{}, fmt.Errorf("retenção de auditoria: %w", err)
		}
	}
	return state, nil
}

func saveAuditState(state auditState) error {
	if state.Path == "" {
		return nil
	}
	if err := validateAuditState(state); err != nil {
		return err
	}
	document := auditStoreDocument{
		SchemaVersion: auditSchemaVersion, PolicyVersion: auditPolicyVersion,
		UpdatedAt: time.Now().UTC().Format(time.RFC3339), AnchorSequence: state.AnchorSequence,
		AnchorHash: state.AnchorHash, Events: state.Events,
	}
	data, err := json.Marshal(document)
	if err != nil || len(data) > auditMaxStoreBytes {
		return errors.New("registro de auditoria excedeu o contrato seguro")
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
		return errors.New("destino de auditoria não é arquivo regular")
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.Rename(temporary, state.Path); err != nil {
		return err
	}
	removeTemporary = false
	return nil
}

func validateAuditState(state auditState) error {
	if !validAuditHash(state.AnchorHash) || len(state.Events) > auditMaxRecords {
		return errors.New("cadeia de auditoria inválida")
	}
	sequence := state.AnchorSequence
	previousHash := state.AnchorHash
	for _, event := range state.Events {
		if err := validateAuditEvent(event, sequence, previousHash); err != nil {
			return err
		}
		sequence = event.Sequence
		previousHash = event.EventHash
	}
	return nil
}

func validateAuditEvent(event auditEvent, previousSequence uint64, previousHash string) error {
	if event.Sequence != previousSequence+1 || event.PreviousHash != previousHash ||
		!validAuditHash(event.EventHash) || !validSemanticVersion(event.ControlVersion) {
		return errors.New("evento de auditoria possui cadeia inválida")
	}
	createdAt, err := time.Parse(time.RFC3339, event.Time)
	if err != nil || createdAt.After(time.Now().UTC().Add(5*time.Minute)) ||
		!validAuditText(event.Actor, 64) || !validAuditKey(event.Action) ||
		!validAuditKey(event.Resource) || !validAuditOutcome(event.Outcome) ||
		!validAuditText(event.Detail, 320) || !validAuditText(event.Address, 256) ||
		event.EventHash != auditEventHash(event) {
		return errors.New("evento de auditoria inválido")
	}
	return nil
}

func validAuditHash(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size
}

func validAuditText(value string, maximum int) bool {
	value = strings.TrimSpace(value)
	return value != "" && len([]rune(value)) <= maximum && !strings.ContainsAny(value, "\r\n\x00")
}

func validAuditKey(value string) bool {
	if value == "" || len(value) > 64 {
		return false
	}
	for _, character := range value {
		if (character < 'a' || character > 'z') &&
			(character < '0' || character > '9') && character != '_' && character != '-' {
			return false
		}
	}
	return true
}

func validAuditOutcome(value string) bool {
	switch value {
	case "success", "denied", "fallback", "failure", "info":
		return true
	default:
		return false
	}
}

func auditEventHash(event auditEvent) string {
	material := struct {
		Sequence       uint64 `json:"sequence"`
		Time           string `json:"time"`
		Actor          string `json:"actor"`
		Action         string `json:"action"`
		Resource       string `json:"resource"`
		Outcome        string `json:"outcome"`
		Detail         string `json:"detail"`
		Address        string `json:"address"`
		ControlVersion string `json:"controlVersion"`
		PreviousHash   string `json:"previousHash"`
	}{
		Sequence: event.Sequence, Time: event.Time, Actor: event.Actor, Action: event.Action,
		Resource: event.Resource, Outcome: event.Outcome, Detail: event.Detail,
		Address: event.Address, ControlVersion: event.ControlVersion, PreviousHash: event.PreviousHash,
	}
	data, _ := json.Marshal(material)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func appendAuditEvent(state *auditState, event auditEvent) {
	if state.AnchorHash == "" {
		state.AnchorHash = auditZeroHash
	}
	sequence := state.AnchorSequence
	previousHash := state.AnchorHash
	if len(state.Events) > 0 {
		last := state.Events[len(state.Events)-1]
		sequence = last.Sequence
		previousHash = last.EventHash
	}
	event.Sequence = sequence + 1
	event.PreviousHash = previousHash
	event.EventHash = auditEventHash(event)
	state.Events = append(state.Events, event)
}

func pruneAuditState(state *auditState, now time.Time) bool {
	firstKept := 0
	for firstKept < len(state.Events) {
		createdAt, err := time.Parse(time.RFC3339, state.Events[firstKept].Time)
		if err != nil || (!createdAt.After(now.Add(5*time.Minute)) && now.Sub(createdAt) <= auditRetention) {
			break
		}
		state.AnchorSequence = state.Events[firstKept].Sequence
		state.AnchorHash = state.Events[firstKept].EventHash
		firstKept++
	}
	if firstKept > 0 {
		state.Events = append([]auditEvent(nil), state.Events[firstKept:]...)
	}
	if len(state.Events) <= auditMaxRecords {
		return firstKept > 0
	}
	discard := len(state.Events) - auditMaxRecords
	lastDiscarded := state.Events[discard-1]
	state.AnchorSequence = lastDiscarded.Sequence
	state.AnchorHash = lastDiscarded.EventHash
	state.Events = append([]auditEvent(nil), state.Events[discard:]...)
	return true
}

func auditPage(events []auditEvent, before uint64, limit int) ([]auditEvent, auditPagination) {
	if limit < 1 || limit > 100 {
		limit = 50
	}
	result := make([]auditEvent, 0, limit)
	more := false
	for index := len(events) - 1; index >= 0; index-- {
		event := events[index]
		if before > 0 && event.Sequence >= before {
			continue
		}
		if len(result) == limit {
			more = true
			break
		}
		result = append(result, event)
	}
	pagination := auditPagination{Limit: limit, HasMore: more}
	if more && len(result) > 0 {
		pagination.NextBefore = result[len(result)-1].Sequence
	}
	return result, pagination
}

func auditChainHead(state auditState) string {
	if len(state.Events) == 0 {
		return state.AnchorHash
	}
	return state.Events[len(state.Events)-1].EventHash
}

func inferAuditActor(action string) string {
	switch {
	case action == "login_failed":
		return "anonymous"
	case strings.HasPrefix(action, "sentinel_"):
		return "mno_sentinel"
	case strings.HasPrefix(action, "fleet_tool"):
		return "vibe_ops_agent"
	case strings.HasPrefix(action, "fleet_"):
		return "fleet_controller"
	default:
		return "admin"
	}
}

func inferAuditResource(action string) string {
	for _, prefix := range []string{"terminal", "assistant", "blueprint", "catalog", "setup", "provider", "login", "logout", "fleet", "sentinel"} {
		if strings.HasPrefix(action, prefix) {
			return prefix
		}
	}
	return "control_center"
}

func inferAuditOutcome(action string) string {
	switch {
	case strings.Contains(action, "fallback"):
		return "fallback"
	case strings.Contains(action, "failed") || strings.Contains(action, "blocked") || strings.Contains(action, "rejected"):
		return "denied"
	default:
		return "success"
	}
}

func filterAuditEvents(events []auditEvent, scope string) []auditEvent {
	if scope == "" || scope == "all" {
		return events
	}
	filtered := make([]auditEvent, 0, len(events))
	for _, ev := range events {
		if matchAuditScope(ev, scope) {
			filtered = append(filtered, ev)
		}
	}
	return filtered
}

func matchAuditScope(ev auditEvent, scope string) bool {
	switch scope {
	case "vibe_ops":
		return ev.Resource == "fleet" || ev.Resource == "sentinel" ||
			strings.HasPrefix(ev.Action, "fleet_") || strings.HasPrefix(ev.Action, "sentinel_") ||
			ev.Actor == "vibe_ops_agent" || ev.Actor == "mno_sentinel" || ev.Actor == "fleet_controller"
	case "fleet":
		return ev.Resource == "fleet" || strings.HasPrefix(ev.Action, "fleet_")
	case "sentinel":
		return ev.Resource == "sentinel" || strings.HasPrefix(ev.Action, "sentinel_") || ev.Actor == "mno_sentinel"
	case "terminal":
		return ev.Resource == "terminal" || strings.HasPrefix(ev.Action, "terminal_")
	case "assistant":
		return ev.Resource == "assistant" || strings.HasPrefix(ev.Action, "assistant_")
	case "security", "session":
		return ev.Resource == "login" || ev.Resource == "logout" || strings.Contains(ev.Action, "login") || strings.Contains(ev.Action, "logout")
	default:
		return ev.Resource == scope || strings.HasPrefix(ev.Action, scope)
	}
}
