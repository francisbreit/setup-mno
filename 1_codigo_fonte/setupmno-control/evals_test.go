package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCanonicalEvalSuitePasses(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	for _, item := range state.Evals.Cases {
		resolution := retriever.resolveQuery(item.Question, nil)
		if item.ExpectedBlueprint != nil {
			resolution.BlueprintRoute = true
		}
		route := routeAssistant(item.Question, resolution, item.Architecture)
		if route.Intent != item.IntentionExpected || route.Specialist != item.SpecialistExpected {
			t.Errorf(
				"%s: rota=%s/%s esperada=%s/%s",
				item.CaseID, route.Intent, route.Specialist,
				item.IntentionExpected, item.SpecialistExpected,
			)
		}
	}
	report, err := runEvalSuite(state, state.Manifest.ControlVersion)
	if err != nil {
		t.Fatal(err)
	}
	if report.Status != "passed" {
		t.Fatalf("gate de evals falhou: %#v", report.Metrics)
	}
	if report.CaseCount != evalExpectedCases || report.RetrievalCases != 656 ||
		report.RoutingCases != 4 || report.Metrics.RecallAt5 < 90 {
		t.Fatalf("relatório de evals incompleto: %#v", report)
	}
}

func TestEvalReportContainsOnlyAggregateSafeData(t *testing.T) {
	_, state := testKnowledgeRetriever(t)
	report, err := runEvalSuite(state, state.Manifest.ControlVersion)
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(report)
	if err != nil {
		t.Fatal(err)
	}
	payload := strings.ToLower(string(encoded))
	for _, forbidden := range []string{
		"question", "referenceanswer", "expecteddocuments", "requiredfacts",
		"forbiddenclaims", "hostname", "password=", "api_key=", "sk-proj-",
	} {
		if strings.Contains(payload, forbidden) {
			t.Fatalf("relatório agregado contém campo proibido %q: %s", forbidden, payload)
		}
	}
}

func TestEvalDatasetTamperingIsRejected(t *testing.T) {
	_, state := testKnowledgeRetriever(t)
	data := append([]byte(nil), state.Files["evals/dataset.json"]...)
	data[len(data)/2] ^= 1
	if _, err := validateEvalDataset(data, state.Manifest); err == nil {
		t.Fatal("dataset adulterado foi aceito")
	}
}

func TestEvalGradersRejectUnsafeResponseAndBadRanking(t *testing.T) {
	recall, precision, reciprocal, averagePrecision := gradeEvalRetrieval(
		[]string{"documento-errado"},
		[]string{"documento-esperado"},
	)
	if recall != 0 || precision != 0 || reciprocal != 0 || averagePrecision != 0 {
		t.Fatalf("ranking incorreto foi aprovado: %v %v %v %v", recall, precision, reciprocal, averagePrecision)
	}
	if !containsCredentialLikeValue("password=valor-de-teste") {
		t.Fatal("grader não detectou atribuição semelhante a credencial")
	}
}
