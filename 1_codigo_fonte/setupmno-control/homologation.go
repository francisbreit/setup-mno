package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	homologationMaxBundle = 2 << 20
	homologationMaxJSON   = 256 << 10
	homologationMaxItems  = 200
)

var (
	homologationRunID = regexp.MustCompile(`^setupmno-hml-[a-z0-9]+(?:-[a-z0-9]+)*-[0-9]{12}$`)
	homologationID    = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)
	homologationSHA   = regexp.MustCompile(`^[a-f0-9]{64}$`)
	homologationImage = regexp.MustCompile(`^\S+@sha256:[a-f0-9]{64}$`)
	homologationPath  = regexp.MustCompile(`^(x86|arm)/SetupLowCodeMno/[a-z0-9_-]+\.sh$`)
)

type homologationArtifact struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

type homologationCheck struct {
	Status   string `json:"status"`
	Evidence string `json:"evidence"`
}

type homologationTester struct {
	DisplayName string `json:"displayName"`
	Attestation string `json:"attestation"`
}

type homologationEnvironment struct {
	Platform     string `json:"platform"`
	Orchestrator string `json:"orchestrator"`
	Isolation    string `json:"isolation"`
}

type homologationCandidate struct {
	SchemaVersion int                          `json:"schemaVersion"`
	Kind          string                       `json:"kind"`
	CandidateID   string                       `json:"candidateId"`
	RunID         string                       `json:"runId"`
	RunnerVersion string                       `json:"runnerVersion"`
	SetupID       string                       `json:"setupId"`
	SetupVersion  string                       `json:"setupVersion"`
	Architecture  string                       `json:"architecture"`
	CreatedAt     string                       `json:"createdAt"`
	Tester        homologationTester           `json:"tester"`
	Environment   homologationEnvironment      `json:"environment"`
	Artifact      homologationArtifact         `json:"artifact"`
	Images        []string                     `json:"images"`
	Checks        map[string]homologationCheck `json:"checks"`
	Result        string                       `json:"result"`
	Sanitized     bool                         `json:"sanitized"`
	Submission    struct {
		Status             string `json:"status"`
		AutomaticPromotion bool   `json:"automaticPromotion"`
		OfficialSeal       bool   `json:"officialSeal"`
	} `json:"submission"`
}

type homologationDecision struct {
	SchemaVersion         int    `json:"schemaVersion"`
	Kind                  string `json:"kind"`
	DecisionID            string `json:"decisionId"`
	CandidateID           string `json:"candidateId"`
	CandidateBundleSHA256 string `json:"candidateBundleSHA256"`
	Decision              string `json:"decision"`
	ReasonCode            string `json:"reasonCode"`
	Reason                string `json:"reason"`
	ReviewedBy            string `json:"reviewedBy"`
	ReviewedAt            string `json:"reviewedAt"`
	Immutable             bool   `json:"immutable"`
	GovernanceUpdated     bool   `json:"governanceUpdated"`
	OfficialSeal          bool   `json:"officialSeal"`
}

type essentialHomologationSeal struct {
	SchemaVersion         int                          `json:"schemaVersion"`
	Kind                  string                       `json:"kind"`
	SealID                string                       `json:"sealId"`
	CandidateID           string                       `json:"candidateId"`
	SetupID               string                       `json:"setupId"`
	SetupVersion          string                       `json:"setupVersion"`
	Architecture          string                       `json:"architecture"`
	IssuedAt              string                       `json:"issuedAt"`
	IssuedBy              string                       `json:"issuedBy"`
	Scope                 string                       `json:"scope"`
	Artifact              homologationArtifact         `json:"artifact"`
	Images                []string                     `json:"images"`
	Checks                map[string]homologationCheck `json:"checks"`
	CandidateBundleSHA256 string                       `json:"candidateBundleSHA256"`
	DecisionSHA256        string                       `json:"decisionSHA256"`
	Status                string                       `json:"status"`
	Immutable             bool                         `json:"immutable"`
	MaintainerAttested    bool                         `json:"maintainerAttested"`
	AutomaticPublication  bool                         `json:"automaticPublication"`
	OfficialSeal          bool                         `json:"officialSeal"`
}

