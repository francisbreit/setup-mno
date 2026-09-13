package main

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNormalizeArch(t *testing.T) {
	cases := []struct {
		input    string
		expected string
	}{
		{"x86_64", "amd64"},
		{"amd64", "amd64"},
		{"x64", "amd64"},
		{"aarch64", "arm64"},
		{"arm64", "arm64"},
		{"armv8", "arm64"},
		{"unknown", "unknown"},
	}

	for _, c := range cases {
		got := normalizeArch(c.input)
		if got != c.expected {
			t.Errorf("normalizeArch(%q) = %q; esperado %q", c.input, got, c.expected)
		}
	}
}

func TestEstimateAppMemoryMB(t *testing.T) {
	if got := estimateAppMemoryMB("chatwoot", nil); got != 2048 {
		t.Errorf("chatwoot RAM = %d; esperado 2048", got)
	}
	if got := estimateAppMemoryMB("wordpress", nil); got != 1024 {
		t.Errorf("wordpress RAM = %d; esperado 1024", got)
	}
	if got := estimateAppMemoryMB("n8n", nil); got != 512 {
		t.Errorf("n8n RAM = %d; esperado 512", got)
	}
	if got := estimateAppMemoryMB("meu-app-custom", []string{"sendingtk/chatwoot:latest"}); got != 2048 {
		t.Errorf("app com imagem chatwoot RAM = %d; esperado 2048", got)
	}
}

func TestPreflightCrossArchitectureBlocked(t *testing.T) {
	origin := FleetNodeStructure{
		NodeID:        "node-origin",
		Name:          "Torre Master (x86_64)",
		Architecture:  "x86_64",
		MemoryTotalMB: 8192,
		MemoryFreeMB:  4096,
		DiskTotalGB:   80,
		DiskFreeGB:    40,
		Apps: []FleetAppStructure{
			{
				Name:             "wordpress",
				RequiredMemoryMB: 1024,
				Volumes:          []FleetVolumeInfo{{Name: "wp_data", SizeBytes: 200 * 1024 * 1024}},
			},
		},
	}

	dest := FleetNodeStructure{
		NodeID:        "node-worker-oracle",
		Name:          "Worker Oracle ARM",
		Architecture:  "aarch64", // Incompatível com x86_64
		MemoryTotalMB: 24576,
		MemoryFreeMB:  16384,
		DiskTotalGB:   200,
		DiskFreeGB:    150,
	}

	result := EvaluateTransferPreflight(origin, dest, "wordpress", "transfer")

	if result.Allowed {
		t.Fatalf("Transferência cross-architecture deveria ter sido BLOQUEADA, mas foi permitida")
	}

	if result.SameArchitecture {
		t.Fatalf("SameArchitecture deveria ser false para x86_64 vs aarch64")
	}

	if result.Mode != "backup_only" {
		t.Errorf("Modo deveria ter sido rebaixado para 'backup_only', recebido: %s", result.Mode)
	}

	if !strings.Contains(result.BlockReason, "incompatíveis") || !strings.Contains(result.BlockReason, "BACKUP PORTÁTIL") {
		t.Errorf("BlockReason não explicou adequadamente o bloqueio: %s", result.BlockReason)
	}
}

func TestPreflightInsufficientRAMBlocked(t *testing.T) {
	origin := FleetNodeStructure{
		NodeID:        "node-origin",
		Name:          "Torre Master",
		Architecture:  "amd64",
		MemoryTotalMB: 8192,
		MemoryFreeMB:  4096,
		DiskTotalGB:   80,
		DiskFreeGB:    40,
		Apps: []FleetAppStructure{
			{
				Name:             "chatwoot",
				RequiredMemoryMB: 2048,
			},
		},
	}

	dest := FleetNodeStructure{
		NodeID:        "node-worker-small",
		Name:          "Worker Pequeno",
		Architecture:  "amd64", // Mesma arquitetura
		MemoryTotalMB: 1024,
		MemoryFreeMB:  256, // Insuficiente para Chatwoot (exige 2048 MB)
		DiskTotalGB:   50,
		DiskFreeGB:    30,
	}

	result := EvaluateTransferPreflight(origin, dest, "chatwoot", "transfer")

	if result.Allowed {
		t.Fatalf("Transferência com RAM insuficiente deveria ter sido bloqueada")
	}

	if result.HasCapacity {
		t.Fatalf("HasCapacity deveria ser false quando destino não tem RAM suficiente")
	}

	if !strings.Contains(result.BlockReason, "Memória RAM livre insuficiente") {
		t.Errorf("BlockReason esperado sobre RAM livre, recebido: %s", result.BlockReason)
	}
}

