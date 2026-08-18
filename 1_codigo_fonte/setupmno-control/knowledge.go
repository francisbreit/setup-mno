package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"math"
	"os"
	"path"
	"path/filepath"
	"reflect"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	knowledgeSchema          = 1
	knowledgeIndexSchema     = 2
	knowledgeRetrieval       = "1.3.0"
	knowledgeQualitySchema   = 2
	blueprintSchema          = 2
	maxBlueprintEntries      = 64
	maxKnowledgeArchiveBytes = 8 << 20
	maxKnowledgeManifest     = 1 << 20
	maxKnowledgeFileBytes    = 3 << 20
	maxKnowledgeFiles        = 1024
	maxKnowledgeChunks       = 4096
	maxKnowledgeChunkRunes   = 2400
)

//go:embed knowledge-package/*
var embeddedKnowledgeFiles embed.FS

type knowledgeFileRecord struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

type knowledgeLimits struct {
	MaxArchiveBytes     int64 `json:"maxArchiveBytes"`
	MaxDocumentBytes    int64 `json:"maxDocumentBytes"`
	MaxEvalDatasetBytes int64 `json:"maxEvalDatasetBytes"`
	MaxDocuments        int   `json:"maxDocuments"`
	MaxIndexBytes       int64 `json:"maxIndexBytes"`
}

type knowledgeManifest struct {
	SchemaVersion             int                     `json:"schemaVersion"`
	KnowledgeVersion          string                  `json:"knowledgeVersion"`
	SetupVersion              string                  `json:"setupVersion"`
	ControlVersion            string                  `json:"controlVersion"`
	GeneratedAt               string                  `json:"generatedAt"`
	ArchiveFile               string                  `json:"archiveFile"`
	ArchiveSHA256             string                  `json:"archiveSHA256"`
	ArchiveBytes              int64                   `json:"archiveBytes"`
	IndexSHA256               string                  `json:"indexSHA256"`
	LegacyIndexSHA256         string                  `json:"legacyIndexSHA256"`
	IndexSchemaVersion        int                     `json:"indexSchemaVersion"`
	RetrievalVersion          string                  `json:"retrievalVersion"`
	EvalSchemaVersion         int                     `json:"evalSchemaVersion"`
	EvalDatasetVersion        string                  `json:"evalDatasetVersion"`
	EvalGraderVersion         string                  `json:"evalGraderVersion"`
	EvalDatasetSHA256         string                  `json:"evalDatasetSHA256"`
	EvalCaseEntries           int                     `json:"evalCaseEntries"`
	DocumentEntries           int                     `json:"documentEntries"`
	ChunkEntries              int                     `json:"chunkEntries"`
	DocumentTypeEntries       map[string]int          `json:"documentTypeEntries"`
	SetupEntries              int                     `json:"setupEntries"`
	InfrastructureEntries     int                     `json:"infrastructureEntries"`
	BlueprintSchemaVersion    int                     `json:"blueprintSchemaVersion"`
	BlueprintFactoryVersion   string                  `json:"blueprintFactoryVersion"`
	BlueprintEntries          int                     `json:"blueprintEntries"`
	BlueprintBundleEntries    int                     `json:"blueprintBundleEntries"`
	BlueprintIndexSHA256      string                  `json:"blueprintIndexSHA256"`
	BlueprintKnowledgeEntries int                     `json:"blueprintKnowledgeEntries"`
	BlueprintFixtureEntries   int                     `json:"blueprintFixtureEntries"`
	QualitySchemaVersion      int                     `json:"qualitySchemaVersion"`
	QualityReportSHA256       string                  `json:"qualityReportSHA256"`
	QualitySummary            knowledgeQualitySummary `json:"qualitySummary"`
	FileEntries               int                     `json:"fileEntries"`
	Limits                    knowledgeLimits         `json:"limits"`
	Files                     []knowledgeFileRecord   `json:"files"`
}

type knowledgeQualitySummary struct {
	SetupEntries               int            `json:"setupEntries"`
	InstallationStatuses       map[string]int `json:"installationStatuses"`
	IntegrationMaturityLevels  map[string]int `json:"integrationMaturityLevels"`
	EditorialStatuses          map[string]int `json:"editorialStatuses"`
	MaturityLevels             map[string]int `json:"maturityLevels"`
	OfficialSourceEntries      int            `json:"officialSourceEntries"`
	OfficialSourceExceptions   int            `json:"officialSourceExceptions"`
	InternalOnlySourceEntries  int            `json:"internalOnlySourceEntries"`
	OperationalEvidenceEntries int            `json:"operationalEvidenceEntries"`
	HomologatedEntries         int            `json:"homologatedEntries"`
	IssueEntries               int            `json:"issueEntries"`
	UnresolvedIssueCount       int            `json:"unresolvedIssueCount"`
}

type knowledgeQualityEntry struct {
	SetupID                     string   `json:"setupId"`
	CatalogName                 string   `json:"catalogName"`
	EditorialStatus             string   `json:"editorialStatus"`
	Maturity                    string   `json:"maturity"`
	SourceClassification        string   `json:"sourceClassification"`
	ScriptSourceDeclared        bool     `json:"scriptSourceDeclared"`
	OperationalEvidence         bool     `json:"operationalEvidence"`
	OperationalCoverage         string   `json:"operationalCoverage"`
	OperationalArchitectures    []string `json:"operationalArchitectures"`
	OperationalEvidenceIDs      []string `json:"operationalEvidenceIds"`
	LastOperationalVerification string   `json:"lastOperationalVerification"`
	HomologationEvidence        bool     `json:"homologationEvidence"`
	InstallationStatus          string   `json:"installationStatus"`
	TestedArchitectures         []string `json:"testedArchitectures"`
	IntegrationMaturity         string   `json:"integrationMaturity"`
	Issues                      []string `json:"issues"`
}

type knowledgeQualityReport struct {
	SchemaVersion         int                     `json:"schemaVersion"`
	EvidenceSchemaVersion int                     `json:"evidenceSchemaVersion"`
	SetupVersion          string                  `json:"setupVersion"`
	KnowledgeVersion      string                  `json:"knowledgeVersion"`
	GeneratedAt           string                  `json:"generatedAt"`
	Summary               knowledgeQualitySummary `json:"summary"`
	Entries               []knowledgeQualityEntry `json:"entries"`
}

type knowledgeIndexEntry struct {
	Architectures   []string `json:"architectures"`
	Category        string   `json:"category"`
	BlueprintID     *string  `json:"blueprintId"`
	Fictitious      bool     `json:"fictitious"`
	Deployable      bool     `json:"deployable"`
	ContentSHA256   string   `json:"contentSHA256"`
	DocumentID      string   `json:"documentId"`
	DocumentType    string   `json:"documentType"`
	DocumentVersion string   `json:"documentVersion"`
	Path            string   `json:"path"`
	Risk            string   `json:"risk"`
	SetupID         *string  `json:"setupId"`
	SetupVersion    string   `json:"setupVersion"`
	SourcePath      string   `json:"sourcePath"`
	Status          string   `json:"status"`
	Tags            []string `json:"tags"`
	Terms           []string `json:"terms"`
	Title           string   `json:"title"`
	TopicID         *string  `json:"topicId"`
	UpdatedAt       string   `json:"updatedAt"`
}