type homologationQueueItem struct {
	Kind          string                       `json:"kind"`
	ID            string                       `json:"id"`
	RunID         string                       `json:"runId,omitempty"`
	CandidateID   string                       `json:"candidateId,omitempty"`
	SetupID       string                       `json:"setupId,omitempty"`
	SetupVersion  string                       `json:"setupVersion,omitempty"`
	RunnerVersion string                       `json:"runnerVersion,omitempty"`
	Architecture  string                       `json:"architecture,omitempty"`
	CreatedAt     string                       `json:"createdAt,omitempty"`
	Compatibility string                       `json:"compatibility"`
	Status        string                       `json:"status"`
	Result        string                       `json:"result,omitempty"`
	Artifact      homologationArtifact         `json:"artifact,omitempty"`
	BundleSHA256  string                       `json:"bundleSHA256,omitempty"`
	Images        []string                     `json:"images,omitempty"`
	Checks        map[string]homologationCheck `json:"checks,omitempty"`
	Decision      *homologationDecision        `json:"decision,omitempty"`
	SealID        string                       `json:"sealId,omitempty"`
	SealScope     string                       `json:"sealScope,omitempty"`
	OfficialSeal  bool                         `json:"officialSeal"`
	Warning       string                       `json:"warning,omitempty"`
}

type homologationQueueResponse struct {
	SchemaVersion int                     `json:"schemaVersion"`
	Source        string                  `json:"source"`
	GeneratedAt   time.Time               `json:"generatedAt"`
	SetupVersion  string                  `json:"setupVersion"`
	RunnerVersion string                  `json:"runnerVersion"`
	Summary       map[string]int          `json:"summary"`
	Items         []homologationQueueItem `json:"items"`
}

type homologationRegistry struct {
	RunnerVersion string `json:"runnerVersion"`
	SetupVersion  string `json:"setupVersion"`
	Entries       []struct {
		SetupID   string                          `json:"setupId"`
		Artifacts map[string]homologationArtifact `json:"artifacts"`
	} `json:"entries"`
}

func collectHomologationQueue(candidateRoot, setupStateDir string) (homologationQueueResponse, error) {
	response := homologationQueueResponse{
		SchemaVersion: 1,
		Source:        "runtime-read-only",
		GeneratedAt:   time.Now().UTC(),
		Summary:       map[string]int{"pending": 0, "approved": 0, "sealed": 0, "rejected": 0, "draft": 0, "incompatible": 0, "quarantine": 0},
		Items:         []homologationQueueItem{},
	}
	registryData, err := homologationReadRegular(filepath.Join(setupStateDir, "homologation-package", "runner-registry.json"), homologationMaxJSON)
	if err != nil {
		return response, fmt.Errorf("registro runtime indisponível: %w", err)
	}
	var registry homologationRegistry
	if err := json.Unmarshal(registryData, &registry); err != nil || registry.RunnerVersion == "" || registry.SetupVersion == "" {
		return response, errors.New("registro runtime inválido")
	}
	response.SetupVersion = registry.SetupVersion
	response.RunnerVersion = registry.RunnerVersion
	artifacts := make(map[string]homologationArtifact)
	for _, entry := range registry.Entries {
		for arch, artifact := range entry.Artifacts {
			artifacts[entry.SetupID+"/"+arch] = artifact
		}
	}

	rootInfo, err := os.Lstat(candidateRoot)
	if errors.Is(err, os.ErrNotExist) {
		return response, nil
	}
	if err != nil || !rootInfo.IsDir() || rootInfo.Mode()&os.ModeSymlink != 0 {
		return response, errors.New("diretório de candidatos inválido")
	}
	entries, err := os.ReadDir(candidateRoot)
	if err != nil {
		return response, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() > entries[j].Name() })
	for _, directory := range entries {
		if len(response.Items) >= homologationMaxItems || !directory.IsDir() || !homologationRunID.MatchString(directory.Name()) {
			continue
		}
		directoryPath := filepath.Join(candidateRoot, directory.Name())
		if info, statErr := os.Lstat(directoryPath); statErr != nil || info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		files, readErr := os.ReadDir(directoryPath)
		if readErr != nil {
			continue
		}
		candidateFound := false
		for _, file := range files {
			if len(response.Items) >= homologationMaxItems || file.IsDir() || !strings.HasSuffix(file.Name(), "-candidate.tar.gz") {
				continue
			}
			candidateFound = true
			item := inspectHomologationCandidate(filepath.Join(directoryPath, file.Name()), artifacts)
			response.Items = append(response.Items, item)
			response.Summary[item.Status]++
		}
		if !candidateFound && len(response.Items) < homologationMaxItems {
			item := inspectHomologationSession(filepath.Join(directoryPath, "session.json"), directory.Name(), registry, artifacts)
			response.Items = append(response.Items, item)
			response.Summary[item.Status]++
		}
	}
	return response, nil
}

