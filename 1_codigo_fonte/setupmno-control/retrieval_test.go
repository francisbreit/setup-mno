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
	retriever, err := newKnowledgeRetriever(state, true)
	if err != nil {
		t.Fatalf("retriever recusou índice válido: %v", err)
	}
	return retriever, state
}

func TestBlueprintFixtureUsesSameControlledRetrievalPath(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	resolution := retriever.resolveQuery(
		"Explique o blueprint-001-whatsapp-marketing-completo e a ordem segura",
		nil,
	)
	resolution.BlueprintRoute = true
	if resolution.BlueprintID != "blueprint-001-whatsapp-marketing-completo" {
		t.Fatalf("Blueprint exato não foi resolvido: %#v", resolution)
	}
	result := retriever.retrieveResolved(
		resolution, state.Manifest.SetupVersion, "amd64",
	)
	if result.Metrics.Confidence != "high" || len(result.Evidence) == 0 ||
		!strings.Contains(result.Metrics.FilterType, "blueprint+exact+homologation") {
		t.Fatalf("fixture não percorreu o retrieval controlado: %#v", result)
	}
	found := false
	for _, evidence := range result.Evidence {
		if evidence.DocumentType != "blueprint" {
			t.Fatalf("fonte externa contaminou Blueprint exato: %#v", evidence)
		}
		if evidence.BlueprintID != "blueprint-001-whatsapp-marketing-completo" ||
			!evidence.Fictitious || evidence.Deployable || evidence.Status != "reviewed" {
			t.Fatalf("metadados inseguros na fixture recuperada: %#v", evidence)
		}
		found = true
	}
	if !found {
		t.Fatalf("documento esperado não foi recuperado: %#v", result.Evidence)
	}
	prompt, status := buildRetrievalPrompt(result)
	if status != "active" || prompt == nil || !prompt.Simulation ||
		prompt.Mode != "blueprint-homologation" ||
		!containsString(prompt.BlueprintIDs, "blueprint-001-whatsapp-marketing-completo") {
		t.Fatalf("fixture não chegou ao prompt equivalente: status=%s prompt=%#v", status, prompt)
	}
	inspection := buildRetrievalInspection(result, state.Manifest.SetupVersion, "image-read-only", false)
	if !inspection.Simulation ||
		!containsString(inspection.BlueprintIDs, "blueprint-001-whatsapp-marketing-completo") {
		t.Fatalf("inspeção não sinalizou simulação: %#v", inspection)
	}
}

func TestBlueprintFixturesResolveAndRetrieveWithoutCrossContamination(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	cases := []struct {
		question    string
		blueprintID string
	}{
		{"Explique o blueprint-001-whatsapp-marketing-completo", "blueprint-001-whatsapp-marketing-completo"},
		{"Quais são os componentes do Blueprint de automação de negócios?", "blueprint-002-automacao-negocios"},
		{"Mostre a topologia do Blueprint de base de conhecimento com IA e RAG", "blueprint-003-base-conhecimento-rag"},
		{"Como validar o Blueprint de observabilidade completa?", "blueprint-004-observabilidade-monitoramento"},
		{"Quais são os riscos do Blueprint para servidor com pouca memória?", "blueprint-005-servidor-pequeno"},
	}
	for _, testCase := range cases {
		t.Run(testCase.blueprintID, func(t *testing.T) {
			resolution := retriever.resolveQuery(testCase.question, nil)
			resolution.BlueprintRoute = true
			if resolution.BlueprintID != testCase.blueprintID || len(resolution.BlueprintIDs) != 1 {
				t.Fatalf("resolução inexata: %#v", resolution)
			}
			result := retriever.retrieveResolved(
				resolution, state.Manifest.SetupVersion, "amd64",
			)
			if len(result.Evidence) == 0 || !strings.Contains(result.Metrics.FilterType, "blueprint+exact+homologation") {
				t.Fatalf("retrieval exato ausente: %#v", result)
			}
			for _, evidence := range result.Evidence {
				if evidence.DocumentType != "blueprint" || evidence.BlueprintID != testCase.blueprintID {
					t.Fatalf("contaminação cruzada: esperado=%s evidência=%#v", testCase.blueprintID, evidence)
				}
			}
		})
	}
}