type knowledgeIndex struct {
	SchemaVersion           int                   `json:"schemaVersion"`
	KnowledgeVersion        string                `json:"knowledgeVersion"`
	SetupVersion            string                `json:"setupVersion"`
	NormalRetrievalStatuses []string              `json:"normalRetrievalStatuses"`
	Entries                 []knowledgeIndexEntry `json:"entries"`
	InvertedIndex           map[string][]string   `json:"invertedIndex"`
}

type knowledgeChunk struct {
	Aliases              []string                  `json:"aliases"`
	Architectures        []string                  `json:"architectures"`
	Category             string                    `json:"category"`
	BlueprintID          *string                   `json:"blueprintId"`
	Fictitious           bool                      `json:"fictitious"`
	Deployable           bool                      `json:"deployable"`
	ChunkID              string                    `json:"chunkId"`
	Content              string                    `json:"content"`
	ContentSHA256        string                    `json:"contentSHA256"`
	DocumentID           string                    `json:"documentId"`
	DocumentType         string                    `json:"documentType"`
	DocumentVersion      string                    `json:"documentVersion"`
	FieldLengths         map[string]int            `json:"fieldLengths"`
	FieldTermFrequencies map[string]map[string]int `json:"fieldTermFrequencies"`
	Heading              string                    `json:"heading"`
	SetupID              *string                   `json:"setupId"`
	SetupVersion         string                    `json:"setupVersion"`
	Status               string                    `json:"status"`
	Tags                 []string                  `json:"tags"`
	Title                string                    `json:"title"`
	TopicID              *string                   `json:"topicId"`
}

type knowledgeIndexV2 struct {
	SchemaVersion           int                 `json:"schemaVersion"`
	RetrievalVersion        string              `json:"retrievalVersion"`
	KnowledgeVersion        string              `json:"knowledgeVersion"`
	SetupVersion            string              `json:"setupVersion"`
	NormalRetrievalStatuses []string            `json:"normalRetrievalStatuses"`
	Synonyms                map[string][]string `json:"synonyms"`
	ChunkCount              int                 `json:"chunkCount"`
	AverageFieldLengths     map[string]float64  `json:"averageFieldLengths"`
	DocumentFrequencies     map[string]int      `json:"documentFrequencies"`
	Chunks                  []knowledgeChunk    `json:"chunks"`
}

type knowledgePackageState struct {
	Manifest   knowledgeManifest
	Index      knowledgeIndex
	IndexV2    knowledgeIndexV2
	Blueprints blueprintIndex
	Evals      evalDataset
	Quality    knowledgeQualityReport
	Files      map[string][]byte
	Source     string
	Stale      bool
}

type blueprintMediaEntry struct {
	MediaID    string  `json:"mediaId"`
	Type       string  `json:"type"`
	Title      string  `json:"title"`
	URL        *string `json:"url"`
	Status     string  `json:"status"`
	Transcript *string `json:"transcript"`
}

type blueprintComponentDetail struct {
	CatalogName  string `json:"catalogName"`
	Role         string `json:"role"`
	Required     bool   `json:"required"`
	InstallOrder int    `json:"installOrder"`
}

type blueprintInstallationStep struct {
	Step              int    `json:"step"`
	Component         string `json:"component"`
	Title             string `json:"title"`
	Description       string `json:"description"`
	HumanConfirmation bool   `json:"humanConfirmation"`
}

type blueprintInstallation struct {
	Mode                      string                      `json:"mode"`
	HumanConfirmationRequired bool                        `json:"humanConfirmationRequired"`
	Steps                     []blueprintInstallationStep `json:"steps"`
}

type blueprintValidationCheck struct {
	CheckID     string `json:"checkId"`
	Description string `json:"description"`
	Expected    string `json:"expected"`
	Required    bool   `json:"required"`
}

type blueprintValidation struct {
	HomologatedAt *string                    `json:"homologatedAt"`
	Checks        []blueprintValidationCheck `json:"checks"`
}

type blueprintRollback struct {
	Strategy string   `json:"strategy"`
	Steps    []string `json:"steps"`
}

type blueprintResourceProfile struct {
	MinimumRAMGB     int    `json:"minimumRamGB"`
	RecommendedRAMGB int    `json:"recommendedRamGB"`
	Basis            string `json:"basis"`
}

type blueprintEditorialHistory struct {
	Stage     string `json:"stage"`
	ChangedAt string `json:"changedAt"`
	Actor     string `json:"actor"`
	Note      string `json:"note"`
}

type blueprintEditorialReview struct {
	Decision   string  `json:"decision"`
	ReviewedAt *string `json:"reviewedAt"`
	ReviewedBy *string `json:"reviewedBy"`
	Notes      string  `json:"notes"`
}

type blueprintEditorialEvidence struct {
	EvidenceID   string `json:"evidenceId"`
	Type         string `json:"type"`
	Title        string `json:"title"`
	SHA256       string `json:"sha256"`
	VerifiedAt   string `json:"verifiedAt"`
	Architecture string `json:"architecture"`
}

type blueprintEditorialHomologation struct {
	Environment   string                       `json:"environment"`
	TestedAt      *string                      `json:"testedAt"`
	Architectures []string                     `json:"architectures"`
	Evidence      []blueprintEditorialEvidence `json:"evidence"`
}

type blueprintEditorialGate struct {
	GateID string `json:"gateId"`
	Title  string `json:"title"`
	Passed bool   `json:"passed"`
}

type blueprintVersionSeal struct {
	Algorithm      string `json:"algorithm"`
	ManifestSHA256 string `json:"manifestSHA256"`
	PayloadSHA256  string `json:"payloadSHA256"`
}

type blueprintEditorial struct {
	CurrentStage   string                         `json:"currentStage"`
	History        []blueprintEditorialHistory    `json:"history"`
	Review         blueprintEditorialReview       `json:"review"`
	Homologation   blueprintEditorialHomologation `json:"homologation"`
	Gates          []blueprintEditorialGate       `json:"gates"`
	PassedGates    int                            `json:"passedGates"`
	TotalGates     int                            `json:"totalGates"`
	PromotionReady bool                           `json:"promotionReady"`
	VersionSeal    blueprintVersionSeal           `json:"versionSeal"`
}

type blueprintIndexEntry struct {
	Aliases          []string                   `json:"aliases"`
	Architectures    []string                   `json:"architectures"`
	Author           string                     `json:"author"`
	BlueprintID      string                     `json:"blueprintId"`
	BlueprintVersion string                     `json:"blueprintVersion"`
	BundleBytes      int64                      `json:"bundleBytes"`
	BundlePath       string                     `json:"bundlePath"`
	BundleSHA256     string                     `json:"bundleSHA256"`
	Components       []string                   `json:"components"`
	ComponentDetails []blueprintComponentDetail `json:"componentDetails"`
	Deployable       bool                       `json:"deployable"`
	Editorial        blueprintEditorial         `json:"editorial"`
	Fictitious       bool                       `json:"fictitious"`
	Media            []blueprintMediaEntry      `json:"media"`
	Installation     blueprintInstallation      `json:"installation"`
	Validation       blueprintValidation        `json:"validation"`
	Rollback         blueprintRollback          `json:"rollback"`
	Objective        string                     `json:"objective"`
	ResourceProfile  blueprintResourceProfile   `json:"resourceProfile"`
	Risk             string                     `json:"risk"`
	Status           string                     `json:"status"`
	Summary          string                     `json:"summary"`
	Tags             []string                   `json:"tags"`
	Title            string                     `json:"title"`
	UpdatedAt        string                     `json:"updatedAt"`
}

