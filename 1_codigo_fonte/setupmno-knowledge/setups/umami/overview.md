---
{
  "schemaVersion": 1,
  "documentId": "setup-umami-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "2e10671f0bac2db4d8d5f66e0a595299530c80b62d5a63c0eadfc2252f63ea33",
  "documentType": "setup",
  "title": "Umami no Setup MNO",
  "setupId": "umami",
  "setupVersion": "7.42.0",
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
    "umami",
    "analytics",
    "privacidade",
    "postgres"
  ],
  "sources": [
    {
      "sourceId": "umami-installer",
      "title": "Instalador Umami",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/umami.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "umami-install",
      "title": "Instalação oficial do Umami",
      "sourceType": "official-documentation",
      "location": "https://docs.umami.is/docs/install",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "umami-docs",
      "title": "Documentação oficial do Umami",
      "sourceType": "official-documentation",
      "location": "https://docs.umami.is/docs",
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
# Umami no Setup MNO

## Quando usar

Use para analytics web auto-hospedado quando finalidade, consentimento, retenção e minimização estiverem definidos. Self-hosting não substitui análise jurídica de tracking.

## Arquitetura no Setup MNO

O instalador usa a imagem Umami com suporte a PostgreSQL e banco previsto pelo Setup. A aplicação guarda sites, eventos, sessões agregadas e usuários administrativos.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM; tráfego, retenção e consultas do PostgreSQL exigem capacidade adicional.

Exige domínio HTTPS, banco, usuário dedicado, segredo de aplicação e política de privacidade. Defina sites autorizados, retenção e exclusão de tráfego interno.

## Fluxo seguro

Troque credenciais iniciais, limite cadastro e colete somente eventos necessários. URLs com identificadores, IPs e dados de visitantes não devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Crie site fictício, valide script de tracking, evento sintético e exclusão. Revise cabeçalhos e consentimento antes de publicar em domínio real.

## Backup e atualização

Preserve banco e configuração, teste restauração e fixe versão. Leia migrações antes de atualizar a imagem com suporte PostgreSQL.

## Validação

Confirme login, coleta sintética, retenção, fuso, exportação, backup e restore. Teste que sites e usuários ficam isolados conforme os papéis.

## Riscos e limites

Analytics pode tratar dados pessoais e criar perfil de navegação. Senha padrão, coleta excessiva e tag flutuante elevam o risco.

## Diagnóstico

Separe script, bloqueador, proxy, aplicação, banco, evento e fuso. Use visitas e URLs sintéticas.
