package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// fetchFleetConfig consulta o agent sobre o modo e credenciais do Fleet Hub.
func (a *webApp) fetchFleetConfig(ctx context.Context) (fleetConfigResponse, error) {
	var cfg fleetConfigResponse
	if err := a.agentRequest(ctx, "/fleet/config", &cfg); err != nil {
		return fleetConfigResponse{FleetMode: FleetModeDisabled}, err
	}
	return cfg, nil
}

// fetchLocalTelemetry consulta o agent sobre a telemetria do nó local.
func (a *webApp) fetchLocalTelemetry(ctx context.Context) (FleetTelemetry, error) {
	var telem FleetTelemetry
	if err := a.agentRequest(ctx, "/fleet/telemetry", &telem); err != nil {
		return FleetTelemetry{
			NodeID:    "local",
			Mode:      FleetModeDisabled,
			Timestamp: time.Now().UTC(),
		}, err
	}
	return telem, nil
}

// probeWorkerNode realiza uma consulta remota segura com timeout para auditar um nó subordinado.
func (a *webApp) probeWorkerNode(ctx context.Context, endpoint, token string) (FleetTelemetry, int64, error) {
	cleanURL, err := validateFleetEndpoint(endpoint)
	if err != nil {
		return FleetTelemetry{}, 0, err
	}

	probeURL := cleanURL + "/api/fleet/worker/telemetry"
	probeCtx, cancel := context.WithTimeout(ctx, fleetProbeTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(probeCtx, http.MethodGet, probeURL, nil)
	if err != nil {
		return FleetTelemetry{}, 0, err
	}

	if token != "" {
		req.Header.Set("X-SetupMNO-Fleet-Token", token)
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("Accept", "application/json")

	start := time.Now()
	resp, err := a.httpClient.Do(req)
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return FleetTelemetry{}, latency, fmt.Errorf("falha de conexão com nó: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return FleetTelemetry{}, latency, fmt.Errorf("nó retornou HTTP %d", resp.StatusCode)
	}

	var telemetry FleetTelemetry
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&telemetry); err != nil {
		return FleetTelemetry{}, latency, fmt.Errorf("resposta de telemetria inválida: %w", err)
	}
	return telemetry, latency, nil
}

// handleFleetStatus retorna o status consolidado do Fleet Hub para a interface e auditorias.
func (a *webApp) handleFleetStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, _ := a.fetchFleetConfig(ctx)
	localTelem, _ := a.fetchLocalTelemetry(ctx)

	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)

	response := FleetStatusResponse{
		Mode:           cfg.FleetMode,
		NodeID:         cfg.FleetNodeID,
		FleetAllowed:   setupState.FleetAllowed,
		FleetToken:     cfg.FleetToken,
		LocalTelemetry: localTelem,
	}

	if cfg.FleetMode == FleetModeDisabled {
		writeJSON(w, http.StatusOK, response)
		return
	}

	if cfg.FleetMode == FleetModeWorker {
		response.IsWorker = true
		response.TotalNodes = 1
		response.OnlineNodes = 1
		writeJSON(w, http.StatusOK, response)
		return
	}

	// Modo Master
	response.IsMaster = true
	if a.fleetStore != nil {
		a.fleetStore.EnsureLocalNode(
			cfg.FleetNodeID,
			"Torre Master (Nó Local)",
			localTelem,
			setupState.Architecture,
			setupState.SetupVersion,
		)
		nodes := a.fleetStore.ListNodes()
		response.TotalNodes = len(nodes)
		for _, n := range nodes {
			switch n.Status {
			case "online":
				response.OnlineNodes++
			case "degraded":
				response.DegradedNodes++
			default:
				response.OfflineNodes++
			}
		}
	}
	writeJSON(w, http.StatusOK, response)
}

