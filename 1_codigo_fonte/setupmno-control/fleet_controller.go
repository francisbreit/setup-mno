package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
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

// probeWorkerNode realiza uma consulta remota segura com timeout e dupla checagem para auditar um nó subordinado.
func (a *webApp) probeWorkerNode(ctx context.Context, endpoint, token string) (FleetTelemetry, int64, error) {
	cleanURL, err := validateFleetEndpoint(endpoint)
	if err != nil {
		return FleetTelemetry{}, 0, err
	}

	probeURL := cleanURL + "/api/fleet/worker/telemetry"

	singleProbe := func() (FleetTelemetry, int64, error) {
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

	// 1ª tentativa
	telem, latency, err := singleProbe()
	if err == nil {
		return telem, latency, nil
	}

	// Se falhou na 1ª tentativa, realiza dupla checagem com delay de segurança de 1.5s
	// para absorver instabilidades de borda na Cloudflare e jitter de rota efêmero
	select {
	case <-ctx.Done():
		return FleetTelemetry{}, latency, ctx.Err()
	case <-time.After(1500 * time.Millisecond):
	}

	return singleProbe()
}

// handleFleetStatus retorna o status consolidado do Fleet Hub para a interface e auditorias.
func (a *webApp) handleFleetStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, _ := a.fetchFleetConfig(ctx)
	localTelem, _ := a.fetchLocalTelemetry(ctx)

	var setupState setupStateResponse
	_ = a.agentRequest(ctx, "/setup-state", &setupState)

	role := cfg.FleetRole
	if role == "" {
		role = "active"
	}
	response := FleetStatusResponse{
		Mode:           cfg.FleetMode,
		NodeID:         cfg.FleetNodeID,
		FleetAllowed:   setupState.FleetAllowed,
		FleetToken:     cfg.FleetToken,
		FleetRole:      role,
		IsStandby:      (role == "standby"),
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
		if telem.PublicIP != "" {
			newNode.PublicIP = telem.PublicIP
		}
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

	if newNode.PublicIP != "" {
		_ = saveFleetSSHHost(newNode.ID, newNode.Name, newNode.PublicIP)
	}

	// Autoriza automaticamente a chave SSH pública do Master no Worker em background
	go func(targetEndpoint, targetToken string) {
		var keyResp struct {
			Success bool   `json:"success"`
			Key     string `json:"key"`
		}
		_ = a.agentRequest(context.Background(), "/fleet/public-ssh-key", &keyResp)
		keyStr := strings.TrimSpace(keyResp.Key)
		if keyStr == "" {
			keyStr = getHostSSHPublicKey()
		}
		if keyStr != "" {
			payloadMap := map[string]any{
				"action": "authorize_ssh_key",
				"payload": map[string]any{
					"key": keyStr,
				},
			}
			bodyBytes, _ := json.Marshal(payloadMap)
			req, _ := http.NewRequest(http.MethodPost, targetEndpoint+"/api/fleet/worker/action", bytes.NewReader(bodyBytes))
			if req != nil {
				req.Header.Set("X-SetupMNO-Fleet-Token", targetToken)
				req.Header.Set("Content-Type", "application/json")
				client := &http.Client{Timeout: 8 * time.Second}
				resp, err := client.Do(req)
				if err == nil && resp != nil {
					_ = resp.Body.Close()
				}
			}
		}
	}(cleanEndpoint, req.Token)

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

	a.fleetLockMu.Lock()
	if a.fleetLock != nil && a.fleetLock.Locked {
		if time.Now().UTC().After(a.fleetLock.ExpiresAt) {
			a.fleetLock.Locked = false
		} else {
			lockCopy := *a.fleetLock
			telem.Lock = &lockCopy
		}
	}
	a.fleetLockMu.Unlock()

	writeJSON(w, http.StatusOK, telem)
}

// handleFleetWorkerLock gerencia a trava de ocupação atômica do nó Worker (Node Lease / Lock).
func (a *webApp) handleFleetWorkerLock(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || !a.authenticateFleetWorkerRequest(r, cfg.FleetToken, cfg.FleetMode) {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado ao endpoint de trava do nó")
		return
	}

	a.fleetLockMu.Lock()
	defer a.fleetLockMu.Unlock()

	now := time.Now().UTC()

	// Se for requisição GET, retorna o status do lock
	if r.Method == http.MethodGet {
		var currentLock FleetNodeLock
		if a.fleetLock != nil && a.fleetLock.Locked {
			if now.After(a.fleetLock.ExpiresAt) {
				a.fleetLock.Locked = false
			} else {
				currentLock = *a.fleetLock
			}
		}
		writeJSON(w, http.StatusOK, FleetLockResponse{
			Success: true,
			Message: "Status da trava consultado",
			Lock:    currentLock,
		})
		return
	}

	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	var req FleetLockRequest
	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "requisição de trava JSON inválida")
		return
	}

	switch strings.ToLower(strings.TrimSpace(req.Action)) {
	case "status":
		var currentLock FleetNodeLock
		if a.fleetLock != nil && a.fleetLock.Locked {
			if now.After(a.fleetLock.ExpiresAt) {
				a.fleetLock.Locked = false
			} else {
				currentLock = *a.fleetLock
			}
		}
		writeJSON(w, http.StatusOK, FleetLockResponse{
			Success: true,
			Message: "Status da trava consultado",
			Lock:    currentLock,
		})

	case "acquire":
		// Verifica se já está travado por outra central
		if a.fleetLock != nil && a.fleetLock.Locked && now.Before(a.fleetLock.ExpiresAt) {
			holderID := strings.TrimSpace(req.HolderID)
			// Se for o mesmo holder, permite renovação do lease (TTL)
			if holderID != "" && holderID == a.fleetLock.HolderID {
				ttl := req.TTLSeconds
				if ttl <= 0 {
					ttl = 300
				}
				if ttl > 1800 {
					ttl = 1800
				}
				a.fleetLock.ExpiresAt = now.Add(time.Duration(ttl) * time.Second)
				if req.Task != "" {
					a.fleetLock.Task = req.Task
				}
				writeJSON(w, http.StatusOK, FleetLockResponse{
					Success: true,
					Message: "Trava renovada com sucesso",
					Lock:    *a.fleetLock,
				})
				return
			}

			// Outro holder tentando adquirir enquanto ocupado: 409 Conflict
			msg := fmt.Sprintf("Este nó está ocupado executando uma tarefa disparada por outra central (%s por %s). Aguarde a conclusão ou expiração do lock.", a.fleetLock.Task, a.fleetLock.HolderName)
			writeJSON(w, http.StatusConflict, FleetLockResponse{
				Success: false,
				Message: msg,
				Lock:    *a.fleetLock,
			})
			return
		}

		// Adquirir nova trava
		ttl := req.TTLSeconds
		if ttl <= 0 {
			ttl = 300 // 5 minutos padrão
		}
		if ttl > 1800 {
			ttl = 1800 // 30 minutos máximo
		}

		holderID := strings.TrimSpace(req.HolderID)
		if holderID == "" {
			holderID = clientAddress(r)
		}
		holderName := strings.TrimSpace(req.HolderName)
		if holderName == "" {
			holderName = "Torre Master"
		}
		task := strings.TrimSpace(req.Task)
		if task == "" {
			task = "Operação de Frota"
		}

		a.fleetLock = &FleetNodeLock{
			Locked:     true,
			HolderID:   holderID,
			HolderName: holderName,
			Task:       task,
			AcquiredAt: now,
			ExpiresAt:  now.Add(time.Duration(ttl) * time.Second),
		}

		writeJSON(w, http.StatusOK, FleetLockResponse{
			Success: true,
			Message: "Trava adquirida com sucesso",
			Lock:    *a.fleetLock,
		})

	case "release":
		if a.fleetLock != nil && a.fleetLock.Locked {
			holderID := strings.TrimSpace(req.HolderID)
			if holderID == "" || holderID == "force" || holderID == a.fleetLock.HolderID {
				a.fleetLock.Locked = false
			}
		}
		writeJSON(w, http.StatusOK, FleetLockResponse{
			Success: true,
			Message: "Trava liberada com sucesso",
			Lock:    FleetNodeLock{},
		})

	default:
		writeError(w, http.StatusBadRequest, "ação de trava inválida (use 'acquire', 'release' ou 'status')")
	}
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
	case "get_ip":
		telem, _ := a.fetchLocalTelemetry(ctx)
		writeJSON(w, http.StatusOK, FleetActionResponse{
			ActionID: req.ActionID,
			Success:  true,
			Output:   telem.PublicIP,
			Data:     map[string]any{"publicIp": telem.PublicIP},
		})
	case "authorize_ssh_key":
		key, ok := req.Payload["key"].(string)
		key = strings.TrimSpace(key)
		validKey := ok && (strings.HasPrefix(key, "ssh-rsa ") ||
			strings.HasPrefix(key, "ssh-ed25519 ") ||
			strings.HasPrefix(key, "ecdsa-sha2-")) &&
			!strings.ContainsAny(key, "\r\n") &&
			len(key) < 4096
		if validKey {
			var agentResp map[string]any
			if err := a.agentPost(ctx, "/fleet/authorize-ssh-key", map[string]string{"key": key}, &agentResp); err == nil {
				writeJSON(w, http.StatusOK, FleetActionResponse{
					ActionID: req.ActionID,
					Success:  true,
					Output:   "ssh_key_authorized",
				})
				return
			}
			_ = appendAuthorizedSSHKey(key)
			writeJSON(w, http.StatusOK, FleetActionResponse{
				ActionID: req.ActionID,
				Success:  true,
				Output:   "ssh_key_authorized",
			})
			return
		}
		writeError(w, http.StatusBadRequest, "chave SSH pública inválida")
		return
	default:
		writeError(w, http.StatusBadRequest, fmt.Sprintf("ação '%s' não suportada ou não permitida", req.Action))
	}
}

