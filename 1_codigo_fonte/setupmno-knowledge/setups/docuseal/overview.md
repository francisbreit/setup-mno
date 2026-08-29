---
{
  "schemaVersion": 1,
  "documentId": "setup-docuseal-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "733fbc31c951c4b5f85bae49f97caddee628875894c9b1eadbc1a920b8729d56",
  "documentType": "setup",
  "title": "DocuSeal no Setup MNO",
  "setupId": "docuseal",
  "setupVersion": "7.40.0",
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
    "docuseal",
    "assinatura",
    "documentos",
    "workflow"
  ],
  "sources": [
    {
      "sourceId": "docuseal-installer",
      "title": "Instalador DocuSeal",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/docuseal.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "docuseal-install",
      "title": "Instalação oficial DocuSeal",
      "sourceType": "official-documentation",
      "location": "https://www.docuseal.com/install",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "docuseal-env",
      "title": "Configuração por variáveis DocuSeal",
      "sourceType": "official-documentation",
      "location": "https://www.docuseal.com/docs/configuring-docuseal-via-environment-variables",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "docuseal-update",
      "title": "Atualização oficial DocuSeal",
      "sourceType": "official-documentation",
      "location": "https://www.docuseal.com/docs/update-docuseal-to-the-latest-version",
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
# DocuSeal no Setup MNO

## Quando usar

Use para preparar documentos e coletar assinaturas eletrônicas após avaliação jurídica e de identidade. Não garanta validade regulatória ou força probatória sem análise do caso.

## Arquitetura no Setup MNO

O instalador usa `DocuSeal na tag latest`, PostgreSQL compartilhado, volume persistente e SMTP. `SECRET_KEY_BASE`, senha do banco e SMTP entram no YAML do stack.

## Pré-requisitos

Exige domínio HTTPS, banco, volume, segredo persistente, SMTP, política de retenção e responsáveis. Integrações e requisitos legais variam por jurisdição.

## Fluxo seguro

Proteja segredos fora de telas e logs, restrinja contas administrativas e limite cadastro. Use dados fictícios até concluir avaliação jurídica, backup e restauração.

## Primeiro acesso e integrações

Crie administrador, modelo e submissão simulada; teste email, assinatura, download, webhook e permissões. Não use documentos pessoais na homologação.

## Backup e atualização

Preserve PostgreSQL, arquivos persistentes, configuração e segredos. Antes da atualização, faça backup e registre a tag; teste restore em ambiente isolado e volte banco e imagem juntos.

## Validação

Confirme login, template, campos, fluxo, evidências, email, webhook, persistência e restauração. Inspecione logs sanitizados.

## Riscos e limites

Assinaturas envolvem dados pessoais e requisitos legais. `latest` e segredos no YAML diminuem reprodutibilidade e ampliam exposição; backup apenas do banco pode ser insuficiente.

## Diagnóstico

Separe aplicação, banco, arquivos, SMTP, webhook e proxy. Nunca envie documentos, assinaturas, IPs ou evidências reais ao Assistente.
