---
{
  "schemaVersion": 1,
  "documentId": "setup-affine-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ef4d227349ee69fc25f2a06b0a8685d481454ac401a71d2c5467438b6c34227f",
  "documentType": "setup",
  "title": "AFFiNE no Setup MNO",
  "setupId": "affine",
  "setupVersion": "7.7.3",
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
    "affine",
    "colaboracao",
    "documentos",
    "workspace"
  ],
  "sources": [
    {
      "sourceId": "affine-installer",
      "title": "Instalador AFFiNE",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/affine.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "affine-docker",
      "title": "Repositório oficial de implantação AFFiNE",
      "sourceType": "official-documentation",
      "location": "https://github.com/toeverything/docker",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "affine-docs",
      "title": "Documentação oficial AFFiNE",
      "sourceType": "official-documentation",
      "location": "https://docs.affine.pro/self-host-affine",
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
# AFFiNE no Setup MNO

## Quando usar

Use como workspace colaborativo para documentos, quadros e conhecimento. Não presuma equivalência integral a Notion nem disponibilidade de todos os recursos do serviço hospedado.

## Arquitetura no Setup MNO

O instalador atual usa `AFFiNE GraphQL na tag canary-1721875`, PostgreSQL e Redis compartilhados, volume de armazenamento e rota web. A imagem canary fixa é antiga e os segredos administrativos e SMTP entram no YAML; isso exige revisão antes de produção.

## Pré-requisitos

Exige domínio, PostgreSQL, Redis, armazenamento persistente, SMTP quando necessário e pelo menos 1 GB conforme catálogo. Faça inventário de usuários, anexos, limites e política de exportação.

## Fluxo seguro

Gere segredos exclusivos, restrinja contas administrativas e trate o YAML do stack como sensível. Valide a compatibilidade da imagem, das migrações e do banco em ambiente isolado antes de aceitar dados reais.

## Primeiro acesso e integrações

Crie usuário de teste, workspace, documento e anexo fictício; valide convite e email. Só habilite integrações após confirmar permissões e exportação.

## Backup e atualização

Salve banco e armazenamento de uploads em ponto consistente, além da configuração. Antes de atualizar, fixe a imagem candidata, faça backup, teste migração e restauração. Rollback pode exigir banco anterior.

## Validação

Confirme réplica saudável, login, convite, edição simultânea, upload, persistência, SMTP e exportação. Revise logs para não expor tokens.

## Riscos e limites

Canary antigo, dependências compartilhadas e segredos em YAML elevam o risco. O catálogo não prova compatibilidade com a versão oficial atual; não atualize diretamente sem ensaio.

## Diagnóstico

Separe aplicação, migração, PostgreSQL, Redis, armazenamento, SMTP e proxy. Use documentos fictícios e somente erros sanitizados.
