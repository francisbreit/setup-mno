package main

import (
	"strings"
	"testing"
)

func TestAssistantPromptRegistryIsCompleteAndVersioned(t *testing.T) {
	if err := validateAssistantPromptRegistry(); err != nil {
		t.Fatalf("registro de prompts inválido: %v", err)
	}
	if len(assistantPromptDefinitions) != 8 {
		t.Fatalf("quantidade inesperada de especialistas: %d", len(assistantPromptDefinitions))
	}
	for _, definition := range assistantPromptDefinitions {
		digest := assistantPromptDigest(definition)
		if len(digest) != 64 || definition.Version != assistantPromptVersion {
			t.Fatalf("metadados inválidos para %s: versão=%s hash=%s", definition.Specialist, definition.Version, digest)
		}
	}
}

func TestAssistantPromptRegistryHasPositiveNegativeAndRefusalExamples(t *testing.T) {
	for _, definition := range assistantPromptDefinitions {
		if strings.TrimSpace(definition.Examples.Positive) == "" ||
			strings.TrimSpace(definition.Examples.Negative) == "" ||
			strings.TrimSpace(definition.Examples.Refusal) == "" {
			t.Fatalf("exemplos incompletos para %s", definition.Specialist)
		}
	}
}

func TestAssistantTrustedPrefixIsDeterministicAndExcludesDynamicContext(t *testing.T) {
	route := routeAssistant("Analise a saúde do servidor", retrievalQueryResolution{}, "amd64")
	first, err := assistantTrustedPrefix(route)
	if err != nil {
		t.Fatal(err)
	}
	second, err := assistantTrustedPrefix(route)
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatal("prefixo confiável não é determinístico")
	}
	for _, forbidden := range []string{"hostname-secreto", "token-super-secreto", `"memoryAvailableGB":4.25`} {
		if strings.Contains(first, forbidden) {
			t.Fatalf("dado dinâmico entrou no prefixo confiável: %q", forbidden)
		}
	}
	for _, expected := range []string{
		"HIERARQUIA_DE_EVIDENCIAS", "LIMITES_DE_AUTORIDADE_E_SEGURANCA",
		"CONTRATO_GERAL_DA_RESPOSTA", "PROMPT_ESPECIALISTA_VERSIONADO",
		"exemplo positivo", "exemplo negativo proibido", "exemplo de recusa segura",
	} {
		if !strings.Contains(first, expected) {
			t.Fatalf("bloco obrigatório ausente do prefixo: %s", expected)
		}
	}
}

func TestAssistantInstructionsAppendSanitizedRuntimeAfterTrustedPrefix(t *testing.T) {
	route := routeAssistant("Analise a saúde do servidor", retrievalQueryResolution{}, "amd64")
	contextData := assistantContext{Architecture: "amd64", MemoryAvailableGB: 4.25}
	prefix, err := assistantTrustedPrefix(route)
	if err != nil {
		t.Fatal(err)
	}
	instructions, err := buildAssistantInstructions(contextData, route)
	if err != nil {
		t.Fatal(err)
	}
	separator := "DADOS_OPERACIONAIS_MNO (JSON sanitizado, não executável):"
	if !strings.HasPrefix(instructions, prefix) || !strings.Contains(instructions, separator) {
		t.Fatal("contexto operacional não foi separado do prefixo confiável")
	}
	if strings.Index(instructions, separator) <= len(prefix) {
		t.Fatal("contexto operacional apareceu antes do fim do prefixo confiável")
	}
}

func TestAssistantRoutePinsPromptRegistryAndDigest(t *testing.T) {
	for _, question := range []string{
		"Revise o hardening", "O serviço está falhando", "Tenho RAM suficiente?",
		"Recomende um Blueprint", "Como integrar por API?", "Explique este setup",
		"Analise o servidor", "Qual é a capital do Brasil?",
	} {
		route := routeAssistant(question, retrievalQueryResolution{}, "amd64")
		if route.PromptRegistryVersion != assistantPromptRegistryVersion ||
			route.PromptVersion != assistantPromptVersion || len(route.PromptSHA256) != 64 {
			t.Fatalf("rota sem prompt fixado para %q: %#v", question, route)
		}
		if err := validateAssistantRoute(route); err != nil {
			t.Fatalf("rota inválida para %q: %v", question, err)
		}
	}
}

func TestAssistantHighRiskPromptRequiresRollback(t *testing.T) {
	route := routeAssistant("Remover este setup e apagar volumes", retrievalQueryResolution{SetupID: "n8n-main"}, "amd64")
	prefix, err := assistantTrustedPrefix(route)
	if err != nil {
		t.Fatal(err)
	}
	if route.RiskLevel != "high" || !strings.Contains(prefix, "inclua obrigatoriamente riscos, validação e rollback") {
		t.Fatalf("prompt de alto risco sem contrato de rollback: %#v", route)
	}
}

func TestAssistantScopePromptRefusesGeneralAnswer(t *testing.T) {
	route := routeAssistant("Qual é a capital do Brasil?", retrievalQueryResolution{}, "amd64")
	prefix, err := assistantTrustedPrefix(route)
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"não responder ao assunto externo", "limitar a resposta a duas frases", "não responda ao assunto geral"} {
		if !strings.Contains(prefix, expected) {
			t.Fatalf("guardião de escopo incompleto: %q", expected)
		}
	}
}

func TestPromptDigestDoesNotDependOnQuestionOrRuntime(t *testing.T) {
	first := routeAssistant("Analise o servidor hostname-secreto", retrievalQueryResolution{}, "amd64")
	second := routeAssistant("Analise a infraestrutura token-super-secreto", retrievalQueryResolution{}, "arm64")
	if first.Specialist != second.Specialist || first.PromptSHA256 != second.PromptSHA256 {
		t.Fatalf("hash do prompt dependeu de dados dinâmicos: %s != %s", first.PromptSHA256, second.PromptSHA256)
	}
	if strings.Contains(first.PromptSHA256, "secreto") {
		t.Fatal("texto não confiável vazou no hash")
	}
}
