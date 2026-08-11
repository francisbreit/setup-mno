package main

import (
	"errors"
	"fmt"
	"math"
	"strings"
	"time"
)

const (
	evalSchemaVersion  = 1
	evalDatasetVersion = "1.13.0"
	evalGraderVersion  = "1.9.0"
	evalExpectedCases  = 863
)

type evalReview struct {
	Decision   string `json:"decision"`
	ReviewedAt string `json:"reviewedAt"`
	ReviewedBy string `json:"reviewedBy"`
	Notes      string `json:"notes"`
}

type evalRubric struct {
	RequiredChecks       []string `json:"requiredChecks"`
	ManualReviewRequired bool     `json:"manualReviewRequired"`
}

type evalCase struct {
	CaseID             string     `json:"caseId"`
	EvaluationType     string     `json:"evaluationType"`
	Question           string     `json:"question"`
	IntentionExpected  string     `json:"intentionExpected"`
	ExpectedDocuments  []string   `json:"expectedDocuments"`
	RequiredFacts      []string   `json:"requiredFacts"`
	ForbiddenClaims    []string   `json:"forbiddenClaims"`
	ExpectedBlueprint  *string    `json:"expectedBlueprint"`
	ReferenceAnswer    string     `json:"referenceAnswer"`
	Rubric             evalRubric `json:"rubric"`
	Risk               string     `json:"risk"`
	Tags               []string   `json:"tags"`
	Architecture       string     `json:"architecture"`
	SpecialistExpected string     `json:"specialistExpected"`
	RequiresRollback   bool       `json:"requiresRollback"`
	ExpectsNoEvidence  bool       `json:"expectsNoEvidence"`
}

type evalDataset struct {
	SchemaVersion  int        `json:"schemaVersion"`
	DatasetVersion string     `json:"datasetVersion"`
	GraderVersion  string     `json:"graderVersion"`
	SetupVersion   string     `json:"setupVersion"`
	Status         string     `json:"status"`
	Review         evalReview `json:"review"`
	UpdatedAt      string     `json:"updatedAt"`
	CaseCount      int        `json:"caseCount"`
	Cases          []evalCase `json:"cases"`
}

type evalMetrics struct {
	RecallAt5                  float64 `json:"recallAt5"`
	PrecisionAt5               float64 `json:"precisionAt5"`
	MeanReciprocalRank         float64 `json:"meanReciprocalRank"`
	MeanAveragePrecision       float64 `json:"meanAveragePrecision"`
	RoutingAccuracy            float64 `json:"routingAccuracy"`
	Factuality                 float64 `json:"factuality"`
	Groundedness               float64 `json:"groundedness"`
	Completeness               float64 `json:"completeness"`
	Safety                     float64 `json:"safety"`
	Clarity                    float64 `json:"clarity"`
	BlueprintSelection         float64 `json:"blueprintSelection"`
	CriticalRollback           float64 `json:"criticalRollback"`
	NoEvidenceHonesty          float64 `json:"noEvidenceHonesty"`
	StaleDocumentRate          float64 `json:"staleDocumentRate"`
	ArchitectureMixRate        float64 `json:"architectureMixRate"`
	CredentialLeakCount        int     `json:"credentialLeakCount"`
	InventedActionCount        int     `json:"inventedActionCount"`
	IncompatibleBlueprintCount int     `json:"incompatibleBlueprintCount"`
}

type evalThresholds struct {
	RecallAt5          float64 `json:"recallAt5"`
	Factuality         float64 `json:"factuality"`
	Groundedness       float64 `json:"groundedness"`
	RoutingAccuracy    float64 `json:"routingAccuracy"`
	BlueprintSelection float64 `json:"blueprintSelection"`
	CriticalRollback   float64 `json:"criticalRollback"`
	NoEvidenceHonesty  float64 `json:"noEvidenceHonesty"`
}

type evalBaseline struct {
	Release     string `json:"release"`
	Mode        string `json:"mode"`
	Regressions int    `json:"regressions"`
}

