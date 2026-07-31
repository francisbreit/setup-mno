package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
)

const (
	retrievalMaxCandidates = 24
	retrievalMaxResults    = 6
	retrievalMaxPerDoc     = 2
	retrievalMaxCharacters = 12000
	retrievalExcerptRunes  = 360
	retrievalPromptResults = 4
	retrievalPromptRunes   = 6000
	retrievalPromptChunk   = 1800
)

var retrievalFieldWeights = map[string]float64{
	"aliases": 8,
	"title":   4,
	"heading": 3,
	"tags":    2,
	"content": 1,
}

var groundingCitationPattern = regexp.MustCompile(`\[Fonte ([1-9][0-9]*)\]`)

var retrievalStopWords = map[string]struct{}{
	"a": {}, "ao": {}, "aos": {}, "as": {}, "com": {}, "como": {},
	"da": {}, "das": {}, "de": {}, "do": {}, "dos": {}, "e": {},
	"em": {}, "entre": {}, "no": {}, "nos": {}, "o": {}, "os": {},
	"ou": {}, "para": {}, "pela": {}, "pelo": {}, "por": {}, "que": {},
	"se": {}, "sem": {}, "um": {}, "uma": {},
}

type retrievalConfig struct {
	K1            float64
	B             float64
	MaxCandidates int
	MaxResults    int
	MaxPerDoc     int
	MaxCharacters int
}

type retrievalMetrics struct {
	Version          string `json:"version"`
	DurationMS       int64  `json:"durationMs"`
	CandidateCount   int    `json:"candidateCount"`
	ReturnedCount    int    `json:"returnedCount"`
	Confidence       string `json:"confidence"`
	FilterType       string `json:"filterType"`
	Fallback         bool   `json:"fallback"`
	KnowledgeVersion string `json:"knowledgeVersion"`
}

type retrievalEvidence struct {
	ChunkID            string
	DocumentID         string
	DocumentVersion    string
	DocumentType       string
	Status             string
	Category           string
	TargetArchitecture string
	Title              string
	Heading            string
	SetupID            string
	ContentSHA256      string
	Content            string
	Score              float64
}

type retrievalResult struct {
	Metrics        retrievalMetrics
	Evidence       []retrievalEvidence
	ResolvedSetup  string
	Contextualized bool
}

type retrievalCitation struct {
	Rank               int    `json:"rank"`
	ChunkID            string `json:"chunkId"`
	DocumentID         string `json:"documentId"`
	DocumentVersion    string `json:"documentVersion"`
	DocumentType       string `json:"documentType"`
	Status             string `json:"status"`
	Category           string `json:"category"`
	Title              string `json:"title"`
	Heading            string `json:"heading"`
	TargetArchitecture string `json:"targetArchitecture"`
	SetupID            string `json:"setupId,omitempty"`
	ContentSHA256      string `json:"contentSHA256"`
	Excerpt            string `json:"excerpt"`
}

type retrievalInspection struct {
	Mode              string              `json:"mode"`
	UsedInAnswer      bool                `json:"usedInAnswer"`
	Version           string              `json:"version"`
	KnowledgeVersion  string              `json:"knowledgeVersion"`
	KnowledgeSource   string              `json:"knowledgeSource"`
	KnowledgeStale    bool                `json:"knowledgeStale"`
	SetupVersion      string              `json:"setupVersion"`
	DurationMS        int64               `json:"durationMs"`
	CandidateCount    int                 `json:"candidateCount"`
	ReturnedCount     int                 `json:"returnedCount"`
	Confidence        string              `json:"confidence"`
	FilterType        string              `json:"filterType"`
	Fallback          bool                `json:"fallback"`
	PromptStatus      string              `json:"promptStatus"`
	PromptSourceCount int                 `json:"promptSourceCount"`
	ResolvedSetupID   string              `json:"resolvedSetupId,omitempty"`
	Contextualized    bool                `json:"contextualized"`
	Evidence          []retrievalCitation `json:"evidence"`
}

