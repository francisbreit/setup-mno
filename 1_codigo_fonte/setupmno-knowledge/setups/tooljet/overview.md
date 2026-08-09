---
{
  "schemaVersion": 1,
  "documentId": "setup-tooljet-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "f0b7c01704cbcbddb82399ef964fa3ec0d064600a4784a569cd3bd2148420969",
  "documentType": "setup",
  "title": "ToolJet no Setup MNO",
  "setupId": "tooljet",
  "setupVersion": "7.7.41",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "tooljet",
    "low-code",
    "apps-internas",
    "fontes-de-dados"
  ],
  "sources": [
    {
      "sourceId": "tooljet-installer",
      "title": "Instalador ToolJet",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/tooljet.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "tooljet-docker",
      "title": "Deploy oficial do ToolJet com Docker",
      "sourceType": "official-documentation",
      "location": "https://docs.tooljet.ai/docs/setup/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "tooljet-docs",
      "title": "Documentação oficial do ToolJet",
      "sourceType": "official-documentation",
      "location": "https://docs.tooljet.ai/",
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
# ToolJet no Setup MNO

## Quando usar

Use em x86 para criar aplicações internas sobre APIs e fontes de dados. Não use low-code como atalho para conceder acesso amplo a bancos produtivos.

## Arquitetura no Setup MNO

O instalador combina ToolJet, banco previsto pelo fluxo e Redis dedicado. A aplicação armazena definições, usuários e credenciais cifradas das fontes, tornando sua segurança crítica.

## Pré-requisitos

O catálogo declara cerca de 2 GB de RAM em x86; apesar disso, o menu atual chama um alerta de aplicação pesada com 2 GB, divergência que deve ser revisada.

Exige domínio HTTPS, banco, Redis, chaves de criptografia e contas de serviço por fonte. Dimensione workers e memória pelos usuários, queries e automações.

## Fluxo seguro

Use credenciais somente leitura ou escopo mínimo, ambientes separados e revisão de cada query. Não envie schemas, queries, dados ou tokens ao Assistente.

## Primeiro acesso e integrações

Crie administrador e app fictício, conecte uma API de teste e valide papéis. Só depois adicione uma fonte real com usuário dedicado e limite de consulta.

## Backup e atualização

Preserve banco, configuração e chaves de criptografia; sem as chaves, credenciais armazenadas podem ficar inutilizáveis. Fixe versão e teste restore.

## Validação

Confirme x86, login, papéis, Redis dedicado, conexão fictícia, persistência, backup e restauração. Teste que usuário comum não edita fontes.

## Riscos e limites

ToolJet concentra acesso a múltiplos sistemas. Credencial ampla, query arbitrária e chave de criptografia perdida podem causar incidente grave.

## Diagnóstico

Separe proxy, aplicação, banco, Redis, criptografia, datasource e query. Reproduza com API e usuário fictícios.
