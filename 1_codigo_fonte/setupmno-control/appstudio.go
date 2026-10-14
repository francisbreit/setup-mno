package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type appStudioRegistryEntry struct {
	Name         string   `json:"name"`
	StackName    string   `json:"stack_name"`
	ImageTag     string   `json:"image_tag,omitempty"`
	Image        string   `json:"image,omitempty"`
	Runtime      string   `json:"runtime,omitempty"`
	InternalPort int      `json:"internal_port"`
	Domain       string   `json:"domain,omitempty"`
	Domains      []string `json:"domains,omitempty"`
	InstallType  string   `json:"install_type"`
	ServiceName  string   `json:"service_name,omitempty"`
	SourceDir    string   `json:"source_dir,omitempty"`
	CreatedAt    string   `json:"created_at"`
	UpdatedAt    string   `json:"updated_at,omitempty"`
	LastDeployAt string   `json:"last_deploy_at,omitempty"`
	Git          struct {
		Repo   string `json:"repo"`
		Branch string `json:"branch"`
	} `json:"git,omitempty"`
	Resources struct {
		CPULimit    string `json:"cpu_limit"`
		MemoryLimit string `json:"memory_limit"`
	} `json:"resources,omitempty"`
	Connections struct {
		Postgres bool `json:"postgres"`
		Redis    bool `json:"redis"`
	} `json:"connections,omitempty"`
}

type appStudioRegistryFile struct {
	UpdatedAt string                            `json:"updated_at"`
	Apps      map[string]appStudioRegistryEntry `json:"apps"`
}

type appStudioAppView struct {
	Name         string   `json:"name"`
	SourceType   string   `json:"sourceType"`
	Image        string   `json:"image,omitempty"`
	GitRepo      string   `json:"gitRepo,omitempty"`
	GitBranch    string   `json:"gitBranch,omitempty"`
	InternalPort int      `json:"internalPort"`
	Domains      []string `json:"domains"`
	PrimaryURL   string   `json:"primaryUrl"`
	InstallType  string   `json:"installType"`
	StackName    string   `json:"stackName"`
	ServiceName  string   `json:"serviceName"`
	CreatedAt    string   `json:"createdAt"`
	Status       string   `json:"status"` // "online", "starting", "stopped", "degraded"
	RunningTasks uint64   `json:"runningTasks"`
	DesiredTasks uint64   `json:"desiredTasks"`
	CPULimit     string   `json:"cpuLimit"`
	MemLimit     string   `json:"memLimit"`
}

type appStudioListResponse struct {
	Total       int                `json:"total"`
	Online      int                `json:"online"`
	Apps        []appStudioAppView `json:"apps"`
	GeneratedAt time.Time          `json:"generatedAt"`
}

func getAppStudioSacredDir() string {
	sacred := os.Getenv("APPSTUDIO_SACRED_DIR")
	if sacred != "" {
		return sacred
	}
	return "/root/setupmno-appstudio"
}

func findAppStudioRegistryData(sacredDir string) []byte {
	candidates := []string{
		filepath.Join(sacredDir, "registry.json"),
		"/root/setupmno-appstudio/registry.json",
		"/runtime-control/appstudio_registry.json",
		"/runtime-control/registry.json",
		"/runtime-control/setupmno-appstudio/registry.json",
	}
	for _, p := range candidates {
		if data, err := os.ReadFile(p); err == nil && len(data) > 0 {
			return data
		}
	}
	return nil
}

func collectAppStudioApps(dockerClient *http.Client, sacredDir string) (appStudioListResponse, error) {
	if sacredDir == "" {
		sacredDir = getAppStudioSacredDir()
	}

	var reg appStudioRegistryFile
	if data := findAppStudioRegistryData(sacredDir); len(data) > 0 {
		_ = json.Unmarshal(data, &reg)
	}

	var services []dockerService
	if dockerClient != nil {
		_ = dockerJSON(dockerClient, "/services?status=true", &services)
	}

	serviceByName := make(map[string]dockerService)
	for _, s := range services {
		serviceByName[s.Spec.Name] = s
	}

	result := appStudioListResponse{
		Apps:        make([]appStudioAppView, 0),
		GeneratedAt: time.Now().UTC(),
	}

	for key, entry := range reg.Apps {
		appName := entry.Name
		if appName == "" {
			appName = key
		}

		targetServiceName := entry.ServiceName
		if targetServiceName == "" {
			targetServiceName = fmt.Sprintf("%s_app", appName)
		}

		sourceType := "DOCKERHUB"
		if entry.Git.Repo != "" && entry.Git.Repo != "none" {
			sourceType = "GIT"
		} else if strings.EqualFold(entry.Runtime, "git_repo") {
			sourceType = "GIT"
		}

		image := entry.ImageTag
		if image == "" {
			image = entry.Image
		}

		domains := entry.Domains
		if len(domains) == 0 && entry.Domain != "" && entry.Domain != "none" {
			domains = []string{entry.Domain}
		}

		cpuLimit := entry.Resources.CPULimit
		memLimit := entry.Resources.MemoryLimit
		if cpuLimit == "" {
			cpuLimit = "0.50"
		}
		if memLimit == "" {
			memLimit = "512M"
		}

		view := appStudioAppView{
			Name:         appName,
			SourceType:   sourceType,
			Image:        image,
			GitRepo:      entry.Git.Repo,
			GitBranch:    entry.Git.Branch,
			InternalPort: entry.InternalPort,
			Domains:      domains,
			InstallType:  entry.InstallType,
			StackName:    entry.StackName,
			ServiceName:  targetServiceName,
			CreatedAt:    entry.CreatedAt,
			CPULimit:     cpuLimit,
			MemLimit:     memLimit,
			Status:       "stopped",
		}

		if len(domains) > 0 && domains[0] != "" && domains[0] != "none" {
			view.PrimaryURL = "https://" + domains[0]
		}

		// Localizar serviço no Swarm (busca por nome exato ou <app_name>_app ou namespace)
		var matchedService *dockerService
		if s, ok := serviceByName[targetServiceName]; ok {
			matchedService = &s
		} else if s, ok := serviceByName[key+"_app"]; ok {
			matchedService = &s
		} else if s, ok := serviceByName[key]; ok {
			matchedService = &s
		} else {
			for _, s := range services {
				if s.Spec.Labels["com.docker.stack.namespace"] == entry.StackName ||
					s.Spec.Labels["com.docker.stack.namespace"] == entry.Name {
					matchedService = &s
					break
				}
			}
		}

		if matchedService != nil {
			var running, desired uint64
			if matchedService.ServiceStatus != nil {
				running = matchedService.ServiceStatus.RunningTasks
				desired = matchedService.ServiceStatus.DesiredTasks
			}
			view.RunningTasks = running
			view.DesiredTasks = desired

			if desired == 0 {
				view.Status = "stopped"
			} else if running >= desired {
				view.Status = "online"
			} else if running == 0 {
				view.Status = "starting"
			} else {
				view.Status = "degraded"
			}
		}

		if view.Status == "online" {
			result.Online++
		}
		result.Apps = append(result.Apps, view)
	}

	result.Total = len(result.Apps)

	sort.Slice(result.Apps, func(i, j int) bool {
		if result.Apps[i].CreatedAt != result.Apps[j].CreatedAt {
			return result.Apps[i].CreatedAt > result.Apps[j].CreatedAt
		}
		return result.Apps[i].Name < result.Apps[j].Name
	})

	return result, nil
}

