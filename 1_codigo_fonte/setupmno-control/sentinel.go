package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// SentinelConfig armazena os parâmetros de monitoramento e alertas autônomos da frota.
type SentinelConfig struct {
	Enabled              bool   `json:"enabled"`
	CheckIntervalSec     int    `json:"checkIntervalSec"`     // Intervalo de verificação em segundos (mín: 15s, default: 60s)
	RAMThresholdPct      int    `json:"ramThresholdPct"`      // Limite percentual de uso de RAM (default: 85%)
	DiskThresholdPct     int    `json:"diskThresholdPct"`     // Limite percentual de uso de Disco (default: 90%)
	NotifyDegradedApp    bool   `json:"notifyDegradedApp"`    // Alerta se qualquer réplica de container Swarm cair
	NotifyNodeDown       bool   `json:"notifyNodeDown"`       // Alerta se qualquer Nó Worker da frota ficar offline
	ConfirmationDelaySec int    `json:"confirmationDelaySec"` // Delay de segurança antes de disparar alerta (default: 45s, mín: 0s, máx: 600s)
	WebhookURL           string `json:"webhookURL"`           // Endpoint HTTP/HTTPS para n8n, Discord, Slack ou webhook próprio
	TelegramBotToken     string `json:"telegramBotToken"`     // Token do Bot no Telegram
	TelegramChatID       string `json:"telegramChatID"`       // Chat ID ou Canal do Telegram
	CooldownMinutes      int    `json:"cooldownMinutes"`      // Tempo mínimo entre repetições do mesmo alerta (default: 15 min)
}

// defaultSentinelConfig retorna as configurações padrão e seguras do Sentinel.
func defaultSentinelConfig() *SentinelConfig {
	return &SentinelConfig{
		Enabled:              false,
		CheckIntervalSec:     60,
		RAMThresholdPct:      85,
		DiskThresholdPct:     90,
		NotifyDegradedApp:     true,
		NotifyNodeDown:        true,
		ConfirmationDelaySec: 45,
		CooldownMinutes:      15,
	}
}

// Sanitized retorna uma visão limpa da configuração para a interface e API, mascarando credenciais.
func (c *SentinelConfig) Sanitized() map[string]any {
	maskedToken := ""
	if len(c.TelegramBotToken) > 8 {
		maskedToken = c.TelegramBotToken[:4] + "..." + c.TelegramBotToken[len(c.TelegramBotToken)-4:]
	} else if len(c.TelegramBotToken) > 0 {
		maskedToken = "***"
	}
	return map[string]any{
		"enabled":              c.Enabled,
		"checkIntervalSec":     c.CheckIntervalSec,
		"ramThresholdPct":      c.RAMThresholdPct,
		"diskThresholdPct":     c.DiskThresholdPct,
		"notifyDegradedApp":    c.NotifyDegradedApp,
		"notifyNodeDown":       c.NotifyNodeDown,
		"confirmationDelaySec": c.ConfirmationDelaySec,
		"webhookURL":           c.WebhookURL,
		"telegramConfigured":   c.TelegramBotToken != "" && c.TelegramChatID != "",
		"telegramBotToken":     maskedToken,
		"telegramChatID":       c.TelegramChatID,
		"cooldownMinutes":      c.CooldownMinutes,
	}
}

// Validate valida e sanitiza a configuração antes de persistir.
func (c *SentinelConfig) Validate() error {
	if c.CheckIntervalSec < 15 {
		c.CheckIntervalSec = 15
	}
	if c.CheckIntervalSec > 3600 {
		c.CheckIntervalSec = 3600
	}
	if c.RAMThresholdPct < 50 || c.RAMThresholdPct > 98 {
		c.RAMThresholdPct = 85
	}
	if c.DiskThresholdPct < 50 || c.DiskThresholdPct > 98 {
		c.DiskThresholdPct = 90
	}
	if c.ConfirmationDelaySec < 0 {
		c.ConfirmationDelaySec = 45
	}
	if c.ConfirmationDelaySec > 600 {
		c.ConfirmationDelaySec = 600
	}
	if c.CooldownMinutes < 1 {
		c.CooldownMinutes = 5
	}
	if c.CooldownMinutes > 1440 {
		c.CooldownMinutes = 1440
	}
	c.WebhookURL = strings.TrimSpace(c.WebhookURL)
	if c.WebhookURL != "" {
		parsed, err := url.Parse(c.WebhookURL)
		if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
			return errors.New("webhookURL deve ser uma URL HTTP ou HTTPS válida")
		}
	}
	c.TelegramBotToken = strings.TrimSpace(c.TelegramBotToken)
	c.TelegramChatID = strings.TrimSpace(c.TelegramChatID)
	return nil
}

