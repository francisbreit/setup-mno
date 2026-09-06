package main

import (
	"errors"
	"regexp"
	"sort"
	"strings"
)

const (
	assistantRouterVersion = "1.4.0"
)

type assistantRoute struct {
	RouterVersion           string   `json:"routerVersion"`
	PromptRegistryVersion   string   `json:"promptRegistryVersion"`
	PromptVersion           string   `json:"promptVersion"`
	PromptSHA256            string   `json:"promptSHA256"`
	ResponseContractVersion string   `json:"responseContractVersion"`
	ResponseProfile         string   `json:"responseProfile"`
	Intent                  string   `json:"intent"`
	Specialist              string   `json:"specialist"`
	Setups                  []string `json:"setups"`
	Domains                 []string `json:"domains"`
	Architecture            string   `json:"architecture"`
	RiskLevel               string   `json:"riskLevel"`
	RequiredEvidence        []string `json:"requiredEvidence"`
	Confidence              string   `json:"confidence"`
	Signals                 []string `json:"signals"`
}

type routeDefinition struct {
	Intent           string
	Specialist       string
	RiskLevel        string
	RequiredEvidence []string
	Signal           string
	Terms            []string
}

type routeDomainDefinition struct {
	Name  string
	Terms []string
}

var routeDefinitions = []routeDefinition{
	{
		Intent: "fleet_dispatch", Specialist: "fleet_commander", RiskLevel: "medium",
		RequiredEvidence: []string{"fleet_inventory", "remote_telemetry"},
		Signal:           "keyword_fleet_dispatch",
		Terms: []string{
			"instalar no worker", "instalar no hetzner", "despachar para worker", "despacho para worker",
			"instalar no debian1", "instalar no debian", "deploy no worker", "deploy no hetzner",
			"instalar no servidor remoto", "despachar aplicacao", "despachar setup", "despacho",
			"no worker", "nos workers", "no hetzner", "no debian1", "no servidor remoto", "despachar", "para o worker",
		},
	},
	{
		Intent: "fleet_node_diagnosis", Specialist: "fleet_commander", RiskLevel: "low",
		RequiredEvidence: []string{"fleet_inventory", "remote_telemetry"},
		Signal:           "keyword_fleet",
		Terms: []string{
			"frota", "fleet", "fleet hub", "servidor debian", "servidor worker",
			"hetzner", "estado do servidor debian", "saude do worker", "servidor debian1",
			"servidor remoto", "servidores remotos", "telemetria remota", "debian1-hetzner",
			"debian1", "estado do worker", "nos da frota", "status da frota",
		},
	},
	{
		Intent: "knowledge_status", Specialist: "setup_specialist", RiskLevel: "low",
		RequiredEvidence: []string{"knowledge_manifest", "catalog_entry"},
		Signal:           "keyword_knowledge_status",
		Terms: []string{
			"base de conhecimento", "conhecimento canonico", "aplicacoes documentadas",
			"setups documentados", "ferramentas documentadas", "cobertura da base",
		},
	},
	{
		Intent: "security_review", Specialist: "security_reviewer", RiskLevel: "high",
		RequiredEvidence: []string{"runtime_state", "security_controls", "risks", "rollback"},
		Signal:           "keyword_security",
		Terms: []string{
			"seguranca", "seguro", "vulnerabilidade", "vulneravel", "hardening",
			"firewall", "tls", "certificado", "secret", "credencial", "permissao",
			"menor privilegio", "autenticacao", "exposicao", "porta publica", "backup",
		},
	},
	{
		Intent: "troubleshooting", Specialist: "troubleshooting_specialist", RiskLevel: "medium",
		RequiredEvidence: []string{"runtime_state", "diagnostics", "setup_documentation", "rollback"},
		Signal:           "keyword_troubleshooting",
		Terms: []string{
			"erro", "falha", "falhando", "nao funciona", "nao inicia", "indisponivel",
			"degradado", "offline", "timeout", "reconectar", "tela preta", "log",
			"corrigir", "diagnosticar", "problema", "travou", "parou", "incompativel",
		},
	},
	{
		Intent: "capacity_planning", Specialist: "capacity_planner", RiskLevel: "medium",
		RequiredEvidence: []string{"runtime_state", "resources", "setup_requirements", "architecture"},
		Signal:           "keyword_capacity",
		Terms: []string{
			"capacidade", "memoria", "ram", "cpu", "disco", "armazenamento", "recurso",
			"quantos usuarios", "quantas execucoes", "escala", "escalar", "dimensionar",
			"suporta", "cabe no servidor", "posso instalar", "pronto para deploy",
		},
	},
	{
		Intent: "blueprint_recommendation", Specialist: "blueprint_architect", RiskLevel: "high",
		RequiredEvidence: []string{"blueprint", "resources", "dependencies", "security_controls", "rollback"},
		Signal:           "keyword_blueprint",
		Terms: []string{
			"blueprint", "blueprints", "quantos blueprints", "arquitetura completa", "solucao completa", "stack recomendada",
			"projeto de infraestrutura", "desenhe a solucao", "monte uma arquitetura",
		},
	},
	{
		Intent: "integration_design", Specialist: "integration_architect", RiskLevel: "medium",
		RequiredEvidence: []string{"setup_documentation", "dependencies", "network", "security_controls", "rollback"},
		Signal:           "keyword_integration",
		Terms: []string{
			"integrar", "integracao", "conectar", "webhook", "via api", "pela api", "por api", "evolution api", "rabbitmq",
			"mensageria", "fluxo entre", "comunicar", "sincronizar", "sso", "oauth",
		},
	},
	{
		Intent: "solution_design", Specialist: "solution_architect", RiskLevel: "medium",
		RequiredEvidence: []string{"ecosystem_taxonomy", "solution_patterns", "catalog_entry", "setup_documentation", "blueprint", "resources", "dependencies"},
		Signal:           "keyword_solution_design",
		Terms: []string{
			"sugira uma solucao", "sugira aplicacoes", "sugira ferramentas",
			"quais aplicacoes usar", "quais ferramentas usar", "ferramentas combinar",
			"combinar ferramentas", "combinacao de ferramentas", "montar um sistema",
			"montar um microsistema", "criar um microsistema", "resolver minha dor",
			"arquitetura orientada a objetivo", "ecossistema para meu negocio",
		},
	},
	{
		Intent: "infrastructure_diagnosis", Specialist: "infrastructure_diagnostician", RiskLevel: "low",
		RequiredEvidence: []string{"infrastructure_documentation", "risks", "rollback"},
		Signal:           "keyword_infrastructure",
		Terms: []string{
			"rollback devo planejar antes de alterar",
		},
	},
	{
		Intent: "setup_guidance", Specialist: "setup_specialist", RiskLevel: "low",
		RequiredEvidence: []string{"catalog_entry", "setup_documentation", "architecture", "resources"},
		Signal:           "keyword_setup",
		Terms: []string{
			"setup", "setups", "aplicacao", "ferramenta", "catalogo", "instalar",
			"deploy", "pre requisito", "requisito", "compativel",
		},
	},
	{
		Intent: "infrastructure_diagnosis", Specialist: "infrastructure_diagnostician", RiskLevel: "low",
		RequiredEvidence: []string{"runtime_state", "infrastructure_documentation"},
		Signal:           "keyword_infrastructure",
		Terms: []string{
			"infraestrutura", "servidor", "vps", "docker", "swarm", "linux", "wsl2",
			"traefik", "cloudflare", "proxy", "rede", "servico", "container",
			"postgres", "redis", "mysql", "minio", "observabilidade", "monitoramento",
			"arquitetura", "portainer", "ssh", "manager", "worker", "node", "task",
			"replica", "replicas", "escala horizontal", "quorum", "manter no ar",
			"reiniciar servico", "logs do servico", "tipo de instalacao",
			"assistente mno", "copiloto", "o que voce pode fazer", "como voce pode ajudar",
		},
	},
}