type blueprintIndex struct {
	SchemaVersion  int                   `json:"schemaVersion"`
	FactoryVersion string                `json:"factoryVersion"`
	SetupVersion   string                `json:"setupVersion"`
	BlueprintCount int                   `json:"blueprintCount"`
	Statuses       map[string]int        `json:"statuses"`
	Entries        []blueprintIndexEntry `json:"entries"`
}

func sha256String(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func decodeStrictJSON(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("JSON contém valores adicionais")
	}
	return nil
}

func safeKnowledgePath(name string) bool {
	if name == "" || strings.HasPrefix(name, "/") || strings.Contains(name, "\\") {
		return false
	}
	cleaned := path.Clean(name)
	return cleaned == name && cleaned != "." && !strings.HasPrefix(cleaned, "../")
}

func readRegularLimited(filename string, maximum int64) ([]byte, error) {
	info, err := os.Lstat(filename)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("arquivo ausente, não regular ou symlink")
	}
	if info.Size() <= 0 || info.Size() > maximum {
		return nil, fmt.Errorf("tamanho fora do limite: %d", info.Size())
	}
	return os.ReadFile(filename)
}

func loadKnowledgePackageDirectory(directory string) (knowledgePackageState, error) {
	archiveData, err := readRegularLimited(
		filepath.Join(directory, "knowledge-package.tar.gz"),
		maxKnowledgeArchiveBytes,
	)
	if err != nil {
		return knowledgePackageState{}, fmt.Errorf("arquivo compactado: %w", err)
	}
	manifestData, err := readRegularLimited(
		filepath.Join(directory, "manifest.json"),
		maxKnowledgeManifest,
	)
	if err != nil {
		return knowledgePackageState{}, fmt.Errorf("manifesto: %w", err)
	}
	state, err := validateKnowledgePackage(archiveData, manifestData)
	if err != nil {
		return knowledgePackageState{}, err
	}
	state.Source = "image-read-only"
	return state, nil
}

func loadEmbeddedKnowledgePackage() (knowledgePackageState, error) {
	archiveData, err := fs.ReadFile(
		embeddedKnowledgeFiles,
		"knowledge-package/knowledge-package.tar.gz",
	)
	if err != nil {
		return knowledgePackageState{}, err
	}
	manifestData, err := fs.ReadFile(
		embeddedKnowledgeFiles,
		"knowledge-package/manifest.json",
	)
	if err != nil {
		return knowledgePackageState{}, err
	}
	state, err := validateKnowledgePackage(archiveData, manifestData)
	if err != nil {
		return knowledgePackageState{}, err
	}
	state.Source = "embedded-fallback"
	state.Stale = true
	return state, nil
}

func loadRuntimeKnowledgePackage() (knowledgePackageState, error) {
	directory := envDefault("KNOWLEDGE_PACKAGE_DIR", "/knowledge-package")
	primary, primaryErr := loadKnowledgePackageDirectory(directory)
	if primaryErr == nil {
		return primary, nil
	}
	fallback, fallbackErr := loadEmbeddedKnowledgePackage()
	if fallbackErr == nil {
		return fallback, nil
	}
	return knowledgePackageState{}, fmt.Errorf(
		"pacote primário inválido (%v) e fallback embutido inválido (%v)",
		primaryErr,
		fallbackErr,
	)
}

