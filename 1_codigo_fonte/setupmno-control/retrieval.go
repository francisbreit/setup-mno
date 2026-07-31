package main

import (
	"errors"
	"log"
	"math"
	"sort"
	"strings"
	"time"
	"unicode"
)

const (
	retrievalMaxCandidates = 24
	retrievalMaxResults    = 6
	retrievalMaxPerDoc     = 2
	retrievalMaxCharacters = 12000
)

var retrievalFieldWeights = map[string]float64{
	"aliases": 8,
	"title":   4,
	"heading": 3,
	"tags":    2,
	"content": 1,
}

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
	TargetArchitecture string
	Title              string
	Heading            string
	Content            string
	Score              float64
}

type retrievalResult struct {
	Metrics  retrievalMetrics
	Evidence []retrievalEvidence
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
	index  knowledgeIndexV2
	legacy knowledgeIndex
	config retrievalConfig
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
	return &knowledgeRetriever{
		index:  state.IndexV2,
		legacy: state.Index,
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
	started := time.Now()
	metrics := retrievalMetrics{
		Version:          knowledgeRetrieval,
		Confidence:       "none",
		FilterType:       "architecture",
		KnowledgeVersion: r.index.KnowledgeVersion,
	}
	if len(r.index.Chunks) == 0 || r.index.RetrievalVersion != knowledgeRetrieval {
		result := r.retrieveLegacy(question, setupVersion, runtimeArchitecture)
		result.Metrics.DurationMS = elapsedMilliseconds(started)
		return result
	}

	terms := retrievalQueryTerms(question)
	architectures := r.targetArchitectures(question, runtimeArchitecture)
	setupID, exactSetup := r.exactSetup(question)
	if exactSetup {
		metrics.FilterType = "setup+architecture"
	}
	if len(terms) == 0 || len(architectures) == 0 {
		metrics.DurationMS = elapsedMilliseconds(started)
		return retrievalResult{Metrics: metrics}
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
	characters := 0
	for _, architecture := range architectures {
		candidates := r.rankLane(terms, question, setupVersion, architecture, setupID, exactSetup)
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
			evidence = append(evidence, retrievalEvidence{
				ChunkID:            candidate.chunk.ChunkID,
				DocumentID:         candidate.chunk.DocumentID,
				DocumentVersion:    candidate.chunk.DocumentVersion,
				TargetArchitecture: architecture,
				Title:              candidate.chunk.Title,
				Heading:            candidate.chunk.Heading,
				Content:            candidate.chunk.Content,
				Score:              candidate.score,
			})
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
	return retrievalResult{Metrics: metrics, Evidence: evidence}
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