// SentinelIncident representa uma falha ou anomalia operacional ativa.
type SentinelIncident struct {
	ID        string    `json:"id"`
	NodeName  string    `json:"nodeName"`
	Severity  string    `json:"severity"` // "warning", "critical"
	Message   string    `json:"message"`
	StartedAt time.Time `json:"startedAt"`
}

// SentinelAlertRecord armazena o histórico do despacho de uma notificação.
type SentinelAlertRecord struct {
	Timestamp time.Time `json:"timestamp"`
	Target    string    `json:"target"` // "telegram", "webhook"
	Incident  string    `json:"incident"`
	Success   bool      `json:"success"`
	Error     string    `json:"error,omitempty"`
}

type sentinelIncidentState struct {
	Incident    SentinelIncident
	FirstSeen   time.Time
	LastAlertAt time.Time
	AlertSent   bool
}

type sentinelRuntimeState struct {
	mu           sync.Mutex
	running      bool
	lastCheck    time.Time
	incidents    map[string]*sentinelIncidentState
	recentAlerts []SentinelAlertRecord
}

func newSentinelRuntimeState() *sentinelRuntimeState {
	return &sentinelRuntimeState{
		incidents:    make(map[string]*sentinelIncidentState),
		recentAlerts: make([]SentinelAlertRecord, 0, 50),
	}
}

// loadSentinelConfig carrega a configuração persistida do disco.
func loadSentinelConfig(path string) (*SentinelConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return defaultSentinelConfig(), err
	}
	var cfg SentinelConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return defaultSentinelConfig(), err
	}
	if err := cfg.Validate(); err != nil {
		return defaultSentinelConfig(), err
	}
	return &cfg, nil
}

// saveSentinelConfig persiste a configuração atômica no disco.
func saveSentinelConfig(path string, cfg *SentinelConfig) error {
	if err := cfg.Validate(); err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("criar diretório do sentinel: %w", err)
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("serializar sentinel config: %w", err)
	}

	tmpFile := fmt.Sprintf("%s.tmp.%d", path, time.Now().UnixNano())
	if err := os.WriteFile(tmpFile, data, 0600); err != nil {
		return fmt.Errorf("gravar sentinel config temporário: %w", err)
	}
	if err := os.Rename(tmpFile, path); err != nil {
		_ = os.Remove(tmpFile)
		return fmt.Errorf("substituir sentinel config: %w", err)
	}
	return nil
}

// sendTelegramAlert envia uma mensagem para o Telegram usando a API Bot oficial.
func sendTelegramAlert(ctx context.Context, token, chatID, text string) error {
	if token == "" || chatID == "" {
		return errors.New("telegram bot token ou chat ID não configurados")
	}

	reqURL := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", token)
	bodyPayload := map[string]any{
		"chat_id":    chatID,
		"text":       text,
		"parse_mode": "Markdown",
	}

	data, err := json.Marshal(bodyPayload)
	if err != nil {
		return err
	}

	reqCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, reqURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("telegram retornou HTTP %d: %s", resp.StatusCode, string(body))
	}
	return nil
}

// sendWebhookAlert envia um payload JSON para o webhook configurado (n8n, Slack, Discord).
func sendWebhookAlert(ctx context.Context, webhookURL string, payload map[string]any) error {
	if webhookURL == "" {
		return errors.New("webhook URL não configurada")
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	reqCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, webhookURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "SetupMNO-Sentinel/1.0")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("webhook retornou HTTP %d", resp.StatusCode)
	}
	return nil
}

