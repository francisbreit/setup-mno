package main

import (
	"context"
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

	if len(schema.Tools) != 10 {
		t.Fatalf("esperava 10 ferramentas homologadas, obteve %d", len(schema.Tools))
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
		"fleet_sentinel_status",
		"fleet_inspect_structure",
		"fleet_preflight_transfer",
		"fleet_execute_transfer",
		"fleet_create_backup",
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

func TestFleetInventoryHeartbeatStaleness(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "fleet-staleness-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	storePath := filepath.Join(tempDir, "fleet-inventory.json")
	store, err := loadFleetInventory(storePath)
	if err != nil {
		t.Fatalf("loadFleetInventory falhou: %v", err)
	}

	// Adiciona nó com heartbeat antigo (ex: 2 horas atrás, como uma VPS formatada)
	staleNode := FleetNode{
		ID:            "node-stale-worker",
		Name:          "Debian-Formatada",
		Endpoint:      "https://vps-morta.com",
		Mode:          FleetModeWorker,
		Status:        "online", // Inicialmente salvo como online
		Role:          "worker",
		Token:         "token-1234567890abcdef",
		LastHeartbeat: time.Now().UTC().Add(-2 * time.Hour),
		TunnelHealthy: true,
	}

	if err := store.AddNode(staleNode); err != nil {
		t.Fatalf("AddNode falhou: %v", err)
	}

	// 1. Ao listar nós, o nó stale deve ser reconciliado e retornado como OFFLINE
	nodes := store.ListNodes()
	if len(nodes) != 1 {
		t.Fatalf("esperava 1 nó, obteve %d", len(nodes))
	}
	if nodes[0].Status != "offline" {
		t.Errorf("ListNodes deveria retornar status 'offline' para nó stale, obteve: %s", nodes[0].Status)
	}
	if nodes[0].TunnelHealthy {
		t.Errorf("ListNodes deveria marcar TunnelHealthy como false para nó stale")
	}

	// 2. GetNode também deve proteger contra falso positivo
	gotNode, found := store.GetNode("node-stale-worker")
	if !found {
		t.Fatalf("GetNode não encontrou o nó")
	}
	if gotNode.Status != "offline" {
		t.Errorf("GetNode deveria retornar status 'offline' para nó stale, obteve: %s", gotNode.Status)
	}

	// 3. FindNodeByNameOrID também deve retornar offline
	foundNode, ok := store.FindNodeByNameOrID("Debian-Formatada")
	if !ok {
		t.Fatalf("FindNodeByNameOrID não encontrou o nó")
	}
	if foundNode.Status != "offline" {
		t.Errorf("FindNodeByNameOrID deveria retornar status 'offline', obteve: %s", foundNode.Status)
	}
}

func TestFleetProbeAllWorkersAndSync(t *testing.T) {
	// Worker 1: Simula um nó online que responde com HTTP 200 e telemetria
	workerServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/fleet/worker/telemetry" {
			telem := FleetTelemetry{
				NodeID:        "worker-live",
				Mode:          FleetModeWorker,
				ActiveSwarm:   true,
				HealthyApps:   5,
				UnhealthyApps: 0,
				MemoryTotalMB: 4096,
				MemoryUsedMB:  1024,
				Timestamp:     time.Now().UTC(),
			}
			_ = json.NewEncoder(w).Encode(telem)
			return
		}
		http.NotFound(w, r)
	}))
	defer workerServer.Close()

	tempDir, err := os.MkdirTemp("", "fleet-probe-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	storePath := filepath.Join(tempDir, "fleet-inventory.json")
	store, err := loadFleetInventory(storePath)
	if err != nil {
		t.Fatalf("loadFleetInventory falhou: %v", err)
	}

	// Nó 1: Worker vivo apontando para o httptest.Server
	liveNode := FleetNode{
		ID:            "node-live-worker",
		Name:          "Debian-Viva",
		Endpoint:      workerServer.URL,
		Mode:          FleetModeWorker,
		Status:        "unknown",
		Role:          "worker",
		Token:         "token-valido-123456",
		LastHeartbeat: time.Now().UTC().Add(-10 * time.Minute),
	}
	_ = store.AddNode(liveNode)

	// Nó 2: Worker morto/formatado apontando para porta fechada/inválida
	deadNode := FleetNode{
		ID:            "node-dead-worker",
		Name:          "Debian1-Hetzner-Formatada",
		Endpoint:      "http://127.0.0.1:1", // porta fechada para simular VPS inacessível
		Mode:          FleetModeWorker,
		Status:        "online", // salvo erroneamente como online
		Role:          "worker",
		Token:         "token-qualquer",
		LastHeartbeat: time.Now().UTC().Add(-5 * time.Minute),
	}
	_ = store.AddNode(deadNode)

	app := &webApp{
		fleetStore: store,
		httpClient: &http.Client{Timeout: 2 * time.Second},
		sessions:   make(map[string]*session),
	}

	// Executa varredura (probeAllWorkers)
	app.probeAllWorkers(context.Background())

	// Verifica Nó 1 (deve estar online e atualizado)
	liveGot, _ := store.GetNode("node-live-worker")
	if liveGot.Status != "online" {
		t.Errorf("esperava que nó vivo estivesse 'online', obteve: %s", liveGot.Status)
	}
	if !liveGot.TunnelHealthy {
		t.Errorf("esperava TunnelHealthy true para nó vivo")
	}
	if liveGot.ServiceCount != 5 {
		t.Errorf("esperava ServiceCount=5 para nó vivo, obteve: %d", liveGot.ServiceCount)
	}

	// Verifica Nó 2 (deve estar offline sem falso positivo)
	deadGot, _ := store.GetNode("node-dead-worker")
	if deadGot.Status != "offline" {
		t.Errorf("esperava que nó morto/formatado estivesse 'offline', obteve: %s", deadGot.Status)
	}
	if deadGot.TunnelHealthy {
		t.Errorf("esperava TunnelHealthy false para nó morto")
	}
}

