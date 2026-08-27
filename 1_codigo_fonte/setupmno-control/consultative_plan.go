package main

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
)

const (
	consultativePlanVersion  = "1.0.0"
	consultativePlanMaturity = "beta"
)

type consultativePlan struct {
	SchemaVersion       int      `json:"schemaVersion"`
	Version             string   `json:"version"`
	Maturity            string   `json:"maturity"`
	Status              string   `json:"status"`
	Intent              string   `json:"intent"`
	Specialist          string   `json:"specialist"`
	RiskLevel           string   `json:"riskLevel"`
	Confidence          string   `json:"confidence"`
	EvidenceStatus      string   `json:"evidenceStatus"`
	Diagnosis           string   `json:"diagnosis"`
	Impact              string   `json:"impact"`
	ObservedEvidence    []string `json:"observedEvidence"`
	MissingEvidence     []string `json:"missingEvidence"`
	Preconditions       []string `json:"preconditions"`
	Rollback            string   `json:"rollback"`
	Validation          string   `json:"validation"`
	NextSafeStep        string   `json:"nextSafeStep"`
	Hypothesis          bool     `json:"hypothesis"`
	RequiresHumanReview bool     `json:"requiresHumanReview"`
	Executed            bool     `json:"executed"`
	Executable          bool     `json:"executable"`
}

type consultativePlanEvidence struct {
	OperationalContextAvailable bool
	CanonicalSourceCount        int
	Grounding                   *groundingAudit
	DeterministicAnswer         bool
	BasicMode                   bool
}

var runtimePlanEvidence = map[string]bool{
	"runtime_state": true, "resources": true, "architecture": true,
	"diagnostics": true,
}

var canonicalPlanEvidence = map[string]bool{
	"security_controls": true, "risks": true, "rollback": true,
	"setup_documentation": true, "setup_requirements": true,
	"blueprint": true, "dependencies": true, "network": true,
	"catalog_entry": true, "infrastructure_documentation": true,
	"knowledge_manifest": true, "ecosystem_taxonomy": true,
	"solution_patterns": true,
}

func buildConsultativePlan(route assistantRoute, evidence consultativePlanEvidence) consultativePlan {
	plan := consultativePlan{
		SchemaVersion:       1,
		Version:             consultativePlanVersion,
		Maturity:            consultativePlanMaturity,
		Intent:              route.Intent,
		Specialist:          route.Specialist,
		RiskLevel:           route.RiskLevel,
		Diagnosis:           consultativeDiagnosis(route.Intent),
		Impact:              consultativeImpact(route.RiskLevel),
		Preconditions:       consultativePreconditions(route),
		Rollback:            consultativeRollback(route),
		Validation:          consultativeValidation(route),
		RequiresHumanReview: route.RiskLevel != "low",
		Executed:            false,
		Executable:          false,
	}

	if route.Intent == "scope_redirect" {
		plan.Status = "informational"
		plan.Confidence = "medium"
		plan.EvidenceStatus = "not-applicable"
		plan.ObservedEvidence = []string{"Roteamento local de escopo aplicado."}
		plan.NextSafeStep = "Reformular a pergunta dentro do escopo de Setup MNO ou infraestrutura."
		return plan
	}

	if evidence.OperationalContextAvailable {
		plan.ObservedEvidence = append(plan.ObservedEvidence, "Snapshot operacional sanitizado disponível.")
	}
	if evidence.DeterministicAnswer {
		plan.ObservedEvidence = append(plan.ObservedEvidence, "Resposta produzida por regra local determinística.")
	}
	if evidence.CanonicalSourceCount > 0 {
		plan.ObservedEvidence = append(plan.ObservedEvidence,
			fmt.Sprintf("%d fonte(s) canônica(s) selecionada(s) localmente.", evidence.CanonicalSourceCount))
	}
	if evidence.Grounding != nil && evidence.Grounding.Grounded {
		plan.ObservedEvidence = append(plan.ObservedEvidence, "Citações conferidas contra as fontes fornecidas à LLM.")
	}
	if evidence.BasicMode {
		plan.ObservedEvidence = append(plan.ObservedEvidence, "Diagnóstico Básico executado sem LLM externa.")
	}

	canonicalConfirmed := evidence.DeterministicAnswer ||
		(evidence.Grounding != nil && evidence.Grounding.Grounded)
	for _, required := range route.RequiredEvidence {
		confirmed := runtimePlanEvidence[required] && evidence.OperationalContextAvailable
		if canonicalPlanEvidence[required] && canonicalConfirmed {
			confirmed = true
		}
		if !confirmed {
			plan.MissingEvidence = append(plan.MissingEvidence, consultativeEvidenceLabel(required))
		}
	}

	switch {
	case len(plan.MissingEvidence) > 0:
		plan.EvidenceStatus = "insufficient"
		plan.Confidence = "low"
		plan.Status = "needs-evidence"
		plan.Hypothesis = true
		plan.RequiresHumanReview = true
		plan.NextSafeStep = "Coletar as evidências pendentes em modo somente leitura e submeter a conclusão à revisão humana."
	case route.RiskLevel == "high":
		plan.EvidenceStatus = "validated"
		plan.Confidence = "medium"
		plan.Status = "human-review"
		plan.RequiresHumanReview = true
		plan.NextSafeStep = "Revisar riscos, backup e rollback antes de abrir qualquer fluxo no Instalador Seguro."
	case route.RiskLevel == "medium":
		plan.EvidenceStatus = "validated"
		plan.Confidence = "medium"
		plan.Status = "human-review"
		plan.RequiresHumanReview = true
		plan.NextSafeStep = "Revisar o plano e confirmar a menor ação reversível fora do Assistente."
	default:
		plan.EvidenceStatus = "validated"
		plan.Confidence = route.Confidence
		if plan.Confidence != "high" {
			plan.Confidence = "medium"
		}
		plan.Status = "review-ready"
		plan.NextSafeStep = "Revisar a orientação e, se houver mudança, continuar pelo Instalador Seguro com confirmação humana."
	}

	return plan
}