// handleFleetNodes lista todos os nós registrados na frota.
func (a *webApp) handleFleetNodes(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, _ := a.fetchFleetConfig(ctx)

	if cfg.FleetMode == FleetModeDisabled {
		writeJSON(w, http.StatusOK, map[string]any{
			"mode":  FleetModeDisabled,
			"nodes": []FleetNode{},
		})
		return
	}

	if cfg.FleetMode == FleetModeWorker {
		localTelem, _ := a.fetchLocalTelemetry(ctx)
		workerNode := FleetNode{
			ID:            cfg.FleetNodeID,
			Name:          "Nó de Frota (Worker Local)",
			Mode:          FleetModeWorker,
			Status:        "online",
			Role:          "worker",
			TunnelHealthy: true,
			LastHeartbeat: time.Now().UTC(),
			Telemetry:     &localTelem,
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"mode":  FleetModeWorker,
			"nodes": []FleetNode{workerNode},
		})
		return
	}

	// Modo Master
	if a.fleetStore == nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"mode":  FleetModeMaster,
			"nodes": []FleetNode{},
		})
		return
	}

	localTelem, _ := a.fetchLocalTelemetry(ctx)
	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)

	a.fleetStore.EnsureLocalNode(
		cfg.FleetNodeID,
		"Torre Master (Nó Local)",
		localTelem,
		setupState.Architecture,
		setupState.SetupVersion,
	)

	nodes := a.fleetStore.ListNodes()
	writeJSON(w, http.StatusOK, map[string]any{
		"mode":  FleetModeMaster,
		"nodes": nodes,
	})
}

// handleFleetAddNode adiciona e pareia um novo Worker na Torre Master.
func (a *webApp) handleFleetAddNode(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)
	if !setupState.FleetAllowed {
		writeError(w, http.StatusForbidden, "gerenciamento da frota exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel")
		return
	}

	cfg, _ := a.fetchFleetConfig(ctx)
	if cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "A adição de nós à frota é permitida apenas quando a VPS opera como Torre Master")
		return
	}

	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	var req FleetAddNodeRequest
	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "corpo da requisição JSON inválido ou campos adicionais não permitidos")
		return
	}

	cleanEndpoint, err := validateFleetEndpoint(req.Endpoint)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	nodeID := strings.TrimSpace(req.ID)
	if nodeID == "" {
		randomBytes := make([]byte, 4)
		_, _ = rand.Read(randomBytes)
		nodeID = "node-worker-" + hex.EncodeToString(randomBytes)
	}

	role := strings.TrimSpace(req.Role)
	if role == "" {
		role = "worker"
	}

	newNode := FleetNode{
		ID:            nodeID,
		Name:          strings.TrimSpace(req.Name),
		Endpoint:      cleanEndpoint,
		Mode:          FleetModeWorker,
		Status:        "unknown",
		Role:          role,
		Tags:          req.Tags,
		Token:         strings.TrimSpace(req.Token),
		TunnelHealthy: true,
		LastHeartbeat: time.Now().UTC(),
	}

	if err := validateFleetNode(newNode); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Probe inicial do novo nó
	telem, _, probeErr := a.probeWorkerNode(ctx, cleanEndpoint, newNode.Token)
	if probeErr == nil {
		newNode.Status = "online"
		newNode.Telemetry = &telem
		newNode.MemoryTotalMB = telem.MemoryTotalMB
		newNode.MemoryUsedMB = telem.MemoryUsedMB
		newNode.ServiceCount = telem.HealthyApps + telem.UnhealthyApps
		if telem.Architecture != "" {
			newNode.Architecture = telem.Architecture
		}
		if telem.SetupVersion != "" {
			newNode.SetupVersion = telem.SetupVersion
		}
	} else {
		newNode.Status = "offline"
	}

	if a.fleetStore == nil {
		writeError(w, http.StatusInternalServerError, "armazém da frota indisponível")
		return
	}

	if err := a.fleetStore.AddNode(newNode); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}

	if err := a.fleetStore.Save(); err != nil {
		writeError(w, http.StatusInternalServerError, "falha ao persistir nó no inventário da frota")
		return
	}

	a.addAudit("fleet_node_added", fmt.Sprintf("Nó %s (%s) pareado e adicionado à frota", newNode.Name, cleanEndpoint), clientAddress(r))
	// Mascarar o token na resposta
	newNode.Token = "••••••••"
	writeJSON(w, http.StatusCreated, newNode)
}

