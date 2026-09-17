package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	fleetInventorySchemaVersion = 1
	fleetInventoryPolicyVersion = "1.0.0"
	fleetInventoryMaxNodes      = 100
	fleetInventoryMaxStoreBytes = 256 << 10 // 256 KiB
)

var (
	nodeIDRegex = regexp.MustCompile(`^[a-zA-Z0-9_-]{3,64}$`)
)

type fleetInventoryDocument struct {
	SchemaVersion int         `json:"schemaVersion"`
	PolicyVersion string      `json:"policyVersion"`
	UpdatedAt     string      `json:"updatedAt"`
	Nodes         []FleetNode `json:"nodes"`
}

type fleetInventoryStore struct {
	mu    sync.RWMutex
	path  string
	nodes []FleetNode
}

func validateFleetEndpoint(rawURL string) (string, error) {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" {
		return "", errors.New("endpoint não pode ser vazio")
	}
	if len(rawURL) > 255 {
		return "", errors.New("endpoint excede o tamanho máximo de 255 caracteres")
	}

	parsed, err := url.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("URL do endpoint inválida: %w", err)
	}

	if parsed.User != nil {
		return "", errors.New("credenciais embutidas na URL do endpoint não são permitidas")
	}

	if parsed.RawQuery != "" || parsed.Fragment != "" {
		return "", errors.New("queries ou fragmentos não são permitidos na URL do endpoint")
	}

	if parsed.Path != "" && parsed.Path != "/" {
		return "", errors.New("paths adicionais não são permitidos na URL do endpoint")
	}

	host := parsed.Hostname()
	if host == "" {
		return "", errors.New("hostname do endpoint não pode ser vazio")
	}

	// Por segurança Zero-Trust: HTTPS é obrigatório em produção.
	// HTTP é tolerado exclusivamente em localhost/127.0.0.1 para laboratórios de teste.
	scheme := strings.ToLower(parsed.Scheme)
	isLocalLab := host == "localhost" || host == "127.0.0.1" || host == "::1"
	if scheme != "https" {
		if scheme == "http" && isLocalLab {
			// Permitido apenas em ambiente de teste local
		} else {
			return "", errors.New("o endpoint do nó exige HTTPS para garantir Zero-Trust e tráfego criptografado")
		}
	}

	port := parsed.Port()
	cleanURL := fmt.Sprintf("%s://%s", scheme, host)
	if port != "" {
		cleanURL = fmt.Sprintf("%s:%s", cleanURL, port)
	}
	return cleanURL, nil
}

func validateFleetNode(node FleetNode) error {
	if !nodeIDRegex.MatchString(node.ID) {
		return errors.New("identificador do nó inválido (deve conter de 3 a 64 caracteres alfanuméricos, hífens ou underscores)")
	}
	name := strings.TrimSpace(node.Name)
	if len(name) < 2 || len(name) > 60 {
		return errors.New("nome do nó deve ter entre 2 e 60 caracteres")
	}
	for _, r := range name {
		if r < 32 || r == 127 {
			return errors.New("nome do nó contém caracteres de controle inválidos")
		}
	}
	if node.Endpoint != "" {
		if _, err := validateFleetEndpoint(node.Endpoint); err != nil {
			return err
		}
	}
	switch node.Mode {
	case FleetModeMaster, FleetModeWorker, FleetModeDisabled:
	default:
		return errors.New("modo do nó inválido")
	}
	return nil
}

