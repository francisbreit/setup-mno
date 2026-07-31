package main

import (
	"errors"
	"net/http"
	"sort"
	"strings"
	"unicode/utf8"
)

const (
	blueprintRecommendationMaxResults = 3
	blueprintObjectiveMaxRunes        = 600
)

var blueprintRecommendationStopWords = map[string]bool{
	"arquitetura": true, "blueprint": true, "blueprints": true,
	"completa": true, "completo": true, "ferramenta": true,
	"ferramentas": true, "gostaria": true, "mno": true, "preciso": true,
	"quero": true, "servidor": true, "solucao": true, "stack": true,
}

type blueprintRecommendationRequest struct {
	Objective string `json:"objective"`
}

type blueprintRecommendationContext struct {
	SetupVersion      string  `json:"setupVersion"`
	Architecture      string  `json:"architecture"`
	MemoryTotalGB     float64 `json:"memoryTotalGB"`
	MemoryAvailableGB float64 `json:"memoryAvailableGB"`
	Source            string  `json:"source"`
}

type blueprintRecommendationItem struct {
	Rank             int      `json:"rank"`
	BlueprintID      string   `json:"blueprintId"`
	Title            string   `json:"title"`
	Status           string   `json:"status"`
	Fictitious       bool     `json:"fictitious"`
	Deployable       bool     `json:"deployable"`
	Risk             string   `json:"risk"`
	Confidence       string   `json:"confidence"`
	CapacityFit      string   `json:"capacityFit"`
	MinimumRAMGB     int      `json:"minimumRamGB"`
	RecommendedRAMGB int      `json:"recommendedRamGB"`
	ResourceBasis    string   `json:"resourceBasis"`
	Components       []string `json:"components"`
	Reasons          []string `json:"reasons"`
	Score            int      `json:"score"`
}

type blueprintRecommendationRejected struct {
	BlueprintID string   `json:"blueprintId"`
	Title       string   `json:"title"`
	Reasons     []string `json:"reasons"`
}

type blueprintRecommendationResponse struct {
	Mode            string                            `json:"mode"`
	Simulation      bool                              `json:"simulation"`
	Context         blueprintRecommendationContext    `json:"context"`
	Recommendations []blueprintRecommendationItem     `json:"recommendations"`
	Rejected        []blueprintRecommendationRejected `json:"rejected"`
	NoMatchReason   string                            `json:"noMatchReason,omitempty"`
	Guardrails      []string                          `json:"guardrails"`
}

func (a *webApp) handleBlueprintRecommendation(w http.ResponseWriter, r *http.Request) {
	var input blueprintRecommendationRequest
	if err := decodeJSON(w, r, &input, maxBodyBytes); err != nil {
		return
	}
	input.Objective = strings.Join(strings.Fields(input.Objective), " ")
	if utf8.RuneCountInString(input.Objective) < 8 ||
		utf8.RuneCountInString(input.Objective) > blueprintObjectiveMaxRunes {
		writeError(w, http.StatusBadRequest, "descreva o objetivo em 8 a 600 caracteres")
		return
	}

	var state setupStateResponse
	if err := a.agentRequest(r.Context(), "/setup-state", &state); err != nil {
		writeError(w, http.StatusServiceUnavailable, "estado runtime indisponível para recomendação")
		return
	}
	var current overview
	if err := a.agentRequest(r.Context(), "/overview", &current); err != nil {
		writeError(w, http.StatusServiceUnavailable, "capacidade runtime indisponível para recomendação")
		return
	}
	if state.Stale || state.Source != "runtime" ||
		state.SetupVersion != a.blueprints.SetupVersion ||
		(state.Architecture != "amd64" && state.Architecture != "arm64") ||
		normalizeBlueprintArchitecture(current.Architecture) != state.Architecture ||
		current.Metrics.MemoryTotal == 0 || current.Metrics.MemoryUsed > current.Metrics.MemoryTotal {
		writeError(w, http.StatusServiceUnavailable, "contexto runtime incompatível com o catálogo de Blueprints")
		return
	}

	available := current.Metrics.MemoryTotal - current.Metrics.MemoryUsed
	context := blueprintRecommendationContext{
		SetupVersion:      state.SetupVersion,
		Architecture:      state.Architecture,
		MemoryTotalGB:     float64(current.Metrics.MemoryTotal) / float64(1<<30),
		MemoryAvailableGB: float64(available) / float64(1<<30),
		Source:            "runtime-read-only",
	}
	result, err := recommendBlueprints(a.blueprints, input.Objective, context)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	a.addAudit(
		"blueprint_recommendation",
		"Recomendação local consultiva: "+recommendationAuditDetail(result),
		clientAddress(r),
	)
	writeJSON(w, http.StatusOK, result)
}

