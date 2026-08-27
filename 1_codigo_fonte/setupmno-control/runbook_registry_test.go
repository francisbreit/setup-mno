package main

import "testing"

func TestRunbookRegistryIsClosedReadOnlyAndHomologated(t *testing.T) {
	if len(homologatedRunbooks) != 3 {
		t.Fatalf("registro inesperado: %d runbooks", len(homologatedRunbooks))
	}
	seen := map[string]bool{}
	for _, item := range homologatedRunbooks {
		if seen[item.ID] {
			t.Fatalf("runbook duplicado: %s", item.ID)
		}
		seen[item.ID] = true
		if err := validateHomologatedRunbook(item); err != nil {
			t.Fatalf("runbook %s inválido: %v", item.ID, err)
		}
	}
}

func TestRunbookSelectionIsDeterministic(t *testing.T) {
	plan := buildConsultativePlan(
		testConsultativeRoute("security_review", "security_reviewer", "high", "security_controls"),
		consultativePlanEvidence{},
	)
	value := buildRunbookRecommendation(
		testConsultativeRoute("security_review", "security_reviewer", "high", "security_controls"), plan,
	)
	if err := validateRunbookRecommendation(value); err != nil {
		t.Fatalf("recomendação inválida: %v", err)
	}
	if value.Status != "recommended" || value.Runbook == nil || value.Runbook.ID != "security-baseline-review" {
		t.Fatalf("seleção incorreta: %+v", value)
	}
}

func TestRunbookRecommendationRejectsMutationAndFreeCommands(t *testing.T) {
	value := buildRunbookRecommendation(
		testConsultativeRoute("troubleshooting", "troubleshooter", "medium", "diagnostics"),
		consultativePlan{Status: "needs-evidence"},
	)
	value.Runbook.MutatesState = true
	if validateRunbookRecommendation(value) == nil {
		t.Fatal("runbook mutável deveria ser rejeitado")
	}
	value = buildRunbookRecommendation(
		testConsultativeRoute("troubleshooting", "troubleshooter", "medium", "diagnostics"),
		consultativePlan{Status: "needs-evidence"},
	)
	value.FreeCommandAllowed = true
	if validateRunbookRecommendation(value) == nil {
		t.Fatal("comando livre deveria ser rejeitado")
	}
}

func TestRunbookScopeRedirectDoesNotSelectOperation(t *testing.T) {
	value := buildRunbookRecommendation(
		testConsultativeRoute("scope_redirect", "scope_guard", "low"),
		consultativePlan{Status: "informational"},
	)
	if err := validateRunbookRecommendation(value); err != nil {
		t.Fatalf("redirecionamento inválido: %v", err)
	}
	if value.Status != "not-applicable" || value.Runbook != nil {
		t.Fatalf("consulta fora do escopo selecionou operação: %+v", value)
	}
}