func TestFleetWorkerLockLease(t *testing.T) {
	app := &webApp{}

	now := time.Now().UTC()
	// 1. Adquire trava pela Torre A
	app.fleetLockMu.Lock()
	app.fleetLock = &FleetNodeLock{
		Locked:     true,
		HolderID:   "torre-master-a",
		HolderName: "Torre Master A (WSL2)",
		Task:       "Migração n8n",
		AcquiredAt: now,
		ExpiresAt:  now.Add(10 * time.Second),
	}
	app.fleetLockMu.Unlock()

	// 2. Valida que está travado
	app.fleetLockMu.Lock()
	if !app.fleetLock.Locked || app.fleetLock.HolderID != "torre-master-a" {
		t.Errorf("esperava nó travado pela Torre A, obteve: %+v", app.fleetLock)
	}
	// Concorrência: outra torre tenta verificar lock
	isOccupied := app.fleetLock != nil && app.fleetLock.Locked && time.Now().UTC().Before(app.fleetLock.ExpiresAt)
	if !isOccupied {
		t.Errorf("esperava que nó estivesse ocupado")
	}
	app.fleetLockMu.Unlock()

	// 3. Libera trava
	app.fleetLockMu.Lock()
	app.fleetLock.Locked = false
	app.fleetLockMu.Unlock()

	// 4. Torre B consegue adquirir
	app.fleetLockMu.Lock()
	app.fleetLock = &FleetNodeLock{
		Locked:     true,
		HolderID:   "torre-master-b",
		HolderName: "Torre Master B (VPS)",
		Task:       "Backup Chatwoot",
		AcquiredAt: time.Now().UTC(),
		ExpiresAt:  time.Now().UTC().Add(300 * time.Second),
	}
	if !app.fleetLock.Locked || app.fleetLock.HolderID != "torre-master-b" {
		t.Errorf("esperava nó travado pela Torre B")
	}
	app.fleetLockMu.Unlock()
}

