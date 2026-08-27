package main

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func testConsultativeRoute(intent, specialist, risk string, evidence ...string) assistantRoute {
	return assistantRoute{
		Intent:           intent,
		Specialist:       specialist,
		RiskLevel:        risk,
		Confidence:       "high",
		RequiredEvidence: evidence,
	}
}

func TestConsultativePlanBasicModeMakesMissingEvidenceVisible(t *testing.T) {
	route := testConsultativeRoute(
		"infrastructure_diagnosis", "infrastructure_diagnostician", "low",
		"runtime_state", "infrastructure_documentation",
	)
	plan := buildConsultativePlan(route, consultativePlanEvidence{
		OperationalContextAvailable: true,
		BasicMode:                   true,
	})
	if err := validateConsultativePlan(plan); err != nil {
		t.Fatalf("plano básico inválido: %v", err)
	}
	if plan.Status != "needs-evidence" || plan.Confidence != "low" || !plan.Hypothesis {
		t.Fatalf("evidência parcial não foi tratada como hipótese: %+v", plan)
	}
	if len(plan.MissingEvidence) != 1 || plan.MissingEvidence[0] != "documentação de infraestrutura" {
		t.Fatalf("evidência pendente incorreta: %#v", plan.MissingEvidence)
	}
	if plan.Executed || plan.Executable {
		t.Fatal("plano consultivo básico tornou-se executável")
	}
}

func TestConsultativePlanGroundedLowRiskIsReviewReady(t *testing.T) {
	route := testConsultativeRoute(
		"setup_guidance", "setup_specialist", "low",
		"catalog_entry", "setup_documentation", "architecture", "resources",
	)
	plan := buildConsultativePlan(route, consultativePlanEvidence{
		OperationalContextAvailable: true,
		CanonicalSourceCount:        3,
		Grounding: &groundingAudit{
			Grounded: true, Status: "citation-validated", CitedSources: 2, AvailableSources: 3,
		},
	})
	if err := validateConsultativePlan(plan); err != nil {
		t.Fatalf("plano fundamentado inválido: %v", err)
	}
	if plan.Status != "review-ready" || plan.EvidenceStatus != "validated" || plan.Confidence != "high" {
		t.Fatalf("plano fundamentado não ficou pronto para revisão: %+v", plan)
	}
	if len(plan.MissingEvidence) != 0 || plan.Hypothesis {
		t.Fatalf("plano fundamentado inventou pendência: %+v", plan)
	}
}

func TestConsultativePlanHighRiskAlwaysRequiresHumanReview(t *testing.T) {
	route := testConsultativeRoute(
		"security_review", "security_reviewer", "high",
		"runtime_state", "security_controls", "risks", "rollback",
	)
	plan := buildConsultativePlan(route, consultativePlanEvidence{
		OperationalContextAvailable: true,
		DeterministicAnswer:         true,
	})
	if err := validateConsultativePlan(plan); err != nil {
		t.Fatalf("plano de alto risco inválido: %v", err)
	}
	if plan.Status != "human-review" || !plan.RequiresHumanReview || plan.Confidence != "medium" {
		t.Fatalf("revisão humana não foi exigida: %+v", plan)
	}
	if !strings.Contains(strings.ToLower(plan.Rollback), "restaura") {
		t.Fatalf("rollback de alto risco não exige restauração: %q", plan.Rollback)
	}
}

func TestConsultativePlanScopeRedirectIsInformational(t *testing.T) {
	plan := buildConsultativePlan(
		testConsultativeRoute("scope_redirect", "scope_guard", "low"),
		consultativePlanEvidence{},
	)
	if err := validateConsultativePlan(plan); err != nil {
		t.Fatalf("plano de escopo inválido: %v", err)
	}
	if plan.Status != "informational" || plan.EvidenceStatus != "not-applicable" || plan.Hypothesis {
		t.Fatalf("redirecionamento de escopo incorreto: %+v", plan)
	}
}

func TestConsultativePlanRejectsExecutablePayload(t *testing.T) {
	plan := buildConsultativePlan(
		testConsultativeRoute("scope_redirect", "scope_guard", "low"),
		consultativePlanEvidence{},
	)
	plan.Executable = true
	if validateConsultativePlan(plan) == nil {
		t.Fatal("plano executável deveria ser rejeitado")
	}
}

func TestConsultativePlanSSEExposesClosedContract(t *testing.T) {
	recorder := httptest.NewRecorder()
	route := testConsultativeRoute(
		"knowledge_status", "setup_specialist", "low",
		"knowledge_manifest", "catalog_entry",
	)
	if !sendConsultativePlanSSE(recorder, route, consultativePlanEvidence{
		CanonicalSourceCount: 1,
		DeterministicAnswer:  true,
	}) {
		t.Fatal("evento consultivo deveria ser válido")
	}
	body := recorder.Body.String()
	for _, required := range []string{
		"event: plan", `"version":"1.0.0"`, `"maturity":"beta"`,
		`"executed":false`, `"executable":false`, "event: runbook",
		`"registryVersion":"1.0.0"`, `"automaticExecution":false`, `"freeCommandAllowed":false`,
	} {
		if !strings.Contains(body, required) {
			t.Fatalf("evento consultivo sem %q: %s", required, body)
		}
	}
}