// dispatchSentinelNotification envia os alertas para os canais configurados (Telegram e/ou Webhook).
func (a *webApp) dispatchSentinelNotification(ctx context.Context, incident SentinelIncident, isResolution bool, telem FleetTelemetry) []SentinelAlertRecord {
	a.sentinelMu.Lock()
	if a.sentinelConfig == nil {
		a.sentinelMu.Unlock()
		return nil
	}
	cfg := *a.sentinelConfig
	a.sentinelMu.Unlock()

	records := make([]SentinelAlertRecord, 0, 2)
	now := time.Now().UTC()

	var tgText string
	var icon string
	if isResolution {
		icon = "✅"
		tgText = fmt.Sprintf("*%s [MNO SENTINEL RESOLVIDO]*\n\n*Servidor:* `%s`\n*Incidente:* %s\n*Status:* Normalizado\n*Telemetria Atual:* RAM: %dMB / %dMB · Disco: %dGB / %dGB · Apps Saudáveis: %d\n*Horário:* %s UTC",
			icon, incident.NodeName, incident.Message, telem.MemoryUsedMB, telem.MemoryTotalMB, telem.DiskUsedGB, telem.DiskTotalGB, telem.HealthyApps, now.Format("2006-01-02 15:04:05"))
	} else {
		if incident.Severity == "critical" {
			icon = "🚨"
		} else {
			icon = "⚠️"
		}
		tgText = fmt.Sprintf("*%s [MNO SENTINEL ALERTA]*\n\n*Servidor:* `%s`\n*Severidade:* %s\n*Alerta:* %s\n*Telemetria:* RAM: %dMB / %dMB · Disco: %dGB / %dGB · Apps Degradados: %d\n*Horário:* %s UTC",
			icon, incident.NodeName, strings.ToUpper(incident.Severity), incident.Message, telem.MemoryUsedMB, telem.MemoryTotalMB, telem.DiskUsedGB, telem.DiskTotalGB, telem.UnhealthyApps, now.Format("2006-01-02 15:04:05"))
	}

	webhookPayload := map[string]any{
		"provider":   "setup-mno-sentinel",
		"event":      "sentinel_alert",
		"resolved":   isResolution,
		"severity":   incident.Severity,
		"server":     incident.NodeName,
		"incidentId": incident.ID,
		"message":    incident.Message,
		"timestamp":  now.Format(time.RFC3339),
		"telemetry": map[string]any{
			"memoryUsedMB":  telem.MemoryUsedMB,
			"memoryTotalMB": telem.MemoryTotalMB,
			"diskUsedGB":    telem.DiskUsedGB,
			"diskTotalGB":   telem.DiskTotalGB,
			"healthyApps":   telem.HealthyApps,
			"unhealthyApps": telem.UnhealthyApps,
		},
		"content": tgText, // Compatibilidade Discord
		"text":    tgText, // Compatibilidade Slack / n8n
	}

	// 1. Canal Telegram
	if cfg.TelegramBotToken != "" && cfg.TelegramChatID != "" {
		err := sendTelegramAlert(ctx, cfg.TelegramBotToken, cfg.TelegramChatID, tgText)
		rec := SentinelAlertRecord{
			Timestamp: now,
			Target:    "telegram",
			Incident:  incident.ID,
			Success:   err == nil,
		}
		if err != nil {
			rec.Error = err.Error()
		}
		records = append(records, rec)
	}

	// 2. Canal Webhook (n8n, Discord, Slack)
	if cfg.WebhookURL != "" {
		err := sendWebhookAlert(ctx, cfg.WebhookURL, webhookPayload)
		rec := SentinelAlertRecord{
			Timestamp: now,
			Target:    "webhook",
			Incident:  incident.ID,
			Success:   err == nil,
		}
		if err != nil {
			rec.Error = err.Error()
		}
		records = append(records, rec)
	}

	return records
}

