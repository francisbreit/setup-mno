package main

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestAssistantRouterSelectsSpecialistsDeterministically(t *testing.T) {
	tests := []struct {
		name       string
		question   string
		resolution retrievalQueryResolution
		intent     string
		specialist string
	}{
		{"security", "Revise o hardening e as permissões do servidor", retrievalQueryResolution{}, "security_review", "security_reviewer"},
		{"troubleshooting", "O serviço está offline e falhando com timeout", retrievalQueryResolution{}, "troubleshooting", "troubleshooting_specialist"},
		{"capacity", "Posso instalar esta aplicação com 4 GB de RAM?", retrievalQueryResolution{}, "capacity_planning", "capacity_planner"},
		{"blueprint", "Crie uma recomendação de Blueprint para atendimento", retrievalQueryResolution{}, "blueprint_recommendation", "blueprint_architect"},
		{"integration", "Como integrar n8n com PostgreSQL por webhook?", retrievalQueryResolution{SetupIDs: []string{"n8n-main"}}, "integration_design", "integration_architect"},
		{"setup", "Este setup funciona em ARM?", retrievalQueryResolution{SetupID: "n8n-main", SetupIDs: []string{"n8n-main"}, Contextualized: true}, "setup_guidance", "setup_specialist"},
		{"canonical api name", "O que é WAHA API no Setup MNO?", retrievalQueryResolution{SetupID: "waha-api", SetupIDs: []string{"waha-api"}, Contextualized: true}, "setup_guidance", "setup_specialist"},
		{"integration first setup", "O que é Evolution API v2 no Setup MNO?", retrievalQueryResolution{SetupID: "evolution-api-v2", SetupIDs: []string{"evolution-api-v2"}, Contextualized: true}, "integration_design", "integration_architect"},
		{"explicit api integration", "Como conectar o WAHA ao n8n via API?", retrievalQueryResolution{SetupIDs: []string{"waha-api", "n8n-main"}, Contextualized: true}, "integration_design", "integration_architect"},
		{"infrastructure", "Analise a saúde do meu servidor Docker", retrievalQueryResolution{}, "infrastructure_diagnosis", "infrastructure_diagnostician"},
		{"knowledge", "Quantas aplicações você possui documentadas em sua base de conhecimento?", retrievalQueryResolution{}, "knowledge_status", "setup_specialist"},
		{"knowledge natural wording", "Quantos setups estão documentados e quantos estão homologados?", retrievalQueryResolution{}, "knowledge_status", "setup_specialist"},
		{"scope", "Qual é a capital do Brasil?", retrievalQueryResolution{}, "scope_redirect", "scope_guard"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			first := routeAssistant(test.question, test.resolution, "amd64")
			second := routeAssistant(test.question, test.resolution, "amd64")
			if !reflect.DeepEqual(first, second) {
				t.Fatalf("roteamento não determinístico: %#v != %#v", first, second)
			}
			if first.Intent != test.intent || first.Specialist != test.specialist {
				t.Fatalf("rota inesperada: %#v", first)
			}
			if err := validateAssistantRoute(first); err != nil {
				t.Fatalf("contrato produzido é inválido: %v", err)
			}
		})
	}
}

func TestSetupOverviewUsesDirectProgressiveProfile(t *testing.T) {
	for _, question := range []string{
		"Para que serve o n8n?",
		"O que é o Baserow?",
		"Qual a finalidade do Uptime Kuma?",
	} {
		route := routeAssistant(
			question,
			retrievalQueryResolution{SetupID: "n8n-main", SetupIDs: []string{"n8n-main"}},
			"unknown",
		)
		if route.Intent != "setup_guidance" || route.ResponseProfile != "direct_overview" {
			t.Fatalf("pergunta conceitual sem explicação direta: %q %#v", question, route)
		}
		if !reflect.DeepEqual(route.RequiredEvidence, []string{"catalog_entry", "setup_documentation"}) {
			t.Fatalf("perfil conceitual exigiu evidência operacional: %#v", route.RequiredEvidence)
		}
		if assistantOutputTokenLimit(route) != 500 {
			t.Fatalf("limite progressivo inesperado: %d", assistantOutputTokenLimit(route))
		}
	}

	decision := routeAssistant(
		"Meu servidor suporta o n8n com 4 GB de RAM?",
		retrievalQueryResolution{SetupID: "n8n-main", SetupIDs: []string{"n8n-main"}},
		"amd64",
	)
	if decision.ResponseProfile != "technical_diagnosis" || decision.Intent != "capacity_planning" {
		t.Fatalf("decisão de capacidade simplificada indevidamente: %#v", decision)
	}
}

