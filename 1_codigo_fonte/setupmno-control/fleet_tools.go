package main

import (
	"crypto/subtle"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// FleetToolDefinition representa a definição de uma ferramenta no formato padrão de Function Calling (Hermes Agent / OpenAI).
type FleetToolDefinition struct {
	Type     string                `json:"type"`
	Function FleetToolFunctionSpec `json:"function"`
}

// FleetToolFunctionSpec detalha a assinatura e o objetivo da ferramenta para o raciocínio da LLM.
type FleetToolFunctionSpec struct {
	Name        string             `json:"name"`
	Description string             `json:"description"`
	Parameters  FleetToolParamSpec `json:"parameters"`
}

// FleetToolParamSpec contém o JSON Schema dos parâmetros esperados pela ferramenta.
type FleetToolParamSpec struct {
	Type       string                        `json:"type"`
	Properties map[string]FleetToolPropField `json:"properties"`
	Required   []string                      `json:"required"`
}

// FleetToolPropField define o tipo e a descrição de um argumento individual.
type FleetToolPropField struct {
	Type        string `json:"type"`
	Description string `json:"description"`
}

// FleetToolsSchemaResponse representa o manifesto retornado por /api/fleet/tools/schema.json.
type FleetToolsSchemaResponse struct {
	SchemaVersion string                `json:"schemaVersion"`
	Provider      string                `json:"provider"`
	Description   string                `json:"description"`
	Endpoint      string                `json:"endpoint"`
	Tools         []FleetToolDefinition `json:"tools"`
}

// FleetToolExecuteRequest é o payload recebido para execução de uma ferramenta via POST /api/fleet/tools/execute.
type FleetToolExecuteRequest struct {
	Tool      string         `json:"tool,omitempty"`
	Name      string         `json:"name,omitempty"` // Suporte a payload padrão OpenAI tool_call
	Arguments map[string]any `json:"arguments"`
}

// FleetToolExecuteResponse é a resposta estruturada para o agente autônomo.
type FleetToolExecuteResponse struct {
	Success   bool           `json:"success"`
	Tool      string         `json:"tool"`
	Timestamp int64          `json:"timestamp"`
	Result    map[string]any `json:"result,omitempty"`
	Error     string         `json:"error,omitempty"`
}

// getFleetToolsDefinitions retorna o catálogo oficial de ferramentas do MNO Fleet Hub.
func getFleetToolsDefinitions() []FleetToolDefinition {
	return []FleetToolDefinition{
		{
			Type: "function",
			Function: FleetToolFunctionSpec{
				Name:        "fleet_get_status",
				Description: "Obtém o status operacional, modo da VPS (Master/Worker), nós online/degradados e telemetria consolidada da frota Setup MNO.",
				Parameters: FleetToolParamSpec{
					Type:       "object",
					Properties: map[string]FleetToolPropField{},
					Required:   []string{},
				},
			},
		},
		{
			Type: "function",
			Function: FleetToolFunctionSpec{
				Name:        "fleet_list_nodes",
				Description: "Lista todos os servidores registrados no MNO Fleet Hub com seus IDs, nomes amigáveis, endpoints HTTPS, papéis, arquiteturas (amd64/arm64) e estado de conexão.",
				Parameters: FleetToolParamSpec{
					Type:       "object",
					Properties: map[string]FleetToolPropField{},
					Required:   []string{},
				},
			},
		},
		{
			Type: "function",
			Function: FleetToolFunctionSpec{
				Name:        "fleet_diagnose_node",
				Description: "Executa um diagnóstico SRE detalhado em tempo real em um nó específico da frota através de probe seguro, medindo latência HTTPS, memória RAM livre, espaço em disco, estado do Docker Swarm e réplicas saudáveis.",
				Parameters: FleetToolParamSpec{
					Type: "object",
					Properties: map[string]FleetToolPropField{
						"node_query": {
							Type:        "string",
							Description: "Nome amigável, ID ou endpoint do servidor a ser diagnosticado (ex: 'Debian1-Hetzner' ou 'node-worker-3bb2fb9f').",
						},
					},
					Required: []string{"node_query"},
				},
			},
		},
		{
			Type: "function",
			Function: FleetToolFunctionSpec{
				Name:        "fleet_consult_dispatch",
				Description: "Avalia a capacidade e prontidão de um nó da frota para receber uma aplicação homologada (WordPress, Chatwoot, n8n, Evolution API, Typebot, etc.) e gera um roteiro consultivo seguro de despacho com segregação de recursos e link de instalação.",
				Parameters: FleetToolParamSpec{
					Type: "object",
					Properties: map[string]FleetToolPropField{
						"node_query": {
							Type:        "string",
							Description: "Nome amigável ou ID do servidor worker alvo do despacho.",
						},
						"application": {
							Type:        "string",
							Description: "Nome da aplicação a ser provisionada (ex: 'wordpress', 'chatwoot', 'n8n', 'evolution', 'typebot').",
						},
					},
					Required: []string{"node_query", "application"},
				},
			},
		},
		{
			Type: "function",
			Function: FleetToolFunctionSpec{
				Name:        "fleet_ping_node",
				Description: "Envia um probe seguro (ping/pong) atômico para auditar conectividade e latência de um nó específico da frota via Cloudflare Tunnel.",
				Parameters: FleetToolParamSpec{
					Type: "object",
					Properties: map[string]FleetToolPropField{
						"node_id": {
							Type:        "string",
							Description: "Identificador único do nó na frota (ex: 'node-worker-3bb2fb9f').",
						},
					},
					Required: []string{"node_id"},
				},
			},
		},
	}
}

// authenticateFleetUserOrToken valida o acesso à API de ferramentas via cookie de sessão ou Bearer Token.
func (a *webApp) authenticateFleetUserOrToken(r *http.Request) bool {
	// 1. Validar via cookie de sessão ativa do Control Center
	if cookie, err := r.Cookie(sessionCookie); err == nil && len(cookie.Value) >= 32 {
		a.sessionMu.Lock()
		s, ok := a.sessions[cookie.Value]
		now := time.Now()
		if ok && (now.After(s.Expires) || now.After(s.IdleUntil)) {
			delete(a.sessions, cookie.Value)
			ok = false
		}
		a.sessionMu.Unlock()
		if ok {
			return true
		}
	}

	// 2. Validar via Fleet Token (Bearer ou X-SetupMNO-Fleet-Token)
	tokenHeader := strings.TrimSpace(r.Header.Get("X-SetupMNO-Fleet-Token"))
	authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
	var bearerToken string
	if strings.HasPrefix(authHeader, "Bearer ") {
		bearerToken = strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
	}
	if tokenHeader == "" && bearerToken == "" {
		return false
	}

	cfg, err := a.fetchFleetConfig(r.Context())
	if err == nil && cfg.FleetToken != "" {
		if (tokenHeader != "" && subtle.ConstantTimeCompare([]byte(tokenHeader), []byte(cfg.FleetToken)) == 1) ||
			(bearerToken != "" && subtle.ConstantTimeCompare([]byte(bearerToken), []byte(cfg.FleetToken)) == 1) {
			return true
		}
	}

	return false
}

// handleFleetToolsSchema expõe a especificação de Function Calling compatível com Hermes Agent e OpenAI.
func (a *webApp) handleFleetToolsSchema(w http.ResponseWriter, r *http.Request) {
	scheme := "https"
	if r.TLS == nil && !strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		scheme = "http"
	}
	endpoint := fmt.Sprintf("%s://%s/api/fleet/tools/execute", scheme, r.Host)

	response := FleetToolsSchemaResponse{
		SchemaVersion: "1.0.0",
		Provider:      "setup-mno-fleet",
		Description:   "API Oficial de Ferramentas do MNO Fleet Hub para Agentes Autônomos (Hermes Agent, OpenAI Tool Calling, LangChain, OpenClaw)",
		Endpoint:      endpoint,
		Tools:         getFleetToolsDefinitions(),
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, response)
}