// evaluateSentinelTelemetry avalia métricas de um nó e retorna lista de anomalias encontradas.
func evaluateSentinelTelemetry(nodeName string, telem FleetTelemetry, cfg *SentinelConfig) []SentinelIncident {
	incidents := make([]SentinelIncident, 0)
	now := time.Now().UTC()

	// 1. Checagem de Memória RAM
	if telem.MemoryTotalMB > 0 && cfg.RAMThresholdPct > 0 {
		ramPct := int((telem.MemoryUsedMB * 100) / telem.MemoryTotalMB)
		if ramPct >= cfg.RAMThresholdPct {
			incidents = append(incidents, SentinelIncident{
				ID:        fmt.Sprintf("ram_high_%s", nodeName),
				NodeName:  nodeName,
				Severity:  "critical",
				Message:   fmt.Sprintf("Uso crítico de memória RAM atingiu %d%% (%d MB / %d MB)", ramPct, telem.MemoryUsedMB, telem.MemoryTotalMB),
				StartedAt: now,
			})
		}
	}

	// 2. Checagem de Espaço em Disco
	if telem.DiskTotalGB > 0 && cfg.DiskThresholdPct > 0 {
		diskPct := int((telem.DiskUsedGB * 100) / telem.DiskTotalGB)
		if diskPct >= cfg.DiskThresholdPct {
			incidents = append(incidents, SentinelIncident{
				ID:        fmt.Sprintf("disk_high_%s", nodeName),
				NodeName:  nodeName,
				Severity:  "warning",
				Message:   fmt.Sprintf("Armazenamento em disco crítico atingiu %d%% (%d GB / %d GB)", diskPct, telem.DiskUsedGB, telem.DiskTotalGB),
				StartedAt: now,
			})
		}
	}

	// 3. Checagem de Aplicações Degradadas no Swarm
	if cfg.NotifyDegradedApp && telem.UnhealthyApps > 0 {
		incidents = append(incidents, SentinelIncident{
			ID:        fmt.Sprintf("degraded_apps_%s", nodeName),
			NodeName:  nodeName,
			Severity:  "critical",
			Message:   fmt.Sprintf("%d aplicação(ões) operando em estado degradado ou instável no Docker Swarm", telem.UnhealthyApps),
			StartedAt: now,
		})
	}

	return incidents
}

// sentinelDaemon executa o ciclo em background de vigilância e emissão de alertas.
func (a *webApp) sentinelDaemon() {
	time.Sleep(5 * time.Second) // Aguarda inicialização completa dos serviços
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		a.sentinelMu.Lock()
		cfg := a.sentinelConfig
		enabled := cfg != nil && cfg.Enabled
		a.sentinelMu.Unlock()

		if !enabled {
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
		a.runSentinelCheckCycle(ctx)
		cancel()
	}
}