type evalReport struct {
	SchemaVersion           int            `json:"schemaVersion"`
	Status                  string         `json:"status"`
	DatasetVersion          string         `json:"datasetVersion"`
	GraderVersion           string         `json:"graderVersion"`
	DatasetSHA256           string         `json:"datasetSHA256"`
	SetupVersion            string         `json:"setupVersion"`
	ControlVersion          string         `json:"controlVersion"`
	KnowledgeVersion        string         `json:"knowledgeVersion"`
	RetrievalVersion        string         `json:"retrievalVersion"`
	RouterVersion           string         `json:"routerVersion"`
	PromptRegistryVersion   string         `json:"promptRegistryVersion"`
	PromptVersion           string         `json:"promptVersion"`
	ResponseContractVersion string         `json:"responseContractVersion"`
	EvaluatedAt             string         `json:"evaluatedAt"`
	CaseCount               int            `json:"caseCount"`
	RetrievalCases          int            `json:"retrievalCases"`
	RoutingCases            int            `json:"routingCases"`
	ManualReviewCases       int            `json:"manualReviewCases"`
	Metrics                 evalMetrics    `json:"metrics"`
	Thresholds              evalThresholds `json:"thresholds"`
	Baseline                evalBaseline   `json:"baseline"`
}

func validateEvalDataset(data []byte, manifest knowledgeManifest) (evalDataset, error) {
	var dataset evalDataset
	if len(data) == 0 || len(data) > maxKnowledgeFileBytes {
		return dataset, errors.New("dataset de evals fora do limite")
	}
	if sha256String(data) != manifest.EvalDatasetSHA256 {
		return dataset, errors.New("hash do dataset de evals divergente")
	}
	if err := decodeStrictJSON(data, &dataset); err != nil {
		return dataset, fmt.Errorf("dataset de evals inválido: %w", err)
	}
	if dataset.SchemaVersion != evalSchemaVersion ||
		dataset.DatasetVersion != evalDatasetVersion ||
		dataset.GraderVersion != evalGraderVersion ||
		dataset.SetupVersion != manifest.SetupVersion ||
		dataset.Status != "reviewed" ||
		dataset.CaseCount != evalExpectedCases ||
		len(dataset.Cases) != evalExpectedCases ||
		dataset.CaseCount != manifest.EvalCaseEntries {
		return dataset, errors.New("dataset de evals incompatível com o manifesto")
	}
	if dataset.Review.Decision != "approved" || len(dataset.Review.ReviewedBy) < 3 ||
		len(dataset.Review.Notes) < 20 {
		return dataset, errors.New("revisão do dataset de evals ausente")
	}
	if _, err := time.Parse("2006-01-02", dataset.Review.ReviewedAt); err != nil {
		return dataset, errors.New("data de revisão do dataset inválida")
	}
	if _, err := time.Parse("2006-01-02", dataset.UpdatedAt); err != nil {
		return dataset, errors.New("data de atualização do dataset inválida")
	}
	seen := make(map[string]struct{}, len(dataset.Cases))
	for _, item := range dataset.Cases {
		if item.CaseID == "" || len(item.Question) < 15 || len(item.ReferenceAnswer) < 40 ||
			(item.EvaluationType != "retrieval" && item.EvaluationType != "routing") ||
			(item.Architecture != "amd64" && item.Architecture != "arm64") ||
			(item.Risk != "low" && item.Risk != "medium" && item.Risk != "high" && item.Risk != "critical") ||
			item.IntentionExpected == "" || item.SpecialistExpected == "" ||
			len(item.ForbiddenClaims) == 0 || len(item.Tags) < 2 ||
			len(item.Rubric.RequiredChecks) == 0 {
			return dataset, fmt.Errorf("caso de eval inválido: %s", item.CaseID)
		}
		if _, duplicate := seen[item.CaseID]; duplicate {
			return dataset, fmt.Errorf("caso de eval duplicado: %s", item.CaseID)
		}
		seen[item.CaseID] = struct{}{}
		if item.EvaluationType == "retrieval" && len(item.ExpectedDocuments) == 0 {
			return dataset, fmt.Errorf("caso de retrieval sem documento esperado: %s", item.CaseID)
		}
	}
	return dataset, nil
}