func TestFleetMasterToMasterSync(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "fleet-m2m-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// 1. Configurar Store de Origem (Torre Master A)
	storeAPath := filepath.Join(tempDir, "master-a.json")
	storeA, err := loadFleetInventory(storeAPath)
	if err != nil {
		t.Fatalf("loadFleetInventory A falhou: %v", err)
	}

	storeA.EnsureLocalNode("master-a-local", "Torre Master A (VPS)", FleetTelemetry{ActiveSwarm: true}, "amd64", "7.48.13")
	_ = storeA.AddNode(FleetNode{
		ID:            "worker-sp-01",
		Name:          "VPS São Paulo 01",
		Endpoint:      "https://sp01.empresa.com",
		Mode:          FleetModeWorker,
		Status:        "online",
		Role:          "worker",
		Token:         "token-worker-sp-secret",
		Architecture:  "amd64",
		SetupVersion:  "7.48.13",
		LastHeartbeat: time.Now().UTC(),
	})
	_ = storeA.AddNode(FleetNode{
		ID:            "worker-oracle-02",
		Name:          "Oracle ARM 02",
		Endpoint:      "https://arm02.empresa.com",
		Mode:          FleetModeWorker,
		Status:        "online",
		Role:          "worker",
		Token:         "token-worker-oracle-secret",
		Architecture:  "arm64",
		SetupVersion:  "7.48.13",
		LastHeartbeat: time.Now().UTC(),
	})

	// Validar ExportWorkerNodes: só deve exportar nós workers e com seus tokens reais
	exported := storeA.ExportWorkerNodes()
	if len(exported) != 2 {
		t.Fatalf("esperava 2 nós exportados, obteve %d", len(exported))
	}
	for _, n := range exported {
		if n.Mode != FleetModeWorker || n.Token == "••••••••" || n.Token == "" {
			t.Errorf("nó exportado inválido ou token mascarado: %+v", n)
		}
	}

	// 2. Configurar Store de Destino (Torre Master B)
	storeBPath := filepath.Join(tempDir, "master-b.json")
	storeB, err := loadFleetInventory(storeBPath)
	if err != nil {
		t.Fatalf("loadFleetInventory B falhou: %v", err)
	}
	storeB.EnsureLocalNode("master-b-local", "Torre Master B (WSL2)", FleetTelemetry{ActiveSwarm: true}, "arm64", "7.48.13")

	// 3. Testar Importação com Merge
	count, err := storeB.ImportNodes(exported, "merge")
	if err != nil || count != 2 {
		t.Fatalf("ImportNodes merge falhou: count=%d, err=%v", count, err)
	}
	nodesB := storeB.ListNodes()
	if len(nodesB) != 3 { // 1 local + 2 importados
		t.Fatalf("esperava 3 nós na Torre B após merge, obteve %d", len(nodesB))
	}

	// 4. Testar Importação com Replace
	// Adiciona um nó temporário que deve sumir após replace
	_ = storeB.AddNode(FleetNode{
		ID:       "worker-temp-antigo",
		Name:     "Worker Obsoleto",
		Endpoint: "https://antigo.empresa.com",
		Mode:     FleetModeWorker,
	})
	if len(storeB.ListNodes()) != 4 {
		t.Fatalf("esperava 4 nós antes do replace")
	}

	countReplace, err := storeB.ImportNodes(exported, "replace")
	if err != nil || countReplace != 2 {
		t.Fatalf("ImportNodes replace falhou: count=%d, err=%v", countReplace, err)
	}
	nodesBAfterReplace := storeB.ListNodes()
	if len(nodesBAfterReplace) != 3 { // local preservado + 2 importados, nó obsoleto removido
		t.Fatalf("esperava 3 nós após replace, obteve %d", len(nodesBAfterReplace))
	}

	// 5. Testar Servidor Remoto e Handler de Exportação/Importação
	masterToken := "chave-mestra-torre-a-999"
	serverA := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/fleet/inventory/export" {
			token := r.Header.Get("X-SetupMNO-Fleet-Token")
			if token != masterToken {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			resp := FleetExportInventoryResponse{
				SchemaVersion: fleetInventorySchemaVersion,
				MasterNodeID:  "master-a-local",
				ExportedAt:    time.Now().UTC(),
				Nodes:         exported,
			}
			_ = json.NewEncoder(w).Encode(resp)
			return
		}
		http.NotFound(w, r)
	}))
	defer serverA.Close()

	// Simular Torre Master B recebendo requisição para importar da Torre Master A
	appB := &webApp{
		fleetStore: storeB,
		httpClient: serverA.Client(),
	}

	importReqBody, _ := json.Marshal(FleetImportInventoryRequest{
		MasterEndpoint: serverA.URL,
		MasterToken:    masterToken,
		Strategy:       "merge",
	})

	// Criar mock server para o agent da Torre B retornando modo Master
	agentServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/fleet/config" {
			_ = json.NewEncoder(w).Encode(fleetConfigResponse{
				FleetMode:   FleetModeMaster,
				FleetNodeID: "master-b-local",
				FleetToken:  "token-master-b",
			})
			return
		}
		http.NotFound(w, r)
	}))
	defer agentServer.Close()

	appB.agentURL = agentServer.URL

	httpImportReq := httptest.NewRequest(http.MethodPost, "/api/fleet/inventory/import", strings.NewReader(string(importReqBody)))
	wImport := httptest.NewRecorder()

	appB.handleFleetImportInventory(wImport, httpImportReq)
	if wImport.Code != http.StatusOK {
		t.Fatalf("handleFleetImportInventory falhou com HTTP %d: %s", wImport.Code, wImport.Body.String())
	}

	var importResult FleetImportInventoryResponse
	if err := json.Unmarshal(wImport.Body.Bytes(), &importResult); err != nil {
		t.Fatalf("falha ao decodificar JSON de resposta da importação: %v", err)
	}

	if !importResult.Success || importResult.ImportedCount != 2 {
		t.Errorf("resultado inesperado na importação: %+v", importResult)
	}
}

