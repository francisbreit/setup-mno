---
{
  "schemaVersion": 1,
  "documentId": "setup-shlink-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "556736efad8a380f154818c88d3ca0d278669bae61100da03426b8f3e2fc2eea",
  "documentType": "setup",
  "title": "Shlink no Setup MNO",
  "setupId": "shlink",
  "setupVersion": "7.24.1",
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
    "shlink",
    "url",
    "links",
    "analytics"
  ],
  "sources": [
    {
      "sourceId": "shlink-installer",
      "title": "Instalador Shlink",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/shlink.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "shlink-docker",
      "title": "Instalação oficial do Shlink com Docker",
      "sourceType": "official-documentation",
      "location": "https://shlink.io/documentation/install-docker-image/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "shlink-docs",
      "title": "Documentação oficial do Shlink",
      "sourceType": "official-documentation",
      "location": "https://shlink.io/documentation/",
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
# Shlink no Setup MNO

## Quando usar

Use para encurtar URLs próprias com API e estatísticas sob seu controle. Não use para ocultar destino, contornar políticas ou coletar visitas sem base legal.

## Arquitetura no Setup MNO

O instalador cria o backend Shlink e o cliente web conforme o script. Banco, domínio curto, HTTPS e chave de API precisam permanecer coerentes entre os componentes.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM; banco, estatísticas e volume de redirecionamentos devem ser medidos separadamente.

Exige domínio curto, HTTPS, banco ou volume adequado, política de retenção e, quando usado, licença GeoLite. Defina prevenção de abuso e limites de criação.

## Fluxo seguro

Proteja a API, use chave dedicada no cliente e não publique endpoints administrativos sem autenticação. Não envie URLs privadas, chaves ou dados de visita ao Assistente.

## Primeiro acesso e integrações

Gere ou confirme a chave de API, conecte o cliente e crie um link fictício. Valide redirecionamento, expiração e desativação antes de uso real.

## Backup e atualização

Preserve banco, configuração e chaves com cópia cifrada. Fixe versão, revise migrações e teste rollback do backend e cliente como par.

## Validação

Confirme HTTPS, domínio canônico, cliente, API, criação, expiração, estatística e restauração. Teste proteção contra criação não autorizada.

## Riscos e limites

Links podem facilitar phishing e estatísticas podem conter dados pessoais. Domínio, API e cliente incompatíveis causam falhas silenciosas.

## Diagnóstico

Separe DNS, proxy, backend, cliente, banco, API key e redirecionamento. Use domínio e link de teste sem identificadores.