type retrievalPromptSource struct {
	Reference          string `json:"reference"`
	DocumentID         string `json:"documentId"`
	DocumentVersion    string `json:"documentVersion"`
	DocumentType       string `json:"documentType"`
	Heading            string `json:"heading"`
	TargetArchitecture string `json:"targetArchitecture"`
	SetupID            string `json:"setupId,omitempty"`
	ContentSHA256      string `json:"contentSHA256"`
	Content            string `json:"content"`
	Truncated          bool   `json:"truncated"`
}

type retrievalPromptContext struct {
	Mode             string                  `json:"mode"`
	RetrievalVersion string                  `json:"retrievalVersion"`
	KnowledgeVersion string                  `json:"knowledgeVersion"`
	Confidence       string                  `json:"confidence"`
	Sources          []retrievalPromptSource `json:"sources"`
}

type retrievalQueryResolution struct {
	Query          string
	SetupID        string
	CatalogName    string
	Contextualized bool
}

type groundingAudit struct {
	Grounded         bool   `json:"grounded"`
	Status           string `json:"status"`
	CitedSources     int    `json:"citedSources"`
	AvailableSources int    `json:"availableSources"`
}

type retrievalAggregate struct {
	Queries          uint64 `json:"queries"`
	Fallbacks        uint64 `json:"fallbacks"`
	TotalDurationMS  uint64 `json:"totalDurationMs"`
	MaxDurationMS    int64  `json:"maxDurationMs"`
	TotalCandidates  uint64 `json:"totalCandidates"`
	TotalReturned    uint64 `json:"totalReturned"`
	HighConfidence   uint64 `json:"highConfidence"`
	MediumConfidence uint64 `json:"mediumConfidence"`
	LowConfidence    uint64 `json:"lowConfidence"`
	NoConfidence     uint64 `json:"noConfidence"`
}

type knowledgeRetriever struct {
	index             knowledgeIndexV2
	legacy            knowledgeIndex
	config            retrievalConfig
	setupCatalogNames map[string]string
}

type scoredChunk struct {
	chunk      knowledgeChunk
	score      float64
	exactAlias bool
}

func newKnowledgeRetriever(state knowledgePackageState) (*knowledgeRetriever, error) {
	if state.IndexV2.SchemaVersion != knowledgeIndexSchema ||
		state.IndexV2.RetrievalVersion != knowledgeRetrieval ||
		len(state.IndexV2.Chunks) == 0 {
		return nil, errors.New("índice v2 indisponível")
	}
	var registry struct {
		Setups []struct {
			SetupID     string `json:"setupId"`
			CatalogName string `json:"catalogName"`
		} `json:"setups"`
	}
	registryData, exists := state.Files["registry/setups.json"]
	if !exists || json.Unmarshal(registryData, &registry) != nil || len(registry.Setups) == 0 {
		return nil, errors.New("registro canônico de setups indisponível")
	}
	setupCatalogNames := make(map[string]string, len(registry.Setups))
	for _, entry := range registry.Setups {
		if entry.SetupID == "" || entry.CatalogName == "" {
			return nil, errors.New("registro canônico de setups inválido")
		}
		setupCatalogNames[entry.SetupID] = entry.CatalogName
	}
	return &knowledgeRetriever{
		index:             state.IndexV2,
		legacy:            state.Index,
		setupCatalogNames: setupCatalogNames,
		config: retrievalConfig{
			K1:            1.2,
			B:             0.75,
			MaxCandidates: retrievalMaxCandidates,
			MaxResults:    retrievalMaxResults,
			MaxPerDoc:     retrievalMaxPerDoc,
			MaxCharacters: retrievalMaxCharacters,
		},
	}, nil
}

func (r *knowledgeRetriever) retrieve(
	question string,
	setupVersion string,
	runtimeArchitecture string,
) retrievalResult {
	return r.retrieveResolved(
		r.resolveQuery(question, nil),
		setupVersion,
		runtimeArchitecture,
	)
}