func fetchAppStudioLogs(dockerClient *http.Client, serviceName string, tail int) (string, error) {
	if dockerClient == nil {
		return "", fmt.Errorf("cliente docker indisponível")
	}
	if tail <= 0 {
		tail = 100
	}

	var services []dockerService
	if err := dockerJSON(dockerClient, "/services?status=true", &services); err != nil {
		return "", fmt.Errorf("falha ao consultar serviços: %w", err)
	}

	var targetID string
	for _, s := range services {
		if s.Spec.Name == serviceName || s.ID == serviceName ||
			s.Spec.Name == serviceName+"_app" ||
			s.Spec.Labels["com.docker.stack.namespace"] == serviceName {
			targetID = s.ID
			break
		}
	}
	if targetID == "" {
		return "", fmt.Errorf("serviço Swarm '%s' não foi encontrado", serviceName)
	}

	endpoint := fmt.Sprintf("/services/%s/logs?stdout=1&stderr=1&tail=%d&timestamps=1", url.PathEscape(targetID), tail)
	bytes, err := dockerBytes(dockerClient, endpoint, 128*1024)
	if err != nil {
		return "", fmt.Errorf("falha ao ler logs do Swarm: %w", err)
	}

	return strings.TrimSpace(string(bytes)), nil
}

func restartAppStudioService(dockerClient *http.Client, serviceName string) error {
	if dockerClient == nil {
		return fmt.Errorf("cliente docker indisponível")
	}

	var services []dockerService
	if err := dockerJSON(dockerClient, "/services?status=true", &services); err != nil {
		return fmt.Errorf("falha ao consultar serviços: %w", err)
	}

	var targetID string
	for _, s := range services {
		if s.Spec.Name == serviceName || s.ID == serviceName ||
			s.Spec.Name == serviceName+"_app" ||
			s.Spec.Labels["com.docker.stack.namespace"] == serviceName {
			targetID = s.ID
			break
		}
	}
	if targetID == "" {
		return fmt.Errorf("serviço Swarm '%s' não encontrado para reinício", serviceName)
	}

	var inspectData map[string]interface{}
	if err := dockerJSON(dockerClient, "/services/"+url.PathEscape(targetID), &inspectData); err != nil {
		return fmt.Errorf("falha ao inspecionar serviço: %w", err)
	}

	versionObj, _ := inspectData["Version"].(map[string]interface{})
	versionIndex := uint64(0)
	if idxVal, ok := versionObj["Index"].(float64); ok {
		versionIndex = uint64(idxVal)
	}

	specObj, ok := inspectData["Spec"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("spec do serviço inválida")
	}

	taskTemplate, _ := specObj["TaskTemplate"].(map[string]interface{})
	if taskTemplate == nil {
		taskTemplate = make(map[string]interface{})
	}
	forceUpdate := uint64(0)
	if fuVal, ok := taskTemplate["ForceUpdate"].(float64); ok {
		forceUpdate = uint64(fuVal)
	}
	taskTemplate["ForceUpdate"] = forceUpdate + 1
	specObj["TaskTemplate"] = taskTemplate

	payloadBytes, err := json.Marshal(specObj)
	if err != nil {
		return fmt.Errorf("falha ao serializar spec: %w", err)
	}

	updateURL := fmt.Sprintf("http://docker/services/%s/update?version=%d",
		url.PathEscape(targetID), versionIndex)

	req, err := http.NewRequest(http.MethodPost, updateURL, bytes.NewReader(payloadBytes))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := dockerClient.Do(req)
	if err != nil {
		return fmt.Errorf("falha na requisição de update: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("Docker retornou HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}

	return nil
}