func TestBlueprintFixturesAreBlockedOutsideHomologationAndSpecialist(t *testing.T) {
	state, err := loadKnowledgePackageDirectory("knowledge-package")
	if err != nil {
		t.Fatal(err)
	}
	disabled, err := newKnowledgeRetriever(state, false)
	if err != nil {
		t.Fatal(err)
	}
	for name, retrieverAndRoute := range map[string]struct {
		retriever *knowledgeRetriever
		route     bool
	}{
		"homologation-disabled": {retriever: disabled, route: true},
		"wrong-specialist":      {retriever: testRetrieverFromState(t, state, true), route: false},
	} {
		t.Run(name, func(t *testing.T) {
			result := retrieverAndRoute.retriever.retrieveResolved(
				retrievalQueryResolution{
					Query:          "blueprint-001-whatsapp-marketing-completo",
					BlueprintRoute: retrieverAndRoute.route,
				},
				state.Manifest.SetupVersion,
				"amd64",
			)
			for _, evidence := range result.Evidence {
				if evidence.DocumentType == "blueprint" || evidence.Fictitious {
					t.Fatalf("fixture atravessou o gate: %#v", evidence)
				}
			}
		})
	}
}

func testRetrieverFromState(
	t *testing.T,
	state knowledgePackageState,
	homologation bool,
) *knowledgeRetriever {
	t.Helper()
	retriever, err := newKnowledgeRetriever(state, homologation)
	if err != nil {
		t.Fatal(err)
	}
	return retriever
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
	chunks := make(map[string]bool)
	for _, evidence := range result.Evidence {
		for _, architecture := range strings.Split(evidence.TargetArchitecture, ",") {
			architectures[architecture] = true
		}
		if chunks[evidence.ChunkID] {
			t.Fatalf("chunk duplicado entre arquiteturas: %s", evidence.ChunkID)
		}
		chunks[evidence.ChunkID] = true
	}
	if !architectures["amd64"] || !architectures["arm64"] {
		t.Fatalf("trilhas arquiteturais ausentes: %#v", architectures)
	}
	if !strings.Contains(result.Metrics.FilterType, "comparison") {
		t.Fatalf("comparação não sinalizada: %#v", result.Metrics)
	}
}

func TestContextualSetupReferenceUsesPreviousUserTurn(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	history := []assistantMessage{
		{Role: "user", Content: "O n8n sem fila funciona em ARM e x86?"},
		{Role: "assistant", Content: "Resposta anterior sobre o n8n."},
	}
	resolution := retriever.resolveQuery(
		"Este setup é compatível com meu servidor amd64?", history,
	)
	if resolution.SetupID != "n8n-main" || !resolution.Contextualized ||
		resolution.CatalogName != "N8N V1 - SEM FILA (MAIN)" {
		t.Fatalf("referência contextual não resolvida: %#v", resolution)
	}
	result := retriever.retrieveResolved(
		resolution, state.Manifest.SetupVersion, "amd64",
	)
	contextData := assistantContext{
		CatalogVersion: "5.0.0",
		CatalogSHA256:  strings.Repeat("c", 64),
		RelevantSetups: []map[string]any{{
			"name": "N8N V1 - SEM FILA (MAIN)", "arch": "x86-arm",
			"ramLabel": "~8GB", "type": "Individual", "desc": "Automação visual.",
		}},
	}
	result = retriever.attachCatalogEvidence(result, contextData)
	if len(result.Evidence) == 0 || result.Evidence[0].DocumentType != "catalog" {
		t.Fatalf("catálogo exato não foi priorizado: %#v", result.Evidence)
	}
	for _, evidence := range result.Evidence {
		if evidence.SetupID != "n8n-main" {
			t.Fatalf("evidência de outro setup atravessou o gate: %#v", evidence)
		}
	}
	prompt, status := buildRetrievalPrompt(result)
	if prompt == nil || status != "active" {
		t.Fatalf("contexto relevante foi recusado: %s %#v", status, prompt)
	}
}

func TestContextualArchitectureQuestionDoesNotRetrieveOtherSetups(t *testing.T) {
	retriever, state := testKnowledgeRetriever(t)
	resolution := retriever.resolveQuery(
		"Quais diferenças de arquitetura existem para instalar este setup?",
		[]assistantMessage{{Role: "user", Content: "Quais são os requisitos do n8n sem fila?"}},
	)
	result := retriever.retrieveResolved(
		resolution, state.Manifest.SetupVersion, "amd64",
	)
	for _, evidence := range result.Evidence {
		if evidence.SetupID != "n8n-main" ||
			strings.Contains(evidence.DocumentID, "appsmith") ||
			strings.Contains(evidence.DocumentID, "grafana") ||
			strings.Contains(evidence.DocumentID, "qdrant") {
			t.Fatalf("setup alheio recuperado: %#v", evidence)
		}
	}
}