// handleFleetRemoveNode remove um nó da frota.
func (a *webApp) handleFleetRemoveNode(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)
	if !setupState.FleetAllowed {
		writeError(w, http.StatusForbidden, "gerenciamento da frota exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel")
		return
	}

	cfg, _ := a.fetchFleetConfig(ctx)
	if cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "A remoção de nós é permitida apenas na Torre Master")
		return
	}

	nodeID := strings.TrimSpace(r.PathValue("id"))
	if nodeID == "" {
		writeError(w, http.StatusBadRequest, "identificador do nó obrigatório")
		return
	}

	if nodeID == cfg.FleetNodeID || strings.HasPrefix(nodeID, "node-master") {
		writeError(w, http.StatusBadRequest, "o nó local da Torre Master não pode ser removido da frota")
		return
	}

	if a.fleetStore == nil {
		writeError(w, http.StatusInternalServerError, "armazém da frota indisponível")
		return
	}

	removed, err := a.fleetStore.RemoveNode(nodeID)
	if err != nil || !removed {
		writeError(w, http.StatusNotFound, "nó não encontrado no inventário da frota")
		return
	}

	if err := a.fleetStore.Save(); err != nil {
		writeError(w, http.StatusInternalServerError, "falha ao salvar alterações do inventário")
		return
	}

	a.addAudit("fleet_node_removed", fmt.Sprintf("Nó %s removido da frota", nodeID), clientAddress(r))
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "nodeId": nodeID})
}

// handleFleetTelemetry retorna telemetria do nó local em tempo real.
func (a *webApp) handleFleetTelemetry(w http.ResponseWriter, r *http.Request) {
	telem, err := a.fetchLocalTelemetry(r.Context())
	if err != nil {
		writeError(w, http.StatusBadGateway, "não foi possível coletar telemetria do nó local")
		return
	}
	writeJSON(w, http.StatusOK, telem)
}

// handleFleetPing testa a conectividade e latência com um nó da frota.
func (a *webApp) handleFleetPing(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, _ := a.fetchFleetConfig(ctx)

	nodeID := strings.TrimSpace(r.PathValue("id"))
	if nodeID == "" || nodeID == "local" || nodeID == cfg.FleetNodeID {
		localTelem, _ := a.fetchLocalTelemetry(ctx)
		writeJSON(w, http.StatusOK, FleetPingResponse{
			NodeID:    cfg.FleetNodeID,
			Mode:      cfg.FleetMode,
			Pong:      true,
			LatencyMs: 0,
			Status:    "online",
			Telemetry: localTelem,
		})
		return
	}

	if cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "Ping a nós remotos permitido apenas na Torre Master")
		return
	}

	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)
	if !setupState.FleetAllowed {
		writeError(w, http.StatusForbidden, "gerenciamento da frota exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel")
		return
	}

	if a.fleetStore == nil {
		writeError(w, http.StatusInternalServerError, "inventário da frota indisponível")
		return
	}

	node, found := a.fleetStore.GetNode(nodeID)
	if !found {
		writeError(w, http.StatusNotFound, fmt.Sprintf("nó '%s' não encontrado", nodeID))
		return
	}

	telem, latency, err := a.probeWorkerNode(ctx, node.Endpoint, node.Token)
	if err != nil {
		node.Status = "offline"
		_ = a.fleetStore.UpdateNode(node)
		_ = a.fleetStore.Save()
		writeJSON(w, http.StatusOK, FleetPingResponse{
			NodeID:    nodeID,
			Mode:      node.Mode,
			Pong:      false,
			LatencyMs: latency,
			Status:    "offline",
			Error:     err.Error(),
		})
		return
	}

	node.Status = "online"
	node.LastHeartbeat = time.Now().UTC()
	node.Telemetry = &telem
	node.MemoryTotalMB = telem.MemoryTotalMB
	node.MemoryUsedMB = telem.MemoryUsedMB
	node.ServiceCount = telem.HealthyApps + telem.UnhealthyApps
	if telem.Architecture != "" {
		node.Architecture = telem.Architecture
	}
	if telem.SetupVersion != "" {
		node.SetupVersion = telem.SetupVersion
	}
	_ = a.fleetStore.UpdateNode(node)
	_ = a.fleetStore.Save()

	writeJSON(w, http.StatusOK, FleetPingResponse{
		NodeID:    nodeID,
		Mode:      node.Mode,
		Pong:      true,
		LatencyMs: latency,
		Status:    "online",
		Telemetry: telem,
	})
}

