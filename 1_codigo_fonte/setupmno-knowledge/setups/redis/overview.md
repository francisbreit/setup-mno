---
{
  "schemaVersion": 1,
  "documentId": "setup-redis-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "94eae70ac09bb74fa2e2d8a4769b62a0447eff4d6fd314c0d0bbd2ff63d67e8a",
  "documentType": "setup",
  "title": "Instância Redis no Setup MNO",
  "setupId": "redis",
  "setupVersion": "7.48.2",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["redis", "cache", "filas"],
  "sources": [
    {
      "sourceId": "redis-installer",
      "title": "Instalador Redis",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/redis.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "redis-catalog",
      "title": "Entrada Redis no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
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
# Instância Redis no Setup MNO

## Quando usar

Use para criar uma instância persistente destinada a uma aplicação que exige
cache, fila ou armazenamento chave-valor. Novas aplicações não devem ser
ligadas ao Redis compartilhado por conveniência.

## Arquitetura no Setup MNO

O instalador cria nome único, volume persistente e serviço somente na rede
interna. A instância pode ser registrada como stack editável no Portainer ou
implantada diretamente.

## Pré-requisitos

Defina a aplicação proprietária, política de memória, persistência e ciclo de
vida. O serviço consumidor deve participar da rede interna e ter configuração
compatível.

## Fluxo seguro

O Instalador Seguro gera o sufixo, cria volume e stack e apresenta os dados
necessários ao operador. O Assistente não recupera conteúdo de chaves nem
connection string.

## Validação

Confirme réplica, persistência com dado descartável e conexão a partir da
aplicação autorizada. Não publique o serviço diretamente na internet.

## Riscos e limites

Limpeza ou perda do volume pode interromper filas e sessões. Uso sem limite de
memória pode afetar a VPS. Backup e restauração dependem da função que a
aplicação atribui aos dados.

## Diagnóstico

Separe serviço indisponível, erro de rede e incompatibilidade da aplicação. Não
recomende limpeza global como correção genérica; primeiro identifique o dono e
o papel da instância.