func recommendBlueprints(
	catalog blueprintCatalogResponse,
	objective string,
	context blueprintRecommendationContext,
) (blueprintRecommendationResponse, error) {
	terms := blueprintRecommendationTerms(objective)
	if len(terms) == 0 {
		return blueprintRecommendationResponse{}, errors.New("objetivo sem termos suficientes para recomendação")
	}
	if context.Architecture != "amd64" && context.Architecture != "arm64" {
		return blueprintRecommendationResponse{}, errors.New("arquitetura runtime não suportada")
	}
	if context.MemoryAvailableGB < 0 || context.MemoryTotalGB <= 0 {
		return blueprintRecommendationResponse{}, errors.New("capacidade runtime inválida")
	}

	responseContext := context
	responseContext.MemoryTotalGB = round(responseContext.MemoryTotalGB)
	responseContext.MemoryAvailableGB = round(responseContext.MemoryAvailableGB)
	result := blueprintRecommendationResponse{
		Mode:            "deterministic-read-only",
		Context:         responseContext,
		Recommendations: make([]blueprintRecommendationItem, 0),
		Rejected:        make([]blueprintRecommendationRejected, 0),
		Guardrails: []string{
			"A recomendação não executa deploy nem altera o servidor.",
			"Exemplos fictícios servem somente para simulação de homologação.",
			"RAM estimada não substitui medição, validação e confirmação humana.",
		},
	}
	for _, blueprint := range catalog.Items {
		score, matchReasons := scoreBlueprintObjective(blueprint, objective, terms)
		if score == 0 {
			continue
		}
		rejectionReasons := blueprintEligibilityReasons(blueprint, context)
		if len(rejectionReasons) > 0 {
			result.Rejected = append(result.Rejected, blueprintRecommendationRejected{
				BlueprintID: blueprint.BlueprintID,
				Title:       blueprint.Title,
				Reasons:     rejectionReasons,
			})
			continue
		}
		capacityFit := "recommended"
		capacityReason := "RAM disponível atende a estimativa recomendada."
		if context.MemoryAvailableGB < float64(blueprint.ResourceProfile.RecommendedRAMGB) {
			capacityFit = "minimum"
			capacityReason = "RAM disponível atende apenas a estimativa mínima; exige margem e medição."
		}
		matchReasons = append(matchReasons, capacityReason)
		result.Recommendations = append(result.Recommendations, blueprintRecommendationItem{
			BlueprintID:      blueprint.BlueprintID,
			Title:            blueprint.Title,
			Status:           blueprint.Status,
			Fictitious:       blueprint.Fictitious,
			Deployable:       blueprint.Deployable,
			Risk:             blueprint.Risk,
			Confidence:       blueprintRecommendationConfidence(score),
			CapacityFit:      capacityFit,
			MinimumRAMGB:     blueprint.ResourceProfile.MinimumRAMGB,
			RecommendedRAMGB: blueprint.ResourceProfile.RecommendedRAMGB,
			ResourceBasis:    blueprint.ResourceProfile.Basis,
			Components:       append([]string(nil), blueprint.Components...),
			Reasons:          matchReasons,
			Score:            score,
		})
	}
	sort.SliceStable(result.Recommendations, func(left, right int) bool {
		first := result.Recommendations[left]
		second := result.Recommendations[right]
		if first.Score != second.Score {
			return first.Score > second.Score
		}
		if first.CapacityFit != second.CapacityFit {
			return first.CapacityFit == "recommended"
		}
		return first.BlueprintID < second.BlueprintID
	})
	if len(result.Recommendations) > blueprintRecommendationMaxResults {
		result.Recommendations = result.Recommendations[:blueprintRecommendationMaxResults]
	}
	for index := range result.Recommendations {
		result.Recommendations[index].Rank = index + 1
		if result.Recommendations[index].Fictitious {
			result.Simulation = true
		}
	}
	if len(result.Recommendations) == 0 {
		if len(result.Rejected) > 0 {
			result.NoMatchReason = "Há aderência ao objetivo, mas nenhum Blueprint passou pelos gates de arquitetura e capacidade atuais."
		} else {
			result.NoMatchReason = "Nenhum Blueprint possui evidência canônica suficiente para este objetivo."
		}
	}
	return result, nil
}

func normalizeBlueprintArchitecture(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "amd64", "x86_64":
		return "amd64"
	case "arm64", "aarch64":
		return "arm64"
	default:
		return ""
	}
}

func blueprintRecommendationTerms(objective string) []string {
	terms := retrievalQueryTerms(objective)
	filtered := make([]string, 0, len(terms))
	for _, term := range terms {
		if !blueprintRecommendationStopWords[term] {
			filtered = append(filtered, term)
		}
	}
	return filtered
}