// handleFleetWorkerIP retorna o IP do worker diretamente para a Torre Master.
func (a *webApp) handleFleetWorkerIP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || !a.authenticateFleetWorkerRequest(r, cfg.FleetToken, cfg.FleetMode) {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado ao endpoint de IP do nó")
		return
	}
	telem, err := a.fetchLocalTelemetry(ctx)
	if err != nil || telem.PublicIP == "" {
		writeError(w, http.StatusBadGateway, "IP do nó indisponível")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"publicIp": telem.PublicIP,
	})
}

func getHostSSHPublicKey() string {
	candidates := []string{
		"/root/.ssh/id_ed25519.pub",
		"/root/.ssh/id_rsa.pub",
		"/runtime-control/master_ssh.pub",
		"/root/SetupLowCodeMno/.control/master_ssh.pub",
	}
	for _, p := range candidates {
		if data, err := os.ReadFile(p); err == nil {
			s := strings.TrimSpace(string(data))
			if s != "" {
				return s
			}
		}
	}
	return ""
}

func appendAuthorizedSSHKey(key string) error {
	key = strings.TrimSpace(key)
	if key == "" {
		return errors.New("chave vazia")
	}
	sshDir := "/root/.ssh"
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		return err
	}
	_ = os.Chmod(sshDir, 0700)
	authFile := filepath.Join(sshDir, "authorized_keys")
	existing, _ := os.ReadFile(authFile)
	if strings.Contains(string(existing), key) {
		_ = os.Chmod(authFile, 0600)
		return nil
	}
	f, err := os.OpenFile(authFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(key + "\n")
	_ = os.Chmod(authFile, 0600)
	return err
}

