package main

import (
	"encoding/json"
	"net/http"
	"sort"
	"strings"
)

const (
	resilienceSchemaVersion = 1
	resilienceMaturity      = "beta"
)

type PersistenceType string

const (
	PersistenceStateless      PersistenceType = "stateless"
	PersistenceDatabaseBacked PersistenceType = "database-backed"
	PersistenceVolumeBacked   PersistenceType = "volume-backed"
	PersistenceHybrid         PersistenceType = "hybrid"
)

type RiskLevel string

const (
	RiskLow      RiskLevel = "low"
	RiskMedium   RiskLevel = "medium"
	RiskHigh     RiskLevel = "high"
	RiskCritical RiskLevel = "critical"
)

type ResilienceChecklist struct {
	BackupReadiness      string `json:"backupReadiness"`      // "configured", "pending", "not-required"
	RestoreVerifiability string `json:"restoreVerifiability"` // "verified", "unverified", "not-required"
	UpdateSafety         string `json:"updateSafety"`         // "safe", "requires-backup", "schema-migration-risk"
	RollbackStrategy     string `json:"rollbackStrategy"`     // "image-rollback", "database-restore-required", "volume-snapshot-required", "coordinated-restore-required"
}

type ResilienceItem struct {
	SetupID          string              `json:"setupId"`
	CatalogName      string              `json:"catalogName"`
	PersistenceType  PersistenceType     `json:"persistenceType"`
	RiskLevel        RiskLevel           `json:"riskLevel"`
	Score            int                 `json:"score"` // 0 - 100
	Checklist        ResilienceChecklist `json:"checklist"`
	StorageLocations []string            `json:"storageLocations"`
	Recommendations  []string            `json:"recommendations"`
	RunbookID        string              `json:"runbookId,omitempty"`
}

type ResilienceSummary struct {
	TotalSetups    int     `json:"totalSetups"`
	StatelessCount int     `json:"statelessCount"`
	DatabaseCount  int     `json:"databaseCount"`
	VolumeCount    int     `json:"volumeCount"`
	HybridCount    int     `json:"hybridCount"`
	ResilientCount int     `json:"resilientCount"` // Score >= 80
	AttentionCount int     `json:"attentionCount"` // 50 <= Score < 80
	CriticalCount  int     `json:"criticalCount"`  // Score < 50
	AverageScore   float64 `json:"averageScore"`
}

type ResilienceResponse struct {
	SchemaVersion int               `json:"schemaVersion"`
	Maturity      string            `json:"maturity"`
	Summary       ResilienceSummary `json:"summary"`
	Items         []ResilienceItem  `json:"items"`
}

