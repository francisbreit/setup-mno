---
{
  "schemaVersion": 1,
  "documentId": "setup-penpot-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "9c05e332603153728c0a1a5fb8d85fe8b2f648d7c667266ccee96d8a4dc1970c",
  "documentType": "setup",
  "title": "Penpot no Setup MNO",
  "setupId": "penpot",
  "setupVersion": "7.7.37",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "penpot",
    "design",
    "colaboracao",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "penpot-installer",
      "title": "Instalador Penpot",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/penpot.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "penpot-docker",
      "title": "Instalação e backup oficiais Penpot",
      "sourceType": "official-documentation",
      "location": "https://help.penpot.app/technical-guide/getting-started/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "penpot-guide",
      "title": "Guia técnico oficial Penpot",
      "sourceType": "official-documentation",
      "location": "https://help.penpot.app/technical-guide/",
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
# Penpot no Setup MNO

## Quando usar

Use para design colaborativo e prototipação quando equipes precisam de alternativa aberta. Não exponha Mailcatcher ou serviços internos nem presuma atualização direta entre versões distantes.

## Arquitetura no Setup MNO

O instalador fixa Penpot 2.16 em frontend, backend, MCP e exporter; inclui PostgreSQL 15 com senha estática `penpot`, Valkey e Mailcatcher `latest` com porta publicada. Os limites somam pelo menos 4 GB, sem contar dependências.

## Pré-requisitos

Exige domínio HTTPS, PostgreSQL, assets persistentes, cache, SMTP real em produção e 4 GB ou mais. O guia recomenda versão fixada e upgrades em pequenos incrementos.

## Fluxo seguro

Troque a senha estática, remova Mailcatcher/porta de produção, proteja banco/cache e desabilite cadastro quando necessário. MCP e integrações exigem escopo explícito.

## Primeiro acesso e integrações

Crie conta e projeto fictícios, arquivo, asset, compartilhamento e exportação; valide email e colaboração em dois navegadores. Não use Mailcatcher publicamente.

## Backup e atualização

O oficial requer backup do volume PostgreSQL e dos assets; copiar diretório de volume diretamente não é procedimento seguro. Teste restore e faça upgrades incrementais.

## Validação

Confirme frontend/backend, WebSocket, export, assets, email, permissões, backup e restore. Verifique que portas internas não estão publicadas.

## Riscos e limites

Senha fixa, Mailcatcher exposto, versão 2.16 defasada e topologia complexa são riscos críticos. Migrações distantes podem falhar.

## Diagnóstico

Separe frontend, backend, exporter, MCP, banco, Valkey, storage, SMTP e proxy. Use design fictício.
