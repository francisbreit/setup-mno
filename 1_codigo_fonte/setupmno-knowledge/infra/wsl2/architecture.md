---
{
  "schemaVersion": 1,
  "documentId": "infra-wsl2-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "4109ffe5b9aec196d90c8bae216ab7a1d1196ddae55968d189f109073997bdea",
  "documentType": "infrastructure",
  "title": "WSL2 e Docker Desktop no Setup MNO",
  "topicId": "wsl2",
  "setupVersion": "6.4.0",
  "architectures": ["amd64", "arm64"],
  "category": "compatibility",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["wsl2", "docker-desktop", "compatibilidade"],
  "sources": [
    {
      "sourceId": "bootstrap-wsl2-script",
      "title": "Detecção e ajustes de WSL2 no bootstrap",
      "sourceType": "setup-mno",
      "location": "setup-mno.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "dockerswarm-wsl2-script",
      "title": "Preparação do Swarm em WSL2",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dockerswarm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# WSL2 e Docker Desktop no Setup MNO

## Papel no Setup MNO

O ambiente local usa WSL2 integrado ao Docker Desktop. O bootstrap detecta o
ambiente e aplica compatibilidades de rede e relógio, enquanto a preparação do
Swarm reutiliza o Docker disponível.

## Princípios

WSL2 segue o fluxo de Cloudflare Tunnel para atravessar limitações da rede
local. O ambiente de homologação instalado é imutável: testes usam recursos
temporários, nomes exclusivos e limpeza apenas do que foi criado pelo teste.

## Validação

Confirmar detecção do WSL2, disponibilidade do Docker Desktop, estado do Swarm,
memória disponível e sincronização de relógio. Problemas do Windows, da
distribuição Linux e do Docker devem ser diferenciados antes da recomendação.

## Riscos e limites

Reinícios do Windows podem alterar estado de rede e disponibilidade do Docker.
O Assistente não modifica a instalação local nem força reinícios. Quando uma
correção afetar o host, deve apresentar o impacto e solicitar ação humana fora
do chat.