func (r *knowledgeRetriever) resolveQuery(
	question string,
	history []assistantMessage,
) retrievalQueryResolution {
	resolution := retrievalQueryResolution{Query: strings.TrimSpace(question)}
	if setupID, exact := r.exactSetup(question); exact {
		resolution.SetupID = setupID
		resolution.CatalogName = r.setupCatalogNames[setupID]
		return resolution
	}
	if !hasContextualSetupReference(question) {
		return resolution
	}
	for index := len(history) - 1; index >= 0; index-- {
		message := history[index]
		if message.Role != "user" {
			continue
		}
		setupID, exact := r.exactSetup(message.Content)
		if !exact {
			continue
		}
		alias := r.matchedSetupAlias(message.Content, setupID)
		if alias == "" {
			alias = r.setupCatalogNames[setupID]
		}
		resolution.Query = strings.TrimSpace(question + " " + alias)
		resolution.SetupID = setupID
		resolution.CatalogName = r.setupCatalogNames[setupID]
		resolution.Contextualized = true
		return resolution
	}
	return resolution
}

func hasContextualSetupReference(question string) bool {
	normalized := normalizeRetrievalPhrase(question)
	for _, reference := range []string{
		"este setup", "esse setup", "aquele setup",
		"esta ferramenta", "essa ferramenta", "este aplicativo",
		"esse aplicativo", "esta aplicacao", "essa aplicacao",
	} {
		if strings.Contains(normalized, reference) {
			return true
		}
	}
	return false
}

func (r *knowledgeRetriever) matchedSetupAlias(question string, setupID string) string {
	best := ""
	if catalogName := r.setupCatalogNames[setupID]; anyPhraseContained(question, []string{catalogName}) {
		best = catalogName
	}
	for _, chunk := range r.index.Chunks {
		if chunk.SetupID == nil || *chunk.SetupID != setupID {
			continue
		}
		for _, alias := range chunk.Aliases {
			if anyPhraseContained(question, []string{alias}) && len([]rune(alias)) > len([]rune(best)) {
				best = alias
			}
		}
	}
	return best
}

func (r *knowledgeRetriever) retrieveResolved(
	resolution retrievalQueryResolution,
	setupVersion string,
	runtimeArchitecture string,
) retrievalResult {
	started := time.Now()
	metrics := retrievalMetrics{
		Version:          knowledgeRetrieval,
		Confidence:       "none",
		FilterType:       "architecture",
		KnowledgeVersion: r.index.KnowledgeVersion,
	}
	if len(r.index.Chunks) == 0 || r.index.RetrievalVersion != knowledgeRetrieval {
		result := r.retrieveLegacy(resolution.Query, setupVersion, runtimeArchitecture)
		result.Metrics.DurationMS = elapsedMilliseconds(started)
		result.ResolvedSetup = resolution.SetupID
		result.Contextualized = resolution.Contextualized
		return result
	}

	terms := retrievalQueryTerms(resolution.Query)
	architectures := r.targetArchitectures(resolution.Query, runtimeArchitecture)
	setupID := resolution.SetupID
	exactSetup := setupID != ""
	if !exactSetup {
		setupID, exactSetup = r.exactSetup(resolution.Query)
	}
	if exactSetup {
		metrics.FilterType = "setup+architecture"
		if resolution.Contextualized {
			metrics.FilterType += "+context"
		}
	}
	if len(terms) == 0 || len(architectures) == 0 {
		metrics.DurationMS = elapsedMilliseconds(started)
		return retrievalResult{
			Metrics: metrics, ResolvedSetup: setupID,
			Contextualized: resolution.Contextualized,
		}
	}

	maxPerLane := r.config.MaxResults
	if len(architectures) > 1 {
		maxPerLane = max(1, r.config.MaxResults/len(architectures))
		metrics.FilterType += "+comparison"
	}
	evidence := make([]retrievalEvidence, 0, r.config.MaxResults)
	candidateCount := 0
	highestScore := 0.0
	anyExactAlias := false
	perDocument := make(map[string]int)
	evidenceByChunk := make(map[string]int)
	characters := 0
	for _, architecture := range architectures {
		candidates := r.rankLane(
			terms, resolution.Query, setupVersion, architecture, setupID, exactSetup,
		)
		candidateCount += min(len(candidates), r.config.MaxCandidates)
		added := 0
		perDocumentLane := make(map[string]int)
		maxPerDocumentLane := r.config.MaxPerDoc
		if len(architectures) > 1 {
			maxPerDocumentLane = max(1, r.config.MaxPerDoc/len(architectures))
		}
		for _, candidate := range candidates {
			if added == maxPerLane || len(evidence) == r.config.MaxResults {
				break
			}
			if perDocument[candidate.chunk.DocumentID] >= r.config.MaxPerDoc ||
				perDocumentLane[candidate.chunk.DocumentID] >= maxPerDocumentLane {
				continue
			}
			if characters+len(candidate.chunk.Content) > r.config.MaxCharacters {
				continue
			}
			if existingIndex, exists := evidenceByChunk[candidate.chunk.ChunkID]; exists {
				evidence[existingIndex].TargetArchitecture = mergeArchitectures(
					evidence[existingIndex].TargetArchitecture,
					architecture,
				)
				highestScore = max(highestScore, candidate.score)
				anyExactAlias = anyExactAlias || candidate.exactAlias
				added++
				continue
			}
			evidence = append(evidence, retrievalEvidence{
				ChunkID:            candidate.chunk.ChunkID,
				DocumentID:         candidate.chunk.DocumentID,
				DocumentVersion:    candidate.chunk.DocumentVersion,
				DocumentType:       candidate.chunk.DocumentType,
				Status:             candidate.chunk.Status,
				Category:           candidate.chunk.Category,
				TargetArchitecture: architecture,
				Title:              candidate.chunk.Title,
				Heading:            candidate.chunk.Heading,
				SetupID:            setupID,
				ContentSHA256:      candidate.chunk.ContentSHA256,
				Content:            candidate.chunk.Content,
				Score:              candidate.score,
			})
			evidenceByChunk[candidate.chunk.ChunkID] = len(evidence) - 1
			perDocument[candidate.chunk.DocumentID]++
			perDocumentLane[candidate.chunk.DocumentID]++
			characters += len(candidate.chunk.Content)
			added++
			highestScore = max(highestScore, candidate.score)
			anyExactAlias = anyExactAlias || candidate.exactAlias
		}
	}
	metrics.CandidateCount = min(candidateCount, r.config.MaxCandidates*len(architectures))
	metrics.ReturnedCount = len(evidence)
	metrics.Confidence = retrievalConfidence(highestScore, anyExactAlias, len(evidence))
	metrics.DurationMS = elapsedMilliseconds(started)
	return retrievalResult{
		Metrics: metrics, Evidence: evidence, ResolvedSetup: setupID,
		Contextualized: resolution.Contextualized,
	}
}