func inspectHomologationSession(filename, runID string, registry homologationRegistry, artifacts map[string]homologationArtifact) homologationQueueItem {
	item := homologationQueueItem{Kind: "session", ID: runID, RunID: runID, Compatibility: "unknown", Status: "quarantine"}
	data, err := homologationReadRegular(filename, homologationMaxJSON)
	if err != nil {
		item.Warning = "Sessão ausente ou ilegível"
		return item
	}
	var session struct {
		RunID         string               `json:"runId"`
		RunnerVersion string               `json:"runnerVersion"`
		SetupID       string               `json:"setupId"`
		SetupVersion  string               `json:"setupVersion"`
		Architecture  string               `json:"architecture"`
		CreatedAt     string               `json:"createdAt"`
		Artifact      homologationArtifact `json:"artifact"`
	}
	if json.Unmarshal(data, &session) != nil || session.RunID != runID || !homologationID.MatchString(session.SetupID) {
		item.Warning = "Sessão inválida"
		return item
	}
	item.SetupID, item.SetupVersion, item.RunnerVersion = session.SetupID, session.SetupVersion, session.RunnerVersion
	item.Architecture, item.CreatedAt, item.Artifact = session.Architecture, session.CreatedAt, session.Artifact
	current, ok := artifacts[session.SetupID+"/"+session.Architecture]
	if ok && current == session.Artifact {
		item.Compatibility = "current-artifact"
		item.Status = "draft"
		if session.SetupVersion != registry.SetupVersion || session.RunnerVersion != registry.RunnerVersion {
			item.Warning = "Sessão anterior compatível: o artefato testado continua atual"
		}
	} else {
		item.Compatibility = "artifact-mismatch"
		item.Status = "incompatible"
		item.Warning = "O instalador atual diverge do artefato registrado"
	}
	return item
}

func inspectHomologationCandidate(filename string, artifacts map[string]homologationArtifact) homologationQueueItem {
	item := homologationQueueItem{Kind: "candidate", ID: filepath.Base(filename), Compatibility: "unknown", Status: "quarantine"}
	bundle, err := homologationReadRegular(filename, homologationMaxBundle)
	if err != nil {
		item.Warning = "Bundle ilegível"
		return item
	}
	digest := sha256.Sum256(bundle)
	item.BundleSHA256 = hex.EncodeToString(digest[:])
	candidateData, err := homologationCandidateFromBundle(bundle)
	if err != nil {
		item.Warning = err.Error()
		return item
	}
	var candidate homologationCandidate
	if homologationDecodeStrict(candidateData, &candidate) != nil || !validHomologationCandidate(candidate) {
		item.Warning = "Candidato inválido ou fora do schema permitido"
		return item
	}
	item.ID, item.CandidateID, item.RunID = candidate.CandidateID, candidate.CandidateID, candidate.RunID
	item.SetupID, item.SetupVersion, item.RunnerVersion = candidate.SetupID, candidate.SetupVersion, candidate.RunnerVersion
	item.Architecture, item.CreatedAt, item.Result = candidate.Architecture, candidate.CreatedAt, candidate.Result
	item.Artifact, item.Images, item.Checks = candidate.Artifact, candidate.Images, candidate.Checks
	current, ok := artifacts[candidate.SetupID+"/"+candidate.Architecture]
	if !ok || current != candidate.Artifact {
		item.Compatibility, item.Status = "artifact-mismatch", "incompatible"
		item.Warning = "O instalador atual diverge do artefato testado"
		return item
	}
	item.Compatibility, item.Status = "current-artifact", "pending"
	decisionPath := strings.TrimSuffix(filename, ".tar.gz") + "-decision.json"
	if decision, decisionErr := homologationDecisionFromFile(decisionPath, candidate.CandidateID, item.BundleSHA256); decisionErr == nil {
		item.Decision = decision
		item.Status = decision.Decision
		sealPath := strings.TrimSuffix(filename, ".tar.gz") + "-essential-seal.json"
		if seal, sealErr := essentialSealFromFile(sealPath, candidate, decision, item.BundleSHA256, decisionPath); sealErr == nil {
			item.SealID, item.SealScope, item.OfficialSeal = seal.SealID, seal.Scope, true
			item.Status = "sealed"
		} else if !errors.Is(sealErr, os.ErrNotExist) {
			item.Status = "quarantine"
			item.Warning = "Selo essencial associado inválido"
		}
	} else if !errors.Is(decisionErr, os.ErrNotExist) {
		item.Status = "quarantine"
		item.Warning = "Decisão associada inválida"
	}
	return item
}