// authenticateFleetWorkerRequest valida o token compartilhado entre a Torre Master e o Worker.
func (a *webApp) authenticateFleetWorkerRequest(r *http.Request, expectedToken string, mode FleetMode) bool {
	if mode == FleetModeDisabled || expectedToken == "" {
		return false
	}

	provided := r.Header.Get("X-SetupMNO-Fleet-Token")
	if provided == "" {
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			provided = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	if len(provided) != len(expectedToken) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expectedToken)) == 1
}

// handleFleetWorkerTelemetry é o endpoint exposto pelo Worker para probes da Torre Master.
func (a *webApp) handleFleetWorkerTelemetry(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || !a.authenticateFleetWorkerRequest(r, cfg.FleetToken, cfg.FleetMode) {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado ao endpoint de telemetria do nó")
		return
	}

	telem, err := a.fetchLocalTelemetry(ctx)
	if err != nil {
		writeError(w, http.StatusBadGateway, "falha ao consultar telemetria local")
		return
	}
	writeJSON(w, http.StatusOK, telem)
}

// handleFleetWorkerAction é o endpoint exposto pelo Worker para ações seguras da Torre Master.
func (a *webApp) handleFleetWorkerAction(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || !a.authenticateFleetWorkerRequest(r, cfg.FleetToken, cfg.FleetMode) {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado ao endpoint de ações do nó")
		return
	}

	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	var req FleetActionRequest
	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "ação JSON inválida")
		return
	}

	switch req.Action {
	case "ping":
		writeJSON(w, http.StatusOK, FleetActionResponse{
			ActionID: req.ActionID,
			Success:  true,
			Output:   "pong",
			Data:     map[string]any{"timestamp": time.Now().UTC().Unix()},
		})
	case "healthcheck":
		telem, _ := a.fetchLocalTelemetry(ctx)
		writeJSON(w, http.StatusOK, FleetActionResponse{
			ActionID: req.ActionID,
			Success:  true,
			Output:   "ok",
			Data: map[string]any{
				"activeSwarm":   telem.ActiveSwarm,
				"healthyApps":   telem.HealthyApps,
				"unhealthyApps": telem.UnhealthyApps,
			},
		})
	default:
		writeError(w, http.StatusBadRequest, fmt.Sprintf("ação '%s' não suportada ou não permitida", req.Action))
	}
}

