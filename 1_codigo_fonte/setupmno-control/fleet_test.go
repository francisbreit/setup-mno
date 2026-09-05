package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestValidateFleetEndpoint(t *testing.T) {
	validCases := []struct {
		input    string
		expected string
	}{
		{"https://vps1.manualnegocioonline.com.br", "https://vps1.manualnegocioonline.com.br"},
		{"https://vps2.dominio.com:8443", "https://vps2.dominio.com:8443"},
		{"http://localhost:8080", "http://localhost:8080"},
		{"http://127.0.0.1:9090", "http://127.0.0.1:9090"},
		{"https://node-sp-01.internal.org/", "https://node-sp-01.internal.org"},
	}

	for _, tc := range validCases {
		got, err := validateFleetEndpoint(tc.input)
		if err != nil {
			t.Errorf("validateFleetEndpoint(%q) retornou erro inesperado: %v", tc.input, err)
		}
		if got != tc.expected {
			t.Errorf("validateFleetEndpoint(%q) = %q; esperado %q", tc.input, got, tc.expected)
		}
	}

	invalidCases := []string{
		"",
		"   ",
		"http://remoto-sem-ssl.com",       // HTTP remoto proibido para Zero-Trust
		"ftp://servidor.com",             // esquema perigoso
		"file:///etc/passwd",             // leitura local proibida
		"gopher://malicioso",             // protocolo legado inseguro
		"javascript:alert(1)",           // XSS injection
		"https://user:pass@vps.com",      // credencial embutida proibida
		"https://vps.com/path/extra",     // paths adicionais proibidos
		"https://vps.com?token=123",      // query string proibida
		"https://vps.com#frag",           // fragmento proibido
	}

	for _, input := range invalidCases {
		if _, err := validateFleetEndpoint(input); err == nil {
			t.Errorf("validateFleetEndpoint(%q) deveria falhar por segurança, mas passou", input)
		}
	}
}

func TestFleetInventoryStoreCRUD(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "fleet-test-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	storePath := filepath.Join(tempDir, "fleet-inventory.json")
	store, err := loadFleetInventory(storePath)
	if err != nil {
		t.Fatalf("loadFleetInventory falhou: %v", err)
	}

	if len(store.ListNodes()) != 0 {
		t.Fatalf("inventário inicial deveria estar vazio")
	}

	node1 := FleetNode{
		ID:            "node-sp-01",
		Name:          "VPS Produção SP",
		Endpoint:      "https://sp01.empresa.com",
		Mode:          FleetModeWorker,
		Status:        "online",
		Role:          "worker",
		Token:         "token-secreto-super-forte-12345678",
		LastHeartbeat: time.Now().UTC(),
	}

	if err := store.AddNode(node1); err != nil {
		t.Fatalf("AddNode falhou: %v", err)
	}

	// Tentar adicionar nó com ID duplicado deve falhar
	if err := store.AddNode(node1); err == nil {
		t.Fatalf("AddNode com ID duplicado deveria falhar")
	}

	// Tentar adicionar nó com Endpoint duplicado deve falhar
	dupEndpointNode := FleetNode{
		ID:       "node-sp-02",
		Name:     "VPS Reserva SP",
		Endpoint: "https://sp01.empresa.com",
		Mode:     FleetModeWorker,
	}
	if err := store.AddNode(dupEndpointNode); err == nil {
		t.Fatalf("AddNode com Endpoint duplicado deveria falhar")
	}

	// Salvar e recarregar do disco para verificar atomicidade
	if err := store.Save(); err != nil {
		t.Fatalf("Save falhou: %v", err)
	}

	reloaded, err := loadFleetInventory(storePath)
	if err != nil {
		t.Fatalf("recarga do inventário falhou: %v", err)
	}

	nodes := reloaded.ListNodes()
	if len(nodes) != 1 {
		t.Fatalf("esperava 1 nó após recarga, obteve %d", len(nodes))
	}
	if nodes[0].Token != "••••••••" {
		t.Errorf("ListNodes deveria mascarar o token, obteve: %s", nodes[0].Token)
	}

	// Obter nó diretamente deve retornar o token real
	gotNode, found := reloaded.GetNode("node-sp-01")
	if !found {
		t.Fatalf("GetNode não encontrou o nó")
	}
	if gotNode.Token != "token-secreto-super-forte-12345678" {
		t.Errorf("GetNode deveria retornar o token real internamente")
	}

	// Remover nó
	removed, err := reloaded.RemoveNode("node-sp-01")
	if err != nil || !removed {
		t.Fatalf("RemoveNode falhou")
	}
	if len(reloaded.ListNodes()) != 0 {
		t.Fatalf("esperava 0 nós após remoção")
	}
}

