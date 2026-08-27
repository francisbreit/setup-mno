package main

import (
	"strings"
	"testing"
)

func healthyOutputGateContext() assistantContext {
	return assistantContext{
		OperationalContextAvailable: true,
		MemoryPercent:               31.2,
		DiskPercent:                 6.1,
		Services:                    11,
		DegradedServices:            0,
		SRESnapshot: &sreDiagnosticSnapshot{
			Swarm: sreSnapshotSwarm{
				Services:         11,
				HealthyServices:  11,
				DegradedServices: 0,
			},
			Events: make([]sreSnapshotEvent, 40),
		},
	}
}

func TestAssistantOutputGateAcceptsConsistentPortugueseAnswer(t *testing.T) {
	decision := validateAssistantProviderOutput(
		"Não há serviços com falha. Os 11 serviços monitorados atendem às réplicas desejadas e o próximo passo é manter o monitoramento.",
		"Faça uma revisão de segurança do servidor",
		"openrouter",
		healthyOutputGateContext(),
	)
	if decision.Status != "accepted" || decision.Fallback {
		t.Fatalf("resposta coerente foi bloqueada: %#v", decision)
	}
}

func TestAssistantOutputGateRejectsUnknownTokens(t *testing.T) {
	decision := validateAssistantProviderOutput(
		"Conclusão: <unk> <unk> <unk>", "Analise o servidor", "openrouter", healthyOutputGateContext(),
	)
	if decision.Reason != "unknown-token" {
		t.Fatalf("token desconhecido não foi bloqueado: %#v", decision)
	}
}

func TestAssistantOutputGateRejectsPromptInstructionLeak(t *testing.T) {
	for _, answer := range []string{
		`"Conclusions" section should be 1-3 sentences. For professionals, preserve versions and architecture.`,
		`Don't repeat sections. In high-risk topics, include validation and rollback.`,
	} {
		decision := validateAssistantProviderOutput(
			answer, "Faça uma revisão de segurança do servidor", "openrouter", healthyOutputGateContext(),
		)
		if decision.Reason != "prompt-instruction-leak" {
			t.Fatalf("instrução interna vazou pelo gate em %q: %#v", answer, decision)
		}
	}
}

func TestAssistantOutputGateRejectsRepetition(t *testing.T) {
	decision := validateAssistantProviderOutput(
		"falha falha falha falha falha falha falha falha", "Analise o servidor", "openrouter", healthyOutputGateContext(),
	)
	if decision.Reason != "token-repetition" {
		t.Fatalf("repetição não foi bloqueada: %#v", decision)
	}
}

func TestAssistantOutputGateRejectsSnapshotContradictions(t *testing.T) {
	for _, answer := range []string{
		"Existem 11 serviços em estado failed e isso indica instabilidade.",
		"Há falhas recorrentes de serviços em 40 eventos consultados.",
		"Não há falhas no banco. Existem 11 serviços em estado failed.",
	} {
		decision := validateAssistantProviderOutput(
			answer, "Existem serviços com falha?", "openrouter", healthyOutputGateContext(),
		)
		if decision.Reason != "snapshot-contradiction" {
			t.Fatalf("contradição não foi bloqueada para %q: %#v", answer, decision)
		}
	}
}

func TestAssistantOutputGateRejectsTrivyCountContradictions(t *testing.T) {
	contextData := healthyOutputGateContext()
	contextData.SRESnapshot.Deterministic = sreDeterministicState{
		Status: "available",
		Result: &sreDeterministicResult{Engines: []sreDeterministicEngine{{
			ID: "trivy", Status: "partial", Counts: map[string]int{"critical": 0, "high": 7},
		}}},
	}
	for _, answer := range []string{
		"O Trivy encontrou critical=3 e high=7.",
		"O scanner encontrou 7 altas e 4 críticas.",
		"O scanner encontrou 7 vulnerabilidades de alta severidade e 4 vulnerabilidades críticas.",
	} {
		decision := validateAssistantProviderOutput(
			answer, "Faça uma revisão de segurança", "openrouter", contextData,
		)
		if decision.Reason != "snapshot-contradiction" {
			t.Fatalf("contagem incompatível não foi bloqueada para %q: %#v", answer, decision)
		}
	}
	decision := validateAssistantProviderOutput(
		"O Trivy registrou critical=0 e high=7 no escopo coberto.",
		"Faça uma revisão de segurança", "openrouter", contextData,
	)
	if decision.Status != "accepted" {
		t.Fatalf("contagem compatível foi bloqueada: %#v", decision)
	}
}

func TestAssistantOutputGateRejectsWrongProviderIdentity(t *testing.T) {
	decision := validateAssistantProviderOutput(
		"A chave OpenAI foi armazenada como Docker Secret e está protegida.",
		"Faça uma revisão de segurança", "openrouter", healthyOutputGateContext(),
	)
	if decision.Reason != "provider-identity-contradiction" {
		t.Fatalf("identidade errada do provedor não foi bloqueada: %#v", decision)
	}
}

func TestAssistantOutputFallbackUsesOnlyLocalFacts(t *testing.T) {
	fallback := buildAssistantOutputFallback(
		"Analise a saúde do servidor", healthyOutputGateContext(),
		routeAssistant("Analise a saúde do servidor", retrievalQueryResolution{}, "amd64"),
	)
	for _, expected := range []string{
		"Resposta externa bloqueada", "diagnóstico", "somente leitura", "40",
	} {
		if !strings.Contains(fallback, expected) {
			t.Fatalf("fallback local sem %q: %s", expected, fallback)
		}
	}
	if strings.Contains(fallback, "<unk>") || strings.Contains(fallback, "Conclusions section") {
		t.Fatalf("fallback contém saída rejeitada: %s", fallback)
	}
}

func TestAssistantOutputGateAuditReasonIsAllowlisted(t *testing.T) {
	if reason, ok := assistantOutputGateAuditReason("rejected:unknown-token"); !ok || reason != "unknown-token" {
		t.Fatalf("motivo seguro não foi aceito: %q %v", reason, ok)
	}
	if _, ok := assistantOutputGateAuditReason("rejected:segredo-do-provedor"); ok {
		t.Fatal("motivo arbitrário não pode entrar na auditoria")
	}
}
