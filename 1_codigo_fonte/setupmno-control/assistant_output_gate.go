package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

const (
	assistantOutputGateVersion  = "1.0.0"
	assistantOutputGateMaturity = "beta"
	assistantOutputGateTrailer  = "X-SetupMNO-Output-Gate"
	assistantOutputMaxBytes     = 128 << 10
)

var (
	assistantOutputSentencePattern = regexp.MustCompile(`[.!?\n]+`)
	assistantOutputWordPattern     = regexp.MustCompile(`[[:alnum:]À-ÿ_-]+`)
	assistantOutputUnknownPattern  = regexp.MustCompile(`(?i)(<\s*unk\s*>|\[\s*unk\s*\])`)
)

type assistantOutputGateDecision struct {
	SchemaVersion int    `json:"schemaVersion"`
	GateVersion   string `json:"gateVersion"`
	Maturity      string `json:"maturity"`
	Status        string `json:"status"`
	Reason        string `json:"reason,omitempty"`
	Fallback      bool   `json:"fallback"`
}

func acceptedAssistantOutput() assistantOutputGateDecision {
	return assistantOutputGateDecision{
		SchemaVersion: 1,
		GateVersion:   assistantOutputGateVersion,
		Maturity:      assistantOutputGateMaturity,
		Status:        "accepted",
	}
}

func rejectedAssistantOutput(reason string) assistantOutputGateDecision {
	return assistantOutputGateDecision{
		SchemaVersion: 1,
		GateVersion:   assistantOutputGateVersion,
		Maturity:      assistantOutputGateMaturity,
		Status:        "rejected",
		Reason:        reason,
		Fallback:      true,
	}
}

func validateAssistantProviderOutput(
	answer, question, provider string,
	contextData assistantContext,
) assistantOutputGateDecision {
	trimmed := strings.TrimSpace(answer)
	if trimmed == "" {
		return rejectedAssistantOutput("empty-output")
	}
	if !utf8.ValidString(trimmed) {
		return rejectedAssistantOutput("invalid-encoding")
	}
	if len(trimmed) > assistantOutputMaxBytes {
		return rejectedAssistantOutput("oversized-output")
	}
	if assistantOutputUnknownPattern.MatchString(trimmed) {
		return rejectedAssistantOutput("unknown-token")
	}
	normalized := normalizeRetrievalPhrase(trimmed)
	if assistantOutputLeaksInstructions(normalized) {
		return rejectedAssistantOutput("prompt-instruction-leak")
	}
	if assistantOutputRepeatsTokens(trimmed) {
		return rejectedAssistantOutput("token-repetition")
	}
	if assistantOutputRepeatsLines(trimmed) {
		return rejectedAssistantOutput("line-repetition")
	}
	if assistantOutputUnexpectedLanguage(trimmed) {
		return rejectedAssistantOutput("unexpected-language")
	}
	if assistantOutputContradictsSnapshot(trimmed, contextData.SRESnapshot) {
		return rejectedAssistantOutput("snapshot-contradiction")
	}
	if assistantOutputContradictsProvider(normalized, question, provider) {
		return rejectedAssistantOutput("provider-identity-contradiction")
	}
	return acceptedAssistantOutput()
}

func assistantOutputLeaksInstructions(normalized string) bool {
	for _, signature := range []string{
		"dados canonicos rag",
		"conclusions section should be",
		"for professionals preserve versions",
		"dont repeat sections",
		"don t repeat sections",
		"if route is scope redirect",
		"if context is blueprint homologation",
		"when rag context has quality",
		"follow responseprofile",
		"responseprofile direct overview",
		"in operation follow observe",
		"ignore previous instructions",
	} {
		if strings.Contains(normalized, signature) {
			return true
		}
	}
	return false
}

func assistantOutputRepeatsTokens(answer string) bool {
	words := assistantOutputWordPattern.FindAllString(strings.ToLower(answer), -1)
	last := ""
	consecutive := 0
	for _, word := range words {
		if word == last && len([]rune(word)) >= 2 {
			consecutive++
		} else {
			last = word
			consecutive = 1
		}
		if consecutive >= 8 {
			return true
		}
	}
	return false
}

func assistantOutputRepeatsLines(answer string) bool {
	last := ""
	consecutive := 0
	for _, line := range strings.Split(answer, "\n") {
		normalized := normalizeRetrievalPhrase(line)
		if len(normalized) < 12 {
			continue
		}
		if normalized == last {
			consecutive++
		} else {
			last = normalized
			consecutive = 1
		}
		if consecutive >= 4 {
			return true
		}
	}
	return false
}

func assistantOutputUnexpectedLanguage(answer string) bool {
	words := assistantOutputWordPattern.FindAllString(strings.ToLower(answer), -1)
	if len(words) < 25 {
		return false
	}
	portuguese := 0
	english := 0
	for _, word := range words {
		switch normalizeRetrievalPhrase(word) {
		case "de", "do", "da", "dos", "das", "para", "que", "com", "nao", "uma", "os", "as", "servidor", "servicos", "evidencia", "risco":
			portuguese++
		case "the", "and", "should", "with", "this", "that", "from", "response", "section", "must", "requested", "follow":
			english++
		}
	}
	return english >= 8 && portuguese <= 2
}

