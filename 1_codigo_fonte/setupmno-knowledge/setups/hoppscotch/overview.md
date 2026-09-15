---
{
  "schemaVersion": 1,
  "documentId": "setup-hoppscotch-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a49df2f4f3ffb7877b3f72239fbf12172630c1cae2e2d38ccdb023f4d2fc32b0",
  "documentType": "setup",
  "title": "Hoppscotch no Setup MNO",
  "setupId": "hoppscotch",
  "setupVersion": "7.48.2",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "hoppscotch",
    "api",
    "desenvolvimento",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "hoppscotch-installer",
      "title": "Instalador Hoppscotch",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/hoppscotch.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "hoppscotch-selfhost",
      "title": "Self-hosting oficial Hoppscotch",
      "sourceType": "official-documentation",
      "location": "https://docs.hoppscotch.io/documentation/self-host/community-edition/install-and-build",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "hoppscotch-config",
      "title": "Configuração oficial Hoppscotch",
      "sourceType": "official-documentation",
      "location": "https://docs.hoppscotch.io/documentation/self-host/community-edition/environment-variables",
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
# Hoppscotch no Setup MNO

## Quando usar

Use para desenvolver e testar APIs, coleções e ambientes em equipe. Não armazene tokens de produção sem política de acesso e não trate o cliente como gateway ou scanner de segurança.

## Arquitetura no Setup MNO

O instalador fixa `Hoppscotch na versão 2026.6.1` com digest, usa PostgreSQL compartilhado, migração controlada, SMTP e rota, com 2 GB. Há cuidados para não deixar variável temporária de migração no serviço final.

## Pré-requisitos

Exige domínio HTTPS, banco, segredos de autenticação, SMTP e URLs corretas de frontend/backend/admin. Integrações OAuth exigem callbacks registrados.

## Fluxo seguro

Use contas e dados de teste, proteja JWT, banco, SMTP e OAuth e restrinja o admin. Ambientes com tokens reais exigem governança própria; não os envie ao Assistente.

## Primeiro acesso e integrações

Crie usuário e workspace fictícios, execute request contra API descartável e teste coleção, ambiente e convite. Valide URLs e CORS.

## Backup e atualização

Preserve PostgreSQL e configuração/segredos. Antes da atualização, faça dump, teste migração com tag candidata e mantenha imagem anterior e banco pré-migração.

## Validação

Confirme login, admin, request REST/GraphQL/WebSocket quando usado, coleção, persistência, SMTP e migrações. Audite ausência de tokens nos logs.

## Riscos e limites

A ferramenta facilita chamadas arbitrárias; SSRF, tokens e coleções compartilhadas precisam de controle. Mudanças de schema e URLs incorretas podem bloquear o serviço.

## Diagnóstico

Separe frontend, backend, admin, banco, OAuth, SMTP, CORS e destino. Use endpoint de teste e sanitize headers/corpo.