func TestEnsureLocalNode(t *testing.T) {
	store, _ := loadFleetInventory("")

	telem := FleetTelemetry{
		NodeID:        "node-master-local",
		Mode:          FleetModeMaster,
		UptimeSeconds: 3600,
		LoadAverage1m: 0.25,
		MemoryUsedMB:  1024,
		MemoryTotalMB: 4096,
		ActiveSwarm:   true,
		HealthyApps:   5,
		UnhealthyApps: 0,
		Timestamp:     time.Now().UTC(),
	}

	store.EnsureLocalNode("node-master-local", "Torre Master", telem, "arm64", "7.44.0")

	nodes := store.ListNodes()
	if len(nodes) != 1 {
		t.Fatalf("esperava 1 nó após EnsureLocalNode, obteve %d", len(nodes))
	}
	if nodes[0].ID != "node-master-local" || nodes[0].Status != "online" || nodes[0].Mode != FleetModeMaster {
		t.Errorf("dados do nó local incorretos: %+v", nodes[0])
	}

	// Chamar novamente deve apenas atualizar
	telem.HealthyApps = 6
	store.EnsureLocalNode("node-master-local", "Torre Master", telem, "arm64", "7.44.0")
	nodes = store.ListNodes()
	if len(nodes) != 1 {
		t.Fatalf("não deveria duplicar o nó local")
	}
	if nodes[0].ServiceCount != 6 {
		t.Errorf("ServiceCount não foi atualizado: %d", nodes[0].ServiceCount)
	}
}

func TestAuthenticateFleetWorkerRequest(t *testing.T) {
	app := &webApp{}
	expectedToken := "chave-mestra-frota-abc-123"

	// 1. Modo disabled deve recusar sempre (fail-closed)
	req1 := httptest.NewRequest(http.MethodGet, "/api/fleet/worker/telemetry", nil)
	req1.Header.Set("X-SetupMNO-Fleet-Token", expectedToken)
	if app.authenticateFleetWorkerRequest(req1, expectedToken, FleetModeDisabled) {
		t.Errorf("modo disabled deveria recusar a requisição")
	}

	// 2. Token vazio deve recusar sempre
	if app.authenticateFleetWorkerRequest(req1, "", FleetModeWorker) {
		t.Errorf("token esperado vazio deveria recusar a requisição")
	}

	// 3. Header X-SetupMNO-Fleet-Token correto
	req2 := httptest.NewRequest(http.MethodGet, "/api/fleet/worker/telemetry", nil)
	req2.Header.Set("X-SetupMNO-Fleet-Token", expectedToken)
	if !app.authenticateFleetWorkerRequest(req2, expectedToken, FleetModeWorker) {
		t.Errorf("deveria aprovar token válido via X-SetupMNO-Fleet-Token")
	}

	// 4. Header Authorization Bearer correto
	req3 := httptest.NewRequest(http.MethodGet, "/api/fleet/worker/telemetry", nil)
	req3.Header.Set("Authorization", "Bearer "+expectedToken)
	if !app.authenticateFleetWorkerRequest(req3, expectedToken, FleetModeWorker) {
		t.Errorf("deveria aprovar token válido via Authorization Bearer")
	}

	// 5. Token incorreto
	req4 := httptest.NewRequest(http.MethodGet, "/api/fleet/worker/telemetry", nil)
	req4.Header.Set("X-SetupMNO-Fleet-Token", "token-errado")
	if app.authenticateFleetWorkerRequest(req4, expectedToken, FleetModeWorker) {
		t.Errorf("deveria rejeitar token incorreto")
	}
}