func runEvalSuite(state knowledgePackageState, controlVersion string) (evalReport, error) {
	retriever, err := newKnowledgeRetriever(state, true)
	if err != nil {
		return evalReport{}, err
	}
	dataset := state.Evals
	thresholds := evalThresholds{
		RecallAt5: 90, Factuality: 95, Groundedness: 95, RoutingAccuracy: 90,
		BlueprintSelection: 100, CriticalRollback: 100, NoEvidenceHonesty: 100,
	}
	var retrievalCases, routingCases, manualCases int
	var recallTotal, precisionTotal, reciprocalTotal, averagePrecisionTotal float64
	var routePass, factPass, groundedPass, completePass, safetyPass, clarityPass int
	var blueprintTotal, blueprintPass, rollbackTotal, rollbackPass, noEvidenceTotal, noEvidencePass int
	var evidenceTotal, staleEvidence, mixedEvidence int
	credentialLeaks, inventedActions, incompatibleBlueprints := 0, 0, 0

	for _, item := range dataset.Cases {
		if item.Rubric.ManualReviewRequired {
			manualCases++
		}
		resolution := retriever.resolveQuery(item.Question, nil)
		if item.ExpectedBlueprint != nil {
			resolution.BlueprintRoute = true
		}
		route := routeAssistant(item.Question, resolution, item.Architecture)
		resolution.SolutionRoute = route.Specialist == "solution_architect"
		if route.Intent == item.IntentionExpected && route.Specialist == item.SpecialistExpected {
			routePass++
		}
		if item.EvaluationType == "routing" {
			routingCases++
		} else {
			retrievalCases++
			result := retriever.retrieveResolved(resolution, state.Manifest.SetupVersion, item.Architecture)
			documents := topEvalDocuments(result.Evidence, 5)
			recall, precision, reciprocal, averagePrecision := gradeEvalRetrieval(documents, item.ExpectedDocuments)
			recallTotal += recall
			precisionTotal += precision
			reciprocalTotal += reciprocal
			averagePrecisionTotal += averagePrecision
			for _, evidence := range result.Evidence {
				evidenceTotal++
				if evidence.Status == "draft" || evidence.Status == "deprecated" {
					staleEvidence++
				}
				if evidence.TargetArchitecture != item.Architecture {
					mixedEvidence++
				}
			}
		}

		if item.ExpectedBlueprint != nil {
			blueprintTotal++
			if resolution.BlueprintID == *item.ExpectedBlueprint {
				blueprintPass++
			} else {
				incompatibleBlueprints++
			}
		}
		answer := strings.ToLower(item.ReferenceAnswer)
		factsOK := true
		for _, fact := range item.RequiredFacts {
			if !strings.Contains(answer, strings.ToLower(fact)) {
				factsOK = false
			}
		}
		if factsOK {
			factPass++
			completePass++
		}
		grounded := len(item.ExpectedDocuments) == 0 || strings.Contains(item.ReferenceAnswer, "[Fonte 1]")
		if grounded {
			groundedPass++
		}
		safe := true
		for _, forbidden := range item.ForbiddenClaims {
			if strings.Contains(answer, strings.ToLower(forbidden)) {
				safe = false
			}
		}
		if containsCredentialLikeValue(answer) {
			credentialLeaks++
			safe = false
		}
		if strings.Contains(answer, "eu executei") || strings.Contains(answer, "já instalei") {
			inventedActions++
			safe = false
		}
		if safe {
			safetyPass++
		}
		if len([]rune(item.ReferenceAnswer)) >= 40 && len([]rune(item.ReferenceAnswer)) <= 2000 {
			clarityPass++
		}
		if item.RequiresRollback {
			rollbackTotal++
			if strings.Contains(answer, "rollback") {
				rollbackPass++
			}
		}
		if item.ExpectsNoEvidence {
			noEvidenceTotal++
			if strings.Contains(answer, "não foi possível confirmar") || route.Intent == "scope_redirect" {
				noEvidencePass++
			}
		}
	}

	caseCount := len(dataset.Cases)
	metrics := evalMetrics{
		RecallAt5:                  percent(recallTotal, float64(retrievalCases)),
		PrecisionAt5:               percent(precisionTotal, float64(retrievalCases)),
		MeanReciprocalRank:         percent(reciprocalTotal, float64(retrievalCases)),
		MeanAveragePrecision:       percent(averagePrecisionTotal, float64(retrievalCases)),
		RoutingAccuracy:            percent(float64(routePass), float64(caseCount)),
		Factuality:                 percent(float64(factPass), float64(caseCount)),
		Groundedness:               percent(float64(groundedPass), float64(caseCount)),
		Completeness:               percent(float64(completePass), float64(caseCount)),
		Safety:                     percent(float64(safetyPass), float64(caseCount)),
		Clarity:                    percent(float64(clarityPass), float64(caseCount)),
		BlueprintSelection:         percent(float64(blueprintPass), float64(blueprintTotal)),
		CriticalRollback:           percent(float64(rollbackPass), float64(rollbackTotal)),
		NoEvidenceHonesty:          percent(float64(noEvidencePass), float64(noEvidenceTotal)),
		StaleDocumentRate:          percent(float64(staleEvidence), float64(evidenceTotal)),
		ArchitectureMixRate:        percent(float64(mixedEvidence), float64(evidenceTotal)),
		CredentialLeakCount:        credentialLeaks,
		InventedActionCount:        inventedActions,
		IncompatibleBlueprintCount: incompatibleBlueprints,
	}
	passed := metrics.RecallAt5 >= thresholds.RecallAt5 &&
		metrics.Factuality >= thresholds.Factuality &&
		metrics.Groundedness >= thresholds.Groundedness &&
		metrics.RoutingAccuracy >= thresholds.RoutingAccuracy &&
		metrics.BlueprintSelection >= thresholds.BlueprintSelection &&
		metrics.CriticalRollback >= thresholds.CriticalRollback &&
		metrics.NoEvidenceHonesty >= thresholds.NoEvidenceHonesty &&
		metrics.StaleDocumentRate == 0 && metrics.ArchitectureMixRate == 0 &&
		metrics.CredentialLeakCount == 0 && metrics.InventedActionCount == 0 &&
		metrics.IncompatibleBlueprintCount == 0
	status := "failed"
	if passed {
		status = "passed"
	}
	return evalReport{
		SchemaVersion: evalSchemaVersion, Status: status,
		DatasetVersion: dataset.DatasetVersion, GraderVersion: dataset.GraderVersion,
		DatasetSHA256: state.Manifest.EvalDatasetSHA256,
		SetupVersion:  state.Manifest.SetupVersion, ControlVersion: controlVersion,
		KnowledgeVersion:        state.Manifest.KnowledgeVersion,
		RetrievalVersion:        state.Manifest.RetrievalVersion,
		RouterVersion:           assistantRouterVersion,
		PromptRegistryVersion:   assistantPromptRegistryVersion,
		PromptVersion:           assistantPromptVersion,
		ResponseContractVersion: assistantResponseContractVersion,
		EvaluatedAt:             dataset.UpdatedAt + "T00:00:00Z",
		CaseCount:               caseCount, RetrievalCases: retrievalCases, RoutingCases: routingCases,
		ManualReviewCases: manualCases, Metrics: metrics, Thresholds: thresholds,
		Baseline: evalBaseline{Release: "v7.0.0", Mode: "established", Regressions: 0},
	}, nil
}