func TestPreflightInsufficientDiskBlocked(t *testing.T) {
	origin := FleetNodeStructure{
		NodeID:        "node-origin",
		Name:          "Torre Master",
		Architecture:  "amd64",
		MemoryTotalMB: 8192,
		MemoryFreeMB:  4096,
		DiskTotalGB:   80,
		DiskFreeGB:    40,
		Apps: []FleetAppStructure{
			{
				Name:             "minio-storage",
				RequiredMemoryMB: 512,
				Volumes: []FleetVolumeInfo{
					{Name: "data_vol", SizeBytes: 15 * 1024 * 1024 * 1024}, // 15 GB
				},
			},
		},
	}

	dest := FleetNodeStructure{
		NodeID:        "node-worker-full",
		Name:          "Worker Sem Disco",
		Architecture:  "amd64",
		MemoryTotalMB: 4096,
		MemoryFreeMB:  2048,
		DiskTotalGB:   20,
		DiskFreeGB:    5, // Apenas 5 GB livres, mas a app exige 18+ GB
	}

	result := EvaluateTransferPreflight(origin, dest, "minio-storage", "transfer")

	if result.Allowed {
		t.Fatalf("Transferência com disco insuficiente deveria ter sido bloqueada")
	}

	if result.HasCapacity {
		t.Fatalf("HasCapacity deveria ser false quando destino não tem disco suficiente")
	}

	if !strings.Contains(result.BlockReason, "Espaço em disco insuficiente") {
		t.Errorf("BlockReason esperado sobre disco, recebido: %s", result.BlockReason)
	}
}

func TestPreflightApprovedSameArchAndCapacity(t *testing.T) {
	origin := FleetNodeStructure{
		NodeID:        "node-origin",
		Name:          "Torre Master",
		Architecture:  "x86_64",
		MemoryTotalMB: 8192,
		MemoryFreeMB:  4096,
		DiskTotalGB:   80,
		DiskFreeGB:    40,
		Apps: []FleetAppStructure{
			{
				Name:             "n8n",
				RequiredMemoryMB: 512,
				Domains:          []string{"n8n.empresa.com"},
				Volumes:          []FleetVolumeInfo{{Name: "n8n_data", SizeBytes: 300 * 1024 * 1024}},
			},
		},
	}

	dest := FleetNodeStructure{
		NodeID:        "node-worker-01",
		Name:          "Worker Hetzner",
		Architecture:  "amd64", // Mesma arquitetura normalizada
		MemoryTotalMB: 4096,
		MemoryFreeMB:  2048,
		DiskTotalGB:   80,
		DiskFreeGB:    50,
	}

	result := EvaluateTransferPreflight(origin, dest, "n8n", "transfer")

	if !result.Allowed {
		t.Fatalf("Preflight deveria ter sido APROVADO, mas foi bloqueado: %s", result.BlockReason)
	}

	if !result.SameArchitecture {
		t.Errorf("SameArchitecture deveria ser true")
	}

	if !result.HasCapacity {
		t.Errorf("HasCapacity deveria ser true")
	}

	if result.DNSAction != "update_cname_and_ingress" {
		t.Errorf("DNSAction esperada: update_cname_and_ingress; recebido: %s", result.DNSAction)
	}
}