func saveFleetSSHHost(nodeID, nodeName, host string) error {
	host = strings.TrimSpace(host)
	if host == "" {
		return nil
	}
	sshHostsFile := "/root/SetupLowCodeMno/.control/fleet-ssh.json"
	_ = os.MkdirAll(filepath.Dir(sshHostsFile), 0755)
	var current map[string]string
	if data, err := os.ReadFile(sshHostsFile); err == nil {
		_ = json.Unmarshal(data, &current)
	}
	if current == nil {
		current = make(map[string]string)
	}
	if nodeID != "" {
		current[nodeID] = host
	}
	if nodeName != "" {
		current[nodeName] = host
	}
	out, err := json.MarshalIndent(current, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(sshHostsFile, out, 0600)
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
			node.Lock = out.telem.Lock
			node.MemoryTotalMB = out.telem.MemoryTotalMB
			node.MemoryUsedMB = out.telem.MemoryUsedMB
			node.ServiceCount = out.telem.HealthyApps + out.telem.UnhealthyApps
			if out.telem.Architecture != "" {
				node.Architecture = out.telem.Architecture
			}
			if out.telem.SetupVersion != "" {
				node.SetupVersion = out.telem.SetupVersion
			}
			if out.telem.PublicIP != "" && node.PublicIP != out.telem.PublicIP {
				node.PublicIP = out.telem.PublicIP
				_ = saveFleetSSHHost(node.ID, node.Name, node.PublicIP)
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
			if cfg.FleetRole == "standby" {
				continue // Em modo Standby (Cockpit Pessoal), não realiza polling contínuo para poupar bateria e conexões
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

// handleFleetNodeStructure retorna a inspeção de infraestrutura e catálogo de um nó.
func (a *webApp) handleFleetNodeStructure(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	nodeID := strings.TrimSpace(r.PathValue("id"))
	if nodeID == "" {
		nodeID = "local"
	}

	structure, err := a.InspectNodeStructure(ctx, nodeID)
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Sprintf("falha ao inspecionar estrutura do nó: %v", err))
		return
	}

	writeJSON(w, http.StatusOK, structure)
}

// handleFleetWorkerStructure é o endpoint exposto pelo Worker para probes estruturais da Torre Master.
func (a *webApp) handleFleetWorkerStructure(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || !a.authenticateFleetWorkerRequest(r, cfg.FleetToken, cfg.FleetMode) {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado ao endpoint estrutural do nó")
		return
	}

	structure, err := a.InspectNodeStructure(ctx, "local")
	if err != nil {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("falha ao coletar estrutura local: %v", err))
		return
	}

	writeJSON(w, http.StatusOK, structure)
}

// handleFleetTransferPreflight avalia previamente os gates de arquitetura e recursos antes de transferir.
func (a *webApp) handleFleetTransferPreflight(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req struct {
		AppName      string `json:"appName"`
		OriginNodeID string `json:"originNodeId"`
		DestNodeID   string `json:"destNodeId"`
		Mode         string `json:"mode"`
		ComboChoice  string `json:"comboChoice"`
		MinioPolicy  string `json:"minioPolicy"`
	}

	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "JSON inválido na requisição de preflight")
		return
	}

	if req.AppName == "" || req.OriginNodeID == "" || req.DestNodeID == "" {
		writeError(w, http.StatusBadRequest, "campos 'appName', 'originNodeId' e 'destNodeId' são obrigatórios")
		return
	}

	origStruct, err := a.InspectNodeStructure(ctx, req.OriginNodeID)
	if err != nil {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("falha ao inspecionar nó de origem: %v", err))
		return
	}

	destStruct, err := a.InspectNodeStructure(ctx, req.DestNodeID)
	if err != nil {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("falha ao inspecionar nó de destino: %v", err))
		return
	}

	result := EvaluateTransferPreflight(origStruct, destStruct, req.AppName, req.Mode, req.ComboChoice, req.MinioPolicy)
	writeJSON(w, http.StatusOK, result)
}