// probeAllWorkers realiza varreduras em paralelo em todos os nós Workers registrados na frota.
// Atualiza imediatamente o status para online ou offline, telemetria e integridade do túnel.
func (a *webApp) probeAllWorkers(ctx context.Context) {
	if a.fleetStore == nil {
		return
	}

	// 1. Reconcilia nós cujo heartbeat expirou primeiro
	_ = a.fleetStore.ReconcileStaleNodes(fleetHeartbeatTimeout)

	nodes := a.fleetStore.ListNodes()
	var workers []FleetNode
	for _, n := range nodes {
		if n.Mode == FleetModeWorker && n.Endpoint != "" {
			// Buscar com o token real preservado
			if realNode, found := a.fleetStore.GetNode(n.ID); found {
				workers = append(workers, realNode)
			}
		}
	}

	if len(workers) == 0 {
		return
	}

	type probeOutcome struct {
		node    FleetNode
		telem   FleetTelemetry
		latency int64
		err     error
	}

	results := make(chan probeOutcome, len(workers))
	var wg sync.WaitGroup

	for _, w := range workers {
		wg.Add(1)
		go func(target FleetNode) {
			defer wg.Done()
			probeCtx, cancel := context.WithTimeout(ctx, fleetProbeTimeout)
			defer cancel()

			telem, latency, err := a.probeWorkerNode(probeCtx, target.Endpoint, target.Token)
			results <- probeOutcome{
				node:    target,
				telem:   telem,
				latency: latency,
				err:     err,
			}
		}(w)
	}

	wg.Wait()
	close(results)

	changed := false
	for out := range results {
		node := out.node
		if out.err != nil {
			// Falha ao conectar: nó desligado, formatado, rede indisponível ou Cloudflare 1033
			if node.Status != "offline" || node.TunnelHealthy {
				node.Status = "offline"
				node.TunnelHealthy = false
				_ = a.fleetStore.UpdateNode(node)
				changed = true
			}
		} else {
			// Sucesso: nó respondendo com telemetria válida
			node.Status = "online"
			node.TunnelHealthy = true
			node.LastHeartbeat = time.Now().UTC()
			node.Telemetry = &out.telem
			node.MemoryTotalMB = out.telem.MemoryTotalMB
			node.MemoryUsedMB = out.telem.MemoryUsedMB
			node.ServiceCount = out.telem.HealthyApps + out.telem.UnhealthyApps
			if out.telem.Architecture != "" {
				node.Architecture = out.telem.Architecture
			}
			if out.telem.SetupVersion != "" {
				node.SetupVersion = out.telem.SetupVersion
			}
			_ = a.fleetStore.UpdateNode(node)
			changed = true
		}
	}

	if changed {
		_ = a.fleetStore.Save()
	}
}

// fleetMonitorDaemon é a rotina em background que audita periodicamente a frota na Torre Master.
func (a *webApp) fleetMonitorDaemon(ctx context.Context) {
	time.Sleep(2 * time.Second)
	// Reconciliação imediata na inicialização para eliminar falsos positivos de imediato
	if a.fleetStore != nil {
		if a.fleetStore.ReconcileStaleNodes(fleetHeartbeatTimeout) {
			_ = a.fleetStore.Save()
		}
	}

	ticker := time.NewTicker(fleetMonitorInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			cfg, err := a.fetchFleetConfig(ctx)
			if err != nil || cfg.FleetMode != FleetModeMaster || a.fleetStore == nil {
				continue
			}

			a.probeAllWorkers(ctx)
		}
	}
}

// handleFleetSync força uma sincronização/probe imediata de todos os nós da frota a partir da interface.
func (a *webApp) handleFleetSync(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)
	if !setupState.FleetAllowed {
		writeError(w, http.StatusForbidden, "gerenciamento da frota exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel")
		return
	}

	cfg, _ := a.fetchFleetConfig(ctx)
	if cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "Sincronização forçada da frota permitida apenas na Torre Master")
		return
	}

	if a.fleetStore == nil {
		writeError(w, http.StatusInternalServerError, "inventário da frota indisponível")
		return
	}

	// Executa probe imediata de todos os workers
	a.probeAllWorkers(ctx)

	nodes := a.fleetStore.ListNodes()
	onlineCount := 0
	offlineCount := 0
	degradedCount := 0
	for _, n := range nodes {
		switch n.Status {
		case "online":
			onlineCount++
		case "degraded":
			degradedCount++
		default:
			offlineCount++
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":        "ok",
		"totalNodes":    len(nodes),
		"onlineNodes":   onlineCount,
		"offlineNodes":  offlineCount,
		"degradedNodes": degradedCount,
		"nodes":         nodes,
		"syncedAt":      time.Now().UTC().Format(time.RFC3339),
	})
}
