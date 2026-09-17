---
{
  "schemaVersion": 1,
  "documentId": "infra-wsl2-architecture",
  "documentVersion": "1.1.0",
  "contentSHA256": "c02deae803dd05241b48e7d53788c23d0a5d9394fcf33581243e99f570ed1b5b",
  "documentType": "infrastructure",
  "title": "WSL2 e Docker Desktop no Setup MNO",
  "topicId": "wsl2",
  "setupVersion": "7.48.12",
  "architectures": ["amd64", "arm64"],
  "category": "compatibility",
  "status": "reviewed",
  "updatedAt": "2026-08-17",
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

Antes de autenticar, limpar arquivos ou decidir pela preparação do Swarm, os
bootstraps validam funcionalmente o Docker dentro da distribuição WSL2. Cliente
ausente, engine inacessível, Windows Containers, arquitetura divergente ou
estado inconsistente do Swarm interrompem o fluxo com instruções para ativar o
Docker Desktop e a integração da distribuição. Em VPS Linux, esse gate não
altera o comportamento existente.

## Princípios

WSL2 segue o fluxo de Cloudflare Tunnel para atravessar limitações da rede
local. O ambiente de homologação instalado é imutável: testes usam recursos
temporários, nomes exclusivos e limpeza apenas do que foi criado pelo teste.

## Validação

Confirmar detecção do WSL2, cliente e engine Docker acessíveis, engine Linux,
arquitetura compatível, estado `active` ou `inactive` do Swarm, memória
disponível e sincronização de relógio. Swarm `inactive` é válido na primeira
instalação; indisponibilidade do Docker nunca deve ser confundida com ausência
do Swarm nem encaminhar automaticamente para o `dockerswarm.sh`.

## Riscos e limites

Reinícios do Windows podem alterar estado de rede e disponibilidade do Docker.
O Assistente não modifica a instalação local nem força reinícios. Quando uma
correção afetar o host, deve apresentar o impacto e solicitar ação humana fora
do chat.
