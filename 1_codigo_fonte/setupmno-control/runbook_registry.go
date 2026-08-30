package main

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
)

const (
	runbookRegistryVersion  = "1.0.0"
	runbookRegistryMaturity = "beta"
)

type homologatedRunbook struct {
	ID                 string   `json:"id"`
	Version            string   `json:"version"`
	Title              string   `json:"title"`
	Scope              string   `json:"scope"`
	MinimumPlan        string   `json:"minimumPlan"`
	Compatibility      []string `json:"compatibility"`
	PreChecks          []string `json:"preChecks"`
	DryRun             string   `json:"dryRun"`
	HumanConfirmation  string   `json:"humanConfirmation"`
	TimeoutSeconds     int      `json:"timeoutSeconds"`
	PostChecks         []string `json:"postChecks"`
	AuditEvent         string   `json:"auditEvent"`
	Rollback           string   `json:"rollback"`
	ExecutionMode      string   `json:"executionMode"`
	HandoffAction      string   `json:"handoffAction"`
	MutatesState       bool     `json:"mutatesState"`
	RequiresBackup     bool     `json:"requiresBackup"`
	AllowsParameters   bool     `json:"allowsParameters"`
	AutomaticExecution bool     `json:"automaticExecution"`
	HomologationStatus string   `json:"homologationStatus"`
	TestedEnvironments []string `json:"testedEnvironments"`
}

type runbookRecommendation struct {
	SchemaVersion      int                 `json:"schemaVersion"`
	RegistryVersion    string              `json:"registryVersion"`
	Maturity           string              `json:"maturity"`
	Status             string              `json:"status"`
	Reason             string              `json:"reason"`
	AutomaticExecution bool                `json:"automaticExecution"`
	FreeCommandAllowed bool                `json:"freeCommandAllowed"`
	Runbook            *homologatedRunbook `json:"runbook,omitempty"`
}