// runSentinelCheckCycle realiza uma rodada de verificação e notificação.
func (a *webApp) runSentinelCheckCycle(ctx context.Context) {
	a.sentinelMu.Lock()
	if a.sentinelConfig == nil {
		a.sentinelMu.Unlock()
		return
	}
	cfg := *a.sentinelConfig
	state := a.sentinelState
	a.sentinelMu.Unlock()

	if state == nil {
		return
	}

	fleetCfg, _ := a.fetchFleetConfig(ctx)
	if fleetCfg.FleetRole == "standby" {
		return // Torre Master em modo Standby (Cockpit Local): alertas autônomos silenciados para evitar duplicidade
	}

	state.mu.Lock()
	state.running = true
	state.lastCheck = time.Now().UTC()
	currentDetected := make(map[string]SentinelIncident)
	state.mu.Unlock()

	// 1. Avaliar nó local
	localTelem, err := a.fetchLocalTelemetry(ctx)
	if err == nil {
		nodeName := "Local"
		if localTelem.NodeID != "" && localTelem.NodeID != "local" {
			nodeName = localTelem.NodeID
		}
		incidents := evaluateSentinelTelemetry(nodeName, localTelem, &cfg)
		for _, inc := range incidents {
			currentDetected[inc.ID] = inc
		}
	}

	// 2. Se for Torre Master, avaliar nós da frota
	if a.fleetStore != nil {
		nodes := a.fleetStore.ListNodes()
		for _, n := range nodes {
			if n.Mode == FleetModeMaster {
				continue
			}
			// Checar se o nó está offline
			if cfg.NotifyNodeDown && (n.Status == "offline" || n.Status == "degraded") {
				incID := fmt.Sprintf("node_down_%s", n.ID)
				currentDetected[incID] = SentinelIncident{
					ID:        incID,
					NodeName:  n.Name,
					Severity:  "critical",
					Message:   fmt.Sprintf("Nó Operário remoto '%s' (%s) está inacessível ou desconectado da frota", n.Name, n.Endpoint),
					StartedAt: time.Now().UTC(),
				}
			}
			if n.Status == "mfa-blocked" {
				incID := fmt.Sprintf("node_mfa_%s", n.ID)
				currentDetected[incID] = SentinelIncident{
					ID:        incID,
					NodeName:  n.Name,
					Severity:  "warning",
					Message:   fmt.Sprintf("Nó Operário remoto '%s' está ativo, mas o Cloudflare Access (MFA) está bloqueando as consultas da Torre Master. Desative o MFA no nó ou configure regra de Bypass.", n.Name),
					StartedAt: time.Now().UTC(),
				}
			}

			// Se tiver telemetria do worker, avaliar métricas de capacidade
			if n.Telemetry != nil {
				workerIncidents := evaluateSentinelTelemetry(n.Name, *n.Telemetry, &cfg)
				for _, inc := range workerIncidents {
					currentDetected[inc.ID] = inc
				}
			}
		}
	}

	state.mu.Lock()
	now := time.Now().UTC()
	cooldownDuration := time.Duration(cfg.CooldownMinutes) * time.Minute
	confirmationDelay := time.Duration(cfg.ConfirmationDelaySec) * time.Second

	// Detectar novos incidentes ou re-notificar após cooldown
	for id, inc := range currentDetected {
		existing, found := state.incidents[id]
		shouldAlert := false
		if !found {
			// Novo incidente detectado: inicia em observação (janela de confirmação / histerese)
			existing = &sentinelIncidentState{
				Incident:    inc,
				FirstSeen:   now,
				LastAlertAt: time.Time{},
				AlertSent:   false,
			}
			state.incidents[id] = existing

			// Se o delay de confirmação for 0, alerta imediatamente
			if confirmationDelay <= 0 {
				existing.AlertSent = true
				existing.LastAlertAt = now
				shouldAlert = true
			}
		} else {
			// Incidente existente: atualiza objeto de incidente
			existing.Incident = inc

			if !existing.AlertSent {
				// Aguarda confirmação contínua pelo tempo de segurança para descartar oscilação temporária
				if now.Sub(existing.FirstSeen) >= confirmationDelay {
					existing.AlertSent = true
					existing.LastAlertAt = now
					shouldAlert = true
				}
			} else if now.Sub(existing.LastAlertAt) >= cooldownDuration {
				// Incidente persistente expirou o cooldown anti-flood.
				// Incidentes críticos (como nó offline ou RAM crítica) re-notificam após o cooldown.
				// Incidentes de severidade "warning" (como MFA bloqueando telemetria ou disco em atenção)
				// notificam apenas UMA VEZ por ocorrência para evitar fadiga de alertas e repetições contínuas.
				if existing.Incident.Severity != "warning" {
					existing.LastAlertAt = now
					shouldAlert = true
				}
			}
		}

		if shouldAlert {
			go func(incident SentinelIncident) {
				recs := a.dispatchSentinelNotification(context.Background(), incident, false, localTelem)
				state.mu.Lock()
				state.recentAlerts = append(state.recentAlerts, recs...)
				if len(state.recentAlerts) > 50 {
					state.recentAlerts = state.recentAlerts[len(state.recentAlerts)-50:]
				}
				state.mu.Unlock()
				a.addAudit("sentinel_alert_dispatched", fmt.Sprintf("Alerta Sentinel emitido para incidente %s (%s)", incident.ID, incident.Message), "sentinel-daemon")
			}(inc)
		}
	}

	// Detectar resolução de incidentes que não estão mais presentes
	for id, existing := range state.incidents {
		if _, stillActive := currentDetected[id]; !stillActive {
			// Incidente foi resolvido!
			delete(state.incidents, id)
			// Somente envia notificação de resolução se o alerta inicial tiver sido de fato emitido ao usuário
			if existing.AlertSent {
				go func(incident SentinelIncident) {
					recs := a.dispatchSentinelNotification(context.Background(), incident, true, localTelem)
					state.mu.Lock()
					state.recentAlerts = append(state.recentAlerts, recs...)
					if len(state.recentAlerts) > 50 {
						state.recentAlerts = state.recentAlerts[len(state.recentAlerts)-50:]
					}
					state.mu.Unlock()
					a.addAudit("sentinel_incident_resolved", fmt.Sprintf("Incidente Sentinel %s normalizado", incident.ID), "sentinel-daemon")
				}(existing.Incident)
			}
		}
	}

	state.mu.Unlock()
}

