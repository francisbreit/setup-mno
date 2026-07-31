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
	"unicode/utf8"
)

const (
	knowledgeSchema          = 1
	knowledgeIndexSchema     = 2
	knowledgeRetrieval       = "1.0.0"
	maxKnowledgeArchiveBytes = 8 << 20
	maxKnowledgeManifest     = 1 << 20
	maxKnowledgeFileBytes    = 2 << 20
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
	MaxArchiveBytes  int64 `json:"maxArchiveBytes"`
	MaxDocumentBytes int64 `json:"maxDocumentBytes"`
	MaxDocuments     int   `json:"maxDocuments"`
	MaxIndexBytes    int64 `json:"maxIndexBytes"`
}

type knowledgeManifest struct {
	SchemaVersion         int                   `json:"schemaVersion"`
	KnowledgeVersion      string                `json:"knowledgeVersion"`
	SetupVersion          string                `json:"setupVersion"`
	ControlVersion        string                `json:"controlVersion"`
	GeneratedAt           string                `json:"generatedAt"`
	ArchiveFile           string                `json:"archiveFile"`
	ArchiveSHA256         string                `json:"archiveSHA256"`
	ArchiveBytes          int64                 `json:"archiveBytes"`
	IndexSHA256           string                `json:"indexSHA256"`
	LegacyIndexSHA256     string                `json:"legacyIndexSHA256"`
	IndexSchemaVersion    int                   `json:"indexSchemaVersion"`
	RetrievalVersion      string                `json:"retrievalVersion"`
	DocumentEntries       int                   `json:"documentEntries"`
	ChunkEntries          int                   `json:"chunkEntries"`
	DocumentTypeEntries   map[string]int        `json:"documentTypeEntries"`
	SetupEntries          int                   `json:"setupEntries"`
	InfrastructureEntries int                   `json:"infrastructureEntries"`
	FileEntries           int                   `json:"fileEntries"`
	Limits                knowledgeLimits       `json:"limits"`
	Files                 []knowledgeFileRecord `json:"files"`
}

type knowledgeIndexEntry struct {
	Architectures   []string `json:"architectures"`
	Category        string   `json:"category"`
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
	Manifest knowledgeManifest
	Index    knowledgeIndex
	IndexV2  knowledgeIndexV2
	Files    map[string][]byte
	Source   string
	Stale    bool
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
		manifest.InfrastructureEntries < 0 {
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
		typeEntries["infrastructure"] != manifest.InfrastructureEntries {
		return knowledgePackageState{}, errors.New("contagens principais divergentes")
	}
	if err := validateKnowledgeIndexV2(indexV2, index); err != nil {
		return knowledgePackageState{}, err
	}
	return knowledgePackageState{
		Manifest: manifest,
		Index:    index,
		IndexV2:  indexV2,
		Files:    files,
	}, nil
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
		"status":                "ok",
		"source":                state.Source,
		"stale":                 state.Stale,
		"knowledgeVersion":      state.Manifest.KnowledgeVersion,
		"indexSchemaVersion":    state.Manifest.IndexSchemaVersion,
		"retrievalVersion":      state.Manifest.RetrievalVersion,
		"setupVersion":          state.Manifest.SetupVersion,
		"controlVersion":        state.Manifest.ControlVersion,
		"documentEntries":       state.Manifest.DocumentEntries,
		"chunkEntries":          state.Manifest.ChunkEntries,
		"setupEntries":          state.Manifest.SetupEntries,
		"infrastructureEntries": state.Manifest.InfrastructureEntries,
		"archiveSHA256":         state.Manifest.ArchiveSHA256,
	}
}
