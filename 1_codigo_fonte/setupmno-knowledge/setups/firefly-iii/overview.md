---
{
  "schemaVersion": 1,
  "documentId": "setup-firefly-iii-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "f8ba1e6f37787f23f818292b2a65e955ce775c781746b5b82b4c27d7114ab0a8",
  "documentType": "setup",
  "title": "Firefly III no Setup MNO",
  "setupId": "firefly-iii",
  "setupVersion": "7.7.38",
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
    "firefly-iii",
    "financas",
    "orcamento",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "firefly-iii-installer",
      "title": "Instalador Firefly III",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/fireflyiii.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "firefly-docs",
      "title": "Documentação oficial Firefly III",
      "sourceType": "official-documentation",
      "location": "https://docs.firefly-iii.org/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "firefly-releases",
      "title": "Releases oficiais Firefly III",
      "sourceType": "official-documentation",
      "location": "https://github.com/firefly-iii/firefly-iii/releases",
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
# Firefly III no Setup MNO

## Quando usar

Use para finanças pessoais, contas, transações e relatórios. Não é contabilidade fiscal empresarial nem aconselhamento financeiro e não deve receber dados reais antes de validar privacidade e restauração.

## Arquitetura no Setup MNO

O instalador usa `Firefly III na tag latest`, PostgreSQL compartilhado com usuário dedicado, volume de uploads, cron token e rota HTTPS, com limite aproximado de 512 MB.

## Pré-requisitos

Exige domínio, PostgreSQL, volume, `APP_KEY`, cron token e política de backup. Importadores e conexões bancárias precisam de avaliação própria e podem tratar credenciais financeiras.

## Fluxo seguro

Proteja APP_KEY, banco, cron token e uploads; não os exiba no YAML, logs ou Assistente. Restrinja cadastro e aplique TLS. Tags flutuantes exigem ensaio prévio.

## Primeiro acesso e integrações

Crie conta fictícia, transação, categoria e orçamento; valide relatórios e cron. Importe apenas CSV sintético até confirmar mapeamento e rollback.

## Backup e atualização

Faça dump do PostgreSQL e cópia do volume de uploads/configuração. Antes da atualização, registre a imagem, faça backup e teste restauração; migrações podem impedir downgrade sem banco anterior.

## Validação

Confirme login, cadastro restrito, transações fictícias, relatórios, cron, upload, persistência e restauração. Revise logs sem saldos ou descrições reais.

## Riscos e limites

Dados financeiros e APP_KEY são críticos. `latest`, limite modesto e dependência compartilhada exigem monitoramento e janela de mudança.

## Diagnóstico

Separe aplicação, migração, banco, cron, uploads, email e proxy. Use dados sintéticos e erros sanitizados.