func assistantOutputContradictsSnapshot(answer string, snapshot *sreDiagnosticSnapshot) bool {
	if snapshot == nil {
		return false
	}
	if snapshot.Swarm.DegradedServices == 0 {
		failurePhrases := []string{
			"servico com falha", "servicos com falha", "servico falhando", "servicos falhando",
			"servico em estado failed", "servicos em estado failed", "servico em shutdown",
			"servicos em shutdown", "falhas recorrentes de servicos", "failed service",
			"failed services", "degraded service", "degraded services", "services in failed",
			"services in shutdown",
		}
		for _, rawSentence := range assistantOutputSentencePattern.Split(answer, -1) {
			sentence := normalizeRetrievalPhrase(rawSentence)
			if !anyPhraseContained(sentence, failurePhrases) {
				continue
			}
			if anyPhraseContained(sentence, []string{
				"nao ha", "nenhum servico", "nenhuma falha", "zero servicos", "sem servicos com falha",
				"no failed services", "zero failed services",
			}) {
				continue
			}
			return true
		}
	}
	if snapshot.Deterministic.Result == nil {
		return false
	}
	critical, high, available := assistantOutputTrivyCounts(snapshot.Deterministic.Result.Engines)
	if !available {
		return false
	}
	normalized := normalizeRetrievalPhrase(answer)
	return assistantOutputCountContradicts(normalized, "critical", critical) ||
		assistantOutputCountContradicts(normalized, "critica", critical) ||
		assistantOutputCountContradicts(normalized, "criticas", critical) ||
		assistantOutputCountContradicts(normalized, "high", high) ||
		assistantOutputCountContradicts(normalized, "alta", high) ||
		assistantOutputCountContradicts(normalized, "altas", high)
}

func assistantOutputTrivyCounts(engines []sreDeterministicEngine) (int, int, bool) {
	for _, engine := range engines {
		if engine.ID != "trivy" || engine.Counts == nil ||
			(engine.Status != "completed" && engine.Status != "partial") {
			continue
		}
		critical, criticalOK := engine.Counts["critical"]
		high, highOK := engine.Counts["high"]
		return critical, high, criticalOK && highOK
	}
	return 0, 0, false
}

func assistantOutputCountContradicts(normalized, label string, expected int) bool {
	noun := `(?:vulnerabilidades?|vulnerabilities|achados?|findings)`
	severity := `(?:severidade|severity)`
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`\b` + regexp.QuoteMeta(label) + `\s+(\d+)\b`),
		regexp.MustCompile(`\b(\d+)\s+` + regexp.QuoteMeta(label) + `\b`),
		regexp.MustCompile(`\b` + regexp.QuoteMeta(label) + `\s+(?:` + noun + `|` + severity + `)\s+(\d+)\b`),
		regexp.MustCompile(`\b(\d+)\s+` + noun + `(?:\s+de)?\s+` + regexp.QuoteMeta(label) + `\b`),
	}
	for _, pattern := range patterns {
		for _, match := range pattern.FindAllStringSubmatch(normalized, -1) {
			value, err := strconv.Atoi(match[1])
			if err == nil && value != expected {
				return true
			}
		}
	}
	return false
}

func assistantOutputContradictsProvider(normalizedAnswer, question, provider string) bool {
	normalizedQuestion := normalizeRetrievalPhrase(question)
	expected := normalizeRetrievalPhrase(provider)
	if expected == "" {
		return false
	}
	for _, other := range []string{"openai", "openrouter", "deepseek", "ollama"} {
		if other == expected || strings.Contains(normalizedQuestion, other) {
			continue
		}
		if anyPhraseContained(normalizedAnswer, []string{
			"chave " + other,
			"api key " + other,
			"secret " + other,
			"docker secret " + other,
		}) {
			return true
		}
	}
	return false
}

func buildAssistantOutputFallback(
	question string,
	contextData assistantContext,
	route assistantRoute,
) string {
	header := "**Resposta externa bloqueada pelo gate de qualidade BETA.**\n\n" +
		"O conteúdo do provedor não passou pelas verificações locais e não foi exibido. " +
		"O diagnóstico determinístico e somente leitura assumiu esta resposta; nenhuma ação foi executada."
	if contextData.SRESnapshot != nil {
		insights := localInsightsForSRESnapshot(*contextData.SRESnapshot, question, route)
		if len(insights) > 0 {
			return header + "\n\n" + strings.Join(insights, "\n\n")
		}
	}
	return fmt.Sprintf(
		"%s\n\n**Fatos locais disponíveis**\n\n- Memória em uso: %.1f%%.\n- Disco em uso: %.1f%%.\n- Serviços monitorados: %d; serviços degradados: %d.\n\n**Próximo passo seguro**\n\nRepita a consulta ou selecione outro modelo. Se precisar alterar algo, use o Instalador Seguro com confirmação humana.",
		header,
		contextData.MemoryPercent,
		contextData.DiskPercent,
		contextData.Services,
		contextData.DegradedServices,
	)
}