var routeDomains = []routeDomainDefinition{
	{Name: "setup_mno", Terms: []string{"setup mno", "setup", "setups", "catalogo", "instalador"}},
	{Name: "infrastructure", Terms: []string{"infraestrutura", "servidor", "vps", "linux", "wsl2", "assistente mno", "copiloto", "portainer", "ssh", "manager", "worker"}},
	{Name: "containers", Terms: []string{"docker", "swarm", "container", "stack", "servico"}},
	{Name: "architecture", Terms: []string{"arquitetura", "amd64", "x86", "x86 64", "arm", "arm64", "aarch64"}},
	{Name: "resources", Terms: []string{"capacidade", "memoria", "ram", "cpu", "disco", "armazenamento", "escala"}},
	{Name: "network", Terms: []string{"rede", "traefik", "cloudflare", "proxy", "dns", "tls", "porta"}},
	{Name: "data", Terms: []string{"postgres", "postgresql", "mysql", "redis", "banco de dados", "minio", "qdrant"}},
	{Name: "automation", Terms: []string{"automacao", "workflow", "n8n", "activepieces"}},
	{Name: "observability", Terms: []string{"observabilidade", "monitoramento", "metrica", "grafana", "prometheus", "beszel", "log"}},
	{Name: "security", Terms: []string{"seguranca", "hardening", "firewall", "secret", "credencial", "permissao", "backup"}},
	{Name: "integration", Terms: []string{"integracao", "integrar", "via api", "pela api", "por api", "evolution api", "webhook", "fila", "rabbitmq", "oauth"}},
	{Name: "blueprints", Terms: []string{"blueprint", "solucao completa", "arquitetura completa"}},
	{Name: "solutions", Terms: []string{"microssistema", "resolver minha dor", "sugira ferramentas", "combinar ferramentas", "montar um sistema"}},
	{Name: "fleet", Terms: []string{"frota", "fleet", "fleet hub", "worker", "hetzner", "debian1", "servidor remoto", "servidores remotos"}},
}

