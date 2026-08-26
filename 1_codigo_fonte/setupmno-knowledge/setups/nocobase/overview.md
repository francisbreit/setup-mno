---
{
  "schemaVersion": 1,
  "documentId": "setup-nocobase-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b7b383cc8a7f7d1823cf9be375f91d9235b89b7939c3ca864f93187d1ced5768",
  "documentType": "setup",
  "title": "NocoBase no Setup MNO",
  "setupId": "nocobase",
  "setupVersion": "7.34.0",
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
    "nocobase",
    "no-code",
    "workflows",
    "plugins"
  ],
  "sources": [
    {
      "sourceId": "nocobase-installer",
      "title": "Instalador NocoBase",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/nocobase.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "nocobase-production",
      "title": "Deploy de produção oficial do NocoBase",
      "sourceType": "official-documentation",
      "location": "https://docs.nocobase.com/get-started/deployment/production",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "nocobase-tutorial",
      "title": "Tutorial oficial do NocoBase",
      "sourceType": "official-documentation",
      "location": "https://docs.nocobase.com/tutorials/v2/01-getting-started",
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
# NocoBase no Setup MNO

## Quando usar

Use para aplicações internas orientadas a dados, permissões e workflows configuráveis. Não use no-code para ocultar requisitos de segurança, governança ou modelagem de dados.

## Arquitetura no Setup MNO

O instalador cria uma instância NocoBase baseada na imagem oficial e recursos persistentes descritos pelo script. A tag flutuante e o ecossistema de plugins exigem controle de versão.

## Pré-requisitos

O catálogo declara cerca de 512 MB de RAM, uma referência que deve ser reavaliada conforme plugins, workflows e usuários.

Exige domínio HTTPS, banco, storage, política de usuários e inventário de plugins. Planeje origem única para frontend e API, pois a documentação alerta para cookies e arquivos em cenários cross-origin.

## Fluxo seguro

Comece sem plugins de terceiros, aplique menor privilégio e mantenha segredos fora dos campos visíveis. Alterações de esquema e workflow precisam de responsável e rollback.

## Primeiro acesso e integrações

Crie administrador, perfil restrito e uma coleção fictícia. Valide permissões por papel, upload e API antes de conectar dados reais.

## Backup e atualização

Preserve banco, arquivos e lista de plugins. Teste upgrade e migrações em cópia isolada, com versão fixada e restauração comprovada.

## Validação

Confirme autenticação, sessão, CORS, permissões, workflow, persistência, backup e restore. Verifique acesso direto a arquivos por usuários não autorizados.

## Riscos e limites

Plugins executam código e mudanças visuais podem alterar o esquema. Tag flutuante, CORS incorreto e permissões amplas são riscos importantes.

## Diagnóstico

Separe proxy, cookie, CORS, API, banco, plugin, workflow e storage. Reproduza com coleção e usuário fictícios.
