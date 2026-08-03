---
{
  "schemaVersion": 1,
  "documentId": "setup-docmost-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ee627043a9141a8e1a493559653710ca3abf6575df68ed9c813e991768b00fce",
  "documentType": "setup",
  "title": "Docmost no Setup MNO",
  "setupId": "docmost",
  "setupVersion": "7.5.0",
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
    "docmost",
    "wiki",
    "documentacao",
    "colaboracao"
  ],
  "sources": [
    {
      "sourceId": "docmost-installer",
      "title": "Instalador Docmost",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/docmost.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "docmost-install",
      "title": "Instalação oficial Docmost",
      "sourceType": "official-documentation",
      "location": "https://docmost.com/docs/installation",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "docmost-docs",
      "title": "Documentação oficial Docmost",
      "sourceType": "official-documentation",
      "location": "https://docmost.com/docs/",
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
# Docmost no Setup MNO

## Quando usar

Use como wiki colaborativa para equipes, espaços, páginas e anexos. Não confunda com suíte de escritório ou repositório de segredos.

## Arquitetura no Setup MNO

O instalador usa `Docmost na tag latest`, PostgreSQL compartilhado e Redis `latest` dentro do mesmo stack, volume de dados e `APP_SECRET` no YAML. O guia oficial atual usa PostgreSQL 18 e Redis 8; compatibilidade deve ser confirmada.

## Pré-requisitos

Exige domínio HTTPS, banco, Redis, volume, segredo com pelo menos 32 caracteres e SMTP quando houver convites. O catálogo reserva 1 GB.

## Fluxo seguro

Gere `APP_SECRET` forte e persistente, restrinja cadastro e trate configuração do stack como sensível. Não armazene senhas operacionais em páginas.

## Primeiro acesso e integrações

Crie proprietário, espaço, página e anexo fictícios; teste convite, edição e permissões. Valide SMTP e exportação antes de migrar conteúdo real.

## Backup e atualização

Copie PostgreSQL e volume de anexos em ponto consistente. Antes de atualizar, fixe versões, leia notas, teste migrações e restauração; preserve o segredo original.

## Validação

Confirme login, criação, edição simultânea, permissões, anexo, busca, convite, persistência e restauração. Verifique conectividade de banco e Redis.

## Riscos e limites

Tags flutuantes, versões de dependências não alinhadas ao guia atual e segredo em YAML exigem homologação. Restore incompleto sem banco e arquivos.

## Diagnóstico

Separe aplicação, migrações, PostgreSQL, Redis, storage, SMTP e proxy. Use conteúdo fictício e sanitize URLs e emails.