// handleFleetTransferExecute inicia a transferência segura com alteração de DNS.
func (a *webApp) handleFleetTransferExecute(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req FleetTransferExecutionRequest

	data, err := io.ReadAll(io.LimitReader(r.Body, 32<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "JSON inválido na requisição de transferência")
		return
	}

	res, err := a.ExecuteApplicationTransfer(ctx, req)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, res)
		return
	}

	writeJSON(w, http.StatusOK, res)
}

// handleFleetBackupExecute dispara a criação de um backup portátil consistente.
func (a *webApp) handleFleetBackupExecute(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req FleetBackupExecutionRequest

	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "JSON inválido na requisição de backup")
		return
	}

	res, err := a.ExecuteApplicationBackup(ctx, req)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, res)
		return
	}

	writeJSON(w, http.StatusOK, res)
}

// handleFleetExportInventory exporta a lista de nós operários da frota para outra Torre Master autorizada.
func (a *webApp) handleFleetExportInventory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "apenas nós configurados como Torre Master podem exportar o inventário da frota")
		return
	}

	tokenAuthorized := a.authenticateFleetWorkerRequest(r, cfg.FleetToken, cfg.FleetMode)
	sessionAuthorized := a.isSessionAuthenticated(r)

	if !tokenAuthorized && !sessionAuthorized {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado ao inventário da frota. Forneça o token no header X-SetupMNO-Fleet-Token")
		return
	}

	nodes := a.fleetStore.ExportWorkerNodes()
	resp := FleetExportInventoryResponse{
		SchemaVersion: fleetInventorySchemaVersion,
		MasterNodeID:  cfg.FleetNodeID,
		ExportedAt:    time.Now().UTC(),
		Nodes:         nodes,
	}

	a.addAudit("fleet_inventory_exported", fmt.Sprintf("Inventário da frota exportado (%d nós) para %s", len(nodes), clientAddress(r)), clientAddress(r))
	writeJSON(w, http.StatusOK, resp)
}

