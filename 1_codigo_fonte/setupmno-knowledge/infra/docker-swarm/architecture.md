---
{
  "schemaVersion": 1,
  "documentId": "infra-docker-swarm-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "929a45d7ea352811c5c57df473c312a68f0153e34c59f73cb499fab8ee070d2b",
  "documentType": "infrastructure",
  "title": "Docker Swarm como base do Setup MNO",
  "topicId": "docker-swarm",
  "setupVersion": "7.7.37",
  "architectures": ["amd64", "arm64"],
  "category": "architecture",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["docker-swarm", "orquestracao", "infraestrutura"],
  "sources": [
    {
      "sourceId": "dockerswarm-x86-script",
      "title": "Instalador da infraestrutura base x86",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dockerswarm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "dockerswarm-arm-script",
      "title": "Instalador da infraestrutura base ARM",
      "sourceType": "setup-mno",
      "location": "arm/SetupLowCodeMno/dockerswarm.sh",
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
# Docker Swarm como base do Setup MNO

## Papel no Setup MNO

O Swarm é a camada de orquestração que mantém stacks, serviços, redes e
volumes usados pelos setups. O instalador verifica esse estado antes de abrir o
catálogo e encaminha a preparação da infraestrutura quando a base está
incompleta.

## Princípios

A instalação deve preservar recursos existentes, usar nomes previsíveis,
separar redes internas das rotas públicas e manter as arquiteturas x86 e ARM
com a mesma lógica. Mudanças reais pertencem ao Instalador Seguro; o Assistente
apenas interpreta estado agregado e orienta o usuário.

## Validação

O diagnóstico deve distinguir nó fora do Swarm, nó ativo sem serviços-base e
serviços com réplicas degradadas. A evidência mínima é o estado do nó, seguida
do estado desejado e atual das réplicas, sem expor comandos, IDs internos ou
dados do host.

## Riscos e limites

Recriar o Swarm, remover stacks ou alterar redes pode interromper todos os
setups. O copiloto não deve sugerir ações destrutivas como primeira resposta.
Quando a evidência indicar mudança estrutural, deve encaminhar o usuário ao
Instalador Seguro e recomendar backup prévio.