func essentialSealFromFile(filename string, candidate homologationCandidate, decision *homologationDecision, bundleSHA, decisionPath string) (*essentialHomologationSeal, error) {
	data, err := homologationReadRegular(filename, homologationMaxJSON)
	if err != nil {
		return nil, err
	}
	decisionData, err := homologationReadRegular(decisionPath, homologationMaxJSON)
	if err != nil {
		return nil, err
	}
	decisionDigest := sha256.Sum256(decisionData)
	var seal essentialHomologationSeal
	if homologationDecodeStrict(data, &seal) != nil || seal.SchemaVersion != 1 ||
		seal.Kind != "setupmno-essential-homologation-seal" || !homologationID.MatchString(seal.SealID) ||
		seal.CandidateID != candidate.CandidateID || seal.SetupID != candidate.SetupID ||
		seal.SetupVersion != candidate.SetupVersion || seal.Architecture != candidate.Architecture ||
		seal.Scope != "essential-startup" || seal.Artifact != candidate.Artifact ||
		seal.CandidateBundleSHA256 != bundleSHA || seal.DecisionSHA256 != hex.EncodeToString(decisionDigest[:]) ||
		seal.Status != "issued" || !seal.Immutable || !seal.MaintainerAttested ||
		seal.AutomaticPublication || !seal.OfficialSeal || decision.Decision != "approved" {
		return nil, errors.New("selo essencial inválido")
	}
	if _, err := time.Parse(time.RFC3339, seal.IssuedAt); err != nil || len(seal.IssuedBy) < 2 || len(seal.IssuedBy) > 80 {
		return nil, errors.New("identidade temporal do selo essencial inválida")
	}
	if len(seal.Images) != len(candidate.Images) || len(seal.Checks) != 3 {
		return nil, errors.New("escopo do selo essencial divergente")
	}
	for index := range seal.Images {
		if seal.Images[index] != candidate.Images[index] {
			return nil, errors.New("imagem do selo essencial divergente")
		}
	}
	for _, name := range []string{"deploy", "convergence", "health"} {
		check, ok := seal.Checks[name]
		if !ok || check != candidate.Checks[name] || check.Status != "passed" {
			return nil, errors.New("gate essencial divergente")
		}
	}
	return &seal, nil
}

func homologationCandidateFromBundle(bundle []byte) ([]byte, error) {
	gzipReader, err := gzip.NewReader(bytes.NewReader(bundle))
	if err != nil {
		return nil, errors.New("Bundle não é gzip válido")
	}
	defer gzipReader.Close()
	archive := tar.NewReader(io.LimitReader(gzipReader, 2*homologationMaxBundle))
	var candidate, manifestData []byte
	seen := map[string]bool{}
	expectedNames := []string{"candidate.json", "manifest.json"}
	entryIndex := 0
	for {
		header, nextErr := archive.Next()
		if errors.Is(nextErr, io.EOF) {
			break
		}
		if nextErr != nil {
			return nil, errors.New("Bundle tar inválido")
		}
		if entryIndex >= len(expectedNames) || header.Name != expectedNames[entryIndex] ||
			header.Typeflag != tar.TypeReg || seen[header.Name] || header.Size < 1 || header.Size > homologationMaxJSON {
			return nil, errors.New("Bundle contém inventário inseguro")
		}
		entryIndex++
		seen[header.Name] = true
		data, readErr := io.ReadAll(io.LimitReader(archive, homologationMaxJSON+1))
		if readErr != nil || int64(len(data)) != header.Size {
			return nil, errors.New("Entrada truncada no bundle")
		}
		if header.Name == "candidate.json" {
			candidate = data
		} else {
			manifestData = data
		}
	}
	if len(seen) != 2 || len(candidate) == 0 || len(manifestData) == 0 {
		return nil, errors.New("Bundle incompleto")
	}
	var manifest struct {
		SchemaVersion      int    `json:"schemaVersion"`
		Kind               string `json:"kind"`
		RunnerVersion      string `json:"runnerVersion"`
		CandidateID        string `json:"candidateId"`
		CandidateSHA256    string `json:"candidateSHA256"`
		CreatedAt          string `json:"createdAt"`
		CandidateBytes     int    `json:"candidateBytes"`
		AutomaticPromotion bool   `json:"automaticPromotion"`
		OfficialSeal       bool   `json:"officialSeal"`
	}
	if homologationDecodeStrict(manifestData, &manifest) != nil || manifest.SchemaVersion != 1 ||
		manifest.Kind != "setupmno-homologation-candidate-bundle" || manifest.CandidateBytes != len(candidate) ||
		manifest.CandidateSHA256 != homologationBytesSHA(candidate) || manifest.AutomaticPromotion || manifest.OfficialSeal {
		return nil, errors.New("Integridade do manifesto divergente")
	}
	var identity struct {
		CandidateID   string `json:"candidateId"`
		RunnerVersion string `json:"runnerVersion"`
		CreatedAt     string `json:"createdAt"`
	}
	if json.Unmarshal(candidate, &identity) != nil || manifest.CandidateID != identity.CandidateID ||
		manifest.RunnerVersion != identity.RunnerVersion || manifest.CreatedAt != identity.CreatedAt {
		return nil, errors.New("Manifesto não corresponde ao candidato")
	}
	return candidate, nil
}