var routeDestructiveTerms = []string{
	"apagar", "deletar", "excluir", "remover", "destruir", "resetar", "formatar",
	"derrubar", "limpar volume", "remover volume", "sem backup", "forcar atualizacao",
}

var integrationFirstSetupIDs = map[string]bool{
	"chatwoot-evolution-rabbitmq":                         true,
	"chatwoot-evolution-rabbitmq-minio":                   true,
	"chatwoot-original-evolution-rabbitmq-minio":          true,
	"chatwoot-original-unlocked-evolution-rabbitmq-minio": true,
	"evolution-api-v1":                                    true,
	"evolution-api-v2":                                    true,
	"rabbitmq":                                            true,
}

var routeSetupIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,63}$`)

var allowedRouteDomains = map[string]bool{
	"setup_mno": true, "infrastructure": true, "containers": true, "architecture": true,
	"resources": true, "network": true, "data": true, "automation": true,
	"observability": true, "security": true, "integration": true,
	"blueprints": true, "out_of_scope": true,
	"knowledge": true, "solutions": true, "fleet": true,
}

var allowedRouteEvidence = map[string]bool{
	"runtime_state": true, "security_controls": true, "risks": true,
	"rollback": true, "diagnostics": true, "setup_documentation": true,
	"resources": true, "setup_requirements": true, "architecture": true,
	"blueprint": true, "dependencies": true, "network": true,
	"catalog_entry": true, "infrastructure_documentation": true,
	"knowledge_manifest": true, "ecosystem_taxonomy": true,
	"solution_patterns": true,
	"fleet_inventory": true, "remote_telemetry": true,
}

var allowedRouteSignals = map[string]bool{
	"keyword_security": true, "keyword_troubleshooting": true,
	"keyword_capacity": true, "keyword_blueprint": true,
	"keyword_integration": true, "keyword_setup": true,
	"keyword_infrastructure": true, "domain_infrastructure": true,
	"keyword_knowledge_status": true, "keyword_solution_design": true,
	"keyword_fleet":            true, "keyword_fleet_dispatch": true,
	"no_domain_signal":         true,
	"canonical_setup_detected": true, "destructive_action_language": true,
	"conversation_context_resolved": true, "route_validation_fallback": true,
}

func routeAssistant(
	question string,
	resolution retrievalQueryResolution,
	runtimeArchitecture string,
) assistantRoute {
	setups := append([]string(nil), resolution.SetupIDs...)
	if len(setups) == 0 && resolution.SetupID != "" {
		setups = []string{resolution.SetupID}
	}
	setups = uniqueSortedStrings(setups)

	domains := detectRouteDomains(question)
	definition, matched := selectRouteDefinition(question, setups)
	if !matched && len(domains) > 0 {
		definition = routeDefinitionByIntent("infrastructure_diagnosis")
		definition.Signal = "domain_infrastructure"
		matched = true
	}
	if !matched {
		definition = routeDefinition{
			Intent: "scope_redirect", Specialist: "scope_guard", RiskLevel: "low",
			Signal: "no_domain_signal",
		}
	}
	if len(setups) > 0 {
		domains = append(domains, "setup_mno")
	}
	if definition.Intent == "scope_redirect" {
		domains = []string{"out_of_scope"}
	}

	riskLevel := definition.RiskLevel
	requiredEvidence := append([]string(nil), definition.RequiredEvidence...)
	responseProfile := responseProfileForRoute(question, definition.Intent)
	if responseProfile == "direct_overview" {
		requiredEvidence = []string{"catalog_entry", "setup_documentation"}
	}
	signals := []string{definition.Signal}
	if len(setups) > 0 {
		signals = append(signals, "canonical_setup_detected")
	}
	if anyPhraseContained(question, routeDestructiveTerms) {
		riskLevel = "high"
		requiredEvidence = append(requiredEvidence, "rollback")
		signals = append(signals, "destructive_action_language")
	}
	if resolution.Contextualized {
		signals = append(signals, "conversation_context_resolved")
	}

	confidence := "high"
	if definition.Intent == "scope_redirect" {
		confidence = "medium"
	} else if definition.Intent == "infrastructure_diagnosis" && len(domains) == 0 {
		confidence = "medium"
	}

	promptVersion, promptSHA256, promptFound := promptMetadataForSpecialist(definition.Specialist)
	if !promptFound {
		return safeScopeRoute(runtimeArchitecture)
	}
	route := assistantRoute{
		RouterVersion:           assistantRouterVersion,
		PromptRegistryVersion:   assistantPromptRegistryVersion,
		PromptVersion:           promptVersion,
		PromptSHA256:            promptSHA256,
		ResponseContractVersion: assistantResponseContractVersion,
		ResponseProfile:         responseProfile,
		Intent:                  definition.Intent,
		Specialist:              definition.Specialist,
		Setups:                  setups,
		Domains:                 uniqueSortedStrings(domains),
		Architecture:            routeArchitecture(question, runtimeArchitecture),
		RiskLevel:               riskLevel,
		RequiredEvidence:        uniqueSortedStrings(requiredEvidence),
		Confidence:              confidence,
		Signals:                 uniqueSortedStrings(signals),
	}
	if err := validateAssistantRoute(route); err != nil {
		return safeScopeRoute(runtimeArchitecture)
	}
	return route
}

func responseProfileForRoute(question string, intent string) string {
	switch intent {
	case "setup_guidance":
		if isSetupOverviewQuestion(question) {
			return "direct_overview"
		}
		return "guided_decision"
	case "knowledge_status":
		return "catalog_inventory"
	case "fleet_dispatch":
		return "guided_decision"
	case "capacity_planning", "troubleshooting", "infrastructure_diagnosis", "fleet_node_diagnosis":
		return "technical_diagnosis"
	case "integration_design", "blueprint_recommendation", "solution_design":
		return "guided_architecture"
	case "security_review":
		return "risk_review"
	default:
		return "safe_redirect"
	}
}

func isSetupOverviewQuestion(question string) bool {
	return anyPhraseContained(question, []string{
		"o que e", "o que faz", "para que serve", "qual a finalidade",
		"qual e a finalidade", "me explique o", "me explique a",
		"explique o", "explique a ferramenta", "quero conhecer",
	})
}

func selectRouteDefinition(question string, setups []string) (routeDefinition, bool) {
	if isKnowledgeStatusQuestion(question) {
		return routeDefinitionByIntent("knowledge_status"), true
	}
	priority := []string{
		"fleet_dispatch", "fleet_node_diagnosis",
		"troubleshooting", "capacity_planning", "blueprint_recommendation",
		"security_review", "integration_design", "solution_design", "infrastructure_diagnosis",
		"setup_guidance",
	}
	if len(setups) > 0 {
		for _, intent := range priority {
			if intent == "setup_guidance" || intent == "infrastructure_diagnosis" ||
				intent == "blueprint_recommendation" {
				continue
			}
			definition := routeDefinitionByIntent(intent)
			if anyPhraseContained(question, definition.Terms) {
				return definition, true
			}
		}
		for _, setupID := range setups {
			if integrationFirstSetupIDs[setupID] {
				return routeDefinitionByIntent("integration_design"), true
			}
		}
		return routeDefinitionByIntent("setup_guidance"), true
	}
	if anyPhraseContained(question, []string{"explique a arquitetura", "arquitetura de"}) {
		return routeDefinitionByIntent("infrastructure_diagnosis"), true
	}
	for _, intent := range priority {
		definition := routeDefinitionByIntent(intent)
		if anyPhraseContained(question, definition.Terms) {
			return definition, true
		}
	}
	return routeDefinition{}, false
}

func routeDefinitionByIntent(intent string) routeDefinition {
	for _, definition := range routeDefinitions {
		if definition.Intent == intent {
			return definition
		}
	}
	return routeDefinition{}
}

func detectRouteDomains(question string) []string {
	domains := make([]string, 0, len(routeDomains))
	for _, definition := range routeDomains {
		if anyPhraseContained(question, definition.Terms) {
			domains = append(domains, definition.Name)
		}
	}
	return domains
}

func routeArchitecture(question string, runtimeArchitecture string) string {
	mentionsAMD64 := anyPhraseContained(question, []string{"amd64", "x86", "x86 64", "x86_64"})
	mentionsARM64 := anyPhraseContained(question, []string{"arm", "arm64", "aarch64"})
	if mentionsAMD64 && mentionsARM64 {
		return "multi"
	}
	if mentionsAMD64 {
		return "amd64"
	}
	if mentionsARM64 {
		return "arm64"
	}
	switch normalizeRetrievalPhrase(runtimeArchitecture) {
	case "amd64", "x86", "x86 64":
		return "amd64"
	case "arm64", "arm", "aarch64":
		return "arm64"
	default:
		return "unknown"
	}
}

func safeScopeRoute(runtimeArchitecture string) assistantRoute {
	promptVersion, promptSHA256, _ := promptMetadataForSpecialist("scope_guard")
	return assistantRoute{
		RouterVersion:           assistantRouterVersion,
		PromptRegistryVersion:   assistantPromptRegistryVersion,
		PromptVersion:           promptVersion,
		PromptSHA256:            promptSHA256,
		ResponseContractVersion: assistantResponseContractVersion,
		ResponseProfile:         "safe_redirect",
		Intent:                  "scope_redirect",
		Specialist:              "scope_guard",
		Domains:                 []string{"out_of_scope"},
		Architecture:            routeArchitecture("", runtimeArchitecture),
		RiskLevel:               "low",
		Confidence:              "medium",
		Signals:                 []string{"route_validation_fallback"},
	}
}

func validateAssistantRoute(route assistantRoute) error {
	promptVersion, promptSHA256, promptFound := promptMetadataForSpecialist(route.Specialist)
	if route.RouterVersion != assistantRouterVersion ||
		route.PromptRegistryVersion != assistantPromptRegistryVersion || !promptFound ||
		route.PromptVersion != promptVersion || route.PromptSHA256 != promptSHA256 ||
		route.ResponseContractVersion != assistantResponseContractVersion {
		return errors.New("versão do roteador incompatível")
	}
	allowedResponseProfiles := map[string]bool{
		"direct_overview": true, "guided_decision": true,
		"catalog_inventory": true, "technical_diagnosis": true,
		"guided_architecture": true, "risk_review": true,
		"safe_redirect": true,
	}
	if !allowedResponseProfiles[route.ResponseProfile] {
		return errors.New("perfil de resposta inválido")
	}
	allowedIntents := map[string]string{
		"fleet_dispatch":          "fleet_commander",
		"fleet_node_diagnosis":    "fleet_commander",
		"security_review":          "security_reviewer",
		"troubleshooting":          "troubleshooting_specialist",
		"capacity_planning":        "capacity_planner",
		"blueprint_recommendation": "blueprint_architect",
		"integration_design":       "integration_architect",
		"solution_design":          "solution_architect",
		"setup_guidance":           "setup_specialist",
		"knowledge_status":         "setup_specialist",
		"infrastructure_diagnosis": "infrastructure_diagnostician",
		"scope_redirect":           "scope_guard",
	}
	if allowedIntents[route.Intent] != route.Specialist {
		return errors.New("especialista incompatível com a intenção")
	}
	if route.RiskLevel != "low" && route.RiskLevel != "medium" && route.RiskLevel != "high" {
		return errors.New("nível de risco inválido")
	}
	if route.Confidence != "medium" && route.Confidence != "high" {
		return errors.New("confiança de roteamento inválida")
	}
	if route.Architecture != "amd64" && route.Architecture != "arm64" &&
		route.Architecture != "multi" && route.Architecture != "unknown" {
		return errors.New("arquitetura de roteamento inválida")
	}
	if route.RiskLevel == "high" && !containsString(route.RequiredEvidence, "rollback") {
		return errors.New("rota de alto risco sem evidência de rollback")
	}
	if route.Intent == "scope_redirect" {
		if len(route.RequiredEvidence) != 0 || !reflectRouteValues(route.Domains, []string{"out_of_scope"}) {
			return errors.New("redirecionamento de escopo inválido")
		}
	} else if len(route.RequiredEvidence) == 0 {
		return errors.New("rota especializada sem evidência obrigatória")
	}
	if hasEmptyOrDuplicate(route.Setups) || hasEmptyOrDuplicate(route.Domains) ||
		hasEmptyOrDuplicate(route.RequiredEvidence) || hasEmptyOrDuplicate(route.Signals) {
		return errors.New("contrato de roteamento contém valor vazio ou duplicado")
	}
	for _, setupID := range route.Setups {
		if !routeSetupIDPattern.MatchString(setupID) {
			return errors.New("setup inválido no contrato de roteamento")
		}
	}
	for _, domain := range route.Domains {
		if !allowedRouteDomains[domain] {
			return errors.New("domínio inválido no contrato de roteamento")
		}
	}
	for _, evidence := range route.RequiredEvidence {
		if !allowedRouteEvidence[evidence] {
			return errors.New("evidência inválida no contrato de roteamento")
		}
	}
	for _, signal := range route.Signals {
		if !allowedRouteSignals[signal] {
			return errors.New("sinal inválido no contrato de roteamento")
		}
	}
	return nil
}

func isKnowledgeStatusQuestion(question string) bool {
	normalized := normalizeRetrievalPhrase(question)
	if normalized == "" {
		return false
	}
	mentionsExplicitKnowledge := anyPhraseContained(normalized, []string{
		"base de conhecimento", "conhecimento canonico", "conhecimento documentado",
		"aplicacoes documentadas", "aplicacao documentada", "setups documentados",
		"setup documentado", "ferramentas documentadas", "ferramenta documentada",
		"documentacao canonica", "cobertura da base",
	})
	mentionsCatalogSubject := anyPhraseContained(normalized, []string{
		"setup", "setups", "aplicacao", "aplicacoes", "ferramenta", "ferramentas",
		"catalogo", "documentacao",
	})
	mentionsGovernanceState := anyPhraseContained(normalized, []string{
		"documentado", "documentados", "documentada", "documentadas",
		"homologado", "homologados", "homologada", "homologadas",
		"maturidade", "revisao operacional", "evidencia operacional",
	})
	requestsStatus := anyPhraseContained(normalized, []string{
		"quantas", "quantos", "quanto", "total", "cobertura", "faltam", "pendentes",
		"estado", "status", "versao", "quais",
	})
	return requestsStatus && (mentionsExplicitKnowledge ||
		(mentionsCatalogSubject && mentionsGovernanceState))
}

func reflectRouteValues(current []string, expected []string) bool {
	if len(current) != len(expected) {
		return false
	}
	for index := range current {
		if current[index] != expected[index] {
			return false
		}
	}
	return true
}

func hasEmptyOrDuplicate(values []string) bool {
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		if value == "" {
			return true
		}
		if _, exists := seen[value]; exists {
			return true
		}
		seen[value] = struct{}{}
	}
	return false
}

func uniqueSortedStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}