func mergeArchitectures(current string, architecture string) string {
	if current == architecture || strings.Contains(current, architecture) {
		return current
	}
	if current == "" {
		return architecture
	}
	return current + "," + architecture
}

func (r *knowledgeRetriever) attachCatalogEvidence(
	result retrievalResult,
	contextData assistantContext,
) retrievalResult {
	if result.ResolvedSetup == "" || !validEvidenceSHA256(contextData.CatalogSHA256) {
		return result
	}
	catalogName := r.setupCatalogNames[result.ResolvedSetup]
	var catalogItem map[string]any
	for _, item := range contextData.RelevantSetups {
		if strings.EqualFold(strings.TrimSpace(fmt.Sprint(item["name"])), catalogName) {
			catalogItem = item
			break
		}
	}
	if catalogItem == nil {
		return result
	}
	architectureLabel, targetArchitectures := catalogArchitectureEvidence(
		strings.TrimSpace(fmt.Sprint(catalogItem["arch"])),
	)
	content := fmt.Sprintf(
		"Entrada estruturada do catálogo validado do Setup MNO. Setup: %s. Arquiteturas declaradas: %s. Memória estimada: %s. Tipo: %s. Descrição: %s.",
		catalogName,
		architectureLabel,
		strings.TrimSpace(fmt.Sprint(catalogItem["ramLabel"])),
		strings.TrimSpace(fmt.Sprint(catalogItem["type"])),
		strings.TrimSpace(fmt.Sprint(catalogItem["desc"])),
	)
	catalogEvidence := retrievalEvidence{
		ChunkID:            "catalog:" + result.ResolvedSetup,
		DocumentID:         "catalog:" + result.ResolvedSetup,
		DocumentVersion:    contextData.CatalogVersion,
		DocumentType:       "catalog",
		Status:             "validated",
		Category:           "catalog",
		TargetArchitecture: targetArchitectures,
		Title:              "Catálogo validado — " + catalogName,
		Heading:            "Compatibilidade e requisitos estruturados",
		SetupID:            result.ResolvedSetup,
		ContentSHA256:      contextData.CatalogSHA256,
		Content:            strings.Join(strings.Fields(content), " "),
		Score:              math.MaxFloat64,
	}
	result.Evidence = append([]retrievalEvidence{catalogEvidence}, result.Evidence...)
	if len(result.Evidence) > retrievalMaxResults {
		result.Evidence = result.Evidence[:retrievalMaxResults]
	}
	result.Metrics.ReturnedCount = len(result.Evidence)
	if result.Metrics.Confidence == "none" || result.Metrics.Confidence == "low" {
		if result.Contextualized {
			result.Metrics.Confidence = "medium"
		} else {
			result.Metrics.Confidence = "high"
		}
	}
	result.Metrics.FilterType += "+catalog"
	return result
}

