---
{
  "schemaVersion": 1,
  "documentId": "setup-karakeep-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "37cebe37dd850b933883f09b8988f65aebafeefe0b128eb6038497d66abb753d",
  "documentType": "setup",
  "title": "Karakeep no Setup MNO",
  "setupId": "karakeep",
  "setupVersion": "7.48.29",
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
    "karakeep",
    "bookmarks",
    "meilisearch",
    "chrome"
  ],
  "sources": [
    {
      "sourceId": "karakeep-installer",
      "title": "Instalador Karakeep",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/karakeep.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "karakeep-install",
      "title": "Instalação Docker oficial Karakeep",
      "sourceType": "official-documentation",
      "location": "https://docs.karakeep.app/installation/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "karakeep-minimal",
      "title": "Instalação mínima Karakeep",
      "sourceType": "official-documentation",
      "location": "https://docs.karakeep.app/installation/minimal-install/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "karakeep-cli",
      "title": "CLI oficial Karakeep",
      "sourceType": "official-documentation",
      "location": "https://docs.karakeep.app/integrations/command-line/",
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
# Karakeep no Setup MNO

## Quando usar

Use para salvar, indexar e pesquisar links e conteúdo, com crawling e classificação opcional. Não use para coletar conteúdo sem autorização nem prometa recursos de IA sem provedor configurado.

## Arquitetura no Setup MNO

O instalador usa `Karakeep na tag release`, Chrome 124 e Meilisearch 1.41, volumes e segredo NextAuth. O conjunto reserva aproximadamente 1,25 GB embora o catálogo indique 1 GB.

## Pré-requisitos

Exige domínio HTTPS, storage, segredo forte, Chrome e Meilisearch; OpenAI/Ollama é opcional. Planeje volume de páginas, anexos e limites de crawling.

## Fluxo seguro

Gere `NEXTAUTH_SECRET`, restrinja cadastro e trate URLs privadas, cookies e chaves de IA como sensíveis. Nunca exponha Chrome ou Meilisearch publicamente.

## Primeiro acesso e integrações

Salve página pública fictícia, valide captura, busca, tag e reprocessamento. Teste falha do alvo e, se usar IA, somente com conteúdo não sensível.

## Backup e atualização

Preserve volume principal e índice/configuração; confirme no guia o que pode ser reconstruído. Antes de atualizar as três imagens, registre versões e teste restauração coordenada.

## Validação

Confirme login, captura, worker, Chrome, Meilisearch, busca, persistência e limites. Verifique que dependências estão apenas na rede interna.

## Riscos e limites

Crawling pode acessar destinos internos ou proibidos; IA pode exfiltrar conteúdo. Versões múltiplas e RAM catalogada abaixo do conjunto requerem medição.

## Diagnóstico

Separe app, worker, Chrome, Meilisearch, DNS e provedor IA. Remova URLs, cookies e conteúdo privado.
