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

func TestFindNodeByNameOrID(t *testing.T) {
	store, _ := loadFleetInventory("")
	node := FleetNode{
		ID:       "node-hetzner-01",
		Name:     "Debian1-Hetzner",
		Endpoint: "https://setup4747985365.manualnegocioonline.com.br",
		Mode:     FleetModeWorker,
		Status:   "online",
		Role:     "worker",
		Token:    "token-hetzner-123456",
	}
	if err := store.AddNode(node); err != nil {
		t.Fatalf("AddNode falhou: %v", err)
	}

	found, ok := store.FindNodeByNameOrID("Debian1-Hetzner")
	if !ok || found.ID != "node-hetzner-01" {
		t.Errorf("FindNodeByNameOrID por nome exato falhou")
	}

	found, ok = store.FindNodeByNameOrID("hetzner")
	if !ok || found.ID != "node-hetzner-01" {
		t.Errorf("FindNodeByNameOrID por substring 'hetzner' falhou")
	}

	found, ok = store.FindNodeByNameOrID("node-hetzner")
	if !ok || found.Name != "Debian1-Hetzner" {
		t.Errorf("FindNodeByNameOrID por prefixo de ID falhou")
	}

	found, ok = store.FindNodeByNameOrID("setup4747985365")
	if !ok || found.ID != "node-hetzner-01" {
		t.Errorf("FindNodeByNameOrID por endpoint falhou")
	}

	_, ok = store.FindNodeByNameOrID("nao-existe")
	if ok {
		t.Errorf("FindNodeByNameOrID deveria retornar false para nó inexistente")
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

func TestFleetToolsSchema(t *testing.T) {
	app := &webApp{}
	req := httptest.NewRequest(http.MethodGet, "/api/fleet/tools/schema.json", nil)
	w := httptest.NewRecorder()

	app.handleFleetToolsSchema(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("esperava HTTP 200, obteve %d", w.Code)
	}

	var schema FleetToolsSchemaResponse
	if err := json.Unmarshal(w.Body.Bytes(), &schema); err != nil {
		t.Fatalf("falha ao decodificar schema JSON: %v", err)
	}

	if schema.SchemaVersion != "1.0.0" || schema.Provider != "setup-mno-fleet" {
		t.Errorf("metadados do schema incorretos: %+v", schema)
	}

	if len(schema.Tools) != 5 {
		t.Fatalf("esperava 5 ferramentas homologadas, obteve %d", len(schema.Tools))
	}

	names := make(map[string]bool)
	for _, tool := range schema.Tools {
		if tool.Type != "function" || tool.Function.Name == "" {
			t.Errorf("ferramenta com formato inválido: %+v", tool)
		}
		names[tool.Function.Name] = true
	}

	expectedTools := []string{
		"fleet_get_status",
		"fleet_list_nodes",
		"fleet_diagnose_node",
		"fleet_consult_dispatch",
		"fleet_ping_node",
	}

	for _, name := range expectedTools {
		if !names[name] {
			t.Errorf("ferramenta esperada '%s' ausente no schema", name)
		}
	}
}

func TestFleetToolsExecuteRejectsUnauthorized(t *testing.T) {
	app := &webApp{}
	payload := `{"tool":"fleet_get_status"}`
	req := httptest.NewRequest(http.MethodPost, "/api/fleet/tools/execute", strings.NewReader(payload))
	w := httptest.NewRecorder()

	app.handleFleetToolsExecute(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("esperava HTTP 401 sem autenticação, obteve %d", w.Code)
	}
}

func TestFleetToolsExecuteAuthorizedListNodes(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "fleet-tools-test-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	storePath := filepath.Join(tempDir, "fleet-inventory.json")
	store, err := loadFleetInventory(storePath)
	if err != nil {
		t.Fatalf("loadFleetInventory falhou: %v", err)
	}

	app := &webApp{
		fleetStore: store,
		sessions:   make(map[string]*session),
	}

	cookieVal := strings.Repeat("c", 32)
	app.sessions[cookieVal] = &session{
		Expires:   time.Now().Add(1 * time.Hour),
		IdleUntil: time.Now().Add(1 * time.Hour),
		User:      "admin",
	}

	payload := `{"tool":"fleet_list_nodes"}`
	req := httptest.NewRequest(http.MethodPost, "/api/fleet/tools/execute", strings.NewReader(payload))
	req.AddCookie(&http.Cookie{
		Name:  sessionCookie,
		Value: cookieVal,
	})
	w := httptest.NewRecorder()

	app.handleFleetToolsExecute(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("esperava HTTP 200 para sessão autorizada, obteve %d (%s)", w.Code, w.Body.String())
	}

	var resp FleetToolExecuteResponse
	if err := decodeStrictJSON(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("resposta JSON inválida: %v", err)
	}

	if !resp.Success || resp.Tool != "fleet_list_nodes" {
		t.Errorf("resposta inesperada: %+v", resp)
	}
}