func loadFleetInventory(path string) (*fleetInventoryStore, error) {
	store := &fleetInventoryStore{
		path:  path,
		nodes: make([]FleetNode, 0, fleetInventoryMaxNodes),
	}

	if path == "" {
		return store, nil
	}

	directory := filepath.Dir(path)
	info, err := os.Lstat(directory)
	if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return store, fmt.Errorf("diretório do inventário da frota: %w", err)
		}
	} else if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return store, errors.New("diretório do inventário da frota inválido")
	}

	data, err := readRegularFile(path, fleetInventoryMaxStoreBytes)
	if errors.Is(err, os.ErrNotExist) {
		return store, nil
	}
	if err != nil {
		return store, fmt.Errorf("arquivo do inventário da frota: %w", err)
	}

	var document fleetInventoryDocument
	if err := decodeStrictJSON(data, &document); err != nil {
		return store, errors.New("arquivo de inventário da frota não contém JSON estrito")
	}
	if document.SchemaVersion != fleetInventorySchemaVersion ||
		document.PolicyVersion != fleetInventoryPolicyVersion ||
		len(document.Nodes) > fleetInventoryMaxNodes {
		return store, errors.New("arquivo de inventário da frota incompatível ou excedeu o limite máximo de nós")
	}

	for _, node := range document.Nodes {
		if err := validateFleetNode(node); err != nil {
			return store, fmt.Errorf("nó inválido no inventário persistido: %w", err)
		}
		store.nodes = append(store.nodes, node)
	}
	return store, nil
}

func (s *fleetInventoryStore) Save() error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.path == "" {
		return nil
	}

	document := fleetInventoryDocument{
		SchemaVersion: fleetInventorySchemaVersion,
		PolicyVersion: fleetInventoryPolicyVersion,
		UpdatedAt:     time.Now().UTC().Format(time.RFC3339),
		Nodes:         s.nodes,
	}

	data, err := json.Marshal(document)
	if err != nil || len(data) > fleetInventoryMaxStoreBytes {
		return errors.New("inventário da frota excedeu o tamanho máximo seguro")
	}

	randomSuffix := make([]byte, 6)
	_, _ = rand.Read(randomSuffix)
	temporary := s.path + ".tmp-" + hex.EncodeToString(randomSuffix)

	file, err := os.OpenFile(temporary, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("falha ao criar arquivo temporário do inventário: %w", err)
	}

	removeTemp := true
	defer func() {
		_ = file.Close()
		if removeTemp {
			_ = os.Remove(temporary)
		}
	}()

	if _, err := file.Write(data); err != nil {
		return fmt.Errorf("falha ao gravar inventário: %w", err)
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("falha ao sincronizar inventário: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("falha ao fechar arquivo temporário: %w", err)
	}

	if info, err := os.Lstat(s.path); err == nil && (!info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0) {
		return errors.New("destino do inventário não é um arquivo regular")
	}

	if err := os.Rename(temporary, s.path); err != nil {
		return fmt.Errorf("falha ao substituir atomicamente o inventário da frota: %w", err)
	}
	removeTemp = false
	return nil
}

// ReconcileStaleNodes marca como offline nós workers cujo último sinal (heartbeat) excedeu o limite seguro.
// Isso elimina imediatamente falsos positivos quando um servidor é desligado ou formatado.
func (s *fleetInventoryStore) ReconcileStaleNodes(timeout time.Duration) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	modified := false
	now := time.Now().UTC()
	for i := range s.nodes {
		if s.nodes[i].Mode == FleetModeWorker {
			if s.nodes[i].Status == "online" {
				if s.nodes[i].LastHeartbeat.IsZero() || now.Sub(s.nodes[i].LastHeartbeat) > timeout {
					s.nodes[i].Status = "offline"
					s.nodes[i].TunnelHealthy = false
					modified = true
				}
			}
		}
	}
	return modified
}

func (s *fleetInventoryStore) ListNodes() []FleetNode {
	// Reconciliar nós com heartbeat expirado antes de listar
	if s.ReconcileStaleNodes(fleetHeartbeatTimeout) {
		_ = s.Save()
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]FleetNode, len(s.nodes))
	for i, n := range s.nodes {
		copied := n
		// Mascarar o token por segurança ao listar
		if copied.Token != "" {
			copied.Token = "••••••••"
		}
		result[i] = copied
	}
	return result
}