func TestKnowledgeStatusQuestionRecognizesGovernanceWithoutFalsePositives(t *testing.T) {
	positive := []string{
		"Quantos setups estão documentados e quantos estão homologados?",
		"Quais aplicações estão homologadas?",
		"Qual o total de ferramentas documentadas?",
		"Qual é o status de maturidade do catálogo?",
		"Quantos setups possuem evidência operacional?",
	}
	for _, question := range positive {
		if !isKnowledgeStatusQuestion(question) {
			t.Fatalf("consulta de inventário não reconhecida: %q", question)
		}
	}

	negative := []string{
		"Como homologar meu setup?",
		"Quero instalar um setup homologado.",
		"Como documentar uma aplicação nova?",
		"Qual versão do n8n devo instalar?",
	}
	for _, question := range negative {
		if isKnowledgeStatusQuestion(question) {
			t.Fatalf("consulta operacional confundida com inventário: %q", question)
		}
	}
}

func TestAssistantRouterPreservesCanonicalSetupsAndArchitecture(t *testing.T) {
	route := routeAssistant(
		"Compare este setup em ARM e x86",
		retrievalQueryResolution{
			SetupID: "n8n-main", SetupIDs: []string{"n8n-main"}, Contextualized: true,
		},
		"amd64",
	)
	if route.Architecture != "multi" || !reflect.DeepEqual(route.Setups, []string{"n8n-main"}) {
		t.Fatalf("contexto canônico ou arquitetura perdidos: %#v", route)
	}
	if !containsString(route.Signals, "conversation_context_resolved") ||
		!containsString(route.Signals, "canonical_setup_detected") {
		t.Fatalf("sinais seguros ausentes: %#v", route.Signals)
	}
}

func TestCanonicalAPISetupNamesDoNotImplyTheSameIntent(t *testing.T) {
	retriever, _ := testKnowledgeRetriever(t)
	tests := []struct {
		question string
		intent   string
	}{
		{"O que é WAHA API no Setup MNO e quando devo usar esse setup?", "setup_guidance"},
		{"O que é Evolution API v1 no Setup MNO e quando devo usar esse setup?", "integration_design"},
		{"Quais arquiteturas são compatíveis com Evolution API v2 no Setup MNO?", "integration_design"},
	}
	for _, test := range tests {
		resolution := retriever.resolveQuery(test.question, nil)
		route := routeAssistant(test.question, resolution, "amd64")
		if route.Intent != test.intent {
			t.Fatalf(
				"rota inesperada para %q: intent=%s setups=%v query=%q",
				test.question, route.Intent, resolution.SetupIDs, resolution.Query,
			)
		}
	}
}

func TestAssistantRouterRequiresRollbackForHighRiskLanguage(t *testing.T) {
	route := routeAssistant(
		"Como deletar este setup e remover volume?",
		retrievalQueryResolution{SetupID: "n8n-main", SetupIDs: []string{"n8n-main"}},
		"amd64",
	)
	if route.RiskLevel != "high" || !containsString(route.RequiredEvidence, "rollback") ||
		!containsString(route.Signals, "destructive_action_language") {
		t.Fatalf("linguagem destrutiva não elevou o gate: %#v", route)
	}
}