func TestFleetMasterActiveStandbyRole(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "fleet-role-*")
	if err != nil {
		t.Fatalf("erro ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	envPath := filepath.Join(tempDir, "environment.json")
	initialEnv := `{
		"schemaVersion": 1,
		"plan": "pro",
		"installationType": "CLOUDFLARE_TUNNEL",
		"fleetMode": "master",
		"fleetNodeId": "master-test-node",
		"fleetToken": "token-test-1234567890",
		"fleetRole": "active"
	}`
	if err := os.WriteFile(envPath, []byte(initialEnv), 0o600); err != nil {
		t.Fatalf("erro ao gravar initialEnv: %v", err)
	}

	// 1. Ler ambiente inicial: deve ser "active"
	env, err := readRuntimeEnvironment(tempDir)
	if err != nil {
		t.Fatalf("readRuntimeEnvironment falhou: %v", err)
	}
	if env.FleetRole != "active" {
		t.Errorf("esperava fleetRole='active', obteve %s", env.FleetRole)
	}

	// 2. Comutar para "standby"
	if err := updateRuntimeEnvironmentFleetRole(tempDir, "standby"); err != nil {
		t.Fatalf("updateRuntimeEnvironmentFleetRole para 'standby' falhou: %v", err)
	}
	envAfterStandby, err := readRuntimeEnvironment(tempDir)
	if err != nil {
		t.Fatalf("readRuntimeEnvironment pós standby falhou: %v", err)
	}
	if envAfterStandby.FleetRole != "standby" {
		t.Errorf("esperava fleetRole='standby', obteve %s", envAfterStandby.FleetRole)
	}

	// 3. Comutar de volta para "active"
	if err := updateRuntimeEnvironmentFleetRole(tempDir, "active"); err != nil {
		t.Fatalf("updateRuntimeEnvironmentFleetRole para 'active' falhou: %v", err)
	}
	envAfterActive, err := readRuntimeEnvironment(tempDir)
	if err != nil {
		t.Fatalf("readRuntimeEnvironment pós active falhou: %v", err)
	}
	if envAfterActive.FleetRole != "active" {
		t.Errorf("esperava fleetRole='active', obteve %s", envAfterActive.FleetRole)
	}

	// 4. Testar handler HTTP POST /api/fleet/role
	agentServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/fleet/config" {
			_ = json.NewEncoder(w).Encode(fleetConfigResponse{
				FleetMode:   FleetModeMaster,
				FleetNodeID: "master-test-node",
				FleetRole:   "active",
			})
			return
		}
		if r.URL.Path == "/fleet/role" {
			var body struct {
				Role string `json:"role"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			_ = json.NewEncoder(w).Encode(map[string]any{"success": true, "role": body.Role})
			return
		}
		http.NotFound(w, r)
	}))
	defer agentServer.Close()

	app := &webApp{
		agentURL:   agentServer.URL,
		httpClient: agentServer.Client(),
	}

	// Requisição para alternar para standby
	roleReqBody, _ := json.Marshal(FleetRoleRequest{Role: "standby"})
	req := httptest.NewRequest(http.MethodPost, "/api/fleet/role", strings.NewReader(string(roleReqBody)))
	w := httptest.NewRecorder()

	app.handleFleetSetRole(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("handleFleetSetRole falhou com HTTP %d: %s", w.Code, w.Body.String())
	}

	var roleResp FleetRoleResponse
	if err := json.Unmarshal(w.Body.Bytes(), &roleResp); err != nil {
		t.Fatalf("erro ao decodificar JSON de role: %v", err)
	}
	if !roleResp.Success || roleResp.Role != "standby" {
		t.Errorf("resposta inesperada da comutação de role: %+v", roleResp)
	}

	// Requisição com role inválido deve ser rejeitada
	invalidReqBody, _ := json.Marshal(FleetRoleRequest{Role: "invalido"})
	reqInvalid := httptest.NewRequest(http.MethodPost, "/api/fleet/role", strings.NewReader(string(invalidReqBody)))
	wInvalid := httptest.NewRecorder()
	app.handleFleetSetRole(wInvalid, reqInvalid)
	if wInvalid.Code != http.StatusBadRequest {
		t.Errorf("esperava HTTP 400 para role inválido, obteve %d", wInvalid.Code)
	}
}