func (s *fleetInventoryStore) GetNode(id string) (FleetNode, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	now := time.Now().UTC()
	for _, n := range s.nodes {
		if n.ID == id {
			copied := n
			if copied.Mode == FleetModeWorker && copied.Status == "online" {
				if copied.LastHeartbeat.IsZero() || now.Sub(copied.LastHeartbeat) > fleetHeartbeatTimeout {
					copied.Status = "offline"
					copied.TunnelHealthy = false
				}
			}
			return copied, true
		}
	}
	return FleetNode{}, false
}

func (s *fleetInventoryStore) FindNodeByNameOrID(query string) (FleetNode, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	cleaned := strings.TrimSpace(query)
	if cleaned == "" {
		return FleetNode{}, false
	}
	lowerQuery := strings.ToLower(cleaned)
	now := time.Now().UTC()

	sanitizedNode := func(n FleetNode) FleetNode {
		if n.Mode == FleetModeWorker && n.Status == "online" {
			if n.LastHeartbeat.IsZero() || now.Sub(n.LastHeartbeat) > fleetHeartbeatTimeout {
				n.Status = "offline"
				n.TunnelHealthy = false
			}
		}
		return n
	}

	// 1. Match exato de ID ou Nome
	for _, n := range s.nodes {
		if strings.EqualFold(n.ID, cleaned) || strings.EqualFold(n.Name, cleaned) {
			return sanitizedNode(n), true
		}
	}

	// 2. Contains match no Nome ou prefixo do ID
	for _, n := range s.nodes {
		if strings.Contains(strings.ToLower(n.Name), lowerQuery) || strings.HasPrefix(strings.ToLower(n.ID), lowerQuery) {
			return sanitizedNode(n), true
		}
	}

	// 3. Match de substring no Endpoint
	for _, n := range s.nodes {
		if n.Endpoint != "" && strings.Contains(strings.ToLower(n.Endpoint), lowerQuery) {
			return sanitizedNode(n), true
		}
	}

	return FleetNode{}, false
}

func (s *fleetInventoryStore) AddNode(node FleetNode) error {
	if err := validateFleetNode(node); err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.nodes) >= fleetInventoryMaxNodes {
		return errors.New("limite máximo de nós na frota atingido (100 nós)")
	}

	for _, existing := range s.nodes {
		if existing.ID == node.ID {
			return fmt.Errorf("já existe um nó com o ID '%s'", node.ID)
		}
		if node.Endpoint != "" && strings.EqualFold(existing.Endpoint, node.Endpoint) {
			return fmt.Errorf("já existe um nó cadastrado com o endpoint '%s'", node.Endpoint)
		}
	}

	s.nodes = append(s.nodes, node)
	return nil
}

func (s *fleetInventoryStore) UpdateNode(node FleetNode) error {
	if err := validateFleetNode(node); err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	for i, existing := range s.nodes {
		if existing.ID == node.ID {
			// Se o token fornecido for a máscara ou vazio, preservar o token existente
			if node.Token == "" || node.Token == "••••••••" {
				node.Token = existing.Token
			}
			if node.Architecture == "" && existing.Architecture != "" {
				node.Architecture = existing.Architecture
			}
			if node.SetupVersion == "" && existing.SetupVersion != "" {
				node.SetupVersion = existing.SetupVersion
			}
			s.nodes[i] = node
			return nil
		}
	}
	return fmt.Errorf("nó '%s' não encontrado para atualização", node.ID)
}

func (s *fleetInventoryStore) RemoveNode(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	found := false
	filtered := make([]FleetNode, 0, len(s.nodes))
	for _, n := range s.nodes {
		if n.ID == id {
			found = true
			continue
		}
		filtered = append(filtered, n)
	}

	if !found {
		return false, nil
	}

	s.nodes = filtered
	return true, nil
}