func scoreBlueprintObjective(
	blueprint blueprintCatalogItem,
	objective string,
	terms []string,
) (int, []string) {
	normalizedObjective := normalizeRetrievalPhrase(objective)
	score := 0
	reasons := make([]string, 0, 4)
	for _, alias := range blueprint.Aliases {
		normalizedAlias := normalizeRetrievalPhrase(alias)
		if normalizedAlias != "" && strings.Contains(normalizedObjective, normalizedAlias) {
			score += 60
			reasons = appendUniqueLimited(reasons, "O objetivo corresponde a um alias canônico do Blueprint.", 4)
		}
	}
	fields := []struct {
		values []string
		weight int
		reason string
	}{
		{blueprint.Tags, 14, "Tags canônicas correspondem ao objetivo informado."},
		{[]string{blueprint.Title}, 10, "O título do Blueprint corresponde ao objetivo."},
		{blueprint.Aliases, 8, "Aliases editoriais reforçam a correspondência."},
		{blueprint.Components, 6, "Componentes canônicos correspondem ao objetivo."},
		{[]string{blueprint.Objective}, 4, "O objetivo editorial possui termos compatíveis."},
		{[]string{blueprint.Summary}, 3, "O resumo possui termos compatíveis."},
	}
	for _, field := range fields {
		matched := 0
		for _, term := range terms {
			if normalizedFieldContains(field.values, term) {
				matched++
			}
		}
		if matched > 0 {
			score += matched * field.weight
			reasons = appendUniqueLimited(reasons, field.reason, 4)
		}
	}
	for _, term := range terms {
		if normalizedFieldContains(blueprint.Tags, term) || normalizedFieldContains(blueprint.Aliases, term) {
			continue
		}
		if approximateCanonicalFieldContains(blueprint.Tags, term) {
			score += 16
			reasons = appendUniqueLimited(reasons, "Uma variação ortográfica segura corresponde a uma tag canônica.", 4)
		}
		if approximateCanonicalFieldContains(blueprint.Aliases, term) {
			score += 10
			reasons = appendUniqueLimited(reasons, "Uma variação ortográfica segura corresponde a um alias canônico.", 4)
		}
	}
	return score, reasons
}

func normalizedFieldContains(values []string, term string) bool {
	for _, value := range values {
		for _, fieldTerm := range retrievalQueryTerms(value) {
			if fieldTerm == term {
				return true
			}
		}
	}
	return false
}

func approximateCanonicalFieldContains(values []string, term string) bool {
	for _, value := range values {
		for _, canonicalTerm := range retrievalQueryTerms(value) {
			if safeBlueprintTypoMatch(term, canonicalTerm) {
				return true
			}
		}
	}
	return false
}

func safeBlueprintTypoMatch(term, canonical string) bool {
	if term == canonical || len(term) < 7 || len(canonical) < 7 ||
		len(term) > 64 || len(canonical) > 64 || term[0] != canonical[0] ||
		absInt(len(term)-len(canonical)) > 1 {
		return false
	}
	if len(term) != len(canonical) {
		shorter, longer := term, canonical
		if len(shorter) > len(longer) {
			shorter, longer = longer, shorter
		}
		for index := 0; index < len(shorter); index++ {
			if shorter[index] != longer[index] {
				return shorter[index:] == longer[index+1:]
			}
		}
		return true
	}
	mismatches := make([]int, 0, 2)
	for index := 0; index < len(term); index++ {
		if term[index] != canonical[index] {
			mismatches = append(mismatches, index)
			if len(mismatches) > 2 {
				return false
			}
		}
	}
	if len(mismatches) == 1 {
		return true
	}
	return len(mismatches) == 2 && mismatches[1] == mismatches[0]+1 &&
		term[mismatches[0]] == canonical[mismatches[1]] &&
		term[mismatches[1]] == canonical[mismatches[0]]
}

func absInt(value int) int {
	if value < 0 {
		return -value
	}
	return value
}

func blueprintEligibilityReasons(
	blueprint blueprintCatalogItem,
	context blueprintRecommendationContext,
) []string {
	reasons := make([]string, 0, 3)
	validStatus := (blueprint.Status == "homologated" && !blueprint.Fictitious && blueprint.Deployable) ||
		(blueprint.Status == "example" && blueprint.Fictitious && !blueprint.Deployable)
	if !validStatus {
		reasons = append(reasons, "Status editorial não elegível para recomendação.")
	}
	if !containsString(blueprint.Architectures, context.Architecture) {
		reasons = append(reasons, "Arquitetura incompatível com o servidor atual.")
	}
	if context.MemoryAvailableGB < float64(blueprint.ResourceProfile.MinimumRAMGB) {
		reasons = append(reasons, "RAM disponível abaixo da estimativa mínima do Blueprint.")
	}
	return reasons
}

func blueprintRecommendationConfidence(score int) string {
	if score >= 60 {
		return "high"
	}
	if score >= 25 {
		return "medium"
	}
	return "low"
}

func appendUniqueLimited(values []string, value string, limit int) []string {
	if len(values) >= limit || containsString(values, value) {
		return values
	}
	return append(values, value)
}

func recommendationAuditDetail(result blueprintRecommendationResponse) string {
	if len(result.Recommendations) == 0 {
		return "nenhum compatível; recusados=" + itoa(len(result.Rejected))
	}
	return "compatíveis=" + itoa(len(result.Recommendations)) +
		"; recusados=" + itoa(len(result.Rejected))
}

func itoa(value int) string {
	const digits = "0123456789"
	if value == 0 {
		return "0"
	}
	buffer := [20]byte{}
	position := len(buffer)
	for value > 0 {
		position--
		buffer[position] = digits[value%10]
		value /= 10
	}
	return string(buffer[position:])
}