func validateKnowledgePackage(
	archiveData []byte,
	manifestData []byte,
) (knowledgePackageState, error) {
	if len(archiveData) == 0 || len(archiveData) > maxKnowledgeArchiveBytes {
		return knowledgePackageState{}, errors.New("arquivo compactado fora do limite")
	}
	if len(manifestData) == 0 || len(manifestData) > maxKnowledgeManifest {
		return knowledgePackageState{}, errors.New("manifesto fora do limite")
	}
	var manifest knowledgeManifest
	if err := decodeStrictJSON(manifestData, &manifest); err != nil {
		return knowledgePackageState{}, fmt.Errorf("manifesto inválido: %w", err)
	}
	if manifest.SchemaVersion != knowledgeSchema ||
		manifest.IndexSchemaVersion != knowledgeIndexSchema ||
		manifest.RetrievalVersion != knowledgeRetrieval ||
		manifest.EvalSchemaVersion != evalSchemaVersion ||
		manifest.EvalDatasetVersion != evalDatasetVersion ||
		manifest.EvalGraderVersion != evalGraderVersion ||
		manifest.BlueprintSchemaVersion != blueprintSchema ||
		manifest.BlueprintFactoryVersion == "" ||
		manifest.QualitySchemaVersion != knowledgeQualitySchema ||
		manifest.KnowledgeVersion == "" ||
		manifest.SetupVersion == "" ||
		manifest.ControlVersion == "" {
		return knowledgePackageState{}, errors.New("versões ou schema inválidos")
	}
	if manifest.ArchiveFile != "knowledge-package.tar.gz" ||
		manifest.ArchiveBytes != int64(len(archiveData)) ||
		manifest.ArchiveSHA256 != sha256String(archiveData) {
		return knowledgePackageState{}, errors.New("hash ou tamanho do arquivo compactado divergente")
	}
	if manifest.DocumentEntries <= 0 ||
		manifest.DocumentEntries > maxKnowledgeFiles ||
		manifest.ChunkEntries <= 0 ||
		manifest.ChunkEntries > maxKnowledgeChunks ||
		manifest.SetupEntries < 0 ||
		manifest.InfrastructureEntries < 0 ||
		manifest.BlueprintEntries <= 0 ||
		manifest.BlueprintEntries > maxBlueprintEntries ||
		manifest.BlueprintBundleEntries != manifest.BlueprintEntries ||
		manifest.BlueprintKnowledgeEntries <= 0 ||
		manifest.BlueprintKnowledgeEntries > manifest.BlueprintEntries ||
		manifest.BlueprintFixtureEntries < 0 ||
		manifest.BlueprintFixtureEntries > manifest.BlueprintKnowledgeEntries ||
		len(manifest.BlueprintIndexSHA256) != 64 ||
		len(manifest.QualityReportSHA256) != 64 ||
		manifest.EvalCaseEntries != evalExpectedCases ||
		len(manifest.EvalDatasetSHA256) != 64 {
		return knowledgePackageState{}, errors.New("contagens do manifesto inválidas")
	}
	typeTotal := 0
	for documentType, count := range manifest.DocumentTypeEntries {
		if documentType == "" || count < 0 {
			return knowledgePackageState{}, errors.New("contagem de tipo inválida")
		}
		typeTotal += count
	}
	if typeTotal != manifest.DocumentEntries {
		return knowledgePackageState{}, errors.New("contagens por tipo divergentes")
	}
	if manifest.FileEntries <= 0 ||
		manifest.FileEntries != len(manifest.Files) ||
		manifest.FileEntries > maxKnowledgeFiles {
		return knowledgePackageState{}, errors.New("inventário do manifesto inválido")
	}
	if manifest.Limits.MaxArchiveBytes <= 0 ||
		manifest.Limits.MaxArchiveBytes > maxKnowledgeArchiveBytes ||
		manifest.Limits.MaxDocumentBytes <= 0 ||
		manifest.Limits.MaxDocumentBytes > maxKnowledgeFileBytes ||
		manifest.Limits.MaxEvalDatasetBytes <= 0 ||
		manifest.Limits.MaxEvalDatasetBytes > maxKnowledgeFileBytes ||
		manifest.Limits.MaxDocuments < manifest.DocumentEntries ||
		manifest.Limits.MaxIndexBytes <= 0 ||
		manifest.Limits.MaxIndexBytes > maxKnowledgeFileBytes {
		return knowledgePackageState{}, errors.New("limites do manifesto inválidos")
	}

	files, err := readKnowledgeArchive(archiveData)
	if err != nil {
		return knowledgePackageState{}, err
	}
	inventory := make(map[string]knowledgeFileRecord, len(manifest.Files))
	for _, record := range manifest.Files {
		if !safeKnowledgePath(record.Path) ||
			len(record.SHA256) != 64 ||
			record.Size <= 0 ||
			record.Size > maxKnowledgeFileBytes {
			return knowledgePackageState{}, fmt.Errorf("entrada inválida no inventário: %q", record.Path)
		}
		if _, exists := inventory[record.Path]; exists {
			return knowledgePackageState{}, fmt.Errorf("entrada duplicada no inventário: %s", record.Path)
		}
		inventory[record.Path] = record
	}
	if len(files) != len(inventory) {
		return knowledgePackageState{}, errors.New("quantidade de arquivos diverge do inventário")
	}
	for filename, data := range files {
		record, exists := inventory[filename]
		if !exists ||
			record.Size != int64(len(data)) ||
			record.SHA256 != sha256String(data) {
			return knowledgePackageState{}, fmt.Errorf("arquivo diverge do inventário: %s", filename)
		}
	}
	qualityData, exists := files["registry/quality-report.json"]
	if !exists || manifest.QualityReportSHA256 != sha256String(qualityData) {
		return knowledgePackageState{}, errors.New("relatório de qualidade ausente ou divergente")
	}
	var qualityReport knowledgeQualityReport
	if err := decodeStrictJSON(qualityData, &qualityReport); err != nil {
		return knowledgePackageState{}, fmt.Errorf("relatório de qualidade inválido: %w", err)
	}
	if err := validateKnowledgeQualityReport(qualityReport, manifest); err != nil {
		return knowledgePackageState{}, err
	}
	if err := validateBlueprintPackage(files, manifest); err != nil {
		return knowledgePackageState{}, err
	}
	evalData, exists := files["evals/dataset.json"]
	if !exists {
		return knowledgePackageState{}, errors.New("dataset de evals ausente")
	}
	if int64(len(evalData)) > manifest.Limits.MaxEvalDatasetBytes {
		return knowledgePackageState{}, errors.New("dataset de evals excede o limite declarado")
	}
	evalDataset, err := validateEvalDataset(evalData, manifest)
	if err != nil {
		return knowledgePackageState{}, err
	}

	indexData, exists := files["index.json"]
	if !exists || manifest.IndexSHA256 != sha256String(indexData) {
		return knowledgePackageState{}, errors.New("índice ausente ou com hash divergente")
	}
	var indexV2 knowledgeIndexV2
	if err := decodeStrictJSON(indexData, &indexV2); err != nil {
		return knowledgePackageState{}, fmt.Errorf("índice v2 inválido: %w", err)
	}
	if indexV2.SchemaVersion != knowledgeIndexSchema ||
		indexV2.RetrievalVersion != manifest.RetrievalVersion ||
		indexV2.KnowledgeVersion != manifest.KnowledgeVersion ||
		indexV2.SetupVersion != manifest.SetupVersion ||
		len(indexV2.Synonyms) == 0 ||
		indexV2.ChunkCount != manifest.ChunkEntries ||
		len(indexV2.Chunks) != manifest.ChunkEntries {
		return knowledgePackageState{}, errors.New("índice v2 incompatível com o manifesto")
	}

	legacyIndexData, exists := files["index-v1.json"]
	if !exists || manifest.LegacyIndexSHA256 != sha256String(legacyIndexData) {
		return knowledgePackageState{}, errors.New(
			"índice v1 de contingência ausente ou com hash divergente",
		)
	}
	var index knowledgeIndex
	if err := decodeStrictJSON(legacyIndexData, &index); err != nil {
		return knowledgePackageState{}, fmt.Errorf("índice v1 inválido: %w", err)
	}
	if index.SchemaVersion != knowledgeSchema ||
		index.KnowledgeVersion != manifest.KnowledgeVersion ||
		index.SetupVersion != manifest.SetupVersion ||
		len(index.Entries) != manifest.DocumentEntries {
		return knowledgePackageState{}, errors.New("índice incompatível com o manifesto")
	}
	seenDocuments := make(map[string]struct{}, len(index.Entries))
	typeEntries := make(map[string]int)
	blueprintFixtureEntries := 0
	blueprintByID := make(map[string]blueprintIndexEntry)
	var blueprintCatalog blueprintIndex
	if err := decodeStrictJSON(files["blueprints/index.json"], &blueprintCatalog); err != nil {
		return knowledgePackageState{}, fmt.Errorf("índice de Blueprints inválido: %w", err)
	}
	for _, entry := range blueprintCatalog.Entries {
		blueprintByID[entry.BlueprintID] = entry
	}
	for _, entry := range index.Entries {
		if entry.DocumentID == "" ||
			entry.SetupVersion != manifest.SetupVersion ||
			(entry.Status != "reviewed" && entry.Status != "homologated") ||
			!safeKnowledgePath(entry.Path) {
			return knowledgePackageState{}, fmt.Errorf("documento inválido no índice: %q", entry.DocumentID)
		}
		if _, exists := files[entry.Path]; !exists {
			return knowledgePackageState{}, fmt.Errorf("documento ausente no pacote: %s", entry.Path)
		}
		if _, exists := seenDocuments[entry.DocumentID]; exists {
			return knowledgePackageState{}, fmt.Errorf("documentId duplicado: %s", entry.DocumentID)
		}
		seenDocuments[entry.DocumentID] = struct{}{}
		if entry.DocumentType == "" {
			return knowledgePackageState{}, fmt.Errorf(
				"tipo de documento ausente no pacote: %s",
				entry.DocumentType,
			)
		}
		if entry.DocumentType == "blueprint" {
			if entry.BlueprintID == nil || *entry.BlueprintID == "" {
				return knowledgePackageState{}, fmt.Errorf(
					"documento de Blueprint sem blueprintId: %s", entry.DocumentID,
				)
			}
			blueprintEntry, exists := blueprintByID[*entry.BlueprintID]
			if !exists || blueprintEntry.Fictitious != entry.Fictitious ||
				blueprintEntry.Deployable != entry.Deployable {
				return knowledgePackageState{}, fmt.Errorf(
					"documento diverge do Blueprint canônico: %s", entry.DocumentID,
				)
			}
			if entry.Fictitious {
				if entry.Deployable || entry.Status != "reviewed" {
					return knowledgePackageState{}, fmt.Errorf(
						"fixture de Blueprint insegura: %s", entry.DocumentID,
					)
				}
				blueprintFixtureEntries++
			} else if (entry.Status == "reviewed" && !entry.Deployable) ||
				(entry.Status == "homologated" && entry.Deployable) {
				// Guias Beta revisados são recuperáveis, mas permanecem não implantáveis.
			} else {
				return knowledgePackageState{}, fmt.Errorf("estado editorial inválido no Blueprint: %s", entry.DocumentID)
			}
		} else if entry.BlueprintID != nil || entry.Fictitious || entry.Deployable {
			return knowledgePackageState{}, fmt.Errorf(
				"metadados de Blueprint em documento incompatível: %s", entry.DocumentID,
			)
		}
		typeEntries[entry.DocumentType]++
	}
	if len(typeEntries) != len(manifest.DocumentTypeEntries) {
		return knowledgePackageState{}, errors.New("contagens do índice divergentes")
	}
	for documentType, count := range typeEntries {
		if manifest.DocumentTypeEntries[documentType] != count {
			return knowledgePackageState{}, errors.New("contagens do índice divergentes")
		}
	}
	if typeEntries["setup"] != manifest.SetupEntries ||
		typeEntries["infrastructure"] != manifest.InfrastructureEntries ||
		typeEntries["blueprint"] != manifest.BlueprintKnowledgeEntries ||
		blueprintFixtureEntries != manifest.BlueprintFixtureEntries {
		return knowledgePackageState{}, errors.New("contagens principais divergentes")
	}
	if err := validateKnowledgeIndexV2(indexV2, index); err != nil {
		return knowledgePackageState{}, err
	}
	return knowledgePackageState{
		Manifest:   manifest,
		Index:      index,
		IndexV2:    indexV2,
		Blueprints: blueprintCatalog,
		Evals:      evalDataset,
		Quality:    qualityReport,
		Files:      files,
	}, nil
}