func catalogArchitectureEvidence(value string) (string, string) {
	switch normalizeRetrievalPhrase(value) {
	case "x86-arm", "x86 arm", "amd64 arm64":
		return "amd64/x86-64 e arm64/aarch64", "amd64,arm64"
	case "x86", "amd64", "x86 64":
		return "amd64/x86-64", "amd64"
	case "arm", "arm64", "aarch64":
		return "arm64/aarch64", "arm64"
	default:
		return "não informadas pelo catálogo", "geral"
	}
}

func (r *knowledgeRetriever) rankLane(
	terms []string,
	question string,
	setupVersion string,
	architecture string,
	setupID string,
	filterSetup bool,
) []scoredChunk {
	allowedStatuses := make(map[string]struct{}, len(r.index.NormalRetrievalStatuses))
	for _, status := range r.index.NormalRetrievalStatuses {
		allowedStatuses[status] = struct{}{}
	}
	candidates := make([]scoredChunk, 0, min(len(r.index.Chunks), r.config.MaxCandidates))
	for _, chunk := range r.index.Chunks {
		if chunk.SetupVersion != setupVersion ||
			!containsString(chunk.Architectures, architecture) {
			continue
		}
		if _, allowed := allowedStatuses[chunk.Status]; !allowed {
			continue
		}
		if filterSetup && (chunk.SetupID == nil || *chunk.SetupID != setupID) {
			continue
		}
		score := 0.0
		for field, weight := range retrievalFieldWeights {
			frequencies := chunk.FieldTermFrequencies[field]
			fieldLength := float64(chunk.FieldLengths[field])
			averageLength := r.index.AverageFieldLengths[field]
			if averageLength <= 0 {
				continue
			}
			for _, term := range terms {
				frequency := float64(frequencies[term])
				if frequency <= 0 {
					continue
				}
				documentFrequency := float64(r.index.DocumentFrequencies[term])
				totalChunks := float64(r.index.ChunkCount)
				idf := math.Log(1 + (totalChunks-documentFrequency+0.5)/(documentFrequency+0.5))
				normalization := frequency + r.config.K1*
					(1-r.config.B+r.config.B*fieldLength/averageLength)
				score += weight * idf * frequency * (r.config.K1 + 1) / normalization
			}
		}
		exactAlias := anyPhraseContained(question, chunk.Aliases)
		if exactAlias {
			score += retrievalFieldWeights["aliases"]
		}
		if score <= 0 {
			continue
		}
		candidates = append(candidates, scoredChunk{
			chunk: chunk, score: score, exactAlias: exactAlias,
		})
	}
	sort.Slice(candidates, func(left, right int) bool {
		if candidates[left].score == candidates[right].score {
			return candidates[left].chunk.ChunkID < candidates[right].chunk.ChunkID
		}
		return candidates[left].score > candidates[right].score
	})
	if len(candidates) > r.config.MaxCandidates {
		candidates = candidates[:r.config.MaxCandidates]
	}
	return candidates
}