func TestAssistantRouteDoesNotExposeQuestionOrSensitiveRuntimeData(t *testing.T) {
	question := "Analise meu servidor hostname-secreto com a credencial token-super-secreto"
	route := routeAssistant(question, retrievalQueryResolution{}, "amd64")
	serialized, err := json.Marshal(route)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"hostname-secreto", "token-super-secreto", question} {
		if strings.Contains(string(serialized), forbidden) {
			t.Fatalf("texto não permitido vazou no contrato: %s", serialized)
		}
	}
	prompt, err := assistantRoutePrompt(route)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(prompt, "hostname-secreto") || strings.Contains(prompt, "token-super-secreto") {
		t.Fatalf("texto do usuário vazou no prompt de rota: %s", prompt)
	}
	for _, expected := range []string{
		"ROTA_ESPECIALISTA_MNO", assistantRouterVersion, assistantPromptRegistryVersion,
		assistantPromptVersion, assistantResponseContractVersion, route.PromptSHA256,
		"PROMPT_ESPECIALISTA_VERSIONADO", "CONTRATO_DE_RESPOSTA_VERSIONADO",
		"Não reclassifique a rota", "Nunca afirme ter executado ações",
	} {
		if !strings.Contains(prompt, expected) {
			t.Fatalf("regra versionada ausente no prompt: %q", expected)
		}
	}
}

func TestAssistantRouteValidationRejectsUntrustedFields(t *testing.T) {
	valid := routeAssistant("Analise meu servidor", retrievalQueryResolution{}, "amd64")
	invalidDomain := valid
	invalidDomain.Domains = []string{"dominio enviado pelo usuario"}
	if validateAssistantRoute(invalidDomain) == nil {
		t.Fatal("domínio fora da allowlist foi aceito")
	}
	invalidSetup := valid
	invalidSetup.Setups = []string{"../../segredo"}
	if validateAssistantRoute(invalidSetup) == nil {
		t.Fatal("setup fora do formato canônico foi aceito")
	}
	invalidIntent := valid
	invalidIntent.Intent = "execute_command"
	if validateAssistantRoute(invalidIntent) == nil {
		t.Fatal("intenção de escrita foi aceita")
	}
	invalidResponseContract := valid
	invalidResponseContract.ResponseContractVersion = "9.9.9"
	if validateAssistantRoute(invalidResponseContract) == nil {
		t.Fatal("contrato de resposta incompatível foi aceito")
	}
	invalidResponseProfile := valid
	invalidResponseProfile.ResponseProfile = "invented"
	if validateAssistantRoute(invalidResponseProfile) == nil {
		t.Fatal("perfil de resposta fora da allowlist foi aceito")
	}
	invalidHighRisk := valid
	invalidHighRisk.RiskLevel = "high"
	invalidHighRisk.RequiredEvidence = []string{"runtime_state"}
	if validateAssistantRoute(invalidHighRisk) == nil {
		t.Fatal("rota de alto risco sem rollback foi aceita")
	}
}

func TestBasicAssistantRedirectsOutOfScopeWithoutMetrics(t *testing.T) {
	current := overview{Architecture: "amd64"}
	answer := strings.Join(localInsights(current, "Qual é a capital do Brasil?"), " ")
	if !strings.Contains(answer, "especializado em Setup MNO e infraestrutura") ||
		strings.Contains(answer, "Memória") || strings.Contains(answer, "Disco") {
		t.Fatalf("contingência fora do escopo respondeu com diagnóstico indevido: %s", answer)
	}
}

func TestBasicAssistantKeepsKnownInfrastructureDomainsInScope(t *testing.T) {
	for _, question := range []string{
		"O n8n funciona em ARM?",
		"Quais diferenças existem entre ARM e x86?",
		"Explique a arquitetura do PostgreSQL",
	} {
		route := routeAssistant(question, retrievalQueryResolution{}, "amd64")
		if route.Intent == "scope_redirect" || route.Specialist != "infrastructure_diagnostician" {
			t.Fatalf("domínio conhecido foi redirecionado: %q %#v", question, route)
		}
	}
}
