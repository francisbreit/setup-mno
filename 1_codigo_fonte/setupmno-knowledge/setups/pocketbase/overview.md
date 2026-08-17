---
{
  "schemaVersion": 1,
  "documentId": "setup-pocketbase-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ef7157b9c4bbeec9d154c82594643989ddf070bca26716bf87cc6c05c5450444",
  "documentType": "setup",
  "title": "PocketBase no Setup MNO",
  "setupId": "pocketbase",
  "setupVersion": "7.19.4",
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
    "pocketbase",
    "backend",
    "sqlite",
    "imagem-nao-oficial"
  ],
  "sources": [
    {
      "sourceId": "pocketbase-installer",
      "title": "Instalador PocketBase",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/pocketbase.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "pocketbase-docs",
      "title": "Documentação oficial do PocketBase",
      "sourceType": "official-documentation",
      "location": "https://pocketbase.io/docs/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "pocketbase-production",
      "title": "Guia oficial para produção do PocketBase",
      "sourceType": "official-documentation",
      "location": "https://pocketbase.io/docs/going-to-production/",
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
# PocketBase no Setup MNO

## Quando usar

Use para protótipos, pequenas aplicações e backends portáteis com SQLite, autenticação e realtime. A documentação oficial não recomenda aplicações críticas antes da versão 1.0 sem disposição para migrações manuais.

## Arquitetura no Setup MNO

O instalador usa uma imagem comunitária, porque o PocketBase não publica imagem Docker oficial. O binário, os dados e as migrações persistem conforme o script; procedência e versão da imagem precisam ser registradas.

## Pré-requisitos

O catálogo declara cerca de 64 MB de RAM; concorrência, realtime e arquivos exigem teste além dessa referência.

Exige domínio HTTPS, storage, política de superusuários e plano de migrações. Avalie limites de SQLite, escrita concorrente e tamanho dos arquivos.

## Fluxo seguro

Crie superusuário forte, restrinja painel administrativo e defina regras de coleção com menor privilégio. Não compartilhe tokens, regras ou dados de usuários com o Assistente.

## Primeiro acesso e integrações

Use coleções e contas fictícias, valide regras por usuário e teste assinatura realtime. SDKs devem apontar ao domínio HTTPS e nunca incorporar credencial administrativa.

## Backup e atualização

Preserve dados, migrações e hooks; copie a base com método consistente e teste restore. Leia o changelog a cada atualização e fixe a versão.

## Validação

Confirme autenticação, regras de coleção, persistência, upload, realtime, backup e restauração. Registre o binário efetivo contido na imagem comunitária.

## Riscos e limites

Pré-1.0, SQLite e imagem não oficial elevam risco. Não trate facilidade de deploy como garantia de escala, compatibilidade ou supply chain.

## Diagnóstico

Separe proxy, aplicação, regras, migração, SQLite e arquivos. Reproduza com coleção e usuário fictícios.