func TestExecuteApplicationBackupPortable(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "mno-backup-test-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	app := &webApp{}
	req := FleetBackupExecutionRequest{
		AppName:         "test-app",
		NodeID:          "local",
		TargetDirectory: tempDir,
		NotifySentinel:  false,
	}

	res, err := app.ExecuteApplicationBackup(context.Background(), req)
	if err != nil {
		t.Fatalf("ExecuteApplicationBackup falhou: %v", err)
	}

	if !res.Success {
		t.Fatalf("ExecuteApplicationBackup retornou Success=false: %s", res.Error)
	}

	if res.SizeBytes <= 0 || res.SHA256 == "" {
		t.Fatalf("SizeBytes (%d) ou SHA256 (%s) inválidos", res.SizeBytes, res.SHA256)
	}

	// Verificar integridade do tar.gz gerado
	f, err := os.Open(res.BackupFile)
	if err != nil {
		t.Fatalf("falha ao abrir arquivo de backup gerado: %v", err)
	}
	defer f.Close()

	gzReader, err := gzip.NewReader(f)
	if err != nil {
		t.Fatalf("arquivo de backup não é um gzip válido: %v", err)
	}
	defer gzReader.Close()

	tarReader := tar.NewReader(gzReader)
	foundManifest := false
	foundStack := false

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("erro ao ler arquivo tar: %v", err)
		}
		if header.Name == "manifest.json" {
			foundManifest = true
		}
		if header.Name == "stack.yaml" {
			foundStack = true
		}
	}

	if !foundManifest || !foundStack {
		t.Errorf("Backup bundle não contém arquivos obrigatórios (manifest: %v, stack: %v)", foundManifest, foundStack)
	}
}

func TestExecuteApplicationTransferWithSentinelNotification(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "mno-fleet-test-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	storePath := filepath.Join(tempDir, "fleet.json")
	store, _ := loadFleetInventory(storePath)

	webhookReceived := false
	var mockServer *httptest.Server
	mockServer = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/api/fleet/worker/structure") {
			writeJSON(w, http.StatusOK, FleetNodeStructure{
				NodeID:        "node-worker-remote",
				Name:          "Worker Hetzner",
				Mode:          FleetModeWorker,
				Architecture:  "amd64",
				SetupVersion:  "7.46.0",
				MemoryTotalMB: 4096,
				MemoryFreeMB:  2048,
				DiskTotalGB:   80,
				DiskFreeGB:    40,
				SwarmActive:   true,
				TunnelHealthy: true,
			})
			return
		}
		webhookReceived = true
		w.WriteHeader(http.StatusOK)
	}))
	defer mockServer.Close()

	destWorker := FleetNode{
		ID:            "node-worker-remote",
		Name:          "Worker Hetzner",
		Endpoint:      mockServer.URL,
		Mode:          FleetModeWorker,
		Status:        "online",
		Role:          "worker",
		Architecture:  "amd64",
		MemoryTotalMB: 4096,
		MemoryUsedMB:  1024,
		Token:         "token-12345678",
	}
	_ = store.AddNode(destWorker)

	app := &webApp{
		fleetStore: store,
		httpClient: mockServer.Client(),
		sentinelConfig: &SentinelConfig{
			Enabled:    true,
			WebhookURL: mockServer.URL + "/webhook",
		},
	}

	transferReq := FleetTransferExecutionRequest{
		AppName:            "n8n",
		OriginNodeID:       "local",
		DestNodeID:         "node-worker-remote",
		Mode:               "transfer",
		UpdateDNS:          true,
		StopOriginStack:    true,
		SafetyFreezeSuffix: "frozen_test_2026",
		NotifySentinel:     true,
	}

	res, err := app.ExecuteApplicationTransfer(context.Background(), transferReq)
	if err != nil {
		t.Fatalf("ExecuteApplicationTransfer falhou: %v", err)
	}

	if !res.Success {
		t.Fatalf("Transferência retornou Success=false: %s", res.Error)
	}

	if !res.DNSUpdated {
		t.Errorf("DNSUpdated deveria ser true")
	}

	if !res.OriginStackStopped {
		t.Errorf("OriginStackStopped deveria ser true em modo transfer")
	}

	if len(res.FrozenVolumes) == 0 {
		t.Errorf("Deveria haver volumes congelados registrados")
	}

	if !strings.Contains(res.FrozenVolumes[0], "frozen_test_2026") {
		t.Errorf("Sufixo de congelamento esperado não encontrado nos volumes: %v", res.FrozenVolumes)
	}

	if !res.NotificationDispatched {
		t.Errorf("NotificationDispatched deveria ser true")
	}

	time.Sleep(50 * time.Millisecond)
	if !webhookReceived {
		t.Errorf("Webhook do Sentinel (n8n) não recebeu o payload da migração")
	}
}