// handleSentinelGetConfig retorna a configuração sanitizada do Sentinel.
func (a *webApp) handleSentinelGetConfig(w http.ResponseWriter, _ *http.Request) {
	a.sentinelMu.Lock()
	cfg := a.sentinelConfig
	a.sentinelMu.Unlock()

	if cfg == nil {
		cfg = defaultSentinelConfig()
	}
	writeJSON(w, http.StatusOK, cfg.Sanitized())
}

// handleSentinelSaveConfig salva alterações na configuração do Sentinel.
func (a *webApp) handleSentinelSaveConfig(w http.ResponseWriter, r *http.Request) {
	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	var req SentinelConfig
	if err := decodeStrictJSON(data, &req); err != nil {
		writeError(w, http.StatusBadRequest, "payload JSON inválido")
		return
	}

	a.sentinelMu.Lock()
	current := a.sentinelConfig
	if current == nil {
		current = defaultSentinelConfig()
	}

	// Se o token do Telegram vier como máscara, preserva o token atual
	if strings.HasPrefix(req.TelegramBotToken, "***") || strings.Contains(req.TelegramBotToken, "...") {
		req.TelegramBotToken = current.TelegramBotToken
	}

	if err := req.Validate(); err != nil {
		a.sentinelMu.Unlock()
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	storePath := envDefault("SENTINEL_CONFIG_PATH", "/audit/sentinel_config.json")
	if err := saveSentinelConfig(storePath, &req); err != nil {
		a.sentinelMu.Unlock()
		writeError(w, http.StatusInternalServerError, "erro ao persistir configurações do Sentinel")
		return
	}

	a.sentinelConfig = &req
	a.sentinelMu.Unlock()

	a.addAudit("sentinel_config_updated", fmt.Sprintf("Configuração do Sentinel atualizada (Enabled=%v, RAM=%d%%, Webhook=%v)", req.Enabled, req.RAMThresholdPct, req.WebhookURL != ""), clientAddress(r))
	writeJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"config":  req.Sanitized(),
	})
}