func consultativeDiagnosis(intent string) string {
	switch intent {
	case "security_review":
		return "A solicitação exige revisão dos controles observados e dos riscos ainda não confirmados."
	case "troubleshooting":
		return "O sintoma foi classificado para diagnóstico; uma causa só pode ser confirmada por evidências compatíveis."
	case "capacity_planning":
		return "A decisão depende da capacidade observada e dos requisitos documentados da aplicação."
	case "blueprint_recommendation", "integration_design", "solution_design":
		return "A arquitetura é uma proposta consultiva e depende de compatibilidade, dependências e riscos confirmados."
	case "setup_guidance":
		return "A orientação compara o setup documentado com o contexto disponível; ela não inicia uma instalação."
	case "knowledge_status":
		return "A resposta descreve o inventário canônico disponível nesta versão."
	case "infrastructure_diagnosis":
		return "O estado da infraestrutura foi interpretado somente dentro da cobertura das evidências disponíveis."
	default:
		return "A consulta foi mantida fora do escopo operacional do Assistente MNO."
	}
}

func consultativeImpact(riskLevel string) string {
	switch riskLevel {
	case "high":
		return "Uma decisão incorreta pode afetar segurança, dados ou disponibilidade; nenhuma mudança deve ocorrer sem revisão humana."
	case "medium":
		return "Uma decisão incorreta pode degradar o serviço ou consumir recursos; prefira uma ação pequena e reversível."
	default:
		return "A resposta é informativa. Qualquer mudança posterior continua sujeita aos controles do Instalador Seguro."
	}
}

func consultativePreconditions(route assistantRoute) []string {
	if route.Intent == "scope_redirect" {
		return []string{"Manter a consulta dentro do escopo declarado do Assistente MNO."}
	}
	preconditions := []string{
		"Confirmar que as evidências exibidas ainda representam o estado atual.",
		"Não fornecer senhas, tokens, secrets ou logs brutos ao Assistente.",
	}
	if route.RiskLevel == "high" {
		preconditions = append(preconditions,
			"Comprovar backup consistente e restauração antes de qualquer mudança stateful.")
	}
	return preconditions
}

