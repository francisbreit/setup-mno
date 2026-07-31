package main

import (
	"encoding/json"
	"sort"
	"strings"
	"testing"
	"time"
)

func testKnowledgeRetriever(t *testing.T) (*knowledgeRetriever, knowledgePackageState) {
	t.Helper()
	state, err := loadKnowledgePackageDirectory("knowledge-package")
	if err != nil {
		t.Fatalf("pacote válido foi recusado: %v", err)
	}
	retriever, err := newKnowledgeRetriever(state)
	if err != nil {
		t.Fatalf("retriever recusou índice válido: %v", err)
	}
	return retriever, state
}

func TestShadowRetrievalFindsExactSetupAlias(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	result := retriever.retrieve(
		"Quais são os pré-requisitos do n8n sem fila?",
		state.Manifest.SetupVersion,
		"amd64",
	)
	if result.Metrics.Confidence != "high" ||
		result.Metrics.Fallback ||
		result.Metrics.ReturnedCount == 0 {
		t.Fatalf("resultado inesperado: %#v", result.Metrics)
	}
	if result.Metrics.CandidateCount > retrievalMaxCandidates ||
		len(result.Evidence) > retrievalMaxResults {
		t.Fatalf("limites de retrieval violados: %#v", result.Metrics)
	}
	perDocument := make(map[string]int)
	characters := 0
	for _, evidence := range result.Evidence {
		if !strings.Contains(evidence.DocumentID, "n8n-main") {
			t.Fatalf("setup alheio recuperado: %#v", evidence)
		}
		if evidence.TargetArchitecture != "amd64" {
			t.Fatalf("arquitetura divergente: %#v", evidence)
		}
		perDocument[evidence.DocumentID]++
		characters += len(evidence.Content)
	}
	for documentID, count := range perDocument {
		if count > retrievalMaxPerDoc {
			t.Fatalf("%s retornou %d chunks", documentID, count)
		}
	}
	if characters > retrievalMaxCharacters {
		t.Fatalf("contexto excedeu o limite: %d", characters)
	}
}

func TestShadowRetrievalResolvesInfrastructureSynonym(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	result := retriever.retrieve(
		"Explique a arquitetura do PostgreSQL",
		state.Manifest.SetupVersion,
		"amd64",
	)
	if result.Metrics.Confidence != "high" || len(result.Evidence) == 0 {
		t.Fatalf("sinônimo não foi recuperado: %#v", result.Metrics)
	}
	if !strings.Contains(result.Evidence[0].DocumentID, "infra-postgres") {
		t.Fatalf("documento inesperado: %#v", result.Evidence[0])
	}
}

func TestShadowRetrievalKeepsArchitectureLanesSeparated(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	result := retriever.retrieve(
		"Compare n8n sem fila em x86 e arm",
		state.Manifest.SetupVersion,
		"amd64",
	)
	architectures := make(map[string]bool)
	for _, evidence := range result.Evidence {
		architectures[evidence.TargetArchitecture] = true
	}
	if !architectures["amd64"] || !architectures["arm64"] {
		t.Fatalf("trilhas arquiteturais ausentes: %#v", architectures)
	}
	if !strings.Contains(result.Metrics.FilterType, "comparison") {
		t.Fatalf("comparação não sinalizada: %#v", result.Metrics)
	}
}

func TestShadowRetrievalRejectsStaleSetupVersion(t *testing.T) {
	retriever, _ := testKnowledgeRetriever(t)
	result := retriever.retrieve("n8n sem fila", "0.0.0", "amd64")
	if result.Metrics.ReturnedCount != 0 ||
		result.Metrics.Confidence != "none" ||
		len(result.Evidence) != 0 {
		t.Fatalf("documentação obsoleta foi aceita: %#v", result)
	}
}

func TestShadowRetrievalFallsBackToLegacyIndex(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	retriever.index.Chunks = nil
	result := retriever.retrieve(
		"requisitos n8n",
		state.Manifest.SetupVersion,
		"amd64",
	)
	if !result.Metrics.Fallback ||
		result.Metrics.FilterType != "legacy+architecture" ||
		result.Metrics.ReturnedCount == 0 {
		t.Fatalf("fallback v1 não foi usado: %#v", result.Metrics)
	}
}

func TestShadowMetricsContainNoQueryOrEvidence(t *testing.T) {
	service := assistantService{}
	service.recordRetrieval(retrievalMetrics{
		Version:          "1.0.0",
		DurationMS:       7,
		CandidateCount:   12,
		ReturnedCount:    4,
		Confidence:       "medium",
		FilterType:       "architecture",
		KnowledgeVersion: "1.2.1",
	})
	serialized, err := json.Marshal(service.retrievalSnapshot())
	if err != nil {
		t.Fatal(err)
	}
	payload := strings.ToLower(string(serialized))
	for _, forbidden := range []string{
		"question",
		"query",
		"content",
		"chunk",
		"alias",
		"hostname",
		"address",
	} {
		if strings.Contains(payload, forbidden) {
			t.Fatalf("telemetria contém campo proibido %q: %s", forbidden, payload)
		}
	}
}

func TestRetrievalTokenizerNormalizesPortugueseWithoutExpandingByLLM(t *testing.T) {
	terms := retrievalQueryTerms("Pré-requisitos do N8N, memória e automação.")
	joined := strings.Join(terms, ",")
	for _, expected := range []string{"automacao", "memoria", "n8n", "pre-requisitos"} {
		if !strings.Contains(joined, expected) {
			t.Fatalf("termo %q ausente em %v", expected, terms)
		}
	}
}

func TestShadowRetrievalP95StaysWithinLocalBudget(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	durations := make([]time.Duration, 200)
	for index := range durations {
		started := time.Now()
		_ = retriever.retrieve(
			"Quais são os pré-requisitos do n8n sem fila em x86?",
			state.Manifest.SetupVersion,
			"amd64",
		)
		durations[index] = time.Since(started)
	}
	sort.Slice(durations, func(left, right int) bool {
		return durations[left] < durations[right]
	})
	p95 := durations[(len(durations)*95/100)-1]
	t.Logf("retrieval local p95=%s para %d consultas", p95, len(durations))
	if p95 > 50*time.Millisecond {
		t.Fatalf("retrieval local p95 excedeu 50 ms: %s", p95)
	}
}