func validateKnowledgeQualityReport(report knowledgeQualityReport, manifest knowledgeManifest) error {
	if report.SchemaVersion != manifest.QualitySchemaVersion ||
		report.EvidenceSchemaVersion != 1 ||
		report.SetupVersion != manifest.SetupVersion ||
		report.KnowledgeVersion != manifest.KnowledgeVersion ||
		report.GeneratedAt == "" ||
		report.Summary.SetupEntries != manifest.SetupEntries ||
		len(report.Entries) != manifest.SetupEntries ||
		!reflect.DeepEqual(report.Summary, manifest.QualitySummary) {
		return errors.New("relatório de qualidade incompatível com o manifesto")
	}
	expectedMaturity := map[string]bool{
		"structural": true, "source-reviewed": true, "script-reviewed": true,
		"operational-reviewed": true, "homologated": true,
	}
	expectedStatuses := map[string]bool{
		"draft": true, "reviewed": true, "homologated": true,
		"outdated": true, "deprecated": true,
	}
	expectedIntegrationMaturity := map[string]bool{
		"not-mapped": true, "suggested": true, "documented": true, "validated": true,
	}
	if len(report.Summary.MaturityLevels) != len(expectedMaturity) ||
		len(report.Summary.EditorialStatuses) != len(expectedStatuses) ||
		len(report.Summary.InstallationStatuses) != 1 ||
		len(report.Summary.IntegrationMaturityLevels) != len(expectedIntegrationMaturity) {
		return errors.New("taxonomia de qualidade incompleta")
	}
	maturityTotal := 0
	for maturity := range expectedMaturity {
		count, exists := report.Summary.MaturityLevels[maturity]
		if !exists || count < 0 {
			return errors.New("contagem de maturidade inválida")
		}
		maturityTotal += count
	}
	statusTotal := 0
	for status := range expectedStatuses {
		count, exists := report.Summary.EditorialStatuses[status]
		if !exists || count < 0 {
			return errors.New("contagem editorial inválida")
		}
		statusTotal += count
	}
	integrationTotal := 0
	for maturity := range expectedIntegrationMaturity {
		count, exists := report.Summary.IntegrationMaturityLevels[maturity]
		if !exists || count < 0 {
			return errors.New("contagem de maturidade de integrações inválida")
		}
		integrationTotal += count
	}
	if maturityTotal != manifest.SetupEntries || statusTotal != manifest.SetupEntries ||
		integrationTotal != manifest.SetupEntries ||
		report.Summary.InstallationStatuses["maintainer-homologated"] != manifest.SetupEntries ||
		report.Summary.HomologatedEntries != report.Summary.MaturityLevels["homologated"] ||
		report.Summary.OfficialSourceEntries < 0 ||
		report.Summary.OfficialSourceExceptions < 0 ||
		report.Summary.InternalOnlySourceEntries < 0 ||
		report.Summary.OfficialSourceEntries+report.Summary.OfficialSourceExceptions+
			report.Summary.InternalOnlySourceEntries != manifest.SetupEntries ||
		report.Summary.OperationalEvidenceEntries < 0 ||
		report.Summary.OperationalEvidenceEntries > manifest.SetupEntries ||
		report.Summary.IssueEntries < 0 ||
		report.Summary.IssueEntries > manifest.SetupEntries ||
		report.Summary.UnresolvedIssueCount < report.Summary.IssueEntries {
		return errors.New("resumo de qualidade inconsistente")
	}
	seen := make(map[string]struct{}, len(report.Entries))
	issueEntries := 0
	issueCount := 0
	operationalEntries := 0
	for _, entry := range report.Entries {
		if entry.SetupID == "" || entry.CatalogName == "" ||
			!expectedMaturity[entry.Maturity] || !expectedStatuses[entry.EditorialStatus] ||
			entry.InstallationStatus != "maintainer-homologated" ||
			!expectedIntegrationMaturity[entry.IntegrationMaturity] ||
			len(entry.TestedArchitectures) == 0 {
			return errors.New("entrada inválida no relatório de qualidade")
		}
		architectureSeen := make(map[string]bool, len(entry.TestedArchitectures))
		for _, architecture := range entry.TestedArchitectures {
			if (architecture != "amd64" && architecture != "arm64") || architectureSeen[architecture] {
				return errors.New("arquitetura testada inválida no relatório de qualidade")
			}
			architectureSeen[architecture] = true
		}
		operationalSeen := make(map[string]bool, len(entry.OperationalArchitectures))
		for _, architecture := range entry.OperationalArchitectures {
			if !architectureSeen[architecture] || operationalSeen[architecture] {
				return errors.New("cobertura operacional inválida no relatório de qualidade")
			}
			operationalSeen[architecture] = true
		}
		coverage := "none"
		if len(operationalSeen) > 0 && len(operationalSeen) < len(architectureSeen) {
			coverage = "partial"
		} else if len(operationalSeen) == len(architectureSeen) {
			coverage = "complete"
		}
		if entry.OperationalCoverage != coverage ||
			entry.OperationalEvidence != (len(operationalSeen) > 0) ||
			len(entry.OperationalEvidenceIDs) != len(operationalSeen) {
			return errors.New("evidências operacionais inconsistentes no relatório de qualidade")
		}
		if entry.OperationalEvidence {
			operationalEntries++
			if _, err := time.Parse(time.RFC3339, entry.LastOperationalVerification); err != nil {
				return errors.New("data da evidência operacional inválida")
			}
		} else if entry.LastOperationalVerification != "" || len(entry.OperationalEvidenceIDs) != 0 {
			return errors.New("entrada sem evidência contém metadados operacionais")
		}
		maturityRank := map[string]int{
			"structural": 0, "source-reviewed": 1, "script-reviewed": 2,
			"operational-reviewed": 3, "homologated": 4,
		}
		if maturityRank[entry.Maturity] >= maturityRank["operational-reviewed"] &&
			!entry.OperationalEvidence {
			return errors.New("maturidade operacional sem evidência")
		}
		if entry.Maturity == "homologated" &&
			(entry.OperationalCoverage != "complete" || !entry.HomologationEvidence) {
			return errors.New("homologação sem cobertura completa")
		}
		if entry.SourceClassification != "official-and-internal" &&
			entry.SourceClassification != "internal-only" &&
			entry.SourceClassification != "exception-approved" {
			return errors.New("classificação de fonte inválida")
		}
		if _, exists := seen[entry.SetupID]; exists {
			return errors.New("setupId duplicado no relatório de qualidade")
		}
		seen[entry.SetupID] = struct{}{}
		if len(entry.Issues) > 0 {
			issueEntries++
		}
		issueCount += len(entry.Issues)
	}
	if issueEntries != report.Summary.IssueEntries ||
		issueCount != report.Summary.UnresolvedIssueCount ||
		operationalEntries != report.Summary.OperationalEvidenceEntries {
		return errors.New("pendências do relatório de qualidade divergentes")
	}
	return nil
}

