---
{
  "schemaVersion": 1,
  "documentId": "setup-discourse-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "bcd4c2f4e4e8f4bc602bdc86618c9c1f4e72d4c3f963371ed32c022caf992708",
  "documentType": "setup",
  "title": "Discourse no Setup MNO",
  "setupId": "discourse",
  "setupVersion": "7.19.7",
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
    "discourse",
    "comunidade",
    "forum",
    "moderacao"
  ],
  "sources": [
    {
      "sourceId": "discourse-installer",
      "title": "Instalador Discourse",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/discourse.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "discourse-install",
      "title": "Instalação oficial Discourse",
      "sourceType": "official-documentation",
      "location": "https://github.com/discourse/discourse_docker",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "discourse-backup",
      "title": "Backup do Discourse pela linha de comando",
      "sourceType": "official-documentation",
      "location": "https://meta.discourse.org/t/backup-discourse-from-the-command-line/64364",
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
# Discourse no Setup MNO

## Quando usar

Use para comunidades, fóruns, moderação e conhecimento público ou privado. Exige governança de usuários, email transacional e rotina operacional; não é uma página estática.

## Arquitetura no Setup MNO

O instalador atual usa `Discourse na tag latest`, PostgreSQL compartilhado, Redis 7.2.4 dedicado, volume e SMTP. A topologia diverge do método oficial `discourse_docker` e precisa ser homologada a cada atualização.

## Pré-requisitos

Exige domínio HTTPS, DNS reverso e reputação de email, banco, Redis, armazenamento e capacidade compatível com usuários e plugins. Defina administradores e política de moderação.

## Fluxo seguro

Use segredos exclusivos, proteja SMTP e banco e restrinja cadastro conforme a comunidade. Plugins ampliam superfície e devem ter origem e compatibilidade verificadas.

## Primeiro acesso e integrações

Crie administrador, configure email, categorias e permissões; teste convite, postagem, moderação e recuperação com contas fictícias. Só depois habilite SSO ou plugins.

## Backup e atualização

Use backup do Discourse e cópias externas de banco e uploads. Antes de atualizar imagem ou plugin, gere backup, registre versões e teste restauração. Rollback exige dados compatíveis.

## Validação

Confirme bootstrap, jobs, email, uploads, busca, moderação, backup e restore de teste. Verifique saúde de PostgreSQL e Redis e ausência de segredos em logs.

## Riscos e limites

`latest`, topologia não oficial, plugins e segredos no YAML aumentam risco de migração. Email mal configurado compromete cadastro e recuperação.

## Diagnóstico

Separe proxy, web, Sidekiq, PostgreSQL, Redis, SMTP, uploads e plugins. Não compartilhe posts privados, emails ou chaves.
