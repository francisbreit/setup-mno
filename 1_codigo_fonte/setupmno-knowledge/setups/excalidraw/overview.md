---
{
  "schemaVersion": 1,
  "documentId": "setup-excalidraw-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e5034cd89d517411d5c838e3c7e0c7bcb392f28015ab93b830e0be1a247b4aab",
  "documentType": "setup",
  "title": "Excalidraw no Setup MNO",
  "setupId": "excalidraw",
  "setupVersion": "7.19.9",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "excalidraw",
    "quadro",
    "diagramas",
    "colaboracao"
  ],
  "sources": [
    {
      "sourceId": "excalidraw-installer",
      "title": "Instalador Excalidraw",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/excalidraw.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "excalidraw-repo",
      "title": "Repositório oficial Excalidraw",
      "sourceType": "official-documentation",
      "location": "https://github.com/excalidraw/excalidraw",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "excalidraw-docker",
      "title": "Imagem e self-hosting Excalidraw",
      "sourceType": "official-documentation",
      "location": "https://github.com/excalidraw/excalidraw/blob/master/docker-compose.yml",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Excalidraw no Setup MNO

## Quando usar

Use para quadros e diagramas visuais no navegador. A imagem frontend isolada não equivale automaticamente à colaboração completa, persistência server-side ou recursos do serviço excalidraw.com.

## Arquitetura no Setup MNO

O catálogo oferece apenas amd64. O instalador usa `Excalidraw na tag latest`, uma réplica e rota web com limite de 1 GB, sem backend colaborativo ou storage adicional explícito.

## Pré-requisitos

Exige domínio HTTPS e decisão clara entre uso local no navegador e colaboração persistente. Avalie backend, compartilhamento, retenção e exportação antes de prometer trabalho em equipe.

## Fluxo seguro

Não trate links de cena como controle de acesso. Proteja a rota quando houver conteúdo interno, fixe versão e não armazene segredos em desenhos.

## Primeiro acesso e integrações

Crie desenho fictício, exporte e reabra; teste compartilhamento em navegadores separados e documente o que persiste ou depende do cliente. Não prometa colaboração não verificada.

## Backup e atualização

A exportação dos desenhos é a cópia principal quando não há backend persistente. Antes de atualizar, preserve arquivos exportados e imagem anterior; valide compatibilidade de importação.

## Validação

Confirme carregamento, criação, exportação/importação, fontes, HTTPS, comportamento offline e colaboração somente se houver backend comprovado.

## Riscos e limites

Frontend sozinho pode induzir expectativa falsa de persistência e colaboração. `latest` é não determinístico e ARM não está no catálogo.

## Diagnóstico

Separe asset frontend, cache, proxy, estado local e eventual backend. Use cenas fictícias sem dados confidenciais.
