package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSentinelConfigDefaultsAndValidation(t *testing.T) {
	cfg := defaultSentinelConfig()
	if cfg.Enabled {
		t.Errorf("sentinel deveria iniciar desativado por padrão")
	}
	if cfg.RAMThresholdPct != 85 || cfg.DiskThresholdPct != 90 {
		t.Errorf("limiares padrão incorretos: %+v", cfg)
	}
	if cfg.CooldownMinutes != 15 {
		t.Errorf("cooldown padrão deveria ser 15 min, obteve %d", cfg.CooldownMinutes)
	}

	sanitized := cfg.Sanitized()
	if sanitized["telegramBotToken"] != "" {
		t.Errorf("token telegram mascarado incorreto: %v", sanitized["telegramBotToken"])
	}

	// Testar validação de URL inválida
	cfg.WebhookURL = "ftp://servidor-invalido.com"
	if err := cfg.Validate(); err == nil {
		t.Errorf("esperava erro para URL de webhook com esquema FTP")
	}

	cfg.WebhookURL = "https://n8n.meudominio.com.br/webhook/alerta"
	if err := cfg.Validate(); err != nil {
		t.Errorf("URL HTTPS válida deveria passar, obteve erro: %v", err)
	}
}

func TestSentinelConfigSaveAndLoad(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "sentinel-test-*")
	if err != nil {
		t.Fatalf("falha ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	configPath := filepath.Join(tempDir, "sentinel_config.json")
	cfg := &SentinelConfig{
		Enabled:           true,
		CheckIntervalSec:  45,
		RAMThresholdPct:   80,
		DiskThresholdPct:  88,
		NotifyDegradedApp: true,
		NotifyNodeDown:    true,
		WebhookURL:        "https://webhook.site/test-uuid",
		TelegramBotToken:  "123456789:ABCdefGHIjklMNOpqrSTUvwxYZ",
		TelegramChatID:    "-1001234567890",
		CooldownMinutes:   20,
	}

	if err := saveSentinelConfig(configPath, cfg); err != nil {
		t.Fatalf("saveSentinelConfig falhou: %v", err)
	}

	loaded, err := loadSentinelConfig(configPath)
	if err != nil {
		t.Fatalf("loadSentinelConfig falhou: %v", err)
	}

	if !loaded.Enabled || loaded.RAMThresholdPct != 80 || loaded.TelegramChatID != "-1001234567890" {
		t.Errorf("configuração carregada divergente: %+v", loaded)
	}

	sanitized := loaded.Sanitized()
	if !strings.HasPrefix(sanitized["telegramBotToken"].(string), "1234...") {
		t.Errorf("mascaramento de token falhou: %v", sanitized["telegramBotToken"])
	}
}

func TestEvaluateSentinelTelemetry(t *testing.T) {
	cfg := &SentinelConfig{
		Enabled:           true,
		RAMThresholdPct:   85,
		DiskThresholdPct:  90,
		NotifyDegradedApp: true,
	}

	// Cenário 1: Tudo saudável
	healthyTelem := FleetTelemetry{
		NodeID:        "node-01",
		MemoryUsedMB:  2048,
		MemoryTotalMB: 8192, // 25% uso
		DiskUsedGB:    20,
		DiskTotalGB:   100, // 20% uso
		HealthyApps:   4,
		UnhealthyApps: 0,
	}
	incidents := evaluateSentinelTelemetry("VPS-01", healthyTelem, cfg)
	if len(incidents) != 0 {
		t.Errorf("esperava 0 incidentes para telemetria saudável, obteve %d", len(incidents))
	}

	// Cenário 2: RAM estourada (> 85%) e aplicação degradada
	criticalTelem := FleetTelemetry{
		NodeID:        "node-01",
		MemoryUsedMB:  7500,
		MemoryTotalMB: 8192, // ~91% uso
		DiskUsedGB:    30,
		DiskTotalGB:   100,
		HealthyApps:   3,
		UnhealthyApps: 1, // 1 app caindo
	}
	incidents = evaluateSentinelTelemetry("VPS-01", criticalTelem, cfg)
	if len(incidents) != 2 {
		t.Fatalf("esperava 2 incidentes (RAM e app degradado), obteve %d: %+v", len(incidents), incidents)
	}

	hasRAM := false
	hasDegraded := false
	for _, inc := range incidents {
		if strings.HasPrefix(inc.ID, "ram_high_") {
			hasRAM = true
		}
		if strings.HasPrefix(inc.ID, "degraded_apps_") {
			hasDegraded = true
		}
	}
	if !hasRAM || !hasDegraded {
		t.Errorf("identificadores de incidente esperados ausentes: %+v", incidents)
	}
}

func TestSentinelHandlers(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "sentinel-handler-test-*")
	if err != nil {
		t.Fatalf("falha ao criar tempDir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	configPath := filepath.Join(tempDir, "sentinel_config.json")
	t.Setenv("SENTINEL_CONFIG_PATH", configPath)

	app := &webApp{
		sentinelConfig: defaultSentinelConfig(),
		sentinelState:  newSentinelRuntimeState(),
		sessions:       make(map[string]*session),
	}

	// 1. GET /api/sentinel/config
	req := httptest.NewRequest(http.MethodGet, "/api/sentinel/config", nil)
	w := httptest.NewRecorder()
	app.handleSentinelGetConfig(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("handleSentinelGetConfig retornou %d", w.Code)
	}

	// 2. POST /api/sentinel/config (Salvar nova configuração)
	savePayload := `{"enabled":true,"checkIntervalSec":30,"ramThresholdPct":80,"diskThresholdPct":85,"notifyDegradedApp":true,"notifyNodeDown":true,"webhookURL":"https://n8n.exemplo.com/hook","telegramBotToken":"123456:abcdef","telegramChatID":"999888","cooldownMinutes":10}`
	saveReq := httptest.NewRequest(http.MethodPost, "/api/sentinel/config", strings.NewReader(savePayload))
	saveW := httptest.NewRecorder()
	app.handleSentinelSaveConfig(saveW, saveReq)
	if saveW.Code != http.StatusOK {
		t.Fatalf("handleSentinelSaveConfig retornou %d (%s)", saveW.Code, saveW.Body.String())
	}

	if !app.sentinelConfig.Enabled || app.sentinelConfig.RAMThresholdPct != 80 {
		t.Errorf("configuração não foi atualizada no app: %+v", app.sentinelConfig)
	}

	// 3. GET /api/sentinel/status
	statusReq := httptest.NewRequest(http.MethodGet, "/api/sentinel/status", nil)
	statusW := httptest.NewRecorder()
	app.handleSentinelGetStatus(statusW, statusReq)
	if statusW.Code != http.StatusOK {
		t.Fatalf("handleSentinelGetStatus retornou %d", statusW.Code)
	}
}