func homologationBytesSHA(data []byte) string {
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}

func validHomologationCandidate(candidate homologationCandidate) bool {
	if candidate.SchemaVersion != 1 || candidate.Kind != "setupmno-homologation-candidate" ||
		!homologationID.MatchString(candidate.CandidateID) || !homologationRunID.MatchString(candidate.RunID) ||
		!homologationID.MatchString(candidate.SetupID) || (candidate.Architecture != "amd64" && candidate.Architecture != "arm64") ||
		(candidate.RunnerVersion != "1.1.0" && candidate.RunnerVersion != "1.2.0" && candidate.RunnerVersion != "1.3.0") ||
		!homologationPath.MatchString(candidate.Artifact.Path) || !homologationSHA.MatchString(candidate.Artifact.SHA256) || len(candidate.Images) == 0 ||
		!candidate.Sanitized || candidate.Submission.Status != "pending-maintainer-review" || candidate.Submission.AutomaticPromotion || candidate.Submission.OfficialSeal {
		return false
	}
	if _, err := time.Parse(time.RFC3339, candidate.CreatedAt); err != nil ||
		!validSemanticVersion(candidate.SetupVersion) || len(candidate.Tester.DisplayName) < 2 || len(candidate.Tester.DisplayName) > 80 ||
		candidate.Tester.Attestation != "self-attested" || candidate.Environment.Orchestrator != "docker-swarm" ||
		candidate.Environment.Isolation != "setupmno-hml" ||
		(candidate.Environment.Platform != "linux-vps" && candidate.Environment.Platform != "wsl2-docker-desktop" && candidate.Environment.Platform != "linux-emulated") {
		return false
	}
	expectedPrefix := "x86/"
	if candidate.Architecture == "arm64" {
		expectedPrefix = "arm/"
	}
	if !strings.HasPrefix(candidate.Artifact.Path, expectedPrefix) {
		return false
	}
	required := []string{"deploy", "convergence", "health", "persistence", "restart", "update", "backup", "restore", "cleanup"}
	seenImages := make(map[string]bool)
	for _, image := range candidate.Images {
		if !homologationImage.MatchString(image) || seenImages[image] {
			return false
		}
		seenImages[image] = true
	}
	for _, name := range required {
		check, ok := candidate.Checks[name]
		if !ok || check.Evidence == "" || len(check.Evidence) > 240 || (check.Status != "passed" && check.Status != "not-tested" && check.Status != "not-applicable") {
			return false
		}
	}
	for _, name := range []string{"deploy", "convergence", "health"} {
		if candidate.Checks[name].Status != "passed" {
			return false
		}
	}
	allPassed := true
	for _, name := range required {
		allPassed = allPassed && candidate.Checks[name].Status == "passed"
	}
	if (allPassed && candidate.Result != "candidate-full") || (!allPassed && candidate.Result != "candidate-operational") {
		return false
	}
	return len(candidate.Checks) == len(required)
}

func homologationDecisionFromFile(filename, candidateID, bundleSHA string) (*homologationDecision, error) {
	data, err := homologationReadRegular(filename, homologationMaxJSON)
	if err != nil {
		return nil, err
	}
	var decision homologationDecision
	if homologationDecodeStrict(data, &decision) != nil || decision.SchemaVersion != 1 || decision.Kind != "setupmno-homologation-review-decision" ||
		decision.CandidateID != candidateID || decision.CandidateBundleSHA256 != bundleSHA ||
		(decision.Decision != "approved" && decision.Decision != "rejected") || !decision.Immutable || decision.GovernanceUpdated || decision.OfficialSeal {
		return nil, errors.New("decisão inválida")
	}
	return &decision, nil
}

func homologationDecodeStrict(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		return errors.New("JSON contém dados adicionais")
	}
	return nil
}

func homologationReadRegular(filename string, limit int64) ([]byte, error) {
	info, err := os.Lstat(filename)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 || info.Size() > limit {
		return nil, errors.New("arquivo inseguro")
	}
	return os.ReadFile(filename)
}