// handleFleetToolsExecute executa de forma segura uma ferramenta invocada pelo Hermes Agent ou agente externo.
func (a *webApp) handleFleetToolsExecute(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if !a.authenticateFleetUserOrToken(r) {
		writeError(w, http.StatusUnauthorized, "acesso não autorizado à API de ferramentas da frota (autentique-se via sessão ou Bearer token)")
		return
	}

	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	var req FleetToolExecuteRequest
	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "payload JSON inválido")
		return
	}

	toolName := strings.TrimSpace(req.Tool)
	if toolName == "" {
		toolName = strings.TrimSpace(req.Name)
	}

	timestamp := time.Now().UTC().Unix()

	switch toolName {
	case "fleet_get_status":
		cfg, _ := a.fetchFleetConfig(ctx)
		localTelem, _ := a.fetchLocalTelemetry(ctx)
		totalNodes := 0
		onlineNodes := 0
		degradedNodes := 0
		offlineNodes := 0
		if a.fleetStore != nil {
			nodes := a.fleetStore.ListNodes()
			totalNodes = len(nodes)
			for _, n := range nodes {
				switch n.Status {
				case "online":
					onlineNodes++
				case "degraded":
					degradedNodes++
				default:
					offlineNodes++
				}
			}
		}
		a.addAudit("fleet_tool_call", "Tool fleet_get_status executada", clientAddress(r))
		writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
			Success:   true,
			Tool:      toolName,
			Timestamp: timestamp,
			Result: map[string]any{
				"mode":          cfg.FleetMode,
				"isMaster":      cfg.FleetMode == FleetModeMaster,
				"totalNodes":    totalNodes,
				"onlineNodes":   onlineNodes,
				"degradedNodes": degradedNodes,
				"offlineNodes":  offlineNodes,
				"localTelemetry": map[string]any{
					"memoryUsedMB":  localTelem.MemoryUsedMB,
					"memoryTotalMB": localTelem.MemoryTotalMB,
					"activeSwarm":   localTelem.ActiveSwarm,
					"healthyApps":   localTelem.HealthyApps,
					"unhealthyApps": localTelem.UnhealthyApps,
				},
			},
		})

	case "fleet_list_nodes":
		if a.fleetStore == nil {
			writeError(w, http.StatusInternalServerError, "inventário da frota indisponível")
			return
		}
		nodes := a.fleetStore.ListNodes()
		sanitized := make([]map[string]any, 0, len(nodes))
		for _, n := range nodes {
			sanitized = append(sanitized, map[string]any{
				"id":            n.ID,
				"name":          n.Name,
				"mode":          n.Mode,
				"role":          n.Role,
				"status":        n.Status,
				"endpoint":      n.Endpoint,
				"architecture":  n.Architecture,
				"setupVersion":  n.SetupVersion,
				"memoryTotalMB": n.MemoryTotalMB,
				"memoryUsedMB":  n.MemoryUsedMB,
				"serviceCount":  n.ServiceCount,
				"tunnelHealthy": n.TunnelHealthy,
				"lastHeartbeat": n.LastHeartbeat.Format(time.RFC3339),
			})
		}
		a.addAudit("fleet_tool_call", "Tool fleet_list_nodes executada", clientAddress(r))
		writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
			Success:   true,
			Tool:      toolName,
			Timestamp: timestamp,
			Result: map[string]any{
				"nodes":      sanitized,
				"totalNodes": len(sanitized),
			},
		})

	case "fleet_diagnose_node":
		if a.fleetStore == nil {
			writeError(w, http.StatusInternalServerError, "inventário da frota indisponível")
			return
		}
		query, _ := req.Arguments["node_query"].(string)
		query = strings.TrimSpace(query)
		if query == "" {
			writeJSON(w, http.StatusBadRequest, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     "argumento obrigatório 'node_query' ausente",
			})
			return
		}

		matchedNode, found := a.fleetStore.FindNodeByNameOrID(query)
		if !found {
			writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     fmt.Sprintf("nó '%s' não encontrado no inventário da frota", query),
			})
			return
		}

		telem, latency, err := a.probeWorkerNode(ctx, matchedNode.Endpoint, matchedNode.Token)
		if err != nil {
			writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     fmt.Sprintf("falha de conexão segura com o nó '%s': %v", matchedNode.Name, err),
				Result: map[string]any{
					"nodeId":    matchedNode.ID,
					"name":      matchedNode.Name,
					"endpoint":  matchedNode.Endpoint,
					"status":    "offline",
					"latencyMs": latency,
				},
			})
			return
		}

		memFree := uint64(0)
		if telem.MemoryTotalMB > telem.MemoryUsedMB {
			memFree = telem.MemoryTotalMB - telem.MemoryUsedMB
		}

		arch := matchedNode.Architecture
		if arch == "" && telem.Architecture != "" {
			arch = telem.Architecture
		}
		if arch == "" {
			arch = "amd64"
		}

		version := matchedNode.SetupVersion
		if version == "" && telem.SetupVersion != "" {
			version = telem.SetupVersion
		}
		if version == "" {
			version = "7.44.0"
		}

		a.addAudit("fleet_tool_call", fmt.Sprintf("Tool fleet_diagnose_node executada para %s", matchedNode.Name), clientAddress(r))
		writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
			Success:   true,
			Tool:      toolName,
			Timestamp: timestamp,
			Result: map[string]any{
				"node": map[string]any{
					"id":           matchedNode.ID,
					"name":         matchedNode.Name,
					"role":         matchedNode.Role,
					"endpoint":     matchedNode.Endpoint,
					"architecture": arch,
					"setupVersion": version,
					"status":       "online",
				},
				"telemetry": map[string]any{
					"latencyMs":     latency,
					"uptimeSeconds": telem.UptimeSeconds,
					"loadAverage1m": telem.LoadAverage1m,
					"memoryUsedMB":  telem.MemoryUsedMB,
					"memoryTotalMB": telem.MemoryTotalMB,
					"memoryFreeMB":  memFree,
					"diskUsedGB":    telem.DiskUsedGB,
					"diskTotalGB":   telem.DiskTotalGB,
					"activeSwarm":   telem.ActiveSwarm,
					"healthyApps":   telem.HealthyApps,
					"unhealthyApps": telem.UnhealthyApps,
				},
				"assessment": fmt.Sprintf("Servidor worker %s online e saudável com %d MB de RAM livres para novas cargas.", matchedNode.Name, memFree),
				"links": map[string]string{
					"installer": matchedNode.Endpoint + "/?action=terminal",
					"panel":     matchedNode.Endpoint + "/",
				},
			},
		})

	case "fleet_consult_dispatch":
		if a.fleetStore == nil {
			writeError(w, http.StatusInternalServerError, "inventário da frota indisponível")
			return
		}
		nodeQuery, _ := req.Arguments["node_query"].(string)
		appQuery, _ := req.Arguments["application"].(string)
		nodeQuery = strings.TrimSpace(nodeQuery)
		appQuery = strings.ToLower(strings.TrimSpace(appQuery))

		if nodeQuery == "" || appQuery == "" {
			writeJSON(w, http.StatusBadRequest, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     "argumentos obrigatórios 'node_query' e 'application' são necessários",
			})
			return
		}

		matchedNode, found := a.fleetStore.FindNodeByNameOrID(nodeQuery)
		if !found {
			writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     fmt.Sprintf("nó '%s' não encontrado no inventário da frota", nodeQuery),
			})
			return
		}

		telem, latency, err := a.probeWorkerNode(ctx, matchedNode.Endpoint, matchedNode.Token)
		if err != nil {
			writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     fmt.Sprintf("nó worker '%s' indisponível para despacho: %v", matchedNode.Name, err),
			})
			return
		}

		memFree := uint64(0)
		if telem.MemoryTotalMB > telem.MemoryUsedMB {
			memFree = telem.MemoryTotalMB - telem.MemoryUsedMB
		}

		requiredRAM := uint64(1024)
		switch {
		case strings.Contains(appQuery, "chatwoot"):
			requiredRAM = 2048
		case strings.Contains(appQuery, "evolution"):
			requiredRAM = 512
		case strings.Contains(appQuery, "n8n"):
			requiredRAM = 512
		case strings.Contains(appQuery, "typebot"):
			requiredRAM = 1024
		case strings.Contains(appQuery, "wordpress"):
			requiredRAM = 1024
		}

		hasCapacity := memFree >= requiredRAM
		statusDesc := "pronto para receber despacho"
		if !hasCapacity {
			statusDesc = "capacidade de memória insuficiente para o deploy seguro desta aplicação"
		}

		a.addAudit("fleet_tool_call", fmt.Sprintf("Tool fleet_consult_dispatch executada para app '%s' no nó '%s'", appQuery, matchedNode.Name), clientAddress(r))
		writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
			Success:   true,
			Tool:      toolName,
			Timestamp: timestamp,
			Result: map[string]any{
				"targetNode": map[string]any{
					"id":           matchedNode.ID,
					"name":         matchedNode.Name,
					"endpoint":     matchedNode.Endpoint,
					"architecture": matchedNode.Architecture,
					"latencyMs":    latency,
				},
				"application":      appQuery,
				"requiredMemoryMB": requiredRAM,
				"availableFreeMB":  memFree,
				"hasCapacity":      hasCapacity,
				"readiness":        statusDesc,
				"consultativePlan": map[string]any{
					"segregation": "Aplicação será provisionada no nó worker remoto, sem onerar a Torre Master.",
					"network":     "Rede overlay segura ('interna') e Cloudflare Tunnel.",
					"actionLink":  matchedNode.Endpoint + "/?action=terminal",
					"rollback":    "Remoção atômica via painel ou Portainer sem impacto nos demais nós da frota.",
				},
			},
		})

	case "fleet_ping_node":
		if a.fleetStore == nil {
			writeError(w, http.StatusInternalServerError, "inventário da frota indisponível")
			return
		}
		nodeID, _ := req.Arguments["node_id"].(string)
		nodeID = strings.TrimSpace(nodeID)
		if nodeID == "" {
			writeJSON(w, http.StatusBadRequest, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     "argumento obrigatório 'node_id' ausente",
			})
			return
		}

		node, found := a.fleetStore.GetNode(nodeID)
		if !found {
			writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     fmt.Sprintf("nó com ID '%s' não encontrado", nodeID),
			})
			return
		}

		telem, latency, err := a.probeWorkerNode(ctx, node.Endpoint, node.Token)
		if err != nil {
			writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
				Success:   false,
				Tool:      toolName,
				Timestamp: timestamp,
				Error:     err.Error(),
				Result: map[string]any{
					"nodeId":    node.ID,
					"pong":      false,
					"latencyMs": latency,
					"status":    "offline",
				},
			})
			return
		}

		writeJSON(w, http.StatusOK, FleetToolExecuteResponse{
			Success:   true,
			Tool:      toolName,
			Timestamp: timestamp,
			Result: map[string]any{
				"nodeId":    node.ID,
				"name":      node.Name,
				"pong":      true,
				"latencyMs": latency,
				"status":    "online",
				"activeSwarm": telem.ActiveSwarm,
			},
		})

	default:
		writeJSON(w, http.StatusBadRequest, FleetToolExecuteResponse{
			Success:   false,
			Tool:      toolName,
			Timestamp: timestamp,
			Error:     fmt.Sprintf("ferramenta '%s' não reconhecida ou não homologada", toolName),
		})
	}
}