func TestDetectDatabaseDependencies_Postgres(t *testing.T) {
	yaml := `version: '3.8'
services:
  typebot:
    image: typebot/builder:latest
    environment:
      - DATABASE_URL=postgresql://postgres:pass@postgres:5432/typebot_db
      - POSTGRES_DB=typebot_db
`
	dbType, dbName := detectDatabaseDependencies(yaml, "typebot")
	if dbType != "postgres" {
		t.Errorf("dbType esperado 'postgres', recebido: %s", dbType)
	}
	if dbName != "typebot_db" {
		t.Errorf("dbName esperado 'typebot_db', recebido: %s", dbName)
	}
}

func TestDetectDatabaseDependencies_MySQL84(t *testing.T) {
	yaml := `version: '3.7'
services:
  mautic_web:
    image: mautic-mno:7.1.2
    environment:
      - MAUTIC_DB_NAME=mautic8c155a0
      - MAUTIC_DB_HOST=mysql84
      - MAUTIC_DB_PORT=3306
      - MAUTIC_DB_USER=root
      - MAUTIC_DB_PASSWORD=secret
`
	dbType, dbName := detectDatabaseDependencies(yaml, "mautic8c155a0")
	if dbType != "mysql84" {
		t.Errorf("dbType esperado 'mysql84', recebido: %s", dbType)
	}
	if dbName != "mautic8c155a0" {
		t.Errorf("dbName esperado 'mautic8c155a0', recebido: %s", dbName)
	}
}

func TestFilterAppSpecificVolumes(t *testing.T) {
	rawVolumes := []string{
		"mautic8c155a0-config",
		"mautic8c155a0-media",
		"postgres_data",
		"mysql84_data",
		"portainer_data",
		"traefik_data",
		"mautic8c155a0-logs",
	}

	filtered := filterAppSpecificVolumes(rawVolumes, "mautic8c155a0")
	if len(filtered) != 3 {
		t.Fatalf("Esperado 3 volumes exclusivos da app, recebido: %d (%v)", len(filtered), filtered)
	}

	for _, v := range filtered {
		if strings.Contains(v, "postgres") || strings.Contains(v, "mysql84") || strings.Contains(v, "portainer") || strings.Contains(v, "traefik") {
			t.Errorf("Volume de infraestrutura vazou no filtro: %s", v)
		}
	}
}

func TestResolveLiveStackYAML_PortainerAndRoot(t *testing.T) {
	tmpDir := t.TempDir()
	portainerDir := filepath.Join(tmpDir, "compose", "1")
	if err := os.MkdirAll(portainerDir, 0755); err != nil {
		t.Fatal(err)
	}
	rootDir := filepath.Join(tmpDir, "root")
	if err := os.MkdirAll(rootDir, 0755); err != nil {
		t.Fatal(err)
	}

	portainerCompose := `version: '3.7'
services:
  myapp:
    image: myapp:v2
`
	_ = os.WriteFile(filepath.Join(portainerDir, "docker-compose.yml"), []byte(portainerCompose), 0644)

	// Resolver a partir do Portainer
	content, source, err := resolveLiveStackYAML("myapp", filepath.Join(tmpDir, "compose"), rootDir)
	if err != nil {
		t.Fatalf("Falha ao resolver live stack do Portainer: %v", err)
	}
	if source != "portainer_live" {
		t.Errorf("Fonte esperada 'portainer_live', recebido: %s", source)
	}
	if !strings.Contains(content, "myapp:v2") {
		t.Errorf("Conteúdo não bate com o compose do Portainer: %s", content)
	}

	// Verificar se auto-sincronizou em rootDir
	syncedFile := filepath.Join(rootDir, "myapp.yaml")
	if data, err := os.ReadFile(syncedFile); err != nil || !strings.Contains(string(data), "myapp:v2") {
		t.Errorf("Auto-sincronização em rootDir falhou")
	}
}

