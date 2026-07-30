package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestReadRuntimeSnapshot(t *testing.T) {
	directory := t.TempDir()
	catalog := []byte(`[{"name":"TESTE","cats":"Utilitários","arch":"x86-arm"}]`)
	sum := sha256.Sum256(catalog)
	release := setupRelease{
		SchemaVersion:  runtimeSchema,
		SetupVersion:   "4.92.4",
		CatalogVersion: "4.92.4",
		CatalogSHA256:  hex.EncodeToString(sum[:]),
		CatalogEntries: 1,
		Architecture:   "amd64",
	}
	releaseData, err := json.Marshal(release)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "catalog.json"), catalog, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "release.json"), releaseData, 0o600); err != nil {
		t.Fatal(err)
	}

	snapshot, err := readRuntimeSnapshot(directory)
	if err != nil {
		t.Fatalf("snapshot válido foi recusado: %v", err)
	}
	if snapshot.Release.SetupVersion != "4.92.4" || len(snapshot.Items) != 1 {
		t.Fatalf("snapshot inesperado: %#v", snapshot)
	}
}

func TestReadRuntimeSnapshotRejectsCatalogMismatch(t *testing.T) {
	directory := t.TempDir()
	catalog := []byte(`[{"name":"TESTE"}]`)
	release := setupRelease{
		SchemaVersion:  runtimeSchema,
		SetupVersion:   "4.92.4",
		CatalogVersion: "4.92.4",
		CatalogSHA256:  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		CatalogEntries: 1,
		Architecture:   "arm64",
	}
	releaseData, err := json.Marshal(release)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "catalog.json"), catalog, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "release.json"), releaseData, 0o600); err != nil {
		t.Fatal(err)
	}

	if _, err := readRuntimeSnapshot(directory); err == nil {
		t.Fatal("catálogo com SHA-256 divergente foi aceito")
	}
}