// handleFleetImportInventory conecta a uma Torre Master remota, obtém seu inventário e mescla ou substitui os nós locais.
func (a *webApp) handleFleetImportInventory(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "apenas nós configurados como Torre Master podem importar inventário da frota")
		return
	}

	var req FleetImportInventoryRequest
	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "JSON inválido na requisição de importação")
		return
	}

	if strings.TrimSpace(req.MasterEndpoint) == "" || strings.TrimSpace(req.MasterToken) == "" {
		writeError(w, http.StatusBadRequest, "campos 'masterEndpoint' e 'masterToken' são obrigatórios")
		return
	}

	cleanEndpoint, err := validateFleetEndpoint(req.MasterEndpoint)
	if err != nil {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("endpoint da Torre Master de origem inválido: %v", err))
		return
	}

	exportURL := cleanEndpoint + "/api/fleet/inventory/export"
	importCtx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(importCtx, http.MethodGet, exportURL, nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "falha ao preparar requisição de importação")
		return
	}
	httpReq.Header.Set("X-SetupMNO-Fleet-Token", req.MasterToken)
	httpReq.Header.Set("Authorization", "Bearer "+req.MasterToken)
	httpReq.Header.Set("Accept", "application/json")

	resp, err := a.httpClient.Do(httpReq)
	if err != nil {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("falha ao conectar na Torre Master remota: %v", err))
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		writeError(w, http.StatusUnauthorized, "token recusado pela Torre Master remota. Verifique a credencial informada.")
		return
	}
	if resp.StatusCode != http.StatusOK {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("Torre Master remota respondeu com status HTTP %d", resp.StatusCode))
		return
	}

	var exportData FleetExportInventoryResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 512<<10)).Decode(&exportData); err != nil {
		writeError(w, http.StatusBadGateway, "resposta de inventário recebida da Torre Master remota é inválida")
		return
	}

	importedCount, err := a.fleetStore.ImportNodes(exportData.Nodes, req.Strategy)
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("falha ao importar nós: %v", err))
		return
	}

	if err := a.fleetStore.Save(); err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("falha ao persistir inventário: %v", err))
		return
	}

	a.addAudit("fleet_inventory_imported", fmt.Sprintf("Importados %d nós da Torre Master %s (estratégia: %s)", importedCount, cleanEndpoint, req.Strategy), clientAddress(r))

	go a.probeAllWorkers(context.Background())

	writeJSON(w, http.StatusOK, FleetImportInventoryResponse{
		Success:       true,
		Message:       fmt.Sprintf("Sincronização concluída com sucesso: %d nós da frota importados/atualizados.", importedCount),
		ImportedCount: importedCount,
		Nodes:         a.fleetStore.ListNodes(),
	})
}

// handleFleetSetRole comuta o papel operacional da Torre Master entre Ativa (24/7) e Standby (Cockpit Local).
func (a *webApp) handleFleetSetRole(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg, err := a.fetchFleetConfig(ctx)
	if err != nil || cfg.FleetMode != FleetModeMaster {
		writeError(w, http.StatusForbidden, "apenas nós configurados como Torre Master possuem papel operacional comutável")
		return
	}

	var req FleetRoleRequest
	data, err := io.ReadAll(io.LimitReader(r.Body, 4<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "JSON inválido na requisição de alteração de papel")
		return
	}

	cleanRole := strings.ToLower(strings.TrimSpace(req.Role))
	if cleanRole != "active" && cleanRole != "standby" {
		writeError(w, http.StatusBadRequest, "papel inválido: use 'active' para Torre Ativa (24/7) ou 'standby' para Cockpit Local")
		return
	}

	var agentResp struct {
		Success bool   `json:"success"`
		Role    string `json:"role"`
	}
	if err := a.agentPost(ctx, "/fleet/role", map[string]string{"role": cleanRole}, &agentResp); err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("falha ao atualizar papel no agente: %v", err))
		return
	}

	a.addAudit("fleet_role_changed", fmt.Sprintf("Papel da Torre Master comutado para '%s'", cleanRole), clientAddress(r))

	message := "Torre Master configurada como Ativa (24/7) com monitoramento contínuo."
	if cleanRole == "standby" {
		message = "Torre Master configurada como Standby (Cockpit Local): alertas autônomos pausados para evitar duplicidade."
	}

	writeJSON(w, http.StatusOK, FleetRoleResponse{
		Success: true,
		Role:    cleanRole,
		Message: message,
	})
}