var homologatedRunbooks = []homologatedRunbook{
	{
		ID: "sre-evidence-collection", Version: "1.0.0", Title: "Coleta determinística de evidências",
		Scope:       "Coletar evidências sanitizadas quando o plano consultivo não possui cobertura suficiente.",
		MinimumPlan: "free", Compatibility: []string{"wsl2-amd64", "vps-amd64", "vps-arm64"},
		PreChecks:         []string{"Confirmar sessão administrativa autenticada.", "Confirmar que o Docker responde em modo somente leitura."},
		DryRun:            "Não se aplica: o runbook é somente leitura e não altera o servidor.",
		HumanConfirmation: "Obrigatória antes de abrir o Terminal Seguro.", TimeoutSeconds: 900,
		PostChecks: []string{"Validar o resumo sanitizado.", "Manter falhas e cobertura parcial visíveis."},
		AuditEvent: "sre_audit_requested", Rollback: "Não se aplica: nenhuma mudança de estado é autorizada.",
		ExecutionMode: "secure-terminal-handoff", HandoffAction: "sre",
		HomologationStatus: "homologated", TestedEnvironments: []string{"wsl2-amd64", "vps-arm64"},
	},
	{
		ID: "swarm-health-triage", Version: "1.0.0", Title: "Triagem de saúde do Docker Swarm",
		Scope:       "Reunir sinais agregados de serviços, recursos e motores SRE sem reiniciar ou atualizar containers.",
		MinimumPlan: "free", Compatibility: []string{"wsl2-amd64", "vps-amd64", "vps-arm64"},
		PreChecks:         []string{"Confirmar sessão administrativa autenticada.", "Confirmar que o Swarm está acessível."},
		DryRun:            "A própria execução é somente leitura; nenhum comando de correção integra este runbook.",
		HumanConfirmation: "Obrigatória antes de abrir o Terminal Seguro.", TimeoutSeconds: 900,
		PostChecks: []string{"Conferir cobertura dos três motores.", "Revisar limitações antes de concluir a causa."},
		AuditEvent: "sre_audit_requested", Rollback: "Não se aplica: nenhuma mudança de estado é autorizada.",
		ExecutionMode: "secure-terminal-handoff", HandoffAction: "sre",
		HomologationStatus: "homologated", TestedEnvironments: []string{"wsl2-amd64", "vps-arm64"},
	},
	{
		ID: "security-baseline-review", Version: "1.0.0", Title: "Revisão da linha de base de segurança",
		Scope:       "Executar Trivy, Lynis e Docker Bench e produzir somente contagens sanitizadas com validade de 24 horas.",
		MinimumPlan: "free", Compatibility: []string{"wsl2-amd64", "vps-amd64", "vps-arm64"},
		PreChecks:         []string{"Confirmar sessão administrativa autenticada.", "Aceitar os limites de cobertura do ambiente."},
		DryRun:            "Não se aplica: os motores são executados em modo somente leitura.",
		HumanConfirmation: "Obrigatória antes de abrir o Terminal Seguro.", TimeoutSeconds: 900,
		PostChecks: []string{"Verificar motores sem falha.", "Distinguir aviso de vulnerabilidade confirmada."},
		AuditEvent: "sre_audit_requested", Rollback: "Não se aplica: nenhuma correção é executada.",
		ExecutionMode: "secure-terminal-handoff", HandoffAction: "sre",
		HomologationStatus: "homologated", TestedEnvironments: []string{"wsl2-amd64", "vps-arm64"},
	},
	{
		ID: "resilience-backup-audit", Version: "1.0.0", Title: "Auditoria de resiliência e backup",
		Scope:       "Verificar integridade e idade de dumps do PostgreSQL e volumes Docker sem expor credenciais.",
		MinimumPlan: "free", Compatibility: []string{"wsl2-amd64", "vps-amd64", "vps-arm64"},
		PreChecks:         []string{"Confirmar sessão administrativa autenticada.", "Confirmar acesso somente leitura aos metadados de backup."},
		DryRun:            "Não se aplica: a checagem é consultiva e somente leitura.",
		HumanConfirmation: "Obrigatória antes de abrir o Terminal Seguro.", TimeoutSeconds: 900,
		PostChecks: []string{"Validar lista de backups encontrados.", "Registrar idade e status dos volumes."},
		AuditEvent: "sre_audit_requested", Rollback: "Não se aplica: nenhuma alteração é feita no disco.",
		ExecutionMode: "secure-terminal-handoff", HandoffAction: "sre",
		HomologationStatus: "homologated", TestedEnvironments: []string{"wsl2-amd64", "vps-arm64"},
	},
	{
		ID: "resilience-recovery-checklist", Version: "1.0.0", Title: "Guia de restauração e rollback de dados",
		Scope:       "Checklist consultivo e ordenado de recuperação de estado e rollback seguro por aplicação.",
		MinimumPlan: "free", Compatibility: []string{"wsl2-amd64", "vps-amd64", "vps-arm64"},
		PreChecks:         []string{"Confirmar sessão administrativa autenticada.", "Identificar o tipo de persistência da aplicação."},
		DryRun:            "Não se aplica: guia consultivo estruturado.",
		HumanConfirmation: "Obrigatória antes de abrir o Terminal Seguro.", TimeoutSeconds: 900,
		PostChecks: []string{"Conferir integridade do banco restaurado.", "Validar comunicação dos serviços dependentes."},
		AuditEvent: "sre_audit_requested", Rollback: "Não se aplica: execução assistida pelo operador.",
		ExecutionMode: "secure-terminal-handoff", HandoffAction: "sre",
		HomologationStatus: "homologated", TestedEnvironments: []string{"wsl2-amd64", "vps-arm64"},
	},
}

func findHomologatedRunbook(id string) *homologatedRunbook {
	for _, item := range homologatedRunbooks {
		if item.ID == id {
			copy := item
			return &copy
		}
	}
	return nil
}

