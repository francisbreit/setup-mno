package main

import "testing"

func recommendationTestCatalog() blueprintCatalogResponse {
	items := []blueprintCatalogItem{
		{
			BlueprintID: "blueprint-001-whatsapp-marketing-completo", Title: "WhatsApp Marketing Completo",
			Status: "example", Fictitious: true, Deployable: false, Risk: "high",
			Architectures: []string{"amd64", "arm64"}, Tags: []string{"whatsapp", "marketing", "automacao", "atendimento"},
			Aliases:    []string{"marketing por whatsapp", "campanhas whatsapp", "automação whatsapp completa"},
			Components: []string{"CHATWOOT", "MAUTIC", "N8N", "TYPEBOT"}, Objective: "Campanhas, automação e atendimento humano pelo WhatsApp.",
			Summary: "Arquitetura de marketing e atendimento.", ResourceProfile: blueprintResourceProfile{MinimumRAMGB: 20, RecommendedRAMGB: 24, Basis: "Estimativa fictícia para teste."},
		},
		{
			BlueprintID: "blueprint-002-automacao-negocios", Title: "Automação de Negócios",
			Status: "example", Fictitious: true, Deployable: false, Risk: "medium",
			Architectures: []string{"amd64", "arm64"}, Tags: []string{"n8n", "activepieces", "workflows", "processos"},
			Aliases:    []string{"automação de negócios", "workflows empresariais", "integração de processos"},
			Components: []string{"BOOKSTACK", "ACTIVEPIECES", "N8N"}, Objective: "Automatizar processos de negócio com workflows.",
			Summary: "Dois motores de automação.", ResourceProfile: blueprintResourceProfile{MinimumRAMGB: 12, RecommendedRAMGB: 16, Basis: "Estimativa fictícia para teste."},
		},
		{
			BlueprintID: "blueprint-003-base-conhecimento-rag", Title: "Base de Conhecimento com IA e RAG",
			Status: "example", Fictitious: true, Deployable: false, Risk: "high",
			Architectures: []string{"amd64", "arm64"}, Tags: []string{"rag", "dify", "qdrant", "ollama"},
			Aliases:    []string{"base de conhecimento com ia", "rag local", "assistente documental"},
			Components: []string{"QDRANT", "DIFY", "OLLAMA"}, Objective: "Base documental com inteligência artificial e RAG.",
			Summary: "Recuperação de conhecimento com IA.", ResourceProfile: blueprintResourceProfile{MinimumRAMGB: 16, RecommendedRAMGB: 32, Basis: "Estimativa fictícia para teste."},
		},
		{
			BlueprintID: "blueprint-004-observabilidade-monitoramento", Title: "Observabilidade e Monitoramento",
			Status: "example", Fictitious: true, Deployable: false, Risk: "medium",
			Architectures: []string{"amd64", "arm64"}, Tags: []string{"observabilidade", "monitoramento", "metricas", "alertas"},
			Aliases:    []string{"monitoramento de servidor", "observabilidade completa", "saúde dos serviços"},
			Components: []string{"BESZEL", "GRAFANA", "PROMETHEUS", "UPTIMEKUMA"}, Objective: "Monitorar métricas, saúde e disponibilidade.",
			Summary: "Observabilidade em camadas.", ResourceProfile: blueprintResourceProfile{MinimumRAMGB: 4, RecommendedRAMGB: 8, Basis: "Estimativa fictícia para teste."},
		},
		{
			BlueprintID: "blueprint-005-servidor-pequeno", Title: "Servidor Pequeno com Ferramentas Leves",
			Status: "example", Fictitious: true, Deployable: false, Risk: "medium",
			Architectures: []string{"amd64", "arm64"}, Tags: []string{"servidor-pequeno", "monitoramento", "dns", "capacidade"},
			Aliases:    []string{"stack leve", "vps pequena", "servidor com pouca memória"},
			Components: []string{"BESZEL", "UPTIMEKUMA", "ADGUARDHOME"}, Objective: "Serviços leves com visibilidade e DNS.",
			Summary: "Composição conservadora para pouca memória.", ResourceProfile: blueprintResourceProfile{MinimumRAMGB: 2, RecommendedRAMGB: 4, Basis: "Estimativa fictícia para teste."},
		},
	}
	return blueprintCatalogResponse{SetupVersion: "7.1.0", BlueprintCount: len(items), Items: items}
}

