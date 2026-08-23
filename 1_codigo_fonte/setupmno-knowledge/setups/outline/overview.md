---
{
  "schemaVersion": 1,
  "documentId": "setup-outline-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ea9473191d397380026219995bcb8477fc6a9abad3555061a8563a651516cc85",
  "documentType": "setup",
  "title": "Outline no Setup MNO",
  "setupId": "outline",
  "setupVersion": "7.28.0",
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
    "outline",
    "wiki",
    "oidc",
    "colaboracao"
  ],
  "sources": [
    {
      "sourceId": "outline-installer",
      "title": "Instalador Outline",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/outline.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "outline-requirements",
      "title": "Requisitos oficiais Outline",
      "sourceType": "official-documentation",
      "location": "https://docs.getoutline.com/s/hosting/doc/requirements-ULdYnwi4wG",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "outline-hosting",
      "title": "Guia oficial de hosting Outline",
      "sourceType": "official-documentation",
      "location": "https://docs.getoutline.com/s/hosting/doc/hosting-outline-nipGaCRBDu",
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
# Outline no Setup MNO

## Quando usar

Use como wiki colaborativa para equipes com provedor de autenticação compatível. Outline exige autenticação externa; não espere cadastro local convencional sem configurar OIDC/OAuth suportado.

## Arquitetura no Setup MNO

O instalador usa `Outline na tag latest`, PostgreSQL compartilhado com usuário dedicado, Redis dedicado no mesmo stack, volume e OIDC. O catálogo não informa RAM; o oficial exige 512 MB mínimos e recomenda 1 GB ou mais.

## Pré-requisitos

Exige domínio dedicado HTTPS, PostgreSQL 12+, Redis 4+, storage, secret persistente e provedor de autenticação. Defina callbacks, grupos e política de exportação.

## Fluxo seguro

Use OIDC com escopos mínimos, proteja client secret, banco e Redis e restrinja domínio/grupos. Segredos no YAML precisam de migração para mecanismo protegido.

## Primeiro acesso e integrações

Com tenant e contas de teste, valide login/logout, convite, coleção, documento, anexo, permissão e callback. Confirme como recuperar acesso administrativo.

## Backup e atualização

Preserve PostgreSQL, storage e configuração/segredos. Antes de atualizar `latest`, fixe candidata, faça dump e teste migração/restauração; mantenha IdP disponível.

## Validação

Confirme OIDC, sessão, permissões, edição, anexos, busca, exportação e restore. Verifique falha controlada do IdP e do Redis.

## Riscos e limites

Erro no IdP pode bloquear todos os usuários. Tags flutuantes e secrets no YAML exigem cautela; o serviço requer experiência DevOps segundo o guia.

## Diagnóstico

Separe Outline, banco, Redis, storage, IdP/callback e proxy. Não compartilhe tokens, documentos ou grupos reais.
