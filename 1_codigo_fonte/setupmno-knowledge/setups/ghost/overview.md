---
{
  "schemaVersion": 1,
  "documentId": "setup-ghost-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "0a7d8851b29bc48975094aaa6887c27651cb8c310748ebcc033b4acea267ba8a",
  "documentType": "setup",
  "title": "Ghost no Setup MNO",
  "setupId": "ghost",
  "setupVersion": "7.48.17",
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
    "ghost",
    "cms",
    "blog",
    "mysql"
  ],
  "sources": [
    {
      "sourceId": "ghost-installer",
      "title": "Instalador Ghost",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/ghost.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ghost-docker",
      "title": "Instalação Docker oficial Ghost",
      "sourceType": "official-documentation",
      "location": "https://docs.ghost.org/install/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ghost-backup",
      "title": "Backup manual oficial Ghost",
      "sourceType": "official-documentation",
      "location": "https://docs.ghost.org/faq/manual-backup",
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
# Ghost no Setup MNO

## Quando usar

Use para publicação editorial, newsletters e sites de conteúdo. Não presuma entrega de email em massa sem provedor transacional, reputação e conformidade.

## Arquitetura no Setup MNO

O instalador usa `ghost:latest`, uma substack MySQL/Percona compartilhada pelo fluxo, volume de conteúdo, SMTP e rota. O catálogo estima 1 GB.

## Pré-requisitos

Exige domínio HTTPS, MySQL compatível, volume, SMTP e política editorial/backup. Planeje crescimento de imagens, membros e newsletters.

## Fluxo seguro

Proteja URL administrativa, banco e SMTP; aplique menor privilégio e restrinja contas. Não exponha segredos no YAML ou logs. Fixe versão antes da mudança.

## Primeiro acesso e integrações

Crie administrador, post e imagem fictícios; teste publicação, tema, email e membro de teste. Valide URLs canônicas e redirects.

## Backup e atualização

Exporte conteúdo pelo Ghost e preserve banco, diretório `content`, temas e configuração. Antes de atualizar, gere backup completo e teste importação/restauração; rollback exige banco compatível.

## Validação

Confirme frontend/admin, publicação, upload, tema, SMTP, membros, persistência e restauração. Verifique jobs e URLs públicas.

## Riscos e limites

`latest`, MySQL compartilhado e email em massa ampliam impacto. Backup apenas do banco não preserva temas e arquivos; plugins/temas podem quebrar upgrades.

## Diagnóstico

Separe Ghost, MySQL, storage, tema, SMTP e proxy. Use conteúdo e emails fictícios.