func recommendationTestContext(available float64) blueprintRecommendationContext {
	return blueprintRecommendationContext{
		SetupVersion: "7.1.0", Architecture: "amd64", MemoryTotalGB: 64,
		MemoryAvailableGB: available, Source: "runtime-read-only",
	}
}

func TestBlueprintRecommendationSelectsExpectedObjective(t *testing.T) {
	cases := []struct {
		objective string
		expected  string
	}{
		{"campanhas de marketing por whatsapp e atendimento", "blueprint-001-whatsapp-marketing-completo"},
		{"automação de negócios com workflows empresariais", "blueprint-002-automacao-negocios"},
		{"base de conhecimento com ia e rag local", "blueprint-003-base-conhecimento-rag"},
		{"observabilidade completa com métricas e alertas", "blueprint-004-observabilidade-monitoramento"},
		{"dns e monitoramento em servidor com pouca memória", "blueprint-005-servidor-pequeno"},
	}
	for _, testCase := range cases {
		t.Run(testCase.expected, func(t *testing.T) {
			result, err := recommendBlueprints(
				recommendationTestCatalog(), testCase.objective, recommendationTestContext(64),
			)
			if err != nil {
				t.Fatal(err)
			}
			if len(result.Recommendations) == 0 ||
				result.Recommendations[0].BlueprintID != testCase.expected ||
				result.Recommendations[0].Rank != 1 || !result.Simulation ||
				result.Recommendations[0].Deployable {
				t.Fatalf("recomendação inesperada: %#v", result)
			}
		})
	}
}

func TestBlueprintRecommendationRejectsInsufficientRAM(t *testing.T) {
	result, err := recommendBlueprints(
		recommendationTestCatalog(), "observabilidade completa", recommendationTestContext(3),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Recommendations) != 0 || !rejectedBlueprint(result, "blueprint-004-observabilidade-monitoramento") ||
		result.NoMatchReason == "" {
		t.Fatalf("gate de RAM falhou: %#v", result)
	}
}

func TestBlueprintRecommendationUsesUnroundedCapacityGate(t *testing.T) {
	result, err := recommendBlueprints(
		recommendationTestCatalog(), "observabilidade completa", recommendationTestContext(3.96),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Recommendations) != 0 || !rejectedBlueprint(result, "blueprint-004-observabilidade-monitoramento") {
		t.Fatalf("arredondamento atravessou o gate de RAM: %#v", result)
	}
	if result.Context.MemoryAvailableGB != 4 {
		t.Fatalf("contexto de apresentação não foi arredondado: %#v", result.Context)
	}
}

func TestNormalizeBlueprintArchitecture(t *testing.T) {
	for input, expected := range map[string]string{
		"amd64": "amd64", "x86_64": "amd64", "arm64": "arm64", "aarch64": "arm64", "mips": "",
	} {
		if actual := normalizeBlueprintArchitecture(input); actual != expected {
			t.Fatalf("arquitetura %q normalizada como %q; esperado %q", input, actual, expected)
		}
	}
}