func (r *knowledgeRetriever) exactSetup(question string) (string, bool) {
	matches := make(map[string]struct{})
	for setupID, catalogName := range r.setupCatalogNames {
		if anyPhraseContained(question, []string{catalogName}) {
			matches[setupID] = struct{}{}
		}
	}
	for _, chunk := range r.index.Chunks {
		if chunk.SetupID == nil || !anyPhraseContained(question, chunk.Aliases) {
			continue
		}
		matches[*chunk.SetupID] = struct{}{}
	}
	if len(matches) != 1 {
		return "", false
	}
	for setupID := range matches {
		return setupID, true
	}
	return "", false
}

func (r *knowledgeRetriever) targetArchitectures(
	question string,
	runtimeArchitecture string,
) []string {
	targets := make([]string, 0, 2)
	for _, architecture := range []string{"amd64", "arm64"} {
		aliases := append([]string{architecture}, r.index.Synonyms[architecture]...)
		if anyPhraseContained(question, aliases) {
			targets = append(targets, architecture)
		}
	}
	if len(targets) > 0 {
		return targets
	}
	switch normalizeRetrievalPhrase(runtimeArchitecture) {
	case "amd64", "x86", "x86 64":
		return []string{"amd64"}
	case "arm64", "arm", "aarch64":
		return []string{"arm64"}
	default:
		return nil
	}
}

func (r *knowledgeRetriever) retrieveLegacy(
	question string,
	setupVersion string,
	architecture string,
) retrievalResult {
	terms := retrievalQueryTerms(question)
	matches := 0
	for _, entry := range r.legacy.Entries {
		if entry.SetupVersion != setupVersion ||
			!containsString(entry.Architectures, architecture) ||
			(entry.Status != "reviewed" && entry.Status != "homologated") {
			continue
		}
		if intersectsSorted(entry.Terms, terms) {
			matches++
		}
	}
	return retrievalResult{Metrics: retrievalMetrics{
		Version:          knowledgeRetrieval,
		CandidateCount:   min(matches, retrievalMaxCandidates),
		ReturnedCount:    min(matches, retrievalMaxResults),
		Confidence:       legacyConfidence(matches),
		FilterType:       "legacy+architecture",
		Fallback:         true,
		KnowledgeVersion: r.index.KnowledgeVersion,
	}}
}

func buildRetrievalInspection(
	result retrievalResult,
	setupVersion string,
	knowledgeSource string,
	knowledgeStale bool,
) retrievalInspection {
	evidence := make([]retrievalCitation, 0, min(len(result.Evidence), retrievalMaxResults))
	for index, item := range result.Evidence {
		if index == retrievalMaxResults {
			break
		}
		evidence = append(evidence, retrievalCitation{
			Rank:               index + 1,
			ChunkID:            item.ChunkID,
			DocumentID:         item.DocumentID,
			DocumentVersion:    item.DocumentVersion,
			DocumentType:       item.DocumentType,
			Status:             item.Status,
			Category:           item.Category,
			Title:              item.Title,
			Heading:            item.Heading,
			TargetArchitecture: item.TargetArchitecture,
			SetupID:            item.SetupID,
			ContentSHA256:      item.ContentSHA256,
			Excerpt:            canonicalExcerpt(item.Content),
		})
	}
	return retrievalInspection{
		Mode:             "shadow",
		UsedInAnswer:     false,
		Version:          result.Metrics.Version,
		KnowledgeVersion: result.Metrics.KnowledgeVersion,
		KnowledgeSource:  knowledgeSource,
		KnowledgeStale:   knowledgeStale,
		SetupVersion:     setupVersion,
		DurationMS:       result.Metrics.DurationMS,
		CandidateCount:   result.Metrics.CandidateCount,
		ReturnedCount:    result.Metrics.ReturnedCount,
		Confidence:       result.Metrics.Confidence,
		FilterType:       result.Metrics.FilterType,
		Fallback:         result.Metrics.Fallback,
		ResolvedSetupID:  result.ResolvedSetup,
		Contextualized:   result.Contextualized,
		Evidence:         evidence,
	}
}

