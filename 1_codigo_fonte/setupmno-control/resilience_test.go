package main

import (
	"encoding/json"
	"testing"
)

func TestEvaluatePersistenceStateless(t *testing.T) {
	item := evaluatePersistence("it-tools", "IT-TOOLS", "Utilitário, Ferramentas")
	if item.PersistenceType != PersistenceStateless {
		t.Fatalf("esperava stateless, obteve %s", item.PersistenceType)
	}
	if item.RiskLevel != RiskLow {
		t.Fatalf("esperava risco low, obteve %s", item.RiskLevel)
	}
	if item.Checklist.RollbackStrategy != "image-rollback" {
		t.Fatalf("esperava rollback de imagem, obteve %s", item.Checklist.RollbackStrategy)
	}
}

func TestEvaluatePersistenceHybrid(t *testing.T) {
	item := evaluatePersistence("chatwoot-evolution-rabbitmq-minio", "CHATWOOT + EVOLUTION + MINIO", "Atendimento, WhatsApp, Storage")
	if item.PersistenceType != PersistenceHybrid {
		t.Fatalf("esperava hybrid, obteve %s", item.PersistenceType)
	}
	if item.RiskLevel != RiskCritical {
		t.Fatalf("esperava risco critical, obteve %s", item.RiskLevel)
	}
	if item.Checklist.RollbackStrategy != "coordinated-restore-required" {
		t.Fatalf("esperava coordinated-restore-required, obteve %s", item.Checklist.RollbackStrategy)
	}
}

func TestEvaluatePersistenceDatabase(t *testing.T) {
	item := evaluatePersistence("metabase", "METABASE", "BI, Dashboards, Análise de Dados")
	if item.PersistenceType != PersistenceDatabaseBacked {
		t.Fatalf("esperava database-backed, obteve %s", item.PersistenceType)
	}
	if item.RiskLevel != RiskMedium {
		t.Fatalf("esperava risco medium, obteve %s", item.RiskLevel)
	}
}

func TestCollectResilienceReportSummary(t *testing.T) {
	catalogJSON := `[
		{"name": "IT-TOOLS", "cats": "Utilitário", "type": "Utilitário"},
		{"name": "CHATWOOT", "cats": "Atendimento, WhatsApp", "type": "Individual"},
		{"name": "METABASE", "cats": "BI, SQL", "type": "Individual"},
		{"name": "FILEBROWSER", "cats": "Arquivos", "type": "Utilitário"}
	]`

	resp := collectResilienceReport([]byte(catalogJSON))
	if resp.SchemaVersion != 1 {
		t.Fatalf("esperava schema 1, obteve %d", resp.SchemaVersion)
	}
	if resp.Summary.TotalSetups != 4 {
		t.Fatalf("esperava 4 setups, obteve %d", resp.Summary.TotalSetups)
	}
	if resp.Summary.StatelessCount != 1 {
		t.Fatalf("esperava 1 stateless, obteve %d", resp.Summary.StatelessCount)
	}
	if resp.Summary.HybridCount != 1 {
		t.Fatalf("esperava 1 hybrid, obteve %d", resp.Summary.HybridCount)
	}
	if resp.Summary.DatabaseCount != 1 {
		t.Fatalf("esperava 1 database, obteve %d", resp.Summary.DatabaseCount)
	}
	if resp.Summary.VolumeCount != 1 {
		t.Fatalf("esperava 1 volume, obteve %d", resp.Summary.VolumeCount)
	}
	if resp.Summary.AverageScore <= 0 {
		t.Fatalf("esperava average score > 0, obteve %f", resp.Summary.AverageScore)
	}

	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("falha ao serializar json: %v", err)
	}
	if len(data) == 0 {
		t.Fatal("json vazio")
	}
}