func TestBlueprintRecommendationRejectsArchitectureAndUnsafeStatus(t *testing.T) {
	catalog := recommendationTestCatalog()
	catalog.Items[0].Architectures = []string{"arm64"}
	catalog.Items[1].Status = "reviewed"
	for _, testCase := range []struct {
		objective string
		id        string
	}{
		{"marketing por whatsapp", catalog.Items[0].BlueprintID},
		{"automação de negócios", catalog.Items[1].BlueprintID},
	} {
		result, err := recommendBlueprints(catalog, testCase.objective, recommendationTestContext(64))
		if err != nil {
			t.Fatal(err)
		}
		if len(result.Recommendations) != 0 || !rejectedBlueprint(result, testCase.id) {
			t.Fatalf("candidato incompatível atravessou o gate: %#v", result)
		}
	}
}

func rejectedBlueprint(result blueprintRecommendationResponse, blueprintID string) bool {
	for _, item := range result.Rejected {
		if item.BlueprintID == blueprintID {
			return true
		}
	}
	return false
}

func TestBlueprintRecommendationDoesNotInventMatch(t *testing.T) {
	result, err := recommendBlueprints(
		recommendationTestCatalog(), "gestão de laboratório químico", recommendationTestContext(64),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Recommendations) != 0 || len(result.Rejected) != 0 || result.NoMatchReason == "" {
		t.Fatalf("objetivo sem evidência recebeu recomendação: %#v", result)
	}
}

func TestBlueprintRecommendationAcceptsSafeCanonicalTypo(t *testing.T) {
	result, err := recommendBlueprints(
		recommendationTestCatalog(), "preciso enviar mensagens pelo whastapp", recommendationTestContext(64),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Recommendations) == 0 ||
		result.Recommendations[0].BlueprintID != "blueprint-001-whatsapp-marketing-completo" ||
		result.Recommendations[0].Confidence != "medium" ||
		!containsString(result.Recommendations[0].Reasons, "Uma variação ortográfica segura corresponde a uma tag canônica.") {
		t.Fatalf("erro ortográfico canônico não foi recuperado com segurança: %#v", result)
	}
}

func TestBlueprintRecommendationAppliesCapacityGateAfterSafeTypo(t *testing.T) {
	result, err := recommendBlueprints(
		recommendationTestCatalog(), "preciso enviar mensagens pelo whastapp", recommendationTestContext(5.1),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Recommendations) != 0 ||
		!rejectedBlueprint(result, "blueprint-001-whatsapp-marketing-completo") ||
		result.NoMatchReason != "Há aderência ao objetivo, mas nenhum Blueprint passou pelos gates de arquitetura e capacidade atuais." {
		t.Fatalf("gate de RAM não foi aplicado após a aproximação: %#v", result)
	}
}

func TestBlueprintRecommendationDoesNotApproximateComponents(t *testing.T) {
	result, err := recommendBlueprints(
		recommendationTestCatalog(), "preciso utilizar prometheis", recommendationTestContext(64),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Recommendations) != 0 || len(result.Rejected) != 0 {
		t.Fatalf("componente não canônico recebeu aproximação: %#v", result)
	}
}

func TestSafeBlueprintTypoMatchBoundaries(t *testing.T) {
	cases := []struct {
		term      string
		canonical string
		expected  bool
	}{
		{"whastapp", "whatsapp", true},
		{"whatsap", "whatsapp", true},
		{"whatsxpp", "whatsapp", true},
		{"whatsapp", "whatsapp", false},
		{"xhatsapp", "whatsapp", false},
		{"whizzapp", "whatsapp", false},
		{"danos", "dados", false},
		{"rga", "rag", false},
	}
	for _, testCase := range cases {
		if actual := safeBlueprintTypoMatch(testCase.term, testCase.canonical); actual != testCase.expected {
			t.Fatalf("safeBlueprintTypoMatch(%q, %q)=%t; esperado %t", testCase.term, testCase.canonical, actual, testCase.expected)
		}
	}
}

func TestBlueprintRecommendationRejectsGenericObjective(t *testing.T) {
	if _, err := recommendBlueprints(
		recommendationTestCatalog(), "quero uma solução", recommendationTestContext(64),
	); err == nil {
		t.Fatal("objetivo genérico foi aceito")
	}
}