func (s *fleetInventoryStore) EnsureLocalNode(localID, localName string, localTelem FleetTelemetry, arch, version string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if localID == "" {
		localID = "node-master-local"
	}
	if localName == "" {
		localName = "Nó Local (Torre Master)"
	}

	for i, n := range s.nodes {
		if n.ID == localID {
			s.nodes[i].Status = "online"
			s.nodes[i].LastHeartbeat = time.Now().UTC()
			s.nodes[i].Telemetry = &localTelem
			s.nodes[i].MemoryTotalMB = localTelem.MemoryTotalMB
			s.nodes[i].MemoryUsedMB = localTelem.MemoryUsedMB
			s.nodes[i].CPUUsagePct = localTelem.LoadAverage1m * 10.0 // aproximado ou métrica host
			s.nodes[i].ServiceCount = localTelem.HealthyApps + localTelem.UnhealthyApps
			s.nodes[i].TunnelHealthy = true
			return
		}
	}

	localNode := FleetNode{
		ID:            localID,
		Name:          localName,
		Endpoint:      "http://127.0.0.1:8080",
		Mode:          FleetModeMaster,
		Status:        "online",
		Role:          "master",
		Architecture:  arch,
		SetupVersion:  version,
		MemoryTotalMB: localTelem.MemoryTotalMB,
		MemoryUsedMB:  localTelem.MemoryUsedMB,
		CPUUsagePct:   localTelem.LoadAverage1m * 10.0,
		ServiceCount:  localTelem.HealthyApps + localTelem.UnhealthyApps,
		TunnelHealthy: true,
		LastHeartbeat: time.Now().UTC(),
		Telemetry:     &localTelem,
	}

	// Prepend local node as first entry
	s.nodes = append([]FleetNode{localNode}, s.nodes...)
}

// ExportWorkerNodes retorna a lista de nós operários com tokens válidos para replicação entre Torres Master autorizadas.
func (s *fleetInventoryStore) ExportWorkerNodes() []FleetNode {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var workers []FleetNode
	for _, n := range s.nodes {
		if n.Mode == FleetModeWorker || n.Role == "worker" {
			workers = append(workers, n)
		}
	}
	return workers
}

// ImportNodes mescla ou substitui a lista de nós da frota a partir de outra Torre Master autorizada.
func (s *fleetInventoryStore) ImportNodes(incoming []FleetNode, strategy string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	strategy = strings.ToLower(strings.TrimSpace(strategy))
	if strategy == "" {
		strategy = "merge"
	}

	importedCount := 0

	if strategy == "replace" {
		// Preserva apenas o nó local da Torre Master
		var preserved []FleetNode
		for _, n := range s.nodes {
			if n.Mode == FleetModeMaster || strings.HasPrefix(n.ID, "node-master") {
				preserved = append(preserved, n)
			}
		}
		s.nodes = preserved
	}

	for _, inc := range incoming {
		if inc.Mode != FleetModeWorker && inc.Role != "worker" {
			continue
		}
		if err := validateFleetNode(inc); err != nil {
			continue
		}

		existingIdx := -1
		for i, existing := range s.nodes {
			if existing.ID == inc.ID || (inc.Endpoint != "" && existing.Endpoint == inc.Endpoint) {
				existingIdx = i
				break
			}
		}

		if existingIdx >= 0 {
			// Atualiza nó existente
			s.nodes[existingIdx].Name = inc.Name
			s.nodes[existingIdx].Endpoint = inc.Endpoint
			if inc.Token != "" && inc.Token != "••••••••" {
				s.nodes[existingIdx].Token = inc.Token
			}
			s.nodes[existingIdx].Tags = inc.Tags
			if inc.Architecture != "" {
				s.nodes[existingIdx].Architecture = inc.Architecture
			}
			if inc.SetupVersion != "" {
				s.nodes[existingIdx].SetupVersion = inc.SetupVersion
			}
			importedCount++
		} else {
			// Adiciona novo nó se não exceder capacidade
			if len(s.nodes) < fleetInventoryMaxNodes {
				s.nodes = append(s.nodes, inc)
				importedCount++
			}
		}
	}

	return importedCount, nil
}