func buildRetrievalPrompt(result retrievalResult) (*retrievalPromptContext, string) {
	if result.Metrics.Fallback {
		return nil, "legacy-fallback"
	}
	if result.Metrics.Confidence != "high" && result.Metrics.Confidence != "medium" {
		return nil, "confidence-insufficient"
	}
	if len(result.Evidence) == 0 {
		return nil, "no-evidence"
	}
	if result.ResolvedSetup != "" {
		hasCatalogEvidence := false
		for _, item := range result.Evidence {
			if item.SetupID != result.ResolvedSetup {
				return nil, "setup-mismatch"
			}
			if item.DocumentType == "catalog" && item.Status == "validated" {
				hasCatalogEvidence = true
			}
		}
		if !hasCatalogEvidence {
			return nil, "catalog-evidence-missing"
		}
	}
	sources := make([]retrievalPromptSource, 0, retrievalPromptResults)
	totalRunes := 0
	for _, item := range result.Evidence {
		if len(sources) == retrievalPromptResults {
			break
		}
		approvedDocument := item.Status == "reviewed" || item.Status == "homologated" ||
			(item.DocumentType == "catalog" && item.Status == "validated")
		if !approvedDocument ||
			!validEvidenceSHA256(item.ContentSHA256) {
			return nil, "invalid-evidence"
		}
		content := strings.Join(strings.Fields(item.Content), " ")
		contentRunes := []rune(content)
		if len(contentRunes) == 0 {
			continue
		}
		limit := min(retrievalPromptChunk, retrievalPromptRunes-totalRunes)
		if limit <= 0 {
			break
		}
		truncated := len(contentRunes) > limit
		if truncated {
			contentRunes = contentRunes[:limit]
		}
		sources = append(sources, retrievalPromptSource{
			Reference:          fmt.Sprintf("Fonte %d", len(sources)+1),
			DocumentID:         item.DocumentID,
			DocumentVersion:    item.DocumentVersion,
			DocumentType:       item.DocumentType,
			Heading:            item.Heading,
			TargetArchitecture: item.TargetArchitecture,
			SetupID:            item.SetupID,
			ContentSHA256:      item.ContentSHA256,
			Content:            string(contentRunes),
			Truncated:          truncated,
		})
		totalRunes += len(contentRunes)
	}
	if len(sources) == 0 {
		return nil, "no-evidence"
	}
	return &retrievalPromptContext{
		Mode:             "controlled",
		RetrievalVersion: result.Metrics.Version,
		KnowledgeVersion: result.Metrics.KnowledgeVersion,
		Confidence:       result.Metrics.Confidence,
		Sources:          sources,
	}, "active"
}

func validateGroundingCitations(answer string, availableSources int) groundingAudit {
	audit := groundingAudit{
		Status: "citation-missing", AvailableSources: availableSources,
	}
	if availableSources <= 0 {
		audit.Status = "no-sources"
		return audit
	}
	matches := groundingCitationPattern.FindAllStringSubmatch(answer, -1)
	if len(matches) == 0 {
		return audit
	}
	unique := make(map[int]struct{}, len(matches))
	for _, match := range matches {
		reference, err := strconv.Atoi(match[1])
		if err != nil || reference < 1 || reference > availableSources {
			audit.Status = "citation-invalid"
			return audit
		}
		unique[reference] = struct{}{}
	}
	audit.Grounded = true
	audit.Status = "citation-validated"
	audit.CitedSources = len(unique)
	return audit
}

func validEvidenceSHA256(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, character := range value {
		if !((character >= '0' && character <= '9') ||
			(character >= 'a' && character <= 'f')) {
			return false
		}
	}
	return true
}

func canonicalExcerpt(content string) string {
	content = strings.Join(strings.Fields(content), " ")
	runes := []rune(content)
	if len(runes) <= retrievalExcerptRunes {
		return content
	}
	return string(runes[:retrievalExcerptRunes]) + "…"
}