func validateBlueprintPackage(files map[string][]byte, manifest knowledgeManifest) error {
	indexData, exists := files["blueprints/index.json"]
	if !exists || manifest.BlueprintIndexSHA256 != sha256String(indexData) {
		return errors.New("índice de Blueprints ausente ou com hash divergente")
	}
	if _, exists := files["blueprints/manifest.json"]; !exists {
		return errors.New("manifesto interno de Blueprints ausente")
	}
	if _, exists := files["blueprints/schema/blueprint.schema.json"]; !exists {
		return errors.New("schema canônico de Blueprints ausente")
	}
	var index blueprintIndex
	if err := decodeStrictJSON(indexData, &index); err != nil {
		return fmt.Errorf("índice de Blueprints inválido: %w", err)
	}
	if index.SchemaVersion != manifest.BlueprintSchemaVersion ||
		index.FactoryVersion != manifest.BlueprintFactoryVersion ||
		index.SetupVersion != manifest.SetupVersion ||
		index.BlueprintCount != manifest.BlueprintEntries ||
		len(index.Entries) != manifest.BlueprintEntries {
		return errors.New("índice de Blueprints incompatível com o manifesto")
	}
	statusTotal := 0
	for status, count := range index.Statuses {
		if status == "" || count < 0 {
			return errors.New("contagem de status de Blueprint inválida")
		}
		statusTotal += count
	}
	if statusTotal != index.BlueprintCount {
		return errors.New("contagens de status de Blueprint divergentes")
	}
	seenIDs := make(map[string]struct{}, len(index.Entries))
	seenBundles := make(map[string]struct{}, len(index.Entries))
	statusCounts := make(map[string]int)
	for _, entry := range index.Entries {
		switch entry.Status {
		case "example", "draft", "reviewed", "homologated", "deprecated":
		default:
			return fmt.Errorf("status de Blueprint inválido: %q", entry.Status)
		}
		if entry.BlueprintID == "" ||
			entry.BlueprintVersion == "" ||
			entry.Title == "" ||
			entry.Objective == "" ||
			entry.Summary == "" ||
			entry.Author == "" ||
			entry.Risk == "" ||
			len(entry.Architectures) == 0 ||
			len(entry.Components) == 0 ||
			len(entry.Tags) < 2 ||
			len(entry.Aliases) < 2 ||
			!safeKnowledgePath(entry.BundlePath) ||
			!strings.HasPrefix(entry.BundlePath, "blueprints/bundles/") ||
			!strings.HasSuffix(entry.BundlePath, ".zip") ||
			entry.BundleBytes <= 0 ||
			entry.ResourceProfile.MinimumRAMGB < 1 ||
			entry.ResourceProfile.RecommendedRAMGB < entry.ResourceProfile.MinimumRAMGB ||
			len(entry.ResourceProfile.Basis) < 10 ||
			len(entry.BundleSHA256) != 64 {
			return fmt.Errorf("entrada de Blueprint inválida: %q", entry.BlueprintID)
		}
		if entry.Status == "example" && (!entry.Fictitious || entry.Deployable) {
			return fmt.Errorf("Blueprint de exemplo com flags inseguras: %s", entry.BlueprintID)
		}
		if entry.Status == "homologated" && (entry.Fictitious || !entry.Deployable) {
			return fmt.Errorf("Blueprint homologado com flags inválidas: %s", entry.BlueprintID)
		}
		if entry.Status != "homologated" && entry.Deployable {
			return fmt.Errorf("Blueprint não homologado marcado como implantável: %s", entry.BlueprintID)
		}
		if err := validateBlueprintEditorial(entry); err != nil {
			return fmt.Errorf("fluxo editorial inválido em %s: %w", entry.BlueprintID, err)
		}
		if _, duplicate := seenIDs[entry.BlueprintID]; duplicate {
			return fmt.Errorf("blueprintId duplicado: %s", entry.BlueprintID)
		}
		seenIDs[entry.BlueprintID] = struct{}{}
		if _, duplicate := seenBundles[entry.BundlePath]; duplicate {
			return fmt.Errorf("bundle de Blueprint duplicado: %s", entry.BundlePath)
		}
		seenBundles[entry.BundlePath] = struct{}{}
		bundle, exists := files[entry.BundlePath]
		if !exists || int64(len(bundle)) != entry.BundleBytes ||
			sha256String(bundle) != entry.BundleSHA256 {
			return fmt.Errorf("bundle de Blueprint divergente: %s", entry.BundlePath)
		}
		for _, media := range entry.Media {
			if media.MediaID == "" || media.Title == "" ||
				(media.Type != "video" && media.Type != "link" && media.Type != "pdf" && media.Type != "download") ||
				(media.Status != "pending" && media.Status != "reviewed") {
				return fmt.Errorf("mídia inválida no Blueprint: %s", entry.BlueprintID)
			}
			if media.Status == "pending" && media.URL != nil {
				return fmt.Errorf("mídia pendente expõe URL no Blueprint: %s", entry.BlueprintID)
			}
			if media.Status == "reviewed" && (media.URL == nil || !strings.HasPrefix(*media.URL, "https://")) {
				return fmt.Errorf("mídia publicada sem HTTPS no Blueprint: %s", entry.BlueprintID)
			}
			if entry.Fictitious && media.URL != nil && !strings.Contains(*media.URL, ".invalid/") {
				return fmt.Errorf("mídia fictícia fora de domínio reservado: %s", entry.BlueprintID)
			}
		}
		statusCounts[entry.Status]++
	}
	if !reflect.DeepEqual(statusCounts, index.Statuses) {
		return errors.New("status do índice de Blueprints divergentes")
	}
	return nil
}

