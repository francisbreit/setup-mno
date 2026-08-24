---
{
  "schemaVersion": 1,
  "documentId": "setup-strapi-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "86d46f4e72df98297526dfcc3990735021330b1ae31b69d564224f5965883f85",
  "documentType": "setup",
  "title": "Strapi no Setup MNO",
  "setupId": "strapi",
  "setupVersion": "7.33.3",
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
    "strapi",
    "cms",
    "api",
    "imagem-customizada"
  ],
  "sources": [
    {
      "sourceId": "strapi-installer",
      "title": "Instalador Strapi",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/strap.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "strapi-docs",
      "title": "Documentação oficial do Strapi",
      "sourceType": "official-documentation",
      "location": "https://docs.strapi.io/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "strapi-selfhost",
      "title": "Orientação oficial para self-host do Strapi",
      "sourceType": "official-documentation",
      "location": "https://strapi.io/hosting",
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
# Strapi no Setup MNO

## Quando usar

Use como CMS headless quando o conteúdo precisa de API, painel editorial e modelo customizável. Não escolha apenas por gerar API rapidamente; modele papéis, publicação e evolução de schema.

## Arquitetura no Setup MNO

O instalador constrói uma imagem Strapi customizada no próprio fluxo, pois o projeto não fornece uma imagem oficial genérica para qualquer aplicação. A imagem e o banco formam um artefato específico dessa instância.

## Pré-requisitos

O catálogo declara cerca de 1,5 GB de RAM; build da imagem, painel, API, banco e plugins precisam ser medidos em fases distintas.

Exige domínio HTTPS, banco, storage de uploads, chaves de aplicação e plano de build. Defina tipos de conteúdo, papéis e ambiente antes de publicar.

## Fluxo seguro

Gere segredos fortes, restrinja o painel administrativo e aplique menor privilégio nas APIs. Plugins e providers devem ser avaliados como código de terceiros.

## Primeiro acesso e integrações

Crie administrador, um tipo de conteúdo fictício e token restrito. Confirme draft e publicação, CORS e upload antes de conectar frontend real.

## Backup e atualização

Preserve banco, uploads, código/configuração do projeto e plugins. Recompile a imagem com versão fixada, execute migrações em cópia e teste restore.

## Validação

Confirme painel, papéis, token restrito, API pública/privada, upload, persistência e restauração. Verifique que campos privados não aparecem na resposta.

## Riscos e limites

Build dinâmico, plugins e mudanças de schema aumentam risco. Backup só do banco não recupera uploads e código da aplicação.

## Diagnóstico

Separe build, proxy, admin, API, token, banco, plugin e storage. Reproduza com coleção e arquivo fictícios.