func (s *assistantService) recordRetrieval(metrics retrievalMetrics) {
	s.retrievalMu.Lock()
	s.retrievalStats.Queries++
	s.retrievalStats.TotalDurationMS += uint64(max(metrics.DurationMS, 0))
	s.retrievalStats.MaxDurationMS = max(s.retrievalStats.MaxDurationMS, metrics.DurationMS)
	s.retrievalStats.TotalCandidates += uint64(max(metrics.CandidateCount, 0))
	s.retrievalStats.TotalReturned += uint64(max(metrics.ReturnedCount, 0))
	if metrics.Fallback {
		s.retrievalStats.Fallbacks++
	}
	switch metrics.Confidence {
	case "high":
		s.retrievalStats.HighConfidence++
	case "medium":
		s.retrievalStats.MediumConfidence++
	case "low":
		s.retrievalStats.LowConfidence++
	default:
		s.retrievalStats.NoConfidence++
	}
	s.retrievalMu.Unlock()
	log.Printf(
		"Assistente MNO retrieval_shadow version=%s duration_ms=%d candidates=%d returned=%d confidence=%s filter=%s fallback=%t knowledge=%s",
		metrics.Version,
		metrics.DurationMS,
		metrics.CandidateCount,
		metrics.ReturnedCount,
		metrics.Confidence,
		metrics.FilterType,
		metrics.Fallback,
		metrics.KnowledgeVersion,
	)
}

func (s *assistantService) retrievalSnapshot() retrievalAggregate {
	s.retrievalMu.Lock()
	defer s.retrievalMu.Unlock()
	return s.retrievalStats
}

func retrievalConfidence(score float64, exactAlias bool, returned int) string {
	if returned == 0 {
		return "none"
	}
	if exactAlias || score >= 12 {
		return "high"
	}
	if returned >= 2 && score >= 4 {
		return "medium"
	}
	return "low"
}

func legacyConfidence(matches int) string {
	if matches == 0 {
		return "none"
	}
	return "low"
}

func elapsedMilliseconds(started time.Time) int64 {
	elapsed := time.Since(started).Milliseconds()
	if elapsed < 0 {
		return 0
	}
	return elapsed
}

func retrievalQueryTerms(value string) []string {
	normalized := normalizeRetrievalAccents(strings.ToLower(value))
	terms := make(map[string]struct{})
	var current strings.Builder
	flush := func() {
		term := strings.Trim(current.String(), "-")
		current.Reset()
		if len(term) < 2 || len(term) > 64 {
			return
		}
		if _, stop := retrievalStopWords[term]; !stop {
			terms[term] = struct{}{}
		}
	}
	for _, character := range normalized {
		if (character >= 'a' && character <= 'z') ||
			(character >= '0' && character <= '9') ||
			character == '-' {
			current.WriteRune(character)
			continue
		}
		flush()
	}
	flush()
	result := make([]string, 0, len(terms))
	for term := range terms {
		result = append(result, term)
	}
	sort.Strings(result)
	return result
}

func normalizeRetrievalPhrase(value string) string {
	value = normalizeRetrievalAccents(strings.ToLower(value))
	var normalized strings.Builder
	space := true
	for _, character := range value {
		if unicode.IsLetter(character) || unicode.IsDigit(character) {
			normalized.WriteRune(character)
			space = false
			continue
		}
		if !space {
			normalized.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimSpace(normalized.String())
}

func normalizeRetrievalAccents(value string) string {
	replacer := strings.NewReplacer(
		"á", "a", "à", "a", "â", "a", "ã", "a", "ä", "a",
		"é", "e", "è", "e", "ê", "e", "ë", "e",
		"í", "i", "ì", "i", "î", "i", "ï", "i",
		"ó", "o", "ò", "o", "ô", "o", "õ", "o", "ö", "o",
		"ú", "u", "ù", "u", "û", "u", "ü", "u",
		"ç", "c",
	)
	return replacer.Replace(value)
}

func anyPhraseContained(question string, phrases []string) bool {
	normalizedQuestion := " " + normalizeRetrievalPhrase(question) + " "
	for _, phrase := range phrases {
		normalizedPhrase := normalizeRetrievalPhrase(phrase)
		if normalizedPhrase != "" &&
			strings.Contains(normalizedQuestion, " "+normalizedPhrase+" ") {
			return true
		}
	}
	return false
}

func containsString(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func intersectsSorted(left, right []string) bool {
	rightTerms := make(map[string]struct{}, len(right))
	for _, term := range right {
		rightTerms[term] = struct{}{}
	}
	for _, term := range left {
		if _, exists := rightTerms[term]; exists {
			return true
		}
	}
	return false
}