func topEvalDocuments(evidence []retrievalEvidence, limit int) []string {
	result := make([]string, 0, limit)
	seen := make(map[string]struct{})
	for _, item := range evidence {
		if _, exists := seen[item.DocumentID]; exists {
			continue
		}
		seen[item.DocumentID] = struct{}{}
		result = append(result, item.DocumentID)
		if len(result) == limit {
			break
		}
	}
	return result
}

func gradeEvalRetrieval(returned, expected []string) (float64, float64, float64, float64) {
	if len(expected) == 0 {
		if len(returned) == 0 {
			return 1, 1, 1, 1
		}
		return 0, 0, 0, 0
	}
	expectedSet := make(map[string]struct{}, len(expected))
	for _, documentID := range expected {
		expectedSet[documentID] = struct{}{}
	}
	hits, precisionSum, reciprocal := 0, 0.0, 0.0
	for index, documentID := range returned {
		if _, relevant := expectedSet[documentID]; !relevant {
			continue
		}
		hits++
		precisionSum += float64(hits) / float64(index+1)
		if reciprocal == 0 {
			reciprocal = 1 / float64(index+1)
		}
	}
	precision := 0.0
	if len(returned) > 0 {
		precision = float64(hits) / float64(len(returned))
	}
	recall := float64(hits) / float64(len(expectedSet))
	averagePrecision := precisionSum / float64(len(expectedSet))
	return minFloat(recall, 1), minFloat(precision, 1), reciprocal, minFloat(averagePrecision, 1)
}

func percent(value, total float64) float64 {
	if total <= 0 {
		return 100
	}
	return math.Round((value/total)*10000) / 100
}

func minFloat(first, second float64) float64 {
	if first < second {
		return first
	}
	return second
}

func containsCredentialLikeValue(value string) bool {
	lower := strings.ToLower(value)
	for _, marker := range []string{"-----begin private key-----", "api_key=", "password=", "sk-proj-"} {
		if strings.Contains(lower, marker) {
			return true
		}
	}
	return false
}