func validateBlueprintEditorial(entry blueprintIndexEntry) error {
	editorial := entry.Editorial
	if editorial.CurrentStage != entry.Status || len(editorial.History) == 0 {
		return errors.New("estágio atual ou histórico ausente")
	}
	stages := make([]string, 0, len(editorial.History))
	previousDate := ""
	for _, item := range editorial.History {
		if item.Stage == "" || len(item.Actor) < 8 || len(item.Note) < 8 {
			return errors.New("transição editorial incompleta")
		}
		if _, err := time.Parse("2006-01-02", item.ChangedAt); err != nil ||
			(previousDate != "" && item.ChangedAt < previousDate) {
			return errors.New("cronologia editorial inválida")
		}
		previousDate = item.ChangedAt
		stages = append(stages, item.Stage)
	}
	history := strings.Join(stages, ",")
	allowedHistory := map[string]map[string]bool{
		"example":     {"example": true},
		"draft":       {"draft": true},
		"reviewed":    {"draft,reviewed": true},
		"homologated": {"draft,reviewed,homologated": true},
		"deprecated": {
			"draft,deprecated":                      true,
			"draft,reviewed,deprecated":             true,
			"draft,reviewed,homologated,deprecated": true,
		},
	}
	if !allowedHistory[entry.Status][history] {
		return errors.New("transição editorial não permitida")
	}
	if len(editorial.Review.Notes) < 10 {
		return errors.New("notas de revisão ausentes")
	}
	if entry.Status == "example" || entry.Status == "draft" {
		if editorial.Review.Decision != "pending" ||
			editorial.Review.ReviewedAt != nil || editorial.Review.ReviewedBy != nil ||
			editorial.Homologation.Environment != "not-applicable" ||
			editorial.Homologation.TestedAt != nil ||
			len(editorial.Homologation.Architectures) != 0 ||
			len(editorial.Homologation.Evidence) != 0 {
			return errors.New("rascunho ou exemplo contém aprovação indevida")
		}
	}
	if entry.Status == "reviewed" || entry.Status == "homologated" {
		if editorial.Review.Decision != "approved" || editorial.Review.ReviewedAt == nil ||
			editorial.Review.ReviewedBy == nil || len(*editorial.Review.ReviewedBy) < 3 {
			return errors.New("revisão aprovada ausente")
		}
		if _, err := time.Parse("2006-01-02", *editorial.Review.ReviewedAt); err != nil {
			return errors.New("data de revisão inválida")
		}
	}

	knownGates := map[string]bool{
		"schema": true, "catalog": true, "architecture": true, "resources": true,
		"installation": true, "validation-plan": true, "rollback": true,
		"review": true, "isolated-homologation": true, "evidence": true,
		"version-seal": true,
	}
	if editorial.TotalGates != len(knownGates) || len(editorial.Gates) != len(knownGates) {
		return errors.New("quantidade de gates divergente")
	}
	passed := 0
	seenGates := make(map[string]struct{}, len(editorial.Gates))
	for _, gate := range editorial.Gates {
		if !knownGates[gate.GateID] || gate.Title == "" {
			return errors.New("gate desconhecido")
		}
		if _, duplicate := seenGates[gate.GateID]; duplicate {
			return errors.New("gate duplicado")
		}
		seenGates[gate.GateID] = struct{}{}
		if gate.Passed {
			passed++
		}
	}
	if passed != editorial.PassedGates || editorial.PassedGates < 0 ||
		editorial.PassedGates > editorial.TotalGates {
		return errors.New("contagem de gates divergente")
	}
	if editorial.VersionSeal.Algorithm != "sha256" ||
		len(editorial.VersionSeal.ManifestSHA256) != 64 ||
		len(editorial.VersionSeal.PayloadSHA256) != 64 {
		return errors.New("selo de versão inválido")
	}
	if _, err := hex.DecodeString(editorial.VersionSeal.ManifestSHA256); err != nil {
		return errors.New("hash do manifesto no selo é inválido")
	}
	if _, err := hex.DecodeString(editorial.VersionSeal.PayloadSHA256); err != nil {
		return errors.New("hash do payload no selo é inválido")
	}
	if editorial.PromotionReady &&
		(entry.Status != "reviewed" && entry.Status != "homologated" || passed != editorial.TotalGates) {
		return errors.New("promoção liberada sem concluir gates")
	}

	requiredEvidence := map[string]bool{
		"test-report": false, "security-review": false, "rollback-test": false,
	}
	knownEvidenceTypes := map[string]bool{
		"test-report": true, "security-review": true, "rollback-test": true,
		"architecture-check": true,
	}
	coveredArchitectures := make(map[string]bool)
	for _, evidence := range editorial.Homologation.Evidence {
		if evidence.EvidenceID == "" || evidence.Title == "" ||
			len(evidence.SHA256) != 64 || evidence.VerifiedAt == "" ||
			!knownEvidenceTypes[evidence.Type] ||
			(evidence.Architecture != "all" && evidence.Architecture != "amd64" &&
				evidence.Architecture != "arm64") {
			return errors.New("evidência editorial inválida")
		}
		if _, err := hex.DecodeString(evidence.SHA256); err != nil {
			return errors.New("hash da evidência editorial inválido")
		}
		if _, err := time.Parse("2006-01-02", evidence.VerifiedAt); err != nil {
			return errors.New("data da evidência editorial inválida")
		}
		if _, exists := requiredEvidence[evidence.Type]; exists {
			requiredEvidence[evidence.Type] = true
		}
		if evidence.Type == "test-report" {
			if evidence.Architecture == "all" {
				for _, architecture := range entry.Architectures {
					coveredArchitectures[architecture] = true
				}
			} else {
				coveredArchitectures[evidence.Architecture] = true
			}
		}
	}
	if entry.Status == "homologated" {
		if !editorial.PromotionReady || passed != editorial.TotalGates ||
			editorial.Homologation.Environment != "isolated-temporary" ||
			editorial.Homologation.TestedAt == nil {
			return errors.New("homologação isolada incompleta")
		}
		if _, err := time.Parse("2006-01-02", *editorial.Homologation.TestedAt); err != nil {
			return errors.New("data da homologação inválida")
		}
		if !sameStringSet(editorial.Homologation.Architectures, entry.Architectures) {
			return errors.New("arquiteturas homologadas divergentes")
		}
		for evidenceType, present := range requiredEvidence {
			if !present {
				return fmt.Errorf("evidência obrigatória ausente: %s", evidenceType)
			}
		}
		for _, architecture := range entry.Architectures {
			if !coveredArchitectures[architecture] {
				return fmt.Errorf("arquitetura sem relatório de teste: %s", architecture)
			}
		}
	}
	return nil
}

func sameStringSet(first, second []string) bool {
	if len(first) != len(second) {
		return false
	}
	values := make(map[string]struct{}, len(first))
	for _, value := range first {
		if _, duplicate := values[value]; duplicate {
			return false
		}
		values[value] = struct{}{}
	}
	for _, value := range second {
		if _, exists := values[value]; !exists {
			return false
		}
	}
	return true
}

