---
{
  "schemaVersion": 1,
  "documentId": "infra-redis-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "57101dc2c80c30447404d962b367d8e533b321f188a3dcd8951682e49fe7f4d0",
  "documentType": "infrastructure",
  "title": "Redis compartilhado e Redis dedicado",
  "topicId": "redis",
  "setupVersion": "7.24.1",
  "architectures": ["amd64", "arm64"],
  "category": "architecture",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["redis", "cache", "isolamento"],
  "sources": [
    {
      "sourceId": "redis-installer-script",
      "title": "Instalador de instâncias Redis",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/redis.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "redis-base-script",
      "title": "Redis da infraestrutura base",
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
# Redis compartilhado e Redis dedicado

## Papel no Setup MNO

A infraestrutura histórica possui Redis compartilhado, enquanto novas
aplicações que dependem de Redis devem usar uma instância dedicada. O
isolamento impede que consumo, políticas de memória ou limpeza de uma
aplicação afetem outra.

## Princípios

O documento do setup deve declarar se usa serviço-base ou dependência
dedicada. Senhas, URLs de conexão e conteúdo de chaves nunca são recuperados
nem enviados ao provedor de IA. Dependências dedicadas são instaladas antes da
aplicação principal.

## Validação

O diagnóstico verifica existência da dependência esperada e estado agregado
das réplicas. Uma aplicação sem sua instância dedicada deve ser tratada como
incompatibilidade de arquitetura, não como autorização para conectá-la ao
serviço compartilhado.

## Riscos e limites

Apagar dados ou trocar políticas pode interromper filas, sessões e cache. O
Assistente não recomenda limpeza destrutiva. Recuperação deve seguir a
documentação específica da aplicação e confirmação humana.
