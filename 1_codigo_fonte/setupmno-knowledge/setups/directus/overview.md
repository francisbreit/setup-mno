---
{
  "schemaVersion": 1,
  "documentId": "setup-directus-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "82b903526b90a7e8ec15ea39e4a5a4e6c842450e04412656d6daf730c6f8f767",
  "documentType": "setup",
  "title": "Directus no Setup MNO",
  "setupId": "directus",
  "setupVersion": "7.48.11",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["directus", "headless-cms", "api"],
  "sources": [
    {
      "sourceId": "directus-installer",
      "title": "Instalador Directus",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/directus.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "directus-catalog",
      "title": "Entrada Directus no catálogo",
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
# Directus no Setup MNO

## Quando usar

Use para administrar conteúdo e dados por uma interface, expondo APIs para
aplicações autorizadas. Não ofereça acesso direto ao banco para contornar as
permissões do Directus.

## Arquitetura no Setup MNO

O fluxo cria Redis dedicado antes da aplicação, usa banco lógico no PostgreSQL
base e mantém volumes para uploads, extensões, dados auxiliares e templates.
Apenas a aplicação recebe publicação.

## Pré-requisitos

Exige PostgreSQL, redes, domínio, SMTP quando necessário e capacidade para
aplicação mais dependência. O modelo de permissões deve ser desenhado antes de
integrar clientes.

## Fluxo seguro

O instalador coleta dados, cria banco e Redis em ordem, gera segredos, prepara
volumes e permite stacks editáveis no Portainer ou deploy direto. Credenciais
permanecem no fluxo protegido.

## Validação

Confirme saúde do Redis e da aplicação, login administrativo, persistência de
um item de teste e acesso autorizado à API. Teste negação para um papel sem
permissão.

## Riscos e limites

Permissões amplas podem expor toda a coleção. Extensões executam código e
exigem revisão. Backup deve combinar PostgreSQL, uploads e extensões
compatíveis.

## Diagnóstico

Falha de inicialização pode vir do banco ou Redis. Erro de arquivo aponta para
volume. Resposta negada da API deve ser analisada como permissão antes de
alterar a rota pública.
