---
{
  "schemaVersion": 1,
  "documentId": "setup-listmonk-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "95009034144e17d412e2cc4269026bba8c25ca437d9c68eb1a605c5671371601",
  "documentType": "setup",
  "title": "listmonk no Setup MNO",
  "setupId": "listmonk",
  "setupVersion": "7.48.19",
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
    "listmonk",
    "newsletter",
    "email",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "listmonk-installer",
      "title": "Instalador listmonk",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/listmonk.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "listmonk-install",
      "title": "Instalação oficial listmonk",
      "sourceType": "official-documentation",
      "location": "https://listmonk.app/docs/installation/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "listmonk-upgrade",
      "title": "Atualização oficial listmonk",
      "sourceType": "official-documentation",
      "location": "https://listmonk.app/docs/upgrade/",
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
# listmonk no Setup MNO

## Quando usar

Use para listas, campanhas e newsletters quando consentimento, descadastro, reputação e conformidade estiverem definidos. Não envie campanhas sem autorização nem trate SMTP como garantia de entrega.

## Arquitetura no Setup MNO

O instalador usa `listmonk na tag latest`, PostgreSQL compartilhado com usuário dedicado, credenciais administrativas no YAML e limite de 512 MB. O projeto requer PostgreSQL 12+ e executa instalação/migração de schema.

## Pré-requisitos

Exige domínio HTTPS, PostgreSQL, SMTP, DNS de email, política de consentimento e backup. Planeje volume, anexos, bounces e opt-out.

## Fluxo seguro

Proteja admin, banco e SMTP; remova credenciais legadas após migração para v4 conforme documentação. Aplique rate limits e não exponha listas ou tokens.

## Primeiro acesso e integrações

Com contatos fictícios e domínio de teste, crie lista, modelo e campanha de uma mensagem; valide opt-in/opt-out, bounce e tracking conforme política.

## Backup e atualização

Faça dump do PostgreSQL antes de cada atualização; o guia alerta que downgrade exige restaurar o banco da versão anterior. Preserve uploads/configuração e tag conhecida.

## Validação

Confirme login, permissões, importação fictícia, envio de teste, descadastro, jobs, persistência e restore. Não use endereços reais na homologação.

## Riscos e limites

Email em massa envolve abuso, reputação e dados pessoais. `latest`, segredos no YAML e migrações v4 exigem janela e rollback por backup.

## Diagnóstico

Separe app, banco, SMTP, DNS, fila, bounce e proxy. Remova emails, listas e credenciais.