func evaluatePersistence(setupID, name, cats string) ResilienceItem {
	sID := strings.ToLower(strings.TrimSpace(setupID))
	sName := strings.ToUpper(strings.TrimSpace(name))
	sCats := strings.ToLower(cats)

	item := ResilienceItem{
		SetupID:     sID,
		CatalogName: sName,
		RunbookID:   "resilience-backup-audit",
	}

	// 1. Stateless detections
	if sID == "it-tools" || sID == "excalidraw" || sID == "stirling-pdf" || sID == "searxng" || sID == "dozzle" {
		item.PersistenceType = PersistenceStateless
		item.RiskLevel = RiskLow
		item.Score = 95
		item.Checklist = ResilienceChecklist{
			BackupReadiness:      "not-required",
			RestoreVerifiability: "not-required",
			UpdateSafety:         "safe",
			RollbackStrategy:     "image-rollback",
		}
		item.StorageLocations = []string{"memória/efêmero"}
		item.Recommendations = []string{
			"Aplicação stateless: atualização e rollback simples por imagem Docker.",
			"Nenhum volume persistente essencial no host.",
		}
		return item
	}

	// 2. Hybrid detections (Database + S3/MinIO or Multi-tier volume coordination)
	isHybrid := strings.Contains(sID, "chatwoot") ||
		strings.Contains(sID, "typebot") ||
		strings.Contains(sID, "evolution") ||
		strings.Contains(sID, "n8n") ||
		strings.Contains(sID, "evoai") ||
		strings.Contains(sID, "langfuse") ||
		sID == "dify" || sID == "activepieces" || sID == "flowise" ||
		sID == "ghost" || sID == "gitlab" || sID == "immich" ||
		sID == "nextcloud" || sID == "openproject" || sID == "penpot" ||
		sID == "rocketchat" || sID == "strapi" || sID == "twenty-crm" ||
		sID == "wordpress" || sID == "windmill" || sID == "discourse" ||
		sID == "humhub"

	if isHybrid {
		item.PersistenceType = PersistenceHybrid
		item.RiskLevel = RiskCritical
		item.Score = 65
		item.Checklist = ResilienceChecklist{
			BackupReadiness:      "pending",
			RestoreVerifiability: "unverified",
			UpdateSafety:         "schema-migration-risk",
			RollbackStrategy:     "coordinated-restore-required",
		}
		item.StorageLocations = []string{"PostgreSQL (postgres_db)", "MinIO / S3 Object Storage", "Docker Volumes (/var/lib/docker/volumes)"}
		item.Recommendations = []string{
			"Aplicação híbrida de alto impacto: exige backup transacional coordenado de banco SQL + mídias no storage.",
			"Antes de atualizar, gere dump completo do banco e snapshot do storage.",
			"Rollback simples de imagem NÃO é suficiente se houver migração de banco.",
		}
		return item
	}

	// 3. Database-backed detections
	isDatabase := strings.Contains(sCats, "banco de dados") ||
		strings.Contains(sCats, "vector db") ||
		strings.Contains(sCats, "bi") ||
		strings.Contains(sCats, "crm") ||
		strings.Contains(sCats, "sql") ||
		strings.Contains(sCats, "analytics") ||
		sID == "metabase" || sID == "baserow" || sID == "planka" ||
		sID == "actual-budget" || sID == "appsmith" || sID == "budibase" ||
		sID == "bytebase" || sID == "calcom" || sID == "directus" ||
		sID == "docmost" || sID == "documenso" || sID == "docuseal" ||
		sID == "firefly-iii" || sID == "formbricks" || sID == "gitea" ||
		sID == "heyform" || sID == "infisical" || sID == "keycloak" ||
		sID == "krayin-crm" || sID == "listmonk" || sID == "matomo" ||
		sID == "maybe" || sID == "nocobase" || sID == "nocodb" ||
		sID == "odoo" || sID == "plane" || sID == "pocketbase" ||
		sID == "pocket-id" || sID == "reactive-resume" || sID == "superset" ||
		sID == "tooljet" || sID == "triliumnext" || sID == "vikunja" ||
		sID == "wekan" || sID == "wiki-js" || sID == "woofed-crm" ||
		sID == "postgres" || sID == "mysql" || sID == "redis" ||
		sID == "clickhouse" || sID == "chromadb" || sID == "milvus-attu" ||
		sID == "neo4j" || sID == "memgraph" || sID == "weaviate" ||
		sID == "qdrant" || sID == "databasus" || sID == "mongodb"

	if isDatabase {
		item.PersistenceType = PersistenceDatabaseBacked
		item.RiskLevel = RiskMedium
		item.Score = 75
		item.Checklist = ResilienceChecklist{
			BackupReadiness:      "configured",
			RestoreVerifiability: "unverified",
			UpdateSafety:         "requires-backup",
			RollbackStrategy:     "database-restore-required",
		}
		item.StorageLocations = []string{"PostgreSQL (postgres_db) ou Volume de Banco"}
		item.Recommendations = []string{
			"Dependência de banco relacional/vetorial: faça dump com pg_dump antes de atualizações de versão.",
			"Restauração transacional restaura dados pontuais em caso de falha.",
		}
		return item
	}

	// 4. Default: Volume-backed
	item.PersistenceType = PersistenceVolumeBacked
	item.RiskLevel = RiskMedium
	item.Score = 70
	item.Checklist = ResilienceChecklist{
		BackupReadiness:      "pending",
		RestoreVerifiability: "unverified",
		UpdateSafety:         "requires-backup",
		RollbackStrategy:     "volume-snapshot-required",
	}
	item.StorageLocations = []string{"Docker Named Volume local"}
	item.Recommendations = []string{
		"Armazenamento persistente em volume do host: configure rotina de cópia com Duplicati ou tar.",
		"Teste periodicamente a descompactação e leitura do volume.",
	}
	return item
}