func validateKnowledgeIndexV2(index knowledgeIndexV2, legacy knowledgeIndex) error {
	requiredFields := map[string]struct{}{
		"aliases": {},
		"content": {},
		"heading": {},
		"tags":    {},
		"title":   {},
	}
	legacyByID := make(map[string]knowledgeIndexEntry, len(legacy.Entries))
	for _, entry := range legacy.Entries {
		legacyByID[entry.DocumentID] = entry
	}
	seenChunks := make(map[string]struct{}, len(index.Chunks))
	documentFrequencies := make(map[string]int)
	fieldTotals := make(map[string]int)
	for _, chunk := range index.Chunks {
		entry, exists := legacyByID[chunk.DocumentID]
		if !exists ||
			chunk.ChunkID == "" ||
			chunk.Content == "" ||
			chunk.Heading == "" ||
			chunk.Title == "" ||
			chunk.DocumentVersion != entry.DocumentVersion ||
			chunk.DocumentType != entry.DocumentType ||
			chunk.SetupVersion != entry.SetupVersion ||
			chunk.Status != entry.Status ||
			chunk.Category != entry.Category ||
			chunk.ContentSHA256 != sha256String([]byte(chunk.Content)) ||
			utf8.RuneCountInString(chunk.Content) > maxKnowledgeChunkRunes {
			return fmt.Errorf("chunk inválido no índice v2: %q", chunk.ChunkID)
		}
		if _, duplicate := seenChunks[chunk.ChunkID]; duplicate {
			return fmt.Errorf("chunkId duplicado no índice v2: %s", chunk.ChunkID)
		}
		seenChunks[chunk.ChunkID] = struct{}{}
		if !reflect.DeepEqual(chunk.Architectures, entry.Architectures) ||
			!reflect.DeepEqual(chunk.Tags, entry.Tags) ||
			!equalOptionalString(chunk.BlueprintID, entry.BlueprintID) ||
			chunk.Fictitious != entry.Fictitious ||
			chunk.Deployable != entry.Deployable ||
			!equalOptionalString(chunk.SetupID, entry.SetupID) ||
			!equalOptionalString(chunk.TopicID, entry.TopicID) {
			return fmt.Errorf("metadados divergentes no chunk: %s", chunk.ChunkID)
		}
		if len(chunk.Aliases) == 0 ||
			!sameStringKeys(chunk.FieldLengths, requiredFields) ||
			!sameFrequencyKeys(chunk.FieldTermFrequencies, requiredFields) {
			return fmt.Errorf("campos BM25F inválidos no chunk: %s", chunk.ChunkID)
		}
		chunkTerms := make(map[string]struct{})
		for field, frequencies := range chunk.FieldTermFrequencies {
			total := 0
			for term, count := range frequencies {
				if term == "" || count <= 0 {
					return fmt.Errorf(
						"frequência inválida no chunk %s",
						chunk.ChunkID,
					)
				}
				total += count
				chunkTerms[term] = struct{}{}
			}
			if chunk.FieldLengths[field] != total {
				return fmt.Errorf("comprimento BM25F divergente: %s", chunk.ChunkID)
			}
			fieldTotals[field] += total
		}
		for term := range chunkTerms {
			documentFrequencies[term]++
		}
	}
	if !reflect.DeepEqual(documentFrequencies, index.DocumentFrequencies) ||
		!sameFloatKeys(index.AverageFieldLengths, requiredFields) {
		return errors.New("estatísticas globais divergentes no índice v2")
	}
	for field, total := range fieldTotals {
		expected := float64(total) / float64(index.ChunkCount)
		if math.Abs(index.AverageFieldLengths[field]-expected) > 0.000001 {
			return fmt.Errorf("média de campo divergente no índice v2: %s", field)
		}
	}
	return nil
}

func equalOptionalString(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func sameStringKeys(values map[string]int, expected map[string]struct{}) bool {
	if len(values) != len(expected) {
		return false
	}
	for key := range expected {
		if _, exists := values[key]; !exists {
			return false
		}
	}
	return true
}

func sameFrequencyKeys(
	values map[string]map[string]int,
	expected map[string]struct{},
) bool {
	if len(values) != len(expected) {
		return false
	}
	for key := range expected {
		if _, exists := values[key]; !exists {
			return false
		}
	}
	return true
}

func sameFloatKeys(values map[string]float64, expected map[string]struct{}) bool {
	if len(values) != len(expected) {
		return false
	}
	for key := range expected {
		if _, exists := values[key]; !exists {
			return false
		}
	}
	return true
}

func readKnowledgeArchive(archiveData []byte) (map[string][]byte, error) {
	compressed, err := gzip.NewReader(bytes.NewReader(archiveData))
	if err != nil {
		return nil, fmt.Errorf("gzip inválido: %w", err)
	}
	defer compressed.Close()
	archive := tar.NewReader(compressed)
	files := make(map[string][]byte)
	var total int64
	for {
		header, nextErr := archive.Next()
		if errors.Is(nextErr, io.EOF) {
			break
		}
		if nextErr != nil {
			return nil, fmt.Errorf("tar inválido: %w", nextErr)
		}
		if header.Typeflag != tar.TypeReg && header.Typeflag != tar.TypeRegA {
			return nil, fmt.Errorf("entrada não regular no pacote: %s", header.Name)
		}
		if !safeKnowledgePath(header.Name) ||
			header.Size <= 0 ||
			header.Size > maxKnowledgeFileBytes {
			return nil, fmt.Errorf("entrada insegura ou fora do limite: %s", header.Name)
		}
		if len(files) >= maxKnowledgeFiles {
			return nil, errors.New("pacote excede o limite de arquivos")
		}
		if _, exists := files[header.Name]; exists {
			return nil, fmt.Errorf("entrada duplicada no pacote: %s", header.Name)
		}
		data, readErr := io.ReadAll(io.LimitReader(archive, header.Size+1))
		if readErr != nil || int64(len(data)) != header.Size {
			return nil, fmt.Errorf("conteúdo truncado: %s", header.Name)
		}
		total += int64(len(data))
		if total > maxKnowledgeArchiveBytes*4 {
			return nil, errors.New("conteúdo descompactado excede o limite")
		}
		files[header.Name] = data
	}
	return files, nil
}

func knowledgeCheckPayload(state knowledgePackageState) map[string]any {
	return map[string]any{
		"status":                    "ok",
		"source":                    state.Source,
		"stale":                     state.Stale,
		"knowledgeVersion":          state.Manifest.KnowledgeVersion,
		"indexSchemaVersion":        state.Manifest.IndexSchemaVersion,
		"retrievalVersion":          state.Manifest.RetrievalVersion,
		"evalSchemaVersion":         state.Manifest.EvalSchemaVersion,
		"evalDatasetVersion":        state.Manifest.EvalDatasetVersion,
		"evalGraderVersion":         state.Manifest.EvalGraderVersion,
		"evalCaseEntries":           state.Manifest.EvalCaseEntries,
		"evalDatasetSHA256":         state.Manifest.EvalDatasetSHA256,
		"setupVersion":              state.Manifest.SetupVersion,
		"controlVersion":            state.Manifest.ControlVersion,
		"documentEntries":           state.Manifest.DocumentEntries,
		"chunkEntries":              state.Manifest.ChunkEntries,
		"setupEntries":              state.Manifest.SetupEntries,
		"infrastructureEntries":     state.Manifest.InfrastructureEntries,
		"blueprintSchemaVersion":    state.Manifest.BlueprintSchemaVersion,
		"blueprintFactoryVersion":   state.Manifest.BlueprintFactoryVersion,
		"blueprintEntries":          state.Manifest.BlueprintEntries,
		"blueprintBundleEntries":    state.Manifest.BlueprintBundleEntries,
		"blueprintKnowledgeEntries": state.Manifest.BlueprintKnowledgeEntries,
		"blueprintFixtureEntries":   state.Manifest.BlueprintFixtureEntries,
		"qualitySchemaVersion":      state.Manifest.QualitySchemaVersion,
		"qualitySummary":            state.Manifest.QualitySummary,
		"archiveSHA256":             state.Manifest.ArchiveSHA256,
	}
}