func TestExplicitSetupOverridesConversationContext(t *testing.T) {
	retriever, _ := testKnowledgeRetriever(t)
	resolution := retriever.resolveQuery(
		"O Appsmith é compatível com este servidor?",
		[]assistantMessage{{Role: "user", Content: "Quais são os requisitos do n8n sem fila?"}},
	)
	if resolution.SetupID != "appsmith" || resolution.Contextualized {
		t.Fatalf("setup explícito não prevaleceu: %#v", resolution)
	}
}

func TestContextualReferenceWithoutUserAntecedentStaysUnresolved(t *testing.T) {
	retriever, _ := testKnowledgeRetriever(t)
	resolution := retriever.resolveQuery(
		"Este setup funciona em ARM?",
		[]assistantMessage{{Role: "assistant", Content: "O Appsmith funciona em ARM."}},
	)
	if resolution.SetupID != "" || resolution.Contextualized ||
		resolution.Query != "Este setup funciona em ARM?" {
		t.Fatalf("conteúdo do assistente foi aceito como antecedente: %#v", resolution)
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

func TestRetrievalInspectionIsBoundedAndContainsOnlyCanonicalEvidence(t *testing.T) {
	result := retrievalResult{
		Metrics: retrievalMetrics{
			Version:          "1.0.0",
			DurationMS:       9,
			CandidateCount:   12,
			ReturnedCount:    8,
			Confidence:       "high",
			FilterType:       "setup+architecture",
			KnowledgeVersion: "1.3.1",
		},
	}
	for index := 0; index < 8; index++ {
		result.Evidence = append(result.Evidence, retrievalEvidence{
			ChunkID:            "documento#secao",
			DocumentID:         "documento",
			DocumentVersion:    "1.0.0",
			DocumentType:       "setup",
			Status:             "homologated",
			Category:           "automacao",
			TargetArchitecture: "amd64",
			Title:              "Documento canônico",
			Heading:            "Pré-requisitos",
			ContentSHA256:      strings.Repeat("a", 64),
			Content:            strings.Repeat("área segura ", 50),
			Score:              99.9,
		})
	}
	inspection := buildRetrievalInspection(result, "4.99.0", "image-read-only", false)
	if inspection.Mode != "shadow" || inspection.UsedInAnswer ||
		len(inspection.Evidence) != retrievalMaxResults {
		t.Fatalf("snapshot de inspeção inválido: %#v", inspection)
	}
	for _, evidence := range inspection.Evidence {
		if len([]rune(strings.TrimSuffix(evidence.Excerpt, "…"))) > retrievalExcerptRunes {
			t.Fatalf("trecho excedeu %d runas", retrievalExcerptRunes)
		}
	}
	serialized, err := json.Marshal(inspection)
	if err != nil {
		t.Fatal(err)
	}
	var payload map[string]any
	if err := json.Unmarshal(serialized, &payload); err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"question", "query", "context", "history", "score"} {
		if _, exists := payload[forbidden]; exists {
			t.Fatalf("inspeção contém campo proibido %q", forbidden)
		}
	}
	evidence, ok := payload["evidence"].([]any)
	if !ok || len(evidence) == 0 {
		t.Fatalf("evidências serializadas ausentes: %s", serialized)
	}
	for _, raw := range evidence {
		item := raw.(map[string]any)
		for _, forbidden := range []string{"content", "score", "question", "query"} {
			if _, exists := item[forbidden]; exists {
				t.Fatalf("evidência contém campo proibido %q: %s", forbidden, serialized)
			}
		}
	}
}

func TestRetrievalPromptUsesOnlyControlledCanonicalEvidence(t *testing.T) {
	result := retrievalResult{Metrics: retrievalMetrics{
		Version: "1.0.0", KnowledgeVersion: "1.3.2", Confidence: "high",
	}}
	for index := 0; index < 6; index++ {
		result.Evidence = append(result.Evidence, retrievalEvidence{
			DocumentID:         "documento-canônico",
			DocumentVersion:    "1.0.0",
			Status:             "reviewed",
			TargetArchitecture: "amd64",
			Heading:            "Seção validada",
			ContentSHA256:      strings.Repeat("a", 64),
			Content:            strings.Repeat("evidência ", 300),
			Score:              99,
		})
	}
	context, status := buildRetrievalPrompt(result)
	if status != "active" || context == nil ||
		len(context.Sources) != retrievalPromptResults {
		t.Fatalf("ativação controlada inesperada: status=%s context=%#v", status, context)
	}
	totalRunes := 0
	for index, source := range context.Sources {
		if source.Reference != "Fonte "+string(rune('1'+index)) {
			t.Fatalf("referência inesperada: %s", source.Reference)
		}
		if len([]rune(source.Content)) > retrievalPromptChunk {
			t.Fatalf("chunk excedeu o orçamento: %d", len([]rune(source.Content)))
		}
		totalRunes += len([]rune(source.Content))
	}
	if totalRunes > retrievalPromptRunes {
		t.Fatalf("contexto excedeu %d runas: %d", retrievalPromptRunes, totalRunes)
	}
	serialized, err := json.Marshal(context)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{`"score"`, `"question"`, `"history"`, `"hostname"`} {
		if strings.Contains(string(serialized), forbidden) {
			t.Fatalf("campo proibido %s no prompt: %s", forbidden, serialized)
		}
	}
}

func TestRetrievalPromptRejectsUnsafeOrInsufficientResults(t *testing.T) {
	base := retrievalResult{
		Metrics: retrievalMetrics{Version: "1.0.0", Confidence: "low"},
		Evidence: []retrievalEvidence{{
			Status: "reviewed", ContentSHA256: strings.Repeat("a", 64), Content: "conteúdo",
		}},
	}
	if context, status := buildRetrievalPrompt(base); context != nil || status != "confidence-insufficient" {
		t.Fatalf("baixa confiança foi ativada: status=%s context=%#v", status, context)
	}
	base.Metrics.Confidence = "medium"
	if context, status := buildRetrievalPrompt(base); context == nil || status != "active" {
		t.Fatalf("confiança média válida foi recusada: status=%s context=%#v", status, context)
	}
	base.Metrics.Confidence = "high"
	base.Metrics.Fallback = true
	if context, status := buildRetrievalPrompt(base); context != nil || status != "legacy-fallback" {
		t.Fatalf("fallback legado foi ativado: status=%s context=%#v", status, context)
	}
	base.Metrics.Fallback = false
	base.Evidence[0].Status = "draft"
	if context, status := buildRetrievalPrompt(base); context != nil || status != "invalid-evidence" {
		t.Fatalf("documento não aprovado foi ativado: status=%s context=%#v", status, context)
	}
}

func TestRetrievalPromptRejectsUnsafeBlueprintFixtureFlags(t *testing.T) {
	result := retrievalResult{
		Metrics: retrievalMetrics{Version: knowledgeRetrieval, Confidence: "high"},
		Evidence: []retrievalEvidence{{
			DocumentID: "blueprint-fixture", DocumentType: "blueprint",
			BlueprintID: "blueprint-fixture", Fictitious: true, Deployable: true,
			Status: "reviewed", ContentSHA256: strings.Repeat("a", 64),
			Content: "Fixture com flags incompatíveis.",
		}},
	}
	if prompt, status := buildRetrievalPrompt(result); prompt != nil ||
		status != "invalid-blueprint-evidence" {
		t.Fatalf("fixture insegura foi aceita: status=%s prompt=%#v", status, prompt)
	}
}

func TestRetrievalPromptRejectsSetupMismatch(t *testing.T) {
	result := retrievalResult{
		Metrics:       retrievalMetrics{Version: knowledgeRetrieval, Confidence: "high"},
		ResolvedSetup: "n8n-main",
		Evidence: []retrievalEvidence{
			{
				DocumentID: "catalog:n8n-main", DocumentType: "catalog",
				Status: "validated", SetupID: "n8n-main",
				ContentSHA256: strings.Repeat("a", 64), Content: "Catálogo do n8n.",
			},
			{
				DocumentID: "setup-appsmith-overview", DocumentType: "setup",
				Status: "reviewed", SetupID: "appsmith",
				ContentSHA256: strings.Repeat("b", 64), Content: "Documento alheio.",
			},
		},
	}
	if prompt, status := buildRetrievalPrompt(result); prompt != nil || status != "setup-mismatch" {
		t.Fatalf("mismatch de setup foi aceito: %s %#v", status, prompt)
	}
}

func TestGroundingCitationAuditRequiresExistingSources(t *testing.T) {
	valid := validateGroundingCitations("Compatível [Fonte 1] e seguro [Fonte 2].", 2)
	if !valid.Grounded || valid.Status != "citation-validated" || valid.CitedSources != 2 {
		t.Fatalf("citações válidas recusadas: %#v", valid)
	}
	missing := validateGroundingCitations("Resposta sem referência.", 2)
	if missing.Grounded || missing.Status != "citation-missing" {
		t.Fatalf("ausência de citação aceita: %#v", missing)
	}
	invalid := validateGroundingCitations("Referência inexistente [Fonte 3].", 2)
	if invalid.Grounded || invalid.Status != "citation-invalid" {
		t.Fatalf("citação inexistente aceita: %#v", invalid)
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