func collectResilienceReport(catalogData []byte) ResilienceResponse {
	var catalog []struct {
		Name string `json:"name"`
		Cats string `json:"cats"`
		Type string `json:"type"`
	}

	_ = json.Unmarshal(catalogData, &catalog)

	items := make([]ResilienceItem, 0, len(catalog))
	totalScore := 0
	resilientCount := 0
	attentionCount := 0
	criticalCount := 0
	statelessCount := 0
	databaseCount := 0
	volumeCount := 0
	hybridCount := 0

	for _, entry := range catalog {
		setupID := normalizeCatalogID(entry.Name)
		item := evaluatePersistence(setupID, entry.Name, entry.Cats)
		items = append(items, item)

		totalScore += item.Score
		switch item.PersistenceType {
		case PersistenceStateless:
			statelessCount++
		case PersistenceDatabaseBacked:
			databaseCount++
		case PersistenceVolumeBacked:
			volumeCount++
		case PersistenceHybrid:
			hybridCount++
		}

		if item.Score >= 80 {
			resilientCount++
		} else if item.Score >= 60 {
			attentionCount++
		} else {
			criticalCount++
		}
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].RiskLevel != items[j].RiskLevel {
			return riskWeight(items[i].RiskLevel) > riskWeight(items[j].RiskLevel)
		}
		return items[i].CatalogName < items[j].CatalogName
	})

	avgScore := 0.0
	if len(items) > 0 {
		avgScore = float64(totalScore) / float64(len(items))
	}

	summary := ResilienceSummary{
		TotalSetups:    len(items),
		StatelessCount: statelessCount,
		DatabaseCount:  databaseCount,
		VolumeCount:    volumeCount,
		HybridCount:    hybridCount,
		ResilientCount: resilientCount,
		AttentionCount: attentionCount,
		CriticalCount:  criticalCount,
		AverageScore:   avgScore,
	}

	return ResilienceResponse{
		SchemaVersion: resilienceSchemaVersion,
		Maturity:      resilienceMaturity,
		Summary:       summary,
		Items:         items,
	}
}

func riskWeight(risk RiskLevel) int {
	switch risk {
	case RiskCritical:
		return 4
	case RiskHigh:
		return 3
	case RiskMedium:
		return 2
	default:
		return 1
	}
}

func normalizeCatalogID(name string) string {
	lower := strings.ToLower(strings.TrimSpace(name))
	lower = strings.ReplaceAll(lower, " + ", "-")
	lower = strings.ReplaceAll(lower, "+", "-")
	lower = strings.ReplaceAll(lower, " ", "-")
	lower = strings.ReplaceAll(lower, "*", "")
	lower = strings.ReplaceAll(lower, "(", "")
	lower = strings.ReplaceAll(lower, ")", "")
	lower = strings.ReplaceAll(lower, "/", "-")
	lower = strings.ReplaceAll(lower, ".", "-")
	return strings.Trim(lower, "-")
}

func (app *webApp) handleResilience(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"método não permitido"}`, http.StatusMethodNotAllowed)
		return
	}

	catalogBytes, err := embeddedFiles.ReadFile("catalog.json")
	if err != nil {
		http.Error(w, `{"error":"catálogo indisponível"}`, http.StatusInternalServerError)
		return
	}

	resp := collectResilienceReport(catalogBytes)

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (app *webApp) handleResilienceSummary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"método não permitido"}`, http.StatusMethodNotAllowed)
		return
	}

	catalogBytes, err := embeddedFiles.ReadFile("catalog.json")
	if err != nil {
		http.Error(w, `{"error":"catálogo indisponível"}`, http.StatusInternalServerError)
		return
	}

	resp := collectResilienceReport(catalogBytes)

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"schemaVersion": resp.SchemaVersion,
		"maturity":      resp.Maturity,
		"summary":       resp.Summary,
	})
}