// handleSentinelTestAlert dispara um alerta de teste em tempo real para os canais configurados.
func (a *webApp) handleSentinelTestAlert(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	data, err := io.ReadAll(io.LimitReader(r.Body, 16<<10))
	if err != nil {
		writeError(w, http.StatusBadRequest, "falha ao ler requisição")
		return
	}

	var testReq SentinelConfig
	if len(data) > 0 {
		_ = decodeStrictJSON(data, &testReq)
	}

	a.sentinelMu.Lock()
	active := a.sentinelConfig
	if active == nil {
		active = defaultSentinelConfig()
	}
	cfg := *active
	a.sentinelMu.Unlock()

	// Permite sobrescrever campos no teste para validação antes de salvar
	if testReq.WebhookURL != "" {
		cfg.WebhookURL = testReq.WebhookURL
	}
	if testReq.TelegramBotToken != "" && !strings.Contains(testReq.TelegramBotToken, "...") {
		cfg.TelegramBotToken = testReq.TelegramBotToken
	}
	if testReq.TelegramChatID != "" {
		cfg.TelegramChatID = testReq.TelegramChatID
	}

	if cfg.WebhookURL == "" && (cfg.TelegramBotToken == "" || cfg.TelegramChatID == "") {
		writeError(w, http.StatusBadRequest, "configure pelo menos uma URL de Webhook ou o Bot do Telegram para realizar o teste")
		return
	}

	testIncident := SentinelIncident{
		ID:        "test_connection",
		NodeName:  "Teste Manual MNO",
		Severity:  "warning",
		Message:   "🧪 Teste de conectividade do MNO Sentinel validado com sucesso a partir do Setup MNO Control Center!",
		StartedAt: time.Now().UTC(),
	}

	localTelem, _ := a.fetchLocalTelemetry(ctx)
	records := make([]SentinelAlertRecord, 0, 2)
	now := time.Now().UTC()

	if cfg.TelegramBotToken != "" && cfg.TelegramChatID != "" {
		err := sendTelegramAlert(ctx, cfg.TelegramBotToken, cfg.TelegramChatID,
			fmt.Sprintf("*🧪 [MNO SENTINEL TESTE]*\n\nConexão com o Telegram validada com sucesso pelo Setup MNO Control Center!\n*Horário:* %s UTC", now.Format("2006-01-02 15:04:05")))
		rec := SentinelAlertRecord{
			Timestamp: now,
			Target:    "telegram",
			Incident:  testIncident.ID,
			Success:   err == nil,
		}
		if err != nil {
			rec.Error = err.Error()
		}
		records = append(records, rec)
	}

	if cfg.WebhookURL != "" {
		err := sendWebhookAlert(ctx, cfg.WebhookURL, map[string]any{
			"provider":  "setup-mno-sentinel",
			"event":     "test_ping",
			"message":   testIncident.Message,
			"timestamp": now.Format(time.RFC3339),
			"telemetry": map[string]any{
				"memoryUsedMB":  localTelem.MemoryUsedMB,
				"memoryTotalMB": localTelem.MemoryTotalMB,
				"healthyApps":   localTelem.HealthyApps,
			},
			"content":   testIncident.Message,
			"text":      testIncident.Message,
		})
		rec := SentinelAlertRecord{
			Timestamp: now,
			Target:    "webhook",
			Incident:  testIncident.ID,
			Success:   err == nil,
		}
		if err != nil {
			rec.Error = err.Error()
		}
		records = append(records, rec)
	}

	a.addAudit("sentinel_test_executed", fmt.Sprintf("Teste manual do Sentinel executado (%d canais testados)", len(records)), clientAddress(r))
	writeJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"records": records,
	})
}

// handleSentinelGetStatus retorna o estado de vigilância, incidentes ativos e logs recentes.
func (a *webApp) handleSentinelGetStatus(w http.ResponseWriter, _ *http.Request) {
	a.sentinelMu.Lock()
	cfg := a.sentinelConfig
	state := a.sentinelState
	a.sentinelMu.Unlock()

	enabled := cfg != nil && cfg.Enabled
	if state == nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"enabled":         enabled,
			"running":         false,
			"lastCheck":       nil,
			"activeCount":     0,
			"activeIncidents": []SentinelIncident{},
			"recentAlerts":    []SentinelAlertRecord{},
		})
		return
	}

	state.mu.Lock()
	activeIncidents := make([]SentinelIncident, 0, len(state.incidents))
	for _, inc := range state.incidents {
		activeIncidents = append(activeIncidents, inc.Incident)
	}
	recent := make([]SentinelAlertRecord, len(state.recentAlerts))
	copy(recent, state.recentAlerts)
	lastCheck := state.lastCheck
	running := state.running
	state.mu.Unlock()

	writeJSON(w, http.StatusOK, map[string]any{
		"enabled":         enabled,
		"running":         running,
		"lastCheck":       lastCheck.Format(time.RFC3339),
		"activeCount":     len(activeIncidents),
		"activeIncidents": activeIncidents,
		"recentAlerts":    recent,
	})
}