func consultativeRollback(route assistantRoute) string {
	if route.Intent == "scope_redirect" {
		return "Não se aplica: nenhuma ação foi proposta ou executada."
	}
	if route.RiskLevel == "high" {
		return "Registrar o estado anterior, preservar dados e comprovar restauração; sem rollback verificável, a mudança deve ser bloqueada."
	}
	return "Registrar o estado anterior e definir como restaurá-lo antes de qualquer alteração; esta resposta não executou mudança."
}

func consultativeValidation(route assistantRoute) string {
	if route.Intent == "scope_redirect" {
		return "Validar apenas se a nova pergunta pertence a Setup MNO ou infraestrutura."
	}
	return "Após uma ação autorizada fora do Assistente, comparar o resultado com o estado anterior, réplicas esperadas, saúde e objetivo declarado."
}

func consultativeEvidenceLabel(value string) string {
	labels := map[string]string{
		"runtime_state": "estado atual do runtime", "resources": "recursos atuais",
		"architecture": "arquitetura confirmada", "diagnostics": "diagnóstico compatível",
		"security_controls": "controles de segurança", "risks": "riscos confirmados",
		"rollback": "rollback verificável", "setup_documentation": "documentação do setup",
		"setup_requirements": "requisitos do setup", "blueprint": "Blueprint aplicável",
		"dependencies": "dependências confirmadas", "network": "topologia de rede",
		"catalog_entry":                "entrada canônica do catálogo",
		"infrastructure_documentation": "documentação de infraestrutura",
		"knowledge_manifest":           "manifesto da base de conhecimento",
		"ecosystem_taxonomy":           "taxonomia do ecossistema",
		"solution_patterns":            "padrões de solução",
	}
	if label := labels[value]; label != "" {
		return label
	}
	return value
}

func validateConsultativePlan(plan consultativePlan) error {
	if plan.SchemaVersion != 1 || plan.Version != consultativePlanVersion ||
		plan.Maturity != consultativePlanMaturity {
		return errors.New("versão do plano consultivo inválida")
	}
	allowedStatus := map[string]bool{
		"informational": true, "needs-evidence": true,
		"human-review": true, "review-ready": true,
	}
	allowedEvidenceStatus := map[string]bool{
		"not-applicable": true, "insufficient": true, "validated": true,
	}
	if !allowedStatus[plan.Status] || !allowedEvidenceStatus[plan.EvidenceStatus] {
		return errors.New("estado do plano consultivo inválido")
	}
	if plan.Confidence != "low" && plan.Confidence != "medium" && plan.Confidence != "high" {
		return errors.New("confiança do plano consultivo inválida")
	}
	if plan.Executed || plan.Executable {
		return errors.New("plano consultivo não pode ser executável")
	}
	if strings.TrimSpace(plan.Diagnosis) == "" || strings.TrimSpace(plan.Impact) == "" ||
		strings.TrimSpace(plan.Rollback) == "" || strings.TrimSpace(plan.Validation) == "" ||
		strings.TrimSpace(plan.NextSafeStep) == "" || len(plan.Preconditions) == 0 {
		return errors.New("plano consultivo incompleto")
	}
	if plan.EvidenceStatus == "insufficient" && (!plan.Hypothesis || len(plan.MissingEvidence) == 0) {
		return errors.New("evidência insuficiente sem hipótese explícita")
	}
	if plan.RiskLevel == "high" && (!plan.RequiresHumanReview || plan.Status != "human-review" && plan.Status != "needs-evidence") {
		return errors.New("plano de alto risco sem revisão humana")
	}
	if hasEmptyOrDuplicate(plan.ObservedEvidence) || hasEmptyOrDuplicate(plan.MissingEvidence) ||
		hasEmptyOrDuplicate(plan.Preconditions) {
		return errors.New("plano consultivo contém valor vazio ou duplicado")
	}
	return nil
}

func sendConsultativePlanSSE(w http.ResponseWriter, route assistantRoute, evidence consultativePlanEvidence) bool {
	return sendConsultativePlanAndRunbookSSE(w, route, evidence)
}
