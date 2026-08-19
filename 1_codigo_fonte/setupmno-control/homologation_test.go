package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func homologationTestJSON(t *testing.T, value any) []byte {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func homologationTestBundle(t *testing.T, candidate map[string]any, corrupt bool) []byte {
	t.Helper()
	candidateData := homologationTestJSON(t, candidate)
	manifest := map[string]any{
		"schemaVersion": 1, "kind": "setupmno-homologation-candidate-bundle",
		"runnerVersion": candidate["runnerVersion"], "candidateId": candidate["candidateId"],
		"candidateSHA256": homologationBytesSHA(candidateData), "candidateBytes": len(candidateData),
		"createdAt": candidate["createdAt"], "automaticPromotion": false, "officialSeal": false,
	}
	if corrupt {
		manifest["candidateSHA256"] = string(make([]byte, 64))
	}
	var raw bytes.Buffer
	archive := tar.NewWriter(&raw)
	for _, entry := range []struct {
		name string
		data []byte
	}{{"candidate.json", candidateData}, {"manifest.json", homologationTestJSON(t, manifest)}} {
		if err := archive.WriteHeader(&tar.Header{Name: entry.name, Mode: 0600, Size: int64(len(entry.data))}); err != nil {
			t.Fatal(err)
		}
		if _, err := archive.Write(entry.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	var compressed bytes.Buffer
	gzipWriter := gzip.NewWriter(&compressed)
	if _, err := gzipWriter.Write(raw.Bytes()); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return compressed.Bytes()
}

func homologationTestCandidate() map[string]any {
	checks := map[string]any{}
	for _, name := range []string{"deploy", "convergence", "health", "persistence", "restart", "update", "backup", "restore", "cleanup"} {
		checks[name] = map[string]any{"status": "passed", "evidence": "Teste isolado aprovado"}
	}
	return map[string]any{
		"schemaVersion": 1, "kind": "setupmno-homologation-candidate",
		"candidateId": "navidrome-amd64-260819120000-candidate", "runId": "setupmno-hml-navidrome-260819120000",
		"runnerVersion": "1.2.0", "setupId": "navidrome", "setupVersion": "7.25.0", "architecture": "amd64",
		"createdAt": "2026-08-19T12:00:00Z", "tester": map[string]any{"displayName": "Revisor MNO", "attestation": "self-attested"},
		"environment": map[string]any{"platform": "wsl2-docker-desktop", "orchestrator": "docker-swarm", "isolation": "setupmno-hml"},
		"artifact":    map[string]any{"path": "x86/SetupLowCodeMno/navidrome.sh", "sha256": string(bytes.Repeat([]byte("a"), 64))},
		"images":      []string{"deluan/navidrome@sha256:" + string(bytes.Repeat([]byte("b"), 64))},
		"checks":      checks, "result": "candidate-full", "sanitized": true,
		"submission": map[string]any{"status": "pending-maintainer-review", "automaticPromotion": false, "officialSeal": false},
	}
}

func prepareHomologationQueueTest(t *testing.T) (string, string, string) {
	t.Helper()
	root, state := t.TempDir(), t.TempDir()
	if err := os.MkdirAll(filepath.Join(state, "homologation-package"), 0700); err != nil {
		t.Fatal(err)
	}
	registry := map[string]any{
		"runnerVersion": "1.2.0", "setupVersion": "7.25.0",
		"entries": []any{map[string]any{"setupId": "navidrome", "artifacts": map[string]any{"amd64": map[string]any{"path": "x86/SetupLowCodeMno/navidrome.sh", "sha256": string(bytes.Repeat([]byte("a"), 64))}}}},
	}
	if err := os.WriteFile(filepath.Join(state, "homologation-package", "runner-registry.json"), homologationTestJSON(t, registry), 0600); err != nil {
		t.Fatal(err)
	}
	runID := "setupmno-hml-navidrome-260819120000"
	directory := filepath.Join(root, runID)
	if err := os.Mkdir(directory, 0700); err != nil {
		t.Fatal(err)
	}
	return root, state, directory
}

func TestHomologationQueuePendingAndApproved(t *testing.T) {
	root, state, directory := prepareHomologationQueueTest(t)
	candidate := homologationTestCandidate()
	bundle := homologationTestBundle(t, candidate, false)
	bundlePath := filepath.Join(directory, "navidrome-amd64-260819120000-candidate.tar.gz")
	if err := os.WriteFile(bundlePath, bundle, 0600); err != nil {
		t.Fatal(err)
	}
	queue, err := collectHomologationQueue(root, state)
	if err != nil || len(queue.Items) != 1 || queue.Items[0].Status != "pending" {
		t.Fatalf("fila pendente inválida: %#v %v", queue, err)
	}
	digest := sha256.Sum256(bundle)
	decision := map[string]any{
		"schemaVersion": 1, "kind": "setupmno-homologation-review-decision", "decisionId": "navidrome-review-260819130000",
		"candidateId": candidate["candidateId"], "candidateBundleSHA256": hex.EncodeToString(digest[:]), "decision": "approved",
		"reasonCode": "operational-evidence-accepted", "reason": "Evidência operacional suficiente", "reviewedBy": "Mantenedor MNO",
		"reviewedAt": "2026-08-19T13:00:00Z", "immutable": true, "governanceUpdated": false, "officialSeal": false,
	}
	decisionPath := filepath.Join(directory, "navidrome-amd64-260819120000-candidate-decision.json")
	if err := os.WriteFile(decisionPath, homologationTestJSON(t, decision), 0600); err != nil {
		t.Fatal(err)
	}
	queue, err = collectHomologationQueue(root, state)
	if err != nil || queue.Items[0].Status != "approved" || queue.Items[0].Decision == nil || queue.Summary["approved"] != 1 {
		t.Fatalf("decisão não classificada: %#v %v", queue, err)
	}
}

func TestHomologationQueueQuarantinesTamperedBundle(t *testing.T) {
	root, state, directory := prepareHomologationQueueTest(t)
	bundle := homologationTestBundle(t, homologationTestCandidate(), true)
	if err := os.WriteFile(filepath.Join(directory, "navidrome-amd64-260819120000-candidate.tar.gz"), bundle, 0600); err != nil {
		t.Fatal(err)
	}
	queue, err := collectHomologationQueue(root, state)
	if err != nil || len(queue.Items) != 1 || queue.Items[0].Status != "quarantine" || queue.Summary["quarantine"] != 1 {
		t.Fatalf("bundle adulterado não foi isolado: %#v %v", queue, err)
	}
}

func TestHomologationQueueAcceptsCompatiblePreviousSession(t *testing.T) {
	root, state, directory := prepareHomologationQueueTest(t)
	session := map[string]any{
		"runId": "setupmno-hml-navidrome-260819120000", "runnerVersion": "1.1.0", "setupId": "navidrome", "setupVersion": "7.23.0",
		"architecture": "amd64", "createdAt": "2026-08-19T12:00:00Z", "artifact": map[string]any{"path": "x86/SetupLowCodeMno/navidrome.sh", "sha256": string(bytes.Repeat([]byte("a"), 64))},
	}
	if err := os.WriteFile(filepath.Join(directory, "session.json"), homologationTestJSON(t, session), 0600); err != nil {
		t.Fatal(err)
	}
	queue, err := collectHomologationQueue(root, state)
	if err != nil || queue.Items[0].Status != "draft" || queue.Items[0].Compatibility != "current-artifact" || queue.Items[0].Warning == "" {
		t.Fatalf("sessão compatível não foi preservada: %#v %v", queue, err)
	}
}