func buildRunbookRecommendation(route assistantRoute, plan consultativePlan) runbookRecommendation {
	recommendation := runbookRecommendation{
		SchemaVersion: 1, RegistryVersion: runbookRegistryVersion, Maturity: runbookRegistryMaturity,
		Status: "unavailable", Reason: "Nenhum runbook homologado corresponde a esta orientação.",
		AutomaticExecution: false, FreeCommandAllowed: false,
	}
	if route.Intent == "scope_redirect" {
		recommendation.Status = "not-applicable"
		recommendation.Reason = "A consulta está fora do escopo operacional; nenhum runbook foi selecionado."
		return recommendation
	}

	selectedID := ""
	switch route.Intent {
	case "security_review":
		selectedID = "security-baseline-review"
	case "troubleshooting":
		selectedID = "swarm-health-triage"
	case "infrastructure_diagnosis", "capacity_planning":
		if plan.Status == "needs-evidence" {
			selectedID = "swarm-health-triage"
		}
	default:
		if plan.Status == "needs-evidence" {
			selectedID = "sre-evidence-collection"
		}
	}
	if selectedID == "" {
		return recommendation
	}
	recommendation.Status = "recommended"
	recommendation.Reason = "O roteador local encontrou um runbook fechado e somente leitura compatível com a evidência pendente."
	recommendation.Runbook = findHomologatedRunbook(selectedID)
	return recommendation
}

func validateHomologatedRunbook(item homologatedRunbook) error {
	if strings.TrimSpace(item.ID) == "" || strings.TrimSpace(item.Version) == "" || strings.TrimSpace(item.Title) == "" ||
		strings.TrimSpace(item.Scope) == "" || strings.TrimSpace(item.MinimumPlan) == "" || item.TimeoutSeconds < 1 || item.TimeoutSeconds > 1800 {
		return errors.New("metadados do runbook inválidos")
	}
	if item.ExecutionMode != "secure-terminal-handoff" || item.HandoffAction != "sre" ||
		item.MutatesState || item.RequiresBackup || item.AllowsParameters || item.AutomaticExecution ||
		item.HomologationStatus != "homologated" {
		return errors.New("runbook fora da fronteira somente leitura homologada")
	}
	if hasEmptyOrDuplicate(item.Compatibility) || hasEmptyOrDuplicate(item.PreChecks) ||
		hasEmptyOrDuplicate(item.PostChecks) || hasEmptyOrDuplicate(item.TestedEnvironments) ||
		len(item.Compatibility) == 0 || len(item.PreChecks) == 0 || len(item.PostChecks) == 0 || len(item.TestedEnvironments) == 0 {
		return errors.New("listas do runbook inválidas")
	}
	for _, value := range []string{item.DryRun, item.HumanConfirmation, item.AuditEvent, item.Rollback} {
		if strings.TrimSpace(value) == "" {
			return errors.New("contrato do runbook incompleto")
		}
	}
	return nil
}

func validateRunbookRecommendation(value runbookRecommendation) error {
	if value.SchemaVersion != 1 || value.RegistryVersion != runbookRegistryVersion || value.Maturity != runbookRegistryMaturity {
		return errors.New("versão do registro de runbooks inválida")
	}
	if value.AutomaticExecution || value.FreeCommandAllowed {
		return errors.New("recomendação de runbook não pode autorizar execução automática ou comando livre")
	}
	if strings.TrimSpace(value.Reason) == "" {
		return errors.New("recomendação de runbook sem justificativa")
	}
	switch value.Status {
	case "recommended":
		if value.Runbook == nil {
			return errors.New("runbook recomendado ausente")
		}
		return validateHomologatedRunbook(*value.Runbook)
	case "unavailable", "not-applicable":
		if value.Runbook != nil {
			return fmt.Errorf("estado %s não pode selecionar runbook", value.Status)
		}
		return nil
	default:
		return errors.New("estado da recomendação de runbook inválido")
	}
}

func sendConsultativePlanAndRunbookSSE(w http.ResponseWriter, route assistantRoute, evidence consultativePlanEvidence) bool {
	plan := buildConsultativePlan(route, evidence)
	if err := validateConsultativePlan(plan); err != nil {
		return false
	}
	recommendation := buildRunbookRecommendation(route, plan)
	if err := validateRunbookRecommendation(recommendation); err != nil {
		return false
	}
	sendSSE(w, "plan", plan)
	sendSSE(w, "runbook", recommendation)
	return true
}
